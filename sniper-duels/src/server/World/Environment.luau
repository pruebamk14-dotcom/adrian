--!strict
-- Iluminación, cielo, nubes, niebla y post-procesado.
-- Halloween: atardecer morado/naranja ("hora bruja") con buena visibilidad
-- para que se pueda seguir francotirando a 300 studs.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)

local Environment = {}

local function get(className: string, parent: Instance): any
	local inst = parent:FindFirstChildOfClass(className)
	if not inst then
		inst = Instance.new(className)
		inst.Parent = parent
	end
	return inst
end

function Environment.Apply()
	local halloween = GameConfig.HalloweenEvent
	local terrain = workspace.Terrain

	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.25

	local sky = get("Sky", Lighting) :: Sky
	sky.StarCount = 3000
	sky.MoonAngularSize = 18
	sky.SunAngularSize = 14
	sky.CelestialBodiesShown = true

	local atmo = get("Atmosphere", Lighting) :: Atmosphere
	local cc = get("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
	local bloom = get("BloomEffect", Lighting) :: BloomEffect
	local rays = get("SunRaysEffect", Lighting) :: SunRaysEffect
	local clouds = get("Clouds", terrain) :: Clouds

	if halloween then
		Lighting.ClockTime = 18.35
		Lighting.GeographicLatitude = 35
		Lighting.Brightness = 2.2
		Lighting.Ambient = Color3.fromRGB(45, 30, 60)
		Lighting.OutdoorAmbient = Color3.fromRGB(110, 80, 125)
		Lighting.ColorShift_Top = Color3.fromRGB(255, 140, 60)
		Lighting.ColorShift_Bottom = Color3.fromRGB(80, 40, 120)
		Lighting.ExposureCompensation = 0.15

		atmo.Density = 0.36
		atmo.Offset = 0.1
		atmo.Haze = 2.2
		atmo.Glare = 0.6
		atmo.Color = Color3.fromRGB(150, 100, 140)
		atmo.Decay = Color3.fromRGB(80, 40, 90)

		cc.TintColor = Color3.fromRGB(255, 238, 225)
		cc.Contrast = 0.12
		cc.Saturation = 0.08
		cc.Brightness = 0.02

		bloom.Intensity = 0.9
		bloom.Size = 32
		bloom.Threshold = 1.3

		rays.Intensity = 0.06
		rays.Spread = 0.6

		clouds.Cover = 0.62
		clouds.Density = 0.45
		clouds.Color = Color3.fromRGB(110, 80, 120)

		terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(62, 78, 46))
		terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(76, 70, 40))
		terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(58, 44, 36))
		terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(78, 62, 48))
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(80, 78, 84))
		terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(70, 68, 78))
		terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(90, 86, 92))
	else
		Lighting.ClockTime = 16.8
		Lighting.Brightness = 2.6
		Lighting.Ambient = Color3.fromRGB(60, 60, 70)
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 140)
		atmo.Density = 0.28
		atmo.Haze = 1.2
		atmo.Color = Color3.fromRGB(200, 190, 180)
		cc.Contrast = 0.08
		cc.Saturation = 0.1
		bloom.Intensity = 0.6
		bloom.Size = 28
		bloom.Threshold = 1.6
		rays.Intensity = 0.1
		clouds.Cover = 0.5
		clouds.Density = 0.4
	end

	pcall(function()
		(terrain :: any).Decoration = true -- hierba animada
	end)
	terrain.WaterWaveSize = 0.1
end

return Environment
