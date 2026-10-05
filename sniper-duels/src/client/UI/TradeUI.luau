--!strict
-- Interfaz de intercambio y regalos:
--  * lista de jugadores del servidor con "Intercambiar" y "Regalar"
--  * aviso de solicitud entrante (aceptar / rechazar)
--  * ventana de intercambio: tu inventario, tu oferta, su oferta, LISTO,
--    cuenta atrás de confirmación (el servidor valida todo)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Make)

local T = Make.Theme
local new = Make.new
local player = Players.LocalPlayer

local TradeUI = {}

type Item = { Kind: string, Id: string }

local gui: ScreenGui
local listPanel: Frame
local playerList: ScrollingFrame
local giftPanel: Frame
local giftGrid: ScrollingFrame
local giftTarget: Player? = nil
local incoming: Frame
local incomingFrom: Player? = nil
local window: Frame
local refs: { [string]: any } = {}
local myOffer: { Item } = {}
local state: any = nil

local function key(item: Item): string
	return item.Kind .. ":" .. item.Id
end

local function myTradeables(): { Item }
	local d = ClientState.Data
	local items: { Item } = {}
	if not d then
		return items
	end
	for id in d.Inventory.Skins do
		if id ~= "Default" and Skins.List[id] then
			table.insert(items, { Kind = "Skin", Id = id })
		end
	end
	for id in d.Inventory.Weapons or {} do
		local w = Weapons.List[id]
		if w and w.Tradeable then
			table.insert(items, { Kind = "Weapon", Id = id })
		end
	end
	table.sort(items, function(a, b)
		return key(a) < key(b)
	end)
	return items
end

-- Tarjeta visual de un objeto
local function itemCard(item: Item, parent: Instance, onClick: (() -> ())?, selected: boolean?): TextButton
	local isSkin = item.Kind == "Skin"
	local skin = if isSkin then Skins.Get(item.Id) else nil
	local w = if not isSkin then Weapons.Get(item.Id) else nil
	local rarityColor = if skin then Skins.RarityInfo(skin.Rarity).Color else T.Gold
	local card = new("TextButton", {
		Text = "",
		AutoButtonColor = onClick ~= nil,
		BackgroundColor3 = T.Panel,
		Parent = parent,
	}, {
		Make.Corner(10),
		new("UIStroke", { Color = if selected then T.Accent else rarityColor, Thickness = if selected then 3 else 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local swatch = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0.5, -4), BackgroundColor3 = if skin then skin.Color else Color3.fromRGB(40, 30, 50), Parent = card }, { Make.Corner(8) })
	if skin then
		new("UIGradient", { Color = ColorSequence.new(skin.Color, skin.Accent), Rotation = 30, Parent = swatch })
	else
		Make.Label("🔫", { Size = UDim2.fromScale(1, 1), TextScaled = true, Parent = swatch })
	end
	Make.Label(if skin then skin.DisplayName else (w :: any).DisplayName, { Position = UDim2.new(0, 6, 0.5, 8), Size = UDim2.new(1, -12, 0, 18), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
	Make.Label(if skin then skin.Rarity else "Arma", { Position = UDim2.new(0, 6, 0.5, 26), Size = UDim2.new(1, -12, 0, 14), TextSize = 11, TextColor3 = rarityColor, Parent = card })
	if onClick then
		card.MouseButton1Click:Connect(onClick)
	end
	return card
end

local function grid(parent: Instance, pos: UDim2, size: UDim2): ScrollingFrame
	local sf = new("ScrollingFrame", {
		Position = pos,
		Size = size,
		BackgroundColor3 = T.Bg,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	}, {
		Make.Corner(12),
		Make.Padding(8),
		new("UIGridLayout", { CellSize = UDim2.fromOffset(108, 116), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.Name }),
	})
	return sf
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function panelFrame(name: string, title: string, size: UDim2): Frame
	local f = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = T.Bg,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	}, {
		Make.Corner(18),
		new("UIStroke", { Color = T.Purple, Thickness = 2, Transparency = 0.3 }),
	})
	local t = Make.Label(title, { Position = UDim2.fromOffset(22, 14), Size = UDim2.new(1, -90, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 36, Parent = f })
	new("UIGradient", { Color = ColorSequence.new(T.Accent, T.Purple), Parent = t })
	return f
end

-- Lista de jugadores ----------------------------------------------------------

local function refreshPlayers()
	clear(playerList)
	local others = 0
	for _, p in Players:GetPlayers() do
		if p ~= player then
			others += 1
			local row = new("Frame", { Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = T.Panel, Parent = playerList }, { Make.Corner(10) })
			local thumb = new("ImageLabel", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = T.PanelLight, Parent = row }, { Make.Corner(20) })
			task.spawn(function()
				local ok, img = pcall(Players.GetUserThumbnailAsync, Players, p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
				if ok then
					thumb.Image = img
				end
			end)
			Make.Label(p.DisplayName, { Position = UDim2.fromOffset(58, 8), Size = UDim2.new(1, -330, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
			Make.Label(string.format("Nivel %s · ELO %s%s", tostring(p:GetAttribute("Level") or "?"), tostring(p:GetAttribute("Elo") or "?"), if p:GetAttribute("VIP") then " · ★VIP" else ""), { Position = UDim2.fromOffset(58, 30), Size = UDim2.new(1, -330, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = T.SubText, Parent = row })
			Make.Button("🔄 INTERCAMBIAR", T.Purple, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -128, 0.5, 0), Size = UDim2.fromOffset(150, 38), TextSize = 13, Parent = row }, function()
				Net.Event("Trade"):FireServer("Request", p)
			end)
			Make.Button("🎁 REGALAR", T.Gold, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 38), TextSize = 13, TextColor3 = T.Bg, Parent = row }, function()
				TradeUI.OpenGift(p)
			end)
		end
	end
	if others == 0 then
		Make.Label("No hay más jugadores en este servidor. ¡Invita a un amigo!", { Size = UDim2.new(1, 0, 0, 40), TextColor3 = T.SubText, Parent = playerList })
	end
end

function TradeUI.OpenList()
	listPanel.Visible = true
	refreshPlayers()
end

-- Regalos --------------------------------------------------------------------

function TradeUI.OpenGift(target: Player)
	giftTarget = target
	listPanel.Visible = false
	giftPanel.Visible = true
	refs.GiftTitle.Text = "Elige qué regalar a " .. target.DisplayName
	clear(giftGrid)
	local items = myTradeables()
	if #items == 0 then
		Make.Label("No tienes objetos que se puedan regalar.", { Size = UDim2.fromOffset(400, 30), TextColor3 = T.SubText, Parent = giftGrid })
	end
	for _, item in items do
		itemCard(item, giftGrid, function()
			refs.GiftStatus.Text = "Enviando..."
			local res = Net.Function("Gift"):InvokeServer(giftTarget, item)
			refs.GiftStatus.Text = if res then res.Message else "Error"
			refs.GiftStatus.TextColor3 = if res and res.Ok then T.Accent else T.Danger
			if res and res.Ok then
				task.delay(0.8, function()
					if giftTarget then
						TradeUI.OpenGift(giftTarget)
					end
				end)
			end
		end)
	end
end

-- Ventana de intercambio -----------------------------------------------------

local function renderWindow()
	if not state then
		return
	end
	refs.Partner.Text = "Intercambio con " .. state.PartnerName
	-- Mi inventario (click para añadir/quitar)
	clear(refs.Inventory)
	local inOffer: { [string]: boolean } = {}
	for _, it in myOffer do
		inOffer[key(it)] = true
	end
	for _, item in myTradeables() do
		local k = key(item)
		itemCard(item, refs.Inventory, function()
			if inOffer[k] then
				for i, it in myOffer do
					if key(it) == k then
						table.remove(myOffer, i)
						break
					end
				end
			else
				table.insert(myOffer, item)
			end
			Net.Event("Trade"):FireServer("SetOffer", myOffer)
		end, inOffer[k])
	end
	clear(refs.Mine)
	for _, item in state.MyOffer do
		itemCard(item, refs.Mine)
	end
	clear(refs.Theirs)
	for _, item in state.TheirOffer do
		itemCard(item, refs.Theirs)
	end
	refs.MyReady.Text = if state.MyReady then "✓ LISTO" else "esperando..."
	refs.MyReady.TextColor3 = if state.MyReady then T.Accent else T.SubText
	refs.TheirReady.Text = if state.TheirReady then "✓ LISTO" else "esperando..."
	refs.TheirReady.TextColor3 = if state.TheirReady then T.Accent else T.SubText
	refs.ReadyBtn.Text = if state.MyReady then "QUITAR LISTO" else "✓ LISTO"
	refs.ReadyBtn.BackgroundColor3 = if state.MyReady then T.PanelLight else T.Accent
end

local function buildWindow()
	window = panelFrame("TradeWindow", "INTERCAMBIO", UDim2.fromOffset(980, 560))
	refs.Partner = Make.Label("", { Position = UDim2.fromOffset(24, 56), Size = UDim2.fromOffset(600, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, Parent = window })

	Make.Label("TU INVENTARIO (pulsa para ofrecer)", { Position = UDim2.fromOffset(24, 86), Size = UDim2.fromOffset(360, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = T.SubText, Parent = window })
	refs.Inventory = grid(window, UDim2.fromOffset(24, 108), UDim2.fromOffset(360, 360))

	Make.Label("TU OFERTA", { Position = UDim2.fromOffset(400, 86), Size = UDim2.fromOffset(270, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = T.Accent, Parent = window })
	refs.MyReady = Make.Label("", { Position = UDim2.fromOffset(560, 86), Size = UDim2.fromOffset(110, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, Parent = window })
	refs.Mine = grid(window, UDim2.fromOffset(400, 108), UDim2.fromOffset(270, 360))

	Make.Label("SU OFERTA", { Position = UDim2.fromOffset(686, 86), Size = UDim2.fromOffset(270, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = T.Purple, Parent = window })
	refs.TheirReady = Make.Label("", { Position = UDim2.fromOffset(846, 86), Size = UDim2.fromOffset(110, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, Parent = window })
	refs.Theirs = grid(window, UDim2.fromOffset(686, 108), UDim2.fromOffset(270, 360))

	refs.Countdown = Make.Label("", { Position = UDim2.fromOffset(24, 482), Size = UDim2.fromOffset(500, 56), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontTitle, TextSize = 30, TextColor3 = T.Gold, Parent = window })
	refs.ReadyBtn = Make.Button("✓ LISTO", T.Accent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -190, 0, 486), Size = UDim2.fromOffset(170, 50), TextColor3 = T.Bg, Parent = window }, function()
		if state then
			Net.Event("Trade"):FireServer("Ready", not state.MyReady)
		end
	end)
	Make.Button("CANCELAR", T.Danger, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 486), Size = UDim2.fromOffset(150, 50), Parent = window }, function()
		Net.Event("Trade"):FireServer("Cancel")
	end)
end

local function buildIncoming()
	incoming = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -120),
		Size = UDim2.fromOffset(440, 104),
		BackgroundColor3 = T.Panel,
		ZIndex = 60,
		Parent = gui,
	}, { Make.Corner(14), new("UIStroke", { Color = T.Purple, Thickness = 2 }) })
	refs.IncomingText = Make.Label("", { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 24), Font = T.FontBlack, ZIndex = 61, Parent = incoming })
	Make.Button("ACEPTAR", T.Accent, { Position = UDim2.new(0, 16, 1, -54), Size = UDim2.new(0.5, -24, 0, 42), TextColor3 = T.Bg, ZIndex = 61, Parent = incoming }, function()
		if incomingFrom then
			Net.Event("Trade"):FireServer("Respond", incomingFrom)
		end
		TweenService:Create(incoming, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) }):Play()
	end)
	Make.Button("RECHAZAR", T.Danger, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -54), Size = UDim2.new(0.5, -24, 0, 42), ZIndex = 61, Parent = incoming }, function()
		if incomingFrom then
			Net.Event("Trade"):FireServer("Decline", incomingFrom)
		end
		TweenService:Create(incoming, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) }):Play()
	end)
end

function TradeUI.Build(screen: ScreenGui, notify: (string, Color3?) -> ())
	gui = screen
	listPanel = panelFrame("TradeList", "INTERCAMBIOS", UDim2.fromOffset(640, 480))
	Make.Label("Intercambia skins y armas de tienda, o regálalas. Las armas por nivel no se intercambian.", { Position = UDim2.fromOffset(24, 58), Size = UDim2.new(1, -48, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = T.SubText, Parent = listPanel })
	playerList = new("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 86),
		Size = UDim2.new(1, -40, 1, -106),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = listPanel,
	}, { new("UIListLayout", { Padding = UDim.new(0, 8) }) })
	Make.Button("✕", T.PanelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(38, 38), Parent = listPanel }, function()
		listPanel.Visible = false
	end)

	giftPanel = panelFrame("Gift", "REGALAR", UDim2.fromOffset(640, 480))
	refs.GiftTitle = Make.Label("", { Position = UDim2.fromOffset(24, 58), Size = UDim2.new(1, -48, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.SubText, Parent = giftPanel })
	refs.GiftStatus = Make.Label("", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -14), Size = UDim2.new(1, -48, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = giftPanel })
	giftGrid = grid(giftPanel, UDim2.fromOffset(20, 86), UDim2.new(1, -40, 1, -130))
	Make.Button("✕", T.PanelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(38, 38), Parent = giftPanel }, function()
		giftPanel.Visible = false
		giftTarget = nil
		refs.GiftStatus.Text = ""
	end)

	buildWindow()
	buildIncoming()

	Net.Event("TradeUpdate").OnClientEvent:Connect(function(msg)
		if msg.Type == "Incoming" then
			incomingFrom = msg.From
			refs.IncomingText.Text = "🔄 " .. msg.FromName .. " quiere intercambiar"
			TweenService:Create(incoming, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 20) }):Play()
			task.delay(20, function()
				if incomingFrom == msg.From then
					TweenService:Create(incoming, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) }):Play()
				end
			end)
		elseif msg.Type == "State" then
			local first = state == nil
			state = msg
			if first then
				myOffer = {}
			end
			-- Sincronizar con lo que el servidor aceptó realmente
			myOffer = table.clone(msg.MyOffer)
			listPanel.Visible = false
			giftPanel.Visible = false
			window.Visible = true
			renderWindow()
		elseif msg.Type == "Closed" then
			state = nil
			myOffer = {}
			window.Visible = false
			if msg.Reason ~= "OK" then
				notify(msg.Reason, T.Danger)
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		if state and state.ConfirmAt then
			local left = math.max(0, state.ConfirmAt - workspace:GetServerTimeNow())
			refs.Countdown.Text = string.format("Intercambiando en %.1f s...", left)
		elseif refs.Countdown then
			refs.Countdown.Text = if state then "Revisad bien las ofertas y pulsad LISTO" else ""
		end
	end)
	ClientState.DataChanged:Connect(function()
		if state then
			renderWindow()
		end
	end)
end

function TradeUI.CloseAll()
	listPanel.Visible = false
	giftPanel.Visible = false
end

return TradeUI
