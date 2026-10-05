--!strict
-- Menú del lobby: tarjeta de perfil, cola ranked, arsenal (armas + skins),
-- tienda de cajas con animación de ruleta, ranking global y perfil/ajustes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local Rank = require(Shared.Rank)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Parent.UI.Make)
local ShopUI = require(script.Parent.Parent.UI.ShopUI)
local TradeUI = require(script.Parent.Parent.UI.TradeUI)
local AdminUI = require(script.Parent.Parent.UI.AdminUI)
local PauseMenu = require(script.Parent.Parent.UI.PauseMenu)
local DailyUI = require(script.Parent.Parent.UI.DailyUI)
local DebugOverlay = require(script.Parent.Parent.UI.DebugOverlay)
local InspectUI = require(script.Parent.Parent.UI.InspectUI)
local HUDController = require(script.Parent.HUDController)

local T = Make.Theme
local new = Make.new
local player = Players.LocalPlayer

local MenuController = {}

local gui: ScreenGui
local refs: { [string]: any } = {}
local panels: { [string]: Frame } = {}
local openPanel: string? = nil

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function makePanel(name: string, title: string): Frame
	local panel = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.6, 0, 0.66, 0),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	}, {
		Make.Corner(16),
		Make.Stroke(T.Stroke, 2),
		new("UISizeConstraint", { MinSize = Vector2.new(360, 320), MaxSize = Vector2.new(900, 620) }),
	})
	Make.Label(title, { Position = UDim2.fromOffset(24, 14), Size = UDim2.new(1, -80, 0, 38), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 34, TextColor3 = if T.Halloween then T.Accent else T.Text, Parent = panel })
	Make.Button("✕", T.PanelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(38, 38), Parent = panel }, function()
		MenuController.Close()
	end)
	local body = new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(20, 64),
		Size = UDim2.new(1, -40, 1, -84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	panels[name] = panel
	return body
end

function MenuController.Close()
	if openPanel then
		panels[openPanel].Visible = false
	end
	openPanel = nil
end

local renderers: { [string]: () -> () } = {}

function MenuController.Open(name: string)
	MenuController.Close()
	openPanel = name
	local p = panels[name]
	p.Visible = true
	p.Position = UDim2.fromScale(0.5, 0.54)
	TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	if renderers[name] then
		renderers[name]()
	end
end

-- Tarjeta de perfil ----------------------------------------------------------

local function buildProfileCard()
	local card = new("Frame", { Name = "Profile", Position = UDim2.fromOffset(16, 70), Size = UDim2.fromOffset(300, 116), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.08, Parent = gui }, {
		Make.Corner(14),
		Make.Stroke(T.Stroke, 1.5),
	})
	local thumb = new("ImageLabel", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = T.PanelLight, Parent = card }, { Make.Corner(30) })
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok then
			thumb.Image = img
		end
	end)
	Make.Label(player.DisplayName, { Position = UDim2.fromOffset(84, 12), Size = UDim2.fromOffset(200, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
	refs.Rank = Make.Label("", { Position = UDim2.fromOffset(84, 34), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, Parent = card })
	refs.Coins = Make.Label("", { Position = UDim2.fromOffset(84, 54), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = T.Gold, Parent = card })
	refs.Level = Make.Label("", { Position = UDim2.fromOffset(12, 80), Size = UDim2.new(1, -24, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = T.SubText, Parent = card })
	local bar = new("Frame", { Position = UDim2.fromOffset(12, 98), Size = UDim2.new(1, -24, 0, 6), BackgroundColor3 = T.PanelLight, BorderSizePixel = 0, Parent = card }, { Make.Corner(3) })
	refs.XPFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Blue, BorderSizePixel = 0, Parent = bar }, { Make.Corner(3) })
	refs.Profile = card
end

local function refreshProfile()
	local d = ClientState.Data
	if not d then
		return
	end
	local tier = Rank.FromElo(d.Elo)
	refs.Rank.Text = string.format("%s · %d ELO%s", tier.Name, d.Elo, if d.RankedPlayed < GameConfig.PlacementMatches then string.format(" (clasificación %d/%d)", d.RankedPlayed, GameConfig.PlacementMatches) else "")
	refs.Rank.TextColor3 = tier.Color
	refs.Coins.Text = if T.Halloween then string.format("● %d monedas    🍬 %d", d.Coins, d.Candies or 0) else string.format("● %d monedas", d.Coins)
	refs.Level.Text = string.format("NIVEL %d   ·   %d / %d XP", d.Level, d.XP, d.XPNext)
	refs.XPFill.Size = UDim2.fromScale(math.clamp(d.XP / math.max(d.XPNext, 1), 0, 1), 1)
end

-- Botonera -------------------------------------------------------------------

local function buildDock()
	local dock = new("Frame", { Name = "Dock", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = gui }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.QuickBtn = Make.Button("▶ PARTIDA RÁPIDA", T.Accent, { Size = UDim2.fromOffset(210, 56), TextSize = 20, LayoutOrder = 0, Parent = dock }, function()
		if ClientState.InQueue then
			Net.Event("LeaveQueue"):FireServer()
		else
			Net.Event("QueueCasual"):FireServer()
		end
	end)
	refs.QuickBtn.TextColor3 = T.Bg
	refs.RankedBtn = Make.Button("⚔ RANKED", T.Danger, { Size = UDim2.fromOffset(170, 56), TextSize = 20, LayoutOrder = 1, Parent = dock }, function()
		if ClientState.InQueue then
			Net.Event("LeaveQueue"):FireServer()
		else
			Net.Event("QueueRanked"):FireServer()
		end
	end)
	for i, info in {
		{ if T.Halloween then "🎃 VS BOT" else "VS BOT", "Bot" },
		{ "🛒 TIENDA", "Shop" },
		{ "ARSENAL", "Arsenal" },
		{ "🔄 TRADE", "Trade" },
		{ "RANKING", "Leaderboard" },
		{ "PERFIL", "Stats" },
	} do
		local color = if i == 1 then T.Purple elseif i == 2 then T.Gold else T.PanelLight
		local b = Make.Button(info[1], color, { Size = UDim2.fromOffset(124, 56), LayoutOrder = i + 1, Parent = dock }, function()
			if info[2] == "Shop" then
				MenuController.Close()
				ShopUI.Open()
				return
			elseif info[2] == "Trade" then
				MenuController.Close()
				TradeUI.OpenList()
				return
			end
			if openPanel == info[2] then
				MenuController.Close()
			else
				MenuController.Open(info[2])
			end
		end)
	end
	Make.Label("PARTIDA RÁPIDA te empareja con quien esté libre (o con un bot si no hay nadie) · pads del lobby: 1v1 / 2v2 · RANKED por ELO · VS BOT para practicar", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.fromOffset(900, 18),
		TextSize = 14,
		TextColor3 = T.SubText,
		TextStrokeTransparency = 0.7,
		Parent = gui,
	})
	refs.Dock = dock
	-- Encoger la barra si la pantalla es estrecha
	local dockScale = new("UIScale", { Parent = dock })
	local function fitDock()
		local vw = workspace.CurrentCamera.ViewportSize.X
		local natural = dock.AbsoluteSize.X / math.max(dockScale.Scale, 0.01)
		dockScale.Scale = math.clamp((vw - 32) / math.max(natural, 1), 0.45, 1)
	end
	dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(fitDock)
	end)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitDock)
	task.defer(fitDock)

	-- Recompensa diaria
	Make.Button("🎁", T.Gold, { Size = UDim2.fromOffset(56, 56), TextSize = 24, LayoutOrder = 0, Parent = dock }, function()
		MenuController.Close()
		DailyUI.Open()
	end)

	-- Botón de admin (solo admins; el rango lo pone el servidor)
	local adminBtn = Make.Button("🛡 ADMIN", Color3.fromRGB(40, 90, 170), { Size = UDim2.fromOffset(110, 56), LayoutOrder = 99, Visible = false, Parent = dock }, function()
		MenuController.Close()
		AdminUI.Toggle()
	end)
	local function updateAdmin()
		adminBtn.Visible = AdminUI.IsAdmin()
	end
	updateAdmin()
	player:GetAttributeChangedSignal("SD_Rank"):Connect(updateAdmin)
end

-- Arsenal --------------------------------------------------------------------

local function card(parent: Instance, height: number, order: number, stroke: Color3?): Frame
	return new("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = T.Panel, LayoutOrder = order, Parent = parent }, {
		Make.Corner(10),
		Make.Stroke(stroke or T.Stroke, 1.5),
	})
end

local function buildArsenal()
	local body = makePanel("Arsenal", "ARSENAL")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	renderers.Arsenal = function()
		for _, c in body:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local d = ClientState.Data
		if not d then
			return
		end
		Make.Label("ARMAS", { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 14, LayoutOrder = 0, Parent = body })
		for i, id in Weapons.Order do
			local w = Weapons.List[id]
			local equipped = d.Equipped.Weapon == id
			local locked = not Weapons.Owns(d, id)
			local inShop = Weapons.IsShopWeapon(w)
			local c = card(body, 84, i, if equipped then T.Accent else nil)
			Make.Label(w.DisplayName, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -180, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 20, Parent = c })
			Make.Label(w.Description, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -180, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Parent = c })
			Make.Label(
				string.format("Cabeza %d · Torso %d · Cadencia %.2fs · Cargador %d · Velocidad %d", w.Damage.Head, w.Damage.Torso, w.FireCooldown, w.MagSize, w.MuzzleVelocity),
				{ Position = UDim2.fromOffset(14, 56), Size = UDim2.new(1, -180, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Parent = c }
			)
			local label = if equipped then "EQUIPADA" elseif locked and inShop then "🛒 EN TIENDA" elseif locked then ("NIVEL " .. w.UnlockLevel) else "EQUIPAR"
			local btn = Make.Button(label, if equipped then T.Accent elseif locked and inShop then T.Gold elseif locked then T.PanelLight else T.Blue, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(140, 40), TextSize = 15, Parent = c })
			Make.Button("👁", T.PanelLight, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -162, 0.5, 0), Size = UDim2.fromOffset(44, 40), TextSize = 18, Parent = c }, function()
				MenuController.Close()
				InspectUI.Open("Rifle", id, d.Equipped.Skin)
			end)
			btn.Active = not equipped
			btn.MouseButton1Click:Connect(function()
				if not locked and not equipped then
					Net.Function("EquipWeapon"):InvokeServer(id)
				elseif locked and inShop then
					MenuController.Close()
					ShopUI.Open("Weapons")
				end
			end)
		end

		Make.Label("SKINS", { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 14, LayoutOrder = 100, Parent = body })
		local grid = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 101, Parent = body }, {
			new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 110), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local order = { "Común", "Raro", "Épico", "Legendario", "Mítico" }
		for _, s in Skins.List do
			local owned = d.Inventory.Skins[s.Id] == true
			local rarity = Skins.RarityInfo(s.Rarity)
			local equipped = d.Equipped.Skin == s.Id
			local cell = new("TextButton", {
				Text = "",
				AutoButtonColor = owned,
				BackgroundColor3 = T.Panel,
				LayoutOrder = (table.find(order, s.Rarity) or 1) * 100 + #s.Id,
				Parent = grid,
			}, { Make.Corner(10), Make.Stroke(if equipped then T.Accent else rarity.Color, if equipped then 3 else 1.5) })
			new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 46), BackgroundColor3 = s.Color, Parent = cell }, {
				Make.Corner(8),
				new("UIGradient", { Color = ColorSequence.new(s.Color, s.Accent), Rotation = 30 }),
			})
			Make.Label(s.DisplayName, { Position = UDim2.fromOffset(10, 60), Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, TextColor3 = if owned then T.Text else T.SubText, Parent = cell })
			Make.Label(if owned then s.Rarity else "🔒 " .. s.Rarity, { Position = UDim2.fromOffset(10, 82), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = rarity.Color, Parent = cell })
			Make.Button("👁", T.PanelLight, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), Size = UDim2.fromOffset(30, 26), TextSize = 14, ZIndex = 3, Parent = cell }, function()
				MenuController.Close()
				InspectUI.Open("Rifle", d.Equipped.Weapon, s.Id)
			end)
			cell.MouseButton1Click:Connect(function()
				if owned and not equipped then
					Net.Function("EquipSkin"):InvokeServer(s.Id)
				end
			end)
		end
	end
end

-- Modo solo (VS BOT) -------------------------------------------------------

local function buildBotPanel()
	local body = makePanel("Bot", if T.Halloween then "DUELO CONTRA LA CALABAZA" else "DUELO CONTRA BOT")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	Make.Label("Practica tú solo. El bot usa las mismas armas, balística y reglas que un jugador.", { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 14, TextWrapped = true, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 0, Parent = body })
	local options = {
		{ "Practica", "PRÁCTICA", "No dispara. Solo se mueve: ideal para probar armas y la caída de la bala.", T.Blue },
		{ "Facil", "FÁCIL", "Reacciona lento y falla bastante.", Color3.fromRGB(90, 200, 110) },
		{ "Normal", "NORMAL", "Un rival decente. Te ve, apunta y dispara con cabeza.", T.Gold },
		{ "Dificil", "DIFÍCIL", "Rápido y preciso. Adelanta tus movimientos. Usa Viper.", T.Accent },
		{ "Pesadilla", "PESADILLA", "Reflejos de élite. Busca la cabeza. Solo para valientes.", T.Danger },
	}
	for i, o in options do
		local row = card(body, 74, i, o[4])
		Make.Label(o[2], { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -200, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 26, TextColor3 = o[4], Parent = row })
		Make.Label(o[3], { Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -200, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Make.Button("JUGAR", o[4], { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(140, 44), TextColor3 = T.Bg, Parent = row }, function()
			Net.Event("PlayBot"):FireServer(o[1])
			MenuController.Close()
		end)
	end
end

-- Ranking --------------------------------------------------------------------

local function buildLeaderboard()
	local body = makePanel("Leaderboard", "RANKING GLOBAL")
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	renderers.Leaderboard = function()
		clear(body)
		Make.Label("Cargando...", { TextColor3 = T.SubText, Parent = body })
		task.spawn(function()
			local list = Net.Function("GetLeaderboard"):InvokeServer() or {}
			clear(body)
			if #list == 0 then
				Make.Label("Aún no hay jugadores clasificados.", { TextColor3 = T.SubText, Parent = body })
			end
			for i, e in list do
				local tier = Rank.FromElo(e.Elo)
				local row = card(body, 38, i, if e.UserId == player.UserId then T.Accent else nil)
				local medal = if i == 1 then T.Gold elseif i == 2 then Color3.fromRGB(200, 205, 215) elseif i == 3 then Color3.fromRGB(205, 127, 50) else T.SubText
				Make.Label("#" .. i, { Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(50, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextColor3 = medal, Parent = row })
				Make.Label(e.Name, { Position = UDim2.fromOffset(64, 8), Size = UDim2.new(1, -260, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
				Make.Label(string.format("%s · %d", tier.Name, e.Elo), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(180, 22), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = tier.Color, Parent = row })
			end
		end)
	end
end

-- Perfil / ajustes -----------------------------------------------------------

local function buildStats()
	local body = makePanel("Stats", "PERFIL Y AJUSTES")
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	renderers.Stats = function()
		clear(body)
		local d = ClientState.Data
		if not d then
			return
		end
		local kd = if d.Deaths > 0 then d.Kills / d.Deaths else d.Kills
		local hsr = if d.Kills > 0 then d.Headshots / d.Kills * 100 else 0
		local rows = {
			{ "Victorias / Derrotas", string.format("%d / %d", d.Wins, d.Losses) },
			{ "Bajas / Muertes (K/D)", string.format("%d / %d  (%.2f)", d.Kills, d.Deaths, kd) },
			{ "Headshots", string.format("%d  (%.0f%%)", d.Headshots, hsr) },
			{ "Precisión", string.format("%.1f%%", d.Accuracy * 100) },
			{ "Tiro más largo", string.format("%d studs", d.LongestShot) },
			{ "Racha actual / mejor", string.format("%d / %d", d.WinStreak, d.BestStreak) },
			{ "Partidas ranked", tostring(d.RankedPlayed) },
		}
		for i, r in rows do
			local row = card(body, 36, i)
			Make.Label(r[1], { Position = UDim2.fromOffset(12, 7), Size = UDim2.new(0.6, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, Parent = row })
			Make.Label(r[2], { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7), Size = UDim2.new(0.4, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
		end

		Make.Label("AJUSTES", { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 14, LayoutOrder = 50, Parent = body })
		local function stepper(label: string, key: string, step: number, min: number, max: number, order: number)
			local row = card(body, 44, order)
			Make.Label(label, { Position = UDim2.fromOffset(12, 11), Size = UDim2.new(0.5, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
			local value = Make.Label(string.format("%.2f", d.Settings[key]), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 11), Size = UDim2.fromOffset(70, 22), Parent = row })
			local function change(delta: number)
				d.Settings[key] = math.clamp(math.round((d.Settings[key] + delta) * 100) / 100, min, max)
				value.Text = string.format("%.2f", d.Settings[key])
				Net.Function("UpdateSettings"):InvokeServer({ [key] = d.Settings[key] })
			end
			Make.Button("−", T.PanelLight, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -134, 0.5, 0), Size = UDim2.fromOffset(34, 32), Parent = row }, function()
				change(-step)
			end)
			Make.Button("+", T.PanelLight, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(34, 32), Parent = row }, function()
				change(step)
			end)
		end
		stepper("Sensibilidad", "Sensitivity", 0.05, 0.1, 4, 51)
		stepper("Sensibilidad con mira", "ScopeSensitivity", 0.05, 0.05, 2, 52)

		local row = card(body, 44, 53)
		Make.Label("Mira: pulsar para alternar", { Position = UDim2.fromOffset(12, 11), Size = UDim2.new(0.6, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local toggle: TextButton
		toggle = Make.Button(if d.Settings.ToggleScope then "SÍ" else "NO", if d.Settings.ToggleScope then T.Accent else T.PanelLight, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(80, 32), Parent = row }, function()
			d.Settings.ToggleScope = not d.Settings.ToggleScope
			toggle.Text = if d.Settings.ToggleScope then "SÍ" else "NO"
			toggle.BackgroundColor3 = if d.Settings.ToggleScope then T.Accent else T.PanelLight
			Net.Function("UpdateSettings"):InvokeServer({ ToggleScope = d.Settings.ToggleScope })
		end)
	end
end

local function refreshQueue(inQueue: boolean, seconds: number, mode: string?)
	ClientState.InQueue = inQueue
	local searching = string.format("BUSCANDO… %d:%02d  ✕", seconds // 60, seconds % 60)
	refs.RankedBtn.Text = if inQueue and mode == "Ranked" then searching else "⚔ RANKED"
	refs.RankedBtn.BackgroundColor3 = if inQueue and mode == "Ranked" then T.PanelLight else T.Danger
	refs.QuickBtn.Text = if inQueue and mode ~= "Ranked" then searching else "▶ PARTIDA RÁPIDA"
	refs.QuickBtn.BackgroundColor3 = if inQueue and mode ~= "Ranked" then T.PanelLight else T.Accent
	refs.QuickBtn.TextColor3 = if inQueue and mode ~= "Ranked" then T.Text else T.Bg
end

local function setVisible(visible: boolean)
	refs.Profile.Visible = visible
	refs.Dock.Visible = visible
	for _, c in gui:GetChildren() do
		if c:IsA("TextLabel") then
			c.Visible = visible
		end
	end
	if not visible then
		MenuController.Close()
		ShopUI.Close()
		TradeUI.CloseAll()
		AdminUI.Close()
		DailyUI.Close()
		InspectUI.Close()
	end
end

function MenuController.Start()
	gui = new("ScreenGui", { Name = "Menu", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10, Parent = player:WaitForChild("PlayerGui") })
	buildProfileCard()
	buildDock()
	buildBotPanel()
	buildArsenal()
	ShopUI.Build(gui)
	TradeUI.Build(gui, HUDController.Toast)
	AdminUI.Build(gui)
	PauseMenu.Build(gui)
	DailyUI.Build(gui, HUDController.Toast)
	DebugOverlay.Build(gui)
	InspectUI.Build(gui)
	buildLeaderboard()
	buildStats()

	Net.Event("DataUpdate").OnClientEvent:Connect(function(data)
		ClientState.Data = data
		ClientState.DataChanged:Fire(data)
		refreshProfile()
		if openPanel == "Arsenal" or openPanel == "Stats" then
			renderers[openPanel]()
		end
	end)
	Net.Event("QueueState").OnClientEvent:Connect(refreshQueue)
	Net.Event("OpenBotMenu").OnClientEvent:Connect(function()
		if not ClientState.Duel and openPanel ~= "Bot" then
			MenuController.Open("Bot")
		end
	end)
	ClientState.DuelChanged:Connect(function(state)
		setVisible(state.State == "Ended")
	end)
	-- Seguridad: en el lobby (sin arma) el ratón nunca debe quedarse clavado
	-- en el centro; si pasa, los botones del menú no se pueden pulsar
	local UserInputService = game:GetService("UserInputService")
	game:GetService("RunService").RenderStepped:Connect(function()
		if ClientState.Armed or not refs.Dock.Visible then
			return
		end
		pcall(function()
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
				if player.CameraMode == Enum.CameraMode.LockFirstPerson then
					player.CameraMode = Enum.CameraMode.Classic
				end
			end
		end)
	end)

	task.spawn(function()
		local data = Net.Function("GetData"):InvokeServer()
		if data then
			ClientState.Data = data
			ClientState.DataChanged:Fire(data)
			refreshProfile()
		end
	end)
end

return MenuController
