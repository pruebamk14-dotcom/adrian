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
}

local Rarities = {
	{ Name = "Común", Weight = 55, Color = Color3.fromRGB(176, 190, 197) },
	{ Name = "Raro", Weight = 27, Color = Color3.fromRGB(66, 165, 245) },
	{ Name = "Épico", Weight = 13, Color = Color3.fromRGB(171, 71, 188) },
	{ Name = "Legendario", Weight = 4.5, Color = Color3.fromRGB(255, 179, 0) },
	{ Name = "Mítico", Weight = 0.5, Color = Color3.fromRGB(255, 61, 87) },
}

local function skin(id, name, rarity, color, accent, material, glow): Skin
	return {
		Id = id,
		DisplayName = name,
		Rarity = rarity,
		Color = color,
		Accent = accent,
		Material = material,
		Glow = glow,
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
}

local function rarityInfo(name: string)
	for _, r in Rarities do
		if r.Name == name then
			return r
		end
	end
	return Rarities[1]
end

local function roll(rng: Random): Skin
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
		if s.Rarity == rarity and s.Id ~= "Default" then
			table.insert(pool, s)
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
