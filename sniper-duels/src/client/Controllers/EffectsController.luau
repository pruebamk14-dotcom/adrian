--!strict
-- Efectos visuales: trazadores balísticos, fogonazo, impactos, sonidos y
-- el destello de mira (scope glint) de los rivales que están apuntando.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local Ballistics = require(Shared.Ballistics)
local Net = require(Shared.Net)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local EffectsController = {}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientFX"
fxFolder.Parent = workspace

function EffectsController.PlaySound(name: string, volume: number?, at: Vector3?)
	local id = (GameConfig.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	if at then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		s.Parent = a
		s.RollOffMaxDistance = 1500
		s:Play()
		Debris:AddItem(a, 4)
	else
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 4)
	end
end

local function impact(pos: Vector3, normal: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(0.6, 0.6, 0.05)
	p.CFrame = CFrame.lookAt(pos, pos + normal)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.1
	p.Parent = fxFolder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6
	light.Brightness = 3
	light.Parent = p
	task.spawn(function()
		for i = 1, 10 do
			p.Size = p.Size + Vector3.new(0.12, 0.12, 0)
			p.Transparency = 0.1 + i * 0.09
			light.Brightness = 3 * (1 - i / 10)
			task.wait(0.02)
		end
		p:Destroy()
	end)
end

function EffectsController.MuzzleFlash(at: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.9, 0.9, 0.9)
	p.Position = at
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Parent = fxFolder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 14
	light.Brightness = 5
	light.Parent = p
	Debris:AddItem(p, 0.06)
end

-- Simula y dibuja la bala. visualOrigin es desde donde se ve salir (cañón);
-- el trazador converge hacia la trayectoria real en los primeros metros.
function EffectsController.Tracer(origin: Vector3, direction: Vector3, weaponId: string, skinId: string, visualOrigin: Vector3?)
	local w = Weapons.Get(weaponId)
	local skin = Skins.Get(skinId)
	local color = if skin.Glow then skin.Color else Color3.fromRGB(255, 220, 150)
	local velocity = direction.Unit * w.MuzzleVelocity
	local offset = (visualOrigin or origin) - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { fxFolder, camera }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = color
	tracer.Size = Vector3.new(0.09, 0.09, 1)
	tracer.Parent = fxFolder

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
		tracer.Size = Vector3.new(0.09, 0.09, math.min(len, 40))
		tracer.CFrame = CFrame.lookAt(pos, tail) * CFrame.new(0, 0, -tracer.Size.Z / 2)
		last = pos
		t = nt
		if hit then
			impact(hit.Position, hit.Normal, color)
			conn:Disconnect()
			tracer:Destroy()
		elseif t >= maxT then
			conn:Disconnect()
			tracer:Destroy()
		end
	end)
end

-- Scope glint de los demás jugadores
local glints: { [Model]: BillboardGui } = {}

local function updateGlints()
	local camPos = camera.CFrame.Position
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			local char = p.Character
			local rifle = char:FindFirstChild("Rifle")
			local lens = rifle and rifle:FindFirstChild("ScopeLens") :: BasePart?
			local scoped = char:GetAttribute("Scoped") == true
			local gui = glints[char]
			if lens and scoped then
				if not gui then
					local g = Instance.new("BillboardGui")
					g.Name = "Glint"
					g.AlwaysOnTop = false
					g.LightInfluence = 0
					g.Size = UDim2.fromScale(3, 3)
					local img = Instance.new("Frame")
					img.Name = "Core"
					img.AnchorPoint = Vector2.new(0.5, 0.5)
					img.Position = UDim2.fromScale(0.5, 0.5)
					img.Size = UDim2.fromScale(1, 1)
					img.BackgroundColor3 = Color3.fromRGB(255, 255, 230)
					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0.5, 0)
					corner.Parent = img
					local grad = Instance.new("UIGradient")
					grad.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.5, 0.4),
						NumberSequenceKeypoint.new(1, 1),
					})
					grad.Parent = img
					img.Parent = g
					g.Adornee = lens
					g.Parent = fxFolder
					glints[char] = g
					gui = g
				end
				local g = gui :: BillboardGui
				local toCam = (camPos - lens.Position).Unit
				-- Solo brilla si el rifle te está apuntando a ti
				local facing = (rifle :: Model):GetPivot().LookVector:Dot(toCam)
				local strength = math.clamp((facing - 0.8) / 0.2, 0, 1)
				local flicker = 0.85 + math.sin(os.clock() * 25) * 0.15
				g.Enabled = strength > 0
				g.Size = UDim2.fromScale(2 + 6 * strength * flicker, 2 + 6 * strength * flicker)
			elseif gui then
				gui:Destroy()
				glints[char] = nil
			end
		end
	end
	for char, g in glints do
		if not char.Parent then
			g:Destroy()
			glints[char] = nil
		end
	end
end

function EffectsController.Start()
	Net.Event("ShotFx").OnClientEvent:Connect(function(shooter: Player, origin: Vector3, direction: Vector3, weaponId: string, skinId: string)
		if shooter == player then
			return
		end
		if (origin - camera.CFrame.Position).Magnitude > 1200 then
			return -- disparo en otra arena
		end
		local char = shooter.Character
		local rifle = char and char:FindFirstChild("Rifle")
		local muzzle = rifle and rifle:FindFirstChild("Muzzle", true) :: Attachment?
		local visual = if muzzle then muzzle.WorldPosition else origin
		EffectsController.MuzzleFlash(visual, Color3.fromRGB(255, 190, 90))
		EffectsController.Tracer(origin, direction, weaponId, skinId, visual)
		EffectsController.PlaySound("Fire", 1, visual)
	end)

	RunService.RenderStepped:Connect(updateGlints)
end

return EffectsController
