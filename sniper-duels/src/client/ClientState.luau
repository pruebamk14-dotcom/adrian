--!strict
-- Estado compartido entre controladores del cliente.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local ClientState = {
	Data = nil :: any, -- datos públicos del jugador (DataUpdate)
	Duel = nil :: any, -- último DuelState recibido (nil en lobby)
	Armed = false,
	WeaponId = "",
	Mag = 0,
	Reloading = false,
	InQueue = false,
	Scoped = false,
	Slot = 1, -- 1 rifle, 2 cuchillo
	Crouched = false,
	MenuOpen = false, -- menú de pausa abierto: bloquea disparo y movimiento
	ScopeProgress = 0,
	Breath = 1, -- 0..1, aguantar respiración

	DataChanged = Signal.new(),
	DuelChanged = Signal.new(),
	AmmoChanged = Signal.new(),
	QueueChanged = Signal.new(),
}

function ClientState.CanShoot(): boolean
	return ClientState.Armed and ClientState.Duel ~= nil and ClientState.Duel.State == "Live"
end

return ClientState
