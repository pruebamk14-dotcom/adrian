--!strict
-- Inspeccionar un arma o skin a pantalla completa (como en Sniper Duels):
-- sala de exposición gris, el arma girando en el centro, título
-- "ARMA | SKIN" con el color de la rareza, procedencia y botón para salir.
--  * Arrastrar con el ratón (o el dedo) para girarla
--  * Rueda para acercar/alejar
--  * M o el botón rojo para salir

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local GunBuilder = require(Shared.GunBuilder)

local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Make)

local T = Make.Theme
local new = Make.new
local player = Players.LocalPlayer

local InspectUI = {}

local root: Frame
local viewport: ViewportFrame
local cam: Camera
local current: Model? = nil
local title: TextLabel
local rarityLabel: TextLabel
local sourceLabel: TextLabel
local ownedLabel: TextLabel
local yaw, pitch, zoom = 0.6, -0.15, 1
local dragging = false
local autoSpin = true
local spinResume = 0
local modelSize = 6

local function buildRoom()
	local function wall(size: Vector3, cf: CFrame, color: Color3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = viewport
		return p
	end
	local grey = Color3.fromRGB(178, 180, 186)
	local dark = Color3.fromRGB(70, 74, 82)
	-- Suelo, techo y fondo de la "cabina"
	wall(Vector3.new(30, 0.5, 30), CFrame.new(0, -4, 0), Color3.fromRGB(88, 96, 110))
	wall(Vector3.new(30, 0.5, 30), CFrame.new(0, 8, 0), grey)
	wall(Vector3.new(30, 14, 0.5), CFrame.new(0, 2, -9), grey)
	-- Columnas y estantes a los lados (como en la sala de la foto)
	for _, x in { -7, 7 } do
		wall(Vector3.new(1.4, 14, 1.4), CFrame.new(x, 2, -4), grey)
		wall(Vector3.new(1.4, 14, 1.4), CFrame.new(x * 1.6, 2, -1), grey)
	end
	wall(Vector3.new(26, 0.5, 6), CFrame.new(0, -2.2, -6.5), dark)
	wall(Vector3.new(26, 0.8, 0.5), CFrame.new(0, -1.8, -3.6), grey)
	-- Focos del techo
	for _, x in { -3, 3 } do
		local lamp = wall(Vector3.new(1.6, 0.2, 1.6), CFrame.new(x, 7.7, -2), Color3.fromRGB(255, 255, 240))
		lamp.Material = Enum.Material.Neon
	end
end

local function rarityOf(skinId: string)
	local s = Skins.Get(skinId)
	return s, Skins.RarityInfo(s.Rarity)
end

function InspectUI.Open(kind: string, weaponId: string?, skinId: string)
	if current then
		current:Destroy()
		current = nil
	end
	local model: Model
	local weaponName: string
	if kind == "Knife" then
		model = GunBuilder.BuildKnife(skinId)
		weaponName = Weapons.Melee.DisplayName
	else
		local w = Weapons.Get(weaponId or Weapons.Default)
		model = GunBuilder.Build(w.Id, skinId)
		weaponName = w.DisplayName
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	current = model
	local _, size = model:GetBoundingBox()
	modelSize = math.max(size.X, size.Y, size.Z)
	yaw, pitch, zoom = 0.6, -0.15, 1
	autoSpin = true

	local skin, rarity = rarityOf(skinId)
	title.Text = string.format("%s  |  %s", string.upper(weaponName), string.upper(skin.DisplayName))
	title.TextColor3 = rarity.Color
	rarityLabel.Text = string.upper(skin.Rarity) .. (if kind == "Knife" then "  ·  CUCHILLO" else "")
	rarityLabel.TextColor3 = rarity.Color
	sourceLabel.Text = if skin.Crate == "Halloween" then "CAJA DE HALLOWEEN" elseif skin.Id == "Default" then "ESTÁNDAR" else "CAJA DE SKINS"
	local d = ClientState.Data
	local owned = d and d.Inventory and d.Inventory.Skins and d.Inventory.Skins[skinId]
	ownedLabel.Text = if owned then "✓ EN TU INVENTARIO" else "🔒 NO LA TIENES"
	ownedLabel.TextColor3 = if owned then Color3.fromRGB(120, 255, 140) else T.SubText

	root.Visible = true
	root.BackgroundTransparency = 1
	TweenService:Create(root, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
	ClientState.MenuOpen = true
	ContextActionService:BindActionAtPriority("SD_InspectClose", function(_, state)
		if state == Enum.UserInputState.Begin then
			InspectUI.Close()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.M, Enum.KeyCode.ButtonB)
end

function InspectUI.Close()
	if not root.Visible then
		return
	end
	root.Visible = false
	ClientState.MenuOpen = false
	ContextActionService:UnbindAction("SD_InspectClose")
	if current then
		current:Destroy()
		current = nil
	end
end

function InspectUI.IsOpen(): boolean
	return root ~= nil and root.Visible
end

function InspectUI.Build(gui: ScreenGui)
	root = new("Frame", {
		Name = "Inspect",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(150, 154, 162),
		Visible = false,
		ZIndex = 80,
		Parent = gui,
	})
	viewport = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(160, 160, 170),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ZIndex = 81,
		Parent = root,
	})
	-- Botón Modal: libera el ratón aunque estemos en primera persona
	new("TextButton", { Text = "", Modal = true, Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, ZIndex = 81, Parent = root })
	cam = new("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = cam
	buildRoom()

	title = Make.Label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.new(0.9, 0, 0, 54), Font = T.FontBlack, TextSize = 46, TextStrokeTransparency = 0.6, ZIndex = 83, Parent = root })
	rarityLabel = Make.Label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.new(0.6, 0, 0, 32), Font = T.FontBlack, TextSize = 28, TextStrokeTransparency = 0.6, ZIndex = 83, Parent = root })
	sourceLabel = Make.Label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(0.6, 0, 0, 26), TextSize = 20, TextColor3 = Color3.fromRGB(235, 235, 240), TextStrokeTransparency = 0.6, ZIndex = 83, Parent = root })
	ownedLabel = Make.Label("", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.new(0.5, 0, 0, 28), Font = T.FontBlack, TextSize = 22, TextStrokeTransparency = 0.5, ZIndex = 83, Parent = root })
	Make.Label("Arrastra para girar · rueda para acercar", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0.5, 0, 0, 18), TextSize = 14, TextColor3 = Color3.fromRGB(230, 230, 235), TextStrokeTransparency = 0.6, ZIndex = 83, Parent = root })

	-- Botón "M  SALIR" abajo a la derecha, como en la foto
	local key = new("TextLabel", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -262, 1, -36), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Color3.new(1, 1, 1), Text = "M", Font = T.FontBlack, TextSize = 22, TextColor3 = Color3.new(0, 0, 0), ZIndex = 83, Parent = root }, { Make.Corner(6) })
	local _ = key
	Make.Button("SALIR DE INSPECCIÓN", Color3.fromRGB(220, 35, 55), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -30), Size = UDim2.fromOffset(226, 48), TextSize = 20, ZIndex = 83, Parent = root }, InspectUI.Close)

	-- Girar arrastrando
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			autoSpin = false
		end
	end)
	root.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			spinResume = os.clock() + 3
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not root.Visible then
			return
		end
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			yaw += input.Delta.X * 0.01
			pitch = math.clamp(pitch - input.Delta.Y * 0.008, -1.1, 1.1)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.5, 1.8)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not root.Visible or not current then
			return
		end
		if not autoSpin and not dragging and os.clock() > spinResume then
			autoSpin = true
		end
		if autoSpin then
			yaw += dt * 0.5
		end
		-- Arma de lado y algo inclinada, flotando en el centro
		local bob = math.sin(os.clock() * 1.4) * 0.08
		;(current :: Model):PivotTo(CFrame.new(0, 1.2 + bob, -2) * CFrame.Angles(pitch, yaw, math.rad(-8)))
		local dist = modelSize * 1.45 * zoom
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.6, -2 + dist), Vector3.new(0, 1.2, -2))
	end)
	local _ = player
end

return InspectUI
