--!strict
-- Manejo del arma en primera persona: viewmodel con sway/bob/recoil, mira con
-- zoom variable, aguantar respiración, dispersión por movimiento, recarga,
-- sprint, agacharse y deslizarse, ranura 2 (cuchillo mariposa con animación de
-- reposo) y controles táctiles.
--
-- El estado "armado" llega por tres vías (atributos del Player, evento Armed y
-- sondeo por frame) para que el duelo arranque aunque una falle.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Weapons = require(Shared.Config.Weapons)
local Ballistics = require(Shared.Ballistics)
local GunBuilder = require(Shared.GunBuilder)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local EffectsController = require(script.Parent.EffectsController)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local BASE_FOV = 70
local WALK_SPEED = 16
local SPRINT_SPEED = 23
local BREATH_DURATION = 4
local BREATH_RECOVER = 0.25

local WeaponController = {}
WeaponController.OnFired = nil :: ((spread: number) -> ())?
WeaponController.OnScopeChanged = nil :: ((boolean) -> ())?

local rng = Random.new()
local weapon: Weapons.Weapon = Weapons.Get(Weapons.Default)
local viewmodel: Model? = nil -- rifle
local knifeModel: Model? = nil -- cuchillo
local equippedSkin = "Default"

local wantScope = false
local zoomIndex = 1
local lastFire = 0
local lastMelee = 0
local holdingBreath = false
local sprinting = false
local triggerHeld = false
local rescopeAfterBolt = false

-- Postura
local crouched = false
local sliding = false
local slideEnd = 0
local slideDir = Vector3.zero
local baseHip: number? = nil

-- Animaciones
local fovKick = 0
local recoil = 0
local recoilVel = 0
local swayOffset = CFrame.identity
local bobTime = 0
local mouseDelta = Vector2.zero
local appliedPitch, appliedYaw, appliedRoll = 0, 0, 0
local meleeAnim = 0 -- 0..1 progreso de la cuchillada
local flipStart = -10 -- instante del último giro de mariposa
local nextFlip = 0
local lastPoll = 0

local scopeBlur = Instance.new("BlurEffect")
scopeBlur.Name = "SD_ScopeBlur"
scopeBlur.Size = 0
scopeBlur.Parent = camera

local function settings()
	local d = ClientState.Data
	return d and d.Settings or { Sensitivity = 1, ScopeSensitivity = 0.55, ToggleScope = false }
end

local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function inputBlocked(): boolean
	return ClientState.MenuOpen == true
end

-- Viewmodels -------------------------------------------------------------------

local function destroyViewmodels()
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
	if knifeModel then
		knifeModel:Destroy()
		knifeModel = nil
	end
end

local function prepareModel(m: Model, name: string)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CastShadow = false
			p.CanQuery = false
			p.CanCollide = false
			p.Anchored = true
		end
	end
	m.Name = name
	m.Parent = camera
end

local function buildViewmodels()
	destroyViewmodels()
	local d = ClientState.Data
	equippedSkin = d and d.Equipped.Skin or "Default"
	local ok1, err1 = pcall(function()
		local vm = GunBuilder.Build(weapon.Id, equippedSkin)
		GunBuilder.AddArms(vm, player.Character)
		prepareModel(vm, "Viewmodel")
		viewmodel = vm
	end)
	if not ok1 then
		warn("[SniperDuels] viewmodel del rifle:", err1)
	end
	local ok2, err2 = pcall(function()
		local km = GunBuilder.BuildKnife(equippedSkin)
		GunBuilder.AddKnifeArm(km, player.Character)
		prepareModel(km, "KnifeViewmodel")
		knifeModel = km
	end)
	if not ok2 then
		warn("[SniperDuels] viewmodel del cuchillo:", err2)
	end
end

-- Mira -----------------------------------------------------------------------------

local function setScoped(scoped: boolean)
	if ClientState.Scoped == scoped then
		return
	end
	ClientState.Scoped = scoped
	Net.Event("ScopeState"):FireServer(scoped)
	if scoped then
		EffectsController.PlaySound("ScopeIn", 0.5)
	end
	if WeaponController.OnScopeChanged then
		WeaponController.OnScopeChanged(scoped)
	end
end

local function currentSpread(): number
	local hum = humanoid()
	local p = ClientState.ScopeProgress
	local spread = weapon.HipSpread + (weapon.ScopedSpread - weapon.HipSpread) * p
	if hum then
		local root = hum.RootPart
		local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
		if speed > 2 then
			spread += weapon.MoveSpreadAdd * math.clamp(speed / WALK_SPEED, 0, 1.5)
		end
		if hum.FloorMaterial == Enum.Material.Air then
			spread += weapon.AirSpreadAdd
		end
	end
	if sliding then
		spread += 4
	elseif crouched then
		spread *= 0.6
	end
	return spread
end
WeaponController.CurrentSpread = currentSpread

-- Acciones ---------------------------------------------------------------------------

local function reload()
	if not ClientState.Armed or ClientState.Slot ~= 1 or ClientState.Reloading or ClientState.Mag >= weapon.MagSize then
		return
	end
	Net.Event("Reload"):FireServer()
	EffectsController.PlaySound("Reload", 0.6)
	setScoped(false)
end

local function ejectShell()
	local vm = viewmodel
	local ej = vm and vm:FindFirstChild("Ejection", true) :: Attachment?
	if ej and not ClientState.Scoped then
		EffectsController.EjectShell(ej.WorldCFrame)
	end
end

local function fire()
	if not ClientState.CanShoot() or ClientState.Reloading or ClientState.Slot ~= 1 or inputBlocked() then
		return
	end
	if ClientState.Mag <= 0 then
		reload()
		return
	end
	local now = os.clock()
	if now - lastFire < weapon.FireCooldown then
		return
	end
	lastFire = now

	local spread = currentSpread()
	local camCf = camera.CFrame
	local origin = camCf.Position
	local aimDir = camCf.LookVector
	-- Si la cámara no está en la cabeza (tercera persona), disparar desde la
	-- cabeza hacia el punto al que apunta la mira
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	if head and (head.Position - origin).Magnitude > 4 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Model, camera }
		local hit = workspace:Raycast(origin, aimDir * 3000, params)
		local target = if hit then hit.Position else origin + aimDir * 3000
		origin = head.Position
		aimDir = (target - origin).Unit
	end
	-- El vaivén de la mira desvía el tiro igual que mueve la retícula
	local sway = ClientState.Sway or Vector2.zero
	if ClientState.Scoped and (sway.X ~= 0 or sway.Y ~= 0) then
		aimDir = (CFrame.lookAt(Vector3.zero, aimDir) * CFrame.Angles(math.rad(sway.Y), math.rad(sway.X), 0)).LookVector
	end
	local direction = Ballistics.ApplySpread(aimDir, spread, rng)
	Net.Event("Fire"):FireServer(origin, direction, workspace:GetServerTimeNow())

	ClientState.Mag -= 1
	ClientState.AmmoChanged:Fire()

	local muzzlePos = origin
	if viewmodel and not ClientState.Scoped then
		local m = viewmodel:FindFirstChild("Muzzle", true) :: Attachment?
		if m then
			muzzlePos = m.WorldPosition
		end
	end
	if not ClientState.Scoped then
		EffectsController.MuzzleFlash(muzzlePos, direction, Color3.fromRGB(255, 200, 100))
	end
	EffectsController.Shake(if ClientState.Scoped then 1.0 else 1.6)
	fovKick = if ClientState.Scoped then 1.5 else 5
	EffectsController.Tracer(origin, direction, weapon.Id, equippedSkin, if ClientState.Scoped then camCf.Position + camCf.UpVector * -0.3 else muzzlePos)
	EffectsController.PlaySound("Fire", 0.9)

	recoilVel += weapon.RecoilPitch * 18
	-- Golpe de cámara único (si el script de cámara lo conserva, se nota; si no, no molesta)
	pcall(function()
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(weapon.RecoilPitch * (if ClientState.Scoped then 0.25 else 0.5)), math.rad(rng:NextNumber(-0.3, 0.3)), 0)
	end)
	if weapon.FireCooldown < 0.8 then
		ejectShell()
	end
	if WeaponController.OnFired then
		WeaponController.OnFired(spread)
	end

	-- Cerrojo: salir de la mira mientras se acciona y volver a entrar
	if weapon.FireCooldown >= 0.8 then
		rescopeAfterBolt = ClientState.Scoped or wantScope
		task.delay(0.12, function()
			if os.clock() - lastFire < weapon.FireCooldown then
				wantScope = false
				EffectsController.PlaySound("Bolt", 0.6)
			end
		end)
		task.delay(weapon.FireCooldown * 0.45, ejectShell)
		task.delay(weapon.FireCooldown, function()
			if rescopeAfterBolt and ClientState.Armed and ClientState.Slot == 1 then
				local s = settings()
				if s.ToggleScope or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
					wantScope = true
				end
			end
			rescopeAfterBolt = false
		end)
	end
end

local function melee()
	if not ClientState.CanShoot() or ClientState.Slot ~= 2 or inputBlocked() then
		return
	end
	local now = os.clock()
	if now - lastMelee < Weapons.Melee.Cooldown then
		return
	end
	lastMelee = now
	meleeAnim = 1
	Net.Event("Melee"):FireServer()
	EffectsController.Shake(0.6)
	EffectsController.PlaySound("Knife", 0.7)
end

function WeaponController.SetSlot(slot: number)
	if not ClientState.Armed or inputBlocked() then
		return
	end
	slot = if slot == 2 then 2 else 1
	if ClientState.Slot == slot then
		return
	end
	ClientState.Slot = slot
	wantScope = false
	setScoped(false)
	nextFlip = os.clock() + 1
	Net.Event("SetSlot"):FireServer(slot)
	ClientState.AmmoChanged:Fire()
end

-- Postura ------------------------------------------------------------------------

local slideForce: LinearVelocity? = nil
local cameraDrop = 0 -- bajada actual de la cámara (suavizada)

local function setCrouch(on: boolean)
	local hum = humanoid()
	if not hum then
		return
	end
	if baseHip == nil then
		baseHip = hum.HipHeight
	end
	crouched = on
	-- Bajar un poco la cadera (y la hitbox con ella) sin hundir las piernas
	hum.HipHeight = if on then math.max((baseHip :: number) - GameConfig.CrouchHipDrop * 0.5, 0.2) else (baseHip :: number)
	ClientState.Crouched = on
end

local function stopSlide()
	sliding = false
	if slideForce then
		local att = slideForce.Attachment0
		slideForce:Destroy()
		if att then
			att:Destroy()
		end
		slideForce = nil
	end
end

local function startSlide(root: BasePart, dir: Vector3)
	stopSlide()
	sliding = true
	slideEnd = os.clock() + GameConfig.SlideDuration
	slideDir = dir
	-- Fuerza física: el Humanoid no puede "frenarla" como hacía con la velocidad
	local att = Instance.new("Attachment")
	att.Name = "SD_SlideAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SD_Slide"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.MaxForce = 60000
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * GameConfig.SlideSpeed
	lv.Parent = root
	slideForce = lv
end

local function tryCrouchOrSlide()
	local hum = humanoid()
	local root = hum and hum.RootPart
	if not hum or not root or inputBlocked() then
		return
	end
	local vel = root.AssemblyLinearVelocity
	local planar = Vector3.new(vel.X, 0, vel.Z)
	-- Corriendo (sprint) + agacharse = deslizarse tipo Call of Duty
	-- Si va corriendo hacia algún lado (aunque la velocidad aún no sea máxima)
	local moveDir = hum.MoveDirection
	local dir = if planar.Magnitude > 4 then planar.Unit elseif moveDir.Magnitude > 0.1 then Vector3.new(moveDir.X, 0, moveDir.Z).Unit else nil
	if sprinting and not crouched and dir and hum.FloorMaterial ~= Enum.Material.Air then
		startSlide(root, dir)
		setCrouch(true)
		EffectsController.Shake(0.4)
		EffectsController.PlaySound("Slide", 0.6)
		return
	end
	setCrouch(not crouched)
end

-- Armado ---------------------------------------------------------------------------

local function forceFirstPerson()
	pcall(function()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end)
	pcall(function()
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	end)
end

local function releaseCamera()
	pcall(function()
		player.CameraMode = Enum.CameraMode.Classic
	end)
	pcall(function()
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 20
	end)
end

local bindActions
local unbindActions

local function onArmedChanged()
	if ClientState.Armed then
		weapon = Weapons.Get(ClientState.WeaponId)
		zoomIndex = 1
		forceFirstPerson()
		pcall(function()
			UserInputService.MouseIconEnabled = false
		end)
		buildViewmodels()
		local ok, err = pcall(bindActions)
		if not ok then
			warn("[SniperDuels] bindActions:", err)
		end
	else
		destroyViewmodels()
		wantScope = false
		setScoped(false)
		ClientState.ScopeProgress = 0
		ClientState.Slot = 1
		camera.FieldOfView = BASE_FOV
		scopeBlur.Size = 0
		recoil, recoilVel = 0, 0
		appliedPitch, appliedYaw, appliedRoll = 0, 0, 0
		stopSlide()
		if crouched then
			setCrouch(false)
		end
		local h = humanoid()
		if h then
			h.CameraOffset = Vector3.zero
		end
		cameraDrop = 0
		releaseCamera()
		pcall(function()
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseDeltaSensitivity = 1
		end)
		pcall(unbindActions)
	end
end

local function applyArmState(weaponId: string?, mag: number?, reloading: boolean?, slot: number?)
	local wasArmed = ClientState.Armed
	local prevWeapon = ClientState.WeaponId
	ClientState.Armed = weaponId ~= nil and weaponId ~= ""
	ClientState.Mag = mag or 0
	ClientState.Reloading = reloading == true
	ClientState.WeaponId = weaponId or ""
	if slot then
		ClientState.Slot = slot
	end
	if ClientState.Armed ~= wasArmed or (ClientState.Armed and prevWeapon ~= ClientState.WeaponId) then
		local ok, err = pcall(onArmedChanged)
		if not ok then
			warn("[SniperDuels] onArmedChanged:", err)
		end
	end
	ClientState.AmmoChanged:Fire()
end

local function syncFromAttributes()
	applyArmState(
		player:GetAttribute("SD_Weapon") :: string?,
		player:GetAttribute("SD_Mag") :: number?,
		player:GetAttribute("SD_Reloading") :: boolean?,
		player:GetAttribute("SD_Slot") :: number?
	)
end

-- Entrada --------------------------------------------------------------------------

function bindActions()
	local touch = UserInputService.TouchEnabled

	ContextActionService:BindAction("SD_Fire", function(_, state)
		if state == Enum.UserInputState.Begin then
			triggerHeld = true
			if ClientState.Slot == 2 then
				melee()
			else
				fire()
			end
		elseif state == Enum.UserInputState.End then
			triggerHeld = false
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction("SD_Scope", function(_, state, input)
		if ClientState.Slot ~= 1 or inputBlocked() then
			return Enum.ContextActionResult.Pass
		end
		local toggle = settings().ToggleScope or input.UserInputType == Enum.UserInputType.Touch
		if state == Enum.UserInputState.Begin then
			wantScope = if toggle then not wantScope else true
		elseif state == Enum.UserInputState.End and not toggle then
			wantScope = false
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)

	ContextActionService:BindAction("SD_Reload", function(_, state)
		if state == Enum.UserInputState.Begin then
			reload()
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

	ContextActionService:BindAction("SD_Zoom", function(_, state, input)
		if ClientState.Slot ~= 1 then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin or input.UserInputType == Enum.UserInputType.MouseWheel then
			if #weapon.ZoomFOV > 1 then
				zoomIndex = zoomIndex % #weapon.ZoomFOV + 1
			end
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.KeyCode.Z, Enum.KeyCode.ButtonY, Enum.UserInputType.MouseWheel)

	ContextActionService:BindAction("SD_Breath", function(_, state)
		local active = state == Enum.UserInputState.Begin
		if state == Enum.UserInputState.Begin or state == Enum.UserInputState.End then
			holdingBreath = active
			sprinting = active
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	ContextActionService:BindAction("SD_Crouch", function(_, state)
		if state == Enum.UserInputState.Begin then
			tryCrouchOrSlide()
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)

	ContextActionService:BindAction("SD_Slot1", function(_, state)
		if state == Enum.UserInputState.Begin then
			WeaponController.SetSlot(1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.DPadLeft)
	ContextActionService:BindAction("SD_Slot2", function(_, state)
		if state == Enum.UserInputState.Begin then
			WeaponController.SetSlot(2)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Two, Enum.KeyCode.DPadRight)
	ContextActionService:BindAction("SD_SwapSlot", function(_, state)
		if state == Enum.UserInputState.Begin then
			WeaponController.SetSlot(if ClientState.Slot == 1 then 2 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)

	if touch then
		local layout = {
			SD_Fire = { UDim2.new(1, -110, 1, -190), "DISPARAR" },
			SD_Scope = { UDim2.new(1, -200, 1, -130), "MIRA" },
			SD_Reload = { UDim2.new(1, -95, 1, -280), "R" },
			SD_Zoom = { UDim2.new(1, -190, 1, -230), "ZOOM" },
			SD_Crouch = { UDim2.new(1, -290, 1, -90), "AGACHAR" },
			SD_SwapSlot = { UDim2.new(1, -290, 1, -170), "CAMBIAR" },
		}
		for name, info in layout do
			ContextActionService:SetPosition(name, info[1])
			ContextActionService:SetTitle(name, info[2])
		end
	end
end

function unbindActions()
	for _, name in { "SD_Fire", "SD_Scope", "SD_Reload", "SD_Zoom", "SD_Breath", "SD_Crouch", "SD_Slot1", "SD_Slot2", "SD_SwapSlot" } do
		ContextActionService:UnbindAction(name)
	end
	triggerHeld = false
	holdingBreath = false
	sprinting = false
end

-- Bucle por frame -------------------------------------------------------------------

local function updateKnifeViewmodel(dt: number, hum: Humanoid?, planar: number)
	local km = knifeModel
	if not km then
		return
	end
	local t = os.clock()
	meleeAnim = math.max(0, meleeAnim - dt * 4)
	bobTime += dt * (planar / WALK_SPEED) * 9
	local bobAmt = math.clamp(planar / WALK_SPEED, 0, 1.4)
	local bob = CFrame.new(math.sin(bobTime) * 0.05 * bobAmt, math.abs(math.cos(bobTime)) * 0.04 * bobAmt, 0)
	local md = mouseDelta
	mouseDelta = Vector2.zero
	swayOffset = swayOffset:Lerp(CFrame.Angles(math.rad(math.clamp(-md.Y * 0.08, -4, 4)), math.rad(math.clamp(-md.X * 0.08, -4, 4)), 0), math.clamp(dt * 10, 0, 1))
	-- Postura base: cuchillo abajo a la derecha, hoja hacia delante
	local base = CFrame.new(0.75, -0.7, -1.4) * CFrame.Angles(math.rad(-10), math.rad(-20), math.rad(15))
	-- Cuchillada: empujón hacia delante con giro
	local stab = CFrame.new(-0.25 * meleeAnim, 0.15 * meleeAnim, -0.9 * math.sin(meleeAnim * math.pi)) * CFrame.Angles(math.rad(-25 * meleeAnim), math.rad(20 * meleeAnim), 0)
	-- Giro de mariposa en reposo cada pocos segundos
	if t >= nextFlip and meleeAnim <= 0 and planar < 2 then
		flipStart = t
		nextFlip = t + rng:NextNumber(2.5, 5)
	end
	local flip = math.clamp((t - flipStart) / 0.9, 0, 1)
	local flipEase = flip * flip * (3 - 2 * flip)
	local spin = CFrame.Angles(0, 0, math.rad(360 * flipEase)) * CFrame.Angles(math.rad(math.sin(flip * math.pi) * 60), 0, 0)
	km:PivotTo(camera.CFrame * base * stab * swayOffset * bob * spin)
	-- Mangos: se abren y cierran alrededor del pivote
	local open = math.sin(flip * math.pi) -- 0 cerrado -> 1 abierto -> 0
	for _, part in km:GetChildren() do
		if part:IsA("BasePart") then
			local side = part:GetAttribute("Side") or part:GetAttribute("HandleSide")
			if side then
				local pivot = km:GetPivot()
				local rel = pivot:ToObjectSpace(part.CFrame)
				local hinge = CFrame.Angles(math.rad(180 * open * (side :: number)), 0, 0)
				part.CFrame = pivot * hinge * rel
			end
		end
	end
	local _ = hum
end

local function update(dt: number)
	-- Sondeo de seguridad: si por lo que sea no llegó el evento ni el atributo
	if not ClientState.Armed and os.clock() - lastPoll > 0.5 then
		lastPoll = os.clock()
		local w = player:GetAttribute("SD_Weapon")
		if type(w) == "string" and w ~= "" then
			syncFromAttributes()
		end
	end
	if not ClientState.Armed then
		return
	end
	-- Primera persona garantizada mientras se está armado (y sin menú abierto)
	if not inputBlocked() and player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
		forceFirstPerson()
	end

	local hum = humanoid()
	local knife = ClientState.Slot == 2
	local canScope = wantScope and not knife and not ClientState.Reloading and hum ~= nil and hum.Health > 0 and not inputBlocked()
	local target = if canScope then 1 else 0
	local rate = dt / math.max(weapon.ScopeInTime, 0.01)
	ClientState.ScopeProgress = math.clamp(ClientState.ScopeProgress + (if target > ClientState.ScopeProgress then rate else -rate * 1.5), 0, 1)
	setScoped(ClientState.ScopeProgress >= 0.92)

	-- FOV
	local zoomFov = weapon.ZoomFOV[math.clamp(zoomIndex, 1, #weapon.ZoomFOV)]
	local p = ClientState.ScopeProgress
	local eased = 1 - (1 - p) ^ 3
	local fov = BASE_FOV + (zoomFov - BASE_FOV) * eased
	fovKick = math.max(0, fovKick - dt * 30)
	camera.FieldOfView = fov + fovKick + (if sliding then 6 else 0)
	scopeBlur.Size = math.sin(math.clamp(p, 0, 1) * math.pi) * 10

	-- Sensibilidad
	local s = settings()
	local sens = s.Sensitivity * (if ClientState.Scoped then s.ScopeSensitivity * (zoomFov / 30) else 1)
	pcall(function()
		UserInputService.MouseDeltaSensitivity = math.clamp(sens, 0.02, 4)
	end)

	-- Respiración
	if ClientState.Scoped and holdingBreath and ClientState.Breath > 0 then
		ClientState.Breath = math.max(ClientState.Breath - dt / BREATH_DURATION, 0)
	elseif not holdingBreath or not ClientState.Scoped then
		ClientState.Breath = math.min(ClientState.Breath + dt * BREATH_RECOVER, 1)
	end
	local breathing = ClientState.Scoped and holdingBreath and ClientState.Breath > 0
	local exhausted = ClientState.Breath <= 0.02

	-- Deslizamiento
	local root = hum and hum.RootPart
	if sliding then
		if os.clock() >= slideEnd or not root then
			stopSlide()
		elseif slideForce then
			-- Frena de forma progresiva hasta el final del deslizamiento
			local remaining = (slideEnd - os.clock()) / GameConfig.SlideDuration
			local speed = GameConfig.SlideSpeed * (0.3 + 0.7 * remaining)
			slideForce.PlaneVelocity = Vector2.new(slideDir.X, slideDir.Z) * speed
		end
	end
	-- Cámara: baja al agacharse/deslizarse (más al deslizarse)
	if hum then
		local target = if sliding then -2.2 elseif crouched then -1.4 else 0
		cameraDrop += (target - cameraDrop) * math.clamp(dt * 12, 0, 1)
		hum.CameraOffset = Vector3.new(0, cameraDrop, 0)
	end

	-- Velocidad de movimiento
	if hum then
		local speed = WALK_SPEED
		if knife then
			speed = WALK_SPEED * Weapons.Melee.WalkMultiplier
			if sprinting then
				speed = SPRINT_SPEED * Weapons.Melee.WalkMultiplier
			end
		elseif ClientState.ScopeProgress > 0.3 then
			speed = WALK_SPEED * weapon.ScopedWalkMultiplier
		elseif sprinting and not triggerHeld then
			speed = SPRINT_SPEED
		end
		if crouched and not sliding then
			speed *= GameConfig.CrouchSpeedMultiplier
		end
		hum.WalkSpeed = if (ClientState.Duel and ClientState.Duel.State ~= "Live") or inputBlocked() then 0 else speed
	end

	-- Retroceso con muelle amortiguado
	local stiffness, damping = 180, 18
	local accel = -stiffness * recoil - damping * recoilVel
	recoilVel += accel * dt
	recoil += recoilVel * dt

	-- Sway de la mira: NO se toca la cámara cada frame (pelea con el script de
	-- cámara de Roblox y da saltos). El vaivén se aplica a la retícula y al
	-- viewmodel; el servidor/cliente lo tienen en cuenta en la dispersión.
	local t = os.clock()
	local swayAmt = weapon.Sway * (if breathing then 0.12 elseif exhausted then 2.2 else 1) * ClientState.ScopeProgress
	local sx = (math.noise(t * 0.45, 0, 1.3) * 2 + math.sin(t * 1.1) * 0.6) * swayAmt
	local sy = (math.noise(0, t * 0.45, 7.7) * 2 + math.sin(t * 0.8) * 0.4) * swayAmt
	ClientState.Sway = Vector2.new(sx, sy)
	ClientState.Recoil = recoil
	local _ = appliedPitch

	local planar = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0

	-- En primera persona Roblox sigue dibujando la herramienta del personaje y
	-- sus brazos: se ocultan solo para este cliente (el viewmodel los sustituye)
	local char = player.Character
	if char and not inputBlocked() then
		for _, name in { "Rifle", "Knife" } do
			local tool = char:FindFirstChild(name)
			if tool then
				for _, part in tool:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 1
					end
				end
			end
		end
		for _, name in { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Right Arm", "Left Arm" } do
			local part = char:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end
	end

	-- Viewmodel activo
	if viewmodel then
		local vm = viewmodel :: Model
		local hideRifle = knife or ClientState.Scoped
		if not knife then
			bobTime += dt * (planar / WALK_SPEED) * 9
			local bobAmt = math.clamp(planar / WALK_SPEED, 0, 1.4) * (1 - p)
			local bob = CFrame.new(math.sin(bobTime) * 0.06 * bobAmt, math.abs(math.cos(bobTime)) * 0.05 * bobAmt, 0)
			local md = mouseDelta
			mouseDelta = Vector2.zero
			local targetSway = CFrame.Angles(math.rad(math.clamp(-md.Y * 0.08, -4, 4)), math.rad(math.clamp(-md.X * 0.08, -4, 4)), 0)
			swayOffset = swayOffset:Lerp(targetSway, math.clamp(dt * 10, 0, 1))
			local hip = CFrame.new(0.85, -0.85, -1.9)
			local ads = CFrame.new(0, -0.42, -1.1)
			local sprintPose = if sprinting and planar > 18 and p < 0.05 then CFrame.Angles(math.rad(-10), math.rad(35), math.rad(10)) * CFrame.new(-0.2, -0.2, 0.2) else CFrame.identity
			local reloadPose = if ClientState.Reloading then CFrame.Angles(math.rad(-25), math.rad(15), math.rad(-30)) * CFrame.new(0, -0.3, 0) else CFrame.identity
			local slidePose = if sliding then CFrame.Angles(math.rad(8), math.rad(-12), math.rad(-8)) else CFrame.identity
			local base = hip:Lerp(ads, eased)
			local kick = CFrame.new(0, 0, recoil * 0.04) * CFrame.Angles(math.rad(recoil * 0.8), 0, 0)
			local shakeV = ClientState.ShakeOffset or Vector3.zero
			local shakeCf = CFrame.new(shakeV.X * 0.02, shakeV.Y * 0.02, 0) * CFrame.Angles(math.rad(shakeV.Y * 0.4), math.rad(shakeV.X * 0.4), 0)
			local aimSway = CFrame.Angles(math.rad(sy * 0.3), math.rad(sx * 0.3), 0)
			vm:PivotTo(camera.CFrame * base * sprintPose * reloadPose * slidePose * swayOffset * aimSway * bob * kick * shakeCf)
		end
		for _, part in vm:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if hideRifle then 1 else 0
			end
		end
	end
	if knifeModel then
		for _, part in (knifeModel :: Model):GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if knife then 0 else 1
			end
		end
		if knife then
			updateKnifeViewmodel(dt, hum, planar)
		end
	end

	-- Armas semiautomáticas: mantener pulsado = disparo repetido
	if triggerHeld and not knife and weapon.FireCooldown < 0.5 then
		fire()
	end
end

function WeaponController.Start()
	ClientState.AmmoChanged:Connect(function()
		if ClientState.Armed and not viewmodel then
			local ok, err = pcall(onArmedChanged)
			if not ok then
				warn("[SniperDuels] onArmedChanged:", err)
			end
		end
	end)

	-- Vía 1: atributos replicados del Player
	for _, attr in { "SD_Weapon", "SD_Mag", "SD_Reloading", "SD_Slot" } do
		player:GetAttributeChangedSignal(attr):Connect(syncFromAttributes)
	end
	-- Vía 2: evento explícito del servidor
	Net.Event("Armed").OnClientEvent:Connect(function(weaponId: string, mag: number, reloading: boolean, slot: number?)
		applyArmState(weaponId, mag, reloading, slot)
	end)
	-- Vía 3: sondeo en update() si nada de lo anterior llegó
	task.defer(syncFromAttributes)
	-- Cambio de skin mientras se está armado: reconstruir el viewmodel
	ClientState.DataChanged:Connect(function(data)
		if ClientState.Armed and data and data.Equipped and data.Equipped.Skin ~= equippedSkin then
			buildViewmodels()
		end
	end)

	-- Vía 4: al empezar cada ronda, preguntar al servidor directamente
	ClientState.DuelChanged:Connect(function(state)
		if state and (state.State == "Countdown" or state.State == "Live") then
			task.spawn(function()
				local ok, res = pcall(function()
					return Net.Function("GetArmState"):InvokeServer()
				end)
				if ok and type(res) == "table" and res.Armed and not ClientState.Armed then
					applyArmState(res.WeaponId, res.Mag, res.Reloading, res.Slot)
				elseif not ok then
					warn("[SniperDuels] GetArmState:", res)
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			mouseDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	end)

	-- Re-aplicar primera persona tras reaparecer cada ronda
	player.CharacterAdded:Connect(function()
		baseHip = nil
		crouched = false
		slideForce = nil
		sliding = false
		cameraDrop = 0
		if ClientState.Armed then
			task.defer(function()
				forceFirstPerson()
				recoil, recoilVel = 0, 0
				appliedPitch, appliedYaw, appliedRoll = 0, 0, 0
				ClientState.Breath = 1
			end)
		end
	end)

	RunService:BindToRenderStep("SD_Weapon", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			-- no spamear: un aviso por segundo como mucho
			if os.clock() - lastPoll > 1 then
				lastPoll = os.clock()
				warn("[SniperDuels] WeaponController.update:", err)
			end
		end
	end)
end

return WeaponController
