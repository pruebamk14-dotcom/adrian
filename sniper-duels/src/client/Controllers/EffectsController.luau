--!strict
-- Efectos visuales: trazadores balísticos, fogonazo con humo, casquillos,
-- impactos con polvo y chispas, fantasma al morir (Halloween), temblor de
-- cámara, sonidos y destello de mira (scope glint) de los rivales.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local Ballistics = require(Shared.Ballistics)
local Net = require(Shared.Net)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local ClientState = require(script.Parent.Parent.ClientState)

local EffectsController = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientFX"
fxFolder.Parent = workspace

-- Temblor de cámara --------------------------------------------------------
local shake = 0
local appliedShake = CFrame.identity
function EffectsController.Shake(amount: number)
	shake = math.min(shake + amount, 3)
end

-- Utilidades -----------------------------------------------------------------

local function fxPart(cf: CFrame, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size or Vector3.one * 0.2
	p.CFrame = cf
	p.Parent = fxFolder
	return p
end

local function burst(at: CFrame, props: { [string]: any }, count: number, life: number?)
	local holder = fxPart(at)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, life or 3)
end

function EffectsController.PlaySound(name: string, volume: number?, at: Vector3?)
	local id = (GameConfig.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	if at then
		local a = fxPart(CFrame.new(at))
		s.RollOffMaxDistance = 1500
		s.Parent = a
		s:Play()
		Debris:AddItem(a, 4)
	else
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 4)
	end
end

local function impact(pos: Vector3, normal: Vector3, color: Color3, material: Enum.Material?)
	local cf = CFrame.lookAt(pos, pos + normal)
	-- Destello
	local flash = fxPart(cf, Vector3.new(0.6, 0.6, 0.05))
	flash.Transparency = 0.1
	flash.Color = color
	flash.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 4
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.25), { Size = Vector3.new(1.8, 1.8, 0.05), Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
	Debris:AddItem(flash, 0.3)

	-- Polvo del material + chispas
	local dustColor = Color3.fromRGB(120, 105, 90)
	if material == Enum.Material.Grass or material == Enum.Material.LeafyGrass then
		dustColor = Color3.fromRGB(80, 90, 55)
	elseif material == Enum.Material.Snow or material == Enum.Material.Ice then
		dustColor = Color3.fromRGB(230, 235, 245)
	end
	burst(cf, {
		Texture = SMOKE,
		Color = ColorSequence.new(dustColor),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(35, 35),
		Drag = 4,
		Acceleration = Vector3.new(0, -4, 0),
		EmissionDirection = Enum.NormalId.Front,
	}, 10)
	burst(cf, {
		Texture = SPARK,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new(0.25, 0),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = Vector3.new(0, -60, 0),
		EmissionDirection = Enum.NormalId.Front,
	}, 14)
end

function EffectsController.MuzzleFlash(at: Vector3, direction: Vector3, color: Color3)
	local cf = CFrame.lookAt(at, at + direction)
	local p = fxPart(cf, Vector3.new(0.7, 0.7, 1.4))
	p.Transparency = 0.15
	p.Material = Enum.Material.Neon
	p.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 16
	light.Brightness = 6
	light.Parent = p
	Debris:AddItem(p, 0.05)
	burst(cf, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(200, 200, 200)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(15, 15),
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		EmissionDirection = Enum.NormalId.Front,
		Rotation = NumberRange.new(0, 360),
	}, 6)
	burst(cf, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)),
		LightEmission = 1,
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.05, 0.1),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Front,
	}, 8, 1)
end

function EffectsController.EjectShell(at: CFrame)
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Cylinder
	shell.Size = Vector3.new(0.35, 0.09, 0.09)
	shell.Color = Color3.fromRGB(205, 160, 60)
	shell.Material = Enum.Material.Metal
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.CFrame = at
	shell.Parent = fxFolder
	shell.AssemblyLinearVelocity = at.RightVector * 12 + at.UpVector * 8 + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 3
	shell.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
	shell.CollisionGroup = "Default"
	shell.CanCollide = true
	Debris:AddItem(shell, 2.5)
end

-- Fantasma que sale del rival eliminado (Halloween) o polvo (normal)
function EffectsController.DeathEffect(character: Model?, headshot: boolean)
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local pos = root.Position
	if not GameConfig.HalloweenEvent then
		burst(CFrame.new(pos), { Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(200, 200, 200)), Size = NumberSequence.new(2, 5), Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180) }, 20)
		return
	end
	local ghost = Instance.new("Model")
	ghost.Name = "Ghost"
	local body = fxPart(CFrame.new(pos), Vector3.new(2.6, 3.6, 2.6))
	body.Transparency = 0.35
	body.Color = Color3.fromRGB(230, 240, 255)
	body.Material = Enum.Material.Neon
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = body
	body.Parent = ghost
	for _, x in { -0.45, 0.45 } do
		local eye = fxPart(CFrame.new(pos) * CFrame.new(x, 0.6, -1.25), Vector3.new(0.4, 0.6, 0.1))
		eye.Transparency = 0
		eye.Color = Color3.new(0, 0, 0)
		eye.Material = Enum.Material.SmoothPlastic
		local em = Instance.new("SpecialMesh")
		em.MeshType = Enum.MeshType.Sphere
		em.Parent = eye
		eye.Parent = ghost
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 210, 255)
	light.Range = 14
	light.Brightness = 2
	light.Parent = body
	ghost.Parent = fxFolder
	-- Caramelos saltando
	burst(CFrame.new(pos), {
		Texture = SPARK,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 0)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 80, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 90)),
		}),
		LightEmission = 1,
		Size = NumberSequence.new(0.6, 0.1),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -40, 0),
		EmissionDirection = Enum.NormalId.Top,
	}, if headshot then 40 else 22)

	local start = os.clock()
	local origin = ghost:GetPivot()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 2.2 then
			conn:Disconnect()
			ghost:Destroy()
			return
		end
		local wobble = math.sin(t * 6) * 0.6
		ghost:PivotTo(origin * CFrame.new(wobble, t * 5, 0) * CFrame.Angles(0, t * 1.5, math.sin(t * 4) * 0.2))
		local fade = math.clamp((t - 1.2) / 1, 0, 1)
		for _, p in ghost:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = if p == body then 0.35 + 0.65 * fade else fade
			end
		end
		light.Brightness = 2 * (1 - fade)
	end)
end

-- Simula y dibuja la bala. visualOrigin es desde donde se ve salir (cañón);
-- el trazador converge hacia la trayectoria real en los primeros metros.
function EffectsController.Tracer(origin: Vector3, direction: Vector3, weaponId: string, skinId: string, visualOrigin: Vector3?)
	local w = Weapons.Get(weaponId)
	local skin = Skins.Get(skinId)
	local color = if skin.Glow then skin.Color else Color3.fromRGB(255, 210, 140)
	local velocity = direction.Unit * w.MuzzleVelocity
	local offset = (visualOrigin or origin) - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { fxFolder, camera }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true

	local tracer = fxPart(CFrame.new(origin), Vector3.new(0.08, 0.08, 1))
	tracer.Transparency = 0
	tracer.Material = Enum.Material.Neon
	tracer.Color = color
	-- Estela de humo con Trail
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.05, 0)
	a0.Parent = tracer
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.05, 0)
	a1.Parent = tracer
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(Color3.fromRGB(220, 220, 230))
	trail.Transparency = NumberSequence.new(0.5, 1)
	trail.WidthScale = NumberSequence.new(1, 4)
	trail.LightEmission = 0.2
	trail.FaceCamera = true
	trail.Parent = tracer

	local t = 0
	local maxT = GameConfig.MaxBulletDistance / w.MuzzleVelocity
	local last = origin + offset
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		local nt = math.min(t + dt, maxT)
		local real = Ballistics.PositionAt(origin, velocity, w.BulletGravity, nt)
		local blend = math.clamp(1 - (nt * w.MuzzleVelocity) / 80, 0, 1)
		local pos = real + offset * blend
		local hit = workspace:Raycast(last, pos - last, params)
		local tail = last
		if hit then
			pos = hit.Position
		end
		local len = math.max((pos - tail).Magnitude, 0.5)
		tracer.Size = Vector3.new(0.08, 0.08, math.min(len, 30))
		tracer.CFrame = CFrame.lookAt(pos, tail) * CFrame.new(0, 0, -tracer.Size.Z / 2)
		last = pos
		t = nt
		if hit then
			impact(hit.Position, hit.Normal, color, hit.Material)
			conn:Disconnect()
			tracer.Transparency = 1
			Debris:AddItem(tracer, 0.6)
		elseif t >= maxT then
			conn:Disconnect()
			tracer:Destroy()
		end
	end)
end

-- Scope glint de los demás --------------------------------------------------
local glints: { [Model]: BillboardGui } = {}

local function updateGlints()
	local camPos = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	-- Jugadores y bots: cualquier personaje con rifle
	local candidates: { Model } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			table.insert(candidates, p.Character)
		end
	end
	for _, m in workspace:GetChildren() do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(m) then
			table.insert(candidates, m)
		end
	end
	for _, char in candidates do
		local rifle = char:FindFirstChild("Rifle")
		local lens = rifle and rifle:FindFirstChild("ScopeLens") :: BasePart?
		local scoped = char:GetAttribute("Scoped") == true
		local gui = glints[char]
		if lens and scoped then
			seen[char] = true
			if not gui then
				local g = Instance.new("BillboardGui")
				g.Name = "Glint"
				g.LightInfluence = 0
				g.Size = UDim2.fromScale(3, 3)
				local core = Instance.new("Frame")
				core.AnchorPoint = Vector2.new(0.5, 0.5)
				core.Position = UDim2.fromScale(0.5, 0.5)
				core.Size = UDim2.fromScale(1, 1)
				core.BackgroundColor3 = Color3.fromRGB(255, 255, 230)
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = core
				local grad = Instance.new("UIGradient")
				grad.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5, 0.4),
					NumberSequenceKeypoint.new(1, 1),
				})
				grad.Parent = core
				core.Parent = g
				-- Rayos en cruz
				for _, rot in { 0, 90 } do
					local ray = Instance.new("Frame")
					ray.AnchorPoint = Vector2.new(0.5, 0.5)
					ray.Position = UDim2.fromScale(0.5, 0.5)
					ray.Size = UDim2.fromScale(2.4, 0.08)
					ray.Rotation = rot
					ray.BorderSizePixel = 0
					ray.BackgroundColor3 = Color3.fromRGB(255, 255, 220)
					ray.BackgroundTransparency = 0.3
					ray.Parent = g
				end
				g.Adornee = lens
				g.Parent = fxFolder
				glints[char] = g
				gui = g
			end
			local g = gui :: BillboardGui
			local toCam = (camPos - lens.Position).Unit
			-- Solo brilla si el rifle te está apuntando a ti
			local body = (rifle :: Instance):FindFirstChild("Handle") or (rifle :: Instance):FindFirstChild("Receiver")
			local forward = if body and body:IsA("BasePart") then body.CFrame.LookVector else lens.CFrame.RightVector
			local facing = forward:Dot(toCam)
			local strength = math.clamp((facing - 0.8) / 0.2, 0, 1)
			local flicker = 0.85 + math.sin(os.clock() * 25) * 0.15
			g.Enabled = strength > 0
			g.Size = UDim2.fromScale(2 + 6 * strength * flicker, 2 + 6 * strength * flicker)
		end
	end
	for char, g in glints do
		if not seen[char] then
			g:Destroy()
			glints[char] = nil
		end
	end
end

function EffectsController.Start()
	Net.Event("ShotFx").OnClientEvent:Connect(function(shooterChar: Model?, origin: Vector3, direction: Vector3, weaponId: string, skinId: string)
		if shooterChar and shooterChar == player.Character then
			return
		end
		if (origin - camera.CFrame.Position).Magnitude > 1200 then
			return -- disparo en otra arena
		end
		local rifle = shooterChar and shooterChar:FindFirstChild("Rifle")
		local muzzle = rifle and rifle:FindFirstChild("Muzzle", true) :: Attachment?
		local visual = if muzzle then muzzle.WorldPosition else origin
		EffectsController.MuzzleFlash(visual, direction, Color3.fromRGB(255, 190, 90))
		EffectsController.Tracer(origin, direction, weaponId, skinId, visual)
		EffectsController.PlaySound("Fire", 1, visual)
		-- Bala que pasa cerca: temblor ligero
		local toCam = camera.CFrame.Position - origin
		local along = toCam:Dot(direction)
		if along > 0 and (toCam - direction * along).Magnitude < 8 then
			EffectsController.Shake(0.6)
		end
	end)

	Net.Event("KillFeed").OnClientEvent:Connect(function(info)
		if info.VictimCharacter and (info.Involved or info.KillerIsMe) then
			EffectsController.DeathEffect(info.VictimCharacter, info.Headshot)
		end
	end)

	RunService.RenderStepped:Connect(updateGlints)

	-- Temblor: se publica como desplazamiento para el viewmodel y el HUD
	-- (no se toca la cámara: el script de cámara de Roblox la reconstruye y daría saltos)
	RunService:BindToRenderStep("SD_Shake", Enum.RenderPriority.Camera.Value + 2, function(dt)
		shake = math.max(0, shake - dt * 4)
		local t = os.clock() * 40
		ClientState.ShakeOffset = if shake > 0.01 then Vector3.new(math.noise(t, 0) * shake * 3, math.noise(0, t) * shake * 3, 0) else Vector3.zero
		local _ = appliedShake
	end)
end

return EffectsController
