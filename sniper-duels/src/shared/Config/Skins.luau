--!strict
-- Skins del arma. Se aplican a las piezas "Body" del modelo.

export type Skin = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Color: Color3,
	Accent: Color3,
	Material: Enum.Material,
	Glow: boolean?,
	Crate: string, -- "Standard" | "Halloween"
	Pattern: string?, -- "camo" | "stripes" | "dots" | "flames" | nil (liso)
	Pattern2: Color3?, -- tercer color del dibujo
}

local Rarities = {
	{ Name = "Común", Weight = 55, Color = Color3.fromRGB(176, 190, 197) },
	{ Name = "Raro", Weight = 27, Color = Color3.fromRGB(66, 165, 245) },
	{ Name = "Épico", Weight = 13, Color = Color3.fromRGB(171, 71, 188) },
	{ Name = "Legendario", Weight = 4.5, Color = Color3.fromRGB(255, 179, 0) },
	{ Name = "Mítico", Weight = 0.5, Color = Color3.fromRGB(255, 61, 87) },
}

local function skin(id, name, rarity, color, accent, material, glow, crate): Skin
	return {
		Id = id,
		DisplayName = name,
		Rarity = rarity,
		Color = color,
		Accent = accent,
		Material = material,
		Glow = glow,
		Crate = crate or "Standard",
	}
end

local List: { [string]: Skin } = {
	Default = skin("Default", "Estándar", "Común", Color3.fromRGB(45, 45, 48), Color3.fromRGB(90, 90, 95), Enum.Material.Metal),
	Desert = skin("Desert", "Desierto", "Común", Color3.fromRGB(194, 164, 116), Color3.fromRGB(120, 98, 70), Enum.Material.Fabric),
	Woodland = skin("Woodland", "Bosque", "Común", Color3.fromRGB(74, 94, 58), Color3.fromRGB(46, 58, 36), Enum.Material.Fabric),
	Arctic = skin("Arctic", "Ártico", "Común", Color3.fromRGB(230, 235, 240), Color3.fromRGB(150, 160, 170), Enum.Material.SmoothPlastic),
	Cobalt = skin("Cobalt", "Cobalto", "Raro", Color3.fromRGB(30, 80, 200), Color3.fromRGB(15, 30, 80), Enum.Material.Metal),
	Crimson = skin("Crimson", "Carmesí", "Raro", Color3.fromRGB(170, 20, 35), Color3.fromRGB(40, 10, 10), Enum.Material.Metal),
	Carbon = skin("Carbon", "Fibra de carbono", "Raro", Color3.fromRGB(25, 25, 28), Color3.fromRGB(70, 70, 75), Enum.Material.CrackedLava),
	Toxic = skin("Toxic", "Tóxico", "Épico", Color3.fromRGB(110, 255, 60), Color3.fromRGB(20, 40, 20), Enum.Material.Neon, true),
	Abyss = skin("Abyss", "Abismo", "Épico", Color3.fromRGB(70, 0, 140), Color3.fromRGB(10, 0, 30), Enum.Material.Glass),
	Gold = skin("Gold", "Oro 24k", "Legendario", Color3.fromRGB(255, 196, 40), Color3.fromRGB(120, 80, 10), Enum.Material.Foil),
	Plasma = skin("Plasma", "Plasma", "Legendario", Color3.fromRGB(0, 230, 255), Color3.fromRGB(0, 40, 80), Enum.Material.ForceField, true),
	Inferno = skin("Inferno", "Infierno", "Mítico", Color3.fromRGB(255, 80, 0), Color3.fromRGB(60, 0, 0), Enum.Material.Neon, true),

	BlueCamo = skin("BlueCamo", "Camo azul", "Raro", Color3.fromRGB(40, 90, 200), Color3.fromRGB(15, 25, 60), Enum.Material.Fabric),
	GreenCamo = skin("GreenCamo", "Camo verde", "Raro", Color3.fromRGB(70, 110, 55), Color3.fromRGB(30, 45, 25), Enum.Material.Fabric),
	PinkCamo = skin("PinkCamo", "Camo rosa", "Épico", Color3.fromRGB(235, 90, 170), Color3.fromRGB(80, 20, 60), Enum.Material.Fabric),
	Glacial = skin("Glacial", "Glacial", "Épico", Color3.fromRGB(150, 210, 255), Color3.fromRGB(40, 60, 90), Enum.Material.Ice),
	Dynasty = skin("Dynasty", "Dinastía olvidada", "Legendario", Color3.fromRGB(225, 225, 230), Color3.fromRGB(210, 120, 20), Enum.Material.Marble),
	Festive = skin("Festive", "Festivo", "Legendario", Color3.fromRGB(190, 30, 40), Color3.fromRGB(30, 110, 50), Enum.Material.Fabric, true),

	-- Halloween (caja de caramelos)
	Pumpkin = skin("Pumpkin", "Calabaza", "Común", Color3.fromRGB(235, 120, 20), Color3.fromRGB(30, 20, 10), Enum.Material.SmoothPlastic, false, "Halloween"),
	Spiderweb = skin("Spiderweb", "Telaraña", "Común", Color3.fromRGB(20, 20, 24), Color3.fromRGB(200, 200, 210), Enum.Material.Fabric, false, "Halloween"),
	Bone = skin("Bone", "Hueso", "Raro", Color3.fromRGB(235, 228, 205), Color3.fromRGB(90, 80, 70), Enum.Material.Marble, false, "Halloween"),
	CandyCorn = skin("CandyCorn", "Maíz dulce", "Raro", Color3.fromRGB(255, 200, 40), Color3.fromRGB(255, 255, 240), Enum.Material.SmoothPlastic, false, "Halloween"),
	Witch = skin("Witch", "Bruja", "Épico", Color3.fromRGB(90, 30, 140), Color3.fromRGB(80, 255, 80), Enum.Material.Metal, true, "Halloween"),
	Vampire = skin("Vampire", "Vampiro", "Épico", Color3.fromRGB(120, 0, 15), Color3.fromRGB(15, 0, 0), Enum.Material.Glass, true, "Halloween"),
	Phantom = skin("Phantom", "Fantasma", "Legendario", Color3.fromRGB(200, 240, 255), Color3.fromRGB(120, 200, 255), Enum.Material.ForceField, true, "Halloween"),
	Headless = skin("Headless", "Jinete sin cabeza", "Mítico", Color3.fromRGB(255, 110, 0), Color3.fromRGB(10, 10, 10), Enum.Material.Neon, true, "Halloween"),
}

-- Dibujos: se pintan con piezas finas encima del cuerpo del arma
local PATTERNS: { [string]: { string | Color3 } } = {
	Woodland = { "camo", Color3.fromRGB(120, 95, 60) },
	Desert = { "camo", Color3.fromRGB(150, 120, 80) },
	Arctic = { "camo", Color3.fromRGB(120, 130, 140) },
	BlueCamo = { "camo", Color3.fromRGB(120, 180, 255) },
	GreenCamo = { "camo", Color3.fromRGB(140, 160, 90) },
	PinkCamo = { "camo", Color3.fromRGB(255, 190, 230) },
	Glacial = { "dots", Color3.fromRGB(30, 50, 80) },
	Carbon = { "stripes", Color3.fromRGB(55, 55, 60) },
	Crimson = { "stripes", Color3.fromRGB(240, 200, 90) },
	Cobalt = { "stripes", Color3.fromRGB(200, 220, 255) },
	Dynasty = { "flames", Color3.fromRGB(230, 140, 30) },
	Festive = { "stripes", Color3.fromRGB(255, 220, 90) },
	Pumpkin = { "stripes", Color3.fromRGB(30, 20, 10) },
	CandyCorn = { "stripes", Color3.fromRGB(255, 120, 20) },
	Spiderweb = { "dots", Color3.fromRGB(210, 210, 220) },
	Bone = { "dots", Color3.fromRGB(120, 110, 95) },
	Inferno = { "flames", Color3.fromRGB(255, 220, 60) },
	Headless = { "flames", Color3.fromRGB(255, 220, 60) },
	Witch = { "dots", Color3.fromRGB(120, 255, 90) },
	Gold = { "stripes", Color3.fromRGB(255, 240, 160) },
}
for id, pat in PATTERNS do
	local s = List[id]
	if s then
		s.Pattern = pat[1] :: string
		s.Pattern2 = pat[2] :: Color3
	end
end

local function rarityInfo(name: string)
	for _, r in Rarities do
		if r.Name == name then
			return r
		end
	end
	return Rarities[1]
end

local function roll(rng: Random, crate: string?): Skin
	crate = crate or "Standard"
	local total = 0
	for _, r in Rarities do
		total += r.Weight
	end
	local pick = rng:NextNumber() * total
	local rarity = Rarities[#Rarities].Name
	for _, r in Rarities do
		pick -= r.Weight
		if pick <= 0 then
			rarity = r.Name
			break
		end
	end
	local pool = {}
	for _, s in List do
		if s.Rarity == rarity and s.Id ~= "Default" and s.Crate == crate then
			table.insert(pool, s)
		end
	end
	if #pool == 0 then
		-- Rareza sin skins en esta caja: caer a cualquier skin de la caja
		for _, s in List do
			if s.Id ~= "Default" and s.Crate == crate then
				table.insert(pool, s)
			end
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

return {
	List = List,
	Rarities = Rarities,
	RarityInfo = rarityInfo,
	Roll = roll,
	Get = function(id: string): Skin
		return List[id] or List.Default
	end,
}
