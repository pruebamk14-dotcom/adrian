--!strict
-- Cajas de skins (con monedas del juego), equipar skins y armas por nivel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Skins = require(Shared.Config.Skins)
local Weapons = require(Shared.Config.Weapons)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local DuelService = require(script.Parent.DuelService)
local CombatService = require(script.Parent.CombatService)

local ShopService = {}
local rng = Random.new()
local lastPurchase: { [Player]: number } = {}

function ShopService.Start()
	Net.Function("BuyCrate").OnServerInvoke = function(player, crateId)
		local d = DataService.Get(player)
		if not d then
			return { Ok = false, Error = "Datos no cargados" }
		end
		if lastPurchase[player] and os.clock() - lastPurchase[player] < 1 then
			return { Ok = false, Error = "Demasiado rápido" }
		end
		lastPurchase[player] = os.clock()
		local halloween = crateId == "Halloween"
		if halloween and not GameConfig.HalloweenEvent then
			return { Ok = false, Error = "El evento de Halloween ha terminado" }
		end
		local currency = if halloween then "Candies" else "Coins"
		local price = if halloween then GameConfig.HalloweenCratePrice else GameConfig.CratePrice
		if d[currency] < price then
			return { Ok = false, Error = if halloween then "Caramelos insuficientes" else "Monedas insuficientes" }
		end
		d[currency] -= price
		local skin = Skins.Roll(rng, if halloween then "Halloween" else "Standard")
		local duplicate = d.Inventory.Skins[skin.Id] == true
		local refund = 0
		if duplicate then
			refund = math.floor(price * GameConfig.DuplicateRefund)
			d[currency] += refund
		else
			d.Inventory.Skins[skin.Id] = true
		end
		DataService.Push(player)
		return { Ok = true, SkinId = skin.Id, Duplicate = duplicate, Refund = refund, Currency = currency }
	end

	Net.Function("EquipSkin").OnServerInvoke = function(player, skinId)
		local d = DataService.Get(player)
		if not d or type(skinId) ~= "string" or not d.Inventory.Skins[skinId] or not Skins.List[skinId] then
			return false
		end
		d.Equipped.Skin = skinId
		DataService.Push(player)
		if DuelService.IsBusy(player) then
			CombatService.Rearm(player)
		end
		return true
	end

	Net.Function("BuyWeapon").OnServerInvoke = function(player, weaponId)
		local d = DataService.Get(player)
		local w = type(weaponId) == "string" and Weapons.List[weaponId] or nil
		if not d or not w or not w.CoinPrice then
			return { Ok = false, Error = "No disponible" }
		end
		if Weapons.Owns(d, w.Id) then
			return { Ok = false, Error = "Ya la tienes" }
		end
		if d.Coins < w.CoinPrice then
			return { Ok = false, Error = "Monedas insuficientes" }
		end
		d.Coins -= w.CoinPrice
		d.Inventory.Weapons[w.Id] = true
		DataService.Push(player)
		return { Ok = true }
	end

	Net.Function("EquipWeapon").OnServerInvoke = function(player, weaponId)
		local d = DataService.Get(player)
		if not d or type(weaponId) ~= "string" then
			return false
		end
		local w = Weapons.List[weaponId]
		if not w or not Weapons.Owns(d, weaponId) then
			return false
		end
		d.Equipped.Weapon = weaponId
		DataService.Push(player)
		if DuelService.IsBusy(player) then
			CombatService.Rearm(player)
		end
		return true
	end

	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastPurchase[p] = nil
	end)
end

return ShopService
