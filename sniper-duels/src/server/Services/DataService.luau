--!strict
-- Persistencia con session-lock, autosave, reintentos y fallback en memoria
-- (Studio sin acceso a API). Para producción a gran escala puedes cambiar
-- este módulo por ProfileStore manteniendo la misma API pública.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Rank = require(Shared.Rank)
local Signal = require(Shared.Signal)
local Net = require(Shared.Net)

local STORE_NAME = "SniperDuelsElite_v1"
local AUTOSAVE_INTERVAL = 120
local LOCK_TIMEOUT = 600

local DataService = {}
DataService.Loaded = Signal.new()

local profiles: { [Player]: any } = {}
local store: DataStore? = nil
local useMemory = false
local memoryStore: { [string]: any } = {}

local function template()
	return {
		Version = 1,
		Coins = 250,
		XP = 0,
		Level = 1,
		Elo = GameConfig.StartingElo,
		RankedPlayed = 0,
		Wins = 0,
		Losses = 0,
		Kills = 0,
		Deaths = 0,
		Headshots = 0,
		ShotsFired = 0,
		ShotsHit = 0,
		LongestShot = 0,
		WinStreak = 0,
		BestStreak = 0,
		Inventory = { Skins = { Default = true } },
		Equipped = { Weapon = "Intervention", Skin = "Default" },
		Settings = { Sensitivity = 1, ScopeSensitivity = 0.55, ToggleScope = false },
	}
end

local function reconcile(data: any, tpl: any)
	for k, v in tpl do
		if data[k] == nil then
			data[k] = if type(v) == "table" then table.clone(v) else v
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
end

local function retry<T>(fn: () -> T): (boolean, T | string)
	local lastErr: any
	for attempt = 1, 5 do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		task.wait(2 ^ attempt * 0.5)
	end
	return false, tostring(lastErr)
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		-- En Studio sin "Enable Studio Access to API Services" las llamadas fallan:
		-- lo detectamos una vez para no esperar reintentos en cada jugador.
		if RunService:IsStudio() then
			local probeOk = pcall(function()
				result:GetAsync("__probe")
			end)
			useMemory = not probeOk
		end
	else
		useMemory = true
	end
	if useMemory then
		warn("[DataService] DataStore no disponible, los datos se guardan solo en memoria.")
	end
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function loadRaw(player: Player): any
	if useMemory or not store then
		return memoryStore[key(player)]
	end
	local jobId = if RunService:IsStudio() then "studio" else game.JobId
	local ds = store :: DataStore
	local ok, res = retry(function()
		local loaded
		ds:UpdateAsync(key(player), function(old)
			old = old or template()
			local lock = old.SessionLock
			if lock and lock.JobId ~= jobId and os.time() - lock.Time < LOCK_TIMEOUT then
				loaded = "LOCKED"
				return nil
			end
			old.SessionLock = { JobId = jobId, Time = os.time() }
			loaded = old
			return old
		end)
		return loaded
	end)
	if not ok then
		error(res)
	end
	return res
end

local function saveRaw(player: Player, data: any, release: boolean)
	if useMemory or not store then
		memoryStore[key(player)] = data
		return
	end
	local ds = store :: DataStore
	local jobId = if RunService:IsStudio() then "studio" else game.JobId
	retry(function()
		ds:UpdateAsync(key(player), function(old)
			if old and old.SessionLock and old.SessionLock.JobId ~= jobId then
				return nil -- otra sesión tomó el control, no sobrescribir
			end
			local copy = table.clone(data)
			copy.SessionLock = if release then nil else { JobId = jobId, Time = os.time() }
			return copy
		end)
	end)
end

local function publicData(data: any)
	return {
		Coins = data.Coins,
		XP = data.XP,
		Level = data.Level,
		XPNext = Rank.XPForLevel(data.Level),
		Elo = data.Elo,
		RankedPlayed = data.RankedPlayed,
		Wins = data.Wins,
		Losses = data.Losses,
		Kills = data.Kills,
		Deaths = data.Deaths,
		Headshots = data.Headshots,
		Accuracy = if data.ShotsFired > 0 then data.ShotsHit / data.ShotsFired else 0,
		LongestShot = data.LongestShot,
		WinStreak = data.WinStreak,
		BestStreak = data.BestStreak,
		Inventory = data.Inventory,
		Equipped = data.Equipped,
		Settings = data.Settings,
	}
end

local function setupLeaderstats(player: Player, data: any)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local elo = Instance.new("IntValue")
	elo.Name = "ELO"
	elo.Value = data.Elo
	elo.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Victorias"
	wins.Value = data.Wins
	wins.Parent = ls
	ls.Parent = player
end

function DataService.Get(player: Player): any
	return profiles[player]
end

function DataService.WaitFor(player: Player, timeout: number?): any
	local start = os.clock()
	while not profiles[player] and player.Parent and os.clock() - start < (timeout or 30) do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.Push(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("ELO") :: IntValue).Value = data.Elo;
		(ls:FindFirstChild("Victorias") :: IntValue).Value = data.Wins
	end
	player:SetAttribute("Elo", data.Elo)
	player:SetAttribute("Level", data.Level)
	Net.Event("DataUpdate"):FireClient(player, publicData(data))
end

-- Suma XP y sube de nivel. Devuelve niveles ganados.
function DataService.AddXP(player: Player, amount: number): number
	local data = profiles[player]
	if not data then
		return 0
	end
	data.XP += amount
	local gained = 0
	while data.XP >= Rank.XPForLevel(data.Level) do
		data.XP -= Rank.XPForLevel(data.Level)
		data.Level += 1
		gained += 1
	end
	if gained > 0 then
		Net.Event("Notify"):FireClient(player, "¡Nivel " .. data.Level .. "!", Color3.fromRGB(255, 215, 64))
	end
	return gained
end

function DataService.Public(player: Player)
	local d = profiles[player]
	return d and publicData(d)
end

local function onPlayerAdded(player: Player)
	local ok, raw = pcall(loadRaw, player)
	if not ok then
		player:Kick("No se pudieron cargar tus datos. Inténtalo de nuevo.")
		return
	end
	if raw == "LOCKED" then
		player:Kick("Tus datos siguen abiertos en otro servidor. Espera unos segundos y vuelve a entrar.")
		return
	end
	if not player.Parent then
		return
	end
	local data = raw or template()
	data.SessionLock = nil
	reconcile(data, template())
	profiles[player] = data
	setupLeaderstats(player, data)
	DataService.Push(player)
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local data = profiles[player]
	if data then
		saveRaw(player, data, true)
		profiles[player] = nil
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	Net.Function("GetData").OnServerInvoke = function(player)
		local d = DataService.WaitFor(player, 15)
		return d and publicData(d)
	end

	Net.Function("UpdateSettings").OnServerInvoke = function(player, settings)
		local d = profiles[player]
		if not d or type(settings) ~= "table" then
			return false
		end
		if type(settings.Sensitivity) == "number" then
			d.Settings.Sensitivity = math.clamp(settings.Sensitivity, 0.1, 4)
		end
		if type(settings.ScopeSensitivity) == "number" then
			d.Settings.ScopeSensitivity = math.clamp(settings.ScopeSensitivity, 0.05, 2)
		end
		if type(settings.ToggleScope) == "boolean" then
			d.Settings.ToggleScope = settings.ToggleScope
		end
		return true
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, data in profiles do
				task.spawn(saveRaw, player, data, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, data in profiles do
			pending += 1
			task.spawn(function()
				saveRaw(player, data, true)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
