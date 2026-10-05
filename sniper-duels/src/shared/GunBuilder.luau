--!strict
-- Construye el modelo del rifle con piezas primitivas para que el proyecto
-- funcione sin assets externos. Sustituible por un MeshPart importado:
-- basta con mantener "Handle" (PrimaryPart) y el Attachment "Muzzle".

local Skins = require(script.Parent.Config.Skins)
local Weapons = require(script.Parent.Config.Weapons)

local GunBuilder = {}

local function part(model: Model, name: string, size: Vector3, offset: CFrame, kind: string, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = offset
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p:SetAttribute("SkinKind", kind)
	p.Parent = model
	return p
end

function GunBuilder.ApplySkin(model: Model, skinId: string)
	local s = Skins.Get(skinId)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("SkinKind")
			if kind == "Body" then
				d.Color = s.Color
				d.Material = s.Material
			elseif kind == "Accent" then
				d.Color = s.Accent
				d.Material = Enum.Material.Metal
			elseif kind == "Glass" then
				d.Color = Color3.fromRGB(20, 30, 40)
				d.Material = Enum.Material.Glass
				d.Transparency = 0.2
			end
		end
	end
	local glow = model:FindFirstChild("SkinGlow", true)
	if glow then
		glow:Destroy()
	end
	if s.Glow then
		local body = model:FindFirstChild("Stock") :: BasePart?
		if body then
			local light = Instance.new("PointLight")
			light.Name = "SkinGlow"
			light.Color = s.Color
			light.Range = 6
			light.Brightness = 1.5
			light.Parent = body
		end
	end
end

function GunBuilder.Build(weaponId: string, skinId: string): Model
	local w = Weapons.Get(weaponId)
	local L = w.BarrelLength
	local model = Instance.new("Model")
	model.Name = "Rifle"

	local handle = part(model, "Handle", Vector3.new(0.3, 0.7, 0.4), CFrame.new(0, -0.35, 0.2) * CFrame.Angles(math.rad(-15), 0, 0), "Body")
	local receiver = part(model, "Receiver", Vector3.new(0.35, 0.45, 1.6), CFrame.new(0, 0, -0.3), "Body")
	part(model, "Stock", Vector3.new(0.3, 0.55, 1.4), CFrame.new(0, -0.08, 1.15), "Body")
	part(model, "Barrel", Vector3.new(0.14, 0.14, L), CFrame.new(0, 0.05, -1.1 - L / 2), "Accent")
	part(model, "Suppressor", Vector3.new(0.22, 0.22, 0.6), CFrame.new(0, 0.05, -1.1 - L - 0.2), "Accent")
	part(model, "Mag", Vector3.new(0.25, 0.5, 0.35), CFrame.new(0, -0.4, -0.45), "Accent")
	part(model, "Bolt", Vector3.new(0.1, 0.1, 0.35), CFrame.new(0.25, 0.12, 0.1) * CFrame.Angles(0, 0, math.rad(90)), "Accent")
	part(model, "ScopeTube", Vector3.new(0.24, 0.24, 1.5), CFrame.new(0, 0.42, -0.35), "Accent")
	part(model, "ScopeFront", Vector3.new(0.34, 0.34, 0.25), CFrame.new(0, 0.42, -1.15), "Accent")
	part(model, "ScopeLens", Vector3.new(0.28, 0.28, 0.02), CFrame.new(0, 0.42, -1.28), "Glass")
	part(model, "BipodL", Vector3.new(0.06, 0.6, 0.06), CFrame.new(-0.12, -0.25, -1.9) * CFrame.Angles(0, 0, math.rad(15)), "Accent")
	part(model, "BipodR", Vector3.new(0.06, 0.6, 0.06), CFrame.new(0.12, -0.25, -1.9) * CFrame.Angles(0, 0, math.rad(-15)), "Accent")

	model.PrimaryPart = receiver

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.05, -(1.1 + L + 0.55)) - receiver.Position
	muzzle.Parent = receiver

	-- Soldar todo al receiver
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= receiver then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = receiver
			weld.Part1 = p
			weld.Parent = p
		end
	end
	handle.Name = "Grip"

	GunBuilder.ApplySkin(model, skinId)
	model:SetAttribute("WeaponId", w.Id)
	model:SetAttribute("SkinId", skinId)
	return model
end

return GunBuilder
