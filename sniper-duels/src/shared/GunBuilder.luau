--!strict
-- Construye el modelo del rifle con piezas primitivas para que el proyecto
-- funcione sin assets externos. Sustituible por un MeshPart importado:
-- basta con mantener PrimaryPart mirando a -Z, el Attachment "Muzzle",
-- el Attachment "Ejection" y la pieza "ScopeLens".

local Skins = require(script.Parent.Config.Skins)
local Weapons = require(script.Parent.Config.Weapons)

local GunBuilder = {}

local CYL = CFrame.Angles(0, math.rad(90), 0) -- eje del cilindro (X) -> Z

local function part(model: Model, name: string, size: Vector3, offset: CFrame, kind: string, shape: Enum.PartType?): Part
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

local function wedge(model: Model, name: string, size: Vector3, offset: CFrame, kind: string): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = offset
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p:SetAttribute("SkinKind", kind)
	p.Parent = model
	return p
end

-- Pinta el dibujo de la skin sobre las piezas "Body" (determinista: siempre
-- sale igual para la misma skin)
function GunBuilder.PaintPattern(model: Instance, s: any)
	local seed = 0
	for i = 1, #s.Id do
		seed += string.byte(s.Id, i) * i
	end
	local rng = Random.new(seed)
	local colors = { s.Accent, s.Pattern2 or s.Accent }
	for _, body in model:GetDescendants() do
		if body:IsA("Part") and body:GetAttribute("SkinKind") == "Body" and body.Shape == Enum.PartType.Block then
			local size = body.Size
			local count = if s.Pattern == "dots" then 6 elseif s.Pattern == "stripes" then 3 else 5
			for k = 1, count do
				-- Elegir una cara lateral (±X) o superior (+Y)
				local face = rng:NextInteger(1, 3)
				local thickness = 0.02
				local w, h, offset
				if s.Pattern == "stripes" then
					w, h = size.Y * 1.02, math.min(size.Z, size.X) * 0.18 + 0.04
					offset = CFrame.new(0, 0, -size.Z / 2 + (k - 0.5) * size.Z / count) * CFrame.Angles(math.rad(35), 0, 0)
				elseif s.Pattern == "dots" then
					w = math.min(size.Y, size.Z) * rng:NextNumber(0.15, 0.3)
					h = w
					offset = CFrame.new(0, rng:NextNumber(-0.35, 0.35) * size.Y, rng:NextNumber(-0.45, 0.45) * size.Z)
				elseif s.Pattern == "flames" then
					w, h = size.Y * rng:NextNumber(0.3, 0.6), size.Z * rng:NextNumber(0.2, 0.35)
					offset = CFrame.new(0, -size.Y * 0.3 + w * 0.3, rng:NextNumber(-0.4, 0.4) * size.Z) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, 0)
				else -- camo: manchas irregulares
					w, h = size.Y * rng:NextNumber(0.35, 0.7), size.Z * rng:NextNumber(0.15, 0.35)
					offset = CFrame.new(0, rng:NextNumber(-0.3, 0.3) * size.Y, rng:NextNumber(-0.4, 0.4) * size.Z) * CFrame.Angles(math.rad(rng:NextNumber(-40, 40)), 0, 0)
				end
				local p = Instance.new("Part")
				p.Name = "Pattern"
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Massless = true
				p.CastShadow = false
				p.Anchored = body.Anchored
				p.Material = if s.Pattern == "flames" then Enum.Material.Neon else Enum.Material.SmoothPlastic
				p.Color = colors[rng:NextInteger(1, #colors)]
				p:SetAttribute("SkinKind", "Pattern")
				local faceCf
				if face == 1 then
					p.Size = Vector3.new(thickness, math.min(w, size.Y), math.min(h, size.Z))
					faceCf = CFrame.new(size.X / 2 + thickness / 2, 0, 0)
				elseif face == 2 then
					p.Size = Vector3.new(thickness, math.min(w, size.Y), math.min(h, size.Z))
					faceCf = CFrame.new(-size.X / 2 - thickness / 2, 0, 0)
				else
					p.Size = Vector3.new(math.min(w, size.X), thickness, math.min(h, size.Z))
					faceCf = CFrame.new(0, size.Y / 2 + thickness / 2, 0)
				end
				p.CFrame = body.CFrame * faceCf * offset
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = p
				weld.Parent = p
				p.Parent = body.Parent
			end
		end
	end
end

function GunBuilder.ApplySkin(model: Instance, skinId: string)
	local s = Skins.Get(skinId)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("SkinKind")
			if kind == "Body" then
				d.Color = s.Color
				d.Material = s.Material
			elseif kind == "Accent" then
				d.Color = s.Accent
				d.Material = if s.Glow then Enum.Material.Neon else Enum.Material.Metal
			elseif kind == "Metal" then
				d.Color = Color3.fromRGB(38, 38, 42)
				d.Material = Enum.Material.Metal
			elseif kind == "Glass" then
				d.Color = Color3.fromRGB(40, 70, 110)
				d.Material = Enum.Material.Glass
				d.Transparency = 0.15
				d.Reflectance = 0.4
			end
		end
	end
	local glow = model:FindFirstChild("SkinGlow", true)
	if glow then
		glow:Destroy()
	end
	-- Dibujo (camuflaje, rayas, puntos, llamas) con piezas finas pegadas al cuerpo
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SkinKind") == "Pattern" then
			d:Destroy()
		end
	end
	if s.Pattern then
		GunBuilder.PaintPattern(model, s)
	end
	if s.Glow then
		local body = (model:FindFirstChild("Receiver") or model:FindFirstChild("Handle")) :: BasePart?
		if body then
			local light = Instance.new("PointLight")
			light.Name = "SkinGlow"
			light.Color = s.Color
			light.Range = 7
			light.Brightness = 1.6
			light.Parent = body
		end
	end
end

function GunBuilder.Build(weaponId: string, skinId: string): Model
	local w = Weapons.Get(weaponId)
	local L = w.BarrelLength
	local model = Instance.new("Model")
	model.Name = "Rifle"

	-- Cuerpo
	local receiver = part(model, "Receiver", Vector3.new(0.34, 0.42, 1.7), CFrame.new(0, 0, -0.3), "Body")
	part(model, "ReceiverTop", Vector3.new(0.26, 0.08, 1.5), CFrame.new(0, 0.25, -0.3), "Metal")
	part(model, "Rail", Vector3.new(0.18, 0.06, 1.4), CFrame.new(0, 0.31, -0.3), "Metal")
	part(model, "Handguard", Vector3.new(0.3, 0.32, 1.3), CFrame.new(0, 0.0, -1.7), "Body")
	part(model, "Grip", Vector3.new(0.24, 0.62, 0.32), CFrame.new(0, -0.42, 0.25) * CFrame.Angles(math.rad(-18), 0, 0), "Body")
	part(model, "TriggerGuard", Vector3.new(0.06, 0.06, 0.42), CFrame.new(0, -0.32, -0.05), "Metal")
	part(model, "Trigger", Vector3.new(0.04, 0.16, 0.04), CFrame.new(0, -0.25, -0.02), "Metal")
	part(model, "Mag", Vector3.new(0.24, 0.52, 0.34), CFrame.new(0, -0.42, -0.6) * CFrame.Angles(math.rad(8), 0, 0), "Metal")

	-- Culata con pieza en cuña
	part(model, "Stock", Vector3.new(0.28, 0.36, 1.2), CFrame.new(0, -0.05, 1.1), "Body")
	wedge(model, "StockWedge", Vector3.new(0.28, 0.36, 0.9), CFrame.new(0, -0.38, 1.25) * CFrame.Angles(0, math.rad(180), math.rad(180)), "Body")
	part(model, "Cheek", Vector3.new(0.22, 0.12, 0.7), CFrame.new(0, 0.18, 1.05), "Accent")
	part(model, "ButtPad", Vector3.new(0.3, 0.72, 0.1), CFrame.new(0, -0.2, 1.74), "Metal")

	-- Cañón cilíndrico + supresor
	part(model, "Barrel", Vector3.new(L, 0.13, 0.13), CFrame.new(0, 0.05, -1.15 - L / 2) * CYL, "Metal", Enum.PartType.Cylinder)
	part(model, "Suppressor", Vector3.new(0.75, 0.24, 0.24), CFrame.new(0, 0.05, -1.15 - L - 0.3) * CYL, "Accent", Enum.PartType.Cylinder)
	part(model, "MuzzleBrake", Vector3.new(0.12, 0.27, 0.27), CFrame.new(0, 0.05, -1.15 - L - 0.7) * CYL, "Metal", Enum.PartType.Cylinder)

	-- Cerrojo
	part(model, "Bolt", Vector3.new(0.4, 0.09, 0.09), CFrame.new(0.24, 0.1, 0.15), "Metal", Enum.PartType.Cylinder)
	part(model, "BoltKnob", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0.45, 0.1, 0.15), "Metal", Enum.PartType.Ball)

	-- Mira telescópica
	part(model, "ScopeTube", Vector3.new(1.6, 0.22, 0.22), CFrame.new(0, 0.52, -0.35) * CYL, "Accent", Enum.PartType.Cylinder)
	part(model, "ScopeBell", Vector3.new(0.38, 0.34, 0.34), CFrame.new(0, 0.52, -1.25) * CYL, "Accent", Enum.PartType.Cylinder)
	part(model, "ScopeEye", Vector3.new(0.3, 0.28, 0.28), CFrame.new(0, 0.52, 0.5) * CYL, "Accent", Enum.PartType.Cylinder)
	part(model, "Turret", Vector3.new(0.16, 0.14, 0.14), CFrame.new(0, 0.66, -0.35) * CFrame.Angles(0, 0, math.rad(90)), "Metal", Enum.PartType.Cylinder)
	part(model, "TurretSide", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0.15, 0.52, -0.35), "Metal", Enum.PartType.Cylinder)
	part(model, "RingFront", Vector3.new(0.12, 0.3, 0.3), CFrame.new(0, 0.42, -0.85) * CYL, "Metal", Enum.PartType.Cylinder)
	part(model, "RingBack", Vector3.new(0.12, 0.3, 0.3), CFrame.new(0, 0.42, 0.1) * CYL, "Metal", Enum.PartType.Cylinder)
	part(model, "ScopeLens", Vector3.new(0.02, 0.3, 0.3), CFrame.new(0, 0.52, -1.45) * CYL, "Glass", Enum.PartType.Cylinder)

	-- Bípode plegado
	part(model, "BipodL", Vector3.new(0.06, 0.06, 0.9), CFrame.new(-0.1, -0.2, -2.0) * CFrame.Angles(math.rad(-8), 0, 0), "Metal")
	part(model, "BipodR", Vector3.new(0.06, 0.06, 0.9), CFrame.new(0.1, -0.2, -2.0) * CFrame.Angles(math.rad(-8), 0, 0), "Metal")

	model.PrimaryPart = receiver

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = receiver.CFrame:PointToObjectSpace(Vector3.new(0, 0.05, -1.15 - L - 0.8))
	muzzle.Parent = receiver

	local ejection = Instance.new("Attachment")
	ejection.Name = "Ejection"
	ejection.Position = receiver.CFrame:PointToObjectSpace(Vector3.new(0.2, 0.15, -0.1))
	ejection.Parent = receiver

	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= receiver then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = receiver
			weld.Part1 = p
			weld.Parent = p
		end
	end

	GunBuilder.ApplySkin(model, skinId)
	model:SetAttribute("WeaponId", w.Id)
	model:SetAttribute("SkinId", skinId)
	return model
end

-- Versión Tool para el personaje: se agarra con la mano derecha (RightGrip)
-- y la animación por defecto "toolnone" levanta el brazo apuntando al frente.
GunBuilder.GripOffset = CFrame.new(0, -0.42, 0.55) -- empuñadura respecto al receiver

function GunBuilder.BuildTool(weaponId: string, skinId: string): Tool
	local model = GunBuilder.Build(weaponId, skinId)
	local tool = Instance.new("Tool")
	tool.Name = "Rifle"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.ToolTip = ""
	tool.Grip = GunBuilder.GripOffset
	local receiver = model.PrimaryPart :: BasePart
	for _, c in model:GetChildren() do
		c.Parent = tool
	end
	receiver.Name = "Handle"
	tool:SetAttribute("WeaponId", model:GetAttribute("WeaponId"))
	tool:SetAttribute("SkinId", skinId)
	model:Destroy()
	return tool
end

-- Cuchillo mariposa: hoja + dos mangos que giran alrededor del pivote
-- ("Pivot"). El cliente anima los mangos (Handle1/Handle2) en reposo.
-- Cuchillo mariposa (balisong): hoja de punta de lanza con lomo, vaceo y
-- filo pulido; dos mangos de canal con ventanas, pasadores y remates.
-- Los mangos llevan el atributo Side/HandleSide para la animación de giro.
function GunBuilder.BuildKnife(skinId: string): Model
	local s = Skins.Get(skinId)
	local model = Instance.new("Model")
	model.Name = "Knife"
	local steel = Color3.fromRGB(196, 200, 210)
	local dark = Color3.fromRGB(38, 40, 46)
	local bladeColor = s.Accent:Lerp(steel, 0.45)
	local glowEdge = s.Glow == true

	local pivot = part(model, "Pivot", Vector3.new(0.12, 0.12, 0.12), CFrame.new(0, 0, 0), "Metal", Enum.PartType.Ball)
	pivot.Color = dark
	pivot.Material = Enum.Material.Metal

	local function bladePart(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, isWedge: boolean?)
		local bp: BasePart = if isWedge then wedge(model, name, size, cf, "Blade") :: BasePart else part(model, name, size, cf, "Blade")
		bp.Color = color
		bp.Material = mat
		bp.Reflectance = if mat == Enum.Material.Metal then 0.12 else 0
		return bp
	end
	-- Hoja
	bladePart("Blade", Vector3.new(0.045, 0.26, 1.05), CFrame.new(0, 0.01, -0.68), bladeColor, Enum.Material.Metal)
	bladePart("Spine", Vector3.new(0.055, 0.035, 1.1), CFrame.new(0, 0.15, -0.66), bladeColor:Lerp(dark, 0.35), Enum.Material.Metal)
	bladePart("Fuller", Vector3.new(0.05, 0.045, 0.7), CFrame.new(0, 0.06, -0.6), bladeColor:Lerp(dark, 0.55), Enum.Material.Metal)
	local edge = bladePart("Edge", Vector3.new(0.025, 0.06, 1.0), CFrame.new(0, -0.13, -0.7), if glowEdge then s.Color else Color3.fromRGB(235, 238, 245), if glowEdge then Enum.Material.Neon else Enum.Material.Metal)
	edge.Reflectance = 0.3
	-- Punta de lanza: cuña superior + cuña inferior
	bladePart("TipTop", Vector3.new(0.045, 0.17, 0.42), CFrame.new(0, 0.085, -1.41) * CFrame.Angles(0, math.rad(180), 0), bladeColor, Enum.Material.Metal, true)
	bladePart("TipLow", Vector3.new(0.045, 0.14, 0.42), CFrame.new(0, -0.07, -1.41) * CFrame.Angles(0, math.rad(180), math.rad(180)), if glowEdge then s.Color else Color3.fromRGB(235, 238, 245), if glowEdge then Enum.Material.Neon else Enum.Material.Metal, true)
	-- Recazo y pasadores del eje
	bladePart("Ricasso", Vector3.new(0.05, 0.3, 0.2), CFrame.new(0, 0.01, -0.1), dark, Enum.Material.Metal)
	bladePart("Kicker", Vector3.new(0.05, 0.1, 0.12), CFrame.new(0, -0.17, -0.06), dark, Enum.Material.Metal)

	-- Mangos (Side = hacia dónde giran al abrirse)
	for i, side in { -1, 1 } do
		local x = side * 0.078
		local h = part(model, "Handle" .. i, Vector3.new(0.075, 0.22, 1.3), CFrame.new(x, 0, 0.68), "Body")
		h.Color = s.Color
		h.Material = s.Material
		h:SetAttribute("Side", side)
		local function bit(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?)
			local bp = part(model, name, size, cf, "Metal", shape)
			bp.Color = color
			bp.Material = mat
			bp:SetAttribute("HandleSide", side)
			return bp
		end
		-- Ventanas del canal
		for k = 0, 3 do
			bit("Hole" .. i .. k, Vector3.new(0.08, 0.075, 0.17), CFrame.new(x + side * 0.003, 0, 0.27 + k * 0.27), Color3.fromRGB(16, 16, 20), Enum.Material.SmoothPlastic)
		end
		-- Bandas de color de la skin a lo largo del mango
		bit("Inlay" .. i .. "a", Vector3.new(0.08, 0.025, 1.05), CFrame.new(x + side * 0.002, 0.085, 0.7), s.Accent, if glowEdge then Enum.Material.Neon else s.Material)
		bit("Inlay" .. i .. "b", Vector3.new(0.08, 0.025, 1.05), CFrame.new(x + side * 0.002, -0.085, 0.7), s.Accent, if glowEdge then Enum.Material.Neon else s.Material)
		-- Pasador del eje y remate
		bit("Pin" .. i, Vector3.new(0.09, 0.09, 0.09), CFrame.new(x, 0.06, 0.04), steel, Enum.Material.Metal, Enum.PartType.Ball)
		bit("Pin" .. i .. "b", Vector3.new(0.09, 0.09, 0.09), CFrame.new(x, -0.06, 0.04), steel, Enum.Material.Metal, Enum.PartType.Ball)
		bit("Cap" .. i, Vector3.new(0.085, 0.24, 0.09), CFrame.new(x, 0, 1.35), steel, Enum.Material.Metal)
	end
	-- Pestillo (en el mango 1)
	local latch = part(model, "Latch", Vector3.new(0.03, 0.05, 0.32), CFrame.new(-0.078 - 0.05, 0, 1.2), "Metal")
	latch.Color = steel
	latch.Material = Enum.Material.Metal
	latch:SetAttribute("HandleSide", -1)

	model.PrimaryPart = pivot
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= pivot then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = pivot
			weld.Part1 = p
			weld.Parent = p
		end
	end
	if s.Glow then
		local light = Instance.new("PointLight")
		light.Name = "SkinGlow"
		light.Color = s.Color
		light.Range = 5
		light.Brightness = 1.2
		light.Parent = pivot
	end
	model:SetAttribute("SkinId", skinId)
	return model
end

function GunBuilder.BuildKnifeTool(skinId: string): Tool
	local model = GunBuilder.BuildKnife(skinId)
	local tool = Instance.new("Tool")
	tool.Name = "Knife"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.new(0, -0.1, 0.45) * CFrame.Angles(math.rad(-90), 0, 0)
	local pivot = model.PrimaryPart :: BasePart
	for _, c in model:GetChildren() do
		c.Parent = tool
	end
	pivot.Name = "Handle"
	pivot.Size = Vector3.new(0.5, 0.5, 0.5)
	pivot.Transparency = 1
	model:Destroy()
	return tool
end

-- Brazos en primera persona: color de piel del personaje si se puede leer
local function skinColor(character: Model?): Color3
	local arm = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if arm and arm:IsA("BasePart") then
		return arm.Color
	end
	return Color3.fromRGB(204, 142, 105)
end

local function armPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p:SetAttribute("SkinKind", "Arm")
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = model.PrimaryPart
	weld.Part1 = p
	weld.Parent = p
end

-- Rifle: mano derecha en la empuñadura, izquierda en el guardamanos
function GunBuilder.AddArms(model: Model, character: Model?)
	local color = skinColor(character)
	local sleeve = Color3.fromRGB(40, 36, 44)
	local base = (model.PrimaryPart :: BasePart).CFrame
	-- Brazo derecho: viene desde abajo-derecha hasta la empuñadura
	armPart(model, "ArmR", Vector3.new(0.5, 0.5, 1.6), base * CFrame.new(0.35, -0.75, 0.95) * CFrame.Angles(math.rad(35), math.rad(-15), 0), sleeve)
	armPart(model, "HandR", Vector3.new(0.42, 0.42, 0.6), base * CFrame.new(0.05, -0.45, 0.3) * CFrame.Angles(math.rad(-20), 0, 0), color)
	-- Brazo izquierdo: hacia delante, mano bajo el guardamanos
	armPart(model, "ArmL", Vector3.new(0.5, 0.5, 1.9), base * CFrame.new(-0.55, -0.55, -0.6) * CFrame.Angles(math.rad(10), math.rad(25), 0), sleeve)
	armPart(model, "HandL", Vector3.new(0.42, 0.42, 0.55), base * CFrame.new(-0.12, -0.28, -1.55) * CFrame.Angles(0, 0, math.rad(20)), color)
end

-- Cuchillo: mano derecha sujetando el mango
function GunBuilder.AddKnifeArm(model: Model, character: Model?)
	local color = skinColor(character)
	local sleeve = Color3.fromRGB(40, 36, 44)
	local base = (model.PrimaryPart :: BasePart).CFrame
	armPart(model, "HandR", Vector3.new(0.45, 0.45, 0.7), base * CFrame.new(0, -0.05, 0.75), color)
	armPart(model, "ArmR", Vector3.new(0.5, 0.5, 1.5), base * CFrame.new(0.15, -0.45, 1.6) * CFrame.Angles(math.rad(30), math.rad(-10), 0), sleeve)
end

return GunBuilder
