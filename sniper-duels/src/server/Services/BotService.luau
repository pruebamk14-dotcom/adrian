--!strict
-- Rival controlado por IA para jugar solo. Usa EXACTAMENTE el mismo sistema
-- de combate que un jugador (munición, cadencia, balística, hitboxes), así
-- que sirve para practicar de verdad.
--
-- Comportamiento:
--  * Se mueve entre posiciones de su mitad de la arena y se asoma.
--  * Detecta al jugador con línea de visión real (raycast).
--  * Tiempo de reacción + error de puntería que se reduce mientras te sigue.
--  * Adelanta el disparo según tu velocidad y compensa la caída de la bala.
--  * Al apuntar se le ve el destello de la mira (puedes reaccionar).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Ballistics = require(Shared.Ballistics)

local CombatService = require(script.Parent.CombatService)
local DuelService = require(script.Parent.DuelService)
local Props = require(script.Parent.Parent.World.Props)

export type Difficulty = {
	Name: string,
	Shoots: boolean,
	Reaction: number, -- s desde que te ve hasta que empieza a apuntar
	AimTime: number, -- s apuntando antes de disparar
	Error: number, -- grados de error inicial
	FocusError: number, -- grados de error tras seguirte un rato
	HeadshotChance: number,
	MoveSpeed: number,
	Weapon: string,
	Elo: number,
}

local DIFFICULTIES: { [string]: Difficulty } = {
	Practica = { Name = "Práctica", Shoots = false, Reaction = 99, AimTime = 99, Error = 0, FocusError = 0, HeadshotChance = 0, MoveSpeed = 10, Weapon = "Intervention", Elo = 0 },
	Facil = { Name = "Fácil", Shoots = true, Reaction = 1.3, AimTime = 1.2, Error = 3, FocusError = 1.2, HeadshotChance = 0.1, MoveSpeed = 11, Weapon = "Intervention", Elo = 800 },
	Normal = { Name = "Normal", Shoots = true, Reaction = 0.85, AimTime = 0.85, Error = 2, FocusError = 0.55, HeadshotChance = 0.25, MoveSpeed = 14, Weapon = "Intervention", Elo = 1100 },
	Dificil = { Name = "Difícil", Shoots = true, Reaction = 0.55, AimTime = 0.6, Error = 1.4, FocusError = 0.3, HeadshotChance = 0.4, MoveSpeed = 16, Weapon = "Viper", Elo = 1450 },
	Pesadilla = { Name = "Pesadilla", Shoots = true, Reaction = 0.32, AimTime = 0.4, Error = 0.9, FocusError = 0.12, HeadshotChance = 0.6, MoveSpeed = 17, Weapon = "Viper", Elo = 1900 },
}

local ANIMS = {
	Idle = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
}

type Bot = {
	IsBot: boolean,
	Active: boolean,
	DisplayName: string,
	Character: Model?,
	Difficulty: Difficulty,
	WeaponId: string,
	SkinId: string,
	Elo: number,
	-- IA
	SeenTime: number,
	AimStart: number?,
	MoveTarget: Vector3?,
	MoveDeadline: number,
	NextRelocate: number,
	Tracks: { [string]: AnimationTrack },
	Home: CFrame?,
}

local BotService = {}
BotService.Difficulties = DIFFICULTIES

local template: Model? = nil
local bots: { Bot } = {}
local rng = Random.new()

local function buildTemplate(): Model?
	local ok, rig = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local skin = Color3.fromRGB(70, 50, 35)
		desc.HeadColor = skin
		desc.LeftArmColor = Color3.fromRGB(60, 45, 30)
		desc.RightArmColor = Color3.fromRGB(60, 45, 30)
		desc.TorsoColor = Color3.fromRGB(70, 30, 90)
		desc.LeftLegColor = Color3.fromRGB(35, 30, 30)
		desc.RightLegColor = Color3.fromRGB(35, 30, 30)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		warn("[BotService] No se pudo crear el rig R15:", rig)
		return nil
	end
	local model = rig :: Model
	model.Name = "PumpkinSniper"
	-- Cabeza de calabaza: la cabeza real sigue siendo la hitbox
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		head.Transparency = 1
		for _, d in head:GetChildren() do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		local pumpkin = Props.Pumpkin(model, head.CFrame * CFrame.new(0, -0.65, 0), 1.6, true)
		for _, part in pumpkin:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.CanQuery = false
				part.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = head
				w.Part1 = part
				w.Parent = part
			end
		end
	end
	-- Capa harapienta
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		local cape = Instance.new("Part")
		cape.Name = "Cape"
		cape.Size = Vector3.new(2.2, 3.2, 0.15)
		cape.CFrame = torso.CFrame * CFrame.new(0, -0.6, 0.6) * CFrame.Angles(math.rad(8), 0, 0)
		cape.Color = Color3.fromRGB(25, 15, 30)
		cape.Material = Enum.Material.Fabric
		cape.CanCollide = false
		cape.CanQuery = false
		cape.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = cape
		w.Parent = cape
		cape.Parent = model
	end
	model.Parent = ServerStorage
	return model
end

local function playAnim(bot: Bot, name: string)
	for n, track in bot.Tracks do
		if n == name then
			if not track.IsPlaying then
				track:Play(0.2)
			end
		elseif track.IsPlaying then
			track:Stop(0.2)
		end
	end
end

function BotService.Create(difficultyKey: string): Bot?
	local diff = DIFFICULTIES[difficultyKey]
	if not diff or not template then
		return nil
	end
	local bot: Bot = {
		IsBot = true,
		Active = true,
		DisplayName = "Calabaza " .. diff.Name,
		Character = nil,
		Difficulty = diff,
		WeaponId = diff.Weapon,
		SkinId = if GameConfig.HalloweenEvent then "Pumpkin" else "Default",
		Elo = diff.Elo,
		SeenTime = 0,
		AimStart = nil,
		MoveTarget = nil,
		MoveDeadline = 0,
		NextRelocate = 0,
		Tracks = {},
		Home = nil,
	}
	table.insert(bots, bot)
	return bot
end

function BotService.Respawn(bot: Bot, cf: CFrame)
	if bot.Character then
		bot.Character:Destroy()
	end
	local char = (template :: Model):Clone()
	char.Name = bot.DisplayName
	char:PivotTo(cf)
	char.Parent = workspace
	local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.WalkSpeed = bot.Difficulty.MoveSpeed
	hum.DisplayName = bot.DisplayName
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	bot.Character = char
	bot.Home = cf
	bot.SeenTime = 0
	bot.AimStart = nil
	bot.MoveTarget = nil
	bot.NextRelocate = os.clock() + rng:NextNumber(1, 3)
	bot.Tracks = {}
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	for name, id in ANIMS do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(a)
		end)
		if ok and track then
			track.Looped = true
			bot.Tracks[name] = track
		end
	end
end

function BotService.Destroy(bot: Bot)
	bot.Active = false
	if bot.Character then
		bot.Character:Destroy()
		bot.Character = nil
	end
	local i = table.find(bots, bot)
	if i then
		table.remove(bots, i)
	end
end

-- IA -------------------------------------------------------------------------

local function losParams(bot: Bot): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.Character :: Model }
	params.IgnoreWater = true
	return params
end

local function visiblePoint(bot: Bot, target: Model): (boolean, Vector3?)
	local head = (bot.Character :: Model):FindFirstChild("Head") :: BasePart?
	if not head then
		return false, nil
	end
	local params = losParams(bot)
	for _, partName in { "Head", "UpperTorso", "Torso", "LowerTorso" } do
		local part = target:FindFirstChild(partName) :: BasePart?
		if part then
			local result = workspace:Raycast(head.Position, part.Position - head.Position, params)
			if result and result.Instance:IsDescendantOf(target) then
				return true, part.Position
			end
		end
	end
	return false, nil
end

local function pickMoveTarget(bot: Bot)
	local home = bot.Home :: CFrame
	-- Moverse lateralmente y algo hacia delante dentro de su mitad
	local offset = Vector3.new(rng:NextNumber(-55, 55), 0, rng:NextNumber(-20, 110))
	local world = home:PointToWorldSpace(Vector3.new(offset.X, 0, -offset.Z))
	bot.MoveTarget = world
	bot.MoveDeadline = os.clock() + 6
end

local function solveAim(origin: Vector3, targetPos: Vector3, targetVel: Vector3, w: Weapons.Weapon): Vector3
	-- Iterar: tiempo de vuelo -> posición futura -> compensar caída
	local t = (targetPos - origin).Magnitude / w.MuzzleVelocity
	local aim = targetPos
	for _ = 1, 3 do
		local future = targetPos + Vector3.new(targetVel.X, 0, targetVel.Z) * t
		aim = future + Vector3.new(0, 0.5 * w.BulletGravity * t * t, 0)
		t = (future - origin).Magnitude / w.MuzzleVelocity
	end
	return (aim - origin).Unit
end

local function think(bot: Bot, now: number, dt: number)
	local char = bot.Character
	if not char or not char.Parent then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return
	end
	local state = CombatService.GetState(bot)
	if not state or not state.CanFire then
		playAnim(bot, "Idle")
		CombatService.SetScoped(bot, false)
		return
	end
	local diff = bot.Difficulty
	local w = Weapons.Get(state.WeaponId)

	local targets = CombatService.TargetResolver(bot)
	local target = targets[1]
	local tChar: Model? = target and target.Character
	local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
	local visible, seenPos = false, nil
	if tChar and tHum and tHum.Health > 0 then
		visible, seenPos = visiblePoint(bot, tChar)
	end

	-- Recarga táctica
	if state.Mag <= 0 and not state.Reloading then
		CombatService.Reload(bot)
	end

	if visible and diff.Shoots and seenPos and tChar then
		bot.SeenTime += dt
		-- Encarar al objetivo y quedarse quieto para apuntar
		hum.AutoRotate = false
		hum:Move(Vector3.zero)
		bot.MoveTarget = nil
		playAnim(bot, "Idle")
		local flat = Vector3.new(seenPos.X, root.Position.Y, seenPos.Z)
		root.CFrame = CFrame.lookAt(root.Position, flat)

		if bot.SeenTime >= diff.Reaction then
			if not bot.AimStart then
				bot.AimStart = now
				CombatService.SetScoped(bot, true)
			end
			local aimed = now - (bot.AimStart :: number)
			local cooldownReady = os.clock() - state.LastFire >= w.FireCooldown
			if aimed >= diff.AimTime and cooldownReady and not state.Reloading and state.Mag > 0 then
				local head = char:FindFirstChild("Head") :: BasePart
				local aimHead = rng:NextNumber() < diff.HeadshotChance
				local aimPart = (if aimHead then tChar:FindFirstChild("Head") else (tChar:FindFirstChild("UpperTorso") or tChar:FindFirstChild("Torso"))) :: BasePart?
				if aimPart then
					local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
					local vel = if tRoot then tRoot.AssemblyLinearVelocity else Vector3.zero
					local dir = solveAim(head.Position, aimPart.Position, vel, w)
					-- El error baja cuanto más tiempo te sigue; sube si te mueves rápido
					local focus = math.clamp((aimed - diff.AimTime) / 1.5 + 0.35, 0, 1)
					local err = diff.Error + (diff.FocusError - diff.Error) * focus
					err += math.clamp(Vector3.new(vel.X, 0, vel.Z).Magnitude / 16, 0, 1.5) * 0.4
					dir = Ballistics.ApplySpread(dir, err, rng)
					CombatService.BotFire(bot, head.Position, dir)
					bot.AimStart = now + w.FireCooldown * 0.5 -- recolocar mira tras el cerrojo
					if w.FireCooldown >= 0.8 then
						CombatService.SetScoped(bot, false)
						task.delay(w.FireCooldown * 0.8, function()
							if bot.Active then
								CombatService.SetScoped(bot, true)
							end
						end)
					end
					-- A veces se recoloca tras disparar
					if rng:NextNumber() < 0.3 then
						bot.NextRelocate = now
					end
				end
			end
		end
		return
	end

	-- Sin visión: moverse / buscar
	bot.SeenTime = math.max(0, bot.SeenTime - dt * 0.5)
	bot.AimStart = nil
	CombatService.SetScoped(bot, false)
	hum.AutoRotate = true
	if not bot.MoveTarget or now > bot.MoveDeadline or now >= bot.NextRelocate then
		pickMoveTarget(bot)
		bot.NextRelocate = now + rng:NextNumber(3, 7)
	end
	local mt = bot.MoveTarget :: Vector3
	if Vector3.new(mt.X - root.Position.X, 0, mt.Z - root.Position.Z).Magnitude < 3 then
		bot.MoveTarget = nil
		playAnim(bot, "Idle")
		hum:Move(Vector3.zero)
	else
		hum:MoveTo(mt)
		playAnim(bot, "Walk")
	end
end

function BotService.IsReady(): boolean
	return template ~= nil
end

function BotService.Start()
	task.spawn(function()
		template = buildTemplate()
	end)
	DuelService.BotHooks.Respawn = BotService.Respawn
	DuelService.BotHooks.Destroy = BotService.Destroy

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		local step = acc
		acc = 0
		local now = os.clock()
		for _, bot in table.clone(bots) do
			if bot.Active then
				local ok, err = pcall(think, bot, now, step)
				if not ok then
					warn("[BotService]", err)
				end
			end
		end
	end)
end

return BotService
