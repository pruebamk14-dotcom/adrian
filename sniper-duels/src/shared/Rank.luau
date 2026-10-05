--!strict
-- Rangos competitivos y curva de niveles.

local Rank = {}

Rank.Tiers = {
	{ Name = "Bronce", Min = 0, Color = Color3.fromRGB(176, 112, 64) },
	{ Name = "Plata", Min = 900, Color = Color3.fromRGB(190, 198, 206) },
	{ Name = "Oro", Min = 1100, Color = Color3.fromRGB(255, 200, 60) },
	{ Name = "Platino", Min = 1300, Color = Color3.fromRGB(80, 220, 200) },
	{ Name = "Diamante", Min = 1500, Color = Color3.fromRGB(110, 170, 255) },
	{ Name = "Maestro", Min = 1700, Color = Color3.fromRGB(200, 90, 255) },
	{ Name = "Élite", Min = 1900, Color = Color3.fromRGB(255, 70, 90) },
}

function Rank.FromElo(elo: number)
	local tier = Rank.Tiers[1]
	for _, t in Rank.Tiers do
		if elo >= t.Min then
			tier = t
		end
	end
	return tier
end

-- Devuelve (deltaA, deltaB) tras un duelo. scoreA = 1 si gana A.
function Rank.EloDelta(eloA: number, eloB: number, scoreA: number, kA: number, kB: number): (number, number)
	local expectedA = 1 / (1 + 10 ^ ((eloB - eloA) / 400))
	local dA = math.round(kA * (scoreA - expectedA))
	local dB = math.round(kB * ((1 - scoreA) - (1 - expectedA)))
	return dA, dB
end

function Rank.XPForLevel(level: number): number
	return math.floor(100 * level ^ 1.35)
end

return Rank
