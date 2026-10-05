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
	HitboxInflate = 1.22,
	ViewInterpolationDelay = 0.06, -- retraso aprox. con el que el cliente ve a los demás
	MaxBulletDistance = 2500,
	BallisticStep = 1 / 120,

	-- Arenas
	ArenaCount = 12, -- 2 por tema
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

	-- Administración. El creador del juego (o el dueño del grupo) siempre es
	-- admin. En Roblox Studio todos son admin para poder testear.
	-- Añade aquí UserIds de tus amigos/moderadores: [12345678] = "Mod"
	Admins = {} :: { [number]: string },
	StudioEveryoneAdmin = true,

	-- Recompensa diaria (racha de 7 días). "Crate" = caja + caramelos
	Daily = {
		Rewards = { 50, 50, 100, 50, 50, 50, "Crate" },
		CrateCandies = 200,
		MinHours = 20, -- horas entre reclamaciones
		MaxHours = 48, -- más de esto rompe la racha
	},

	-- Agacharse / deslizarse
	CrouchSpeedMultiplier = 0.5,
	CrouchHipDrop = 1.3,
	SlideSpeed = 40,
	SlideDuration = 0.85,

	-- Intercambios
	TradeConfirmTime = 4, -- s de cuenta atrás tras aceptar ambos (anti-estafa)
	TradeMaxItems = 8,

	-- Sonidos (rbxassetid://...). Vacío = desactivado. Los incluidos son de la
	-- librería pública de la Creator Store; cámbialos por los que quieras.
	Sounds = {
		Fire = "rbxassetid://9114726695",
		Bolt = "",
		Reload = "rbxassetid://138084889",
		Hitmarker = "rbxasset://sounds/electronicpingshort.wav",
		Headshot = "",
		ScopeIn = "",
		Countdown = "rbxasset://sounds/button.wav",
		RoundWin = "",
		RoundLose = "",
		Thunder = "rbxassetid://9126069842",
		Ambience = "rbxassetid://9112775175", -- Eerie Ambience 1 (SFX)
		GhostWhoosh = "rbxassetid://9120732173",
		Jumpscare = "rbxassetid://9125712561",
		Knife = "rbxassetid://9113081793", -- whoosh
		Slide = "",
		Daily = "rbxasset://sounds/electronicpingshort.wav",
	},
}

return GameConfig
