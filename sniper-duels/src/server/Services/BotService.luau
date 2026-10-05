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
local PathfindingService = game:GetService("PathfindingService")

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
	Run = "rbxassetid://507767714",
	Hold = "rbxassetid://507768375", -- "toolnone": brazo derecho sujetando el arma
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
	Mode: string, -- "Cover" | "Peek" | "Engage" | "Hunt"
	SeenTime: number,
	AimStart: number?,
	LastSeenPos: Vector3?,
	LastSeenTime: number,
	CoverPoints: { { Cover: Vector3, Peek: Vector3 } },
	CurrentCover: { Cover: Vector3, Peek: Vector3 }?,
	ModeUntil: number,
	PeeksLeft: number,
	Path: { Vector3 },
	PathIndex: number,
	PathTarget: Vector3?,
	PathDeadline: number,
	LastHealth: number,
	StrafeDir: number,
	HuntTarget: Vector3?,
	RoundStart: number?,
	Tracks: { [string]: AnimationTrack },
	Home: CFrame?,
}

local BotService = {}
BotService.Difficulties = DIFFICULTIES

local template: Model? = nil
local thinking: { [any]: boolean } = {}
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
	-- "Hold" va aparte: siempre sonando encima del resto
	for n, track in bot.Tracks do
		if n == "Hold" then
			continue
		end
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
		Mode = "Cover",
		SeenTime = 0,
		AimStart = nil,
		LastSeenPos = nil,
		LastSeenTime = -math.huge,
		CoverPoints = {},
		CurrentCover = nil,
		ModeUntil = 0,
		PeeksLeft = 0,
		Path = {},
		PathIndex = 1,
		PathTarget = nil,
		PathDeadline = 0,
		LastHealth = 100,
		StrafeDir = 1,
		Tracks = {},
		Home = nil,
	}
	table.insert(bots, bot)
	return bot
end

-- Busca coberturas en la mitad del bot: un punto escondido detrás del objeto
-- y un punto de "asomarse" a un lado.
local function computeCoverPoints(bot: Bot, home: CFrame)
	local points = {}
	local arenas = workspace:FindFirstChild("Arenas")
	local arena: Instance? = nil
	if arenas then
		for _, m in arenas:GetChildren() do
			local sa = m:FindFirstChild("SpawnA") :: BasePart?
			local sb = m:FindFirstChild("SpawnB") :: BasePart?
			for _, sp in { sa, sb } do
				if sp and (sp.Position - home.Position).Magnitude < 12 then
					arena = m
				end
			end
		end
	end
	if not arena then
		return points
	end
	local forward = home.LookVector * Vector3.new(1, 0, 1) -- hacia el enemigo
	forward = if forward.Magnitude > 0 then forward.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	local folder = (arena :: Instance):FindFirstChild("Cover") or arena
	for _, part in (folder :: Instance):GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and part.CanQuery and part.Size.Y >= 3.5 and part.Size.Y <= 20 then
			local rel = part.Position - home.Position
			local along = rel:Dot(forward)
			-- Solo coberturas de su mitad (no más allá del centro)
			if along > 10 and along < 175 then
				local depth = math.max(part.Size.X, part.Size.Z) * 0.5 + 3
				local cover = Vector3.new(part.Position.X, home.Position.Y, part.Position.Z) - forward * depth
				local side = if math.random() < 0.5 then 1 else -1
				local width = math.max(part.Size.X, part.Size.Z) * 0.5 + 3
				local peek = cover + right * side * width + forward * 1.5
				table.insert(points, { Cover = cover, Peek = peek })
			end
		end
	end
	-- Mezclar
	for i = #points, 2, -1 do
		local j = rng:NextInteger(1, i)
		points[i], points[j] = points[j], points[i]
	end
	while #points > 40 do
		table.remove(points)
	end
	return points
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
	bot.Mode = "Cover"
	bot.SeenTime = 0
	bot.AimStart = nil
	bot.LastSeenPos = nil
	bot.LastSeenTime = -math.huge
	bot.CurrentCover = nil
	bot.ModeUntil = 0
	bot.Path = {}
	bot.PathTarget = nil
	bot.LastHealth = hum.Health
	bot.HuntTarget = nil
	bot.RoundStart = os.clock() + 3 -- la cuenta atrás
	bot.CoverPoints = computeCoverPoints(bot, cf)
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
			if name == "Hold" then
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0)
			end
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

-- Devuelve las partes visibles del objetivo (cabeza primero)
local function visibleParts(bot: Bot, target: Model): { BasePart }
	local head = (bot.Character :: Model):FindFirstChild("Head") :: BasePart?
	local result = {}
	if not head then
		return result
	end
	local params = losParams(bot)
	for _, partName in { "Head", "UpperTorso", "Torso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg" } do
		local part = target:FindFirstChild(partName) :: BasePart?
		if part then
			local hit = workspace:Raycast(head.Position, part.Position - head.Position, params)
			if hit and hit.Instance:IsDescendantOf(target) then
				table.insert(result, part)
			end
		end
	end
	return result
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

-- Movimiento con PathfindingService (no se atasca con las coberturas)
local function goTo(bot: Bot, hum: Humanoid, root: BasePart, target: Vector3, now: number)
	if not bot.PathTarget or (bot.PathTarget - target).Magnitude > 2 or now > bot.PathDeadline then
		bot.PathTarget = target
		bot.PathDeadline = now + 8
		bot.Path = { target }
		bot.PathIndex = 1
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local wps = {}
			for _, wp in path:GetWaypoints() do
				table.insert(wps, wp.Position)
			end
			if #wps > 0 then
				bot.Path = wps
			end
		end
	end
	local wp = bot.Path[bot.PathIndex]
	if not wp then
		return true
	end
	if Vector3.new(wp.X - root.Position.X, 0, wp.Z - root.Position.Z).Magnitude < 2.5 then
		bot.PathIndex += 1
		wp = bot.Path[bot.PathIndex]
		if not wp then
			hum:Move(Vector3.zero)
			return true
		end
	end
	hum:MoveTo(wp)
	if wp.Y > root.Position.Y + 1.5 then
		hum.Jump = true
	end
	return false
end

-- Posición actual del rival (en un duelo de francotiradores se intuye dónde
-- está; el bot no hace trampa con la puntería, solo con la búsqueda)
local function enemyPosition(bot: Bot): Vector3?
	local target = CombatService.TargetResolver(bot)[1]
	local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- ¿Desde este punto se ve al rival? (raycast a la altura de la cabeza)
local function hasLineFrom(bot: Bot, point: Vector3, enemy: Vector3): boolean
	local params = losParams(bot)
	local from = point + Vector3.new(0, 4.5, 0)
	local to = enemy + Vector3.new(0, 1.5, 0)
	local hit = workspace:Raycast(from, to - from, params)
	if not hit then
		return true
	end
	local target = CombatService.TargetResolver(bot)[1]
	return target ~= nil and target.Character ~= nil and hit.Instance:IsDescendantOf(target.Character)
end

local function pickCover(bot: Bot): { Cover: Vector3, Peek: Vector3 }?
	if #bot.CoverPoints == 0 then
		return nil
	end
	local enemy = enemyPosition(bot)
	local root = bot.Character and bot.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Preferir coberturas cercanas cuyo punto de asomarse SÍ ve al rival
	local best, bestScore = nil, math.huge
	for _ = 1, 10 do
		local c = bot.CoverPoints[rng:NextInteger(1, #bot.CoverPoints)]
		local dist = if root then (c.Cover - root.Position).Magnitude else 0
		local score = dist + rng:NextNumber(0, 30)
		if enemy and not hasLineFrom(bot, c.Peek, enemy) then
			score += 400 -- asomarse ahí no sirve de nada
		end
		if c ~= bot.CurrentCover and score < bestScore then
			best, bestScore = c, score
		end
	end
	return best
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
		bot.LastHealth = hum.Health
		return
	end
	local diff = bot.Difficulty
	char:SetAttribute("AIMode", bot.Mode) -- visible en el Explorador para depurar
	local w = Weapons.Get(state.WeaponId)

	-- ¿Le han dado? -> abandonar posición y moverse a otra cobertura
	if hum.Health < bot.LastHealth - 1 then
		bot.Mode = "Cover"
		bot.CurrentCover = pickCover(bot)
		bot.AimStart = nil
		bot.SeenTime = 0
		hum.Jump = rng:NextNumber() < 0.5
		CombatService.SetScoped(bot, false)
	end
	bot.LastHealth = hum.Health

	local target = CombatService.TargetResolver(bot)[1]
	local tChar: Model? = target and target.Character
	local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
	local visible: { BasePart } = {}
	if tChar and tHum and tHum.Health > 0 then
		visible = visibleParts(bot, tChar)
	end

	if state.Mag <= 0 and not state.Reloading then
		CombatService.Reload(bot)
		bot.Mode = "Cover"
	end

	-- COMBATE -------------------------------------------------------------
	if #visible > 0 and diff.Shoots and tChar and not state.Reloading then
		local wasRecent = now - bot.LastSeenTime < 3 and bot.LastSeenPos ~= nil and (bot.LastSeenPos - visible[1].Position).Magnitude < 25
		bot.LastSeenPos = visible[1].Position
		bot.LastSeenTime = now
		bot.SeenTime += dt
		bot.Mode = "Engage"
		local flat = Vector3.new(visible[1].Position.X, root.Position.Y, visible[1].Position.Z)
		hum.AutoRotate = false
		root.CFrame = CFrame.lookAt(root.Position, flat)

		-- Pre-apuntado: si ya te tenía controlado reacciona mucho más rápido
		local reaction = if wasRecent then diff.Reaction * 0.35 else diff.Reaction
		if bot.SeenTime >= reaction then
			if not bot.AimStart then
				bot.AimStart = now
				CombatService.SetScoped(bot, true)
			end
			local aimed = now - (bot.AimStart :: number)
			-- Los bots buenos hacen "strafe" mientras apuntan y se paran para disparar
			if diff.Reaction < 0.6 and aimed < diff.AimTime * 0.8 then
				if rng:NextNumber() < 0.15 then
					bot.StrafeDir = -bot.StrafeDir
				end
				hum:Move(root.CFrame.RightVector * bot.StrafeDir)
				playAnim(bot, "Walk")
			else
				hum:Move(Vector3.zero)
				playAnim(bot, "Idle")
			end
			local cooldownReady = os.clock() - state.LastFire >= w.FireCooldown
			if aimed >= diff.AimTime and cooldownReady and state.Mag > 0 then
				local head = char:FindFirstChild("Head") :: BasePart
				-- Elegir parte: cabeza si se ve y tira dado; si no, la más grande visible
				local aimPart = visible[1]
				for _, p in visible do
					if p.Name == "UpperTorso" or p.Name == "Torso" then
						aimPart = p
						break
					end
				end
				if visible[1].Name == "Head" and rng:NextNumber() < diff.HeadshotChance then
					aimPart = visible[1]
				end
				local tRoot = tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				local vel = if tRoot then tRoot.AssemblyLinearVelocity else Vector3.zero
				local dir = solveAim(head.Position, aimPart.Position, vel, w)
				local focus = math.clamp((aimed - diff.AimTime) / 1.5 + 0.35, 0, 1)
				local err = diff.Error + (diff.FocusError - diff.Error) * focus
				err += math.clamp(Vector3.new(vel.X, 0, vel.Z).Magnitude / 16, 0, 1.5) * 0.4
				dir = Ballistics.ApplySpread(dir, err, rng)
				CombatService.BotFire(bot, head.Position, dir)
				bot.AimStart = now + w.FireCooldown * 0.5
				-- Tras disparar con cerrojo: esconderse mientras recarga el tiro
				if w.FireCooldown >= 0.8 then
					CombatService.SetScoped(bot, false)
					if bot.CurrentCover and rng:NextNumber() < 0.7 then
						bot.Mode = "Cover"
						bot.ModeUntil = now + w.FireCooldown * 0.9
						bot.SeenTime = 0
						bot.AimStart = nil
					else
						task.delay(w.FireCooldown * 0.8, function()
							if bot.Active then
								CombatService.SetScoped(bot, true)
							end
						end)
					end
				end
			end
		else
			hum:Move(Vector3.zero)
			playAnim(bot, "Idle")
		end
		if bot.Mode == "Engage" then
			return
		end
	end

	-- SIN VISIÓN: cobertura / asomarse / buscar -----------------------------
	bot.SeenTime = math.max(0, bot.SeenTime - dt * 0.5)
	bot.AimStart = nil
	hum.AutoRotate = true
	CombatService.SetScoped(bot, false)

	if bot.Mode == "Engage" then
		-- Te ha perdido de vista: ir a cubrirse y volver a asomarse
		bot.Mode = "Cover"
		bot.ModeUntil = now + rng:NextNumber(0.6, 1.5)
	end
	if not bot.CurrentCover then
		bot.CurrentCover = pickCover(bot)
		bot.PeeksLeft = rng:NextInteger(2, 4)
	end
	local cover = bot.CurrentCover

	-- Un rato sin verte: salir a buscarte hacia donde estás (no se queda escondido)
	local enemyPos = enemyPosition(bot)
	local idleFor = now - math.max(bot.LastSeenTime, bot.RoundStart or 0)
	if bot.Mode ~= "Hunt" and enemyPos and idleFor > (if diff.Reaction < 0.6 then 4 else 7) then
		bot.Mode = "Hunt"
		bot.ModeUntil = now + 5
		bot.HuntTarget = enemyPos
	end

	if bot.Mode == "Hunt" and (bot.HuntTarget or bot.LastSeenPos) then
		local goal = (bot.HuntTarget or bot.LastSeenPos) :: Vector3
		-- Avanzar hacia el rival, en diagonal para no ir en línea recta
		local side = (bot.Home :: CFrame).RightVector * (if bot.StrafeDir > 0 then 25 else -25)
		local dest = root.Position:Lerp(Vector3.new(goal.X, root.Position.Y, goal.Z) + side, 0.35)
		goTo(bot, hum, root, dest, now)
		playAnim(bot, "Run")
		if now > bot.ModeUntil then
			bot.Mode = "Cover"
			bot.HuntTarget = nil
			bot.LastSeenTime = now -- reiniciar el contador de búsqueda
			bot.CurrentCover = pickCover(bot)
		end
		return
	end

	if not cover then
		-- Sin coberturas conocidas: deambular por su mitad
		local home = bot.Home :: CFrame
		local wander = home:PointToWorldSpace(Vector3.new(rng:NextNumber(-50, 50), 0, -rng:NextNumber(10, 100)))
		goTo(bot, hum, root, wander, now)
		playAnim(bot, "Walk")
		return
	end

	if bot.Mode == "Cover" then
		local arrived = goTo(bot, hum, root, cover.Cover, now)
		playAnim(bot, if arrived then "Idle" else "Run")
		if arrived and now >= bot.ModeUntil then
			bot.Mode = "Peek"
			bot.ModeUntil = now + rng:NextNumber(1.2, 2.5)
		end
	elseif bot.Mode == "Peek" then
		local arrived = goTo(bot, hum, root, cover.Peek, now)
		playAnim(bot, if arrived then "Idle" else "Walk")
		if arrived then
			-- Mirar hacia donde te vio por última vez (o hacia el centro)
			local look = bot.LastSeenPos or (bot.Home :: CFrame).Position + (bot.Home :: CFrame).LookVector * 200
			hum.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(look.X, root.Position.Y, look.Z))
		end
		if now > bot.ModeUntil then
			bot.PeeksLeft -= 1
			if bot.PeeksLeft <= 0 then
				bot.CurrentCover = pickCover(bot)
				bot.PeeksLeft = rng:NextInteger(2, 4)
			end
			bot.Mode = "Cover"
			bot.ModeUntil = now + rng:NextNumber(0.8, 2)
		end
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
			-- think puede ceder (pathfinding): no solapar dos ejecuciones
			if bot.Active and not thinking[bot] then
				thinking[bot] = true
				task.spawn(function()
					local ok, err = pcall(think, bot, now, step)
					if not ok then
						warn("[BotService]", err)
					end
					thinking[bot] = nil
				end)
			end
		end
	end)
end

return BotService
