--!strict
-- Ciclo de vida del duelo 1v1: intro -> cuenta atrás -> ronda -> fin de ronda
-- ... -> fin del duelo (recompensas, ELO, rachas) -> vuelta al lobby.
-- Un lado puede ser un bot (modo solo): ver BotService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Rank = require(Shared.Rank)
local Net = require(Shared.Net)

local ArenaService = require(script.Parent.ArenaService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)

type Combatant = any -- Player | Bot

type Duel = {
	Id: number,
	Players: { Combatant },
	Arena: ArenaService.Arena,
	Scores: { [Combatant]: number },
	Kills: { [Combatant]: number },
	Headshots: { [Combatant]: number },
	Round: number,
	State: string,
	Ranked: boolean,
	VsBot: boolean,
	RoundToken: number,
	RoundEndsAt: number,
	LastKill: { Headshot: boolean, Distance: number }?,
	Connections: { RBXScriptConnection },
	Finished: boolean,
}

local DuelService = {}

-- BotService rellena esto (evita dependencia circular)
DuelService.BotHooks = {
	Respawn = function(_bot: Combatant, _cf: CFrame) end,
	Destroy = function(_bot: Combatant) end,
}

local duels: { [Combatant]: Duel } = {}
local nextId = 0

local isPlayer = CombatService.IsPlayer

local function present(c: Combatant): boolean
	if isPlayer(c) then
		return c.Parent ~= nil
	end
	return c.Active == true
end

local function opponentOf(duel: Duel, c: Combatant): Combatant
	return if duel.Players[1] == c then duel.Players[2] else duel.Players[1]
end

local function eloOf(c: Combatant): number
	if isPlayer(c) then
		return (c:GetAttribute("Elo") :: number?) or GameConfig.StartingElo
	end
	return c.Elo or GameConfig.StartingElo
end

local function sendState(duel: Duel, extra: { [string]: any }?)
	for _, p in duel.Players do
		if isPlayer(p) and p.Parent then
			local opp = opponentOf(duel, p)
			local payload: { [string]: any } = {
				State = duel.State,
				Round = duel.Round,
				RoundsToWin = GameConfig.RoundsToWin,
				MyScore = duel.Scores[p],
				OppScore = duel.Scores[opp],
				OpponentName = opp.DisplayName,
				OpponentElo = eloOf(opp),
				OpponentIsBot = not isPlayer(opp),
				Arena = duel.Arena.Name,
				Ranked = duel.Ranked,
				VsBot = duel.VsBot,
				EndsAt = duel.RoundEndsAt,
			}
			if extra then
				for k, v in extra do
					if k ~= "PerPlayer" and k ~= "RoundWinner" and k ~= "Winner" then
						payload[k] = v
					end
				end
				if extra.RoundWinner ~= nil or extra.Reason == "draw" then
					payload.RoundWon = extra.RoundWinner == p
					payload.IsDraw = extra.RoundWinner == nil
				end
				if extra.Winner ~= nil then
					payload.Won = extra.Winner == p
				end
				if extra.PerPlayer and extra.PerPlayer[p] then
					for k, v in extra.PerPlayer[p] do
						payload[k] = v
					end
				end
			end
			Net.Event("DuelState"):FireClient(p, payload)
		end
	end
end

local function disconnectAll(duel: Duel)
	for _, c in duel.Connections do
		c:Disconnect()
	end
	table.clear(duel.Connections)
end

local function setFrozen(c: Combatant, frozen: boolean)
	local root = c.Character and c.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = frozen
	end
end

local function clearHighlights(duel: Duel)
	for _, p in duel.Players do
		local h = p.Character and p.Character:FindFirstChild("RevealHighlight")
		if h then
			h:Destroy()
		end
	end
end

local roundOver: (duel: Duel, winner: Combatant?, reason: string) -> ()
local endDuel: (duel: Duel, winner: Combatant, reason: string) -> ()

local function spawnCombatant(duel: Duel, c: Combatant, cf: CFrame)
	if isPlayer(c) then
		c:LoadCharacter()
		local char = c.Character
		if char then
			char:PivotTo(cf)
		end
	else
		DuelService.BotHooks.Respawn(c, cf)
	end
	local char = c.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = GameConfig.MaxHealth
		hum.Health = GameConfig.MaxHealth
		-- Sin nombres flotantes: en un duelo de francotiradores delatarían posiciones
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	if duel.Round == 1 then
		if isPlayer(c) then
			CombatService.Arm(c)
		else
			CombatService.Arm(c, c.WeaponId, c.SkinId)
		end
	else
		CombatService.ResetForRound(c)
	end
	CombatService.SetCanFire(c, false)
	setFrozen(c, true)
end

local function spawnRound(duel: Duel)
	if duel.Finished then
		return
	end
	disconnectAll(duel)
	duel.Round += 1
	duel.RoundToken += 1
	local token = duel.RoundToken
	duel.LastKill = nil
	duel.State = "Countdown"

	-- Cargar ambos personajes en paralelo
	local pending = 0
	for i, c in duel.Players do
		pending += 1
		task.spawn(function()
			if present(c) then
				local ok, err = pcall(spawnCombatant, duel, c, if i == 1 then duel.Arena.SpawnA else duel.Arena.SpawnB)
				if not ok then
					warn("[Duel] spawn:", err)
				end
			end
			pending -= 1
		end)
	end
	local waitStart = os.clock()
	while pending > 0 and os.clock() - waitStart < 10 do
		task.wait()
	end
	if duel.Finished or duel.RoundToken ~= token then
		return
	end

	-- Muerte por cualquier causa (caída, reset...) = punto para el rival
	for _, c in duel.Players do
		local hum = c.Character and c.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(
				duel.Connections,
				hum.Died:Connect(function()
					task.delay(0.15, function()
						if duel.RoundToken == token and duel.State == "Live" then
							roundOver(duel, opponentOf(duel, c), "death")
						end
					end)
				end)
			)
		end
	end

	duel.RoundEndsAt = workspace:GetServerTimeNow() + GameConfig.CountdownTime
	sendState(duel, { Countdown = GameConfig.CountdownTime })
	task.wait(GameConfig.CountdownTime)
	if duel.Finished or duel.RoundToken ~= token then
		return
	end

	duel.State = "Live"
	duel.RoundEndsAt = workspace:GetServerTimeNow() + GameConfig.RoundMaxTime
	for _, c in duel.Players do
		setFrozen(c, false)
		CombatService.SetCanFire(c, true)
	end
	sendState(duel)

	-- Revelar posiciones contra el camping
	task.delay(GameConfig.RevealAfter, function()
		if duel.RoundToken ~= token or duel.State ~= "Live" then
			return
		end
		for _, c in duel.Players do
			if c.Character then
				local h = Instance.new("Highlight")
				h.Name = "RevealHighlight"
				h.FillTransparency = 1
				h.OutlineColor = Color3.fromRGB(255, 120, 30)
				h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				h.Parent = c.Character
			end
			if isPlayer(c) then
				Net.Event("Notify"):FireClient(c, "¡Posiciones reveladas!", Color3.fromRGB(255, 120, 30))
			end
		end
	end)

	-- Límite de tiempo: gana quien tenga más vida
	task.delay(GameConfig.RoundMaxTime, function()
		if duel.RoundToken ~= token or duel.State ~= "Live" then
			return
		end
		local a, b = duel.Players[1], duel.Players[2]
		local function hp(c: Combatant): number
			local h = c.Character and c.Character:FindFirstChildOfClass("Humanoid")
			return h and h.Health or 0
		end
		if hp(a) > hp(b) then
			roundOver(duel, a, "time")
		elseif hp(b) > hp(a) then
			roundOver(duel, b, "time")
		else
			roundOver(duel, nil, "draw")
		end
	end)
end

roundOver = function(duel: Duel, winner: Combatant?, reason: string)
	if duel.Finished or duel.State ~= "Live" then
		return
	end
	duel.State = "RoundEnd"
	for _, c in duel.Players do
		CombatService.SetCanFire(c, false)
	end
	clearHighlights(duel)

	if winner then
		duel.Scores[winner] += 1
	end

	local kill = duel.LastKill
	sendState(duel, {
		RoundWinner = winner,
		Reason = reason,
		Headshot = kill and kill.Headshot or false,
		Distance = kill and kill.Distance or 0,
	})

	if winner and duel.Scores[winner] >= GameConfig.RoundsToWin then
		task.wait(GameConfig.RoundEndTime * 0.6)
		endDuel(duel, winner, "score")
		return
	end
	task.wait(GameConfig.RoundEndTime)
	spawnRound(duel)
end

local function returnToLobby(c: Combatant)
	if isPlayer(c) then
		if not c.Parent then
			return
		end
		CombatService.Disarm(c)
		c:LoadCharacter()
	else
		CombatService.Disarm(c)
		DuelService.BotHooks.Destroy(c)
	end
end

endDuel = function(duel: Duel, winner: Combatant, reason: string)
	if duel.Finished then
		return
	end
	duel.Finished = true
	duel.State = "Ended"
	disconnectAll(duel)
	clearHighlights(duel)
	for _, c in duel.Players do
		CombatService.SetCanFire(c, false)
	end
	local loser = opponentOf(duel, winner)
	local R = GameConfig.Rewards
	local mult = if duel.Ranked then R.RankedMultiplier elseif duel.VsBot then R.BotMultiplier else 1

	local perPlayer = {}
	local wd = if isPlayer(winner) then DataService.Get(winner) else nil
	local ld = if isPlayer(loser) then DataService.Get(loser) else nil

	local eloW, eloL = 0, 0
	if duel.Ranked and wd then
		-- Si el perdedor abandonó, sus datos pueden haberse descargado ya
		local loserElo = if ld then ld.Elo else eloOf(loser)
		local loserPlayed = if ld then ld.RankedPlayed else GameConfig.PlacementMatches
		local kW = if wd.RankedPlayed < GameConfig.PlacementMatches then GameConfig.EloKPlacement else GameConfig.EloK
		local kL = if loserPlayed < GameConfig.PlacementMatches then GameConfig.EloKPlacement else GameConfig.EloK
		eloW, eloL = Rank.EloDelta(wd.Elo, loserElo, 1, kW, kL)
		eloW = math.max(eloW, 1)
		wd.Elo += eloW
		wd.RankedPlayed += 1
		if ld then
			ld.Elo = math.max(0, ld.Elo + eloL)
			ld.RankedPlayed += 1
		end
	end

	for _, p in duel.Players do
		if not isPlayer(p) then
			continue
		end
		local d = DataService.Get(p)
		local won = p == winner
		local kills = duel.Kills[p] or 0
		local base = (if won then R.WinCoins else R.LossCoins) + kills * R.KillCoins + (duel.Headshots[p] or 0) * R.HeadshotBonusCoins
		local coins = math.floor(base * mult)
		local xp = math.floor(((if won then R.WinXP else R.LossXP) + kills * R.KillXP) * mult)
		local candy = 0
		if GameConfig.HalloweenEvent then
			candy = math.floor(((if won then R.WinCandy else 0) + kills * R.KillCandy) * (if duel.VsBot then R.BotMultiplier else 1))
		end
		if d and d._VIP then
			coins *= GameConfig.Monetization.VIPMultiplier
			candy *= GameConfig.Monetization.VIPMultiplier
		end
		if reason == "forfeit" and not won then
			coins, xp, candy = 0, 0, 0
		end
		if d then
			d.Coins += coins
			d.Candies += candy
			if won then
				d.Wins += 1
				-- Las rachas solo cuentan contra jugadores reales
				if not duel.VsBot then
					d.WinStreak += 1
					d.BestStreak = math.max(d.BestStreak, d.WinStreak)
					local streakBonus = math.floor(coins * math.min(d.WinStreak - 1, 5) * 0.1)
					d.Coins += streakBonus
					coins += streakBonus
				end
			else
				d.Losses += 1
				if not duel.VsBot then
					d.WinStreak = 0
				end
			end
			DataService.AddXP(p, xp)
			DataService.Push(p)
			if duel.Ranked then
				LeaderboardService.Submit(p)
			end
		end
		perPlayer[p] = {
			Coins = coins,
			XP = xp,
			Candies = candy,
			EloDelta = if duel.Ranked then (if won then eloW else eloL) else nil,
			NewElo = d and d.Elo,
			Streak = d and d.WinStreak,
		}
	end

	sendState(duel, { Winner = winner, Reason = reason, PerPlayer = perPlayer })

	if not duel.VsBot then
		for _, p in Players:GetPlayers() do
			Net.Event("Notify"):FireClient(
				p,
				string.format("%s venció a %s (%d-%d)%s", winner.DisplayName, loser.DisplayName, duel.Scores[winner], duel.Scores[loser], if duel.Ranked then " · Ranked" else ""),
				Color3.fromRGB(200, 200, 200)
			)
		end
	end

	task.wait(5)
	for _, c in duel.Players do
		duels[c] = nil
		task.spawn(returnToLobby, c)
	end
	ArenaService.Release(duel.Arena)
end

function DuelService.IsBusy(c: Combatant): boolean
	return duels[c] ~= nil
end

function DuelService.StartDuel(a: Combatant, b: Combatant, ranked: boolean): boolean
	if a == b or duels[a] or duels[b] or not present(a) or not present(b) then
		return false
	end
	local arena = ArenaService.Acquire()
	if not arena then
		return false
	end
	nextId += 1
	local vsBot = not isPlayer(a) or not isPlayer(b)
	local duel: Duel = {
		Id = nextId,
		Players = { a, b },
		Arena = arena,
		Scores = { [a] = 0, [b] = 0 },
		Kills = { [a] = 0, [b] = 0 },
		Headshots = { [a] = 0, [b] = 0 },
		Round = 0,
		State = "Intro",
		Ranked = ranked and not vsBot,
		VsBot = vsBot,
		RoundToken = 0,
		RoundEndsAt = workspace:GetServerTimeNow() + GameConfig.IntroTime,
		LastKill = nil,
		Connections = {},
		Finished = false,
	}
	duels[a] = duel
	duels[b] = duel
	sendState(duel)
	task.delay(GameConfig.IntroTime, spawnRound, duel)
	return true
end

function DuelService.Start()
	CombatService.TargetResolver = function(c: Combatant): { Combatant }
		local duel = duels[c]
		if not duel or duel.State ~= "Live" then
			return {}
		end
		return { opponentOf(duel, c) }
	end

	CombatService.Killed:Connect(function(killer: Combatant, victim: Combatant, info)
		local duel = duels[killer]
		if not duel or duels[victim] ~= duel or duel.State ~= "Live" then
			return
		end
		duel.Kills[killer] += 1
		if info.Headshot then
			duel.Headshots[killer] += 1
		end
		duel.LastKill = { Headshot = info.Headshot, Distance = info.Distance }
		local victimChar = victim.Character
		for _, p in Players:GetPlayers() do
			local involved = p == killer or p == victim
			-- Los duelos contra bots solo se muestran a su jugador
			if involved or not duel.VsBot then
				Net.Event("KillFeed"):FireClient(p, {
					KillerName = killer.DisplayName,
					VictimName = victim.DisplayName,
					KillerIsMe = p == killer,
					VictimIsMe = p == victim,
					Involved = involved,
					Headshot = info.Headshot,
					Distance = info.Distance,
					WeaponId = info.WeaponId,
					VictimCharacter = victimChar,
				})
			end
		end
		roundOver(duel, killer, "kill")
	end)

	Players.PlayerRemoving:Connect(function(player)
		local duel = duels[player]
		if duel then
			duels[player] = nil
			local other = opponentOf(duel, player)
			if not duel.Finished then
				task.spawn(endDuel, duel, other, "forfeit")
			end
		end
	end)
end

return DuelService
