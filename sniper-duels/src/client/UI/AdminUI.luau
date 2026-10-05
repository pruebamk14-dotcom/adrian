--!strict
-- Panel de administración (solo visible para admins): elegir jugador y
-- dar monedas/caramelos/nivel/skins/armas, expulsar, banear, anunciar,
-- y una consola para escribir comandos (:coins me 5000, etc.).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local Make = require(script.Parent.Make)

local T = Make.Theme
local new = Make.new
local player = Players.LocalPlayer

local AdminUI = {}

local panel: Frame
local selected = "me"
local list: ScrollingFrame
local output: TextLabel
local amountBox: TextBox
local reasonBox: TextBox

local function run(cmd: string)
	output.Text = "> " .. cmd
	output.TextColor3 = T.SubText
	local res = Net.Function("AdminCommand"):InvokeServer(cmd)
	output.Text = "> " .. cmd .. "\n" .. tostring(res)
	output.TextColor3 = T.Text
end

local function box(parent: Instance, placeholder: string, pos: UDim2, size: UDim2): TextBox
	return new("TextBox", {
		Position = pos,
		Size = size,
		BackgroundColor3 = T.Panel,
		PlaceholderText = placeholder,
		PlaceholderColor3 = T.SubText,
		Text = "",
		TextColor3 = T.Text,
		Font = T.Font,
		TextSize = 16,
		ClearTextOnFocus = false,
		Parent = parent,
	}, { Make.Corner(8), Make.Stroke(T.Stroke, 1.5) })
end

local function refreshList()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local entries = { { "me", "Yo (" .. player.DisplayName .. ")" }, { "all", "TODOS" } }
	for _, p in Players:GetPlayers() do
		if p ~= player then
			table.insert(entries, { p.Name, p.DisplayName .. " @" .. p.Name })
		end
	end
	for _, e in entries do
		local active = e[1] == selected
		Make.Button(e[2], if active then T.Accent else T.Panel, { Size = UDim2.new(1, -6, 0, 34), TextSize = 13, TextColor3 = if active then T.Bg else T.Text, TextTruncate = Enum.TextTruncate.AtEnd, Parent = list }, function()
			selected = e[1]
			refreshList()
		end)
	end
end

function AdminUI.Open()
	panel.Visible = true
	refreshList()
end

function AdminUI.Close()
	panel.Visible = false
end

function AdminUI.Toggle()
	if panel.Visible then
		AdminUI.Close()
	else
		AdminUI.Open()
	end
end

function AdminUI.Build(gui: ScreenGui)
	panel = new("Frame", {
		Name = "Admin",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 500),
		BackgroundColor3 = T.Bg,
		Visible = false,
		ZIndex = 45,
		Parent = gui,
	}, { Make.Corner(16), new("UIStroke", { Color = Color3.fromRGB(80, 160, 255), Thickness = 2 }) })
	Make.Label("🛡 PANEL DE ADMIN", { Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(500, 36), TextXAlignment = Enum.TextXAlignment.Left, Font = T.FontBlack, TextSize = 26, TextColor3 = Color3.fromRGB(120, 190, 255), Parent = panel })
	Make.Label("Rango: " .. tostring(player:GetAttribute("SD_Rank")), { Position = UDim2.fromOffset(22, 46), Size = UDim2.fromOffset(300, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = T.SubText, Parent = panel })
	Make.Button("✕", T.PanelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(36, 36), Parent = panel }, AdminUI.Close)

	Make.Label("JUGADOR", { Position = UDim2.fromOffset(20, 72), Size = UDim2.fromOffset(220, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = T.SubText, Parent = panel })
	list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 92),
		Size = UDim2.fromOffset(220, 300),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6) }) })

	amountBox = box(panel, "Cantidad (ej. 5000)", UDim2.fromOffset(260, 92), UDim2.fromOffset(200, 38))
	reasonBox = box(panel, "Motivo / minutos de ban", UDim2.fromOffset(470, 92), UDim2.fromOffset(270, 38))

	local grid = new("Frame", { Position = UDim2.fromOffset(260, 142), Size = UDim2.fromOffset(480, 200), BackgroundTransparency = 1, Parent = panel }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(152, 42), CellPadding = UDim2.fromOffset(12, 10) }),
	})
	local function amt(default: string): string
		return if amountBox.Text ~= "" then amountBox.Text else default
	end
	local actions = {
		{ "💰 +Monedas", T.Gold, function() run(string.format(":coins %s %s", selected, amt("5000"))) end },
		{ "🍬 +Caramelos", T.Candy, function() run(string.format(":candies %s %s", selected, amt("500"))) end },
		{ "⭐ Poner nivel", T.Blue, function() run(string.format(":level %s %s", selected, amt("20"))) end },
		{ "🎨 Todas skins", T.Purple, function() run(":skins " .. selected) end },
		{ "🔫 Todas armas", T.Purple, function() run(":weapons " .. selected) end },
		{ "❤ Curar", Color3.fromRGB(90, 200, 110), function() run(":heal " .. selected) end },
		{ "👢 Expulsar", T.Danger, function() run(string.format(":kick %s %s", selected, reasonBox.Text)) end },
		{ "⛔ Banear", Color3.fromRGB(150, 20, 40), function()
			local mins = tonumber(reasonBox.Text)
			run(string.format(":ban %s %s", selected, if mins then tostring(mins) else ("perm " .. reasonBox.Text)))
		end },
		{ "📢 Anunciar", T.Accent, function() run(":announce " .. reasonBox.Text) end },
	}
	for _, a in actions do
		Make.Button(a[1], a[2], { TextSize = 14, TextColor3 = if a[2] == T.Gold or a[2] == T.Accent then T.Bg else Color3.new(1, 1, 1), Parent = grid }, a[3])
	end

	local console = box(panel, "Consola:  :coins me 5000   :unban 123456   :level all 10", UDim2.fromOffset(20, 404), UDim2.new(1, -40, 0, 36))
	console.FocusLost:Connect(function(enter)
		if enter and console.Text ~= "" then
			run(console.Text)
			console.Text = ""
		end
	end)
	output = Make.Label("Selecciona un jugador y una acción.", { Position = UDim2.fromOffset(260, 352), Size = UDim2.fromOffset(480, 44), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextSize = 13, TextColor3 = T.SubText, Parent = panel })
	Make.Label("También puedes escribir los comandos en el chat empezando por  :", { Position = UDim2.fromOffset(22, 450), Size = UDim2.new(1, -44, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = T.SubText, Parent = panel })

	Players.PlayerAdded:Connect(function()
		if panel.Visible then
			refreshList()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if panel.Visible then
			task.defer(refreshList)
		end
	end)
end

function AdminUI.IsAdmin(): boolean
	local r = player:GetAttribute("SD_Rank")
	return r == "Owner" or r == "Admin"
end

return AdminUI
