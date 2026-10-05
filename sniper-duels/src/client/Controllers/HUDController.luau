--!strict
-- HUD de combate: mira telescópica, crosshair dinámico, munición, vida,
-- marcador del duelo, banners, hitmarkers, indicador de daño, killfeed,
-- pantalla VS y resumen final.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Rank = require(Shared.Rank)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Parent.UI.Make)
local EffectsController = require(script.Parent.EffectsController)
local WeaponController = require(script.Parent.WeaponController)

local T = Make.Theme
local new = Make.new
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local HUDController = {}

-- Desaturar la pantalla con poca vida
local lowHp = Instance.new("ColorCorrectionEffect")
lowHp.Name = "SD_LowHealth"
lowHp.Enabled = false
lowHp.Parent = game:GetService("Lighting")

local gui: ScreenGui
local refs: { [string]: any } = {}

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Construcción ---------------------------------------------------------------

local function buildScope(parent: Instance)
	local scope = new("Frame", { Name = "Scope", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = parent })
	-- Círculo con borde enorme = todo negro salvo la lente
	local lens = new("Frame", {
		Name = "Lens",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Parent = scope,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3000, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	-- Viñeta interior suave
	new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		Parent = lens,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.75, 1),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
		}),
	})
	-- Cristal: tinte azulado, reflejo curvo, borde iluminado y anillo interior
	new("Frame", {
		Name = "GlassTint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 190, 255),
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		Parent = lens,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIGradient", {
			Rotation = 135,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 0.4) }),
		}),
	})
	local reflection = new("Frame", {
		Name = "Reflection",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.32, 0.26),
		Size = UDim2.fromScale(0.42, 0.16),
		Rotation = -35,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = lens,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	local _ = reflection
	new("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = lens,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIStroke", { Color = Color3.fromRGB(80, 170, 255), Thickness = 3, Transparency = 0.35 }),
	})
	new("Frame", {
		Name = "InnerRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.94),
		BackgroundTransparency = 1,
		Parent = lens,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.55 }),
	})
	-- Punto central iluminado con halo
	new("Frame", {
		Name = "DotGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.fromRGB(255, 60, 60),
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = lens,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	-- Retícula
	local function line(size: UDim2, pos: UDim2)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = size, Position = pos, BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = lens })
	end
	line(UDim2.new(0.42, 0, 0, 2), UDim2.fromScale(0.25, 0.5))
	line(UDim2.new(0.42, 0, 0, 2), UDim2.fromScale(0.75, 0.5))
	line(UDim2.new(0, 2, 0.42, 0), UDim2.fromScale(0.5, 0.75))
	line(UDim2.new(0, 2, 0.2, 0), UDim2.fromScale(0.5, 0.1))
	-- Mil-dots para compensar la caída
	for i = 1, 4 do
		line(UDim2.fromOffset(10 - i, 2), UDim2.new(0.5, 0, 0.5, i * 22))
	end
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.fromRGB(255, 40, 40),
		BorderSizePixel = 0,
		Parent = lens,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local breath = new("Frame", {
		Name = "Breath",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(220, 6),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BorderSizePixel = 0,
		Parent = scope,
	}, { Make.Corner(3) })
	refs.BreathFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 200, 255), BorderSizePixel = 0, Parent = breath }, { Make.Corner(3) })
	Make.Label("SHIFT: aguantar respiración  ·  Z / rueda: zoom", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -50),
		Size = UDim2.fromOffset(400, 18),
		TextSize = 13,
		TextColor3 = Color3.fromRGB(180, 180, 180),
		Parent = scope,
	})
	refs.Zoom = Make.Label("", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -40, 1, -40), Size = UDim2.fromOffset(120, 30), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 22, Parent = scope })
	refs.Scope = scope
end

local function buildCrosshair(parent: Instance)
	local ch = new("Frame", { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Visible = false, Parent = parent })
	refs.CrossLines = {}
	for i, dir in { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) } do
		local horizontal = dir.Y == 0
		refs.CrossLines[i] = {
			Dir = dir,
			Frame = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = if horizontal then UDim2.fromOffset(10, 2) else UDim2.fromOffset(2, 10),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Parent = ch,
			}, { new("UIStroke", { Thickness = 1, Transparency = 0.5 }) }),
		}
	end
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = ch })
	refs.Crosshair = ch

	-- Hitmarker
	local hm = new("Frame", { Name = "Hitmarker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, Visible = false, Parent = parent })
	refs.HitLines = {}
	for i, rot in { 45, 135, 225, 315 } do
		local r = math.rad(rot)
		refs.HitLines[i] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(r) * 12, 0.5, math.sin(r) * 12),
			Size = UDim2.fromOffset(10, 2),
			Rotation = rot,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = hm,
		})
	end
	refs.Hitmarker = hm
	refs.HitText = Make.Label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Size = UDim2.fromOffset(400, 26),
		Font = T.FontBlack,
		TextSize = 20,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = parent,
	})
end

local function buildBottom(parent: Instance)
	local ammo = new("Frame", { Name = "Ammo", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 1, -30), Size = UDim2.fromOffset(240, 80), BackgroundTransparency = 1, Visible = false, Parent = parent })
	refs.AmmoText = Make.Label("5 / 5", { Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Right, Font = T.FontBlack, TextSize = 40, TextStrokeTransparency = 0.6, Parent = ammo })
	refs.WeaponName = Make.Label("", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.SubText, TextSize = 16, Parent = ammo })
	refs.Ammo = ammo

	-- Barra de ranuras (1 rifle / 2 cuchillo) como en Sniper Duels
	local slots = new("Frame", { Name = "Slots", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(200, 74), BackgroundTransparency = 1, Visible = false, Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.SlotFrames = {}
	for i, icon in { "🔫", "🔪" } do
		local f = new("Frame", { Size = UDim2.fromOffset(84, 74), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.25, LayoutOrder = i, Parent = slots }, { Make.Corner(10), Make.Stroke(T.Stroke, 2) })
		Make.Label(tostring(i), { Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(20, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = T.SubText, Parent = f })
		Make.Label(icon, { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 40), TextSize = 30, Parent = f })
		local sub = Make.Label("", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Font = T.FontBlack, Parent = f })
		refs.SlotFrames[i] = { Frame = f, Sub = sub }
	end
	refs.Slots = slots
	refs.Status = Make.Label("", { Position = UDim2.fromOffset(16, 70), Size = UDim2.fromOffset(520, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = Color3.fromRGB(180, 255, 200), TextStrokeTransparency = 0.5, Parent = parent })
	refs.Hint = Make.Label("C agacharse · Shift+C deslizarse · Q cuchillo · M menú", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(600, 16), TextSize = 12, TextColor3 = T.SubText, Visible = false, Parent = parent })

	local hp = new("Frame", { Name = "Health", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 30, 1, -36), Size = UDim2.fromOffset(260, 14), BackgroundColor3 = Color3.fromRGB(30, 30, 30), BackgroundTransparency = 0.2, Visible = false, Parent = parent }, { Make.Corner(7) })
	refs.HealthFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0, Parent = hp }, { Make.Corner(7) })
	refs.HealthText = Make.Label("100", { Position = UDim2.fromOffset(0, -24), Size = UDim2.fromOffset(100, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 20, Parent = hp })
	refs.Health = hp
	refs.HurtText = Make.Label("", { Position = UDim2.fromOffset(70, -30), Size = UDim2.fromOffset(120, 30), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 28, TextColor3 = T.Danger, TextTransparency = 1, TextStrokeTransparency = 1, Parent = hp })
end

local function scorePill(parent: Instance, name: string, color: Color3, order: number)
	local f = new("Frame", { Name = name, Size = UDim2.fromOffset(220, 74), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.15, LayoutOrder = order, Parent = parent }, {
		Make.Corner(10),
		Make.Stroke(color, 2),
	})
	local label = Make.Label("", { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = if order == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f })
	local pips = new("Frame", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 14), BackgroundTransparency = 1, Parent = f }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = if order == 1 then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right }),
	})
	-- Barra de vida del equipo (con una barra blanca "fantasma" que baja
	-- despacio para que se note cada impacto)
	local bar = new("Frame", { Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 0, 14), BackgroundColor3 = Color3.fromRGB(25, 25, 30), BorderSizePixel = 0, Parent = f }, { Make.Corner(5) })
	local ghost = new("Frame", { AnchorPoint = Vector2.new(if order == 1 then 0 else 1, 0), Position = UDim2.fromScale(if order == 1 then 0 else 1, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = bar }, { Make.Corner(5) })
	local fill = new("Frame", { AnchorPoint = Vector2.new(if order == 1 then 0 else 1, 0), Position = UDim2.fromScale(if order == 1 then 0 else 1, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0, Parent = bar }, { Make.Corner(5) })
	local hpText = Make.Label("100", { Size = UDim2.fromScale(1, 1), Font = T.FontBlack, TextSize = 12, TextStrokeTransparency = 0.3, ZIndex = 3, Parent = bar })
	return { Frame = f, Label = label, Pips = pips, Color = color, Fill = fill, Ghost = ghost, HpText = hpText, Ghosted = 1 }
end

local function buildTop(parent: Instance)
	local top = new("Frame", { Name = "Score", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(600, 78), BackgroundTransparency = 1, Visible = false, Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.Me = scorePill(top, "Me", T.Accent, 1)
	local mid = new("Frame", { Size = UDim2.fromOffset(120, 74), BackgroundColor3 = T.Bg, BackgroundTransparency = 0.15, LayoutOrder = 2, Parent = top }, { Make.Corner(10) })
	refs.Timer = Make.Label("0:00", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 28), Font = T.FontBlack, TextSize = 26, Parent = mid })
	refs.RoundLabel = Make.Label("RONDA 1", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 16), TextColor3 = T.SubText, TextSize = 12, Parent = mid })
	refs.Opp = scorePill(top, "Opp", T.Danger, 3)
	refs.Top = top

	refs.Feed = new("Frame", { Name = "KillFeed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 90), Size = UDim2.fromOffset(380, 200), BackgroundTransparency = 1, Parent = parent }, {
		new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.Toasts = new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84), Size = UDim2.fromOffset(600, 200), BackgroundTransparency = 1, Parent = parent }, {
		new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

local function buildBanner(parent: Instance)
	local banner = new("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(800, 140), BackgroundTransparency = 1, Parent = parent })
	refs.BannerTitle = Make.Label("", { Size = UDim2.new(1, 0, 0, 80), Font = T.FontTitle, TextSize = 72, TextTransparency = 1, TextStrokeTransparency = 1, Parent = banner })
	refs.BannerSub = Make.Label("", { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 30), TextColor3 = T.SubText, TextSize = 22, TextTransparency = 1, Parent = banner })
	refs.Banner = banner

	refs.DamageFlash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 0, 20), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Parent = parent }, {
		new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }),
		}),
	})
	refs.DamageArrowPivot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Parent = parent })
	refs.DamageArrow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, -150),
		Size = UDim2.fromOffset(70, 8),
		BackgroundColor3 = Color3.fromRGB(255, 40, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = refs.DamageArrowPivot,
	}, { Make.Corner(4) })
end

local function buildOverlay(parent: Instance)
	-- Pantalla VS
	local vs = new("Frame", { Name = "VS", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Bg, BackgroundTransparency = 0.25, Visible = false, ZIndex = 20, Parent = parent })
	refs.VSMe = Make.Label("", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.5, -90, 0.45, 0), Size = UDim2.fromOffset(500, 60), TextXAlignment = Enum.TextXAlignment.Right, Font = T.FontBlack, TextSize = 46, TextColor3 = T.Accent, ZIndex = 21, Parent = vs })
	refs.VSOpp = Make.Label("", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 90, 0.45, 0), Size = UDim2.fromOffset(500, 60), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 46, TextColor3 = T.Danger, ZIndex = 21, Parent = vs })
	refs.VSMeSub = Make.Label("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -90, 0.45, 32), Size = UDim2.fromOffset(500, 26), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.SubText, ZIndex = 21, Parent = vs })
	refs.VSOppSub = Make.Label("", { AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0.5, 90, 0.45, 32), Size = UDim2.fromOffset(500, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, ZIndex = 21, Parent = vs })
	Make.Label("VS", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(160, 100), Font = T.FontTitle, TextSize = 80, TextColor3 = T.Gold, ZIndex = 21, Parent = vs })
	refs.VSArena = Make.Label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(600, 30), TextColor3 = T.SubText, TextSize = 20, ZIndex = 21, Parent = vs })
	refs.VS = vs

	-- Resumen final
	local sum = new("Frame", { Name = "Summary", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 330), BackgroundColor3 = T.Panel, Visible = false, ZIndex = 30, Parent = parent }, {
		Make.Corner(16),
		Make.Stroke(T.Stroke, 2),
		Make.Padding(20),
		new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.SumTitle = Make.Label("VICTORIA", { Size = UDim2.new(1, 0, 0, 56), Font = T.FontTitle, TextSize = 50, ZIndex = 31, LayoutOrder = 1, Parent = sum })
	refs.SumScore = Make.Label("", { Size = UDim2.new(1, 0, 0, 26), TextColor3 = T.SubText, ZIndex = 31, LayoutOrder = 2, Parent = sum })
	refs.SumCoins = Make.Label("", { Size = UDim2.new(1, 0, 0, 28), TextColor3 = T.Gold, TextSize = 22, ZIndex = 31, LayoutOrder = 3, Parent = sum })
	refs.SumXP = Make.Label("", { Size = UDim2.new(1, 0, 0, 28), TextColor3 = T.Blue, TextSize = 22, ZIndex = 31, LayoutOrder = 4, Parent = sum })
	refs.SumCandy = Make.Label("", { Size = UDim2.new(1, 0, 0, 26), TextColor3 = T.Candy, TextSize = 20, ZIndex = 31, LayoutOrder = 4, Parent = sum })
	refs.SumElo = Make.Label("", { Size = UDim2.new(1, 0, 0, 28), TextSize = 22, ZIndex = 31, LayoutOrder = 5, Parent = sum })
	refs.SumStreak = Make.Label("", { Size = UDim2.new(1, 0, 0, 24), TextColor3 = Color3.fromRGB(255, 140, 60), ZIndex = 31, LayoutOrder = 6, Parent = sum })
	refs.Summary = sum
end

-- Lógica ---------------------------------------------------------------------

function HUDController.Banner(title: string, sub: string?, color: Color3?, duration: number?)
	refs.BannerTitle.Text = title
	refs.BannerTitle.TextColor3 = color or T.Text
	refs.BannerSub.Text = sub or ""
	refs.BannerTitle.TextTransparency = 0
	refs.BannerTitle.TextStrokeTransparency = 0.5
	refs.BannerSub.TextTransparency = 0
	refs.Banner.Size = UDim2.fromOffset(900, 160)
	tween(refs.Banner, 0.25, { Size = UDim2.fromOffset(800, 140) }, Enum.EasingStyle.Back)
	local token = {}
	refs.BannerToken = token
	task.delay(duration or 1.6, function()
		if refs.BannerToken == token then
			tween(refs.BannerTitle, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween(refs.BannerSub, 0.4, { TextTransparency = 1 })
		end
	end)
end

function HUDController.Toast(text: string, color: Color3?)
	local toast = new("Frame", { Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.Panel, BackgroundTransparency = 0.1, Parent = refs.Toasts }, {
		Make.Corner(8),
		Make.Padding(8),
		Make.Stroke(color or T.Stroke, 1.5),
	})
	Make.Label(text, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextSize = 16, TextColor3 = color or T.Text, Parent = toast })
	task.delay(3.5, function()
		toast:Destroy()
	end)
end

local feedOrder = 0
local function addKillFeed(info: any)
	local headshot, distance = info.Headshot, info.Distance
	local involved = info.Involved
	if not involved and not headshot and distance < 300 then
		return -- de otros duelos solo se muestran headshots y tiros largos
	end
	feedOrder -= 1
	local row = new("Frame", { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = if involved then Color3.fromRGB(40, 40, 30) else T.Panel, BackgroundTransparency = 0.2, LayoutOrder = feedOrder, Parent = refs.Feed }, {
		Make.Corner(6),
		Make.Padding(6),
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	Make.Label(info.KillerName, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextSize = 15, TextColor3 = if info.KillerIsMe then T.Accent else T.Text, Parent = row })
	Make.Label(string.format("[%s%s · %dst]", Weapons.Get(info.WeaponId).DisplayName, if headshot then " ✦" else "", distance), { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextColor3 = if headshot then T.Gold else T.SubText, Parent = row })
	Make.Label(info.VictimName, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextSize = 15, TextColor3 = if info.VictimIsMe then T.Danger else T.Text, Parent = row })
	task.delay(6, function()
		row:Destroy()
	end)
end

local function setPips(pill, score: number, total: number)
	for _, c in pill.Pips:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i = 1, total do
		new("Frame", { Size = UDim2.fromOffset(26, 10), BackgroundColor3 = if i <= score then pill.Color else Color3.fromRGB(60, 60, 70), BorderSizePixel = 0, Parent = pill.Pips }, { Make.Corner(5) })
	end
end

local function showSummary(state: any)
	local won = state.Won
	refs.SumTitle.Text = if won then "VICTORIA" else "DERROTA"
	refs.SumTitle.TextColor3 = if won then T.Accent else T.Danger
	refs.SumScore.Text = string.format("%d - %d contra %s%s", state.MyScore, state.OppScore, state.OpponentName, if state.Reason == "forfeit" then " (abandono)" else "")
	refs.SumCoins.Text = string.format("+%d monedas", state.Coins or 0)
	refs.SumXP.Text = string.format("+%d XP", state.XP or 0)
	refs.SumCandy.Text = if T.Halloween then string.format("+%d caramelos", state.Candies or 0) else ""
	if state.Ranked and state.EloDelta then
		local tier = Rank.FromElo(state.NewElo or 0)
		refs.SumElo.Text = string.format("ELO %s%d  →  %d  (%s)", if state.EloDelta >= 0 then "+" else "", state.EloDelta, state.NewElo or 0, tier.Name)
		refs.SumElo.TextColor3 = if state.EloDelta >= 0 then T.Accent else T.Danger
	else
		refs.SumElo.Text = if state.VsBot then "Modo solo (recompensas x0.5)" else "Duelo casual"
		refs.SumElo.TextColor3 = T.SubText
	end
	refs.SumStreak.Text = if won and (state.Streak or 0) >= 2 then string.format("🔥 Racha de %d victorias", state.Streak) else ""
	refs.Summary.Visible = true
	refs.Summary.Size = UDim2.fromOffset(380, 290)
	tween(refs.Summary, 0.35, { Size = UDim2.fromOffset(420, 330) }, Enum.EasingStyle.Back)
	task.delay(5, function()
		refs.Summary.Visible = false
	end)
end

local lastState = ""
local function onDuelState(state: any)
	ClientState.Duel = if state.State == "Ended" then nil else state
	ClientState.DuelChanged:Fire(state)

	refs.Top.Visible = state.State ~= "Ended"
	refs.Me.Label.Text = player.DisplayName .. (if state.AllyNames and state.AllyNames ~= "" then " & " .. state.AllyNames else "")
	refs.Opp.Label.Text = state.OpponentName .. (if string.find(state.OpponentName, "Práctica") then " (no dispara)" else "")
	setPips(refs.Me, state.MyScore, state.RoundsToWin)
	setPips(refs.Opp, state.OppScore, state.RoundsToWin)
	refs.RoundLabel.Text = if state.Ranked then string.format("RANKED · R%d", math.max(state.Round, 1)) else string.format("RONDA %d", math.max(state.Round, 1))

	if state.State == "Intro" then
		local myElo = player:GetAttribute("Elo") or 1000
		refs.VSMe.Text = player.DisplayName
		refs.VSOpp.Text = state.OpponentName
		refs.VSMeSub.Text = string.format("%s · %d", Rank.FromElo(myElo).Name, myElo)
		refs.VSOppSub.Text = if state.OpponentIsBot then "BOT · IA" else string.format("%s · %d", Rank.FromElo(state.OpponentElo or 1000).Name, state.OpponentElo or 1000)
		refs.VSMe.Text = player.DisplayName .. (if state.AllyNames and state.AllyNames ~= "" then " & " .. state.AllyNames else "")
		refs.VSArena.Text = string.format("%s  ·  Mapa: %s  ·  Primero a %d", if state.Ranked then "RANKED" elseif state.VsBot then "MODO SOLO" elseif state.Mode == "2v2" then "2v2" else "CASUAL", state.Arena, state.RoundsToWin)
		refs.VS.Visible = true
		refs.VS.BackgroundTransparency = 1
		tween(refs.VS, 0.4, { BackgroundTransparency = 0.25 })
	elseif state.State == "Countdown" then
		refs.VS.Visible = false
		local n = state.Countdown or 3
		task.spawn(function()
			for i = n, 1, -1 do
				if not ClientState.Duel or ClientState.Duel.State ~= "Countdown" then
					return
				end
				HUDController.Banner(tostring(i), if i == n then "RONDA " .. state.Round else nil, T.Text, 0.8)
				EffectsController.PlaySound("Countdown", 0.6)
				task.wait(1)
			end
		end)
	elseif state.State == "Live" and lastState == "Countdown" then
		HUDController.Banner("¡YA!", nil, T.Accent, 0.6)
	elseif state.State == "RoundEnd" then
		local won = state.RoundWon == true
		if state.IsDraw then
			HUDController.Banner("EMPATE", "Nadie suma punto", T.SubText, 2.5)
		else
			local sub = if state.Reason == "kill"
				then string.format("%s%d studs", if state.Headshot then "HEADSHOT · " else "", state.Distance)
				elseif state.Reason == "time" then "Tiempo agotado: gana quien tiene más vida"
				else ""
			HUDController.Banner(if won then "RONDA GANADA" else "RONDA PERDIDA", sub, if won then T.Accent else T.Danger, 2.5)
		end
		EffectsController.PlaySound(if won then "RoundWin" else "RoundLose", 0.7)
	elseif state.State == "Ended" then
		refs.VS.Visible = false
		showSummary(state)
	end
	lastState = state.State
end

local hitToken = {}
-- Personajes por equipo (atributo SD_Team que pone el servidor)
local teamCache: { Model } = {}
local teamCacheAt = 0
local function duelCharacters(): { Model }
	if os.clock() - teamCacheAt > 0.5 then
		teamCacheAt = os.clock()
		teamCache = {}
		for _, m in workspace:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("SD_Team") ~= nil and m:FindFirstChildOfClass("Humanoid") then
				table.insert(teamCache, m)
			end
		end
	end
	return teamCache
end

local function teamHealth(mine: boolean): (number, number)
	local myTeam = player.Character and player.Character:GetAttribute("SD_Team")
	local hp, max = 0, 0
	if type(myTeam) ~= "string" then
		return 0, 0
	end
	local myDuel = string.match(myTeam, "^(.-):") or ""
	for _, m in duelCharacters() do
		local team = if m.Parent then m:GetAttribute("SD_Team") else nil
		-- Solo personajes de mi duelo
		if type(team) == "string" and (string.match(team, "^(.-):") or "") == myDuel and (team == myTeam) == mine then
			local h = m:FindFirstChildOfClass("Humanoid")
			if h then
				hp += math.max(h.Health, 0)
				max += h.MaxHealth
			end
		end
	end
	return hp, max
end

local function updateHealthPill(pill, mine: boolean)
	local hp, max = teamHealth(mine)
	if max <= 0 then
		pill.Fill.Size = UDim2.fromScale(1, 1)
		pill.Ghost.Size = UDim2.fromScale(1, 1)
		pill.HpText.Text = ""
		pill.Ghosted = 1
		return
	end
	local frac = math.clamp(hp / max, 0, 1)
	pill.Fill.Size = UDim2.fromScale(frac, 1)
	-- La barra blanca baja poco a poco detrás de la de color
	pill.Ghosted = if pill.Ghosted > frac then math.max(frac, pill.Ghosted - 0.012) else frac
	pill.Ghost.Size = UDim2.fromScale(pill.Ghosted, 1)
	pill.HpText.Text = string.format("%d ❤", math.ceil(hp))
end

-- Número de daño que sube y se desvanece en el punto del impacto
local function damageNumber(position: Vector3, text: string, color: Color3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Name = "SD_DamageNumber"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace.CurrentCamera
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(if big then 260 else 160, if big then 70 else 50), AlwaysOnTop = true, LightInfluence = 0, StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0), Parent = anchor })
	local label = Make.Label(text, { Size = UDim2.fromScale(1, 1), Font = T.FontBlack, TextScaled = true, TextColor3 = color, TextStrokeTransparency = 0, Parent = bb })
	tween(bb, 1.1, { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) })
	task.delay(0.5, function()
		tween(label, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	game:GetService("Debris"):AddItem(anchor, 1.3)
end

-- Destello rojo sobre el rival al darle
local function flashCharacterNear(position: Vector3, color: Color3)
	local best, bestD = nil, 8
	for _, m in duelCharacters() do
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and m ~= player.Character then
			local d = (root.Position - position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	if not best then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = "SD_HitFlash"
	h.FillColor = color
	h.OutlineColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.2
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = best
	tween(h, 0.45, { FillTransparency = 1, OutlineTransparency = 1 })
	game:GetService("Debris"):AddItem(h, 0.5)
end

local function onHitConfirm(zone: string, damage: number, killed: boolean, distance: number, position: Vector3?, hpLeft: number?)
	local color = if zone == "Head" then T.Gold elseif killed then T.Danger else Color3.new(1, 1, 1)
	for _, l in refs.HitLines do
		l.BackgroundColor3 = color
	end
	refs.Hitmarker.Visible = true
	refs.Hitmarker.Size = UDim2.fromOffset(52, 52)
	tween(refs.Hitmarker, 0.15, { Size = UDim2.fromOffset(36, 36) })
	local text = if killed then (if zone == "Head" then "HEADSHOT" else "ELIMINADO") else ("-" .. damage)
	refs.HitText.Text = string.format("%s  ·  %d studs%s", text, distance, if hpLeft and not killed then string.format("  ·  le quedan %d ❤", math.ceil(hpLeft)) else "")
	if typeof(position) == "Vector3" then
		damageNumber(position, if killed then (if zone == "Head" then "💀 HEADSHOT" else "💀 -" .. damage) else "-" .. damage, color, killed or zone == "Head")
		flashCharacterNear(position, if zone == "Head" then T.Gold else Color3.fromRGB(255, 40, 40))
	end
	teamCacheAt = 0
	refs.HitText.TextColor3 = color
	refs.HitText.TextTransparency = 0
	refs.HitText.TextStrokeTransparency = 0.5
	local token = {}
	hitToken = token
	task.delay(0.35, function()
		if hitToken == token then
			refs.Hitmarker.Visible = false
		end
	end)
	task.delay(1.4, function()
		if hitToken == token then
			tween(refs.HitText, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
	EffectsController.PlaySound(if zone == "Head" then "Headshot" else "Hitmarker", 1, nil, if zone == "Head" then 1.35 else 1)
	if killed then
		task.delay(0.08, function()
			EffectsController.PlaySound("Kill", 1, nil, 0.7)
		end)
	end
end

local function onDamaged(fromPos: Vector3, damage: number, health: number)
	EffectsController.Shake(1.4)
	EffectsController.PlaySound("Hurt", 0.5)
	refs.HurtText.Text = string.format("-%d", damage)
	refs.HurtText.TextTransparency = 0
	refs.HurtText.TextStrokeTransparency = 0.3
	tween(refs.HurtText, 1.2, { TextTransparency = 1, TextStrokeTransparency = 1 })
	local _ = health
	refs.DamageFlash.BackgroundTransparency = 0.35
	tween(refs.DamageFlash, 0.8, { BackgroundTransparency = 1 })
	local cf = camera.CFrame
	local rel = cf:PointToObjectSpace(fromPos)
	local angle = math.deg(math.atan2(rel.X, -rel.Z))
	refs.DamageArrowPivot.Rotation = angle
	refs.DamageArrow.BackgroundTransparency = 0
	tween(refs.DamageArrow, 1.5, { BackgroundTransparency = 1 })
end

local function update()
	local armed = ClientState.Armed
	local duel = ClientState.Duel
	refs.Ammo.Visible = armed
	refs.Health.Visible = armed
	refs.Scope.Visible = armed and ClientState.Scoped
	refs.Crosshair.Visible = armed and not ClientState.Scoped and ClientState.ScopeProgress < 0.5 and not ClientState.MenuOpen

	refs.Slots.Visible = armed
	refs.Hint.Visible = armed
	-- Vaivén y temblor sobre la retícula (en vez de sobre la cámara)
	local sway = ClientState.Sway or Vector2.zero
	local shk = ClientState.ShakeOffset or Vector3.zero
	local px = (camera.ViewportSize.Y / 2) / math.tan(math.rad(camera.FieldOfView / 2))
	local ox = math.tan(math.rad(sway.X)) * px
	local oy = -math.tan(math.rad(sway.Y)) * px
	-- La retícula se mueve con el vaivén (exacto: es donde va la bala); el temblor solo al crosshair
	refs.Scope.Position = UDim2.new(0, math.floor(ox + 0.5), 0, math.floor(oy + 0.5))
	refs.Crosshair.Position = UDim2.new(0.5, shk.X * 4, 0.5, shk.Y * 4)
	-- Línea de estado (diagnóstico): si algo falla, una captura de esto basta
	if duel then
		refs.Status.Text = string.format("estado: %s · armado: %s · arma: %s · ranura: %d · mira: %s · menú: %s · último tiro: %s", tostring(duel.State), if armed then "sí" else "NO", tostring(ClientState.WeaponId ~= "" and ClientState.WeaponId or player:GetAttribute("SD_Weapon") or "-"), ClientState.Slot, tostring(ClientState.Scoped), tostring(ClientState.MenuOpen), ClientState.LastShot ~= "" and ClientState.LastShot or "-")
		refs.Status.Visible = true
	else
		refs.Status.Visible = false
	end
	if armed then
		local w = Weapons.Get(ClientState.WeaponId)
		for i, sf in refs.SlotFrames do
			local active = ClientState.Slot == i
			local stroke = sf.Frame:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color = if active then T.Accent else T.Stroke
			sf.Frame.BackgroundTransparency = if active then 0.05 else 0.4
		end
		refs.SlotFrames[1].Sub.Text = if ClientState.Reloading then "..." else string.format("%d / %d", ClientState.Mag, w.MagSize)
		refs.SlotFrames[2].Sub.Text = "CUCHILLO"
		refs.AmmoText.Text = if ClientState.Reloading then "RECARGANDO" else string.format("%d / %d", ClientState.Mag, w.MagSize)
		refs.AmmoText.TextColor3 = if ClientState.Mag == 0 and not ClientState.Reloading then T.Danger else T.Text
		refs.WeaponName.Text = w.DisplayName
		local zoomFov = camera.FieldOfView
		refs.Zoom.Text = string.format("%.1fx", math.tan(math.rad(35)) / math.tan(math.rad(zoomFov / 2)))
		refs.BreathFill.Size = UDim2.fromScale(ClientState.Breath, 1)
		refs.BreathFill.BackgroundColor3 = if ClientState.Breath < 0.25 then T.Danger else Color3.fromRGB(120, 200, 255)

		-- Crosshair dinámico según dispersión real
		local spread = WeaponController.CurrentSpread()
		local px = math.tan(math.rad(spread)) / math.tan(math.rad(camera.FieldOfView / 2)) * (camera.ViewportSize.Y / 2)
		local gap = math.clamp(px, 4, 200)
		for _, l in refs.CrossLines do
			l.Frame.Position = UDim2.fromOffset(l.Dir.X * (gap + 5), l.Dir.Y * (gap + 5))
		end

		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
			refs.HealthFill.Size = UDim2.fromScale(frac, 1)
			refs.HealthFill.BackgroundColor3 = if frac > 0.5 then T.Accent elseif frac > 0.25 then T.Gold else T.Danger
			refs.HealthText.Text = tostring(math.ceil(hum.Health))
			local low = math.clamp(1 - frac / 0.4, 0, 1)
			lowHp.Enabled = low > 0 and hum.Health > 0
			lowHp.Saturation = -0.7 * low
			lowHp.TintColor = Color3.new(1, 1 - 0.25 * low, 1 - 0.25 * low)
		end
	else
		lowHp.Enabled = false
	end

	if duel then
		updateHealthPill(refs.Me, true)
		updateHealthPill(refs.Opp, false)
		local remaining = math.max(0, (duel.EndsAt or 0) - workspace:GetServerTimeNow())
		refs.Timer.Text = string.format("%d:%02d", remaining // 60, math.floor(remaining % 60))
		refs.Timer.TextColor3 = if duel.State == "Live" and remaining < 10 then T.Danger else T.Text
	end
end

function HUDController.Start()
	gui = new("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })
	buildScope(gui)
	buildCrosshair(gui)
	buildBottom(gui)
	buildTop(gui)
	buildBanner(gui)
	buildOverlay(gui)

	Net.Event("DuelState").OnClientEvent:Connect(onDuelState)
	Net.Event("HitConfirm").OnClientEvent:Connect(onHitConfirm)
	Net.Event("ShotResult").OnClientEvent:Connect(function(text: string)
		ClientState.LastShot = text
	end)
	Net.Event("Damaged").OnClientEvent:Connect(onDamaged)
	Net.Event("KillFeed").OnClientEvent:Connect(addKillFeed)
	Net.Event("Announce").OnClientEvent:Connect(function(from: string, msg: string)
		if msg == "__SKYFACE__" then
			local Ambient = require(script.Parent.AmbientController)
			if Ambient.ShowCommander then
				Ambient.ShowCommander(20)
			end
			return
		end
		HUDController.Banner("📢 " .. msg, "Anuncio de " .. from, T.Accent, 5)
	end)
	Net.Event("Notify").OnClientEvent:Connect(function(text: string, color: Color3?)
		HUDController.Toast(text, color)
	end)
	RunService.RenderStepped:Connect(update)
end

return HUDController
