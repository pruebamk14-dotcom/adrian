--!strict
-- Punto de entrada del servidor. Arranca los servicios en orden y gestiona
-- la aparición de personajes fuera de los duelos (CharacterAutoLoads = false).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared").Net) -- crea los Remotes

local Services = script.Services
local DataService = require(Services.DataService)
local ArenaService = require(Services.ArenaService)
local HitboxHistory = require(Services.HitboxHistory)
local CombatService = require(Services.CombatService)
local DuelService = require(Services.DuelService)
local MatchmakingService = require(Services.MatchmakingService)
local ShopService = require(Services.ShopService)
local LeaderboardService = require(Services.LeaderboardService)
local BotService = require(Services.BotService)
local MonetizationService = require(Services.MonetizationService)
local TradeService = require(Services.TradeService)

Players.CharacterAutoLoads = false
Players.RespawnTime = 2

ArenaService.Start()
HitboxHistory.Start()
CombatService.Start()
DuelService.Start()
BotService.Start()
MatchmakingService.Start()
ShopService.Start()
LeaderboardService.Start()
MonetizationService.Start()
TradeService.Start()
DataService.Start()

-- Personajes del lobby: reaparecer al morir si no está en un duelo
local function hookCharacter(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.Died:Connect(function()
		task.wait(Players.RespawnTime)
		if player.Parent and player.Character == character and not DuelService.IsBusy(player) then
			player:LoadCharacter()
		end
	end)
	-- Seguridad: caída al vacío
	task.spawn(function()
		while character.Parent and hum.Health > 0 do
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < -60 then
				hum.Health = 0
			end
			task.wait(0.5)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)
	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

DataService.Loaded:Connect(function(player: Player)
	if player.Parent and not player.Character then
		player:LoadCharacter()
	end
end)
