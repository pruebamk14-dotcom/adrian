--!strict
-- Recompensa diaria: racha de 7 días (como en Sniper Duels). Se abre sola al
-- entrar si se puede reclamar; también desde el botón 🎁 del lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Skins = require(Shared.Config.Skins)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local Make = require(script.Parent.Make)

local T = Make.Theme
local new = Make.new

local DailyUI = {}

local root: Frame
local cells: { Frame } = {}
local claimBtn: TextButton
local status: TextLabel
local notify: ((string, Color3?) -> ())? = nil

local function paint()
	local d = ClientState.Data
	local streak = d and d.DailyStreak or 0
	local claimable = d and d.DailyClaimable
	local nextDay = (streak % 7) + 1
	for i, cell in cells do
		local stroke = cell:FindFirstChildOfClass("UIStroke") :: UIStroke
		local done = i <= streak and not (claimable and i == nextDay and streak == 7)
		if claimable and i == nextDay then
			stroke.Color = T.Accent
			stroke.Thickness = 3
			cell.BackgroundColor3 = Color3.fromRGB(70, 45, 20)
		elseif done then
			stroke.Color = T.Gold
			stroke.Thickness = 1.5
			cell.BackgroundColor3 = Color3.fromRGB(50, 40, 20)
		else
			stroke.Color = T.Stroke
			stroke.Thickness = 1.5
			cell.BackgroundColor3 = T.Panel
		end
	end
	claimBtn.Visible = claimable == true
	status.Text = if claimable then string.format("¡Día %d listo para reclamar!", nextDay) else string.format("Racha: %d/7 · vuelve mañana", streak)
end

function DailyUI.Open()
	root.Visible = true
	paint()
	local panel = root:FindFirstChild("Panel") :: Frame
	panel.Size = UDim2.fromOffset(640, 300)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(680, 330) }):Play()
end

function DailyUI.Close()
	root.Visible = false
end

function DailyUI.Build(gui: ScreenGui, notifyFn: (string, Color3?) -> ())
	notify = notifyFn
	root = new("Frame", { Name = "Daily", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Visible = false, ZIndex = 40, Parent = gui })
	local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(680, 330), BackgroundColor3 = T.Bg, ZIndex = 41, Parent = root }, { Make.Corner(18), Make.Stroke(T.Gold, 2) })
	local title = Make.Label("RECOMPENSA DIARIA", { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 50), Font = T.FontTitle, TextSize = 46, ZIndex = 42, Parent = panel })
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 160, 40)), Parent = title })
	local row = new("Frame", { Position = UDim2.fromOffset(20, 86), Size = UDim2.new(1, -40, 0, 120), BackgroundTransparency = 1, ZIndex = 42, Parent = panel }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	for i, reward in GameConfig.Daily.Rewards do
		local cell = new("Frame", { Size = UDim2.fromOffset(84, 120), BackgroundColor3 = T.Panel, LayoutOrder = i, ZIndex = 42, Parent = row }, { Make.Corner(10), Make.Stroke(T.Stroke, 1.5) })
		Make.Label("DÍA " .. i, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = T.SubText, ZIndex = 43, Parent = cell })
		local icon = if reward == "Crate" then "🎁" else "🪙"
		Make.Label(icon, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 50), TextSize = 40, ZIndex = 43, Parent = cell })
		Make.Label(if reward == "Crate" then "CAJA" else tostring(reward), { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 24), Font = T.FontBlack, TextSize = 18, TextColor3 = if reward == "Crate" then T.Candy else T.Gold, ZIndex = 43, Parent = cell })
		table.insert(cells, cell)
	end
	status = Make.Label("", { Position = UDim2.fromOffset(0, 214), Size = UDim2.new(1, 0, 0, 22), TextSize = 15, TextColor3 = T.SubText, ZIndex = 42, Parent = panel })
	claimBtn = Make.Button("RECLAMAR", Color3.fromRGB(60, 200, 110), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 246), Size = UDim2.fromOffset(220, 54), TextSize = 22, ZIndex = 42, Parent = panel }, function()
		claimBtn.Visible = false
		local res = Net.Function("ClaimDaily"):InvokeServer()
		if res and res.Ok then
			local text
			if res.SkinId then
				local s = Skins.Get(res.SkinId)
				text = string.format("Día %d: skin %s%s y +%d caramelos 🍬", res.Day, s.DisplayName, if res.Duplicate then " (duplicada)" else "", res.Candies)
			else
				text = string.format("Día %d: +%d monedas", res.Day, res.Coins)
			end
			status.Text = text
			status.TextColor3 = T.Accent
			if notify then
				notify("🎁 " .. text, T.Gold)
			end
		else
			status.Text = res and res.Error or "Error"
			status.TextColor3 = T.Danger
		end
		task.delay(0.5, paint)
	end)
	Make.Button("✕", T.PanelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(36, 36), ZIndex = 42, Parent = panel }, DailyUI.Close)

	-- Abrir sola la primera vez que se puede reclamar
	local opened = false
	ClientState.DataChanged:Connect(function(data)
		if data and data.DailyClaimable and not opened and not ClientState.Duel then
			opened = true
			task.delay(1.5, function()
				if not ClientState.Duel then
					DailyUI.Open()
				end
			end)
		elseif root.Visible then
			paint()
		end
	end)
end

return DailyUI
