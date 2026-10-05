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

-- Un "combatiente" es un Player o un bot (tabla con Character, DisplayName, IsBot)
type Combatant = any

type State = {
	WeaponId: string,
	SkinId: string,
	Slot: number, -- 1 rifle, 2 cuchillo
	LastMelee: number,
	RifleTool: Tool?,
	KnifeTool: Tool?,
	Mag: number,
	Reloading: boolean,
	LastFire: number,
	CanFire: boolean,
	ReloadToken: number,
}

type Bullet = {
	Shooter: Combatant,
	Origin: Vector3,
	Velocity: Vector3,
	Gravity: number,
	ShotTime: number,
	T: number,
	MaxT: number,
	Weapon: Weapons.Weapon,
	Targets: { Combatant },
	Params: RaycastParams,
	Closest: number,
}

local CombatService = {}
CombatService.Killed = Signal.new() -- (killer, victim, KillInfo); pueden ser bots

-- DuelService reemplaza esto para decir a quién puede dañar cada jugador.
CombatService.TargetResolver = function(_c: Combatant): { Combatant }
	return {}
end

local states: { [Combatant]: State } = {}

local function isPlayer(c: Combatant): boolean
	return typeof(c) == "Instance" and c:IsA("Player")
end
CombatService.IsPlayer = isPlayer
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

-- El estado del arma se publica como atributos del Player: Roblox los
-- replica siempre y el cliente puede leerlos en cualquier momento (no se
-- pierden aunque el script del cliente arranque tarde).
local function pushAmmo(player: Combatant)
	local s = states[player]
	if s and isPlayer(player) then
		player:SetAttribute("SD_Weapon", s.WeaponId)
		player:SetAttribute("SD_Mag", s.Mag)
		player:SetAttribute("SD_Reloading", s.Reloading)
		player:SetAttribute("SD_Slot", s.Slot)
		-- Vía redundante: evento explícito por si los atributos tardan
		Net.Event("Armed"):FireClient(player, s.WeaponId, s.Mag, s.Reloading, s.Slot)
	end
end

-- Brazo izquierdo hacia delante sujetando el guardamanos (el derecho lo
-- coloca la animación de herramienta)
local function poseArms(character: Model, raised: boolean)
	local arm = character:FindFirstChild("LeftUpperArm")
	local motor = arm and arm:FindFirstChild("LeftShoulder") :: Motor6D?
	if motor then
		local original = motor:GetAttribute("OriginalC0") :: CFrame?
		if not original then
			original = motor.C0
			motor:SetAttribute("OriginalC0", original)
		end
		local o = original :: CFrame
		motor.C0 = if raised then o * CFrame.fromEulerAnglesYXZ(math.rad(80), math.rad(-38), 0) else o
	end
end

local function attachGun(player: Combatant)
	local character = player.Character
	local s = states[player]
	if not character or not s then
		return
	end
	local old = character:FindFirstChild("Rifle")
	if old then
		old:Destroy()
	end
	if isPlayer(player) then
		local backpack = player:FindFirstChildOfClass("Backpack")
		local inPack = backpack and backpack:FindFirstChild("Rifle")
		if inPack then
			inPack:Destroy()
		end
	end
	local old2 = character:FindFirstChild("Knife")
	if old2 then
		old2:Destroy()
	end
	local tool = GunBuilder.BuildTool(s.WeaponId, s.SkinId)
	local knife = GunBuilder.BuildKnifeTool(s.SkinId)
	s.RifleTool = tool
	s.KnifeTool = knife
	s.Slot = 1
	tool.Parent = character -- al ponerlo en el personaje se equipa en la mano
	if isPlayer(player) then
		local backpack = player:FindFirstChildOfClass("Backpack")
		knife.Parent = backpack or character
	end
	-- Si el jugador intenta guardar el arma activa (retroceso), se vuelve a equipar
	local function keepEquipped(t: Tool, slot: number)
		t.AncestryChanged:Connect(function(_, parent)
			if parent and parent:IsA("Backpack") and states[player] == s and s.Slot == slot and character.Parent then
				task.defer(function()
					if t.Parent and t.Parent:IsA("Backpack") and s.Slot == slot then
						t.Parent = character
					end
				end)
			end
		end)
	end
	keepEquipped(tool, 1)
	keepEquipped(knife, 2)
	poseArms(character, true)
end

-- Cambiar de ranura: 1 rifle, 2 cuchillo
function CombatService.SetSlot(player: Combatant, slot: number)
	local s = states[player]
	local character = player.Character
	if not s or not character or not s.RifleTool or not s.KnifeTool then
		return
	end
	slot = if slot == 2 then 2 else 1
	if s.Slot == slot then
		return
	end
	s.Slot = slot
	local backpack = if isPlayer(player) then player:FindFirstChildOfClass("Backpack") else nil
	local active = if slot == 1 then s.RifleTool else s.KnifeTool
	local inactive = if slot == 1 then s.KnifeTool else s.RifleTool
	if inactive and inactive.Parent == character then
		inactive.Parent = backpack
	end
	if active and active.Parent ~= character then
		active.Parent = character
	end
	character:SetAttribute("Scoped", false)
	character:SetAttribute("Slot", slot)
	pushAmmo(player)
end

function CombatService.Arm(player: Combatant, weaponOverride: string?, skinOverride: string?)
	local data = if isPlayer(player) then DataService.Get(player) else nil
	local weaponId = weaponOverride or (data and data.Equipped.Weapon) or Weapons.Default
	local skinId = skinOverride or (data and data.Equipped.Skin) or "Default"
	local w = Weapons.Get(weaponId)
	local prev = states[player]
	states[player] = {
		WeaponId = w.Id,
		SkinId = skinId,
		Slot = 1,
		LastMelee = 0,
		RifleTool = nil,
		KnifeTool = nil,
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

function CombatService.Disarm(player: Combatant)
	local s = states[player]
	states[player] = nil
	HitboxHistory.Untrack(player)
	if s then
		for _, t in { s.RifleTool, s.KnifeTool } do
			if t then
				t:Destroy()
			end
		end
	end
	local character = player.Character
	if character then
		for _, name in { "Rifle", "Knife" } do
			local t = character:FindFirstChild(name)
			if t then
				t:Destroy()
			end
		end
		character:SetAttribute("Scoped", false)
		poseArms(character, false)
	end
	if isPlayer(player) then
		player:SetAttribute("SD_Weapon", "")
		player:SetAttribute("SD_Mag", 0)
		player:SetAttribute("SD_Reloading", false)
		player:SetAttribute("SD_Slot", 1)
		Net.Event("Armed"):FireClient(player, "", 0, false, 1)
	end
end

function CombatService.SetCanFire(player: Combatant, canFire: boolean)
	local s = states[player]
	if s then
		s.CanFire = canFire
	end
end

-- Cambiar de arma/skin en mitad de un duelo: reconstruir las herramientas
-- con lo equipado, sin tocar el permiso de disparo
function CombatService.Rearm(player: Combatant)
	local s = states[player]
	if not s or not isPlayer(player) then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local w = Weapons.Get(data.Equipped.Weapon)
	s.WeaponId = w.Id
	s.SkinId = data.Equipped.Skin or "Default"
	s.Mag = w.MagSize
	s.Reloading = false
	s.ReloadToken += 1
	s.Slot = 1
	attachGun(player)
	pushAmmo(player)
end

-- Recarga instantánea entre rondas + reponer arma al nuevo personaje
function CombatService.ResetForRound(player: Combatant)
	local s = states[player]
	if not s then
		return
	end
	local w = Weapons.Get(s.WeaponId)
	s.Mag = w.MagSize
	s.Reloading = false
	s.ReloadToken += 1
	s.LastFire = 0
	s.Slot = 1
	attachGun(player)
	HitboxHistory.Clear(player)
	pushAmmo(player)
end

local function applyHit(bullet: Bullet, victim: Combatant, zone: string, position: Vector3)
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

	local data = if isPlayer(shooter) then DataService.Get(shooter) else nil
	if data then
		data.ShotsHit += 1
	end

	local studs = math.floor(distance)
	if isPlayer(shooter) then
		Net.Event("HitConfirm"):FireClient(shooter, zone, damage, killed, studs)
	end
	if isPlayer(victim) then
		Net.Event("Damaged"):FireClient(victim, bullet.Origin, damage, humanoid.Health)
	end

	if killed then
		if data then
			data.Kills += 1
			if zone == "Head" then
				data.Headshots += 1
			end
			data.LongestShot = math.max(data.LongestShot, studs)
		end
		local vdata = if isPlayer(victim) then DataService.Get(victim) else nil
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
		local bestFrac, bestVictim, bestZone = math.huge, nil :: Combatant?, ""
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
			if isPlayer(b.Shooter) then
				Net.Event("ShotResult"):FireClient(b.Shooter, string.format("IMPACTO %s a %d studs", bestZone, math.floor((from + delta * bestFrac - b.Origin).Magnitude)))
			end
			return true
		end
		-- Distancia mínima al rival para el diagnóstico
		for _, target in b.Targets do
			local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - to).Magnitude
				if d < b.Closest then
					b.Closest = d
				end
			end
		end
		if worldHit then
			if isPlayer(b.Shooter) then
				Net.Event("ShotResult"):FireClient(b.Shooter, string.format("fallo: chocó con %s (pasó a %.1f studs del rival)", worldHit.Instance.Name, b.Closest))
			end
			return true
		end
		b.T = t1
		if b.T >= b.MaxT then
			if isPlayer(b.Shooter) then
				Net.Event("ShotResult"):FireClient(b.Shooter, string.format("fallo: pasó a %.1f studs del rival", b.Closest))
			end
			return true
		end
	end
	return false
end

local function fireShot(player: Combatant, origin: any, direction: any, shotTime: any)
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
	local data = if isPlayer(player) then DataService.Get(player) else nil
	if data then
		data.ShotsFired += 1
	end
	pushAmmo(player)

	local serverNow = workspace:GetServerTimeNow()
	shotTime = math.clamp(shotTime, serverNow - GameConfig.MaxRewindTime, serverNow)

	local targets = CombatService.TargetResolver(player)

	-- Efectos para todos los que puedan verlo (el cliente descarta lo lejano)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.Event("ShotFx"):FireClient(other, character, origin, direction.Unit, s.WeaponId, s.SkinId)
		end
	end

	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for c in states do
		if not isPlayer(c) and c.Character then
			table.insert(exclude, c.Character)
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
		Closest = math.huge,
	}
	-- Ponerse al día con el tiempo que la bala ya lleva volando (latencia)
	if not stepBullet(bullet, serverNow - shotTime) then
		table.insert(bullets, bullet)
	end
end

local function onFire(player: Player, origin: any, direction: any, shotTime: any)
	local s = states[player]
	if s and s.Slot ~= 1 then
		return
	end
	fireShot(player, origin, direction, shotTime)
end

-- Cuchillada: el servidor comprueba distancia y orientación contra las
-- hitboxes del rival (rebobinadas igual que las balas)
local function onMelee(player: Player)
	local s = states[player]
	if not s or not s.CanFire or s.Slot ~= 2 then
		return
	end
	local m = Weapons.Melee
	local clock = os.clock()
	if clock - s.LastMelee < m.Cooldown * 0.9 then
		return
	end
	s.LastMelee = clock
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid or humanoid.Health <= 0 then
		return
	end
	local look = head.CFrame.LookVector
	local now = workspace:GetServerTimeNow()
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.Event("ShotFx"):FireClient(other, character, head.Position, look, "Knife", s.SkinId)
		end
	end
	local bestDist, bestVictim, bestZone = math.huge, nil :: Combatant?, ""
	for _, target in CombatService.TargetResolver(player) do
		local boxes = HitboxHistory.Sample(target, now - GameConfig.ViewInterpolationDelay)
		if boxes then
			for _, box in boxes do
				local to = box.CFrame.Position - head.Position
				local d = to.Magnitude
				if d <= m.Range + math.max(box.Size.X, box.Size.Z) * 0.5 and (d < 1.5 or to.Unit:Dot(look) > 0.35) and d < bestDist then
					bestDist, bestVictim, bestZone = d, target, box.Zone
				end
			end
		end
	end
	if bestVictim then
		local vh = bestVictim.Character and bestVictim.Character:FindFirstChildOfClass("Humanoid")
		if vh and vh.Health > 0 then
			local killed = vh.Health - m.Damage <= 0
			vh.Health = math.max(0, vh.Health - m.Damage)
			local data = DataService.Get(player)
			if data then
				data.ShotsFired += 1
				data.ShotsHit += 1
			end
			Net.Event("HitConfirm"):FireClient(player, bestZone, m.Damage, killed, math.floor(bestDist))
			if isPlayer(bestVictim) then
				Net.Event("Damaged"):FireClient(bestVictim, head.Position, m.Damage, vh.Health)
			end
			if killed then
				if data then
					data.Kills += 1
				end
				local vdata = if isPlayer(bestVictim) then DataService.Get(bestVictim) else nil
				if vdata then
					vdata.Deaths += 1
				end
				CombatService.Killed:Fire(player, bestVictim, { Headshot = false, Distance = math.floor(bestDist), WeaponId = "Knife" })
			end
		end
	end
end

-- Disparo de un bot: mismas reglas (munición, cadencia, origen) que un jugador
function CombatService.BotFire(bot: Combatant, origin: Vector3, direction: Vector3)
	fireShot(bot, origin, direction, workspace:GetServerTimeNow())
end

function CombatService.SetScoped(c: Combatant, scoped: boolean)
	if c.Character and states[c] then
		c.Character:SetAttribute("Scoped", scoped)
	end
end

local function onReload(player: Combatant)
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
	-- Vía 4 de armado: el cliente pregunta su estado cuando empieza la ronda
	Net.Function("GetArmState").OnServerInvoke = function(player)
		local s = states[player]
		if not s then
			return { Armed = false }
		end
		return { Armed = true, WeaponId = s.WeaponId, Mag = s.Mag, Reloading = s.Reloading, Slot = s.Slot, CanFire = s.CanFire }
	end
	Net.Event("Melee").OnServerEvent:Connect(onMelee)
	Net.Event("SetSlot").OnServerEvent:Connect(function(player, slot)
		if type(slot) == "number" then
			CombatService.SetSlot(player, slot)
		end
	end)
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
			local gone = if isPlayer(b.Shooter) then b.Shooter.Parent == nil else not b.Shooter.Active
			if gone or stepBullet(b, now - b.ShotTime) then
				table.remove(bullets, i)
			end
		end
	end)
end

CombatService.Reload = onReload

function CombatService.GetState(player: Combatant)
	return states[player]
end

return CombatService
