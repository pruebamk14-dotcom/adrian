--!strict
-- Ajustes globales del juego. Todo lo "tuneable" vive aquí.

local GameConfig = {
	-- Evento de temporada: arenas, lobby, skins y caramelos de Halloween
	HalloweenEvent = true,

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
		BotMultiplier = 0.5, -- duelos contra bot dan la mitad
		KillCandy = 5,
		WinCandy = 15,
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
	HalloweenCratePrice = 120, -- en caramelos
	DuplicateRefund = 0.4,

	-- Recompensa al subir de nivel: monedas = LevelUpCoinsBase + nivel * LevelUpCoinsPerLevel
	LevelUpCoinsBase = 100,
	LevelUpCoinsPerLevel = 25,

	-- Monetización. Crea los productos en create.roblox.com
	-- (tu experiencia -> Monetización -> Pases / Productos para desarrolladores)
	-- y pega aquí sus IDs. Con 0 el botón aparece como "no disponible".
	Monetization = {
		GamePasses = {
			VIP = 0, -- x2 monedas, x2 caramelos, etiqueta VIP dorada
		},
		Products = {
			Coins1000 = 0,
			Coins5000 = 0,
			Coins15000 = 0,
			Candy500 = 0,
			WeaponReaper = 0,
			WeaponObsidian = 0,
		},
		-- Precios orientativos para mostrar en la tienda (el real lo pone Roblox)
		RobuxPrices = {
			VIP = 399,
			Coins1000 = 49,
			Coins5000 = 199,
			Coins15000 = 499,
			Candy500 = 99,
			WeaponReaper = 299,
			WeaponObsidian = 449,
		},
		CoinPacks = {
			Coins1000 = 1000,
			Coins5000 = 5500, -- +10% bonus
			Coins15000 = 18000, -- +20% bonus
		},
		CandyPacks = {
			Candy500 = 500,
		},
		VIPMultiplier = 2,
	},

	-- Intercambios
	TradeConfirmTime = 4, -- s de cuenta atrás tras aceptar ambos (anti-estafa)
	TradeMaxItems = 8,

	-- Sonidos (rbxassetid://...). Vacío = desactivado. Pon tus propios IDs.
	Sounds = {
		Fire = "",
		Bolt = "",
		Reload = "",
		Hitmarker = "rbxasset://sounds/electronicpingshort.wav",
		Headshot = "",
		ScopeIn = "",
		Countdown = "rbxasset://sounds/button.wav",
		RoundWin = "",
		RoundLose = "",
		Thunder = "",
	},
}

return GameConfig
