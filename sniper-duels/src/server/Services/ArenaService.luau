--!strict
-- Genera el lobby y un pool de arenas simétricas (justas para ambos lados).
-- Si ya existe una carpeta "Arenas" o "Lobby" en Workspace hecha a mano,
-- se respeta y no se genera nada: así un builder puede reemplazar el mapa.
--
-- Formato de arena manual: Model con Parts "SpawnA" y "SpawnB".
-- Formato de lobby manual: Model con Parts "LobbySpawn" y pares "PadA_n"/"PadB_n".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

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

local arenas: { Arena } = {}
local padPairs: { PadPair } = {}
local lobbySpawn = CFrame.new(0, 5, 0)

local THEMES = {
	{
		Name = "Lost Hill",
		Ground = Color3.fromRGB(58, 56, 54),
		GroundMat = Enum.Material.Basalt,
		Cover = Color3.fromRGB(92, 88, 82),
		CoverMat = Enum.Material.Rock,
		Accent = Color3.fromRGB(0, 255, 140),
	},
	{
		Name = "Dunas",
		Ground = Color3.fromRGB(214, 186, 132),
		GroundMat = Enum.Material.Sand,
		Cover = Color3.fromRGB(170, 140, 100),
		CoverMat = Enum.Material.Sandstone,
		Accent = Color3.fromRGB(255, 140, 40),
	},
	{
		Name = "Tundra",
		Ground = Color3.fromRGB(235, 240, 245),
		GroundMat = Enum.Material.Snow,
		Cover = Color3.fromRGB(160, 190, 210),
		CoverMat = Enum.Material.Ice,
		Accent = Color3.fromRGB(80, 180, 255),
	},
	{
		Name = "Neón",
		Ground = Color3.fromRGB(20, 20, 28),
		GroundMat = Enum.Material.SmoothPlastic,
		Cover = Color3.fromRGB(35, 35, 50),
		CoverMat = Enum.Material.Metal,
		Accent = Color3.fromRGB(255, 0, 170),
	},
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

local function buildArena(index: number, origin: Vector3): Arena
	local theme = THEMES[(index - 1) % #THEMES + 1]
	local rng = Random.new(index * 7919)
	local model = Instance.new("Model")
	model.Name = string.format("Arena_%02d_%s", index, theme.Name)

	local W, L = 140, 360
	local base = CFrame.new(origin)
	block(model, "Ground", Vector3.new(W, 4, L), base * CFrame.new(0, -2, 0), theme.Ground, theme.GroundMat)

	-- Muros perimetrales
	local wallH = 60
	for _, side in { -1, 1 } do
		block(model, "WallX", Vector3.new(4, wallH, L), base * CFrame.new(side * (W / 2 + 2), wallH / 2, 0), theme.Cover, theme.CoverMat)
		block(model, "WallZ", Vector3.new(W + 8, wallH, 4), base * CFrame.new(0, wallH / 2, side * (L / 2 + 2)), theme.Cover, theme.CoverMat)
	end
	local ceiling = block(model, "Ceiling", Vector3.new(W + 8, 2, L + 8), base * CFrame.new(0, wallH + 1, 0), theme.Cover, theme.CoverMat)
	ceiling.Transparency = 1
	ceiling.CanQuery = false

	-- Cobertura simétrica: se genera la mitad A y se refleja 180° para B
	local half = Instance.new("Folder")
	half.Name = "Cover"
	half.Parent = model
	local mirror = CFrame.Angles(0, math.pi, 0)
	local function coverPair(size: Vector3, localCf: CFrame, name: string)
		block(half, name, size, base * localCf, theme.Cover, theme.CoverMat)
		block(half, name, size, base * mirror * localCf, theme.Cover, theme.CoverMat)
	end

	-- Bunker de spawn
	coverPair(Vector3.new(26, 7, 3), CFrame.new(0, 3.5, -L / 2 + 30), "SpawnWall")
	coverPair(Vector3.new(3, 7, 14), CFrame.new(-14, 3.5, -L / 2 + 24), "SpawnWall")
	coverPair(Vector3.new(3, 7, 14), CFrame.new(14, 3.5, -L / 2 + 24), "SpawnWall")

	-- Cobertura media procedural
	for _ = 1, 9 do
		local h = rng:NextInteger(4, 14)
		local size = Vector3.new(rng:NextInteger(4, 16), h, rng:NextInteger(3, 10))
		local x = rng:NextNumber(-W / 2 + 10, W / 2 - 10)
		local z = rng:NextNumber(-L / 2 + 50, -14)
		coverPair(size, CFrame.new(x, h / 2, z) * CFrame.Angles(0, math.rad(rng:NextInteger(-30, 30)), 0), "Cover")
	end
	-- Torre de francotirador (alto riesgo / alta recompensa)
	coverPair(Vector3.new(10, 1, 10), CFrame.new(W / 2 - 14, 16, -L / 2 + 70), "TowerFloor")
	coverPair(Vector3.new(1.5, 16, 1.5), CFrame.new(W / 2 - 18, 8, -L / 2 + 66), "TowerLeg")
	coverPair(Vector3.new(1.5, 16, 1.5), CFrame.new(W / 2 - 10, 8, -L / 2 + 74), "TowerLeg")
	coverPair(Vector3.new(10, 3.5, 1), CFrame.new(W / 2 - 14, 18.25, -L / 2 + 74.5), "TowerRail")
	for i = 0, 7 do
		coverPair(Vector3.new(4, 1, 2), CFrame.new(W / 2 - 24, 1 + i * 2, -L / 2 + 58 + i * 2), "Stair")
	end
	-- Muro central bajo para cruzar
	block(half, "MidWall", Vector3.new(30, 5, 3), base * CFrame.new(0, 2.5, 0), theme.Cover, theme.CoverMat)

	-- Líneas de neón de acento
	for _, side in { -1, 1 } do
		local strip = block(model, "Accent", Vector3.new(0.4, 0.4, L), base * CFrame.new(side * (W / 2 - 0.2), 0.2, 0), theme.Accent, Enum.Material.Neon)
		strip.CanCollide = false
	end

	local spawnA = block(model, "SpawnA", Vector3.new(6, 1, 6), base * CFrame.new(0, 0.5, -L / 2 + 15), theme.Accent, Enum.Material.Neon)
	local spawnB = block(model, "SpawnB", Vector3.new(6, 1, 6), base * mirror * CFrame.new(0, 0.5, -L / 2 + 15), theme.Accent, Enum.Material.Neon)
	spawnA.CanCollide = false
	spawnB.CanCollide = false
	spawnA.Transparency = 0.6
	spawnB.Transparency = 0.6

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
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	gui.Parent = pad
	return label
end

local function buildLobby(): Model
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	block(lobby, "Floor", Vector3.new(220, 4, 220), CFrame.new(0, -2, 0), Color3.fromRGB(32, 34, 40), Enum.Material.Concrete)
	for _, side in { -1, 1 } do
		block(lobby, "Wall", Vector3.new(4, 30, 220), CFrame.new(side * 112, 15, 0), Color3.fromRGB(24, 26, 30), Enum.Material.Concrete)
		block(lobby, "Wall", Vector3.new(228, 30, 4), CFrame.new(0, 15, side * 112), Color3.fromRGB(24, 26, 30), Enum.Material.Concrete)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 60)
	spawn.Color = Color3.fromRGB(0, 255, 140)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Parent = lobby

	-- Cartel
	local sign = block(lobby, "Sign", Vector3.new(60, 16, 1), CFrame.new(0, 14, -100), Color3.fromRGB(15, 15, 18), Enum.Material.SmoothPlastic)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(1200, 320)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(0, 255, 140)
	t.Text = "SNIPER DUELS: ELITE"
	t.Parent = sg
	sg.Parent = sign

	-- Pares de pads de duelo
	for i = 1, 4 do
		local x = -60 + (i - 1) * 40
		local a = block(lobby, "PadA_" .. i, Vector3.new(8, 0.6, 8), CFrame.new(x, 0.3, -10), Color3.fromRGB(255, 70, 90), Enum.Material.Neon)
		local b = block(lobby, "PadB_" .. i, Vector3.new(8, 0.6, 8), CFrame.new(x, 0.3, -40), Color3.fromRGB(80, 160, 255), Enum.Material.Neon)
		block(lobby, "PadLink", Vector3.new(1, 0.2, 22), CFrame.new(x, 0.1, -25), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	end

	lobby.Parent = workspace
	return lobby
end

function ArenaService.Start()
	-- Iluminación ambiente
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.28
	atmo.Haze = 1.2
	atmo.Color = Color3.fromRGB(200, 190, 180)
	atmo.Parent = Lighting
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end

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
		i += 1
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
		for idx = 1, GameConfig.ArenaCount do
			local origin = GameConfig.ArenaOrigin + Vector3.new((idx - 1) * GameConfig.ArenaSpacing, 0, 0)
			local arena = buildArena(idx, origin)
			arena.Model.Parent = f
			table.insert(arenas, arena)
		end
		f.Parent = workspace
	end
end

function ArenaService.Acquire(): Arena?
	-- Elegir una arena libre al azar para variar mapas
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

return ArenaService
