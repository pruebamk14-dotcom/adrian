--!strict
-- Combate autoritativo en el servidor:
--  * munición, cadencia y recarga validadas en servidor
--  * la bala se simula en tiempo real con caída (misma balística que el cliente)
--  * lag compensation: los rivales se rebobinan al instante que vio el tirador
--  * daño por zona (cabeza/torso/extremidades) con caída de daño por distancia

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Ballistics = require(Shared.Ballistics)
local GunBuilder = require(Shared.GunBuilder)
local Signal = require(Shared.Signal)
local Net = require(Shared.Net)

local HitboxHistory = require(script.Parent.HitboxHistory)
local DataService = require(script.Parent.DataService)

export type KillInfo = { Headshot: boolean, Distance: number, WeaponId: string }

type State = {
	WeaponId: string,
	SkinId: string,
	Mag: number,
	Reloading: boolean,
	LastFire: number,
	CanFire: boolean,
	ReloadToken: number,
}

type Bullet = {
	Shooter: Player,
	Origin: Vector3,
	Velocity: Vector3,
	Gravity: number,
	ShotTime: number,
	T: number,
	MaxT: number,
	Weapon: Weapons.Weapon,
	Targets: { Player },
	Params: RaycastParams,
}

local CombatService = {}
CombatService.Killed = Signal.new() -- (killer, victim, KillInfo)

-- DuelService reemplaza esto para decir a quién puede dañar cada jugador.
CombatService.TargetResolver = function(_player: Player): { Player }
	return {}
end

local states: { [Player]: State } = {}
local bullets: { Bullet } = {}

local function isFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or c == math.huge or c == -math.huge then
			return false
		end
	end
	return true
end

local function pushAmmo(player: Player)
	local s = states[player]
	if s then
		Net.Event("AmmoUpdate"):FireClient(player, s.Mag, s.Reloading, s.WeaponId)
	end
end

local function poseArms(character: Model, raised: boolean)
	for _, info in { { "RightUpperArm", "RightShoulder", 15 }, { "LeftUpperArm", "LeftShoulder", -40 } } do
		local arm = character:FindFirstChild(info[1])
		local motor = arm and arm:FindFirstChild(info[2]) :: Motor6D?
		if motor then
			local original = motor:GetAttribute("OriginalC0") :: CFrame?
			if not original then
				original = motor.C0
				motor:SetAttribute("OriginalC0", original)
			end
			local o = original :: CFrame
			motor.C0 = if raised then o * CFrame.fromEulerAnglesYXZ(math.rad(88), math.rad(info[3]), 0) else o
		end
	end
end

local function attachGun(player: Player)
	local character = player.Character
	local s = states[player]
	if not character or not s then
		return
	end
	local old = character:FindFirstChild("Rifle")
	if old then
		old:Destroy()
	end
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	local gun = GunBuilder.Build(s.WeaponId, s.SkinId)
	gun:PivotTo(torso.CFrame * CFrame.new(0.55, 0.35, -1.6))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = gun.PrimaryPart
	weld.Parent = gun
	gun.Parent = character
	poseArms(character, true)
end

function CombatService.Arm(player: Player)
	local data = DataService.Get(player)
	local weaponId = data and data.Equipped.Weapon or Weapons.Default
	local skinId = data and data.Equipped.Skin or "Default"
	local w = Weapons.Get(weaponId)
	local prev = states[player]
	states[player] = {
		WeaponId = w.Id,
		SkinId = skinId,
		Mag = w.MagSize,
		Reloading = false,
		LastFire = 0,
		CanFire = false,
		ReloadToken = if prev then prev.ReloadToken + 1 else 0,
	}
	attachGun(player)
	HitboxHistory.Track(player)
	pushAmmo(player)
end

function CombatService.Disarm(player: Player)
	states[player] = nil
	HitboxHistory.Untrack(player)
	local character = player.Character
	if character then
		local gun = character:FindFirstChild("Rifle")
		if gun then
			gun:Destroy()
		end
		character:SetAttribute("Scoped", false)
		poseArms(character, false)
	end
	Net.Event("AmmoUpdate"):FireClient(player, -1, false, "")
end

function CombatService.SetCanFire(player: Player, canFire: boolean)
	local s = states[player]
	if s then
		s.CanFire = canFire
	end
end

-- Recarga instantánea entre rondas + reponer arma al nuevo personaje
function CombatService.ResetForRound(player: Player)
	local s = states[player]
	if not s then
		return
	end
	local w = Weapons.Get(s.WeaponId)
	s.Mag = w.MagSize
	s.Reloading = false
	s.ReloadToken += 1
	s.LastFire = 0
	attachGun(player)
	HitboxHistory.Clear(player)
	pushAmmo(player)
end

local function applyHit(bullet: Bullet, victim: Player, zone: string, position: Vector3)
	local shooter = bullet.Shooter
	local w = bullet.Weapon
	local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local distance = (position - bullet.Origin).Magnitude
	local damage = (w.Damage :: any)[zone] :: number
	if zone ~= "Head" and distance > w.FalloffStart then
		local alpha = math.clamp((distance - w.FalloffStart) / w.FalloffStart, 0, 1)
		damage *= 1 - (1 - w.FalloffMinMultiplier) * alpha
	end
	damage = math.floor(damage + 0.5)

	local killed = humanoid.Health - damage <= 0
	humanoid.Health = math.max(humanoid.Health - damage, 0)

	local data = DataService.Get(shooter)
	if data then
		data.ShotsHit += 1
	end

	local studs = math.floor(distance)
	Net.Event("HitConfirm"):FireClient(shooter, zone, damage, killed, studs)
	Net.Event("Damaged"):FireClient(victim, bullet.Origin, damage, humanoid.Health)

	if killed then
		if data then
			data.Kills += 1
			if zone == "Head" then
				data.Headshots += 1
			end
			data.LongestShot = math.max(data.LongestShot, studs)
		end
		local vdata = DataService.Get(victim)
		if vdata then
			vdata.Deaths += 1
		end
		CombatService.Killed:Fire(shooter, victim, { Headshot = zone == "Head", Distance = studs, WeaponId = w.Id })
	end
end

-- Avanza una bala hasta el tiempo de vuelo objetivo. Devuelve true si terminó.
local function stepBullet(b: Bullet, targetT: number): boolean
	local step = GameConfig.BallisticStep
	local now = workspace:GetServerTimeNow()
	while b.T < targetT do
		local t0 = b.T
		local t1 = math.min(t0 + step, b.MaxT)
		local from = Ballistics.PositionAt(b.Origin, b.Velocity, b.Gravity, t0)
		local to = Ballistics.PositionAt(b.Origin, b.Velocity, b.Gravity, t1)
		local delta = to - from
		local len = delta.Magnitude

		local worldHit = workspace:Raycast(from, delta, b.Params)
		local worldFrac = if worldHit then (worldHit.Position - from).Magnitude / math.max(len, 1e-6) else math.huge

		-- Instante que el tirador veía para esta parte del vuelo
		local sampleT = math.min(b.ShotTime + t1 - GameConfig.ViewInterpolationDelay, now)
		local bestFrac, bestVictim, bestZone = math.huge, nil :: Player?, ""
		for _, target in b.Targets do
			local boxes = HitboxHistory.Sample(target, sampleT)
			if boxes then
				for _, box in boxes do
					local frac = Ballistics.SegmentOBB(from, to, box.CFrame, box.Size)
					if frac and (frac < bestFrac - 1e-4 or (math.abs(frac - bestFrac) <= 1e-4 and box.Zone == "Head")) then
						bestFrac, bestVictim, bestZone = frac, target, box.Zone
					end
				end
			end
		end

		if bestVictim and bestFrac <= worldFrac then
			applyHit(b, bestVictim, bestZone, from + delta * bestFrac)
			return true
		end
		if worldHit then
			return true
		end
		b.T = t1
		if b.T >= b.MaxT then
			return true
		end
	end
	return false
end

local function onFire(player: Player, origin: any, direction: any, shotTime: any)
	local s = states[player]
	if not s or not s.CanFire or s.Reloading or s.Mag <= 0 then
		return
	end
	if not isFiniteVector(origin) or not isFiniteVector(direction) or type(shotTime) ~= "number" or shotTime ~= shotTime then
		return
	end
	if direction.Magnitude < 0.5 then
		return
	end
	local w = Weapons.Get(s.WeaponId)
	local clock = os.clock()
	if clock - s.LastFire < w.FireCooldown * 0.85 then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (head.Position - origin).Magnitude > GameConfig.MaxOriginDistance then
		return
	end

	s.LastFire = clock
	s.Mag -= 1
	local data = DataService.Get(player)
	if data then
		data.ShotsFired += 1
	end
	pushAmmo(player)

	local serverNow = workspace:GetServerTimeNow()
	shotTime = math.clamp(shotTime, serverNow - GameConfig.MaxRewindTime, serverNow)

	local targets = CombatService.TargetResolver(player)

	-- Efectos para todos los que puedan verlo (rivales + espectadores del duelo)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.Event("ShotFx"):FireClient(other, player, origin, direction.Unit, s.WeaponId, s.SkinId)
		end
	end

	local exclude = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true

	local bullet: Bullet = {
		Shooter = player,
		Origin = origin,
		Velocity = direction.Unit * w.MuzzleVelocity,
		Gravity = w.BulletGravity,
		ShotTime = shotTime,
		T = 0,
		MaxT = GameConfig.MaxBulletDistance / w.MuzzleVelocity,
		Weapon = w,
		Targets = targets,
		Params = params,
	}
	-- Ponerse al día con el tiempo que la bala ya lleva volando (latencia)
	if not stepBullet(bullet, serverNow - shotTime) then
		table.insert(bullets, bullet)
	end
end

local function onReload(player: Player)
	local s = states[player]
	if not s or s.Reloading then
		return
	end
	local w = Weapons.Get(s.WeaponId)
	if s.Mag >= w.MagSize then
		return
	end
	s.Reloading = true
	s.ReloadToken += 1
	local token = s.ReloadToken
	pushAmmo(player)
	task.delay(w.ReloadTime, function()
		local cur = states[player]
		if cur == s and s.ReloadToken == token then
			s.Mag = w.MagSize
			s.Reloading = false
			pushAmmo(player)
		end
	end)
end

function CombatService.Start()
	Net.Event("Fire").OnServerEvent:Connect(onFire)
	Net.Event("Reload").OnServerEvent:Connect(onReload)
	Net.Event("ScopeState").OnServerEvent:Connect(function(player, scoped)
		local character = player.Character
		if character and states[player] then
			character:SetAttribute("Scoped", scoped == true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for i = #bullets, 1, -1 do
			local b = bullets[i]
			if not b.Shooter.Parent or stepBullet(b, now - b.ShotTime) then
				table.remove(bullets, i)
			end
		end
	end)
end

function CombatService.GetState(player: Player)
	return states[player]
end

return CombatService
