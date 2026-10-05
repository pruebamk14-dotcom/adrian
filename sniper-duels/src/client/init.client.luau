--!strict
-- Punto de entrada del cliente.

local Controllers = script.Controllers

local EffectsController = require(Controllers.EffectsController)
local WeaponController = require(Controllers.WeaponController)
local HUDController = require(Controllers.HUDController)
local MenuController = require(Controllers.MenuController)
local AmbientController = require(Controllers.AmbientController)

EffectsController.Start()
WeaponController.Start()
HUDController.Start()
MenuController.Start()
AmbientController.Start()
