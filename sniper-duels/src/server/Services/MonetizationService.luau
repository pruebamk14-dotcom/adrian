--!strict
-- Monetización con Robux:
--  * Pase VIP: x2 monedas y caramelos + etiqueta dorada en el lobby.
--  * Productos: packs de monedas, pack de caramelos, armas exclusivas.
-- ProcessReceipt es idempotente (guarda los PurchaseId ya entregados) y guarda
-- los datos antes de confirmar la compra a Roblox, como recomienda la doc.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local DuelService = require(script.Parent.DuelService)

local M = GameConfig.Monetization
local MonetizationService = {}

local productKeyById: { [number]: string } = {}
for key, id in M.Products do
	if id ~= 0 then
		productKeyById[id] = key
	end
end

local function weaponForProduct(key: string): Weapons.Weapon?
	for _, w in Weapons.List do
		if w.RobuxProduct == key then
			return w
		end
	end
	return nil
end

function MonetizationService.IsVIP(player: Player): boolean
	local d = DataService.Get(player)
	return d ~= nil and d._VIP == true
end

function MonetizationService.RewardMultiplier(player: Player): number
	return if MonetizationService.IsVIP(player) then M.VIPMultiplier else 1
end

local function addVipTag(player: Player, character: Model)
	if not MonetizationService.IsVIP(player) or DuelService.IsBusy(player) then
		return
	end
	local head = character:WaitForChild("Head", 5) :: BasePart?
	if not head or DuelService.IsBusy(player) then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VIPTag"
	gui.Size = UDim2.fromOffset(90, 28)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 22, 8)
	label.BackgroundTransparency = 0.2
	label.Text = "★ VIP"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 205, 60)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 205, 60)
	stroke.Thickness = 1.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = head
end

local function setVIP(player: Player, value: boolean)
	local d = DataService.Get(player)
	if not d then
		return
	end
	d._VIP = value
	player:SetAttribute("VIP", value)
	DataService.Push(player)
	if value and player.Character then
		task.spawn(addVipTag, player, player.Character)
	end
end

local function grant(player: Player, key: string): boolean
	local d = DataService.Get(player)
	if not d then
		return false
	end
	if M.CoinPacks[key] then
		d.Coins += M.CoinPacks[key]
		Net.Event("Notify"):FireClient(player, string.format("+%d monedas. ¡Gracias por tu compra!", M.CoinPacks[key]), Color3.fromRGB(255, 205, 60))
		return true
	end
	if M.CandyPacks[key] then
		d.Candies += M.CandyPacks[key]
		Net.Event("Notify"):FireClient(player, string.format("+%d caramelos 🍬", M.CandyPacks[key]), Color3.fromRGB(255, 120, 200))
		return true
	end
	local w = weaponForProduct(key)
	if w then
		if d.Inventory.Weapons[w.Id] then
			-- Ya la tenía (p. ej. se la regalaron): compensar con monedas
			d.Coins += 5000
			Net.Event("Notify"):FireClient(player, "Ya tenías " .. w.DisplayName .. ": +5000 monedas de compensación", Color3.fromRGB(255, 205, 60))
		else
			d.Inventory.Weapons[w.Id] = true
			Net.Event("Notify"):FireClient(player, "¡" .. w.DisplayName .. " desbloqueada!", Color3.fromRGB(255, 205, 60))
		end
		return true
	end
	return false
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = function(info)
		local player = Players:GetPlayerByUserId(info.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local d = DataService.WaitFor(player, 15)
		if not d then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if table.find(d.ProcessedReceipts, info.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local key = productKeyById[info.ProductId]
		if not key or not grant(player, key) then
			warn("[Monetization] Producto desconocido:", info.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(d.ProcessedReceipts, info.PurchaseId)
		while #d.ProcessedReceipts > 50 do
			table.remove(d.ProcessedReceipts, 1)
		end
		local ok = pcall(DataService.SaveNow, player)
		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		DataService.Push(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	Net.Event("PromptPurchase").OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			return
		end
		if key == "VIP" then
			local id = M.GamePasses.VIP
			if id ~= 0 and not MonetizationService.IsVIP(player) then
				MarketplaceService:PromptGamePassPurchase(player, id)
			elseif id == 0 then
				Net.Event("Notify"):FireClient(player, "El pase VIP aún no está configurado", Color3.fromRGB(255, 120, 90))
			end
			return
		end
		local id = M.Products[key]
		if not id or id == 0 then
			Net.Event("Notify"):FireClient(player, "Este producto aún no está configurado", Color3.fromRGB(255, 120, 90))
			return
		end
		local w = weaponForProduct(key)
		local d = DataService.Get(player)
		if w and d and d.Inventory.Weapons[w.Id] then
			Net.Event("Notify"):FireClient(player, "Ya tienes " .. w.DisplayName, Color3.fromRGB(255, 205, 60))
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == M.GamePasses.VIP then
			setVIP(player, true)
			Net.Event("Notify"):FireClient(player, "★ ¡Ahora eres VIP! x2 monedas y caramelos", Color3.fromRGB(255, 205, 60))
		end
	end)

	DataService.Loaded:Connect(function(player: Player)
		local id = M.GamePasses.VIP
		if id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok and owns then
				setVIP(player, true)
			end
		end
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.wait(0.2) -- dejar que DuelService marque el duelo antes
			addVipTag(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return MonetizationService
