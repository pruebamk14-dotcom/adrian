--!nocheck
-- Ejecuta el juego entero en el simulador y comprueba los flujos principales.
-- Uso:  rojo build -o build/sim.rbxl && lune run tools/sim/run.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local M = require("./rbxmock")

local Enum, Vector3 = roblox.Enum, roblox.Vector3
local CFrame = M.CFrame
M.Verbose = process.args[1] == "-v"

local checks, failed = 0, 0
local function check(name: string, cond: boolean, detail: string?)
	checks += 1
	if cond then
		print("\27[32m[OK]\27[0m " .. name)
	else
		failed += 1
		print("\27[31m[FALLO]\27[0m " .. name .. (if detail then "  (" .. detail .. ")" else ""))
	end
end
local function section(name: string)
	print("\n\27[36m== " .. name .. " ==\27[0m")
end

-- Cargar el place generado por Rojo dentro del DataModel del simulador
local place = roblox.deserializePlace(fs.readFile("build/sim.rbxl"))
for _, svc in place:GetChildren() do
	local mine = M.Game:GetService(svc.ClassName)
	for _, child in svc:GetChildren() do
		child.Parent = mine
	end
	-- Copiar propiedades sencillas (Lighting, etc.)
	if svc.ClassName == "Lighting" then
		mine.ClockTime = svc.ClockTime
	end
end
local game = M.GameProxy -- el runner usa los mismos proxies que el juego
local workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local function main()
-- SERVIDOR --------------------------------------------------------------------
section("Arranque del servidor")
local serverScript = M.Unwrap(game:GetService("ServerScriptService"):FindFirstChild("Server"))
check("existe ServerScriptService.Server", serverScript ~= nil)
local errorsBefore = #M.Errors
M.RunScript(serverScript, "server")
M.Run(1.5)
check("servidor arranca sin errores", #M.Errors == errorsBefore)
local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
check("remotes creados", remotes ~= nil and remotes:FindFirstChild("Fire") ~= nil)
check("lobby generado", workspace:FindFirstChild("Lobby") ~= nil)
check("arenas generadas", workspace:FindFirstChild("Arenas") ~= nil and #workspace.Arenas:GetChildren() > 0)

-- JUGADOR ---------------------------------------------------------------------
section("Entra un jugador")
errorsBefore = #M.Errors
local p1 = M.Wrap(M.AddPlayer("Tester", 1))
M.Run(1.5)
check("datos cargados (leaderstats)", p1:FindFirstChild("leaderstats") ~= nil)
check("personaje cargado en el lobby", p1.Character ~= nil and p1.Character.Parent == workspace)
check("rango admin en Studio", p1:GetAttribute("SD_Rank") == "Owner", tostring(p1:GetAttribute("SD_Rank")))
check("sin errores al entrar", #M.Errors == errorsBefore)

-- CLIENTE ---------------------------------------------------------------------
section("Arranque del cliente")
local clientScript = M.Unwrap(game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"))
check("existe StarterPlayerScripts.Client", clientScript ~= nil)
M.LocalPlayer = p1
M.ClientRunning = true
errorsBefore = #M.Errors
M.RunScript(clientScript, "client")
M.Run(1.5)
check("cliente arranca sin errores", #M.Errors == errorsBefore)
local pg = p1:FindFirstChild("PlayerGui")
check("HUD creado", pg:FindFirstChild("HUD") ~= nil)
check("Menú creado", pg:FindFirstChild("Menu") ~= nil)

-- Escuchar DuelState
local duelStates = {}
M.GetSignal(M.Unwrap(remotes.DuelState), "OnClientEvent"):Connect(function(state)
	table.insert(duelStates, state)
end)
local notifies = {}
M.GetSignal(M.Unwrap(remotes.Notify), "OnClientEvent"):Connect(function(text)
	table.insert(notifies, text)
end)

-- Pulsar todos los botones del menú para que se construyan los paneles
section("Menú del lobby: pulsar todos los botones")
errorsBefore = #M.Errors
local function clickAll(root, filter)
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("TextButton") and (not filter or filter(d)) then
			n += 1
			M.GetSignal(M.Unwrap(d), "MouseButton1Click"):Fire()
			task.wait(0.05)
		end
	end
	return n
end
local dock = pg.Menu:FindFirstChild("Dock")
check("dock con botones", dock ~= nil and #dock:GetChildren() > 3)
local clicked = clickAll(dock, function(b)
	return b.Text ~= "⚔ RANKED"
end)
M.Run(0.5)
check("botones del dock pulsados sin errores (" .. clicked .. ")", #M.Errors == errorsBefore)
check("tienda creada", pg.Menu:FindFirstChild("Shop") ~= nil)
check("panel admin visible para admin", pg.Menu:FindFirstChild("Admin") ~= nil)

-- ADMIN -------------------------------------------------------------------------
section("Comandos de admin")
local AdminCommand = remotes:FindFirstChild("AdminCommand")
local GetData = remotes:FindFirstChild("GetData")
local function data()
	return GetData:InvokeServer()
end
local coinsBefore = data().Coins
local res = AdminCommand:InvokeServer(":coins me 5000")
check(":coins me 5000 -> " .. tostring(res), data().Coins == coinsBefore + 5000, tostring(data().Coins))
res = AdminCommand:InvokeServer(":candies me 500")
check(":candies me 500 -> " .. tostring(res), data().Candies >= 500)
res = AdminCommand:InvokeServer(":skins me")
check(":skins me -> " .. tostring(res), data().Inventory.Skins.Inferno == true)
res = AdminCommand:InvokeServer(":weapons me")
check(":weapons me -> " .. tostring(res), data().Inventory.Weapons.Reaper == true and data().Level >= 20)
res = AdminCommand:InvokeServer(":level me 30")
check(":level me 30 -> " .. tostring(res), data().Level == 30)

section("Tienda: equipar y cajas")
check("EquipSkin Inferno", remotes.EquipSkin:InvokeServer("Inferno") == true)
check("skin equipada en datos", data().Equipped.Skin == "Inferno")
check("EquipWeapon Leviathan", remotes.EquipWeapon:InvokeServer("Leviathan") == true)
check("EquipWeapon Reaper (exclusiva)", remotes.EquipWeapon:InvokeServer("Reaper") == true)
local crate = remotes.BuyCrate:InvokeServer("Standard")
check("caja estándar se abre", crate ~= nil and crate.Ok == true, crate and (crate.Error or crate.SkinId))
task.wait(1.2)
crate = remotes.BuyCrate:InvokeServer("Halloween")
check("caja Halloween se abre", crate ~= nil and crate.Ok == true, crate and (crate.Error or crate.SkinId))
local buy = remotes.BuyWeapon:InvokeServer("Valkyrie")
check("comprar Valkyrie con monedas", buy ~= nil and (buy.Ok == true or buy.Error == "Ya la tienes"), buy and buy.Error)
-- Pulsar todo dentro de la tienda (pestañas, comprar, abrir caja)
errorsBefore = #M.Errors
local shopClicks = clickAll(pg.Menu.Shop)
M.Run(0.3)
check("tienda: " .. shopClicks .. " botones pulsados sin errores", #M.Errors == errorsBefore)
errorsBefore = #M.Errors
M.Run(0.2)
clickAll(pg.Menu:FindFirstChild("Arsenal") or pg.Menu)
M.Run(0.3)
check("arsenal: botones sin errores", #M.Errors == errorsBefore)

-- DUELO CONTRA BOT ----------------------------------------------------------------
section("Duelo contra bot")
errorsBefore = #M.Errors
remotes.PlayBot:FireServer("Practica") -- el bot de práctica no dispara: prueba determinista
M.Run(1)
check("DuelState Intro recibido", #duelStates > 0 and duelStates[1].State == "Intro", duelStates[1] and duelStates[1].State)
M.Run(8.5) -- intro 4 + cuenta atrás 3
local last = duelStates[#duelStates]
check("ronda en Live", last and last.State == "Live", last and last.State)
local bot = nil
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and string.find(m.Name, "Calabaza") then
		bot = m
	end
end
check("bot creado en el mundo", bot ~= nil)
check("jugador armado (atributo SD_Weapon)", p1:GetAttribute("SD_Weapon") ~= nil and p1:GetAttribute("SD_Weapon") ~= "", tostring(p1:GetAttribute("SD_Weapon")))
check("rifle en la mano (Tool)", p1.Character ~= nil and p1.Character:FindFirstChild("Rifle") ~= nil)
check("cámara en primera persona", p1.CameraMode == Enum.CameraMode.LockFirstPerson, tostring(p1.CameraMode))
check("acciones de disparo vinculadas", M.Actions.SD_Fire ~= nil and M.Actions.SD_Scope ~= nil)
check("viewmodel creado", workspace.CurrentCamera:FindFirstChild("Viewmodel") ~= nil)
local hud = pg.HUD
check("HUD munición visible", hud:FindFirstChild("Ammo") ~= nil and hud.Ammo.Visible == true)
check("crosshair visible", hud:FindFirstChild("Crosshair") ~= nil and hud.Crosshair.Visible == true)
check("sin errores hasta ahora en el duelo", #M.Errors == errorsBefore)

-- Apuntar al bot y disparar
section("Disparar al bot")
errorsBefore = #M.Errors
local myHead = p1.Character:FindFirstChild("Head")
local botHead = bot and bot:FindFirstChild("Head")
check("cabezas encontradas", myHead ~= nil and botHead ~= nil)
-- Sacar al jugador del búnker y colocar al bot a la vista (sin cobertura en medio)
local botTorso = bot and (bot:FindFirstChild("UpperTorso") or bot:FindFirstChild("Torso"))
if bot and myHead and botTorso then
	local myRoot = p1.Character.HumanoidRootPart
	myRoot.Anchored = true
	local params = M.RaycastParams.new()
	params.FilterDescendantsInstances = { p1.Character, bot }
	local placed = false
	local base = myRoot.CFrame
	for _, pair in {
		{ Vector3.new(30, 0, -45), Vector3.new(30, 0, -150) },
		{ Vector3.new(-30, 0, -45), Vector3.new(-30, 0, -150) },
		{ Vector3.new(45, 0, -60), Vector3.new(45, 0, -140) },
		{ Vector3.new(-45, 0, -60), Vector3.new(-45, 0, -140) },
		{ Vector3.new(0, 0, -50), Vector3.new(0, 0, -110) },
		{ Vector3.new(20, 0, -70), Vector3.new(20, 0, -100) },
	} do
		p1.Character:PivotTo(base * CFrame.new(pair[1]))
		bot.HumanoidRootPart.Anchored = false
		bot:PivotTo(base * CFrame.new(pair[2]))
		bot.HumanoidRootPart.Anchored = true
		local hit = workspace:Raycast(myHead.Position, botTorso.Position - myHead.Position, params)
		if not hit then
			placed = true
			break
		end
	end
	check("bot colocado con línea de visión libre", placed)
	M.Run(0.3) -- que HitboxHistory capture la nueva posición
	local Weapons = M.Require.server(game:GetService("ReplicatedStorage").Shared.Config.Weapons)
	local w = Weapons.Get(p1:GetAttribute("SD_Weapon"))
	local dist = (botTorso.Position - myHead.Position).Magnitude
	local t = dist / w.MuzzleVelocity
	local aim = botTorso.Position + Vector3.new(0, 0.5 * w.BulletGravity * t * t, 0)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(myHead.Position, aim)
	print(string.format("distancia al bot: %.0f studs (arma %s)", dist, w.Id))
end
local scopeCalls = {}
M.GetSignal(M.Unwrap(remotes.ScopeState), "OnServerEvent"):Connect(function(pl, v)
	table.insert(scopeCalls, tostring(v))
end)
local ClientState = M.Require.client(M.Unwrap(clientScript):FindFirstChild("ClientState"))
M.FireAction("SD_Scope", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton2)
M.MouseButtons[Enum.UserInputType.MouseButton2] = true
for i = 1, 18 do
	M.Run(1 / 30)
	if M.Verbose or i % 6 == 0 then
		print(string.format("  frame %d: Armed=%s Scoped=%s progreso=%.2f Reloading=%s Mag=%s", i, tostring(ClientState.Armed), tostring(ClientState.Scoped), ClientState.ScopeProgress, tostring(ClientState.Reloading), tostring(ClientState.Mag)))
	end
end
check("mira puesta (atributo Scoped)", p1.Character:GetAttribute("Scoped") == true, "ScopeState recibidos: " .. table.concat(scopeCalls, ","))
do
	local scopes = {}
	for _, c in hud:GetChildren() do
		if c.Name == "Scope" then
			table.insert(scopes, c.ClassName .. "/" .. tostring(c.Visible))
		end
	end
	print("  hijos 'Scope' del HUD:", table.concat(scopes, " "), "| FindFirstChild:", hud:FindFirstChild("Scope") and hud:FindFirstChild("Scope").Visible)
	local sc = hud:FindFirstChild("Scope")
	sc.Visible = true
	print("  tras escribir Visible=true desde el runner:", sc.Visible, hud.Scope.Visible)
end
check("mira visible en HUD", hud:FindFirstChild("Scope") ~= nil and hud.Scope.Visible == true, string.format("Scope=%s Ammo=%s Crosshair=%s", tostring(hud.Scope.Visible), tostring(hud.Ammo.Visible), tostring(hud.Crosshair.Visible)))
local hits = {}
M.GetSignal(M.Unwrap(remotes.HitConfirm), "OnClientEvent"):Connect(function(zone, dmg, killed, d)
	table.insert(hits, { zone, dmg, killed, d })
end)
-- Recarga: disparar al suelo y recargar antes del tiro real
do
	local savedCam = workspace.CurrentCamera.CFrame
	workspace.CurrentCamera.CFrame = CFrame.lookAt(myHead.Position, myHead.Position + Vector3.new(0, -10, 1))
	M.FireAction("SD_Fire", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
	M.FireAction("SD_Fire", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
	M.Run(1.6)
	check("tiro al suelo gasta munición", p1:GetAttribute("SD_Mag") == 4, tostring(p1:GetAttribute("SD_Mag")))
	local reloadCalls = 0
	M.GetSignal(M.Unwrap(remotes.Reload), "OnServerEvent"):Connect(function()
		reloadCalls += 1
	end)
	M.FireAction("SD_Reload", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
	M.Run(0.5)
	local reloadingSeen = p1:GetAttribute("SD_Reloading")
	M.Run(3.2)
	check("recarga completa", p1:GetAttribute("SD_Mag") == 5, string.format("mag=%s reloadCalls=%d reloadingVisto=%s", tostring(p1:GetAttribute("SD_Mag")), reloadCalls, tostring(reloadingSeen)))
	-- volver a apuntar al torso del bot
	M.FireAction("SD_Scope", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton2)
	local Weapons = M.Require.server(game:GetService("ReplicatedStorage").Shared.Config.Weapons)
	local w = Weapons.Get(p1:GetAttribute("SD_Weapon"))
	local dist = (botTorso.Position - myHead.Position).Magnitude
	local t = dist / w.MuzzleVelocity
	workspace.CurrentCamera.CFrame = CFrame.lookAt(myHead.Position, botTorso.Position + Vector3.new(0, 0.5 * w.BulletGravity * t * t, 0))
	M.Run(0.5)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(myHead.Position, botTorso.Position + Vector3.new(0, 0.5 * w.BulletGravity * t * t, 0))
	local _ = savedCam
end
-- Diagnóstico de la trayectoria: ¿pasa por la cabeza del bot? ¿la bloquea algo?
do
	local Ballistics = M.Require.server(game:GetService("ReplicatedStorage").Shared.Ballistics)
	local Weapons = M.Require.server(game:GetService("ReplicatedStorage").Shared.Config.Weapons)
	local w = Weapons.Get(p1:GetAttribute("SD_Weapon"))
	local cam = workspace.CurrentCamera.CFrame
	local best, bestT = math.huge, 0
	local vel = cam.LookVector * w.MuzzleVelocity
	local blocked = nil
	local params = M.RaycastParams.new()
	params.FilterDescendantsInstances = { p1.Character, bot }
	local lastPos = cam.Position
	for t = 0, 0.5, 1 / 120 do
		local pos = Ballistics.PositionAt(cam.Position, vel, w.BulletGravity, t)
		local d = (pos - (bot:FindFirstChild("UpperTorso") or botHead).Position).Magnitude
		if d < best then
			best, bestT = d, t
		end
		if not blocked then
			local hit = workspace:Raycast(lastPos, pos - lastPos, params)
			if hit then
				blocked = hit.Instance:GetFullName()
			end
		end
		lastPos = pos
	end
	print(string.format("  arma %s: distancia mínima bala-cabeza %.2f studs (t=%.3f), cabeza %s; bloqueo: %s", w.Id, best, bestT, tostring(botHead.Size), tostring(blocked)))
end
M.FireAction("SD_Fire", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
M.FireAction("SD_Fire", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
M.Run(1.5)
check("disparo enviado al servidor y procesado (munición baja)", p1:GetAttribute("SD_Mag") == 4, tostring(p1:GetAttribute("SD_Mag")))
check("impacto confirmado en el bot", #hits > 0, if #hits > 0 then string.format("%s %d studs", hits[1][1], hits[1][4]) else "sin HitConfirm")
check("sin errores al disparar", #M.Errors == errorsBefore)
-- Recargar
-- Cuchillo (ranura 2), agacharse, menú y recompensa diaria
section("Cuchillo, agacharse, menú, diaria")
errorsBefore = #M.Errors
M.FireAction("SD_Slot2", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
M.Run(0.5)
check("ranura 2 en el cliente", ClientState.Slot == 2)
check("ranura 2 en el servidor (atributo)", p1:GetAttribute("SD_Slot") == 2, tostring(p1:GetAttribute("SD_Slot")))
check("cuchillo en la mano", p1.Character ~= nil and p1.Character:FindFirstChild("Knife") ~= nil)
check("viewmodel del cuchillo", workspace.CurrentCamera:FindFirstChild("KnifeViewmodel") ~= nil)
M.Run(1.2) -- que gire la mariposa en reposo
-- Rival nuevo (el anterior murió): esperar a la siguiente ronda Live
M.Run(5)
last = duelStates[#duelStates]
local bot2 = nil
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and string.find(m.Name, "Calabaza") then
		bot2 = m
	end
end
if last and last.State == "Live" and bot2 and p1.Character then
	-- la ronda nueva vuelve a la ranura 1: cambiar a cuchillo y acercar al bot
	M.FireAction("SD_Slot2", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
	M.Run(0.3)
	local myRoot = p1.Character.HumanoidRootPart
	myRoot.Anchored = true
	bot2.HumanoidRootPart.Anchored = false
	bot2:PivotTo(myRoot.CFrame * CFrame.new(0, 0, -5))
	bot2.HumanoidRootPart.Anchored = true
	M.Run(0.3)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(p1.Character.Head.Position, bot2.Head.Position)
	local before = #hits
	M.FireAction("SD_Fire", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
	M.FireAction("SD_Fire", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
	M.Run(0.6)
	check("cuchillada elimina al bot", #hits > before and hits[#hits][3] == true, if #hits > before then tostring(hits[#hits][2]) else "sin HitConfirm")
else
	check("ronda nueva lista para probar el cuchillo", false, last and last.State or "?")
end
-- Agacharse
M.Run(4.5)
local hum = p1.Character and p1.Character:FindFirstChildOfClass("Humanoid")
local hipBefore = hum and hum.HipHeight or 0
M.FireAction("SD_Crouch", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
M.Run(0.2)
check("agacharse baja la cadera", hum ~= nil and hum.HipHeight < hipBefore, string.format("%s -> %s", tostring(hipBefore), tostring(hum and hum.HipHeight)))
M.FireAction("SD_Crouch", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
M.Run(0.2)
check("levantarse restaura la cadera", hum ~= nil and math.abs(hum.HipHeight - hipBefore) < 0.01)
-- Menú (tecla M)
M.FireAction("SD_Menu", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
M.Run(0.2)
check("menú de pausa abierto", ClientState.MenuOpen == true and pg.Menu:FindFirstChild("PauseMenu") ~= nil and pg.Menu.PauseMenu.Visible == true)
M.FireAction("SD_Menu", Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
M.Run(0.2)
check("menú de pausa cerrado", ClientState.MenuOpen == false)
-- Recompensa diaria
local daily = remotes.ClaimDaily:InvokeServer()
check("recompensa diaria reclamada", daily ~= nil and daily.Ok == true and daily.Day == 1, daily and (daily.Error or tostring(daily.Coins)))
local daily2 = remotes.ClaimDaily:InvokeServer()
check("segunda reclamación rechazada", daily2 ~= nil and daily2.Ok == false)
check("sin errores en cuchillo/menú/diaria", #M.Errors == errorsBefore)

-- Abandonar duelo desde el menú
section("Abandonar duelo")
errorsBefore = #M.Errors
remotes.LeaveDuel:FireServer()
M.Run(1.5)
last = duelStates[#duelStates]
check("duelo terminado por abandono", last and last.State == "Ended" and last.Won == false and last.Reason == "forfeit", last and (last.State .. " " .. tostring(last.Reason)))
M.Run(6)
check("desarmado tras abandonar", p1:GetAttribute("SD_Weapon") == "", tostring(p1:GetAttribute("SD_Weapon")))
check("sin errores al abandonar", #M.Errors == errorsBefore)
-- Salir del duelo: el jugador se desconecta y vuelve a entrar
section("Salir y volver")
errorsBefore = #M.Errors
M.RemovePlayer(p1)
M.Run(1)
check("salida sin errores", #M.Errors == errorsBefore)
M.LocalPlayer = nil
local p1b = M.Wrap(M.AddPlayer("Tester", 1))
M.LocalPlayer = p1b
M.Run(1.5)
check("datos persistidos (monedas > 5000)", GetData:InvokeServer().Coins > 5000, tostring(GetData:InvokeServer().Coins))

-- INTERCAMBIO entre dos jugadores ---------------------------------------------------
section("Intercambio y regalo")
errorsBefore = #M.Errors
local p2 = M.Wrap(M.AddPlayer("Amigo", 2))
M.Run(1.5)
local tradeStates = {}
M.GetSignal(M.Unwrap(remotes.TradeUpdate), "OnClientEvent"):Connect(function(msg)
	table.insert(tradeStates, msg)
end)
-- p2 pide intercambio a p1 (simulado desde el servidor)
M.GetSignal(M.Unwrap(remotes.Trade), "OnServerEvent"):Fire(p2, "Request", p1b)
M.Run(0.3)
check("solicitud entrante recibida", #tradeStates > 0 and tradeStates[#tradeStates].Type == "Incoming")
remotes.Trade:FireServer("Respond", p2)
M.Run(0.3)
check("ventana de intercambio abierta", #tradeStates > 0 and tradeStates[#tradeStates].Type == "State")
remotes.Trade:FireServer("SetOffer", { { Kind = "Skin", Id = "Inferno" } })
M.Run(0.3)
check("oferta aceptada por el servidor", tradeStates[#tradeStates].MyOffer and #tradeStates[#tradeStates].MyOffer == 1)
remotes.Trade:FireServer("Ready", true)
M.GetSignal(M.Unwrap(remotes.Trade), "OnServerEvent"):Fire(p2, "Ready", true)
M.Run(5)
local closed = tradeStates[#tradeStates]
check("intercambio completado", closed and closed.Type == "Closed" and closed.Reason == "OK", closed and (closed.Reason or closed.Type))
check("skin transferida", GetData:InvokeServer().Inventory.Skins.Inferno == nil)
local gift = remotes.Gift:InvokeServer(p2, { Kind = "Skin", Id = "Gold" })
check("regalo enviado -> " .. tostring(gift and gift.Message), gift ~= nil and gift.Ok == true)
check("sin errores en intercambios", #M.Errors == errorsBefore)

-- DUELO EN PADS (dos jugadores) -------------------------------------------------------
section("Duelo casual en los pads")
errorsBefore = #M.Errors
local lobby = workspace.Lobby
local padA, padB = lobby:FindFirstChild("PadA_1"), lobby:FindFirstChild("PadB_1")
check("pads existen", padA ~= nil and padB ~= nil)
if padA and padB and p1b.Character and p2.Character then
	p1b.Character:PivotTo(padA.CFrame + Vector3.new(0, 3, 0))
	p2.Character:PivotTo(padB.CFrame + Vector3.new(0, 3, 0))
end
local before = #duelStates
M.Run(4.5)
check("duelo de pads iniciado", #duelStates > before and duelStates[#duelStates].OpponentName == "Amigo", duelStates[#duelStates] and duelStates[#duelStates].OpponentName)
M.Run(8)
last = duelStates[#duelStates]
check("duelo de pads en Live", last and last.State == "Live", last and last.State)
check("ambos armados", p1b:GetAttribute("SD_Weapon") ~= "" and p2:GetAttribute("SD_Weapon") ~= "")
-- p2 abandona: p1 gana por abandono
M.RemovePlayer(p2)
M.Run(1.5)
last = duelStates[#duelStates]
check("victoria por abandono", last and last.State == "Ended" and last.Won == true and last.Reason == "forfeit", last and (last.State .. " " .. tostring(last.Reason)))
M.Run(6)
check("vuelta al lobby (desarmado)", p1b:GetAttribute("SD_Weapon") == "", tostring(p1b:GetAttribute("SD_Weapon")))
check("cámara vuelve a tercera persona", p1b.CameraMode == Enum.CameraMode.Classic)
check("sin errores en el duelo de pads", #M.Errors == errorsBefore)

end
local okMain, errMain = xpcall(main, M.Traceback)
if not okMain then
	print("\27[31m[ABORTADO]\27[0m " .. tostring(errMain))
	failed += 1
end

-- RESUMEN -------------------------------------------------------------------------------
section("Resumen")
print(string.format("%d comprobaciones, %d fallos, %d errores en tiempo de ejecución", checks, failed, #M.Errors))
for i, e in M.Errors do
	print(string.format("\n--- error %d: %s ---\n%s", i, e.Context, e.Error))
end
process.exit(if failed == 0 and #M.Errors == 0 then 0 else 1)
