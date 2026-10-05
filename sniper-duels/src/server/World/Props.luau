--!strict
-- Biblioteca de props generados por código (sin assets externos):
-- calabazas con cara, tumbas, árboles muertos, vallas, farolas, criptas,
-- balas de heno, espantapájaros, muros en ruinas, calderos, rocas.
-- Las luces que deben parpadear llevan el tag "Flicker" (lo anima el cliente).

local CollectionService = game:GetService("CollectionService")

local Props = {}

local WOOD = Color3.fromRGB(58, 42, 30)
local DARK_WOOD = Color3.fromRGB(38, 28, 22)
local STONE = Color3.fromRGB(110, 110, 118)
local ORANGE = Color3.fromRGB(230, 115, 20)

local function p(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(part :: any)[k] = v
	end
	part.Parent = parent
	return part
end

local function deco(part: BasePart)
	-- Decoración que no debe bloquear balas ni al jugador
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number, flicker: boolean?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	if flicker then
		l:SetAttribute("BaseBrightness", brightness)
		CollectionService:AddTag(l, "Flicker")
	end
	return l
end

local function mist(parent: BasePart, color: Color3?, rate: number?)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color or Color3.fromRGB(200, 200, 220))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.85), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) })
	e.Lifetime = NumberRange.new(4, 7)
	e.Rate = rate or 1.5
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 10)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-10, 10)
	e.LightInfluence = 0.6
	e.Parent = parent
	return e
end
Props.Mist = mist

-- Calabaza con cara tallada (Jack-o'-lantern)
function Props.Pumpkin(parent: Instance, cf: CFrame, size: number, lit: boolean?): Model
	local m = Instance.new("Model")
	m.Name = "Pumpkin"
	-- Block + SpecialMesh esfera = elipsoide (Shape Ball fuerza tamaño uniforme)
	local body = p(m, {
		Name = "Body",
		Size = Vector3.new(1.15, 0.85, 1.15) * size,
		CFrame = cf * CFrame.new(0, size * 0.4, 0),
		Color = ORANGE,
		Material = Enum.Material.SmoothPlastic,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	-- gajos
	for i = 0, 3 do
		local g = p(m, {
			Name = "Rib",
			Size = Vector3.new(size * 0.35, size * 0.8, size * 1.1),
			CFrame = body.CFrame * CFrame.Angles(0, math.rad(i * 45), 0),
			Color = Color3.fromRGB(205, 95, 15),
			Material = Enum.Material.SmoothPlastic,
		})
		local gm = Instance.new("SpecialMesh")
		gm.MeshType = Enum.MeshType.Sphere
		gm.Parent = g
		deco(g)
	end
	local stem = p(m, {
		Name = "Stem",
		Size = Vector3.new(size * 0.12, size * 0.3, size * 0.12),
		CFrame = body.CFrame * CFrame.new(0, size * 0.45, 0) * CFrame.Angles(0, 0, math.rad(12)),
		Color = Color3.fromRGB(70, 90, 30),
		Material = Enum.Material.Wood,
	})
	deco(stem)
	if lit then
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Front
		face.LightInfluence = 0
		face.Brightness = 3
		face.CanvasSize = Vector2.new(200, 200)
		face.AlwaysOnTop = false
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Text = "▲ ▲\n◥◣◢◤"
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 220, 80)
		t.Parent = face
		local facePart = p(m, {
			Name = "Face",
			Size = Vector3.new(size * 0.7, size * 0.55, 0.05),
			CFrame = body.CFrame * CFrame.new(0, 0, -size * 0.56),
			Transparency = 1,
		})
		deco(facePart)
		face.Parent = facePart
		light(body, Color3.fromRGB(255, 140, 30), size * 4, 2.5, true)
	end
	m.PrimaryPart = body
	m.Parent = parent
	return m
end

-- Lápida con "RIP"
function Props.Grave(parent: Instance, cf: CFrame, scale: number?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Grave"
	local slab = p(m, {
		Name = "Slab",
		Size = Vector3.new(2.4, 3, 0.5) * s,
		CFrame = cf * CFrame.new(0, 1.5 * s, 0) * CFrame.Angles(math.rad(math.random(-6, 6)), 0, math.rad(math.random(-5, 5))),
		Color = STONE,
		Material = Enum.Material.Slate,
	})
	local top = p(m, {
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5 * s, 2.4 * s, 2.4 * s),
		CFrame = slab.CFrame * CFrame.new(0, 1.5 * s, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = STONE,
		Material = Enum.Material.Slate,
	})
	local _ = top
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(200, 240)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.6)
	t.Position = UDim2.fromScale(0, 0.1)
	t.Text = "R.I.P"
	t.Font = Enum.Font.Creepster
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(60, 60, 65)
	t.Parent = gui
	gui.Parent = slab
	local dirt = p(m, {
		Name = "Dirt",
		Size = Vector3.new(2.8, 0.4, 5) * s,
		CFrame = cf * CFrame.new(0, 0.1, -2.6 * s),
		Color = Color3.fromRGB(60, 45, 35),
		Material = Enum.Material.Mud,
	})
	deco(dirt)
	m.Parent = parent
	return m
end

-- Árbol muerto con ramas recursivas
function Props.DeadTree(parent: Instance, cf: CFrame, height: number, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "DeadTree"
	local function branch(base: CFrame, length: number, thickness: number, depth: number)
		local seg = p(m, {
			Name = "Branch",
			Size = Vector3.new(thickness, length, thickness),
			CFrame = base * CFrame.new(0, length / 2, 0),
			Color = if depth == 0 then DARK_WOOD else WOOD,
			Material = Enum.Material.Wood,
		})
		if depth > 0 then
			seg.CanCollide = false
		end
		if depth < 3 then
			local tip = base * CFrame.new(0, length * 0.9, 0)
			local n = if depth == 0 then 3 else 2
			for i = 1, n do
				local yaw = math.rad(i * (360 / n) + rng:NextNumber(-30, 30))
				local pitch = math.rad(rng:NextNumber(25, 50))
				branch(tip * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0), length * rng:NextNumber(0.5, 0.7), thickness * 0.6, depth + 1)
			end
		end
	end
	branch(cf, height * 0.5, height * 0.09, 0)
	m.Parent = parent
	return m
end

function Props.Fence(parent: Instance, from: Vector3, to: Vector3)
	local m = Instance.new("Model")
	m.Name = "Fence"
	local dir = to - from
	local len = dir.Magnitude
	local count = math.max(2, math.floor(len / 4))
	for i = 0, count do
		local pos = from + dir * (i / count)
		p(m, { Name = "Post", Size = Vector3.new(0.4, 3.6, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(math.random(-6, 6))), Color = DARK_WOOD, Material = Enum.Material.Wood })
	end
	for _, h in { 1.2, 2.6 } do
		local mid = (from + to) / 2 + Vector3.new(0, h, 0)
		p(m, { Name = "Rail", Size = Vector3.new(0.2, 0.35, len), CFrame = CFrame.lookAt(mid, to + Vector3.new(0, h, 0)), Color = WOOD, Material = Enum.Material.Wood })
	end
	m.Parent = parent
	return m
end

function Props.Lantern(parent: Instance, cf: CFrame, color: Color3?)
	local m = Instance.new("Model")
	m.Name = "Lantern"
	p(m, { Name = "Pole", Size = Vector3.new(0.35, 9, 0.35), CFrame = cf * CFrame.new(0, 4.5, 0), Color = Color3.fromRGB(25, 25, 28), Material = Enum.Material.Metal })
	p(m, { Name = "Arm", Size = Vector3.new(0.25, 0.25, 1.8), CFrame = cf * CFrame.new(0, 8.8, -0.8), Color = Color3.fromRGB(25, 25, 28), Material = Enum.Material.Metal })
	local lamp = p(m, { Name = "Lamp", Size = Vector3.new(0.8, 1, 0.8), CFrame = cf * CFrame.new(0, 8.2, -1.6), Color = color or Color3.fromRGB(255, 170, 70), Material = Enum.Material.Neon })
	deco(lamp)
	light(lamp, color or Color3.fromRGB(255, 160, 60), 22, 2, true)
	m.Parent = parent
	return m
end

-- Cripta / mausoleo (cobertura grande)
function Props.Crypt(parent: Instance, cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Crypt"
	p(m, { Name = "Base", Size = Vector3.new(12, 1, 10), CFrame = cf * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(80, 80, 86), Material = Enum.Material.Cobblestone })
	for _, x in { -5.2, 5.2 } do
		p(m, { Name = "Wall", Size = Vector3.new(1.4, 9, 9), CFrame = cf * CFrame.new(x, 5, 0), Color = STONE, Material = Enum.Material.Brick })
	end
	p(m, { Name = "Back", Size = Vector3.new(9, 9, 1.4), CFrame = cf * CFrame.new(0, 5, 4), Color = STONE, Material = Enum.Material.Brick })
	local roof = Instance.new("WedgePart")
	roof.Anchored = true
	roof.Size = Vector3.new(13, 3, 5.5)
	roof.CFrame = cf * CFrame.new(0, 11, -2.5)
	roof.Color = Color3.fromRGB(60, 60, 66)
	roof.Material = Enum.Material.Slate
	roof.Parent = m
	local roof2 = roof:Clone()
	roof2.CFrame = cf * CFrame.new(0, 11, 2.5) * CFrame.Angles(0, math.rad(180), 0)
	roof2.Parent = m
	p(m, { Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 1.2, 1.2), CFrame = cf * CFrame.new(-3.6, 5, -4.2) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 150, 155), Material = Enum.Material.Marble })
	p(m, { Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 1.2, 1.2), CFrame = cf * CFrame.new(3.6, 5, -4.2) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 150, 155), Material = Enum.Material.Marble })
	local glow = p(m, { Name = "Glow", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 3, 2), Transparency = 1 })
	deco(glow)
	light(glow, Color3.fromRGB(120, 255, 140), 14, 1.5, true)
	mist(glow, Color3.fromRGB(150, 255, 170), 1)
	m.Parent = parent
	return m
end

function Props.HayBale(parent: Instance, cf: CFrame): Part
	return p(parent, {
		Name = "HayBale",
		Size = Vector3.new(6, 3.4, 3.4),
		CFrame = cf * CFrame.new(0, 1.7, 0),
		Color = Color3.fromRGB(200, 165, 80),
		Material = Enum.Material.Grass,
	})
end

function Props.Scarecrow(parent: Instance, cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Scarecrow"
	p(m, { Name = "Pole", Size = Vector3.new(0.4, 8, 0.4), CFrame = cf * CFrame.new(0, 4, 0), Color = DARK_WOOD, Material = Enum.Material.Wood })
	p(m, { Name = "Arms", Size = Vector3.new(5, 0.35, 0.35), CFrame = cf * CFrame.new(0, 6, 0), Color = DARK_WOOD, Material = Enum.Material.Wood })
	p(m, { Name = "Shirt", Size = Vector3.new(2.2, 2.6, 1), CFrame = cf * CFrame.new(0, 5.4, 0), Color = Color3.fromRGB(110, 50, 40), Material = Enum.Material.Fabric })
	Props.Pumpkin(m, cf * CFrame.new(0, 7, 0), 1.8, true)
	local hat = p(m, { Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3, 3), CFrame = cf * CFrame.new(0, 8.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(30, 25, 25), Material = Enum.Material.Fabric })
	deco(hat)
	local crown = p(m, { Name = "HatCrown", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.4, 1.4), CFrame = cf * CFrame.new(0, 9.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(30, 25, 25), Material = Enum.Material.Fabric })
	deco(crown)
	m.Parent = parent
	return m
end

function Props.RuinWall(parent: Instance, cf: CFrame, width: number, height: number, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "RuinWall"
	local bricks = math.max(1, math.floor(width / 2))
	for i = 0, bricks - 1 do
		local h = height * rng:NextNumber(0.45, 1)
		p(m, {
			Name = "Column",
			Size = Vector3.new(width / bricks, h, 2),
			CFrame = cf * CFrame.new(-width / 2 + (i + 0.5) * width / bricks, h / 2, 0),
			Color = Color3.fromRGB(95 + rng:NextInteger(-10, 10), 80, 75),
			Material = Enum.Material.Brick,
		})
	end
	m.Parent = parent
	return m
end

function Props.Cauldron(parent: Instance, cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Cauldron"
	local pot = p(m, { Name = "Pot", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.4, CFrame = cf * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(25, 25, 28), Material = Enum.Material.Metal })
	local brew = p(m, { Name = "Brew", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.8, 2.8), CFrame = cf * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(90, 255, 60), Material = Enum.Material.Neon })
	deco(brew)
	light(brew, Color3.fromRGB(110, 255, 80), 16, 2, true)
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(120, 255, 90))
	bubbles.Size = NumberSequence.new(0.4, 0)
	bubbles.Lifetime = NumberRange.new(1, 2)
	bubbles.Rate = 8
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.LightEmission = 1
	bubbles.Parent = brew
	mist(brew, Color3.fromRGB(140, 255, 120), 2)
	local _ = pot
	m.Parent = parent
	return m
end

function Props.Rock(parent: Instance, cf: CFrame, size: Vector3, color: Color3?): Part
	local r = p(parent, {
		Name = "Rock",
		Size = size,
		CFrame = cf * CFrame.new(0, size.Y / 2 - 0.4, 0) * CFrame.Angles(math.rad(math.random(-8, 8)), math.rad(math.random(0, 360)), math.rad(math.random(-8, 8))),
		Color = color or Color3.fromRGB(85, 82, 80),
		Material = Enum.Material.Rock,
	})
	return r
end

function Props.Candle(parent: Instance, cf: CFrame)
	local c = p(parent, { Name = "Candle", Size = Vector3.new(0.3, 0.8, 0.3), CFrame = cf * CFrame.new(0, 0.4, 0), Color = Color3.fromRGB(240, 230, 200), Material = Enum.Material.SmoothPlastic })
	deco(c)
	local flame = p(parent, { Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.25, 0.4, 0.25), CFrame = cf * CFrame.new(0, 0.95, 0), Color = Color3.fromRGB(255, 190, 80), Material = Enum.Material.Neon })
	deco(flame)
	light(flame, Color3.fromRGB(255, 170, 70), 8, 1.2, true)
end

-- Telaraña plana (decal hecho con líneas)
function Props.Web(parent: Instance, cf: CFrame, size: number)
	local holder = p(parent, { Name = "Web", Size = Vector3.new(size, size, 0.05), CFrame = cf, Transparency = 1 })
	deco(holder)
	for i = 0, 3 do
		local strand = p(parent, { Name = "Strand", Size = Vector3.new(0.04, size * 1.3, 0.04), CFrame = cf * CFrame.Angles(0, 0, math.rad(i * 45)), Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
		deco(strand)
	end
	for r = 1, 3 do
		for i = 0, 7 do
			local a1 = math.rad(i * 45)
			local rad = size * 0.2 * r
			local mid = Vector3.new(math.cos(a1 + math.rad(22.5)), math.sin(a1 + math.rad(22.5)), 0) * rad * 0.92
			local strand = p(parent, { Name = "Ring", Size = Vector3.new(rad * 0.77, 0.03, 0.03), CFrame = cf * CFrame.new(mid) * CFrame.Angles(0, 0, a1 + math.rad(112.5)), Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.SmoothPlastic, Transparency = 0.35 })
			deco(strand)
		end
	end
end

return Props
