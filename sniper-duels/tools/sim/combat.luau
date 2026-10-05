--!nocheck
-- Escenario de combate realista: duelo contra un bot que dispara, sin trucos
-- (el bot no se ancla ni se teletransporta). Comprueba que el bot te quita
-- vida y que tú puedes matarlo apuntando como un jugador.
-- Uso: lune run tools/sim/combat.luau [Normal|Pesadilla]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local M = require("./rbxmock")

local Enum, Vector3 = roblox.Enum, roblox.Vector3
local CFrame = M.CFrame
local difficulty = process.args[1] or "Normal"

local place = roblox.deserializePlace(fs.readFile("build/sim.rbxl"))
for _, svc in place:GetChildren() do
	local mine = M.Game:GetService(svc.ClassName)
	for _, child in svc:GetChildren() do
		child.Parent = mine
	end
end
local game = M.GameProxy
local workspace = game:GetService("Workspace")

M.RunScript(M.Unwrap(game:GetService("ServerScriptService").Server), "server")
M.Run(1.5)
local p1 = M.Wrap(M.AddPlayer("Tester", 1))
M.Run(1.5)
local clientScript = M.Unwrap(game:GetService("StarterPlayer").StarterPlayerScripts.Client)
M.LocalPlayer = p1
M.ClientRunning = true
M.RunScript(clientScript, "client")
M.Run(1)
local remotes = game:GetService("ReplicatedStorage").Remotes

local log = {}
M.GetSignal(M.Unwrap(remotes.ShotResult), "OnClientEvent"):Connect(function(text)
	table.insert(log, "mi tiro: " .. text)
end)
M.GetSignal(M.Unwrap(remotes.Damaged), "OnClientEvent"):Connect(function(_, dmg, hp)
	table.insert(log, string.format("me dieron: -%d (vida %d)", dmg, hp))
end)
local states = {}
M.GetSignal(M.Unwrap(remotes.DuelState), "OnClientEvent"):Connect(function(s)
	table.insert(states, s)
end)

remotes.PlayBot:FireServer(difficulty)
M.Run(12.5)
print("estado:", states[#states] and states[#states].State)

local bot
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and string.find(m.Name, "Calabaza") then
		bot = m
	end
end
print("bot:", bot and bot.Name)

-- Sacar al jugador del búnker hacia el centro para que el bot lo vea
local myRoot = p1.Character.HumanoidRootPart
local base = myRoot.CFrame
p1.Character:PivotTo(base * CFrame.new(0, 0, -60))
local myHum = p1.Character:FindFirstChildOfClass("Humanoid")

-- Fase 1: quedarse quieto 15 s y ver si el bot dispara y acierta
local shots = 0
M.GetSignal(M.Unwrap(remotes.ShotFx), "OnClientEvent"):Connect(function(char)
	if char and bot and M.Key(M.Unwrap(char)) == M.Key(M.Unwrap(bot)) then
		shots += 1
	end
end)
for sec = 1, tonumber(process.args[2]) or 30 do
	M.Run(1)
	if bot and bot:FindFirstChild("HumanoidRootPart") then
		local r = bot.HumanoidRootPart
		local params = M.RaycastParams.new()
		params.FilterDescendantsInstances = { bot }
		local bh, ph = bot:FindFirstChild("Head"), p1.Character and p1.Character:FindFirstChild("Head")
		local hit = bh and ph and workspace:Raycast(bh.Position, ph.Position - bh.Position, params)
		local los = if hit then (if hit.Instance:IsDescendantOf(p1.Character) then "VE" else hit.Instance.Name) else "libre"
		print(string.format("  t=%d los=%s yo=(%.0f,%.0f)", sec, los, ph and ph.Position.X or 0, ph and ph.Position.Z or 0))
		print(string.format("  t=%d bot en (%.0f, %.0f) modo=%s scoped=%s", sec, r.Position.X, r.Position.Z, tostring(bot:GetAttribute("AIMode")), tostring(bot:GetAttribute("Scoped"))))
	end
	if myHum.Health <= 0 then
		break
	end
end
print(string.format("Fase 1 (%s): el bot disparó %d veces; mi vida: %d", difficulty, shots, myHum.Health))

if process.args[3] == "solo1" then
	for _, l in log do
		print("  " .. l)
	end
	process.exit(0)
end
-- Fase 2: apuntar al bot (con la caída) y disparar 5 veces
M.Run(8.5)
local last = states[#states]
print("estado antes de disparar:", last and last.State, "ronda", last and last.Round)
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and string.find(m.Name, "Calabaza") then
		bot = m
	end
end
local ClientState = M.Require.client(clientScript.ClientState)
local hits = 0
M.GetSignal(M.Unwrap(remotes.HitConfirm), "OnClientEvent"):Connect(function()
	hits += 1
end)
-- Colocarse donde se vea al bot (como haría un jugador), sin mover al bot
do
	local head = p1.Character and p1.Character:FindFirstChild("Head")
	local torso = bot and bot:FindFirstChild("UpperTorso")
	if head and torso then
		local params = M.RaycastParams.new()
		params.FilterDescendantsInstances = { p1.Character, bot }
		local origin = p1.Character.HumanoidRootPart.CFrame
		local found = false
		for x = -60, 60, 10 do
			for z = 0, 120, 15 do
				p1.Character:PivotTo(origin * CFrame.new(x, 0, -z))
				if not workspace:Raycast(head.Position, torso.Position - head.Position, params) then
					found = true
					break
				end
			end
			if found then
				break
			end
		end
		print("posición con visión al bot:", found)
		p1.Character.HumanoidRootPart.Anchored = true
	end
end
for i = 1, 5 do
	local head = p1.Character and p1.Character:FindFirstChild("Head")
	local torso = bot and (bot:FindFirstChild("UpperTorso"))
	if head and torso then
		local w = M.Require.server(game:GetService("ReplicatedStorage").Shared.Config.Weapons).Get(p1:GetAttribute("SD_Weapon"))
		local d = (torso.Position - head.Position).Magnitude
		local t = d / w.MuzzleVelocity
		workspace.CurrentCamera.CFrame = CFrame.lookAt(head.Position, torso.Position + Vector3.new(0, 0.5 * w.BulletGravity * t * t, 0))
		M.MouseButtons[Enum.UserInputType.MouseButton2] = true
		M.FireAction("SD_Scope", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton2)
		M.Run(0.7)
		workspace.CurrentCamera.CFrame = CFrame.lookAt(head.Position, torso.Position + Vector3.new(0, 0.5 * w.BulletGravity * t * t, 0))
		local WC = M.Require.client(clientScript.Controllers.WeaponController)
		local bv = bot.HumanoidRootPart.AssemblyLinearVelocity
		print(string.format("  disparo %d a %.0f studs (scoped=%s prog=%.2f spread=%.2f sway=%s vel_bot=%.1f)", i, d, tostring(ClientState.Scoped), ClientState.ScopeProgress, WC.CurrentSpread(), tostring(ClientState.Sway), bv.Magnitude))
		M.FireAction("SD_Fire", Enum.UserInputState.Begin, Enum.UserInputType.MouseButton1)
		M.FireAction("SD_Fire", Enum.UserInputState.End, Enum.UserInputType.MouseButton1)
	end
	M.Run(1.6)
	if hits > 0 then
		break -- el bot muere de un tiro al torso
	end
end
print(string.format("Fase 2: impactos confirmados %d", hits))
for _, l in log do
	print("  " .. l)
end
print("errores:", #M.Errors)
for _, e in M.Errors do
	print(e.Context, e.Error)
end
process.exit(0)
