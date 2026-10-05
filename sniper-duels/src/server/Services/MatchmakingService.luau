--!strict
-- Dos formas de entrar a un duelo:
--  1) Pads del lobby (casual): dos jugadores se suben a un par de pads.
--  2) Cola ranked: empareja por ELO con ventana que crece con la espera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local ArenaService = require(script.Parent.ArenaService)
local DuelService = require(script.Parent.DuelService)
local DataService = require(script.Parent.DataService)

type QueueEntry = { Player: Player, Since: number }

local MatchmakingService = {}

local queue: { QueueEntry } = {}
local padTimers: { [number]: number? } = {}

local function queueIndex(player: Player): number?
	for i, e in queue do
		if e.Player == player then
			return i
		end
	end
	return nil
end

local function leaveQueue(player: Player)
	local i = queueIndex(player)
	if i then
		table.remove(queue, i)
		if player.Parent then
			Net.Event("QueueState"):FireClient(player, false, 0)
		end
	end
end

local function playerOnPad(pad: BasePart): Player?
	local padPos = pad.Position
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local d = root.Position - padPos
			if Vector2.new(d.X, d.Z).Magnitude <= GameConfig.PadRadius and d.Y > -1 and d.Y < 8 then
				if not DuelService.IsBusy(p) and not queueIndex(p) then
					return p
				end
			end
		end
	end
	return nil
end

local function updatePads()
	for _, pair in ArenaService.PadPairs() do
		local a = playerOnPad(pair.A)
		local b = playerOnPad(pair.B)
		if a and b and a ~= b then
			local started = padTimers[pair.Id]
			if not started then
				padTimers[pair.Id] = os.clock()
				started = os.clock()
			end
			local remaining = GameConfig.PadCountdown - (os.clock() - (started :: number))
			if remaining <= 0 then
				if DuelService.StartDuel(a, b, false) then
					padTimers[pair.Id] = nil
					pair.Label.Text = "DUELO 1v1"
				else
					pair.Label.Text = "Arenas llenas..."
				end
			else
				pair.Label.Text = string.format("%s vs %s\n%d", a.DisplayName, b.DisplayName, math.ceil(remaining))
			end
		else
			padTimers[pair.Id] = nil
			if a or b then
				pair.Label.Text = "Esperando rival..."
			else
				pair.Label.Text = "DUELO 1v1"
			end
		end
	end
end

local function updateQueue()
	local now = os.clock()
	-- Limpiar entradas inválidas
	for i = #queue, 1, -1 do
		local e = queue[i]
		if not e.Player.Parent or DuelService.IsBusy(e.Player) then
			table.remove(queue, i)
		end
	end
	if #queue < 2 then
		for _, e in queue do
			Net.Event("QueueState"):FireClient(e.Player, true, math.floor(now - e.Since))
		end
		return
	end

	local function elo(p: Player): number
		local d = DataService.Get(p)
		return d and d.Elo or GameConfig.StartingElo
	end
	table.sort(queue, function(x, y)
		return elo(x.Player) < elo(y.Player)
	end)

	local matched: { [Player]: boolean } = {}
	for i = 1, #queue - 1 do
		local x, y = queue[i], queue[i + 1]
		if not matched[x.Player] and not matched[y.Player] then
			local waited = math.min(now - x.Since, now - y.Since)
			local window = GameConfig.BaseEloWindow + GameConfig.EloWindowGrowthPerSecond * waited
			if math.abs(elo(x.Player) - elo(y.Player)) <= window then
				if DuelService.StartDuel(x.Player, y.Player, true) then
					matched[x.Player] = true
					matched[y.Player] = true
				end
			end
		end
	end
	for i = #queue, 1, -1 do
		local e = queue[i]
		if matched[e.Player] then
			table.remove(queue, i)
			Net.Event("QueueState"):FireClient(e.Player, false, 0)
		else
			Net.Event("QueueState"):FireClient(e.Player, true, math.floor(now - e.Since))
		end
	end
end

function MatchmakingService.Start()
	Net.Event("QueueRanked").OnServerEvent:Connect(function(player)
		if DuelService.IsBusy(player) or queueIndex(player) or not DataService.Get(player) then
			return
		end
		table.insert(queue, { Player = player, Since = os.clock() })
		Net.Event("QueueState"):FireClient(player, true, 0)
	end)
	Net.Event("LeaveQueue").OnServerEvent:Connect(leaveQueue)
	Players.PlayerRemoving:Connect(leaveQueue)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(updatePads)
			if not ok then
				warn("[Matchmaking] pads:", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(updateQueue)
			if not ok then
				warn("[Matchmaking] queue:", err)
			end
		end
	end)
end

return MatchmakingService
