--!strict
-- Ranking global de ELO con OrderedDataStore, cacheado para no gastar cuota.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local DataService = require(script.Parent.DataService)

local REFRESH = 90
local LeaderboardService = {}

local ordered: OrderedDataStore? = nil
local cache: { { Name: string, UserId: number, Elo: number } } = {}
local lastRefresh = -math.huge
local names: { [number]: string } = {}

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok then name else ("#" .. userId)
	return names[userId]
end

local function refresh()
	if not ordered then
		-- Sin DataStore: ranking local con los jugadores del servidor
		local list = {}
		for _, p in Players:GetPlayers() do
			local d = DataService.Get(p)
			if d then
				table.insert(list, { Name = p.DisplayName, UserId = p.UserId, Elo = d.Elo })
			end
		end
		table.sort(list, function(a, b)
			return a.Elo > b.Elo
		end)
		cache = list
		return
	end
	local store = ordered :: OrderedDataStore
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 50)
	end)
	if not ok then
		return
	end
	local list = {}
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(string.match(entry.key, "%d+")) or 0
		table.insert(list, { Name = nameOf(userId), UserId = userId, Elo = entry.value })
	end
	cache = list
end

local function submit(player: Player)
	local d = DataService.Get(player)
	if d and ordered and d.RankedPlayed > 0 then
		local store = ordered :: OrderedDataStore
		pcall(function()
			store:SetAsync("u" .. player.UserId, math.floor(d.Elo))
		end)
	end
end

function LeaderboardService.Submit(player: Player)
	task.spawn(submit, player)
end

function LeaderboardService.Start()
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("EloLeaderboard_v1")
	end)
	if ok then
		local probe = pcall(function()
			store:GetSortedAsync(false, 1)
		end)
		if probe then
			ordered = store
		end
	end

	Net.Function("GetLeaderboard").OnServerInvoke = function()
		if os.clock() - lastRefresh > REFRESH or not ordered then
			lastRefresh = os.clock()
			refresh()
		end
		return cache
	end

	Players.PlayerRemoving:Connect(submit)
	task.spawn(function()
		while true do
			task.wait(180)
			for _, p in Players:GetPlayers() do
				submit(p)
			end
		end
	end)
end

return LeaderboardService
