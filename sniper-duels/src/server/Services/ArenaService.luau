--!strict
-- Genera el lobby y un pool de arenas simétricas (justas para ambos lados)
-- con terreno real, colinas, niebla, luces y props temáticos.
-- Si ya existe una carpeta "Arenas" o un modelo "Lobby" en Workspace hecho a
-- mano, se respeta y no se genera nada: así un builder puede reemplazar el mapa.
--
-- Formato de arena manual: Model con Parts "SpawnA" y "SpawnB".
-- Formato de lobby manual: Model con Parts "LobbySpawn" y pares "PadA_n"/"PadB_n".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local World = script.Parent.Parent.World
local Props = require(World.Props)
local Environment = require(World.Environment)

local ArenaService = {}

export type Arena = {
	Id: number,
	Name: string,
	Model: Model,
	SpawnA: CFrame,
	SpawnB: CFrame,
	InUse: boolean,
}

export type PadPair = {
	Id: number,
	A: BasePart,
	B: BasePart,
	Label: TextLabel,
}

-- Grupo de pads: cada equipo tiene uno (1v1) o dos (2v2) cuadrados
export type PadGroup = {
	Id: number,
	Mode: string, -- "1v1" | "2v2"
	A: { BasePart },
	B: { BasePart },
	Label: TextLabel,
}

type Theme = {
	Name: string,
	Ground: Enum.Material,
	Patch: Enum.Material,
	Hill: Enum.Material,
	Cover: Color3,
	CoverMat: Enum.Material,
	Accent: Color3,
	Style: string,
}

local arenas: { Arena } = {}
local padPairs: { PadPair } = {}
local padGroups: { PadGroup } = {}
local botPad: BasePart? = nil
local lobbySpawn = CFrame.new(0, 5, 0)

local HALLOWEEN_THEMES: { Theme } = {
	{ Name = "Cementerio Olvidado", Ground = Enum.Material.Grass, Patch = Enum.Material.Mud, Hill = Enum.Material.Grass, Cover = Color3.fromRGB(100, 98, 106), CoverMat = Enum.Material.Brick, Accent = Color3.fromRGB(255, 120, 20), Style = "graves" },
	{ Name = "Granja de Calabazas", Ground = Enum.Material.LeafyGrass, Patch = Enum.Material.Ground, Hill = Enum.Material.Grass, Cover = Color3.fromRGB(90, 62, 42), CoverMat = Enum.Material.WoodPlanks, Accent = Color3.fromRGB(255, 150, 30), Style = "farm" },
	{ Name = "Mansión Embrujada", Ground = Enum.Material.Cobblestone, Patch = Enum.Material.Slate, Hill = Enum.Material.Rock, Cover = Color3.fromRGB(95, 80, 78), CoverMat = Enum.Material.Brick, Accent = Color3.fromRGB(170, 70, 255), Style = "ruins" },
	{ Name = "Bosque Maldito", Ground = Enum.Material.Mud, Patch = Enum.Material.LeafyGrass, Hill = Enum.Material.Rock, Cover = Color3.fromRGB(80, 78, 84), CoverMat = Enum.Material.Rock, Accent = Color3.fromRGB(90, 255, 120), Style = "forest" },
	{ Name = "Pueblo Abandonado", Ground = Enum.Material.Ground, Patch = Enum.Material.Cobblestone, Hill = Enum.Material.Rock, Cover = Color3.fromRGB(96, 70, 52), CoverMat = Enum.Material.WoodPlanks, Accent = Color3.fromRGB(255, 190, 60), Style = "village" },
	{ Name = "Pantano Maldito", Ground = Enum.Material.Mud, Patch = Enum.Material.Grass, Hill = Enum.Material.LeafyGrass, Cover = Color3.fromRGB(60, 70, 50), CoverMat = Enum.Material.Rock, Accent = Color3.fromRGB(120, 255, 90), Style = "swamp" },
}

local NORMAL_THEMES: { Theme } = {
	{ Name = "Lost Hill", Ground = Enum.Material.Ground, Patch = Enum.Material.Rock, Hill = Enum.Material.Rock, Cover = Color3.fromRGB(92, 88, 82), CoverMat = Enum.Material.Rock, Accent = Color3.fromRGB(0, 255, 140), Style = "rocks" },
	{ Name = "Dunas", Ground = Enum.Material.Sand, Patch = Enum.Material.Sandstone, Hill = Enum.Material.Sandstone, Cover = Color3.fromRGB(170, 140, 100), CoverMat = Enum.Material.Sandstone, Accent = Color3.fromRGB(255, 140, 40), Style = "rocks" },
	{ Name = "Tundra", Ground = Enum.Material.Snow, Patch = Enum.Material.Glacier, Hill = Enum.Material.Snow, Cover = Color3.fromRGB(160, 190, 210), CoverMat = Enum.Material.Ice, Accent = Color3.fromRGB(80, 180, 255), Style = "rocks" },
	{ Name = "Pradera", Ground = Enum.Material.Grass, Patch = Enum.Material.Ground, Hill = Enum.Material.Grass, Cover = Color3.fromRGB(100, 96, 90), CoverMat = Enum.Material.Rock, Accent = Color3.fromRGB(255, 220, 80), Style = "rocks" },
}

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function barrier(parent: Instance, size: Vector3, cf: CFrame)
	local b = block(parent, "Barrier", size, cf, Color3.new(), Enum.Material.SmoothPlastic)
	b.Transparency = 1
	b.CanQuery = false
	b.CastShadow = false
end

-- Colinas de terreno alrededor de un rectángulo (decoran y tapan los límites)
local function hillsAround(center: Vector3, w: number, l: number, mat: Enum.Material, rng: Random)
	local terrain = workspace.Terrain
	local function ball(pos: Vector3)
		terrain:FillBall(pos, rng:NextNumber(30, 44), mat)
	end
	for z = -l / 2, l / 2, 34 do
		ball(center + Vector3.new(-(w / 2 + 40), rng:NextNumber(-6, 10), z))
		ball(center + Vector3.new(w / 2 + 40, rng:NextNumber(-6, 10), z))
	end
	for x = -w / 2, w / 2, 34 do
		ball(center + Vector3.new(x, rng:NextNumber(-6, 10), -(l / 2 + 40)))
		ball(center + Vector3.new(x, rng:NextNumber(-6, 10), l / 2 + 40))
	end
end

local function buildArena(index: number, origin: Vector3): Arena
	local themes = if GameConfig.HalloweenEvent then HALLOWEEN_THEMES else NORMAL_THEMES
	local theme = themes[(index - 1) % #themes + 1]
	local rng = Random.new(index * 7919)
	local terrain = workspace.Terrain
	local model = Instance.new("Model")
	model.Name = string.format("Arena_%02d_%s", index, theme.Name)

	local W, L = 140, 360
	local base = CFrame.new(origin)
	local mirror = CFrame.Angles(0, math.pi, 0)

	-- Suelo de terreno con parches simétricos
	terrain:FillBlock(base * CFrame.new(0, -6, 0), Vector3.new(W + 120, 12, L + 120), theme.Ground)
	for _ = 1, 10 do
		-- Una capa completa de vóxel (4 studs) para no dejar hundimientos
		local size = Vector3.new(rng:NextNumber(8, 26), 4, rng:NextNumber(8, 30))
		local local_ = CFrame.new(rng:NextNumber(-W / 2, W / 2), -2, rng:NextNumber(-L / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		terrain:FillBlock(base * local_, size, theme.Patch)
		terrain:FillBlock(base * mirror * local_, size, theme.Patch)
	end
	hillsAround(origin, W, L, theme.Hill, rng)

	-- Límites invisibles (las colinas hacen de pared visual)
	local wallH = 80
	for _, side in { -1, 1 } do
		barrier(model, Vector3.new(4, wallH, L + 8), base * CFrame.new(side * (W / 2 + 2), wallH / 2, 0))
		barrier(model, Vector3.new(W + 8, wallH, 4), base * CFrame.new(0, wallH / 2, side * (L / 2 + 2)))
	end
	barrier(model, Vector3.new(W + 8, 2, L + 8), base * CFrame.new(0, wallH + 1, 0))

	local cover = Instance.new("Folder")
	cover.Name = "Cover"
	cover.Parent = model

	-- Coloca el mismo prop en el lado A y reflejado en el lado B
	local function pair(localCf: CFrame, build: (parent: Instance, cf: CFrame, r: Random) -> ())
		local seed = rng:NextInteger(1, 1e9)
		build(cover, base * localCf, Random.new(seed))
		build(cover, base * mirror * localCf, Random.new(seed))
	end
	local function solid(size: Vector3, localCf: CFrame, name: string)
		pair(localCf, function(parent, cf)
			block(parent, name, size, cf, theme.Cover, theme.CoverMat)
		end)
	end
	local function randomSpot(zMin: number, zMax: number): CFrame
		return CFrame.new(rng:NextNumber(-W / 2 + 10, W / 2 - 10), 0, rng:NextNumber(zMin, zMax)) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0)
	end

	-- Búnker de spawn
	solid(Vector3.new(26, 7, 3), CFrame.new(0, 3.5, -L / 2 + 30), "SpawnWall")
	solid(Vector3.new(3, 7, 14), CFrame.new(-14, 3.5, -L / 2 + 24), "SpawnWall")
	solid(Vector3.new(3, 7, 14), CFrame.new(14, 3.5, -L / 2 + 24), "SpawnWall")
	pair(CFrame.new(-10, 0, -L / 2 + 32), function(parent, cf)
		Props.Lantern(parent, cf, theme.Accent)
	end)

	-- Cobertura temática
	local style = theme.Style
	if style == "graves" then
		for _ = 1, 2 do
			pair(randomSpot(-L / 2 + 70, -40), function(parent, cf)
				Props.Crypt(parent, cf)
			end)
		end
		for _ = 1, 5 do
			local center = randomSpot(-L / 2 + 50, -16)
			for g = 0, 2 do
				pair(center * CFrame.new(g * 3.4 - 3.4, 0, 0), function(parent, cf)
					Props.Grave(parent, cf, 1.15)
				end)
			end
		end
		for _ = 1, 4 do
			pair(randomSpot(-L / 2 + 50, -20), function(parent, cf, r)
				Props.DeadTree(parent, cf, r:NextNumber(18, 28), r)
			end)
		end
		pair(CFrame.new(-W / 2 + 20, 0, -60), function(parent, cf)
			Props.Fence(parent, cf.Position, (cf * CFrame.new(0, 0, 30)).Position)
		end)
	elseif style == "farm" then
		for _ = 1, 6 do
			local spot = randomSpot(-L / 2 + 50, -18)
			local stack = rng:NextInteger(1, 3)
			pair(spot, function(parent, cf)
				for s = 0, stack - 1 do
					Props.HayBale(parent, cf * CFrame.new(0, s * 3.4, 0) * CFrame.Angles(0, s * 0.3, 0))
				end
			end)
		end
		for _ = 1, 3 do
			pair(randomSpot(-L / 2 + 60, -30), function(parent, cf)
				Props.Scarecrow(parent, cf)
			end)
		end
		for _ = 1, 3 do
			local patch = randomSpot(-L / 2 + 50, -20)
			for i = 1, 6 do
				pair(patch * CFrame.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)), function(parent, cf, r)
					Props.Pumpkin(parent, cf, r:NextNumber(2, 3.4), i == 1)
				end)
			end
		end
		pair(randomSpot(-L / 2 + 80, -50), function(parent, cf, r)
			local barn = Props.RuinWall(parent, cf, 18, 12, r)
			for _, c in barn:GetChildren() do
				if c:IsA("BasePart") then
					c.Material = Enum.Material.WoodPlanks
					c.Color = Color3.fromRGB(120, 40, 30)
				end
			end
		end)
	elseif style == "ruins" then
		for _ = 1, 7 do
			pair(randomSpot(-L / 2 + 50, -16), function(parent, cf, r)
				Props.RuinWall(parent, cf, r:NextNumber(8, 16), r:NextNumber(6, 13), r)
			end)
		end
		for _ = 1, 4 do
			pair(randomSpot(-L / 2 + 50, -16), function(parent, cf)
				block(parent, "Pillar", Vector3.new(14, 2.4, 2.4), cf * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 145, 150), Enum.Material.Marble).Shape = Enum.PartType.Cylinder
			end)
		end
		pair(randomSpot(-L / 2 + 60, -40), function(parent, cf)
			Props.Cauldron(parent, cf)
			for c = 0, 4 do
				Props.Candle(parent, cf * CFrame.Angles(0, c * math.rad(72), 0) * CFrame.new(0, 0, 3.5))
			end
		end)
		pair(randomSpot(-L / 2 + 70, -40), function(parent, cf)
			Props.Crypt(parent, cf)
		end)
	elseif style == "forest" then
		for _ = 1, 9 do
			pair(randomSpot(-L / 2 + 45, -12), function(parent, cf, r)
				Props.DeadTree(parent, cf, r:NextNumber(20, 34), r)
			end)
		end
		for _ = 1, 6 do
			local size = Vector3.new(rng:NextNumber(5, 12), rng:NextNumber(4, 9), rng:NextNumber(5, 10))
			pair(randomSpot(-L / 2 + 50, -16), function(parent, cf)
				Props.Rock(parent, cf, size, theme.Cover)
			end)
		end
		for _ = 1, 4 do
			pair(randomSpot(-L / 2 + 50, -20), function(parent, cf)
				Props.Pumpkin(parent, cf, 2.6, true)
			end)
		end
	elseif style == "village" then
		-- Casas en ruinas de madera y piedra, vallas, farolas y calabazas en los porches
		for _ = 1, 6 do
			pair(randomSpot(-L / 2 + 50, -16), function(parent, cf, r)
				local wall = Props.RuinWall(parent, cf, r:NextNumber(10, 18), r:NextNumber(7, 12), r)
				for _, c in wall:GetChildren() do
					if c:IsA("BasePart") then
						c.Material = if r:NextNumber() < 0.5 then Enum.Material.WoodPlanks else Enum.Material.Brick
						c.Color = if c.Material == Enum.Material.WoodPlanks then Color3.fromRGB(90, 64, 44) else Color3.fromRGB(110, 95, 85)
					end
				end
				Props.Pumpkin(parent, cf * CFrame.new(r:NextNumber(-5, 5), 0, 3), 2.2, true)
			end)
		end
		for _ = 1, 3 do
			pair(randomSpot(-L / 2 + 60, -30), function(parent, cf)
				Props.Fence(parent, cf.Position, (cf * CFrame.new(18, 0, 0)).Position)
			end)
		end
		for _ = 1, 3 do
			pair(randomSpot(-L / 2 + 50, -20), function(parent, cf)
				Props.Lantern(parent, cf, Color3.fromRGB(255, 180, 70))
			end)
		end
		pair(randomSpot(-L / 2 + 70, -50), function(parent, cf)
			Props.Scarecrow(parent, cf)
		end)
	elseif style == "swamp" then
		-- Agua turbia, troncos, rocas cubiertas de musgo y mucha niebla
		for _ = 1, 8 do
			pair(randomSpot(-L / 2 + 45, -12), function(parent, cf, r)
				Props.DeadTree(parent, cf, r:NextNumber(16, 30), r)
			end)
		end
		for _ = 1, 7 do
			local size = Vector3.new(rng:NextNumber(5, 13), rng:NextNumber(3, 8), rng:NextNumber(5, 11))
			pair(randomSpot(-L / 2 + 50, -16), function(parent, cf)
				Props.Rock(parent, cf, size, Color3.fromRGB(70, 85, 60))
			end)
		end
		for _ = 1, 4 do
			pair(randomSpot(-L / 2 + 50, -20), function(parent, cf, r)
				local log = block(parent, "Log", Vector3.new(r:NextNumber(8, 14), 2.4, 2.4), cf * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, 0), Color3.fromRGB(70, 50, 36), Enum.Material.Wood)
				log.Shape = Enum.PartType.Cylinder
			end)
		end
		for _ = 1, 3 do
			pair(randomSpot(-L / 2 + 60, -30), function(parent, cf)
				Props.Cauldron(parent, cf)
			end)
		end
		for _ = 1, 6 do
			local m = block(cover, "SwampMist", Vector3.new(1, 1, 1), base * CFrame.new(rng:NextNumber(-W / 2, W / 2), 0.5, rng:NextNumber(-L / 2, L / 2)), Color3.new(), Enum.Material.SmoothPlastic)
			m.Transparency = 1
			m.CanCollide = false
			m.CanQuery = false
			Props.Mist(m, Color3.fromRGB(150, 200, 150), 3)
		end
	else -- rocks
		for _ = 1, 10 do
			local size = Vector3.new(rng:NextNumber(5, 15), rng:NextNumber(4, 12), rng:NextNumber(4, 10))
			pair(randomSpot(-L / 2 + 50, -14), function(parent, cf)
				Props.Rock(parent, cf, size, theme.Cover)
			end)
		end
	end

	-- Torre de francotirador (alto riesgo / alta recompensa)
	local wood, woodMat = Color3.fromRGB(70, 50, 36), Enum.Material.WoodPlanks
	pair(CFrame.new(W / 2 - 14, 0, -L / 2 + 70), function(parent, cf)
		block(parent, "TowerFloor", Vector3.new(10, 1, 10), cf * CFrame.new(0, 16, 0), wood, woodMat)
		for _, o in { Vector2.new(-4, -4), Vector2.new(4, -4), Vector2.new(-4, 4), Vector2.new(4, 4) } do
			block(parent, "TowerLeg", Vector3.new(1.2, 16, 1.2), cf * CFrame.new(o.X, 8, o.Y), wood, Enum.Material.Wood)
		end
		block(parent, "TowerRail", Vector3.new(10, 3.5, 1), cf * CFrame.new(0, 18.25, 4.5), wood, woodMat)
		block(parent, "TowerRoof", Vector3.new(11, 0.6, 11), cf * CFrame.new(0, 24, 0), Color3.fromRGB(40, 30, 25), woodMat)
		for _, o in { Vector2.new(-4.5, -4.5), Vector2.new(4.5, 4.5) } do
			block(parent, "RoofPost", Vector3.new(0.5, 7.5, 0.5), cf * CFrame.new(o.X, 20, o.Y), wood, Enum.Material.Wood)
		end
		for i = 0, 7 do
			block(parent, "Stair", Vector3.new(4, 1, 2), cf * CFrame.new(-10, 1 + i * 2, -12 + i * 2), wood, woodMat)
		end
		if GameConfig.HalloweenEvent then
			Props.Pumpkin(parent, cf * CFrame.new(3, 16.5, -3), 1.6, true)
			Props.Web(parent, cf * CFrame.new(0, 21.5, 5.1), 4)
		end
	end)

	-- Muro central bajo y ambientación
	block(cover, "MidWall", Vector3.new(30, 5, 3), base * CFrame.new(0, 2.5, 0), theme.Cover, theme.CoverMat)
	for _, side in { -1, 1 } do
		for z = -L / 2 + 50, L / 2 - 50, 90 do
			Props.Lantern(cover, base * CFrame.new(side * (W / 2 - 3), 0, z) * CFrame.Angles(0, if side > 0 then math.rad(90) else math.rad(-90), 0), theme.Accent)
		end
	end
	if GameConfig.HalloweenEvent then
		for _ = 1, 6 do
			local m = block(model, "MistSource", Vector3.new(1, 1, 1), base * CFrame.new(rng:NextNumber(-W / 2, W / 2), 0.5, rng:NextNumber(-L / 2, L / 2)), Color3.new(), Enum.Material.SmoothPlastic)
			m.Transparency = 1
			m.CanCollide = false
			m.CanQuery = false
			Props.Mist(m, Color3.fromRGB(190, 170, 210), 2)
		end
	end

	local spawnA = block(model, "SpawnA", Vector3.new(6, 0.4, 6), base * CFrame.new(0, 0.2, -L / 2 + 15), theme.Accent, Enum.Material.Neon)
	local spawnB = block(model, "SpawnB", Vector3.new(6, 0.4, 6), base * mirror * CFrame.new(0, 0.2, -L / 2 + 15), theme.Accent, Enum.Material.Neon)
	for _, s in { spawnA, spawnB } do
		s.CanCollide = false
		s.CanQuery = false
		s.Transparency = 0.5
	end

	model:SetAttribute("Theme", theme.Name)
	return {
		Id = index,
		Name = theme.Name,
		Model = model,
		SpawnA = CFrame.lookAt(spawnA.Position + Vector3.new(0, 3, 0), spawnB.Position + Vector3.new(0, 3, 0)),
		SpawnB = CFrame.lookAt(spawnB.Position + Vector3.new(0, 3, 0), spawnA.Position + Vector3.new(0, 3, 0)),
		InUse = false,
	}
end

local function padLabel(pad: BasePart, text: string): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 70)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = if GameConfig.HalloweenEvent then Enum.Font.Creepster else Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = pad
	return label
end

local function buildLobby(): Model
	local halloween = GameConfig.HalloweenEvent
	local rng = Random.new(31)
	local terrain = workspace.Terrain
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(320, 12, 320), Enum.Material.Grass)
	terrain:FillBlock(CFrame.new(0, -2, 10), Vector3.new(16, 4, 120), Enum.Material.Cobblestone)
	terrain:FillBlock(CFrame.new(0, -2, -25), Vector3.new(170, 4, 50), Enum.Material.Cobblestone)
	hillsAround(Vector3.zero, 230, 230, Enum.Material.Rock, rng)
	for _, side in { -1, 1 } do
		barrier(lobby, Vector3.new(4, 60, 236), CFrame.new(side * 116, 30, 0))
		barrier(lobby, Vector3.new(236, 60, 4), CFrame.new(0, 30, side * 116))
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.6, 12)
	spawn.CFrame = CFrame.new(0, 0.3, 60)
	spawn.Color = if halloween then Color3.fromRGB(255, 120, 20) else Color3.fromRGB(0, 255, 140)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.3
	spawn.Duration = 0
	spawn.Parent = lobby

	-- Cartel
	local sign = block(lobby, "Sign", Vector3.new(64, 20, 1.5), CFrame.new(0, 18, -100), Color3.fromRGB(15, 12, 18), Enum.Material.Slate)
	block(lobby, "SignPost", Vector3.new(2, 10, 2), CFrame.new(-26, 4, -100), Color3.fromRGB(40, 30, 25), Enum.Material.Wood)
	block(lobby, "SignPost", Vector3.new(2, 10, 2), CFrame.new(26, 4, -100), Color3.fromRGB(40, 30, 25), Enum.Material.Wood)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(1280, 400)
	sg.LightInfluence = 0
	sg.Brightness = 2
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 0.62)
	t.BackgroundTransparency = 1
	t.Font = if halloween then Enum.Font.Creepster else Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = if halloween then Color3.fromRGB(255, 130, 20) else Color3.fromRGB(0, 255, 140)
	t.Text = "SNIPER DUELS"
	t.Parent = sg
	local t2 = t:Clone()
	t2.Position = UDim2.fromScale(0, 0.6)
	t2.Size = UDim2.fromScale(1, 0.36)
	t2.TextColor3 = if halloween then Color3.fromRGB(180, 90, 255) else Color3.new(1, 1, 1)
	t2.Text = if halloween then "~ EDICIÓN HALLOWEEN ~" else "ELITE"
	t2.Parent = sg
	sg.Parent = sign

	-- Sala de espera: cuadrados 1v1 (x2), 2v2 y BOT, cada uno con su cartel
	local padA, padB = Color3.fromRGB(255, 110, 20), Color3.fromRGB(160, 70, 255)
	local function signPost(cf: CFrame, text: string, color: Color3)
		local post = block(lobby, "SignPost", Vector3.new(0.6, 9, 0.6), cf * CFrame.new(0, 4.5, 0), Color3.fromRGB(40, 36, 44), Enum.Material.Metal)
		local board = block(lobby, "SignBoard", Vector3.new(14, 5, 0.6), cf * CFrame.new(0, 11, 0), Color3.fromRGB(18, 14, 22), Enum.Material.SmoothPlastic)
		local _ = post
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.CanvasSize = Vector2.new(560, 200)
			gui.LightInfluence = 0
			gui.Brightness = 2
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.TextColor3 = color
			t.Text = text
			t.Parent = gui
			gui.Parent = board
		end
	end
	for i = 1, 2 do
		local x = -75 + (i - 1) * 36
		block(lobby, "PadA_" .. i, Vector3.new(8, 0.6, 8), CFrame.new(x, 0.3, -10), padA, Enum.Material.Neon)
		block(lobby, "PadB_" .. i, Vector3.new(8, 0.6, 8), CFrame.new(x, 0.3, -40), padB, Enum.Material.Neon)
		block(lobby, "PadLink", Vector3.new(1, 0.2, 22), CFrame.new(x, 0.1, -25), Color3.fromRGB(50, 45, 55), Enum.Material.Metal)
		signPost(CFrame.new(x, 0, -56), "DUELO 1v1", padA)
	end
	-- 2v2: dos cuadrados por equipo
	do
		local x = 10
		for k = 1, 2 do
			block(lobby, "Pad2A_1_" .. k, Vector3.new(7, 0.6, 7), CFrame.new(x + (k - 1.5) * 9, 0.3, -10), padA, Enum.Material.Neon)
			block(lobby, "Pad2B_1_" .. k, Vector3.new(7, 0.6, 7), CFrame.new(x + (k - 1.5) * 9, 0.3, -40), padB, Enum.Material.Neon)
		end
		block(lobby, "PadLink", Vector3.new(1, 0.2, 22), CFrame.new(x, 0.1, -25), Color3.fromRGB(50, 45, 55), Enum.Material.Metal)
		signPost(CFrame.new(x, 0, -56), "DUELO 2v2", padB)
	end
	-- BOT: un cuadrado; al subirte se abre el menú de dificultad
	block(lobby, "BotPad", Vector3.new(9, 0.6, 9), CFrame.new(70, 0.3, -25), Color3.fromRGB(255, 180, 40), Enum.Material.Neon)
	signPost(CFrame.new(70, 0, -40), "VS BOT (solo)", Color3.fromRGB(255, 180, 40))
	if halloween then
		for _, x in { -75, -39, 10, 70 } do
			Props.Pumpkin(lobby, CFrame.new(x + 7, 0, -58), 2.4, true)
			Props.Pumpkin(lobby, CFrame.new(x - 7, 0, -58), 2.4, true)
		end
	end

	-- Decoración
	if halloween then
		Props.Pumpkin(lobby, CFrame.new(-70, 0, -80) * CFrame.Angles(0, math.rad(30), 0), 20, true)
		Props.Pumpkin(lobby, CFrame.new(72, 0, -78) * CFrame.Angles(0, math.rad(-30), 0), 16, true)
		for g = 0, 9 do
			Props.Grave(lobby, CFrame.new(70 + (g % 5) * 5, 0, 30 + (g // 5) * 9), 1)
		end
		Props.Crypt(lobby, CFrame.new(82, 0, 62) * CFrame.Angles(0, math.rad(-90), 0))
		Props.Cauldron(lobby, CFrame.new(-60, 0, 40))
		for c = 0, 5 do
			Props.Candle(lobby, CFrame.new(-60, 0, 40) * CFrame.Angles(0, c * math.rad(60), 0) * CFrame.new(0, 0, 4))
		end
		Props.Scarecrow(lobby, CFrame.new(-85, 0, 10))
		Props.Fence(lobby, Vector3.new(60, 0, 20), Vector3.new(100, 0, 20))
		Props.Web(lobby, CFrame.new(-25, 24, -99.2), 6)
	end
	for _ = 1, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(85, 105)
		Props.DeadTree(lobby, CFrame.new(math.cos(angle) * r, 0, math.sin(angle) * r), rng:NextNumber(22, 36), rng)
	end
	for z = 70, -50, -30 do
		Props.Lantern(lobby, CFrame.new(-10, 0, z))
		Props.Lantern(lobby, CFrame.new(10, 0, z) * CFrame.Angles(0, math.rad(180), 0))
	end

	lobby.Parent = workspace
	return lobby
end

function ArenaService.Start()
	Environment.Apply()

	local lobby = workspace:FindFirstChild("Lobby") :: Model?
	if not lobby then
		lobby = buildLobby()
	end
	local lobbyModel = lobby :: Model
	local spawnPart = lobbyModel:FindFirstChild("LobbySpawn") :: BasePart?
	if spawnPart then
		lobbySpawn = spawnPart.CFrame + Vector3.new(0, 4, 0)
	end
	local i = 1
	while true do
		local a = lobbyModel:FindFirstChild("PadA_" .. i) :: BasePart?
		local b = lobbyModel:FindFirstChild("PadB_" .. i) :: BasePart?
		if not a or not b then
			break
		end
		local label = padLabel(a, "DUELO 1v1")
		padLabel(b, "")
		table.insert(padPairs, { Id = i, A = a, B = b, Label = label })
		table.insert(padGroups, { Id = #padGroups + 1, Mode = "1v1", A = { a }, B = { b }, Label = label })
		i += 1
	end
	i = 1
	while true do
		local a1 = lobbyModel:FindFirstChild("Pad2A_" .. i .. "_1") :: BasePart?
		local a2 = lobbyModel:FindFirstChild("Pad2A_" .. i .. "_2") :: BasePart?
		local b1 = lobbyModel:FindFirstChild("Pad2B_" .. i .. "_1") :: BasePart?
		local b2 = lobbyModel:FindFirstChild("Pad2B_" .. i .. "_2") :: BasePart?
		if not (a1 and a2 and b1 and b2) then
			break
		end
		local label = padLabel(a1, "DUELO 2v2")
		table.insert(padGroups, { Id = #padGroups + 1, Mode = "2v2", A = { a1, a2 }, B = { b1, b2 }, Label = label })
		i += 1
	end
	botPad = lobbyModel:FindFirstChild("BotPad") :: BasePart?
	if botPad then
		padLabel(botPad, "VS BOT")
	end

	local folder = workspace:FindFirstChild("Arenas")
	if folder then
		for idx, m in folder:GetChildren() do
			local sa = m:FindFirstChild("SpawnA") :: BasePart?
			local sb = m:FindFirstChild("SpawnB") :: BasePart?
			if m:IsA("Model") and sa and sb then
				table.insert(arenas, {
					Id = idx,
					Name = m.Name,
					Model = m,
					SpawnA = CFrame.lookAt(sa.Position + Vector3.new(0, 3, 0), sb.Position + Vector3.new(0, 3, 0)),
					SpawnB = CFrame.lookAt(sb.Position + Vector3.new(0, 3, 0), sa.Position + Vector3.new(0, 3, 0)),
					InUse = false,
				})
			end
		end
	else
		local f = Instance.new("Folder")
		f.Name = "Arenas"
		f.Parent = workspace
		for idx = 1, GameConfig.ArenaCount do
			local origin = GameConfig.ArenaOrigin + Vector3.new((idx - 1) * GameConfig.ArenaSpacing, 0, 0)
			local arena = buildArena(idx, origin)
			arena.Model.Parent = f
			table.insert(arenas, arena)
			task.wait() -- repartir la generación en varios frames
		end
	end
end

function ArenaService.Acquire(): Arena?
	local free = {}
	for _, a in arenas do
		if not a.InUse then
			table.insert(free, a)
		end
	end
	if #free == 0 then
		return nil
	end
	local arena = free[math.random(1, #free)]
	arena.InUse = true
	return arena
end

function ArenaService.Release(arena: Arena)
	arena.InUse = false
end

function ArenaService.LobbySpawn(): CFrame
	return lobbySpawn
end

function ArenaService.PadPairs(): { PadPair }
	return padPairs
end

function ArenaService.PadGroups(): { PadGroup }
	return padGroups
end

function ArenaService.BotPad(): BasePart?
	return botPad
end

return ArenaService
