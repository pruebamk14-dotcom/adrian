--!strict
-- Manejo del rifle en primera persona: viewmodel con sway/bob/recoil,
-- mira con zoom variable, aguantar respiración, dispersión por movimiento,
-- recarga, sprint, auto-rescope tras el cerrojo, y controles táctiles.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
local viewmodel: Model? = nil
local equippedSkin = "Default"

local wantScope = false
local zoomIndex = 1
local lastFire = 0
local holdingBreath = false
local sprinting = false
local triggerHeld = false
local rescopeAfterBolt = false

local recoil = 0 -- grados actuales de patada
local recoilVel = 0
local swayOffset = CFrame.identity
local bobTime = 0
local mouseDelta = Vector2.zero
-- El módulo de cámara de Roblox parte del CFrame del frame anterior, así que
-- aplicamos solo la diferencia respecto al offset del frame anterior.
local appliedPitch, appliedYaw = 0, 0

local function settings()
	local d = ClientState.Data
	return d and d.Settings or { Sensitivity = 1, ScopeSensitivity = 0.55, ToggleScope = false }
end

local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function destroyViewmodel()
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
end

local function buildViewmodel()
	destroyViewmodel()
	local d = ClientState.Data
	equippedSkin = d and d.Equipped.Skin or "Default"
	local vm = GunBuilder.Build(weapon.Id, equippedSkin)
	for _, p in vm:GetDescendants() do
		if p:IsA("BasePart") then
			p.CastShadow = false
		end
	end
	;(vm.PrimaryPart :: BasePart).Anchored = true
	vm.Name = "Viewmodel"
	vm.Parent = camera
	viewmodel = vm
end

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
	return spread
end
WeaponController.CurrentSpread = currentSpread

local function reload()
	if not ClientState.Armed or ClientState.Reloading or ClientState.Mag >= weapon.MagSize then
		return
	end
	Net.Event("Reload"):FireServer()
	EffectsController.PlaySound("Reload", 0.6)
	setScoped(false)
end

local function fire()
	if not ClientState.CanShoot() or ClientState.Reloading then
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
	local direction = Ballistics.ApplySpread(camCf.LookVector, spread, rng)
	Net.Event("Fire"):FireServer(origin, direction, workspace:GetServerTimeNow())

	-- Predicción local (el servidor confirma con munición/impacto)
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
		EffectsController.MuzzleFlash(muzzlePos, Color3.fromRGB(255, 200, 100))
	end
	EffectsController.Tracer(origin, direction, weapon.Id, equippedSkin, if ClientState.Scoped then origin + camCf.UpVector * -0.3 else muzzlePos)
	EffectsController.PlaySound("Fire", 0.9)

	recoilVel += weapon.RecoilPitch * 18
	if WeaponController.OnFired then
		WeaponController.OnFired(spread)
	end

	-- Armas de cerrojo: salir de la mira mientras se acciona y volver a entrar
	if weapon.FireCooldown >= 0.8 then
		rescopeAfterBolt = ClientState.Scoped or wantScope
		task.delay(0.12, function()
			if os.clock() - lastFire < weapon.FireCooldown then
				wantScope = false
				EffectsController.PlaySound("Bolt", 0.6)
			end
		end)
		task.delay(weapon.FireCooldown, function()
			if rescopeAfterBolt and ClientState.Armed then
				local s = settings()
				-- Con mira por pulsación, solo re-apuntar si aún mantiene el botón
				if s.ToggleScope or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
					wantScope = true
				end
			end
			rescopeAfterBolt = false
		end)
	end
end

local function onArmedChanged()
	if ClientState.Armed then
		weapon = Weapons.Get(ClientState.WeaponId)
		zoomIndex = 1
		buildViewmodel()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		UserInputService.MouseIconEnabled = false
	else
		destroyViewmodel()
		wantScope = false
		setScoped(false)
		ClientState.ScopeProgress = 0
		camera.FieldOfView = BASE_FOV
		recoil, recoilVel = 0, 0
		appliedPitch, appliedYaw = 0, 0
		player.CameraMode = Enum.CameraMode.Classic
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseDeltaSensitivity = 1
	end
end

-- Acciones ------------------------------------------------------------------

local function bindActions()
	local touch = UserInputService.TouchEnabled

	ContextActionService:BindAction("SD_Fire", function(_, state)
		if state == Enum.UserInputState.Begin then
			triggerHeld = true
			fire()
		elseif state == Enum.UserInputState.End then
			triggerHeld = false
		end
		return Enum.ContextActionResult.Sink
	end, touch, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction("SD_Scope", function(_, state, input)
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

	if touch then
		local layout = {
			SD_Fire = { UDim2.new(1, -110, 1, -190), "DISPARAR" },
			SD_Scope = { UDim2.new(1, -200, 1, -130), "MIRA" },
			SD_Reload = { UDim2.new(1, -95, 1, -280), "R" },
			SD_Zoom = { UDim2.new(1, -190, 1, -230), "ZOOM" },
		}
		for name, info in layout do
			ContextActionService:SetPosition(name, info[1])
			ContextActionService:SetTitle(name, info[2])
		end
	end
end

local function unbindActions()
	for _, name in { "SD_Fire", "SD_Scope", "SD_Reload", "SD_Zoom", "SD_Breath" } do
		ContextActionService:UnbindAction(name)
	end
	triggerHeld = false
	holdingBreath = false
	sprinting = false
end

-- Bucle por frame -------------------------------------------------------------

local function update(dt: number)
	if not ClientState.Armed then
		return
	end
	local hum = humanoid()
	local canScope = wantScope and not ClientState.Reloading and hum ~= nil and hum.Health > 0
	local target = if canScope then 1 else 0
	local rate = dt / math.max(weapon.ScopeInTime, 0.01)
	ClientState.ScopeProgress = math.clamp(ClientState.ScopeProgress + (if target > ClientState.ScopeProgress then rate else -rate * 1.5), 0, 1)
	setScoped(ClientState.ScopeProgress >= 0.92)

	-- FOV
	local zoomFov = weapon.ZoomFOV[math.clamp(zoomIndex, 1, #weapon.ZoomFOV)]
	local p = ClientState.ScopeProgress
	local eased = 1 - (1 - p) ^ 3
	local fov = BASE_FOV + (zoomFov - BASE_FOV) * eased
	camera.FieldOfView = fov

	-- Sensibilidad
	local s = settings()
	local sens = s.Sensitivity * (if ClientState.Scoped then s.ScopeSensitivity * (zoomFov / 30) else 1)
	UserInputService.MouseDeltaSensitivity = math.clamp(sens, 0.02, 4)

	-- Respiración
	if ClientState.Scoped and holdingBreath and ClientState.Breath > 0 then
		ClientState.Breath = math.max(ClientState.Breath - dt / BREATH_DURATION, 0)
	elseif not holdingBreath or not ClientState.Scoped then
		ClientState.Breath = math.min(ClientState.Breath + dt * BREATH_RECOVER, 1)
	end
	local breathing = ClientState.Scoped and holdingBreath and ClientState.Breath > 0
	local exhausted = ClientState.Breath <= 0.02

	-- Velocidad de movimiento
	if hum then
		local speed = WALK_SPEED
		if ClientState.ScopeProgress > 0.3 then
			speed = WALK_SPEED * weapon.ScopedWalkMultiplier
		elseif sprinting and not triggerHeld then
			speed = SPRINT_SPEED
		end
		hum.WalkSpeed = if ClientState.Duel and ClientState.Duel.State ~= "Live" then 0 else speed
	end

	-- Retroceso con muelle amortiguado
	local stiffness, damping = 180, 18
	local accel = -stiffness * recoil - damping * recoilVel
	recoilVel += accel * dt
	recoil += recoilVel * dt

	-- Sway de la mira (ruido suave, se reduce al aguantar la respiración)
	local t = os.clock()
	local swayAmt = weapon.Sway * (if breathing then 0.12 elseif exhausted then 2.2 else 1) * ClientState.ScopeProgress
	local sx = (math.noise(t * 0.45, 0, 1.3) * 2 + math.sin(t * 1.1) * 0.6) * swayAmt
	local sy = (math.noise(0, t * 0.45, 7.7) * 2 + math.sin(t * 0.8) * 0.4) * swayAmt
	local pitch, yaw = sy + recoil * 0.35, sx
	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(pitch - appliedPitch), math.rad(yaw - appliedYaw), 0)
	appliedPitch, appliedYaw = pitch, yaw

	-- Viewmodel
	if viewmodel then
		local vm = viewmodel :: Model
		local root = hum and hum.RootPart
		local planar = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
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
		local base = hip:Lerp(ads, eased)
		local kick = CFrame.new(0, 0, recoil * 0.04) * CFrame.Angles(math.rad(recoil * 0.8), 0, 0)
		vm:PivotTo(camera.CFrame * base * sprintPose * reloadPose * swayOffset * bob * kick)

		-- Ocultar el modelo cuando la mira está completamente puesta
		local hide = ClientState.Scoped
		for _, part in vm:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if hide then 1 else 0
			end
		end
	end

	-- Armas semiautomáticas: mantener pulsado = disparo repetido
	if triggerHeld and weapon.FireCooldown < 0.5 then
		fire()
	end
end

function WeaponController.Start()
	ClientState.AmmoChanged:Connect(function()
		-- reconstruir si cambia el arma o la skin entre duelos
		if ClientState.Armed and (not viewmodel or ClientState.WeaponId ~= weapon.Id) then
			onArmedChanged()
		end
	end)

	Net.Event("AmmoUpdate").OnClientEvent:Connect(function(mag: number, reloading: boolean, weaponId: string)
		local wasArmed = ClientState.Armed
		ClientState.Armed = mag >= 0
		ClientState.Mag = math.max(mag, 0)
		ClientState.Reloading = reloading
		ClientState.WeaponId = weaponId
		if ClientState.Armed ~= wasArmed then
			onArmedChanged()
			if ClientState.Armed then
				bindActions()
			else
				unbindActions()
			end
		end
		ClientState.AmmoChanged:Fire()
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			mouseDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	end)

	-- Re-aplicar primera persona tras reaparecer cada ronda
	player.CharacterAdded:Connect(function()
		if ClientState.Armed then
			task.defer(function()
				player.CameraMode = Enum.CameraMode.LockFirstPerson
				recoil, recoilVel = 0, 0
				appliedPitch, appliedYaw = 0, 0
				ClientState.Breath = 1
			end)
		end
	end)

	RunService:BindToRenderStep("SD_Weapon", Enum.RenderPriority.Camera.Value + 1, update)
end

return WeaponController
