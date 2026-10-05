--!nocheck
-- Simulador de Roblox sobre Lune para ejecutar el juego fuera de Studio.
-- Implementa lo que @lune/roblox no trae: eventos, servicios, jugadores,
-- personajes, remotes, pathfinding, tweens... Lo justo para que el servidor
-- y el cliente arranquen y jueguen un duelo completo y poder cazar errores.

local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Instance, Enum = roblox.Instance, roblox.Enum
local Vector3, Vector2, CFrame, Color3 = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Color3

local M = {}
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.new(0, 5, 0)
M.Errors = {}
M.Log = {}
M.IsStudio = true
M.Verbose = false

-- Lune devuelve un userdata distinto cada vez que se accede a la misma
-- instancia: todas las tablas se indexan por su id estable.
local function key(inst): string
	return inst:GetDebugId()
end
M.Key = key

local function report(ctx: string, err: any)
	local msg = tostring(err)
	table.insert(M.Errors, { Context = ctx, Error = msg })
	print(string.format("\27[31m[ERROR] %s\27[0m\n%s", ctx, msg))
end
M.Report = report

local function tb(err)
	local ok, r = pcall(debug.traceback, tostring(err), 2)
	return if ok then r else tostring(err)
end
M.Traceback = tb

local function safe(ctx: string, fn, ...)
	local ok, err = xpcall(fn, tb, ...)
	if not ok then
		report(ctx, err)
	end
	return ok
end
M.Safe = safe

-- Señales -------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal
function Signal.new(name: string)
	return setmetatable({ _h = {}, _name = name }, Signal)
end
function Signal:Connect(fn)
	local c = { fn = fn, Connected = true }
	function c.Disconnect()
		c.Connected = false
		local i = table.find(self._h, c)
		if i then
			table.remove(self._h, i)
		end
	end
	table.insert(self._h, c)
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Wait()
	local done, args = false, nil
	self:Once(function(...)
		done = true
		args = table.pack(...)
	end)
	while not done do
		task.wait()
	end
	return table.unpack(args, 1, args.n)
end
function Signal:Fire(...)
	for _, c in table.clone(self._h) do
		if c.Connected then
			local args = table.pack(...)
			for i = 1, args.n do
				if typeof(args[i]) == "Instance" then
					args[i] = M.Wrap(args[i])
				end
			end
			task.spawn(function()
				local ok, err = xpcall(c.fn, tb, table.unpack(args, 1, args.n))
				if not ok then
					report("evento " .. self._name, err)
				end
			end)
		end
	end
end
M.Signal = Signal

local instSignals = {}
local function getSignal(inst, name: string)
	local k = key(inst)
	local t = instSignals[k]
	if not t then
		t = {}
		instSignals[k] = t
	end
	if not t[name] then
		t[name] = Signal.new(tostring(inst.Name) .. "." .. name)
	end
	return t[name]
end
M.GetSignal = getSignal

local function signalProp(className: string, name: string)
	roblox.implementProperty(className, name, function(inst)
		return getSignal(inst, name)
	end, function() end)
end

-- Instancia: eventos y métodos genéricos -------------------------------------

for _, name in { "Changed", "AncestryChanged", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Destroying", "AttributeChanged" } do
	signalProp("Instance", name)
end

-- Los métodos nativos de Lune tienen prioridad sobre implementMethod, así que
-- los cambios de atributos se detectan por sondeo en cada Step.
local attrWatch: { { Inst: Instance, Name: string, Last: any } } = {}
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(inst, name)
	local found = false
	for _, w in attrWatch do
		if key(w.Inst) == key(inst) and w.Name == name then
			found = true
		end
	end
	if not found then
		table.insert(attrWatch, { Inst = inst, Name = name, Last = inst:GetAttribute(name) })
	end
	return getSignal(inst, "Attr:" .. name)
end)
local function pollAttributes()
	for i = #attrWatch, 1, -1 do
		local w = attrWatch[i]
		local ok, v = pcall(function()
			return w.Inst:GetAttribute(w.Name)
		end)
		if not ok then
			table.remove(attrWatch, i)
		elseif v ~= w.Last then
			w.Last = v
			getSignal(w.Inst, "Attr:" .. w.Name):Fire()
			getSignal(w.Inst, "AttributeChanged"):Fire(w.Name)
		end
	end
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(inst, name)
	return getSignal(inst, "Prop:" .. name)
end)
roblox.implementMethod("Instance", "WaitForChild", function(inst, name, timeout)
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		local c = inst:FindFirstChild(name)
		if c then
			return c
		end
		task.wait(0.05)
	end
	if timeout then
		return nil
	end
	report("WaitForChild", string.format("'%s' no apareció dentro de %s", name, inst:GetFullName()))
	return nil
end)
roblox.implementMethod("Instance", "FindFirstAncestorOfClass", function(inst, className)
	local p = inst.Parent
	while p do
		if p.ClassName == className then
			return p
		end
		p = p.Parent
	end
	return nil
end)

-- Partes --------------------------------------------------------------------

local velocities = {} -- [id] = Vector3
roblox.implementProperty("BasePart", "AssemblyLinearVelocity", function(inst)
	return velocities[key(inst)] or Vector3.zero
end, function(inst, v)
	velocities[key(inst)] = v
end)
roblox.implementProperty("BasePart", "AssemblyAngularVelocity", function()
	return Vector3.zero
end, function() end)
roblox.implementProperty("BasePart", "Position", function(inst)
	return inst.CFrame.Position
end, function(inst, v)
	local cf = inst.CFrame
	inst.CFrame = CFrame.fromMatrix(v, cf.XVector, cf.YVector, cf.ZVector)
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
roblox.implementMethod("BasePart", "GetMass", function()
	return 1
end)
roblox.implementProperty("Attachment", "WorldPosition", function(inst)
	local p = inst.Parent
	return if p and p:IsA("BasePart") then p.CFrame:PointToWorldSpace(inst.Position) else inst.Position
end, function() end)
roblox.implementProperty("Attachment", "WorldCFrame", function(inst)
	local p = inst.Parent
	return if p and p:IsA("BasePart") then p.CFrame * inst.CFrame else inst.CFrame
end, function() end)

roblox.implementMethod("Model", "GetPivot", function(inst)
	local pp = inst.PrimaryPart
	if pp then
		return pp.CFrame
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			return d.CFrame
		end
	end
	return inst.WorldPivot
end)
roblox.implementMethod("Model", "PivotTo", function(inst, cf)
	local current = inst:GetPivot()
	local delta = cf * current:Inverse()
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	inst.WorldPivot = cf
end)
roblox.implementMethod("Model", "GetBoundingBox", function(inst)
	local minV, maxV = nil, nil
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			local p, s = d.CFrame.Position, d.Size / 2
			local lo, hi = p - s, p + s
			minV = if minV then Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) else lo
			maxV = if maxV then Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) else hi
		end
	end
	if not minV then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end)
roblox.implementMethod("Model", "SetPrimaryPartCFrame", function(inst, cf)
	inst:PivotTo(cf)
end)

-- Humanoid -------------------------------------------------------------------

signalProp("Humanoid", "Died")
signalProp("Humanoid", "HealthChanged")
signalProp("Humanoid", "StateChanged")
signalProp("Humanoid", "MoveToFinished")
roblox.implementProperty("Humanoid", "RootPart", function(inst)
	local c = inst.Parent
	return c and c:FindFirstChild("HumanoidRootPart")
end, function() end)
roblox.implementProperty("Humanoid", "FloorMaterial", function()
	return Enum.Material.Grass
end, function() end)
roblox.implementProperty("Humanoid", "MoveDirection", function()
	return Vector3.zero
end, function() end)
local moveTargets = {} -- [id] = Vector3
M.MoveTargets = moveTargets
roblox.implementMethod("Humanoid", "MoveTo", function(inst, pos)
	moveTargets[key(inst)] = pos
end)
roblox.implementMethod("Humanoid", "Move", function(inst, dir)
	moveTargets[key(inst)] = nil
	if dir.Magnitude > 0 then
		local root = inst.RootPart
		if root then
			velocities[key(root)] = dir.Unit * inst.WalkSpeed
		end
	else
		local root = inst.RootPart
		if root then
			velocities[key(root)] = Vector3.zero
		end
	end
end)
roblox.implementMethod("Humanoid", "TakeDamage", function(inst, d)
	inst.Health = math.max(0, inst.Health - d)
end)
roblox.implementMethod("Humanoid", "GetState", function()
	return Enum.HumanoidStateType.Running
end)
roblox.implementMethod("Humanoid", "ChangeState", function() end)
roblox.implementMethod("Humanoid", "ApplyDescription", function() end)

-- Vida: Died al llegar a 0 (lo gestiona el tick del simulador)
local humanoids = {} -- [id] = Humanoid
M.Humanoids = humanoids

-- Animaciones
local Track = {}
Track.__index = Track
function Track:Play()
	self.IsPlaying = true
end
function Track:Stop()
	self.IsPlaying = false
end
function Track:AdjustSpeed() end
roblox.implementMethod("Animator", "LoadAnimation", function(_, anim)
	return setmetatable({ IsPlaying = false, Looped = false, Priority = Enum.AnimationPriority.Core, Animation = anim, Length = 1, Stopped = Signal.new("Track.Stopped"), KeyframeReached = Signal.new("Track.KeyframeReached") }, Track)
end)

-- GUI ------------------------------------------------------------------------

for _, name in { "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "Activated", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" } do
	signalProp("GuiObject", name)
end
signalProp("TextBox", "FocusLost")
signalProp("TextBox", "Focused")
roblox.implementMethod("TextBox", "CaptureFocus", function() end)
roblox.implementMethod("TextBox", "ReleaseFocus", function() end)
roblox.implementProperty("GuiObject", "AbsoluteSize", function(inst)
	local s = inst.Size
	return Vector2.new(s.X.Scale * 1280 + s.X.Offset, s.Y.Scale * 720 + s.Y.Offset)
end, function() end)
roblox.implementProperty("GuiObject", "AbsolutePosition", function()
	return Vector2.zero
end, function() end)
roblox.implementProperty("GuiBase2d", "AbsoluteSize", function()
	return Vector2.new(1280, 720)
end, function() end)
roblox.implementProperty("Camera", "ViewportSize", function()
	return Vector2.new(1280, 720)
end, function() end)
roblox.implementMethod("Camera", "WorldToViewportPoint", function(_, pos)
	return Vector3.new(640, 360, 10), true
end)
roblox.implementMethod("Camera", "WorldToScreenPoint", function(_, pos)
	return Vector3.new(640, 360, 10), true
end)
roblox.implementMethod("Camera", "ScreenPointToRay", function(inst)
	return roblox.Ray.new(inst.CFrame.Position, inst.CFrame.LookVector)
end)

-- Sonido
roblox.implementMethod("Sound", "Play", function(inst)
	inst.Playing = true
end)
roblox.implementMethod("Sound", "Stop", function(inst)
	inst.Playing = false
end)
roblox.implementMethod("Sound", "Pause", function() end)
roblox.implementProperty("Sound", "IsPlaying", function(inst)
	return inst.Playing
end, function() end)
signalProp("Sound", "Ended")

-- Partículas
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("ParticleEmitter", "Clear", function() end)

-- Tool
for _, name in { "Equipped", "Unequipped", "Activated", "Deactivated" } do
	signalProp("Tool", name)
end
roblox.implementMethod("Tool", "Activate", function(inst)
	getSignal(inst, "Activated"):Fire()
end)

-- Terrain
roblox.implementMethod("Terrain", "FillBlock", function() end)
roblox.implementMethod("Terrain", "FillBall", function() end)
roblox.implementMethod("Terrain", "FillRegion", function() end)
roblox.implementMethod("Terrain", "SetMaterialColor", function() end)
roblox.implementMethod("Terrain", "Clear", function() end)

-- Player ---------------------------------------------------------------------

local playerData = {} -- [id] = datos
local function pdata(p)
	local k = key(p)
	local d = playerData[k]
	if not d then
		d = {}
		playerData[k] = d
	end
	return d
end
roblox.implementProperty("Player", "UserId", function(inst)
	return pdata(inst).UserId or 0
end, function(inst, v)
	pdata(inst).UserId = v
end)
roblox.implementProperty("Player", "DisplayName", function(inst)
	return pdata(inst).DisplayName or inst.Name
end, function(inst, v)
	pdata(inst).DisplayName = v
end)
roblox.implementProperty("Player", "Character", function(inst)
	return pdata(inst).Character
end, function(inst, v)
	pdata(inst).Character = v
end)
roblox.implementProperty("Player", "Team", function()
	return nil
end, function() end)
for _, name in { "CharacterAdded", "CharacterRemoving", "Chatted", "Idled" } do
	signalProp("Player", name)
end
roblox.implementMethod("Player", "Kick", function(inst, msg)
	print("\27[33m[KICK]\27[0m", inst.Name, msg)
	pdata(inst).Kicked = msg or true
	if M.RemovePlayer then
		task.defer(M.RemovePlayer, inst)
	end
end)
roblox.implementMethod("Player", "GetRankInGroup", function()
	return 0
end)
roblox.implementMethod("Player", "IsInGroup", function()
	return false
end)
roblox.implementMethod("Player", "GetMouse", function()
	return { Hit = CFrame.new(), Target = nil, X = 0, Y = 0 }
end)

-- Personaje R15 de prueba
function M.BuildR15(name: string): Instance
	local char = Instance.new("Model")
	char.Name = name
	local function part(pname, size, offset)
		local p = Instance.new("Part")
		p.Name = pname
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Parent = char
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	root.Transparency = 1
	part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 2.2, 0))
	local upper = part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.2, 0))
	part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0))
	local arms = {
		{ "LeftUpperArm", "LeftShoulder", -1.5, 3.4 }, { "LeftLowerArm", "LeftElbow", -1.5, 2.8 }, { "LeftHand", "LeftWrist", -1.5, 2.3 },
		{ "RightUpperArm", "RightShoulder", 1.5, 3.4 }, { "RightLowerArm", "RightElbow", 1.5, 2.8 }, { "RightHand", "RightWrist", 1.5, 2.3 },
	}
	for _, a in arms do
		local p = part(a[1], Vector3.new(1, 0.6, 1), Vector3.new(a[3], a[4], 0))
		local m = Instance.new("Motor6D")
		m.Name = a[2]
		m.Part0 = upper
		m.Part1 = p
		m.Parent = p
	end
	for _, l in { { "LeftUpperLeg", -0.5, 1.6 }, { "LeftLowerLeg", -0.5, 1.0 }, { "LeftFoot", -0.5, 0.4 }, { "RightUpperLeg", 0.5, 1.6 }, { "RightLowerLeg", 0.5, 1.0 }, { "RightFoot", 0.5, 0.4 } } do
		part(l[1], Vector3.new(1, 0.6, 1), Vector3.new(l[2], l[3], 0))
	end
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.Health = 100
	hum.MaxHealth = 100
	hum.HipHeight = 2
	hum.Parent = char
	local animator = Instance.new("Animator")
	animator.Parent = hum
	char.PrimaryPart = root
	humanoids[key(hum)] = hum
	return char
end


-- Proxy de instancias ---------------------------------------------------------
-- Lune no permite leer propiedades sin valor por defecto (Position, AbsoluteSize,
-- UserId...) ni sobreescribir las que existen. Los scripts del juego ven un
-- proxy por instancia que calcula esas propiedades y envuelve todo lo que sale.

local proxies = {} -- [id] = proxy
local rawOf = setmetatable({}, { __mode = "k" })
local wrap, unwrap

function unwrap(v)
	if type(v) == "table" then
		local r = rawOf[v]
		if r ~= nil then
			return r
		end
	end
	return v
end

local function unwrapArgs(...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = unwrap(args[i])
	end
	return table.unpack(args, 1, args.n)
end

local function wrapResult(v)
	if typeof(v) == "Instance" then
		return wrap(v)
	elseif type(v) == "table" and getmetatable(v) == nil then
		local anyInst = false
		for _, x in v do
			if typeof(x) == "Instance" then
				anyInst = true
				break
			end
		end
		if anyInst then
			local out = {}
			for k, x in v do
				out[k] = if typeof(x) == "Instance" then wrap(x) else x
			end
			return out
		end
	end
	return v
end

-- Propiedades calculadas cuando Lune no tiene valor
local computed = {
	Position = function(raw)
		if raw:IsA("BasePart") then
			return raw.CFrame.Position
		end
		return roblox.UDim2.new()
	end,
	Orientation = function(raw)
		local x, y, z = raw.CFrame:ToOrientation()
		return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
	end,
	AssemblyLinearVelocity = function(raw)
		return velocities[key(raw)] or Vector3.zero
	end,
	AssemblyAngularVelocity = function()
		return Vector3.zero
	end,
	Velocity = function(raw)
		return velocities[key(raw)] or Vector3.zero
	end,
	WorldPosition = function(raw)
		local p = raw.Parent
		return if p and p:IsA("BasePart") then p.CFrame:PointToWorldSpace(raw.Position) else raw.Position
	end,
	WorldCFrame = function(raw)
		local p = raw.Parent
		return if p and p:IsA("BasePart") then p.CFrame * raw.CFrame else raw.CFrame
	end,
	AbsoluteSize = function(raw)
		local ok, sz = pcall(function()
			return raw.Size
		end)
		if ok and typeof(sz) == "UDim2" then
			return Vector2.new(sz.X.Scale * 1280 + sz.X.Offset, sz.Y.Scale * 720 + sz.Y.Offset)
		end
		return Vector2.new(1280, 720)
	end,
	AbsolutePosition = function()
		return Vector2.zero
	end,
	ViewportSize = function()
		return Vector2.new(1280, 720)
	end,
	UserId = function(raw)
		return pdata(raw).UserId or 0
	end,
	DisplayName = function(raw)
		return pdata(raw).DisplayName or raw.Name
	end,
	Character = function(raw)
		local c = pdata(raw).Character
		if c == nil then
			local ok, v = pcall(function()
				return raw.Character
			end)
			if ok then
				c = v
			end
		end
		return c
	end,
	FloorMaterial = function()
		return Enum.Material.Grass
	end,
	RootPart = function(raw)
		local c = raw.Parent
		return c and c:FindFirstChild("HumanoidRootPart")
	end,
	MoveDirection = function()
		return Vector3.zero
	end,
	IsPlaying = function(raw)
		return raw.Playing
	end,
	TimePosition = function()
		return 0
	end,
	PlaybackLoudness = function()
		return 0
	end,
	CurrentCamera = function()
		return camera
	end,
	CameraMode = function()
		return Enum.CameraMode.Classic
	end,
	LocalPlayer = function()
		return if M.Side == "client" then M.LocalPlayer else nil
	end,
	Terrain = function(raw)
		local t = raw:FindFirstChildOfClass("Terrain")
		if not t then
			t = Instance.new("Terrain")
			t.Parent = raw
		end
		return t
	end,
	CreatorId = function()
		return 1
	end,
	CreatorType = function()
		return Enum.CreatorType.User
	end,
	GameId = function()
		return 0
	end,
	PlaceId = function()
		return 0
	end,
	JobId = function()
		return "sim"
	end,
	TouchEnabled = function()
		return false
	end,
	KeyboardEnabled = function()
		return true
	end,
	MouseEnabled = function()
		return true
	end,
	GamepadEnabled = function()
		return false
	end,
	MouseIconEnabled = function()
		return true
	end,
	MouseDeltaSensitivity = function()
		return 1
	end,
	Playing = function()
		return false
	end,
	TextBounds = function()
		return Vector2.new(100, 20)
	end,
	ContentText = function(raw)
		return raw.Text
	end,
	Team = function()
		return nil
	end,
}
local computedSet = {
	Position = function(raw, v)
		if raw:IsA("BasePart") then
			local cf = raw.CFrame
			raw.CFrame = CFrame.fromMatrix(v, cf.XVector, cf.YVector, cf.ZVector)
		else
			raw.Position = v
		end
	end,
	Character = function(raw, v)
		pdata(raw).Character = v
	end,
	UserId = function(raw, v)
		pdata(raw).UserId = v
	end,
	DisplayName = function(raw, v)
		pdata(raw).DisplayName = v
	end,
	AssemblyLinearVelocity = function(raw, v)
		velocities[key(raw)] = v
	end,
	Velocity = function(raw, v)
		velocities[key(raw)] = v
	end,
	MouseIconEnabled = function() end,
	MouseDeltaSensitivity = function() end,
	MouseBehavior = function() end,
}

-- Propiedades de solo lectura según la base de datos de la API
local reflection = roblox.getReflectionDatabase()
local propTagsCache = {}
local function propTags(className: string, prop: string): { string }?
	local ck = className .. "." .. prop
	if propTagsCache[ck] ~= nil then
		return propTagsCache[ck] or nil
	end
	local cls = reflection:GetClass(className)
	local tags = nil
	while cls do
		local p = cls.Properties[prop]
		if p then
			tags = p.Tags
			break
		end
		cls = if cls.Superclass then reflection:GetClass(cls.Superclass) else nil
	end
	propTagsCache[ck] = tags or false
	return tags
end
local writableAnyway = { Position = true, Character = true, UserId = true, DisplayName = true, AssemblyLinearVelocity = true, Velocity = true, MouseIconEnabled = true, MouseDeltaSensitivity = true, MouseBehavior = true, Playing = true }

local proxyMeta = {}
proxyMeta.__index = function(self, k)
	local raw = rawOf[self]
	local ok, v = pcall(function()
		return raw[k]
	end)
	if ok then
		if v == nil and computed[k] then
			return wrapResult(computed[k](raw))
		end
		if type(v) == "function" then
			return function(_, ...)
				local results = table.pack(v(raw, unwrapArgs(...)))
				for i = 1, results.n do
					results[i] = wrapResult(results[i])
				end
				return table.unpack(results, 1, results.n)
			end
		end
		return wrapResult(v)
	end
	if computed[k] then
		return wrapResult(computed[k](raw))
	end
	error(tostring(v):gsub("^runtime error: ", ""), 2)
end
proxyMeta.__newindex = function(self, k, v)
	local raw = rawOf[self]
	v = unwrap(v)
	if not writableAnyway[k] then
		local tags = propTags(raw.ClassName, k)
		if tags then
			for _, t in tags do
				if t == "ReadOnly" or t == "NotScriptable" then
					error(string.format("Unable to assign property %s. Property is read only", k), 2)
				end
			end
		end
	end
	if computedSet[k] then
		computedSet[k](raw, v)
		local ok2 = pcall(function()
			raw[k] = v
		end)
		local _ = ok2
		return
	end
	local ok, err = pcall(function()
		raw[k] = v
	end)
	if not ok then
		error(tostring(err):gsub("^runtime error: ", ""), 2)
	end
	-- Cambios de Parent: ChildAdded / AncestryChanged
	if k == "Parent" then
		local t = instSignals[key(raw)]
		if t and t.AncestryChanged then
			t.AncestryChanged:Fire(raw, v)
		end
		if v then
			local pt = instSignals[key(v)]
			if pt and pt.ChildAdded then
				pt.ChildAdded:Fire(raw)
			end
		end
	end
end
proxyMeta.__tostring = function(self)
	return tostring(rawOf[self].Name)
end
proxyMeta.__eq = function(a, b)
	return rawOf[a] == rawOf[b]
end

function wrap(raw)
	if typeof(raw) ~= "Instance" then
		return raw
	end
	local k = key(raw)
	local p = proxies[k]
	if not p then
		p = setmetatable({}, proxyMeta)
		proxies[k] = p
		rawOf[p] = raw
	end
	return p
end
M.Wrap = wrap
M.Unwrap = unwrap

local function simTypeof(v)
	if type(v) == "table" and rawOf[v] then
		return "Instance"
	end
	return typeof(v)
end
M.Typeof = simTypeof

local InstanceLib = setmetatable({
	new = function(className, parent)
		local inst = Instance.new(className)
		if parent then
			inst.Parent = unwrap(parent)
		end
		return wrap(inst)
	end,
}, { __index = Instance })

-- Servicios ------------------------------------------------------------------

M.Side = "server" -- "server" | "client" (lo cambia el runner al ejecutar cada lado)
M.LocalPlayer = nil
M.Players = {}

local game = Instance.new("DataModel")
M.Game = game
local workspaceSvc = game:GetService("Workspace")
local playersSvc = game:GetService("Players")
local runSvc = game:GetService("RunService")

roblox.implementProperty("DataModel", "CreatorId", function()
	return 1
end, function() end)
roblox.implementProperty("DataModel", "CreatorType", function()
	return Enum.CreatorType.User
end, function() end)
roblox.implementProperty("DataModel", "GameId", function()
	return 0
end, function() end)
roblox.implementProperty("DataModel", "PlaceId", function()
	return 0
end, function() end)
roblox.implementProperty("DataModel", "JobId", function()
	return "sim"
end, function() end)
roblox.implementMethod("DataModel", "BindToClose", function() end)
roblox.implementMethod("DataModel", "IsLoaded", function()
	return true
end)

-- Workspace
camera.Parent = workspaceSvc
roblox.implementProperty("Workspace", "CurrentCamera", function()
	return camera
end, function() end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.clock()
end)
-- Raycast simple contra cajas alineadas de partes con CanQuery (y personajes)
local function segmentHitsBox(from, dir, cf, size)
	local lo = cf:PointToObjectSpace(from)
	local ld = cf:PointToObjectSpace(from + dir) - lo
	local half = size * 0.5
	local tMin, tMax = 0, 1
	for _, a in { { lo.X, ld.X, half.X }, { lo.Y, ld.Y, half.Y }, { lo.Z, ld.Z, half.Z } } do
		local o, d, h = a[1], a[2], a[3]
		if math.abs(d) < 1e-8 then
			if o < -h or o > h then
				return nil
			end
		else
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin, tMax = math.max(tMin, t1), math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
	local best, bestT = nil, math.huge
	local exclude = {}
	for _, e in (params and params.FilterDescendantsInstances or {}) do
		table.insert(exclude, unwrap(e))
	end
	local function excluded(inst)
		for _, e in exclude do
			if inst == e or inst:IsDescendantOf(e) then
				return true
			end
		end
		return false
	end
	for _, d in workspaceSvc:GetDescendants() do
		if d:IsA("BasePart") and d.CanQuery and d ~= camera and not excluded(d) and d.Transparency < 1 then
			local t = segmentHitsBox(origin, direction, d.CFrame, d.Size)
			if t and t < bestT then
				best, bestT = d, t
			end
		end
	end
	if best then
		local pos = origin + direction * bestT
		return { Instance = best, Position = pos, Normal = Vector3.yAxis, Material = best.Material, Distance = (direction * bestT).Magnitude }
	end
	return nil
end)
roblox.implementMethod("Workspace", "GetPartBoundsInBox", function()
	return {}
end)
roblox.implementMethod("Workspace", "GetPartsInPart", function()
	return {}
end)
roblox.implementProperty("Workspace", "Terrain", function()
	local t = workspaceSvc:FindFirstChildOfClass("Terrain")
	if not t then
		t = Instance.new("Terrain")
		t.Parent = workspaceSvc
	end
	return t
end, function() end)

-- RaycastParams
local RaycastParams = {}
RaycastParams.__index = RaycastParams
function RaycastParams.new()
	return setmetatable({ FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, IgnoreWater = false, RespectCanCollide = false, CollisionGroup = "Default" }, RaycastParams)
end
function RaycastParams:AddToFilter(list)
	for _, i in list do
		table.insert(self.FilterDescendantsInstances, i)
	end
end
M.RaycastParams = RaycastParams

-- OverlapParams
local OverlapParams = {}
OverlapParams.__index = OverlapParams
function OverlapParams.new()
	return setmetatable({ FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {} }, OverlapParams)
end
M.OverlapParams = OverlapParams

-- Players
roblox.implementProperty("Players", "LocalPlayer", function()
	return if M.Side == "client" then M.LocalPlayer else nil
end, function() end)
roblox.implementMethod("Players", "GetPlayers", function()
	return table.clone(M.Players)
end)
roblox.implementMethod("Players", "GetPlayerFromCharacter", function(_, char)
	for _, p in M.Players do
		local c = pdata(p).Character
		if c and char and key(c) == key(char) then
			return p
		end
	end
	return nil
end)
roblox.implementMethod("Players", "GetPlayerByUserId", function(_, id)
	for _, p in M.Players do
		if p.UserId == id then
			return p
		end
	end
	return nil
end)
roblox.implementMethod("Players", "GetNameFromUserIdAsync", function(_, id)
	return "User" .. id
end)
roblox.implementMethod("Players", "GetUserThumbnailAsync", function()
	return "rbxthumb://", true
end)
roblox.implementMethod("Players", "CreateHumanoidModelFromDescription", function(_, desc, rig)
	return M.BuildR15("Dummy")
end)
roblox.implementMethod("Players", "GetHumanoidDescriptionFromUserId", function()
	return Instance.new("HumanoidDescription")
end)
for _, name in { "PlayerAdded", "PlayerRemoving" } do
	signalProp("Players", name)
end

local function loadCharacter(player)
	local old = player.Character
	if old then
		getSignal(player, "CharacterRemoving"):Fire(old)
		old:Destroy()
	end
	local char = M.BuildR15(player.Name)
	player.Character = char
	pdata(player).Character = char
	-- Spawn en el lobby
	local spawn = workspaceSvc:FindFirstChild("LobbySpawn", true)
	if spawn then
		char:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
	end
	char.Parent = workspaceSvc
	getSignal(player, "CharacterAdded"):Fire(char)
	task.wait()
	return char
end
roblox.implementMethod("Player", "LoadCharacter", loadCharacter)
roblox.implementMethod("Player", "LoadCharacterAsync", loadCharacter)

function M.AddPlayer(name: string, userId: number)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = userId
	p.DisplayName = name
	local backpack = Instance.new("Backpack")
	backpack.Parent = p
	local gui = Instance.new("PlayerGui")
	gui.Parent = p
	local ps = Instance.new("PlayerScripts")
	ps.Parent = p
	p.Parent = playersSvc
	table.insert(M.Players, p)
	getSignal(playersSvc, "PlayerAdded"):Fire(p)
	return p
end
function M.RemovePlayer(p)
	p = unwrap(p)
	local i = nil
	for idx, x in M.Players do
		if key(x) == key(p) then
			i = idx
		end
	end
	if not i then
		return
	end
	table.remove(M.Players, i)
	getSignal(playersSvc, "PlayerRemoving"):Fire(p)
	task.wait()
	local c = pdata(p).Character
	if c then
		c:Destroy()
		pdata(p).Character = nil
	end
	pcall(function()
		p.Parent = nil
	end)
end

-- RunService
roblox.implementMethod("RunService", "IsServer", function()
	return M.Side == "server"
end)
roblox.implementMethod("RunService", "IsClient", function()
	return M.Side == "client"
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return M.IsStudio
end)
roblox.implementMethod("RunService", "IsRunning", function()
	return true
end)
for _, name in { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation" } do
	signalProp("RunService", name)
end
M.RenderSteps = {}
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, priority, fn)
	M.RenderSteps[name] = { Priority = priority, Fn = fn }
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
	M.RenderSteps[name] = nil
end)

-- Remotes: un solo proceso, dos "lados"
roblox.implementMethod("RemoteEvent", "FireServer", function(inst, ...)
	getSignal(inst, "OnServerEvent"):Fire(M.LocalPlayer, ...)
end)
roblox.implementMethod("RemoteEvent", "FireClient", function(inst, player, ...)
	if M.LocalPlayer and player and key(player) == key(M.LocalPlayer) then
		getSignal(inst, "OnClientEvent"):Fire(...)
	end
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(inst, ...)
	getSignal(inst, "OnClientEvent"):Fire(...)
end)
signalProp("RemoteEvent", "OnServerEvent")
signalProp("RemoteEvent", "OnClientEvent")
local invokes = {} -- [id] = fn
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(inst)
	return invokes[key(inst)]
end, function(inst, fn)
	invokes[key(inst)] = fn
end)
roblox.implementProperty("RemoteFunction", "OnClientInvoke", function() end, function() end)
roblox.implementMethod("RemoteFunction", "InvokeServer", function(inst, ...)
	local fn = invokes[key(inst)]
	if not fn then
		error("RemoteFunction " .. inst.Name .. " sin OnServerInvoke")
	end
	local args = table.pack(...)
	for i = 1, args.n do
		if typeof(args[i]) == "Instance" then
			args[i] = M.Wrap(args[i])
		end
	end
	return fn(M.Wrap(M.LocalPlayer), table.unpack(args, 1, args.n))
end)
signalProp("BindableEvent", "Event")
roblox.implementMethod("BindableEvent", "Fire", function(inst, ...)
	getSignal(inst, "Event"):Fire(...)
end)

-- TweenService: aplica el estado final al instante y avisa Completed
roblox.implementMethod("TweenService", "Create", function(_, inst, info, props)
	local tw = { Completed = Signal.new("Tween.Completed"), PlaybackState = Enum.PlaybackState.Begin }
	function tw:Play()
		for k, v in props do
			inst[k] = v
		end
		task.delay(math.min(info and info.Time or 0, 0.05), function()
			tw.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tw:Cancel() end
	function tw:Pause() end
	return tw
end)
local TweenInfo = {}
TweenInfo.__index = TweenInfo
function TweenInfo.new(time, style, dir, rep, rev, delay)
	return setmetatable({ Time = time or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rep or 0, Reverses = rev or false, DelayTime = delay or 0 }, TweenInfo)
end
M.TweenInfo = TweenInfo

-- Debris
roblox.implementMethod("Debris", "AddItem", function(_, inst, t)
	task.delay(t or 10, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end)

-- UserInputService
local uis = game:GetService("UserInputService")
for _, name in { "InputBegan", "InputEnded", "InputChanged", "TouchTap", "JumpRequest", "WindowFocused", "WindowFocusReleased" } do
	signalProp("UserInputService", name)
end
roblox.implementProperty("UserInputService", "TouchEnabled", function()
	return false
end, function() end)
roblox.implementProperty("UserInputService", "KeyboardEnabled", function()
	return true
end, function() end)
roblox.implementProperty("UserInputService", "MouseEnabled", function()
	return true
end, function() end)
roblox.implementProperty("UserInputService", "GamepadEnabled", function()
	return false
end, function() end)
M.MouseButtons = {}
roblox.implementMethod("UserInputService", "IsMouseButtonPressed", function(_, b)
	return M.MouseButtons[b] == true
end)
M.Keys = {}
roblox.implementMethod("UserInputService", "IsKeyDown", function(_, k)
	return M.Keys[k] == true
end)
roblox.implementMethod("UserInputService", "GetMouseLocation", function()
	return Vector2.new(640, 360)
end)
roblox.implementMethod("UserInputService", "GetLastInputType", function()
	return Enum.UserInputType.MouseMovement
end)

-- ContextActionService
M.Actions = {}
roblox.implementMethod("ContextActionService", "BindAction", function(_, name, fn, touch, ...)
	M.Actions[name] = { Fn = fn, Keys = { ... } }
end)
roblox.implementMethod("ContextActionService", "BindActionAtPriority", function(_, name, fn, touch, prio, ...)
	M.Actions[name] = { Fn = fn, Keys = { ... } }
end)
roblox.implementMethod("ContextActionService", "UnbindAction", function(_, name)
	M.Actions[name] = nil
end)
roblox.implementMethod("ContextActionService", "SetPosition", function() end)
roblox.implementMethod("ContextActionService", "SetTitle", function() end)
roblox.implementMethod("ContextActionService", "SetImage", function() end)
function M.FireAction(name: string, state, inputType)
	local a = M.Actions[name]
	if not a then
		report("FireAction", "acción no vinculada: " .. name)
		return
	end
	local input = { UserInputType = inputType or Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown, UserInputState = state, Delta = Vector3.zero, Position = Vector3.zero }
	return safe("acción " .. name, a.Fn, name, state, input)
end

-- CollectionService: tabla propia (Instance:AddTag nativo tiene prioridad)
local tagged: { [string]: { Instance } } = {}
local collectionSvc = {}
local collectionSignals = {}
local function tagSignal(kind, tag)
	local k = kind .. ":" .. tag
	if not collectionSignals[k] then
		collectionSignals[k] = Signal.new("CollectionService." .. k)
	end
	return collectionSignals[k]
end
local function findTagged(list, inst)
	for i, x in list do
		if key(x) == key(inst) then
			return i
		end
	end
	return nil
end
function collectionSvc:AddTag(inst, tag)
	inst = unwrap(inst)
	tagged[tag] = tagged[tag] or {}
	if not findTagged(tagged[tag], inst) then
		table.insert(tagged[tag], inst)
		tagSignal("Added", tag):Fire(inst)
	end
end
function collectionSvc:RemoveTag(inst, tag)
	inst = unwrap(inst)
	local list = tagged[tag]
	local i = list and findTagged(list, inst)
	if i then
		table.remove(list, i)
		tagSignal("Removed", tag):Fire(inst)
	end
end
function collectionSvc:HasTag(inst, tag)
	inst = unwrap(inst)
	return tagged[tag] ~= nil and findTagged(tagged[tag], inst) ~= nil
end
function collectionSvc:GetTagged(tag)
	return table.clone(tagged[tag] or {})
end
function collectionSvc:GetTags(inst)
	local out = {}
	for tag, list in tagged do
		if findTagged(list, unwrap(inst)) then
			table.insert(out, tag)
		end
	end
	return out
end
function collectionSvc:GetInstanceAddedSignal(tag)
	return tagSignal("Added", tag)
end
function collectionSvc:GetInstanceRemovedSignal(tag)
	return tagSignal("Removed", tag)
end

-- "game" que ven los scripts: igual que el DataModel pero con servicios propios
local gameProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" or k == "FindService" then
			return function(_, name)
				if name == "CollectionService" then
					return collectionSvc
				end
				return M.Wrap(game:GetService(name))
			end
		end
		if computed[k] then
			return M.Wrap(computed[k](game))
		end
		local v = game[k]
		if type(v) == "function" then
			return function(_, ...)
				return M.Wrap(v(game, unwrapArgs(...)))
			end
		end
		return M.Wrap(v)
	end,
	__newindex = function(_, k, v)
		game[k] = v
	end,
})
M.GameProxy = gameProxy

-- DataStoreService (en memoria)
M.DataStores = {}
local function makeStore(name)
	local store = M.DataStores[name]
	if store then
		return store
	end
	local data = {}
	store = {
		_data = data,
		GetAsync = function(_, key)
			return data[key]
		end,
		SetAsync = function(_, key, value)
			data[key] = value
		end,
		RemoveAsync = function(_, key)
			data[key] = nil
		end,
		UpdateAsync = function(_, key, fn)
			local new = fn(data[key])
			if new ~= nil then
				data[key] = new
			end
			return data[key]
		end,
		IncrementAsync = function(_, key, n)
			data[key] = (data[key] or 0) + (n or 1)
			return data[key]
		end,
		GetSortedAsync = function()
			local list = {}
			for k, v in data do
				table.insert(list, { key = k, value = v })
			end
			table.sort(list, function(a, b)
				return a.value > b.value
			end)
			return { GetCurrentPage = function()
				return list
			end, IsFinished = true, AdvanceToNextPageAsync = function() end }
		end,
	}
	M.DataStores[name] = store
	return store
end
roblox.implementMethod("DataStoreService", "GetDataStore", function(_, name)
	return makeStore(name)
end)
roblox.implementMethod("DataStoreService", "GetOrderedDataStore", function(_, name)
	return makeStore("ordered:" .. name)
end)

-- MarketplaceService
local receiptHandler = nil
roblox.implementProperty("MarketplaceService", "ProcessReceipt", function()
	return receiptHandler
end, function(_, fn)
	receiptHandler = fn
end)
M.GetReceiptHandler = function()
	return receiptHandler
end
for _, name in { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished" } do
	signalProp("MarketplaceService", name)
end
M.Prompts = {}
roblox.implementMethod("MarketplaceService", "PromptProductPurchase", function(_, player, id)
	table.insert(M.Prompts, { Player = player, Product = id })
end)
roblox.implementMethod("MarketplaceService", "PromptGamePassPurchase", function(_, player, id)
	table.insert(M.Prompts, { Player = player, Pass = id })
end)
roblox.implementMethod("MarketplaceService", "UserOwnsGamePassAsync", function()
	return false
end)
roblox.implementMethod("MarketplaceService", "GetProductInfo", function()
	return { PriceInRobux = 10, Name = "x" }
end)

-- PathfindingService: camino recto
roblox.implementMethod("PathfindingService", "CreatePath", function()
	local path = { Status = Enum.PathStatus.NoPath, _wps = {}, Blocked = Signal.new("Path.Blocked") }
	function path:ComputeAsync(from, to)
		self._wps = { { Position = from, Action = Enum.PathWaypointAction.Walk }, { Position = to, Action = Enum.PathWaypointAction.Walk } }
		self.Status = Enum.PathStatus.Success
	end
	function path:GetWaypoints()
		return self._wps
	end
	function path:Destroy() end
	return path
end)

signalProp("LogService", "MessageOut")
-- StarterGui / otros
roblox.implementMethod("StarterGui", "SetCoreGuiEnabled", function() end)
roblox.implementMethod("StarterGui", "SetCore", function() end)
roblox.implementMethod("StarterGui", "GetCoreGuiEnabled", function()
	return true
end)
roblox.implementMethod("TextChatService", "DisplayBubble", function() end)
roblox.implementMethod("SoundService", "PlayLocalSound", function() end)
roblox.implementMethod("TeleportService", "Teleport", function() end)
roblox.implementMethod("HttpService", "GenerateGUID", function()
	return "GUID"
end)
roblox.implementMethod("HttpService", "JSONEncode", function(_, t)
	return require("@lune/serde").encode("json", t)
end)
roblox.implementMethod("HttpService", "JSONDecode", function(_, s)
	return require("@lune/serde").decode("json", s)
end)
roblox.implementMethod("BadgeService", "AwardBadge", function() end)
roblox.implementMethod("MessagingService", "SubscribeAsync", function()
	return { Disconnect = function() end }
end)
roblox.implementMethod("MessagingService", "PublishAsync", function() end)
roblox.implementMethod("Chat", "Chat", function() end)
roblox.implementMethod("LocalizationService", "GetTranslatorForPlayer", function() end)
roblox.implementMethod("Lighting", "GetMinutesAfterMidnight", function(inst)
	return inst.ClockTime * 60
end)
roblox.implementMethod("Lighting", "SetMinutesAfterMidnight", function(inst, m)
	inst.ClockTime = m / 60
end)

-- Globales que faltan ---------------------------------------------------------

local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ _s = (seed or os.clock() * 1000) % 2147483647 }, Random)
end
local function nextRaw(self)
	self._s = (self._s * 48271) % 2147483647
	return self._s / 2147483647
end
function Random:NextNumber(a, b)
	local r = nextRaw(self)
	if a == nil then
		return r
	end
	return a + (b - a) * r
end
function Random:NextInteger(a, b)
	return math.floor(a + nextRaw(self) * (b - a + 1))
end
function Random:NextUnitVector()
	return Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1)).Unit
end
function Random:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
M.Random = Random

local mathEx = setmetatable({
	noise = function(x, y, z)
		return (math.sin((x or 0) * 12.9898 + (y or 0) * 78.233 + (z or 0) * 37.719) * 43758.5453) % 1 - 0.5
	end,
}, { __index = math })

-- CFrame.lookAt de Lune devuelve la rotación reflejada: versión correcta
local function lookAt(at, target, up)
	up = up or Vector3.yAxis
	local z = (at - target)
	if z.Magnitude < 1e-6 then
		return CFrame.new(at)
	end
	z = z.Unit
	if math.abs(z:Dot(up)) > 0.999 then
		up = Vector3.new(0, 0, 1)
	end
	local x = up:Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(at, x, y, z)
end
local CFrameLib = setmetatable({
	lookAt = lookAt,
	lookAlong = function(at, dir, up)
		return lookAt(at, at + dir, up)
	end,
	new = function(...)
		local n = select("#", ...)
		if n == 2 and typeof(select(1, ...)) == "Vector3" and typeof(select(2, ...)) == "Vector3" then
			return lookAt(...)
		end
		return CFrame.new(...)
	end,
}, { __index = CFrame })

M.CFrame = CFrameLib

local function makeEnv(scriptInst, requireFn, extra)
	local env = {
		game = gameProxy,
		workspace = wrap(workspaceSvc),
		script = wrap(scriptInst),
		require = requireFn,
		Instance = InstanceLib,
		Enum = Enum,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrameLib,
		Color3 = Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		BrickColor = roblox.BrickColor,
		Ray = roblox.Ray,
		Rect = roblox.Rect,
		Region3 = roblox.Region3,
		Font = roblox.Font,
		PhysicalProperties = roblox.PhysicalProperties,
		TweenInfo = TweenInfo,
		Random = Random,
		RaycastParams = RaycastParams,
		OverlapParams = OverlapParams,
		task = task,
		math = mathEx,
		tick = os.clock,
		time = os.clock,
		elapsedTime = os.clock,
		wait = task.wait,
		spawn = task.spawn,
		delay = task.delay,
		typeof = simTypeof,
		warn = function(...)
			local parts = {}
			for _, v in { ... } do
				table.insert(parts, tostring(v))
			end
			local msg = table.concat(parts, " ")
			table.insert(M.Log, "WARN " .. msg)
			print("\27[33m[warn]\27[0m " .. msg)
		end,
		print = function(...)
			local parts = {}
			for _, v in { ... } do
				table.insert(parts, tostring(v))
			end
			table.insert(M.Log, table.concat(parts, " "))
			if M.Verbose then
				print(...)
			end
		end,
	}
	for _, k in { "assert", "error", "getmetatable", "setmetatable", "ipairs", "pairs", "next", "pcall", "xpcall", "rawequal", "rawget", "rawset", "rawlen", "select", "tonumber", "tostring", "type", "unpack", "string", "table", "os", "utf8", "coroutine", "debug", "bit32", "buffer", "_G", "_VERSION" } do
		env[k] = _G[k] or (getfenv and getfenv()[k])
	end
	env.string = string
	env.table = table
	env.os = os
	env.coroutine = coroutine
	-- debug.traceback nativo falla dentro de luau.load: versión tolerante
	env.debug = setmetatable({
		traceback = function(a, b, c)
			if type(a) == "thread" then
				return tostring(b)
			end
			local ok, r = pcall(debug.traceback, a, b)
			return if ok then r else tostring(a)
		end,
	}, { __index = debug })
	env.utf8 = utf8
	env.bit32 = bit32
	env.buffer = buffer
	env.shared = M.Shared or {}
	M.Shared = env.shared
	env._G = M.Shared
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return env
end

-- require(ModuleScript) con caché por lado
function M.MakeRequire(side: string)
	local cache = {}
	local loading = {}
	local function req(target)
		if type(target) == "string" then
			return require(target)
		end
		target = unwrap(target)
		if typeof(target) ~= "Instance" or not target:IsA("ModuleScript") then
			error("require: se esperaba un ModuleScript, recibido " .. tostring(target))
		end
		if cache[key(target)] ~= nil then
			return cache[key(target)]
		end
		if loading[key(target)] then
			error("require cíclico: " .. target:GetFullName())
		end
		loading[key(target)] = true
		local env = makeEnv(target, req)
		local fn = luau.load(target.Source, { debugName = side .. ":" .. target:GetFullName(), environment = env })
		local result = fn()
		if result == nil then
			error("el módulo no devolvió nada: " .. target:GetFullName())
		end
		cache[key(target)] = result
		loading[key(target)] = nil
		return result
	end
	return req
end

M.Require = {}
function M.RunScript(scriptInst, side: string)
	M.Side = side
	local req = M.MakeRequire(side)
	M.Require[side] = req
	local env = makeEnv(scriptInst, req)
	local fn = luau.load(scriptInst.Source, { debugName = side .. ":" .. scriptInst:GetFullName(), environment = env })
	local ok, err = xpcall(fn, tb)
	if not ok then
		report("script " .. scriptInst:GetFullName(), err)
	end
	return ok
end

-- Avance del mundo: física mínima (bots que se mueven) y vida
function M.Step(dt: number)
	pollAttributes()
	for id, hum in humanoids do
		local char = hum.Parent
		if not char or not char.Parent then
			humanoids[id] = nil
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local target = moveTargets[key(hum)]
			if target then
				local delta = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
				if delta.Magnitude < 0.5 then
					moveTargets[key(hum)] = nil
					getSignal(hum, "MoveToFinished"):Fire(true)
				else
					local step = delta.Unit * math.min(hum.WalkSpeed * dt, delta.Magnitude)
					if not root.Anchored then
						char:PivotTo(char:GetPivot() + step)
					end
				end
			else
				local v = velocities[key(root)]
				if v and v.Magnitude > 0 and not root.Anchored then
					char:PivotTo(char:GetPivot() + v * dt)
				end
			end
		end
		if hum.Health <= 0 and not hum:GetAttribute("__died") then
			hum:SetAttribute("__died", true)
			getSignal(hum, "Died"):Fire()
		end
	end
	getSignal(runSvc, "Stepped"):Fire(os.clock(), dt)
	getSignal(runSvc, "Heartbeat"):Fire(dt)
	if M.Side ~= "server" or M.ClientRunning then
		getSignal(runSvc, "RenderStepped"):Fire(dt)
		local list = {}
		for name, s in M.RenderSteps do
			table.insert(list, { Name = name, P = s.Priority, Fn = s.Fn })
		end
		table.sort(list, function(a, b)
			return a.P < b.P
		end)
		for _, s in list do
			safe("RenderStep " .. s.Name, s.Fn, dt)
		end
	end
end

-- Correr N segundos de simulación (tiempo real) a ~30 fps
function M.Run(seconds: number)
	local t0 = os.clock()
	local last = t0
	while os.clock() - t0 < seconds do
		task.wait(1 / 30)
		local now = os.clock()
		M.Step(now - last)
		last = now
	end
end

return M
