--!strict
-- Consola de errores en pantalla (F8). Muestra los errores y avisos del
-- cliente y, para los admins, también los del servidor. Si aparece un error
-- sale un aviso rojo en la esquina para que se pueda capturar y enviar.

local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local Make = require(script.Parent.Make)

local new = Make.new
local T = Make.Theme

local DebugOverlay = {}

local panel: Frame
local badge: TextButton
local list: ScrollingFrame
local lines: { string } = {}
local errorCount = 0

local function render()
	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i = math.max(1, #lines - 40), #lines do
		local text = lines[i]
		local isError = string.sub(text, 1, 3) == "[E]"
		Make.Label(text, {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextSize = 13,
			Font = Enum.Font.Code,
			TextColor3 = if isError then Color3.fromRGB(255, 120, 120) else Color3.fromRGB(255, 210, 130),
			LayoutOrder = i,
			Parent = list,
		})
	end
	badge.Text = string.format("⚠ %d error(es) · F8", errorCount)
end

local function add(isError: boolean, source: string, message: string)
	table.insert(lines, string.format("%s %s %s: %s", if isError then "[E]" else "[W]", os.date("%H:%M:%S"), source, message))
	if isError then
		errorCount += 1
		badge.Visible = true
	end
	if panel.Visible then
		render()
	else
		badge.Text = string.format("⚠ %d error(es) · F8", errorCount)
	end
end

function DebugOverlay.Toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		render()
	end
end

function DebugOverlay.Build(gui: ScreenGui)
	badge = Make.Button("", Color3.fromRGB(120, 20, 30), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 56),
		Size = UDim2.fromOffset(190, 30),
		TextSize = 13,
		Visible = false,
		ZIndex = 90,
		Parent = gui,
	}, DebugOverlay.Toggle)
	panel = new("Frame", {
		Name = "DebugConsole",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.new(0.8, 0, 0.6, 0),
		BackgroundColor3 = Color3.fromRGB(12, 8, 12),
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 95,
		Parent = gui,
	}, { Make.Corner(12), Make.Stroke(Color3.fromRGB(255, 80, 80), 2) })
	Make.Label("CONSOLA DE ERRORES (F8 para cerrar) · haz una captura y envíala", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = Color3.fromRGB(255, 120, 120), ZIndex = 96, Parent = panel })
	list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 36),
		Size = UDim2.new(1, -16, 1, -44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 96,
		Parent = panel,
	}, { new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- Errores del cliente
	pcall(function()
		LogService.MessageOut:Connect(function(message, messageType)
			if messageType == Enum.MessageType.MessageError then
				add(true, "cliente", message)
			elseif messageType == Enum.MessageType.MessageWarning and string.find(message, "SniperDuels") then
				add(false, "cliente", message)
			end
		end)
	end)
	-- Errores del servidor (solo llegan a admins)
	Net.Event("ServerLog").OnClientEvent:Connect(function(isError: boolean, message: string)
		add(isError, "servidor", message)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			DebugOverlay.Toggle()
		end
	end)
	local _ = T
end

return DebugOverlay
