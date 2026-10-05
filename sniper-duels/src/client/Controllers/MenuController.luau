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
	Make.Label(title, { Position = UDim2.fromOffset(24, 16), Size = UDim2.new(1, -80, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 28, Parent = panel })
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
	local card = new("Frame", { Name = "Profile", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(300, 116), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.08, Parent = gui }, {
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
	refs.Coins.Text = string.format("● %d monedas", d.Coins)
	refs.Level.Text = string.format("NIVEL %d   ·   %d / %d XP", d.Level, d.XP, d.XPNext)
	refs.XPFill.Size = UDim2.fromScale(math.clamp(d.XP / math.max(d.XPNext, 1), 0, 1), 1)
end

-- Botonera -------------------------------------------------------------------

local function buildDock()
	local dock = new("Frame", { Name = "Dock", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = gui }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.RankedBtn = Make.Button("⚔ RANKED", T.Danger, { Size = UDim2.fromOffset(170, 56), TextSize = 20, LayoutOrder = 1, Parent = dock }, function()
		if ClientState.InQueue then
			Net.Event("LeaveQueue"):FireServer()
		else
			Net.Event("QueueRanked"):FireServer()
		end
	end)
	for i, info in { { "ARSENAL", "Arsenal" }, { "TIENDA", "Shop" }, { "RANKING", "Leaderboard" }, { "PERFIL", "Stats" } } do
		Make.Button(info[1], T.PanelLight, { Size = UDim2.fromOffset(130, 56), LayoutOrder = i + 1, Parent = dock }, function()
			if openPanel == info[2] then
				MenuController.Close()
			else
				MenuController.Open(info[2])
			end
		end)
	end
	Make.Label("Súbete a un par de pads para un duelo casual · RANKED busca rival por ELO", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.fromOffset(700, 18),
		TextSize = 14,
		TextColor3 = T.SubText,
		TextStrokeTransparency = 0.7,
		Parent = gui,
	})
	refs.Dock = dock
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
			local locked = d.Level < w.UnlockLevel
			local c = card(body, 84, i, if equipped then T.Accent else nil)
			Make.Label(w.DisplayName, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -180, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 20, Parent = c })
			Make.Label(w.Description, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -180, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Parent = c })
			Make.Label(
				string.format("Cabeza %d · Torso %d · Cadencia %.2fs · Cargador %d · Velocidad %d", w.Damage.Head, w.Damage.Torso, w.FireCooldown, w.MagSize, w.MuzzleVelocity),
				{ Position = UDim2.fromOffset(14, 56), Size = UDim2.new(1, -180, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Parent = c }
			)
			local label = if equipped then "EQUIPADA" elseif locked then ("NIVEL " .. w.UnlockLevel) else "EQUIPAR"
			local btn = Make.Button(label, if equipped then T.Accent elseif locked then T.PanelLight else T.Blue, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(140, 40), TextSize = 15, Parent = c })
			btn.Active = not locked and not equipped
			btn.MouseButton1Click:Connect(function()
				if not locked and not equipped then
					Net.Function("EquipWeapon"):InvokeServer(id)
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
			cell.MouseButton1Click:Connect(function()
				if owned and not equipped then
					Net.Function("EquipSkin"):InvokeServer(s.Id)
				end
			end)
		end
	end
end

-- Tienda ---------------------------------------------------------------------

local function buildShop()
	local body = makePanel("Shop", "TIENDA")
	local rolling = false

	local reel = new("Frame", { Size = UDim2.new(1, 0, 0, 140), BackgroundColor3 = T.Panel, ClipsDescendants = true, Parent = body }, { Make.Corner(12), Make.Stroke(T.Stroke, 1.5) })
	local strip = new("Frame", { Size = UDim2.fromOffset(0, 120), Position = UDim2.fromOffset(0, 10), BackgroundTransparency = 1, Parent = reel })
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = T.Gold, BorderSizePixel = 0, ZIndex = 5, Parent = reel })

	local result = Make.Label("Caja de skins · " .. GameConfig.CratePrice .. " monedas", { Position = UDim2.fromOffset(0, 154), Size = UDim2.new(1, 0, 0, 30), TextSize = 20, Parent = body })
	local odds = {}
	for _, r in Skins.Rarities do
		table.insert(odds, string.format("%s %.1f%%", r.Name, r.Weight))
	end
	Make.Label(table.concat(odds, "  ·  "), { Position = UDim2.fromOffset(0, 186), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = T.SubText, Parent = body })
	Make.Label(string.format("Los duplicados devuelven el %d%% del precio.", GameConfig.DuplicateRefund * 100), { Position = UDim2.fromOffset(0, 206), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = T.SubText, Parent = body })

	local CELL = 130
	local function cellFor(s: Skins.Skin, x: number)
		local rarity = Skins.RarityInfo(s.Rarity)
		local f = new("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(CELL - 10, 120), BackgroundColor3 = T.PanelLight, Parent = strip }, { Make.Corner(10), Make.Stroke(rarity.Color, 2) })
		new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 60), BackgroundColor3 = s.Color, Parent = f }, { Make.Corner(8), new("UIGradient", { Color = ColorSequence.new(s.Color, s.Accent), Rotation = 30 }) })
		Make.Label(s.DisplayName, { Position = UDim2.fromOffset(8, 74), Size = UDim2.new(1, -16, 0, 18), TextSize = 14, Parent = f })
		Make.Label(s.Rarity, { Position = UDim2.fromOffset(8, 94), Size = UDim2.new(1, -16, 0, 16), TextSize = 12, TextColor3 = rarity.Color, Parent = f })
	end

	Make.Button("ABRIR CAJA", T.Gold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 236), Size = UDim2.fromOffset(220, 52), TextColor3 = T.Bg, TextSize = 20, Parent = body }, function()
		if rolling then
			return
		end
		rolling = true
		local res = Net.Function("BuyCrate"):InvokeServer()
		if not res or not res.Ok then
			result.Text = res and res.Error or "Error"
			result.TextColor3 = T.Danger
			rolling = false
			return
		end
		clear(strip)
		strip.Position = UDim2.fromOffset(0, 10)
		local rng = Random.new()
		local winIndex = 40
		for i = 1, winIndex + 5 do
			local s = if i == winIndex then Skins.Get(res.SkinId) else Skins.Roll(rng)
			cellFor(s, (i - 1) * CELL)
		end
		local center = reel.AbsoluteSize.X / 2
		local target = -((winIndex - 1) * CELL + (CELL - 10) / 2 - center) + rng:NextNumber(-40, 40)
		result.Text = "..."
		result.TextColor3 = T.Text
		local tw = TweenService:Create(strip, TweenInfo.new(4.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(target, 10) })
		tw:Play()
		tw.Completed:Wait()
		local s = Skins.Get(res.SkinId)
		local rarity = Skins.RarityInfo(s.Rarity)
		result.Text = if res.Duplicate then string.format("%s (duplicado) · +%d monedas", s.DisplayName, res.Refund) else string.format("¡%s %s!", s.Rarity, s.DisplayName)
		result.TextColor3 = rarity.Color
		rolling = false
	end)
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

local function refreshQueue(inQueue: boolean, seconds: number)
	ClientState.InQueue = inQueue
	refs.RankedBtn.Text = if inQueue then string.format("BUSCANDO… %d:%02d", seconds // 60, seconds % 60) else "⚔ RANKED"
	refs.RankedBtn.BackgroundColor3 = if inQueue then T.PanelLight else T.Danger
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
	end
end

function MenuController.Start()
	gui = new("ScreenGui", { Name = "Menu", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10, Parent = player:WaitForChild("PlayerGui") })
	buildProfileCard()
	buildDock()
	buildArsenal()
	buildShop()
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
	ClientState.DuelChanged:Connect(function(state)
		setVisible(state.State == "Ended")
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
