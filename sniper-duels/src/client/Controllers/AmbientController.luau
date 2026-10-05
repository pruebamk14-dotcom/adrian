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
