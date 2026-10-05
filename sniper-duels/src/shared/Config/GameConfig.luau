--!strict
-- Ajustes globales del juego. Todo lo "tuneable" vive aquí.

local GameConfig = {
	-- Duelos
	RoundsToWin = 3, -- Mejor de 5
	IntroTime = 4,
	CountdownTime = 3,
	RoundEndTime = 3.5,
	RoundMaxTime = 75,
	RevealAfter = 35, -- a los 35 s ambos jugadores quedan resaltados (anti-camping)
	MaxHealth = 100,

	-- Lobby / pads
	PadRadius = 4,
	PadCountdown = 3,

	-- Matchmaking ranked
	BaseEloWindow = 100,
	EloWindowGrowthPerSecond = 25,

	-- ELO
	EloK = 32,
	EloKPlacement = 64,
	PlacementMatches = 5,
	StartingElo = 1000,

	-- Recompensas
	Rewards = {
		KillCoins = 10,
		HeadshotBonusCoins = 5,
		WinCoins = 60,
		LossCoins = 15,
		KillXP = 25,
		WinXP = 120,
		LossXP = 40,
		RankedMultiplier = 1.5,
	},

	-- Red / anti-cheat
	MaxRewindTime = 0.45, -- segundos máximos de lag compensation
	HistoryLength = 1.0,
	MaxOriginDistance = 10, -- distancia máxima entre cabeza y origen del disparo
	HitboxInflate = 1.08,
	ViewInterpolationDelay = 0.06, -- retraso aprox. con el que el cliente ve a los demás
	MaxBulletDistance = 2500,
	BallisticStep = 1 / 120,

	-- Arenas
	ArenaCount = 8,
	ArenaSpacing = 600,
	ArenaOrigin = Vector3.new(0, 0, 2000),

	-- Crates
	CratePrice = 300,
	DuplicateRefund = 0.4,

	-- Sonidos (rbxassetid://...). Vacío = desactivado. Pon tus propios IDs.
	Sounds = {
		Fire = "",
		Bolt = "",
		Reload = "",
		Hitmarker = "",
		Headshot = "",
		ScopeIn = "",
		Countdown = "",
		RoundWin = "",
		RoundLose = "",
	},
}

return GameConfig
