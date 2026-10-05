--!strict
-- Punto de entrada del cliente.

local StarterGui = game:GetService("StarterGui")

local Controllers = script.Controllers

-- Sin mochila: el rifle lo gestiona el juego, no el jugador
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

local EffectsController = require(Controllers.EffectsController)
local WeaponController = require(Controllers.WeaponController)
local HUDController = require(Controllers.HUDController)
local MenuController = require(Controllers.MenuController)
local AmbientController = require(Controllers.AmbientController)

-- Arrancar cada controlador por separado: si uno falla, los demás siguen
-- y el error aparece claro en Output / consola (F9)
for _, entry in {
	{ "Effects", EffectsController },
	{ "Weapon", WeaponController },
	{ "HUD", HUDController },
	{ "Menu", MenuController },
	{ "Ambient", AmbientController },
} do
	local ok, err = xpcall(entry[2].Start, debug.traceback)
	if not ok then
		warn("[SniperDuels] Error al iniciar " .. entry[1] .. ":\n" .. tostring(err))
	end
end
