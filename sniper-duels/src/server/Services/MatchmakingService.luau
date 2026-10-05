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
local BotService = require(script.Parent.BotService)

type QueueEntry = { Player: Player, Since: number, Ranked: boolean }

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
			Net.Event("QueueState"):FireClient(player, false, 0, "")
		end
	end
end

local function modeOf(e: QueueEntry): string
	return if e.Ranked then "Ranked" else "Casual"
end

local function startBotFor(player: Player, difficulty: string): boolean
	if not BotService.IsReady() then
		return false
	end
	local bot = BotService.Create(difficulty)
	if not bot then
		return false
	end
	if not DuelService.StartDuel(player, bot, false) then
		BotService.Destroy(bot)
		return false
	end
	return true
end

local function playerOnPad(pad: BasePart, taken: { [Player]: boolean }?): Player?
	local padPos = pad.Position
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and not (taken and taken[p]) then
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

local groupTimers: { [number]: number? } = {}
local botPadLast: { [Player]: number } = {}

local function updatePads()
	for _, group in ArenaService.PadGroups() do
		local taken: { [Player]: boolean } = {}
		local teamA, teamB = {}, {}
		local filled = 0
		for _, pad in group.A do
			local p = playerOnPad(pad, taken)
			if p then
				taken[p] = true
				table.insert(teamA, p)
				filled += 1
			end
		end
		for _, pad in group.B do
			local p = playerOnPad(pad, taken)
			if p then
				taken[p] = true
				table.insert(teamB, p)
				filled += 1
			end
		end
		local needed = #group.A + #group.B
		if filled == needed then
			local started = groupTimers[group.Id]
			if not started then
				groupTimers[group.Id] = os.clock()
				started = os.clock()
			end
			local remaining = GameConfig.PadCountdown - (os.clock() - (started :: number))
			if remaining <= 0 then
				if DuelService.StartTeams(teamA, teamB, false) then
					groupTimers[group.Id] = nil
					group.Label.Text = "DUELO " .. group.Mode
				else
					group.Label.Text = "Arenas llenas..."
				end
			else
				group.Label.Text = string.format("%d", math.ceil(remaining))
			end
		else
			groupTimers[group.Id] = nil
			if filled > 0 then
				group.Label.Text = string.format("Esperando %d/%d", filled, needed)
			else
				group.Label.Text = "DUELO " .. group.Mode
			end
		end
	end
	-- Pad de BOT: abre el menú de dificultad al subirse
	local bp = ArenaService.BotPad()
	if bp then
		local p = playerOnPad(bp)
		if p and os.clock() - (botPadLast[p] or 0) > 4 then
			botPadLast[p] = os.clock()
			Net.Event("OpenBotMenu"):FireClient(p)
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
	local matched: { [Player]: boolean } = {}

	-- Partida rápida: emparejar a los que más llevan esperando
	local casual = {}
	for _, e in queue do
		if not e.Ranked then
			table.insert(casual, e)
		end
	end
	table.sort(casual, function(x, y)
		return x.Since < y.Since
	end)
	local i = 1
	while i < #casual do
		local x, y = casual[i], casual[i + 1]
		if DuelService.StartDuel(x.Player, y.Player, false) then
			matched[x.Player] = true
			matched[y.Player] = true
		end
		i += 2
	end
	for _, e in casual do
		if not matched[e.Player] and now - e.Since >= GameConfig.CasualBotFallback then
			Net.Event("Notify"):FireClient(e.Player, "No hay nadie libre ahora mismo: ¡a calentar contra un bot!", Color3.fromRGB(255, 170, 60))
			if startBotFor(e.Player, "Normal") then
				matched[e.Player] = true
			end
		end
	end

	-- Ranked: por ELO, con ventana que crece con la espera
	local ranked = {}
	for _, e in queue do
		if e.Ranked then
			table.insert(ranked, e)
		end
	end
	local function elo(p: Player): number
		local d = DataService.Get(p)
		return d and d.Elo or GameConfig.StartingElo
	end
	table.sort(ranked, function(x, y)
		return elo(x.Player) < elo(y.Player)
	end)
	for k = 1, #ranked - 1 do
		local x, y = ranked[k], ranked[k + 1]
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

	for k = #queue, 1, -1 do
		local e = queue[k]
		if matched[e.Player] then
			table.remove(queue, k)
			Net.Event("QueueState"):FireClient(e.Player, false, 0, "")
		else
			Net.Event("QueueState"):FireClient(e.Player, true, math.floor(now - e.Since), modeOf(e))
		end
	end
end

function MatchmakingService.Start()
	Net.Event("QueueRanked").OnServerEvent:Connect(function(player)
		if DuelService.IsBusy(player) or queueIndex(player) or not DataService.Get(player) then
			return
		end
		table.insert(queue, { Player = player, Since = os.clock(), Ranked = true })
		Net.Event("QueueState"):FireClient(player, true, 0, "Ranked")
	end)
	Net.Event("QueueCasual").OnServerEvent:Connect(function(player)
		if DuelService.IsBusy(player) or queueIndex(player) or not DataService.Get(player) then
			return
		end
		table.insert(queue, { Player = player, Since = os.clock(), Ranked = false })
		Net.Event("QueueState"):FireClient(player, true, 0, "Casual")
	end)
	Net.Event("LeaveQueue").OnServerEvent:Connect(leaveQueue)

	-- Modo solo: duelo contra bot
	local lastBotRequest: { [Player]: number } = {}
	Net.Event("PlayBot").OnServerEvent:Connect(function(player, difficulty)
		if type(difficulty) ~= "string" or not BotService.Difficulties[difficulty] then
			return
		end
		if DuelService.IsBusy(player) or not DataService.Get(player) then
			return
		end
		if lastBotRequest[player] and os.clock() - lastBotRequest[player] < 2 then
			return
		end
		lastBotRequest[player] = os.clock()
		leaveQueue(player)
		if not BotService.IsReady() then
			Net.Event("Notify"):FireClient(player, "El bot aún se está preparando, prueba en unos segundos", Color3.fromRGB(255, 200, 80))
			return
		end
		local bot = BotService.Create(difficulty)
		if not bot then
			return
		end
		if not DuelService.StartDuel(player, bot, false) then
			BotService.Destroy(bot)
			Net.Event("Notify"):FireClient(player, "Todas las arenas están ocupadas, inténtalo enseguida", Color3.fromRGB(255, 120, 90))
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastBotRequest[p] = nil
	end)
	Players.PlayerRemoving:Connect(function(p)
		leaveQueue(p)
		botPadLast[p] = nil
	end)

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
