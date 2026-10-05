--!strict
-- Menú de pausa (tecla M o botón ☰). Roblox reserva la tecla Escape para su
-- propio menú, así que el del juego va en M.
--  * Continuar
--  * Ajustes (sensibilidad, mira por pulsación)
--  * Abandonar duelo / Volver al lobby
-- Mientras está abierto se libera el ratón y se bloquean disparo y movimiento.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Make)

local T = Make.Theme
local new = Make.new
local player = Players.LocalPlayer

local PauseMenu = {}

local root: Frame
local leaveBtn: TextButton
local sensValue: TextLabel
local scopeSensValue: TextLabel
local toggleBtn: TextButton

local function settings()
	local d = ClientState.Data
	return d and d.Settings or { Sensitivity = 1, ScopeSensitivity = 0.55, ToggleScope = false }
end

local function refresh()
	local s = settings()
	sensValue.Text = string.format("%.2f", s.Sensitivity)
	scopeSensValue.Text = string.format("%.2f", s.ScopeSensitivity)
	toggleBtn.Text = if s.ToggleScope then "Mira: ALTERNAR (clic)" else "Mira: MANTENER (clic)"
	local inDuel = ClientState.Duel ~= nil
	leaveBtn.Visible = inDuel
	leaveBtn.Text = if ClientState.Duel and ClientState.Duel.VsBot then "🚪 SALIR DEL DUELO" else "🏳 ABANDONAR DUELO (cuenta como derrota)"
end

function PauseMenu.Open()
	if root.Visible then
		return
	end
	root.Visible = true
	ClientState.MenuOpen = true
	refresh()
	pcall(function()
		player.CameraMode = Enum.CameraMode.Classic
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

function PauseMenu.Close()
	if not root.Visible then
		return
	end
	root.Visible = false
	ClientState.MenuOpen = false
	if ClientState.Armed then
		pcall(function()
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			UserInputService.MouseIconEnabled = false
		end)
	end
end

function PauseMenu.Toggle()
	if root.Visible then
		PauseMenu.Close()
	else
		PauseMenu.Open()
	end
end

local function change(key: string, delta: number, min: number, max: number)
	local s = settings()
	s[key] = math.clamp(math.round((s[key] + delta) * 100) / 100, min, max)
	refresh()
	task.spawn(function()
		Net.Function("UpdateSettings"):InvokeServer({ [key] = s[key] })
	end)
end

function PauseMenu.Build(gui: ScreenGui)
	root = new("Frame", {
		Name = "PauseMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 70,
		Parent = gui,
	})
	local panel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 470),
		BackgroundColor3 = T.Bg,
		ZIndex = 71,
		Parent = root,
	}, { Make.Corner(18), Make.Stroke(T.Accent, 2), Make.Padding(22), new("UIListLayout", { Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	local title = Make.Label("MENÚ", { Size = UDim2.new(1, 0, 0, 52), Font = T.FontTitle, TextSize = 48, ZIndex = 72, LayoutOrder = 1, Parent = panel })
	new("UIGradient", { Color = ColorSequence.new(T.Accent, T.Purple), Parent = title })

	local function button(text: string, color: Color3, order: number, fn: () -> ())
		local b = Make.Button(text, color, { Size = UDim2.new(1, 0, 0, 46), TextSize = 16, ZIndex = 72, LayoutOrder = order, Parent = panel }, fn)
		return b
	end
	button("▶ CONTINUAR", T.Accent, 2, PauseMenu.Close).TextColor3 = T.Bg

	-- Ajustes
	Make.Label("AJUSTES", { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = T.SubText, ZIndex = 72, LayoutOrder = 3, Parent = panel })
	local function stepper(label: string, key: string, order: number): TextLabel
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.Panel, ZIndex = 72, LayoutOrder = order, Parent = panel }, { Make.Corner(8) })
		Make.Label(label, { Position = UDim2.fromOffset(12, 9), Size = UDim2.new(0.5, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, ZIndex = 73, Parent = row })
		local value = Make.Label("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 9), Size = UDim2.fromOffset(60, 22), TextSize = 14, ZIndex = 73, Parent = row })
		Make.Button("−", T.PanelLight, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -122, 0.5, 0), Size = UDim2.fromOffset(30, 28), ZIndex = 73, Parent = row }, function()
			change(key, -0.05, 0.05, 4)
		end)
		Make.Button("+", T.PanelLight, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(30, 28), ZIndex = 73, Parent = row }, function()
			change(key, 0.05, 0.05, 4)
		end)
		return value
	end
	sensValue = stepper("Sensibilidad", "Sensitivity", 4)
	scopeSensValue = stepper("Sensibilidad con mira", "ScopeSensitivity", 5)
	toggleBtn = button("", T.PanelLight, 6, function()
		local s = settings()
		s.ToggleScope = not s.ToggleScope
		refresh()
		task.spawn(function()
			Net.Function("UpdateSettings"):InvokeServer({ ToggleScope = s.ToggleScope })
		end)
	end)

	Make.Label("Controles: clic dcho mira · clic izq dispara · R recarga · Z zoom · Shift correr/respirar · C agacharse (corriendo = deslizarse) · 1/2/Q rifle/cuchillo · M menú · F8 consola", {
		Size = UDim2.new(1, 0, 0, 54),
		TextWrapped = true,
		TextSize = 12,
		TextColor3 = T.SubText,
		ZIndex = 72,
		LayoutOrder = 7,
		Parent = panel,
	})
	leaveBtn = button("", T.Danger, 8, function()
		Net.Event("LeaveDuel"):FireServer()
		PauseMenu.Close()
	end)

	-- Botón ☰ siempre visible arriba a la izquierda (también en móvil)
	Make.Button("☰", T.Panel, { Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(44, 44), TextSize = 22, ZIndex = 60, Parent = gui }, PauseMenu.Toggle)

	ContextActionService:BindAction("SD_Menu", function(_, state)
		if state == Enum.UserInputState.Begin then
			PauseMenu.Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonStart)

	ClientState.DuelChanged:Connect(function(state)
		if state.State == "Ended" then
			PauseMenu.Close()
		elseif root.Visible then
			refresh()
		end
	end)
	ClientState.DataChanged:Connect(function()
		if root.Visible then
			refresh()
		end
	end)
end

return PauseMenu
