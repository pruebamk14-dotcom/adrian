--!strict
-- Crea (servidor) o encuentra (cliente) todos los RemoteEvents / RemoteFunctions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Fire", -- C->S: origin, direction, shotTime
	"Melee", -- C->S: cuchillada
	"SetSlot", -- C->S: 1 rifle / 2 cuchillo
	"LeaveDuel", -- C->S: abandonar el duelo actual
	"Armed", -- S->C: weaponId, mag, reloading (redundante con los atributos)
	"ServerLog", -- S->C (admins): errores del servidor
	"Reload", -- C->S
	"ScopeState", -- C->S: bool (para velocidad de movimiento)
	"ShotFx", -- S->C: shooterCharacter, origin, direction, weaponId, skinId
	"HitConfirm", -- S->C: zone, damage, killed, distance
	"ShotResult", -- S->C: texto de diagnóstico del disparo
	"OpenBotMenu", -- S->C: el jugador se subió al pad de BOT
	"Damaged", -- S->C: fromPosition, damage, health
	"DuelState", -- S->C: tabla de estado del duelo
	"KillFeed", -- S->C: info { KillerName, VictimName, KillerIsMe, VictimIsMe, Headshot, Distance, WeaponId, VictimCharacter }
	"Notify", -- S->C: texto, color?
	"DataUpdate", -- S->C: datos públicos del jugador
	"QueueRanked", -- C->S
	"QueueCasual", -- C->S: partida rápida (cualquier rival, o bot si no hay)
	"PlayBot", -- C->S: dificultad
	"PromptPurchase", -- C->S: clave de producto / "VIP"
	"Trade", -- C->S: acción, ...
	"TradeUpdate", -- S->C: estado del intercambio
	"Announce", -- S->C: anuncio global de un admin
	"LeaveQueue", -- C->S
	"QueueState", -- S->C: inQueue, seconds
	"CrateOpened", -- S->C: skinId, duplicate, refund
}

local FUNCTIONS = {
	"GetData",
	"BuyCrate",
	"EquipSkin",
	"EquipWeapon",
	"GetLeaderboard",
	"UpdateSettings",
	"BuyWeapon",
	"Gift",
	"AdminCommand",
	"ClaimDaily",
	"GetArmState",
}

local Net = {}
local folder: Folder

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
	end
	for _, name in FUNCTIONS do
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
