--!strict
-- Ambientación solo visual (no afecta a la jugabilidad ni a la red):
--  * luces con parpadeo de vela (tag "Flicker")
--  * bandadas de murciélagos volando alrededor de la cámara
--  * brasas / luciérnagas flotando cerca del jugador
--  * relámpagos lejanos de vez en cuando
-- Todo se apaga si el evento de Halloween está desactivado (salvo el parpadeo).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)
local ClientState = require(script.Parent.Parent.ClientState)
local EffectsController = require(script.Parent.EffectsController)

local camera = workspace.CurrentCamera

local AmbientController = {}

local folder = Instance.new("Folder")
folder.Name = "Ambient"
folder.Parent = workspace

-- Parpadeo -------------------------------------------------------------------
local flickers: { [PointLight]: number } = {}
local function addFlicker(inst: Instance)
	if inst:IsA("PointLight") then
		flickers[inst] = math.random() * 100
	end
end
local function updateFlicker()
	local t = os.clock()
	for light, seed in flickers do
		if not light.Parent then
			flickers[light] = nil
		else
			local base = (light:GetAttribute("BaseBrightness") :: number?) or 2
			local n = math.noise(t * 3, seed) * 0.5 + math.noise(t * 11, seed + 7) * 0.25
			light.Brightness = math.max(0, base * (0.8 + n))
		end
	end
end

-- Murciélagos ----------------------------------------------------------------
type Bat = { Model: Model, Body: BasePart, L: BasePart, R: BasePart, Phase: number, Radius: number, Height: number, Speed: number, Center: Vector3 }
local bats: { Bat } = {}

local function makeBat(): Bat
	local m = Instance.new("Model")
	m.Name = "Bat"
	local function piece(size: Vector3): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = Color3.fromRGB(15, 10, 15)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = m
		return p
	end
	local body = piece(Vector3.new(0.5, 0.45, 0.9))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	local l = piece(Vector3.new(1.6, 0.05, 0.8))
	local r = piece(Vector3.new(1.6, 0.05, 0.8))
	for _, x in { -0.12, 0.12 } do
		local eye = piece(Vector3.new(0.08, 0.08, 0.08))
		eye.Color = Color3.fromRGB(255, 60, 40)
		eye.Material = Enum.Material.Neon
		eye:SetAttribute("EyeX", x)
	end
	m.Parent = folder
	return {
		Model = m,
		Body = body,
		L = l,
		R = r,
		Phase = math.random() * math.pi * 2,
		Radius = 25 + math.random() * 45,
		Height = 22 + math.random() * 25,
		Speed = 0.4 + math.random() * 0.5,
		Center = Vector3.zero,
	}
end

local function updateBats(dt: number)
	local camPos = camera.CFrame.Position
	local t = os.clock()
	for i, bat in bats do
		-- El centro sigue a la cámara con retraso
		bat.Center = bat.Center:Lerp(camPos, math.clamp(dt * 0.3, 0, 1))
		bat.Phase += dt * bat.Speed
		local a = bat.Phase
		local pos = bat.Center + Vector3.new(math.cos(a) * bat.Radius, bat.Height + math.sin(a * 2.3 + i) * 4, math.sin(a) * bat.Radius * 0.7)
		local ahead = bat.Center + Vector3.new(math.cos(a + 0.05) * bat.Radius, bat.Height + math.sin((a + 0.05) * 2.3 + i) * 4, math.sin(a + 0.05) * bat.Radius * 0.7)
		local cf = CFrame.lookAt(pos, ahead)
		local flap = math.sin(t * 22 + i) * 0.9
		bat.Body.CFrame = cf
		bat.L.CFrame = cf * CFrame.new(-0.25, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.8, 0, 0)
		bat.R.CFrame = cf * CFrame.new(0.25, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.8, 0, 0)
		for _, c in bat.Model:GetChildren() do
			local ex = c:GetAttribute("EyeX") :: number?
			if ex and c:IsA("BasePart") then
				c.CFrame = cf * CFrame.new(ex, 0.08, -0.42)
			end
		end
	end
end

-- Brasas / luciérnagas que siguen al jugador ---------------------------------
local function makeEmbers(): BasePart
	local p = Instance.new("Part")
	p.Name = "EmberVolume"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(90, 1, 90)
	p.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 160, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
	})
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(5, 9)
	e.Rate = 18
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 0.6, 0)
	e.Parent = p
	return p
end

-- Relámpagos -----------------------------------------------------------------
local lightningBusy = false
local function lightning()
	if lightningBusy then
		return
	end
	lightningBusy = true
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Lightning"
	cc.Brightness = 0
	cc.TintColor = Color3.fromRGB(220, 220, 255)
	cc.Parent = Lighting
	local function flash(strength: number, time: number)
		cc.Brightness = strength
		TweenService:Create(cc, TweenInfo.new(time), { Brightness = 0 }):Play()
		task.wait(time)
	end
	flash(0.35, 0.08)
	task.wait(0.06)
	flash(0.22, 0.25)
	-- Trueno con retraso (distancia)
	task.delay(math.random(8, 20) / 10, function()
		EffectsController.PlaySound("Thunder", 0.5)
		EffectsController.Shake(0.15)
	end)
	cc:Destroy()
	lightningBusy = false
end


-- Fantasmas ------------------------------------------------------------------
-- Vagan alrededor del jugador (solo visual, cada cliente los suyos). Uno de
-- ellos es "El Comandante": fantasma barbudo con gorra militar y puro.

type Ghost = { Model: Model, Body: BasePart, Center: Vector3, Angle: number, Radius: number, Height: number, Speed: number, NextWhoosh: number }
local ghosts: { Ghost } = {}

local function ghostPart(m: Model, size: Vector3, color: Color3, mat: Enum.Material, transparency: number, sphere: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Transparency = transparency
	if sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = m
	return p
end

local function makeGhost(commander: boolean): Ghost
	local m = Instance.new("Model")
	m.Name = if commander then "ElComandante" else "Ghost"
	local white = Color3.fromRGB(225, 235, 255)
	local body = ghostPart(m, Vector3.new(3, 4.2, 3), white, Enum.Material.Neon, 0.45, true)
	body.Name = "Body"
	-- Cola ondulante
	for i = 1, 3 do
		local tail = ghostPart(m, Vector3.new(2.4 - i * 0.5, 1.6, 2.4 - i * 0.5), white, Enum.Material.Neon, 0.5 + i * 0.12, true)
		tail.Name = "Tail" .. i
	end
	-- Cara
	for _, x in { -0.5, 0.5 } do
		local eye = ghostPart(m, Vector3.new(0.5, 0.75, 0.2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 0, true)
		eye.Name = "Eye"
		eye:SetAttribute("Offset", CFrame.new(x, 0.7, -1.35))
	end
	local mouth = ghostPart(m, Vector3.new(0.6, 0.9, 0.2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 0, true)
	mouth.Name = "Mouth"
	mouth:SetAttribute("Offset", CFrame.new(0, -0.3, -1.4))
	-- Brazos
	for _, x in { -1.7, 1.7 } do
		local arm = ghostPart(m, Vector3.new(1.4, 0.6, 0.6), white, Enum.Material.Neon, 0.5, true)
		arm.Name = "Arm"
		arm:SetAttribute("Offset", CFrame.new(x, 0.2, -0.4) * CFrame.Angles(0, 0, math.rad(if x > 0 then -25 else 25)))
	end
	if commander then
		local olive = Color3.fromRGB(70, 85, 50)
		local cap = ghostPart(m, Vector3.new(2.4, 1, 2.4), olive, Enum.Material.Fabric, 0.15)
		cap.Name = "Cap"
		cap:SetAttribute("Offset", CFrame.new(0, 2.15, 0))
		local visor = ghostPart(m, Vector3.new(2, 0.15, 1), olive, Enum.Material.Fabric, 0.15)
		visor.Name = "Visor"
		visor:SetAttribute("Offset", CFrame.new(0, 1.65, -1.4) * CFrame.Angles(math.rad(-10), 0, 0))
		local star = ghostPart(m, Vector3.new(0.4, 0.4, 0.1), Color3.fromRGB(255, 60, 60), Enum.Material.Neon, 0)
		star.Name = "Star"
		star:SetAttribute("Offset", CFrame.new(0, 2.2, -1.22))
		local beard = ghostPart(m, Vector3.new(2.2, 1.6, 1.2), Color3.fromRGB(60, 60, 65), Enum.Material.Fabric, 0.25, true)
		beard.Name = "Beard"
		beard:SetAttribute("Offset", CFrame.new(0, -0.7, -1.0))
		local cigar = ghostPart(m, Vector3.new(0.18, 0.18, 1), Color3.fromRGB(110, 70, 40), Enum.Material.Wood, 0)
		cigar.Name = "Cigar"
		cigar:SetAttribute("Offset", CFrame.new(0.4, -0.3, -1.9) * CFrame.Angles(0, math.rad(-15), 0))
		local tip = ghostPart(m, Vector3.new(0.2, 0.2, 0.15), Color3.fromRGB(255, 120, 30), Enum.Material.Neon, 0)
		tip.Name = "CigarTip"
		tip:SetAttribute("Offset", CFrame.new(0.53, -0.3, -2.4))
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
		smoke.Size = NumberSequence.new(0.3, 1.5)
		smoke.Transparency = NumberSequence.new(0.5, 1)
		smoke.Lifetime = NumberRange.new(1, 2)
		smoke.Rate = 6
		smoke.Speed = NumberRange.new(0.5, 1)
		smoke.Acceleration = Vector3.new(0, 1.5, 0)
		smoke.Parent = tip
		-- Cartel flotante con su apodo
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(200, 30)
		bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.MaxDistance = 70
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Creepster
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(170, 255, 170)
		t.TextStrokeTransparency = 0.4
		t.Text = "El Comandante"
		t.Parent = bb
		bb.Parent = body
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 210, 255)
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = body
	local wisps = Instance.new("ParticleEmitter")
	wisps.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	wisps.Color = ColorSequence.new(Color3.fromRGB(190, 220, 255))
	wisps.LightEmission = 1
	wisps.Size = NumberSequence.new(0.4, 0)
	wisps.Transparency = NumberSequence.new(0.3, 1)
	wisps.Lifetime = NumberRange.new(1, 2)
	wisps.Rate = 10
	wisps.Speed = NumberRange.new(0.2, 1)
	wisps.Parent = body
	m.Parent = folder
	return {
		Model = m,
		Body = body,
		Center = camera.CFrame.Position,
		Angle = math.random() * math.pi * 2,
		Radius = 30 + math.random() * 50,
		Height = 5 + math.random() * 10,
		Speed = (0.15 + math.random() * 0.2) * (if math.random() < 0.5 then -1 else 1),
		NextWhoosh = 0,
	}
end

local function placeGhost(g: Ghost, cf: CFrame, t: number, i: number)
	g.Body.CFrame = cf
	for _, p in g.Model:GetChildren() do
		if p:IsA("BasePart") and p ~= g.Body then
			local offset = p:GetAttribute("Offset") :: CFrame?
			if offset then
				p.CFrame = cf * offset
			elseif string.sub(p.Name, 1, 4) == "Tail" then
				local n = tonumber(string.sub(p.Name, 5)) or 1
				p.CFrame = cf * CFrame.new(math.sin(t * 3 + n + i) * 0.4 * n, -1.6 - n * 1.1, 0.3 * n)
			end
		end
	end
end

local function updateGhosts(dt: number)
	local camPos = camera.CFrame.Position
	local t = os.clock()
	for i, g in ghosts do
		g.Center = g.Center:Lerp(camPos, math.clamp(dt * 0.15, 0, 1))
		g.Angle += dt * g.Speed
		local pos = g.Center + Vector3.new(math.cos(g.Angle) * g.Radius, g.Height + math.sin(t * 1.3 + i) * 1.5, math.sin(g.Angle) * g.Radius)
		local tangent = Vector3.new(-math.sin(g.Angle), 0, math.cos(g.Angle)) * math.sign(g.Speed)
		-- Mirar al jugador de vez en cuando (da más miedo)
		local lookAt = if math.sin(t * 0.4 + i) > 0.3 then camPos else pos + tangent
		placeGhost(g, CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z)), t, i)
		if (pos - camPos).Magnitude < 28 and t > g.NextWhoosh then
			g.NextWhoosh = t + 12
			EffectsController.PlaySound("GhostWhoosh", 0.5, pos)
		end
	end
end

-- Susto: un fantasma se lanza contra la cámara (solo en el lobby)
local scaring = false
local function jumpscare(gui: ScreenGui)
	if scaring then
		return
	end
	scaring = true
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 100
	overlay.Parent = gui
	local face = Instance.new("Frame")
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0.05, 0.05)
	face.SizeConstraint = Enum.SizeConstraint.RelativeYY
	face.BackgroundColor3 = Color3.fromRGB(235, 240, 255)
	face.ZIndex = 101
	face.Parent = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = face
	local function hole(x: number, y: number, w: number, h: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.ZIndex = 102
		f.Parent = face
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	hole(0.32, 0.38, 0.18, 0.26)
	hole(0.68, 0.38, 0.18, 0.26)
	hole(0.5, 0.72, 0.24, 0.3)
	local id = (GameConfig.Sounds :: any).Jumpscare
	if id and id ~= "" then
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Volume = 0.9
		snd.Parent = game:GetService("SoundService")
		snd:Play()
		task.delay(1.6, function()
			snd:Destroy() -- el audio es largo: solo el golpe inicial
		end)
	end
	EffectsController.Shake(3)
	TweenService:Create(face, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(1.6, 1.6) }):Play()
	task.wait(0.55)
	TweenService:Create(face, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	for _, c in face:GetChildren() do
		if c:IsA("Frame") then
			TweenService:Create(c, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		end
	end
	task.wait(0.6)
	overlay:Destroy()
	scaring = false
end

local function startAmbience()
	local id = (GameConfig.Sounds :: any).Ambience
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "HalloweenAmbience"
	s.SoundId = id
	s.Looped = true
	s.Volume = 0.35
	s.Parent = game:GetService("SoundService")
	s:Play()
	-- Bajar el ambiente con la mira puesta para concentrarse
	RunService.Heartbeat:Connect(function()
		s.Volume = if ClientState.Scoped then 0.12 else 0.35
	end)
end


-- El Comandante en el cielo ------------------------------------------------------
-- Cara gigante y espectral (gorra verde, barba gris, cejas espesas, ojos
-- hundidos) que aparece entre las estrellas unos segundos cada pocos minutos,
-- como en el cuadro. Solo visual.

local skyFace: Model? = nil
local skyFaceParts: { { Part: BasePart, Base: number } } = {}

local function facePart(m: Model, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, transparency: number, sphere: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = 1
	if sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p:SetAttribute("Offset", offset)
	p.Parent = m
	table.insert(skyFaceParts, { Part = p, Base = transparency })
	return p
end

local function buildSkyFace(): Model
	local m = Instance.new("Model")
	m.Name = "ElComandanteSky"
	local S = 1 -- escala base (la cara mide ~60 studs)
	local skin = Color3.fromRGB(215, 190, 170)
	local shadow = Color3.fromRGB(120, 95, 90)
	local grey = Color3.fromRGB(190, 190, 195)
	local olive = Color3.fromRGB(70, 92, 55)
	-- Cara (elipsoide) y mejillas hundidas
	facePart(m, "Head", Vector3.new(40, 52, 36) * S, CFrame.new(0, 0, 0), skin, Enum.Material.SmoothPlastic, 0.35, true)
	facePart(m, "CheekL", Vector3.new(14, 12, 10) * S, CFrame.new(-11, -8, -14), shadow, Enum.Material.SmoothPlastic, 0.6, true)
	facePart(m, "CheekR", Vector3.new(14, 12, 10) * S, CFrame.new(11, -8, -14), shadow, Enum.Material.SmoothPlastic, 0.6, true)
	-- Gorra verde con visera
	facePart(m, "Cap", Vector3.new(44, 16, 40) * S, CFrame.new(0, 22, 1), olive, Enum.Material.Fabric, 0.25, true)
	facePart(m, "CapBand", Vector3.new(43, 5, 39) * S, CFrame.new(0, 16, 1), Color3.fromRGB(55, 72, 42), Enum.Material.Fabric, 0.25, true)
	facePart(m, "Visor", Vector3.new(30, 2, 14) * S, CFrame.new(0, 15, -20) * CFrame.Angles(math.rad(-12), 0, 0), olive, Enum.Material.Fabric, 0.25)
	-- Cejas gruesas y ojos hundidos
	for _, x in { -8, 8 } do
		facePart(m, "Brow", Vector3.new(13, 3.5, 4) * S, CFrame.new(x, 9, -17) * CFrame.Angles(0, 0, math.rad(if x < 0 then 8 else -8)), Color3.fromRGB(80, 80, 85), Enum.Material.Fabric, 0.3)
		facePart(m, "Socket", Vector3.new(11, 7, 6) * S, CFrame.new(x, 4, -16.5), Color3.fromRGB(60, 45, 50), Enum.Material.SmoothPlastic, 0.4, true)
		facePart(m, "Eye", Vector3.new(4, 4, 3) * S, CFrame.new(x, 4, -19), Color3.fromRGB(25, 20, 20), Enum.Material.SmoothPlastic, 0.1, true)
		facePart(m, "Glint", Vector3.new(1.2, 1.2, 1.2) * S, CFrame.new(x - 1, 5, -20.3), Color3.fromRGB(255, 255, 230), Enum.Material.Neon, 0.1, true)
	end
	-- Nariz y barba (varias esferas grises)
	facePart(m, "Nose", Vector3.new(8, 13, 9) * S, CFrame.new(0, -2, -18) * CFrame.Angles(math.rad(10), 0, 0), skin, Enum.Material.SmoothPlastic, 0.35, true)
	local beard = { { 0, -16, -14, 26, 20, 16 }, { -10, -12, -12, 16, 14, 12 }, { 10, -12, -12, 16, 14, 12 }, { 0, -26, -10, 20, 16, 12 }, { -6, -30, -8, 12, 12, 10 }, { 6, -30, -8, 12, 12, 10 } }
	for i, b in beard do
		facePart(m, "Beard" .. i, Vector3.new(b[4], b[5], b[6]) * S, CFrame.new(b[1], b[2], b[3]), grey, Enum.Material.Fabric, 0.3, true)
	end
	facePart(m, "Mustache", Vector3.new(16, 4, 5) * S, CFrame.new(0, -9, -17), grey, Enum.Material.Fabric, 0.3, true)
	-- Halo espectral
	local halo = facePart(m, "Halo", Vector3.new(70, 80, 10) * S, CFrame.new(0, 0, 12), Color3.fromRGB(200, 220, 255), Enum.Material.Neon, 0.92, true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 210, 255)
	light.Range = 60
	light.Brightness = 0.6
	light.Parent = halo
	m.Parent = folder
	return m
end

local skyFaceVisible = 0 -- 0..1
local skyFaceTarget = 0
local skyAnchor = Vector3.zero

local function updateSkyFace(dt: number)
	local m = skyFace
	if not m then
		return
	end
	skyFaceVisible += (skyFaceTarget - skyFaceVisible) * math.clamp(dt * 0.6, 0, 1)
	if skyFaceVisible < 0.01 and skyFaceTarget == 0 then
		for _, e in skyFaceParts do
			e.Part.Transparency = 1
		end
		return
	end
	local camPos = camera.CFrame.Position
	-- Aparece lejos, alto, y mira al jugador
	if skyFaceTarget > 0 and skyAnchor == Vector3.zero then
		local flat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		flat = if flat.Magnitude > 0 then flat.Unit else Vector3.new(0, 0, -1)
		skyAnchor = camPos + flat * 260 + Vector3.new(0, 130, 0)
	end
	local t = os.clock()
	local pos = skyAnchor + Vector3.new(math.sin(t * 0.3) * 4, math.sin(t * 0.5) * 3, 0)
	local cf = CFrame.lookAt(pos, Vector3.new(camPos.X, camPos.Y, camPos.Z)) * CFrame.Angles(0, math.rad(180), 0)
	for _, e in skyFaceParts do
		local offset = e.Part:GetAttribute("Offset") :: CFrame
		e.Part.CFrame = cf * offset
		local flicker = 0.9 + math.noise(t * 2, (e.Part.Position.X % 7)) * 0.2
		e.Part.Transparency = 1 - (1 - e.Base) * skyFaceVisible * flicker
	end
end

local function showSkyFace(seconds: number)
	skyAnchor = Vector3.zero
	skyFaceTarget = 1
	EffectsController.PlaySound("GhostWhoosh", 0.7)
	task.delay(seconds, function()
		skyFaceTarget = 0
	end)
end
AmbientController.ShowCommander = showSkyFace

function AmbientController.Start()
	for _, l in CollectionService:GetTagged("Flicker") do
		addFlicker(l)
	end
	CollectionService:GetInstanceAddedSignal("Flicker"):Connect(addFlicker)

	local halloween = GameConfig.HalloweenEvent
	local embers: BasePart? = nil
	if halloween then
		for _ = 1, 14 do
			table.insert(bats, makeBat())
		end
		embers = makeEmbers()
		for i = 1, 6 do
			table.insert(ghosts, makeGhost(i == 1))
		end
		startAmbience()
		skyFace = buildSkyFace()
		task.spawn(function()
			task.wait(25)
			while true do
				if not ClientState.Scoped then
					showSkyFace(18)
				end
				task.wait(math.random(120, 200))
			end
		end)
		-- Sustos de vez en cuando, nunca durante un duelo
		task.spawn(function()
			local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local scareGui = Instance.new("ScreenGui")
			scareGui.Name = "Jumpscare"
			scareGui.IgnoreGuiInset = true
			scareGui.DisplayOrder = 100
			scareGui.ResetOnSpawn = false
			scareGui.Parent = playerGui
			task.wait(60)
			while true do
				if not ClientState.Duel and not ClientState.Armed then
					jumpscare(scareGui)
				end
				task.wait(math.random(150, 300))
			end
		end)
		task.spawn(function()
			while true do
				task.wait(math.random(18, 45))
				-- Nada de destellos con la mira puesta: molestaría al apuntar
				if not ClientState.Scoped then
					lightning()
				end
			end
		end)
	end

	local frame = 0
	RunService.RenderStepped:Connect(function(dt)
		frame += 1
		if frame % 2 == 0 then
			updateFlicker()
		end
		if halloween then
			updateBats(dt)
			updateGhosts(dt)
			updateSkyFace(dt)
			if embers then
				local cp = camera.CFrame.Position
				embers.CFrame = CFrame.new(cp.X, cp.Y - 4, cp.Z)
				local e = embers:FindFirstChildOfClass("ParticleEmitter")
				if e then
					e.Enabled = not ClientState.Scoped
				end
			end
		end
	end)
end

return AmbientController
