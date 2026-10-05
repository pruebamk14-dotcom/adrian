--!strict
-- Tienda premium a pantalla completa:
--  ⭐ Destacado  (arma exclusiva con vista 3D giratoria, VIP, mejor pack)
--  🔫 Armas      (tarjetas con modelo 3D, barras de estadísticas, compra)
--  🎁 Cajas      (ruleta animada; caja estándar y de Halloween)
--  💰 Monedas    (packs con bonus)
--  👑 VIP        (beneficios del pase)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local GunBuilder = require(Shared.GunBuilder)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Make)
local InspectUI = require(script.Parent.InspectUI)

local T = Make.Theme
local new = Make.new
local M = GameConfig.Monetization
local camera = workspace.CurrentCamera

local ShopUI = {}

local root: Frame
local content: Frame
local pages: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Featured"
local spinning: { { Model: Model, Base: CFrame, Speed: number } } = {}
local refreshers: { () -> () } = {}
local coinLabel: TextLabel
local candyLabel: TextLabel
local blur: BlurEffect

local GOLD_GRAD = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 120)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 225, 120)),
})

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function robux(key: string): string
	local price = M.RobuxPrices[key]
	return if price then ("R$ " .. price) else "R$ —"
end

-- Efecto hover: escala + brillo del borde
local function hover(button: GuiButton, target: GuiObject?, stroke: UIStroke?)
	local t = target or button
	local scale = t:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = t })
	button.MouseEnter:Connect(function()
		tween(scale, 0.15, { Scale = 1.03 })
		if stroke then
			tween(stroke, 0.15, { Thickness = 3, Transparency = 0 })
		end
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.15, { Scale = 1 })
		if stroke then
			tween(stroke, 0.15, { Thickness = 1.5, Transparency = 0.3 })
		end
	end)
end

-- Destello diagonal que recorre una tarjeta
local function shine(card: GuiObject)
	local s = new("Frame", {
		Name = "Shine",
		Size = UDim2.new(0.25, 0, 2, 0),
		Position = UDim2.new(-0.4, 0, -0.5, 0),
		Rotation = 20,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = card,
	}, {
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	task.spawn(function()
		while s.Parent do
			s.Position = UDim2.new(-0.4, 0, -0.5, 0)
			tween(s, 1.2, { Position = UDim2.new(1.3, 0, -0.5, 0) }, Enum.EasingStyle.Sine)
			task.wait(math.random(30, 50) / 10)
		end
	end)
end

local function ribbon(parent: GuiObject, text: string, color: Color3)
	new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		Text = "  " .. text .. "  ",
		TextColor3 = Color3.fromRGB(20, 12, 4),
		Font = T.FontBlack,
		TextSize = 12,
		ZIndex = 9,
		Parent = parent,
	}, { Make.Corner(12) })
end

-- Vista 3D del arma que gira
local function weaponViewport(parent: GuiObject, weaponId: string, skinId: string, size: UDim2, pos: UDim2?): ViewportFrame
	local vp = new("ViewportFrame", {
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 140, 160),
		LightColor = Color3.fromRGB(255, 230, 200),
		LightDirection = Vector3.new(-1, -1, -0.5),
		Parent = parent,
	})
	local cam = new("Camera", { FieldOfView = 30, Parent = vp })
	vp.CurrentCamera = cam
	local model = GunBuilder.Build(weaponId, skinId)
	local base = CFrame.new(0, 0, 0)
	model:PivotTo(base)
	model.Parent = vp
	local _, sizeV = model:GetBoundingBox()
	local dist = sizeV.Magnitude * 1.65
	cam.CFrame = CFrame.lookAt(Vector3.new(dist * 0.9, dist * 0.25, 0), Vector3.zero)
	table.insert(spinning, { Model = model, Base = base, Speed = 0.6 })
	return vp
end

local function statBar(parent: Instance, label: string, value: number, order: number)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Make.Label(label, { Size = UDim2.new(0.42, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 11, TextColor3 = T.SubText, Parent = row })
	local track = new("Frame", { Position = UDim2.new(0.44, 0, 0.5, -3), Size = UDim2.new(0.56, 0, 0, 6), BackgroundColor3 = Color3.fromRGB(50, 40, 60), BorderSizePixel = 0, Parent = row }, { Make.Corner(3) })
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0, Parent = track }, {
		Make.Corner(3),
		new("UIGradient", { Color = ColorSequence.new(T.Accent, T.Purple) }),
	})
	task.delay(0.1 + order * 0.05, function()
		tween(fill, 0.6, { Size = UDim2.fromScale(math.clamp(value, 0.05, 1), 1) }, Enum.EasingStyle.Quart)
	end)
end

local function weaponStats(w: Weapons.Weapon)
	return {
		{ "Velocidad bala", (w.MuzzleVelocity - 900) / 1400 },
		{ "Cadencia", 1 - (w.FireCooldown - 0.3) / 1.7 },
		{ "Rapidez de mira", 1 - (w.ScopeInTime - 0.1) / 0.22 },
		{ "Estabilidad", 1 - (w.Sway - 0.15) / 0.4 },
		{ "Cargador", w.MagSize / 10 },
	}
end

local function primaryButton(parent: Instance, text: string, color: Color3, size: UDim2, pos: UDim2, onClick: () -> ()): TextButton
	local b = Make.Button(text, color, { Size = size, Position = pos, TextSize = 18, ZIndex = 6, Parent = parent }, onClick)
	new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), Rotation = 90, Parent = b })
	hover(b)
	return b
end

-- Páginas ------------------------------------------------------------------

local function page(name: string): Frame
	local p = new("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = T.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = content,
	})
	pages[name] = p
	return p
end

local function featureCard(parent: Instance, size: UDim2, pos: UDim2, colorA: Color3, colorB: Color3): (TextButton, UIStroke)
	local stroke = new("UIStroke", { Color = colorA, Thickness = 1.5, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local card = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = size,
		Position = pos,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		Parent = parent,
	}, {
		Make.Corner(18),
		stroke,
		new("UIGradient", { Color = ColorSequence.new(colorA, colorB), Rotation = 35 }),
	})
	hover(card, card, stroke)
	return card, stroke
end

local function buildFeatured()
	local p = page("Featured")
	local reaper = Weapons.Get("Reaper")
	local hero = featureCard(p, UDim2.new(0.62, -10, 0, 360), UDim2.fromOffset(0, 0), Color3.fromRGB(70, 20, 90), Color3.fromRGB(20, 8, 26))
	shine(hero)
	ribbon(hero, reaper.Tagline or "EXCLUSIVA", T.Accent)
	Make.Label("ARMA EXCLUSIVA", { Position = UDim2.fromOffset(26, 22), Size = UDim2.fromOffset(300, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = T.Accent, ZIndex = 5, Parent = hero })
	local title = Make.Label(reaper.DisplayName, { Position = UDim2.fromOffset(24, 40), Size = UDim2.fromOffset(500, 64), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 60, ZIndex = 5, Parent = hero })
	new("UIGradient", { Color = GOLD_GRAD, Parent = title })
	Make.Label(reaper.Description, { Position = UDim2.fromOffset(26, 104), Size = UDim2.new(0.55, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextSize = 14, TextColor3 = T.SubText, ZIndex = 5, Parent = hero })
	weaponViewport(hero, "Reaper", "Headless", UDim2.new(0.75, 0, 1, -40), UDim2.new(0.28, 0, 0, 30))
	local buy = primaryButton(hero, robux("WeaponReaper"), T.Accent, UDim2.fromOffset(200, 52), UDim2.new(0, 26, 1, -78), function()
		Net.Event("PromptPurchase"):FireServer("WeaponReaper")
	end)
	table.insert(refreshers, function()
		local d = ClientState.Data
		local owned = d and d.Inventory.Weapons and d.Inventory.Weapons.Reaper
		buy.Text = if owned then "✓ EN TU ARSENAL" else robux("WeaponReaper")
		buy.Active = not owned
	end)

	-- VIP
	local vip = featureCard(p, UDim2.new(0.38, 0, 0, 175), UDim2.new(0.62, 10, 0, 0), Color3.fromRGB(110, 75, 10), Color3.fromRGB(30, 20, 5))
	shine(vip)
	local vt = Make.Label("👑 VIP", { Position = UDim2.fromOffset(20, 16), Size = UDim2.fromOffset(240, 44), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 42, ZIndex = 5, Parent = vip })
	new("UIGradient", { Color = GOLD_GRAD, Parent = vt })
	Make.Label("x2 monedas · x2 caramelos · etiqueta dorada", { Position = UDim2.fromOffset(20, 62), Size = UDim2.new(1, -40, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = Color3.fromRGB(255, 225, 160), ZIndex = 5, Parent = vip })
	local vb = primaryButton(vip, robux("VIP"), T.Gold, UDim2.fromOffset(160, 44), UDim2.new(0, 20, 1, -62), function()
		Net.Event("PromptPurchase"):FireServer("VIP")
	end)
	vb.TextColor3 = Color3.fromRGB(30, 20, 5)
	table.insert(refreshers, function()
		local isVip = ClientState.Data and ClientState.Data.VIP
		vb.Text = if isVip then "✓ ERES VIP" else robux("VIP")
	end)

	-- Mejor valor
	local best = featureCard(p, UDim2.new(0.38, 0, 0, 175), UDim2.new(0.62, 10, 0, 185), Color3.fromRGB(20, 80, 60), Color3.fromRGB(6, 26, 20))
	ribbon(best, "MEJOR VALOR +20%", Color3.fromRGB(120, 255, 160))
	local bt = Make.Label(string.format("%d", M.CoinPacks.Coins15000), { Position = UDim2.fromOffset(20, 18), Size = UDim2.fromOffset(260, 46), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 40, ZIndex = 5, Parent = best })
	new("UIGradient", { Color = GOLD_GRAD, Parent = bt })
	Make.Label("monedas", { Position = UDim2.fromOffset(20, 62), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = T.SubText, ZIndex = 5, Parent = best })
	primaryButton(best, robux("Coins15000"), Color3.fromRGB(60, 200, 120), UDim2.fromOffset(160, 44), UDim2.new(0, 20, 1, -62), function()
		Net.Event("PromptPurchase"):FireServer("Coins15000")
	end)
end

local function buildWeapons()
	local p = page("Weapons")
	new("UIGridLayout", { CellSize = UDim2.new(0.333, -12, 0, 330), CellPadding = UDim2.fromOffset(16, 16), SortOrder = Enum.SortOrder.LayoutOrder, Parent = p })
	for i, id in Weapons.Order do
		local w = Weapons.List[id]
		local accent = if w.Exclusive then T.Gold elseif w.CoinPrice then T.Purple else T.Blue
		local card, _ = featureCard(p, UDim2.new(), UDim2.new(), Color3.fromRGB(40, 28, 50), Color3.fromRGB(18, 12, 22))
		card.LayoutOrder = (if w.Exclusive then 0 elseif w.CoinPrice then 10 else 20) + i
		if w.Exclusive then
			shine(card)
			ribbon(card, "EXCLUSIVA", T.Gold)
		elseif w.CoinPrice then
			ribbon(card, "TIENDA", T.Purple)
		end
		weaponViewport(card, id, if w.Exclusive then "Headless" else "Default", UDim2.new(1, 0, 0, 130), UDim2.fromOffset(0, 18))
		Make.Button("👁 INSPECCIONAR", Color3.fromRGB(30, 22, 36), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 120), Size = UDim2.fromOffset(130, 26), TextSize = 12, ZIndex = 7, Parent = card }, function()
			ShopUI.Close()
			InspectUI.Open("Rifle", id, if w.Exclusive then "Headless" else "Default")
		end)
		local name = Make.Label(w.DisplayName, { Position = UDim2.fromOffset(16, 148), Size = UDim2.new(1, -32, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 22, ZIndex = 5, Parent = card })
		if w.Exclusive then
			new("UIGradient", { Color = GOLD_GRAD, Parent = name })
		end
		local stats = new("Frame", { Position = UDim2.fromOffset(16, 178), Size = UDim2.new(1, -32, 0, 92), BackgroundTransparency = 1, ZIndex = 5, Parent = card }, {
			new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for j, st in weaponStats(w) do
			statBar(stats, st[1], st[2], j)
		end
		local btn = primaryButton(card, "", accent, UDim2.new(1, -32, 0, 40), UDim2.new(0, 16, 1, -52), function() end)
		local function refresh()
			local d = ClientState.Data
			if not d then
				return
			end
			local owned = Weapons.Owns(d, id)
			local equipped = d.Equipped.Weapon == id
			if equipped then
				btn.Text = "✓ EQUIPADA"
			elseif owned then
				btn.Text = "EQUIPAR"
			elseif w.RobuxProduct then
				btn.Text = robux(w.RobuxProduct)
			elseif w.CoinPrice then
				btn.Text = string.format("● %d", w.CoinPrice)
			else
				btn.Text = "🔒 NIVEL " .. w.UnlockLevel
			end
		end
		table.insert(refreshers, refresh)
		btn.MouseButton1Click:Connect(function()
			local d = ClientState.Data
			if not d then
				return
			end
			if Weapons.Owns(d, id) then
				if d.Equipped.Weapon ~= id then
					Net.Function("EquipWeapon"):InvokeServer(id)
				end
			elseif w.RobuxProduct then
				Net.Event("PromptPurchase"):FireServer(w.RobuxProduct)
			elseif w.CoinPrice then
				local res = Net.Function("BuyWeapon"):InvokeServer(id)
				if res and not res.Ok then
					btn.Text = res.Error
					task.delay(1.5, refresh)
				end
			end
		end)
	end
end

local function buildCrates()
	local p = page("Crates")
	local rolling = false
	local crateId = if T.Halloween then "Halloween" else "Standard"

	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Parent = p }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }),
	})
	local reel = new("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, -10, 0, 170), BackgroundColor3 = Color3.fromRGB(12, 8, 16), ClipsDescendants = true, Parent = p }, {
		Make.Corner(16),
		new("UIStroke", { Color = T.Stroke, Thickness = 2 }),
	})
	local strip = new("Frame", { Size = UDim2.fromOffset(0, 140), Position = UDim2.fromOffset(0, 15), BackgroundTransparency = 1, Parent = reel })
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = T.Gold, BorderSizePixel = 0, ZIndex = 5, Parent = reel }, {
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0) }) }),
	})
	for _, side in { 0, 1 } do
		new("Frame", { AnchorPoint = Vector2.new(side, 0), Position = UDim2.fromScale(side, 0), Size = UDim2.new(0.18, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(12, 8, 16), BorderSizePixel = 0, ZIndex = 4, Parent = reel }, {
			new("UIGradient", { Rotation = if side == 0 then 0 else 180, Transparency = NumberSequence.new(0, 1) }),
		})
	end
	local result = Make.Label("", { Position = UDim2.fromOffset(0, 250), Size = UDim2.new(1, 0, 0, 34), Font = T.FontTitle, TextSize = 30, Parent = p })
	local odds = Make.Label("", { Position = UDim2.fromOffset(0, 286), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = T.SubText, Parent = p })

	local function describe()
		result.TextColor3 = if crateId == "Halloween" then T.Candy else T.Text
		result.Text = if crateId == "Halloween"
			then string.format("🎃 Caja de Halloween · %d caramelos", GameConfig.HalloweenCratePrice)
			else string.format("Caja estándar · %d monedas", GameConfig.CratePrice)
		local parts = {}
		for _, r in Skins.Rarities do
			table.insert(parts, string.format("%s %.1f%%", r.Name, r.Weight))
		end
		odds.Text = table.concat(parts, "  ·  ") .. string.format("   |   Duplicados: devuelve %d%%", GameConfig.DuplicateRefund * 100)
	end

	local CELL = 150
	local function cellFor(s: Skins.Skin, x: number)
		local rarity = Skins.RarityInfo(s.Rarity)
		local f = new("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(CELL - 12, 140), BackgroundColor3 = Color3.fromRGB(28, 20, 34), Parent = strip }, {
			Make.Corner(12),
			new("UIStroke", { Color = rarity.Color, Thickness = 2 }),
			new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), rarity.Color), Rotation = 90, Transparency = NumberSequence.new(0, 0.6) }),
		})
		new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 70), BackgroundColor3 = s.Color, Parent = f }, { Make.Corner(10), new("UIGradient", { Color = ColorSequence.new(s.Color, s.Accent), Rotation = 30 }) })
		Make.Label(s.DisplayName, { Position = UDim2.fromOffset(8, 86), Size = UDim2.new(1, -16, 0, 20), TextSize = 15, Parent = f })
		Make.Label(s.Rarity, { Position = UDim2.fromOffset(8, 108), Size = UDim2.new(1, -16, 0, 18), TextSize = 13, TextColor3 = rarity.Color, Parent = f })
	end

	local function preview()
		strip:ClearAllChildren()
		strip.Position = UDim2.fromOffset(0, 15)
		local rng = Random.new()
		for i = 1, 12 do
			cellFor(Skins.Roll(rng, crateId), (i - 1) * CELL)
		end
	end

	local function tab(text: string, id: string, color: Color3)
		Make.Button(text, color, { Size = UDim2.fromOffset(200, 48), TextSize = 16, Parent = header }, function()
			if not rolling then
				crateId = id
				describe()
				preview()
			end
		end)
	end
	if T.Halloween then
		tab("🎃 HALLOWEEN", "Halloween", T.Purple)
	end
	tab("📦 ESTÁNDAR", "Standard", T.PanelLight)

	local open = primaryButton(p, "ABRIR CAJA", T.Gold, UDim2.fromOffset(260, 58), UDim2.new(0.5, -130, 0, 316), function() end)
	open.TextColor3 = Color3.fromRGB(30, 20, 5)
	open.MouseButton1Click:Connect(function()
		if rolling then
			return
		end
		rolling = true
		local res = Net.Function("BuyCrate"):InvokeServer(crateId)
		if not res or not res.Ok then
			result.Text = res and res.Error or "Error"
			result.TextColor3 = T.Danger
			rolling = false
			return
		end
		strip:ClearAllChildren()
		strip.Position = UDim2.fromOffset(0, 15)
		local rng = Random.new()
		local winIndex = 45
		for i = 1, winIndex + 5 do
			cellFor(if i == winIndex then Skins.Get(res.SkinId) else Skins.Roll(rng, crateId), (i - 1) * CELL)
		end
		local center = reel.AbsoluteSize.X / 2
		local target = -((winIndex - 1) * CELL + (CELL - 12) / 2 - center) + rng:NextNumber(-50, 50)
		result.Text = "..."
		result.TextColor3 = T.Text
		local tw = tween(strip, 5, { Position = UDim2.fromOffset(target, 15) }, Enum.EasingStyle.Quint)
		tw.Completed:Wait()
		local s = Skins.Get(res.SkinId)
		local rarity = Skins.RarityInfo(s.Rarity)
		local currency = if res.Currency == "Candies" then "caramelos" else "monedas"
		result.Text = if res.Duplicate then string.format("%s (duplicado) · +%d %s", s.DisplayName, res.Refund, currency) else string.format("¡%s %s!", s.Rarity, s.DisplayName)
		result.TextColor3 = rarity.Color
		-- Como en el original: enseñar la skin conseguida en la sala de inspección
		local wonSkin = res.SkinId
		task.delay(1.2, function()
			if root.Visible then
				ShopUI.Close()
				local d = ClientState.Data
				InspectUI.Open("Rifle", d and d.Equipped and d.Equipped.Weapon or "Intervention", wonSkin)
			end
		end)
		-- Destello de rareza
		local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rarity.Color, BackgroundTransparency = 0.4, ZIndex = 6, Parent = reel })
		tween(flash, 0.8, { BackgroundTransparency = 1 })
		task.delay(0.9, function()
			flash:Destroy()
		end)
		rolling = false
	end)
	describe()
	preview()
end

local function buildCoins()
	local p = page("Coins")
	new("UIGridLayout", { CellSize = UDim2.new(0.25, -12, 0, 260), CellPadding = UDim2.fromOffset(16, 16), SortOrder = Enum.SortOrder.LayoutOrder, Parent = p })
	local packs = {
		{ "Coins1000", M.CoinPacks.Coins1000, "monedas", "", Color3.fromRGB(60, 50, 20) },
		{ "Coins5000", M.CoinPacks.Coins5000, "monedas", "+10% BONUS", Color3.fromRGB(90, 70, 15) },
		{ "Coins15000", M.CoinPacks.Coins15000, "monedas", "+20% MEJOR VALOR", Color3.fromRGB(120, 90, 10) },
		{ "Candy500", M.CandyPacks.Candy500, "caramelos 🍬", "HALLOWEEN", Color3.fromRGB(110, 30, 90) },
	}
	for i, pack in packs do
		local card = featureCard(p, UDim2.new(), UDim2.new(), pack[5], Color3.fromRGB(18, 12, 22))
		card.LayoutOrder = i
		if pack[4] ~= "" then
			ribbon(card, pack[4], if i == 4 then T.Candy else T.Gold)
		end
		if i == 3 then
			shine(card)
		end
		-- Pila de monedas dibujada con círculos
		local icon = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(110, 90), BackgroundTransparency = 1, ZIndex = 5, Parent = card })
		for c = 0, math.min(i + 1, 5) do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, (c % 2) * 14 - 7, 1, -c * 10),
				Size = UDim2.fromOffset(70, 26),
				BackgroundColor3 = if i == 4 then T.Candy else T.Gold,
				ZIndex = 5 + c,
				Parent = icon,
			}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), new("UIStroke", { Color = Color3.fromRGB(120, 80, 10), Thickness = 2 }) })
		end
		local amount = Make.Label(tostring(pack[2]), { Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 40), Font = T.FontBlack, TextSize = 34, ZIndex = 5, Parent = card })
		new("UIGradient", { Color = GOLD_GRAD, Parent = amount })
		Make.Label(pack[3], { Position = UDim2.fromOffset(0, 178), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = T.SubText, ZIndex = 5, Parent = card })
		primaryButton(card, robux(pack[1]), if i == 4 then T.Candy else Color3.fromRGB(60, 200, 120), UDim2.new(1, -32, 0, 40), UDim2.new(0, 16, 1, -54), function()
			Net.Event("PromptPurchase"):FireServer(pack[1])
		end)
	end
end

local function buildVIP()
	local p = page("VIP")
	local card = featureCard(p, UDim2.new(1, -10, 0, 380), UDim2.new(), Color3.fromRGB(120, 85, 10), Color3.fromRGB(25, 16, 4))
	shine(card)
	local t = Make.Label("👑 PASE VIP", { Position = UDim2.fromOffset(34, 26), Size = UDim2.fromOffset(600, 76), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 72, ZIndex = 5, Parent = card })
	new("UIGradient", { Color = GOLD_GRAD, Parent = t })
	local list = new("Frame", { Position = UDim2.fromOffset(36, 116), Size = UDim2.new(0.6, 0, 0, 180), BackgroundTransparency = 1, ZIndex = 5, Parent = card }, {
		new("UIListLayout", { Padding = UDim.new(0, 10) }),
	})
	for _, line in {
		"💰  Doble de monedas en cada duelo",
		"🍬  Doble de caramelos durante Halloween",
		"★  Etiqueta VIP dorada en el lobby",
		"❤  Apoyas el desarrollo del juego",
	} do
		Make.Label(line, { Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 20, TextColor3 = Color3.fromRGB(255, 235, 190), ZIndex = 5, Parent = list })
	end
	local b = primaryButton(card, robux("VIP"), T.Gold, UDim2.fromOffset(260, 60), UDim2.new(0, 34, 1, -86), function()
		Net.Event("PromptPurchase"):FireServer("VIP")
	end)
	b.TextColor3 = Color3.fromRGB(30, 20, 5)
	table.insert(refreshers, function()
		b.Text = if ClientState.Data and ClientState.Data.VIP then "✓ YA ERES VIP" else robux("VIP")
	end)
	Make.Label("Los objetos de pago no dan ventaja de daño: todos los rifles matan igual.", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(520, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12, TextColor3 = Color3.fromRGB(200, 180, 140), ZIndex = 5, Parent = card })
end

-- API ------------------------------------------------------------------------

function ShopUI.SelectTab(name: string)
	currentTab = name
	for n, pg in pages do
		pg.Visible = n == name
	end
	for n, b in tabButtons do
		local active = n == name
		tween(b, 0.15, { BackgroundTransparency = if active then 0 else 1, TextColor3 = if active then Color3.fromRGB(20, 12, 4) else T.Text })
	end
end

function ShopUI.Refresh()
	local d = ClientState.Data
	if d and coinLabel then
		coinLabel.Text = string.format("● %d", d.Coins)
		candyLabel.Text = string.format("🍬 %d", d.Candies or 0)
	end
	for _, r in refreshers do
		r()
	end
end

function ShopUI.Open(tab: string?)
	root.Visible = true
	root.BackgroundTransparency = 1
	tween(root, 0.25, { BackgroundTransparency = 0.25 })
	local panel = root:FindFirstChild("Panel") :: Frame
	panel.Position = UDim2.fromScale(0.5, 0.56)
	tween(panel, 0.35, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
	blur.Enabled = true
	tween(blur, 0.3, { Size = 18 })
	ShopUI.SelectTab(tab or currentTab)
	ShopUI.Refresh()
end

function ShopUI.Close()
	root.Visible = false
	blur.Size = 0
	blur.Enabled = false
end

function ShopUI.IsOpen(): boolean
	return root ~= nil and root.Visible
end

function ShopUI.Build(gui: ScreenGui)
	blur = new("BlurEffect", { Name = "ShopBlur", Size = 0, Enabled = false, Parent = camera })
	root = new("TextButton", { Name = "Shop", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, Visible = false, ZIndex = 50, Parent = gui })
	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.84),
		BackgroundColor3 = T.Bg,
		Parent = root,
	}, {
		Make.Corner(22),
		new("UIStroke", { Color = T.Accent, Thickness = 2, Transparency = 0.4 }),
		new("UISizeConstraint", { MaxSize = Vector2.new(1300, 820), MinSize = Vector2.new(600, 420) }),
		new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 185, 215)), Rotation = 90 }),
	})

	-- Cabecera
	local title = Make.Label("TIENDA", { Position = UDim2.fromOffset(30, 16), Size = UDim2.fromOffset(400, 60), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 58, Parent = panel })
	new("UIGradient", { Color = ColorSequence.new(T.Accent, T.Purple), Parent = title })
	local pills = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 26), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = panel }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }),
	})
	local function pill(color: Color3): TextLabel
		local l = Make.Label("", { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = T.Panel, TextColor3 = color, Font = T.FontBlack, TextSize = 18, Parent = pills })
		Make.Corner(20).Parent = l
		new("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = l })
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = l })
		return l
	end
	coinLabel = pill(T.Gold)
	candyLabel = pill(T.Candy)
	candyLabel.Visible = T.Halloween
	local close = Make.Button("✕", T.PanelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(44, 44), TextSize = 20, Parent = panel }, function()
		ShopUI.Close()
	end)
	hover(close)

	-- Barra lateral
	local side = new("Frame", { Position = UDim2.fromOffset(24, 96), Size = UDim2.new(0, 200, 1, -120), BackgroundColor3 = T.Panel, Parent = panel }, {
		Make.Corner(16),
		Make.Padding(10),
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, info in {
		{ "Featured", "⭐  DESTACADO" },
		{ "Weapons", "🔫  ARMAS" },
		{ "Crates", "🎁  CAJAS" },
		{ "Coins", "💰  MONEDAS" },
		{ "VIP", "👑  VIP" },
	} do
		local b = Make.Button(info[2], T.Accent, { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 17, LayoutOrder = i, Parent = side }, function()
			ShopUI.SelectTab(info[1])
		end)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), Parent = b })
		hover(b)
		tabButtons[info[1]] = b
	end

	content = new("Frame", { Position = UDim2.fromOffset(244, 96), Size = UDim2.new(1, -268, 1, -120), BackgroundTransparency = 1, ClipsDescendants = true, Parent = panel })

	buildFeatured()
	buildWeapons()
	buildCrates()
	buildCoins()
	buildVIP()

	-- Girar los modelos 3D solo con la tienda abierta
	RunService.RenderStepped:Connect(function(dt)
		if not root.Visible then
			return
		end
		local t = os.clock()
		for _, s in spinning do
			s.Model:PivotTo(s.Base * CFrame.Angles(0, t * s.Speed, math.sin(t * 0.8) * 0.06))
		end
	end)
	ClientState.DataChanged:Connect(function()
		if root.Visible then
			ShopUI.Refresh()
		end
	end)
end

return ShopUI
