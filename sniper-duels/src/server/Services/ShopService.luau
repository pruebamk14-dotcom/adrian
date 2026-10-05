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

local ShopService = {}
local rng = Random.new()
local lastPurchase: { [Player]: number } = {}

function ShopService.Start()
	Net.Function("BuyCrate").OnServerInvoke = function(player)
		local d = DataService.Get(player)
		if not d then
			return { Ok = false, Error = "Datos no cargados" }
		end
		if lastPurchase[player] and os.clock() - lastPurchase[player] < 1 then
			return { Ok = false, Error = "Demasiado rápido" }
		end
		lastPurchase[player] = os.clock()
		if d.Coins < GameConfig.CratePrice then
			return { Ok = false, Error = "Monedas insuficientes" }
		end
		d.Coins -= GameConfig.CratePrice
		local skin = Skins.Roll(rng)
		local duplicate = d.Inventory.Skins[skin.Id] == true
		local refund = 0
		if duplicate then
			refund = math.floor(GameConfig.CratePrice * GameConfig.DuplicateRefund)
			d.Coins += refund
		else
			d.Inventory.Skins[skin.Id] = true
		end
		DataService.Push(player)
		return { Ok = true, SkinId = skin.Id, Duplicate = duplicate, Refund = refund }
	end

	Net.Function("EquipSkin").OnServerInvoke = function(player, skinId)
		local d = DataService.Get(player)
		if not d or type(skinId) ~= "string" or not d.Inventory.Skins[skinId] or not Skins.List[skinId] then
			return false
		end
		if DuelService.IsBusy(player) then
			return false
		end
		d.Equipped.Skin = skinId
		DataService.Push(player)
		return true
	end

	Net.Function("EquipWeapon").OnServerInvoke = function(player, weaponId)
		local d = DataService.Get(player)
		if not d or type(weaponId) ~= "string" then
			return false
		end
		local w = Weapons.List[weaponId]
		if not w or d.Level < w.UnlockLevel or DuelService.IsBusy(player) then
			return false
		end
		d.Equipped.Weapon = weaponId
		DataService.Push(player)
		return true
	end

	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastPurchase[p] = nil
	end)
end

return ShopService
