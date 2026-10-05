--!strict
-- Administración: rangos, expulsar, banear (persistente), dar monedas,
-- caramelos, niveles, skins y armas, y anuncios.
--
-- Rangos: Owner (creador del juego / dueño del grupo), Admin (lista en
-- GameConfig.Admins). En Studio todos son Owner para testear.
--
-- Se usa desde el panel 🛡 ADMIN del menú o escribiendo en el chat:
--   :coins <jugador> <cantidad>     :candies <jugador> <cantidad>
--   :level <jugador> <nivel>        :xp <jugador> <cantidad>
--   :skins <jugador>                :weapons <jugador>
--   :kick <jugador> [motivo]        :ban <jugador> [minutos|perm] [motivo]
--   :unban <userId>                 :announce <mensaje>
--   :elo <jugador> <valor>          :heal <jugador>
-- <jugador> puede ser parte del nombre, "me" o "all".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Skins = require(Shared.Config.Skins)
local Rank = require(Shared.Rank)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local AdminService = {}

local banStore: DataStore? = nil
local memoryBans: { [number]: any } = {}
local rankCache: { [Player]: string } = {}

local function rankOf(player: Player): string
	if rankCache[player] then
		return rankCache[player]
	end
	local rank = "Player"
	if RunService:IsStudio() and GameConfig.StudioEveryoneAdmin then
		rank = "Owner"
	elseif game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		rank = "Owner"
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, r = pcall(player.GetRankInGroup, player, game.CreatorId)
		if ok and r >= 255 then
			rank = "Owner"
		elseif ok and r >= 250 then
			rank = "Admin"
		end
	end
	if rank == "Player" and GameConfig.Admins[player.UserId] then
		rank = "Admin"
	end
	rankCache[player] = rank
	return rank
end

function AdminService.IsAdmin(player: Player): boolean
	local r = rankOf(player)
	return r == "Owner" or r == "Admin"
end

-- Bans ---------------------------------------------------------------------

local function getBan(userId: number): any
	if not banStore then
		return memoryBans[userId]
	end
	local store = banStore :: DataStore
	local ok, ban = pcall(function()
		return store:GetAsync("ban_" .. userId)
	end)
	return if ok then ban else nil
end

local function setBan(userId: number, ban: any)
	memoryBans[userId] = ban
	if banStore then
		local store = banStore :: DataStore
		pcall(function()
			if ban then
				store:SetAsync("ban_" .. userId, ban)
			else
				store:RemoveAsync("ban_" .. userId)
			end
		end)
	end
end

local function banMessage(ban: any): string
	local untilText = if ban.Until == 0 then "permanente" else ("hasta " .. os.date("!%d/%m/%Y %H:%M UTC", ban.Until))
	return string.format("Estás baneado (%s). Motivo: %s", untilText, ban.Reason or "sin motivo")
end

local function checkBan(player: Player)
	local ban = getBan(player.UserId)
	if ban then
		if ban.Until ~= 0 and os.time() >= ban.Until then
			setBan(player.UserId, nil)
		else
			player:Kick(banMessage(ban))
		end
	end
end

-- Comandos -----------------------------------------------------------------

local function findPlayers(caller: Player, query: string?): { Player }
	if not query or query == "" or query == "me" then
		return { caller }
	end
	if query == "all" then
		return Players:GetPlayers()
	end
	local q = string.lower(query)
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == q or string.lower(p.DisplayName) == q then
			return { p }
		end
	end
	for _, p in Players:GetPlayers() do
		if string.sub(string.lower(p.Name), 1, #q) == q or string.sub(string.lower(p.DisplayName), 1, #q) == q then
			return { p }
		end
	end
	return {}
end

local function notify(p: Player, text: string, color: Color3?)
	Net.Event("Notify"):FireClient(p, text, color or Color3.fromRGB(120, 200, 255))
end

local function eachData(targets: { Player }, fn: (Player, any) -> ()): number
	local n = 0
	for _, p in targets do
		local d = DataService.Get(p)
		if d then
			fn(p, d)
			DataService.Push(p)
			n += 1
		end
	end
	return n
end

type Command = { MinRank: string, Run: (caller: Player, args: { string }) -> string }

local COMMANDS: { [string]: Command } = {}

local function amountArg(args: { string }, i: number): number?
	local n = tonumber(args[i])
	if not n or n ~= n or math.abs(n) > 1e9 then
		return nil
	end
	return math.floor(n)
end

COMMANDS.coins = {
	MinRank = "Admin",
	Run = function(caller, args)
		local amount = amountArg(args, 2)
		if not amount then
			return "Uso: :coins <jugador> <cantidad>"
		end
		local n = eachData(findPlayers(caller, args[1]), function(p, d)
			d.Coins = math.max(0, d.Coins + amount)
			notify(p, string.format("Un admin te dio %+d monedas", amount), Color3.fromRGB(255, 205, 60))
		end)
		return string.format("%+d monedas a %d jugador(es)", amount, n)
	end,
}
COMMANDS.candies = {
	MinRank = "Admin",
	Run = function(caller, args)
		local amount = amountArg(args, 2)
		if not amount then
			return "Uso: :candies <jugador> <cantidad>"
		end
		local n = eachData(findPlayers(caller, args[1]), function(p, d)
			d.Candies = math.max(0, d.Candies + amount)
			notify(p, string.format("Un admin te dio %+d caramelos 🍬", amount), Color3.fromRGB(255, 120, 200))
		end)
		return string.format("%+d caramelos a %d jugador(es)", amount, n)
	end,
}
COMMANDS.level = {
	MinRank = "Admin",
	Run = function(caller, args)
		local lvl = amountArg(args, 2)
		if not lvl or lvl < 1 or lvl > 1000 then
			return "Uso: :level <jugador> <1-1000>"
		end
		local n = eachData(findPlayers(caller, args[1]), function(_, d)
			d.Level = lvl
			d.XP = 0
		end)
		return string.format("Nivel %d para %d jugador(es)", lvl, n)
	end,
}
COMMANDS.xp = {
	MinRank = "Admin",
	Run = function(caller, args)
		local amount = amountArg(args, 2)
		if not amount or amount < 0 then
			return "Uso: :xp <jugador> <cantidad>"
		end
		local count = 0
		for _, p in findPlayers(caller, args[1]) do
			DataService.AddXP(p, amount)
			DataService.Push(p)
			count += 1
		end
		return string.format("+%d XP a %d jugador(es)", amount, count)
	end,
}
COMMANDS.elo = {
	MinRank = "Owner",
	Run = function(caller, args)
		local v = amountArg(args, 2)
		if not v or v < 0 then
			return "Uso: :elo <jugador> <valor>"
		end
		local n = eachData(findPlayers(caller, args[1]), function(_, d)
			d.Elo = v
		end)
		return string.format("ELO %d (%s) para %d jugador(es)", v, Rank.FromElo(v).Name, n)
	end,
}
COMMANDS.skins = {
	MinRank = "Admin",
	Run = function(caller, args)
		local n = eachData(findPlayers(caller, args[1]), function(p, d)
			for id in Skins.List do
				d.Inventory.Skins[id] = true
			end
			notify(p, "Un admin te dio TODAS las skins", Color3.fromRGB(255, 205, 60))
		end)
		return "Todas las skins a " .. n .. " jugador(es)"
	end,
}
COMMANDS.weapons = {
	MinRank = "Admin",
	Run = function(caller, args)
		local n = eachData(findPlayers(caller, args[1]), function(p, d)
			for id, w in Weapons.List do
				if Weapons.IsShopWeapon(w) then
					d.Inventory.Weapons[id] = true
				end
			end
			d.Level = math.max(d.Level, 20) -- desbloquea también las de nivel
			notify(p, "Un admin te dio TODAS las armas", Color3.fromRGB(255, 205, 60))
		end)
		return "Todas las armas a " .. n .. " jugador(es)"
	end,
}
COMMANDS.heal = {
	MinRank = "Admin",
	Run = function(caller, args)
		local n = 0
		for _, p in findPlayers(caller, args[1]) do
			local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if h then
				h.Health = h.MaxHealth
				n += 1
			end
		end
		return "Curados " .. n
	end,
}
COMMANDS.kick = {
	MinRank = "Admin",
	Run = function(caller, args)
		local targets = findPlayers(caller, args[1])
		if not args[1] or #targets == 0 then
			return "Uso: :kick <jugador> [motivo]"
		end
		local reason = table.concat(args, " ", 2)
		for _, p in targets do
			if p ~= caller and rankOf(p) ~= "Owner" then
				p:Kick("Expulsado por un admin. " .. (if reason ~= "" then "Motivo: " .. reason else ""))
			end
		end
		return "Expulsado(s): " .. #targets
	end,
}
COMMANDS.ban = {
	MinRank = "Admin",
	Run = function(caller, args)
		local targets = findPlayers(caller, args[1])
		if not args[1] or #targets == 0 then
			return "Uso: :ban <jugador> [minutos|perm] [motivo]"
		end
		local minutes = tonumber(args[2])
		local permanent = args[2] == "perm" or args[2] == nil
		local reasonStart = if minutes or args[2] == "perm" then 3 else 2
		local reason = table.concat(args, " ", reasonStart)
		local banned = 0
		for _, p in targets do
			if p ~= caller and rankOf(p) ~= "Owner" then
				local ban = {
					Reason = if reason ~= "" then reason else "Incumplir las normas",
					By = caller.UserId,
					At = os.time(),
					Until = if permanent or not minutes then 0 else os.time() + math.floor(minutes * 60),
				}
				setBan(p.UserId, ban)
				p:Kick(banMessage(ban))
				banned += 1
			end
		end
		return "Baneado(s): " .. banned
	end,
}
COMMANDS.unban = {
	MinRank = "Admin",
	Run = function(_, args)
		local id = tonumber(args[1])
		if not id then
			return "Uso: :unban <userId>"
		end
		setBan(id, nil)
		return "Desbaneado " .. id
	end,
}
COMMANDS.announce = {
	MinRank = "Admin",
	Run = function(caller, args)
		local msg = table.concat(args, " ")
		if msg == "" then
			return "Uso: :announce <mensaje>"
		end
		Net.Event("Announce"):FireAllClients(caller.DisplayName, string.sub(msg, 1, 200))
		return "Anuncio enviado"
	end,
}

local RANK_LEVEL = { Player = 0, Admin = 1, Owner = 2 }

function AdminService.Run(caller: Player, text: string): string
	if type(text) ~= "string" or #text > 300 then
		return "Comando no válido"
	end
	text = string.gsub(text, "^[:!/]", "")
	local args = string.split(text, " ")
	local name = string.lower(table.remove(args, 1) or "")
	local cleaned = {}
	for _, a in args do
		if a ~= "" then
			table.insert(cleaned, a)
		end
	end
	local cmd = COMMANDS[name]
	if not cmd then
		local names = {}
		for n in COMMANDS do
			table.insert(names, ":" .. n)
		end
		table.sort(names)
		return "Comandos: " .. table.concat(names, " ")
	end
	if RANK_LEVEL[rankOf(caller)] < RANK_LEVEL[cmd.MinRank] then
		return "No tienes permiso para :" .. name
	end
	local ok, result = pcall(cmd.Run, caller, cleaned)
	if not ok then
		warn("[Admin]", result)
		return "Error: " .. tostring(result)
	end
	print(string.format("[Admin] %s (%d): %s -> %s", caller.Name, caller.UserId, text, result))
	return result
end

function AdminService.Start()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("SniperDuels_Bans_v1")
	end)
	if ok then
		local probe = pcall(function()
			store:GetAsync("__probe")
		end)
		if probe then
			banStore = store
		end
	end

	local function onPlayer(player: Player)
		task.spawn(checkBan, player)
		local rank = rankOf(player)
		player:SetAttribute("SD_Rank", rank)
		player.Chatted:Connect(function(msg)
			if string.sub(msg, 1, 1) == ":" and AdminService.IsAdmin(player) then
				notify(player, AdminService.Run(player, msg), Color3.fromRGB(120, 200, 255))
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		rankCache[p] = nil
	end)

	Net.Function("AdminCommand").OnServerInvoke = function(player, text)
		if not AdminService.IsAdmin(player) then
			return "No eres admin"
		end
		return AdminService.Run(player, text)
	end
end

return AdminService
