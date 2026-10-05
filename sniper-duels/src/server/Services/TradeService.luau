--!strict
-- Intercambio y regalos de objetos entre jugadores del mismo servidor.
-- Objetos intercambiables: skins (excepto la estándar) y armas de tienda
-- con Tradeable = true. Las armas por nivel no se intercambian.
--
-- Anti-estafa:
--  * cambiar la oferta quita el "Listo" de ambos
--  * cuenta atrás de confirmación tras aceptar los dos
--  * todo se re-valida en el servidor justo antes del intercambio
--  * no se puede ofrecer algo que el otro ya tiene
--  * se guarda inmediatamente a los dos jugadores

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local DuelService = require(script.Parent.DuelService)

type Item = { Kind: string, Id: string }
type Trade = {
	A: Player,
	B: Player,
	Offers: { [Player]: { Item } },
	Ready: { [Player]: boolean },
	Token: number,
	ConfirmAt: number?,
	Closed: boolean,
}

local TradeService = {}

local trades: { [Player]: Trade } = {}
local requests: { [Player]: { [Player]: number } } = {} -- requests[target][from] = time
local lastGift: { [Player]: number } = {}

local function owns(d: any, item: Item): boolean
	if item.Kind == "Skin" then
		return d.Inventory.Skins[item.Id] == true
	elseif item.Kind == "Weapon" then
		return d.Inventory.Weapons[item.Id] == true
	end
	return false
end

local function tradeable(item: any): boolean
	if type(item) ~= "table" or type(item.Kind) ~= "string" or type(item.Id) ~= "string" then
		return false
	end
	if item.Kind == "Skin" then
		return Skins.List[item.Id] ~= nil and item.Id ~= "Default"
	elseif item.Kind == "Weapon" then
		local w = Weapons.List[item.Id]
		return w ~= nil and w.Tradeable == true
	end
	return false
end

local function transfer(from: any, to: any, item: Item)
	if item.Kind == "Skin" then
		from.Inventory.Skins[item.Id] = nil
		to.Inventory.Skins[item.Id] = true
		if from.Equipped.Skin == item.Id then
			from.Equipped.Skin = "Default"
		end
	else
		from.Inventory.Weapons[item.Id] = nil
		to.Inventory.Weapons[item.Id] = true
		if from.Equipped.Weapon == item.Id then
			from.Equipped.Weapon = Weapons.Default
		end
	end
end

local function itemName(item: Item): string
	if item.Kind == "Skin" then
		return "Skin " .. Skins.Get(item.Id).DisplayName
	end
	return Weapons.Get(item.Id).DisplayName
end

local function other(t: Trade, p: Player): Player
	return if t.A == p then t.B else t.A
end

local function push(t: Trade)
	for _, p in { t.A, t.B } do
		if p.Parent then
			local o = other(t, p)
			Net.Event("TradeUpdate"):FireClient(p, {
				Type = "State",
				PartnerName = o.DisplayName,
				PartnerId = o.UserId,
				MyOffer = t.Offers[p],
				TheirOffer = t.Offers[o],
				MyReady = t.Ready[p] == true,
				TheirReady = t.Ready[o] == true,
				ConfirmAt = t.ConfirmAt,
			})
		end
	end
end

local function close(t: Trade, reason: string)
	if t.Closed then
		return
	end
	t.Closed = true
	for _, p in { t.A, t.B } do
		if trades[p] == t then
			trades[p] = nil
		end
		if p.Parent then
			Net.Event("TradeUpdate"):FireClient(p, { Type = "Closed", Reason = reason })
		end
	end
end

local function validOffer(t: Trade, p: Player): boolean
	local d, od = DataService.Get(p), DataService.Get(other(t, p))
	if not d or not od then
		return false
	end
	for _, item in t.Offers[p] do
		if not tradeable(item) or not owns(d, item) or owns(od, item) then
			return false
		end
	end
	return true
end

local function execute(t: Trade)
	if t.Closed then
		return
	end
	if DuelService.IsBusy(t.A) or DuelService.IsBusy(t.B) then
		close(t, "Uno de los jugadores ha entrado en un duelo")
		return
	end
	if not validOffer(t, t.A) or not validOffer(t, t.B) then
		close(t, "La oferta ya no es válida")
		return
	end
	if #t.Offers[t.A] == 0 and #t.Offers[t.B] == 0 then
		close(t, "Intercambio vacío")
		return
	end
	local da, db = DataService.Get(t.A), DataService.Get(t.B)
	for _, item in t.Offers[t.A] do
		transfer(da, db, item)
	end
	for _, item in t.Offers[t.B] do
		transfer(db, da, item)
	end
	da.TradesCompleted += 1
	db.TradesCompleted += 1
	for _, p in { t.A, t.B } do
		DataService.Push(p)
		task.spawn(pcall, DataService.SaveNow, p)
	end
	close(t, "OK")
	for _, p in { t.A, t.B } do
		Net.Event("Notify"):FireClient(p, "¡Intercambio completado con " .. other(t, p).DisplayName .. "!", Color3.fromRGB(120, 255, 140))
	end
end

local function setOffer(player: Player, items: any)
	local t = trades[player]
	if not t or t.Closed or type(items) ~= "table" then
		return
	end
	local d = DataService.Get(player)
	local od = DataService.Get(other(t, player))
	if not d or not od then
		return
	end
	local clean: { Item } = {}
	local seen: { [string]: boolean } = {}
	for _, item in items do
		if #clean >= GameConfig.TradeMaxItems then
			break
		end
		if tradeable(item) and owns(d, item) and not owns(od, item) then
			local k = item.Kind .. ":" .. item.Id
			if not seen[k] then
				seen[k] = true
				table.insert(clean, { Kind = item.Kind, Id = item.Id })
			end
		end
	end
	t.Offers[player] = clean
	-- Cualquier cambio anula las confirmaciones
	t.Ready = {}
	t.ConfirmAt = nil
	t.Token += 1
	push(t)
end

local function setReady(player: Player, ready: any)
	local t = trades[player]
	if not t or t.Closed then
		return
	end
	t.Ready[player] = ready == true
	t.Token += 1
	t.ConfirmAt = nil
	if t.Ready[t.A] and t.Ready[t.B] then
		local token = t.Token
		t.ConfirmAt = workspace:GetServerTimeNow() + GameConfig.TradeConfirmTime
		task.delay(GameConfig.TradeConfirmTime, function()
			if t.Token == token and not t.Closed then
				execute(t)
			end
		end)
	end
	push(t)
end

local function canTrade(p: Player): boolean
	return p.Parent ~= nil and DataService.Get(p) ~= nil and not trades[p] and not DuelService.IsBusy(p)
end

local function onTrade(player: Player, action: any, arg: any)
	if action == "Request" then
		local target = arg
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target == player then
			return
		end
		if not canTrade(player) or not canTrade(target) then
			Net.Event("Notify"):FireClient(player, "Ese jugador no puede intercambiar ahora", Color3.fromRGB(255, 120, 90))
			return
		end
		requests[target] = requests[target] or {}
		local list = requests[target] :: { [Player]: number }
		if list[player] and os.clock() - list[player] < 10 then
			return
		end
		list[player] = os.clock()
		Net.Event("TradeUpdate"):FireClient(target, { Type = "Incoming", FromName = player.DisplayName, From = player })
		Net.Event("Notify"):FireClient(player, "Solicitud enviada a " .. target.DisplayName, Color3.fromRGB(200, 200, 200))
	elseif action == "Respond" then
		local from = arg
		local list = requests[player]
		if typeof(from) ~= "Instance" or not list or not list[from] then
			return
		end
		local fromPlayer = from :: Player
		local sentAt = list[fromPlayer]
		list[fromPlayer] = nil
		if os.clock() - sentAt > 60 then
			return -- solicitud caducada
		end
		if not canTrade(player) or not canTrade(fromPlayer) then
			return
		end
		local t: Trade = { A = fromPlayer, B = player, Offers = { [fromPlayer] = {}, [player] = {} }, Ready = {}, Token = 0, ConfirmAt = nil, Closed = false }
		trades[fromPlayer] = t
		trades[player] = t
		push(t)
	elseif action == "Decline" then
		local list = requests[player]
		if typeof(arg) == "Instance" and list then
			list[arg :: Player] = nil
		end
	elseif action == "SetOffer" then
		setOffer(player, arg)
	elseif action == "Ready" then
		setReady(player, arg)
	elseif action == "Cancel" then
		local t = trades[player]
		if t then
			close(t, player.DisplayName .. " canceló el intercambio")
		end
	end
end

local function gift(player: Player, target: any, item: any): (boolean, string)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == player then
		return false, "Jugador no válido"
	end
	if lastGift[player] and os.clock() - lastGift[player] < 3 then
		return false, "Espera un momento"
	end
	local d, td = DataService.Get(player), DataService.Get(target)
	if not d or not td then
		return false, "Datos no cargados"
	end
	if trades[player] then
		return false, "Termina primero tu intercambio"
	end
	if not tradeable(item) or not owns(d, item) then
		return false, "No puedes regalar eso"
	end
	if owns(td, item) then
		return false, target.DisplayName .. " ya lo tiene"
	end
	lastGift[player] = os.clock()
	transfer(d, td, item)
	DataService.Push(player)
	DataService.Push(target)
	task.spawn(pcall, DataService.SaveNow, player)
	task.spawn(pcall, DataService.SaveNow, target)
	Net.Event("Notify"):FireClient(target, string.format("🎁 %s te ha regalado: %s", player.DisplayName, itemName(item)), Color3.fromRGB(255, 205, 60))
	return true, "Regalo enviado"
end

function TradeService.Start()
	Net.Event("Trade").OnServerEvent:Connect(onTrade)
	Net.Function("Gift").OnServerInvoke = function(player, target, item)
		local ok, msg = gift(player, target, item)
		return { Ok = ok, Message = msg }
	end
	Players.PlayerRemoving:Connect(function(player)
		local t = trades[player]
		if t then
			close(t, player.DisplayName .. " salió del juego")
		end
		requests[player] = nil
		for _, list in requests do
			list[player] = nil
		end
		lastGift[player] = nil
	end)
end

return TradeService
