--!strict
-- Ciclo de vida de un duelo por equipos (1v1, 2v2 o contra bot):
-- intro -> cuenta atrás -> ronda -> fin de ronda ... -> fin del duelo
-- (recompensas, ELO en ranked 1v1, rachas) -> vuelta al lobby.

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
	Teams: { A: { Combatant }, B: { Combatant } },
	TeamOf: { [Combatant]: string },
	Players: { Combatant },
	Arena: ArenaService.Arena,
	Scores: { A: number, B: number },
	Kills: { [Combatant]: number },
	Headshots: { [Combatant]: number },
	Alive: { [Combatant]: boolean },
	Round: number,
	State: string,
	Mode: string, -- "1v1" | "2v2" | "BOT"
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

local function otherTeam(team: string): string
	return if team == "A" then "B" else "A"
end

local function enemiesOf(duel: Duel, c: Combatant): { Combatant }
	return duel.Teams[otherTeam(duel.TeamOf[c])]
end

local function alliesOf(duel: Duel, c: Combatant): { Combatant }
	local out = {}
	for _, m in duel.Teams[duel.TeamOf[c]] do
		if m ~= c then
			table.insert(out, m)
		end
	end
	return out
end

local function names(list: { Combatant }): string
	local out = {}
	for _, c in list do
		table.insert(out, c.DisplayName)
	end
	return table.concat(out, " & ")
end

local function eloOf(c: Combatant): number
	if isPlayer(c) then
		return (c:GetAttribute("Elo") :: number?) or GameConfig.StartingElo
	end
	return c.Elo or GameConfig.StartingElo
end

local function teamAlive(duel: Duel, team: string): number
	local n = 0
	for _, c in duel.Teams[team] do
		if duel.Alive[c] then
			n += 1
		end
	end
	return n
end

local function sendState(duel: Duel, extra: { [string]: any }?)
	for _, p in duel.Players do
		if isPlayer(p) and p.Parent then
			local team = duel.TeamOf[p]
			local enemies = enemiesOf(duel, p)
			local payload: { [string]: any } = {
				State = duel.State,
				Round = duel.Round,
				RoundsToWin = GameConfig.RoundsToWin,
				MyScore = duel.Scores[team],
				OppScore = duel.Scores[otherTeam(team)],
				OpponentName = names(enemies),
				AllyNames = names(alliesOf(duel, p)),
				OpponentElo = if #enemies == 1 then eloOf(enemies[1]) else nil,
				OpponentIsBot = #enemies == 1 and not isPlayer(enemies[1]),
				Arena = duel.Arena.Name,
				Mode = duel.Mode,
				Ranked = duel.Ranked,
				VsBot = duel.VsBot,
				EndsAt = duel.RoundEndsAt,
				AlliesAlive = teamAlive(duel, team),
				EnemiesAlive = teamAlive(duel, otherTeam(team)),
			}
			if extra then
				for k, v in extra do
					if k ~= "PerPlayer" and k ~= "RoundWinner" and k ~= "Winner" then
						payload[k] = v
					end
				end
				if extra.RoundWinner ~= nil or extra.Reason == "draw" then
					payload.RoundWon = extra.RoundWinner == team
					payload.IsDraw = extra.RoundWinner == nil
				end
				if extra.Winner ~= nil then
					payload.Won = extra.Winner == team
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

local roundOver: (duel: Duel, winner: string?, reason: string) -> ()
local endDuel: (duel: Duel, winner: string, reason: string) -> ()

local duelKeyCounter = 0

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
	if char then
		-- El cliente usa esto para la barra de vida del rival
		-- "<duelo>:<equipo>" para no mezclar con otros duelos del servidor
		if not (duel :: any).Key then
			duelKeyCounter += 1
			;(duel :: any).Key = tostring(duelKeyCounter)
		end
		char:SetAttribute("SD_Team", (duel :: any).Key .. ":" .. duel.TeamOf[c])
	end
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
	for _, c in duel.Players do
		duel.Alive[c] = true
	end

	-- Cargar todos los personajes en paralelo; los compañeros aparecen en fila
	local pending = 0
	for _, team in { "A", "B" } do
		local base = if team == "A" then duel.Arena.SpawnA else duel.Arena.SpawnB
		local members = duel.Teams[team]
		for i, c in members do
			pending += 1
			local cf = base * CFrame.new((i - (#members + 1) / 2) * 5, 0, 0)
			task.spawn(function()
				if present(c) then
					local ok, err = pcall(spawnCombatant, duel, c, cf)
					if not ok then
						warn("[Duel] spawn:", err)
						if isPlayer(c) then
							Net.Event("Notify"):FireClient(c, "ERROR al preparar el arma: " .. tostring(err), Color3.fromRGB(255, 80, 80))
						end
					end
				else
					duel.Alive[c] = false
				end
				pending -= 1
			end)
		end
	end
	local waitStart = os.clock()
	while pending > 0 and os.clock() - waitStart < 10 do
		task.wait()
	end
	if duel.Finished or duel.RoundToken ~= token then
		return
	end

	-- Muerte por cualquier causa (caída, reset...) cuenta como baja
	for _, c in duel.Players do
		local hum = c.Character and c.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(
				duel.Connections,
				hum.Died:Connect(function()
					duel.Alive[c] = false
					task.delay(0.15, function()
						if duel.RoundToken == token and duel.State == "Live" and teamAlive(duel, duel.TeamOf[c]) == 0 then
							roundOver(duel, otherTeam(duel.TeamOf[c]), "death")
						elseif duel.RoundToken == token and duel.State == "Live" then
							sendState(duel)
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

	-- Límite de tiempo: gana el equipo con más vida total
	task.delay(GameConfig.RoundMaxTime, function()
		if duel.RoundToken ~= token or duel.State ~= "Live" then
			return
		end
		local function hp(team: string): number
			local total = 0
			for _, c in duel.Teams[team] do
				local h = c.Character and c.Character:FindFirstChildOfClass("Humanoid")
				total += if h and duel.Alive[c] then h.Health else 0
			end
			return total
		end
		local a, b = hp("A"), hp("B")
		if a > b then
			roundOver(duel, "A", "time")
		elseif b > a then
			roundOver(duel, "B", "time")
		else
			roundOver(duel, nil, "draw")
		end
	end)
end

roundOver = function(duel: Duel, winner: string?, reason: string)
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

endDuel = function(duel: Duel, winner: string, reason: string)
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
	local loserTeam = otherTeam(winner)
	local R = GameConfig.Rewards
	local mult = if duel.Ranked then R.RankedMultiplier elseif duel.VsBot then R.BotMultiplier else 1

	local perPlayer = {}

	-- ELO solo en ranked 1v1
	local eloW, eloL = 0, 0
	local wp = duel.Teams[winner][1]
	local lp = duel.Teams[loserTeam][1]
	local wd = if wp and isPlayer(wp) then DataService.Get(wp) else nil
	local ld = if lp and isPlayer(lp) then DataService.Get(lp) else nil
	if duel.Ranked and wd and lp then
		local loserElo = if ld then ld.Elo else eloOf(lp)
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
		local won = duel.TeamOf[p] == winner
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
				string.format("%s venció a %s (%d-%d)%s", names(duel.Teams[winner]), names(duel.Teams[loserTeam]), duel.Scores[winner], duel.Scores[loserTeam], if duel.Ranked then " · Ranked" elseif duel.Mode == "2v2" then " · 2v2" else ""),
				Color3.fromRGB(200, 200, 200)
			)
		end
	end

	task.wait(5)
	for _, c in duel.Players do
		if duels[c] == duel then
			duels[c] = nil
		end
		task.spawn(returnToLobby, c)
	end
	ArenaService.Release(duel.Arena)
end

-- Un jugador abandona (menú o desconexión)
local function leave(player: Player, byMenu: boolean)
	local duel = duels[player]
	if not duel then
		return
	end
	duels[player] = nil
	if duel.Finished then
		return
	end
	local team = duel.TeamOf[player]
	duel.Alive[player] = false
	local members = duel.Teams[team]
	local i = table.find(members, player)
	if i then
		table.remove(members, i)
	end
	local idx = table.find(duel.Players, player)
	if idx then
		table.remove(duel.Players, idx)
	end
	-- El que abandona recibe su "fin de duelo" (derrota) y pierde la racha
	if isPlayer(player) and player.Parent then
		local d = DataService.Get(player)
		if d then
			d.Losses += 1
			if not duel.VsBot then
				d.WinStreak = 0
			end
			DataService.Push(player)
		end
		Net.Event("DuelState"):FireClient(player, {
			State = "Ended",
			Won = false,
			Reason = "forfeit",
			Round = duel.Round,
			RoundsToWin = GameConfig.RoundsToWin,
			MyScore = duel.Scores[team],
			OppScore = duel.Scores[otherTeam(team)],
			OpponentName = names(duel.Teams[otherTeam(team)]),
			AllyNames = names(members),
			Mode = duel.Mode,
			Ranked = duel.Ranked,
			VsBot = duel.VsBot,
			Coins = 0,
			XP = 0,
			Candies = 0,
		})
	end
	if byMenu then
		task.spawn(returnToLobby, player)
	end
	if #members == 0 then
		task.spawn(endDuel, duel, otherTeam(team), "forfeit")
	elseif duel.State == "Live" and teamAlive(duel, team) == 0 then
		task.spawn(roundOver, duel, otherTeam(team), "death")
	else
		sendState(duel)
	end
end

function DuelService.Forfeit(player: Player)
	leave(player, true)
end

function DuelService.IsBusy(c: Combatant): boolean
	return duels[c] ~= nil
end

function DuelService.StartTeams(teamA: { Combatant }, teamB: { Combatant }, ranked: boolean): boolean
	local all = {}
	for _, c in teamA do
		table.insert(all, c)
	end
	for _, c in teamB do
		table.insert(all, c)
	end
	if #teamA == 0 or #teamB == 0 then
		return false
	end
	for _, c in all do
		if duels[c] or not present(c) then
			return false
		end
	end
	local arena = ArenaService.Acquire()
	if not arena then
		return false
	end
	nextId += 1
	local vsBot = false
	local teamOf = {}
	for _, c in teamA do
		teamOf[c] = "A"
		vsBot = vsBot or not isPlayer(c)
	end
	for _, c in teamB do
		teamOf[c] = "B"
		vsBot = vsBot or not isPlayer(c)
	end
	local mode = if vsBot then "BOT" elseif #teamA == 1 and #teamB == 1 then "1v1" else string.format("%dv%d", #teamA, #teamB)
	local duel: Duel = {
		Id = nextId,
		Teams = { A = table.clone(teamA), B = table.clone(teamB) },
		TeamOf = teamOf,
		Players = all,
		Arena = arena,
		Scores = { A = 0, B = 0 },
		Kills = {},
		Headshots = {},
		Alive = {},
		Round = 0,
		State = "Intro",
		Mode = mode,
		Ranked = ranked and mode == "1v1",
		VsBot = vsBot,
		RoundToken = 0,
		RoundEndsAt = workspace:GetServerTimeNow() + GameConfig.IntroTime,
		LastKill = nil,
		Connections = {},
		Finished = false,
	}
	for _, c in all do
		duel.Kills[c] = 0
		duel.Headshots[c] = 0
		duel.Alive[c] = true
		duels[c] = duel
	end
	sendState(duel)
	task.delay(GameConfig.IntroTime, spawnRound, duel)
	return true
end

function DuelService.StartDuel(a: Combatant, b: Combatant, ranked: boolean): boolean
	if a == b then
		return false
	end
	return DuelService.StartTeams({ a }, { b }, ranked)
end

function DuelService.Start()
	CombatService.TargetResolver = function(c: Combatant): { Combatant }
		local duel = duels[c]
		if not duel or duel.State ~= "Live" then
			return {}
		end
		local out = {}
		for _, e in enemiesOf(duel, c) do
			if duel.Alive[e] and e.Character then
				table.insert(out, e)
			end
		end
		return out
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
		duel.Alive[victim] = false
		duel.LastKill = { Headshot = info.Headshot, Distance = info.Distance }
		local victimChar = victim.Character
		for _, p in Players:GetPlayers() do
			local involved = duels[p] == duel
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
		if teamAlive(duel, duel.TeamOf[victim]) == 0 then
			roundOver(duel, duel.TeamOf[killer], "kill")
		else
			sendState(duel)
		end
	end)

	Net.Event("LeaveDuel").OnServerEvent:Connect(function(player)
		leave(player, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		leave(player, false)
	end)
end

return DuelService
