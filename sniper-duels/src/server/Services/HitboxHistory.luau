--!strict
-- Guarda un historial de las hitboxes de cada personaje para lag compensation.
-- El servidor "rebobina" a los jugadores al instante en que el tirador
-- disparó (según workspace:GetServerTimeNow()) y prueba la bala contra eso.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)

export type Box = { Zone: string, CFrame: CFrame, Size: Vector3 }
type Snapshot = { T: number, Boxes: { [string]: Box } }

local HitboxHistory = {}

-- Clave: Player o bot (cualquier tabla con campo Character)
local history: { [any]: { Snapshot } } = {}

local ZONES: { [string]: string } = {
	Head = "Head",
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	Torso = "Torso",
	LeftUpperArm = "Limb",
	LeftLowerArm = "Limb",
	LeftHand = "Limb",
	RightUpperArm = "Limb",
	RightLowerArm = "Limb",
	RightHand = "Limb",
	LeftUpperLeg = "Limb",
	LeftLowerLeg = "Limb",
	LeftFoot = "Limb",
	RightUpperLeg = "Limb",
	RightLowerLeg = "Limb",
	RightFoot = "Limb",
	["Left Arm"] = "Limb",
	["Right Arm"] = "Limb",
	["Left Leg"] = "Limb",
	["Right Leg"] = "Limb",
}

local function capture(character: Model): { [string]: Box }
	local boxes = {}
	for name, zone in ZONES do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local size = p.Size * GameConfig.HitboxInflate
			if zone == "Head" then
				size = Vector3.new(1.25, 1.25, 1.25) * GameConfig.HitboxInflate
			end
			boxes[name] = { Zone = zone, CFrame = p.CFrame, Size = size }
		end
	end
	return boxes
end

function HitboxHistory.Track(player: any)
	history[player] = {}
end

function HitboxHistory.Untrack(player: any)
	history[player] = nil
end

function HitboxHistory.Clear(player: any)
	if history[player] then
		history[player] = {}
	end
end

-- Devuelve las cajas del jugador interpoladas en el tiempo t.
function HitboxHistory.Sample(player: any, t: number): { [string]: Box }?
	local list = history[player]
	if not list or #list == 0 then
		return nil
	end
	if t >= list[#list].T then
		return list[#list].Boxes
	end
	if t <= list[1].T then
		return list[1].Boxes
	end
	for i = #list - 1, 1, -1 do
		local a, b = list[i], list[i + 1]
		if a.T <= t and t <= b.T then
			local alpha = (t - a.T) / math.max(b.T - a.T, 1e-6)
			local result = {}
			for name, boxA in a.Boxes do
				local boxB = b.Boxes[name]
				if boxB then
					result[name] = { Zone = boxA.Zone, CFrame = boxA.CFrame:Lerp(boxB.CFrame, alpha), Size = boxA.Size }
				end
			end
			return result
		end
	end
	return list[#list].Boxes
end

function HitboxHistory.Start()
	Players.PlayerRemoving:Connect(HitboxHistory.Untrack)
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for player, list in history do
			local char = player.Character
			if char and char.Parent then
				table.insert(list, { T = now, Boxes = capture(char) })
				while #list > 0 and now - list[1].T > GameConfig.HistoryLength do
					table.remove(list, 1)
				end
			end
		end
	end)
end

return HitboxHistory
