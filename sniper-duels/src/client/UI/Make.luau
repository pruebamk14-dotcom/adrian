--!strict
-- Helper declarativo para construir UI desde código + tema visual.

local Make = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)
local halloween = GameConfig.HalloweenEvent

Make.Theme = {
	Bg = if halloween then Color3.fromRGB(16, 11, 20) else Color3.fromRGB(14, 15, 19),
	Panel = if halloween then Color3.fromRGB(28, 20, 34) else Color3.fromRGB(24, 26, 33),
	PanelLight = if halloween then Color3.fromRGB(46, 33, 54) else Color3.fromRGB(36, 39, 49),
	Stroke = if halloween then Color3.fromRGB(90, 60, 110) else Color3.fromRGB(60, 64, 78),
	Text = Color3.fromRGB(240, 236, 244),
	SubText = if halloween then Color3.fromRGB(170, 150, 180) else Color3.fromRGB(150, 156, 172),
	Accent = if halloween then Color3.fromRGB(255, 130, 20) else Color3.fromRGB(0, 255, 140),
	Purple = Color3.fromRGB(170, 80, 255),
	Danger = Color3.fromRGB(255, 70, 90),
	Gold = Color3.fromRGB(255, 200, 60),
	Blue = Color3.fromRGB(80, 160, 255),
	Candy = Color3.fromRGB(255, 120, 200),
	Font = Enum.Font.GothamBold,
	FontBlack = Enum.Font.GothamBlack,
	FontMedium = Enum.Font.GothamMedium,
	FontTitle = if halloween then Enum.Font.Creepster else Enum.Font.GothamBlack,
	Halloween = halloween,
}

function Make.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			elseif type(k) == "string" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Make.Corner(radius: number?): UICorner
	return Make.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Make.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Make.new("UIStroke", {
		Color = color or Make.Theme.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Make.Padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return Make.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Make.Label(text: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Make.Theme.Text,
		Font = Make.Theme.Font,
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 24),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Make.new("TextLabel", base)
end

function Make.Button(text: string, color: Color3, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local base: { [string]: any } = {
		BackgroundColor3 = color,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Make.Theme.FontBlack,
		TextSize = 18,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(160, 44),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local b = Make.new("TextButton", base, { Make.Corner(10) })
	if onClick then
		b.MouseButton1Click:Connect(onClick)
	end
	return b
end

return Make
