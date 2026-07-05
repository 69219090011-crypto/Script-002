local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local KEY_TOGGLE = Enum.KeyCode.E

local SPEED_MULT = 5
local FOV_BOOST = 20

local SND_ON  = 134849405671692
local SND_OFF = 123844681344865

local SPAWN_INTERVAL = 0.05
local RAINBOW_SPEED = 0.35

local PART_TRANSPARENCY = 0.18
local MATERIAL = Enum.Material.Neon

local HL_FILL_TRANSP = 0.62
local LIGHT_BRIGHTNESS = 0.18
local LIGHT_RANGE = 4

local FADE_GAP = 0.045
local FADE_START_TIME = 0.30
local FADE_END_TIME = 0.08

local SHAKE_DURATION = 0.3
local SHAKE_MAGNITUDE = 0.35

local BLUE_TINT = Color3.fromRGB(80, 160, 255)
local BLUE_SAT = 0.25
local BLUE_CONTRAST = 0.08
local BLUR_SIZE = 5

local CHARGE_DRAIN_TIME = 30
local CHARGE_FULL_TIME = 45
local CHARGE_MIN_ENABLE = 0.4

local EXCLUDE_PART_NAMES = {
	HumanoidRootPart = true,
}

local camera = workspace.CurrentCamera or workspace:WaitForChild("Camera")
local folder = camera:FindFirstChild("SandevistanAfterimages")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "SandevistanAfterimages"
	folder.Parent = camera
end

local enabled = false
local spawnAcc = 0
local afterimages = {}

local character
local humanoid
local hrp
local head
local baseWalkSpeed = 16
local lastAppliedSpeed = 0
local baseFOV = 70
local internalSpeedSet = false
local wsConn
local fovTween
local shakeUntil = 0
local rng = Random.new()

local charge = 1
local chargeLockout = false

local colorFx = Lighting:FindFirstChild("SandevistanColor") or Instance.new("ColorCorrectionEffect")
colorFx.Name = "SandevistanColor"
colorFx.Enabled = false
colorFx.TintColor = Color3.new(1, 1, 1)
colorFx.Saturation = 0
colorFx.Contrast = 0
colorFx.Parent = Lighting

local blurFx = Lighting:FindFirstChild("SandevistanBlur") or Instance.new("BlurEffect")
blurFx.Name = "SandevistanBlur"
blurFx.Enabled = false
blurFx.Size = 0
blurFx.Parent = Lighting

local gui = Instance.new("ScreenGui")
gui.Name = "SandevistanUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

if not UserInputService.TouchEnabled then
	gui.Enabled = false
end

local barBack = Instance.new("Frame")
barBack.Name = "ChargeBack"
barBack.Size = UDim2.new(0, 16, 0, 220)
barBack.Position = UDim2.new(0, 16, 0.5, -110)
barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
barBack.BorderSizePixel = 0
barBack.Parent = gui

local barStroke = Instance.new("UIStroke")
barStroke.Thickness = 1
barStroke.Color = Color3.fromRGB(0, 160, 255)
barStroke.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Name = "ChargeFill"
barFill.AnchorPoint = Vector2.new(0, 1)
barFill.Position = UDim2.new(0, 0, 1, 0)
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local function updateChargeUI()
	barFill.Size = UDim2.new(1, 0, math.clamp(charge, 0, 1), 0)
	if chargeLockout then
		barFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		barStroke.Color = Color3.fromRGB(255, 80, 80)
	else
		barFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
		barStroke.Color = Color3.fromRGB(0, 160, 255)
	end
end

local function playSound(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume or 1
	s.Parent = SoundService
	SoundService:PlayLocalSound(s)
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function tweenFOV(target)
	local cam = workspace.CurrentCamera
	if not cam then return end
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = TweenService:Create(cam, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = target})
	fovTween:Play()
end

local function tweenFX(on)
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if on then
		colorFx.Enabled = true
		blurFx.Enabled = true
		TweenService:Create(colorFx, info, {TintColor = BLUE_TINT, Saturation = BLUE_SAT, Contrast = BLUE_CONTRAST}):Play()
		TweenService:Create(blurFx, info, {Size = BLUR_SIZE}):Play()
	else
		TweenService:Create(colorFx, info, {TintColor = Color3.new(1,1,1), Saturation = 0, Contrast = 0}):Play()
		TweenService:Create(blurFx, info, {Size = 0}):Play()
		task.delay(0.3, function()
			colorFx.Enabled = false
			blurFx.Enabled = false
		end)
	end
end

local function triggerShake()
	shakeUntil = os.clock() + SHAKE_DURATION
end

local function applyShake()
	if os.clock() >= shakeUntil then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local remaining = math.max(shakeUntil - os.clock(), 0)
	local damp = remaining / SHAKE_DURATION
	local mag = SHAKE_MAGNITUDE * damp
	local offset = Vector3.new(
		(rng:NextNumber(-1, 1)) * mag,
		(rng:NextNumber(-1, 1)) * mag,
		(rng:NextNumber(-1, 1)) * mag * 0.4
	)
	cam.CFrame = cam.CFrame * CFrame.new(offset)
end

local function isFirstPerson()
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end
	local cam = workspace.CurrentCamera
	if not cam or not head then
		return false
	end
	return (cam.CFrame.Position - head.Position).Magnitude < 1.2
end

local function getChar()
	local ch = player.Character
	if not ch then return nil end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local root = ch:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	return ch, hum, root
end

local function sanitizeClone(root, color)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("WrapLayer") or d:IsA("WrapTarget") then
			d:Destroy()
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end

	if root:IsA("MeshPart") then
		root.TextureID = ""
	end

	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Massless = true
	root.Material = MATERIAL
	root.Color = color
	root.Transparency = PART_TRANSPARENCY
end

local function clonePartSnapshot(src, parent, color)
	local cp = src:Clone()

	cp.Anchored = true
	cp.CanCollide = false
	cp.CanTouch = false
	cp.CanQuery = false
	cp.CastShadow = false
	cp.Massless = true
	cp.Material = MATERIAL
	cp.Color = color
	cp.Transparency = PART_TRANSPARENCY

	local isAccessoryPart = (src:FindFirstAncestorWhichIsA("Accessory") ~= nil)

	for _, d in ipairs(cp:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("WrapLayer") or d:IsA("WrapTarget") then
			if isAccessoryPart then
				d:Destroy()
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Constraint") then
			d:Destroy()
		elseif d:IsA("Attachment") then
			d:Destroy()
		end
	end

	if cp:IsA("MeshPart") then
		cp.TextureID = ""
		cp.RenderFidelity = Enum.RenderFidelity.Precise
		cp.CollisionFidelity = Enum.CollisionFidelity.Box
	end

	cp.Parent = parent
	cp.CFrame = src.CFrame

	return cp
end

local function spawnAfterimage(ch)
	local model = Instance.new("Model")
	model.Name = "Afterimage"
	model.Parent = folder
	table.insert(afterimages, model)

	local hue = (os.clock() * RAINBOW_SPEED) % 1
	local color = Color3.fromHSV(hue, 1, 1)

	local firstPart

	for _, c in ipairs(ch:GetChildren()) do
		if c:IsA("Accessory") then
			local h = c:FindFirstChild("Handle")
			if h and h:IsA("BasePart") then
				local cp = clonePartSnapshot(h, model, color)
				firstPart = firstPart or cp
			end
		end
	end

	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("BasePart") then
			if not EXCLUDE_PART_NAMES[d.Name] then
				if not d:FindFirstAncestorWhichIsA("Accessory") then
					local cp = clonePartSnapshot(d, model, color)
					firstPart = firstPart or cp
				end
			end
		end
	end

	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.FillTransparency = HL_FILL_TRANSP
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = model

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = firstPart or model
end

local function fadeModel(m, time)
	if not (m and m.Parent) then return end
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, info, {Transparency = 1}):Play()
		elseif d:IsA("Highlight") then
			TweenService:Create(d, info, {FillTransparency = 1, OutlineTransparency = 1}):Play()
		elseif d:IsA("PointLight") then
			TweenService:Create(d, info, {Brightness = 0}):Play()
		end
	end

	Debris:AddItem(m, time + 0.05)
end

local function clearAfterimagesSequentialFasterLater()
	if #afterimages == 0 then return end
	local list = afterimages
	afterimages = {}

	local n = #list
	for i = 1, n do
		local a = (n <= 1) and 0 or ((i - 1) / (n - 1))
		local t = FADE_START_TIME + (FADE_END_TIME - FADE_START_TIME) * a
		local m = list[i]
		task.delay((i - 1) * FADE_GAP, function()
			fadeModel(m, t)
		end)
	end
end

local function applySpeed()
	if not humanoid then return end
	internalSpeedSet = true
	if enabled then
		lastAppliedSpeed = baseWalkSpeed * SPEED_MULT
		humanoid.WalkSpeed = lastAppliedSpeed
	else
		lastAppliedSpeed = baseWalkSpeed
		humanoid.WalkSpeed = baseWalkSpeed
	end
	internalSpeedSet = false
end

local function hookDynamicSpeed()
	if not humanoid then return end
	if wsConn then
		wsConn:Disconnect()
		wsConn = nil
	end

	baseWalkSpeed = humanoid.WalkSpeed
	lastAppliedSpeed = enabled and (baseWalkSpeed * SPEED_MULT) or baseWalkSpeed

	wsConn = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if internalSpeedSet then return end

		local ws = humanoid.WalkSpeed
		local eps = 0.05

		if enabled then
			if math.abs(ws - lastAppliedSpeed) <= eps then
				return
			end
			baseWalkSpeed = ws
			applySpeed()
		else
			baseWalkSpeed = ws
			lastAppliedSpeed = ws
		end
	end)
end

local function refreshCharacter()
	local ch, hum, root = getChar()
	character = ch
	humanoid = hum
	hrp = root
	head = character and character:FindFirstChild("Head") or nil
	if humanoid then
		hookDynamicSpeed()
		applySpeed()
	end
end

local function canEnable()
	if chargeLockout and charge < CHARGE_MIN_ENABLE then
		return false
	end
	return charge > 0
end

local function setEnabled(v)
	if enabled == v then return end
	if v and not canEnable() then return end

	enabled = v
	applySpeed()

	local cam = workspace.CurrentCamera
	if cam then
		if enabled then
			baseFOV = cam.FieldOfView
			tweenFOV(math.clamp(baseFOV + FOV_BOOST, 70, 120))
		else
			tweenFOV(baseFOV)
		end
	end

	if enabled then
		playSound(SND_ON, 1)
		tweenFX(true)
		triggerShake()
	else
		playSound(SND_OFF, 1)
		tweenFX(false)
		triggerShake()
		clearAfterimagesSequentialFasterLater()
	end
end

local function toggle()
	setEnabled(not enabled)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == KEY_TOGGLE then
		toggle()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	applyShake()

	if enabled then
		charge = math.max(charge - (dt / CHARGE_DRAIN_TIME), 0)
		if charge <= 0 then
			charge = 0
			chargeLockout = true
			setEnabled(false)
		end
	else
		if charge < 1 then
			charge = math.min(charge + (dt / CHARGE_FULL_TIME), 1)
		end
		if chargeLockout and charge >= CHARGE_MIN_ENABLE then
			chargeLockout = false
		end
	end
	updateChargeUI()

	if not enabled then
		spawnAcc = 0
		return
	end

	if isFirstPerson() then
		spawnAcc = 0
		return
	end

	if not (character and humanoid and hrp and character.Parent) then
		refreshCharacter()
		if not character then return end
	end

	local moving = humanoid.MoveDirection.Magnitude > 0.05
	local vel = hrp.AssemblyLinearVelocity.Magnitude
	local state = humanoid:GetState()
	local inAir = state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown

	if not (moving or inAir or vel > 2) then
		spawnAcc = 0
		return
	end

	spawnAcc += dt
	while spawnAcc >= SPAWN_INTERVAL do
		spawnAcc -= SPAWN_INTERVAL
		spawnAfterimage(character)
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.1)
	refreshCharacter()
end)

refreshCharacter()
updateChargeUI()

local buttonsLocked = false

local function applyButtonStyle(btn)
	btn.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	btn.TextColor3 = Color3.fromRGB(0, 200, 255)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.AutoButtonColor = true
	btn.ZIndex = 6
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(0, 160, 255)
	stroke.Parent = btn
end

local function attachDrag(btn)
	local dragging = false
	local dragInput
	local startPos
	local startInput

	local function update(input)
		local delta = input.Position - startInput
		btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end

	btn.InputBegan:Connect(function(input)
		if buttonsLocked then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			startPos = btn.Position
			startInput = input.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	btn.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging and not buttonsLocked then
			update(input)
		end
	end)
end

local lockBtn = Instance.new("TextButton")
lockBtn.Name = "LockButton"
lockBtn.Text = "LOCK"
lockBtn.Size = UDim2.new(0, 70, 0, 32)
lockBtn.AnchorPoint = Vector2.new(0, 1)
lockBtn.Position = UDim2.new(0, 16, 1, -16)
lockBtn.Parent = gui
lockBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
lockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
lockBtn.BorderSizePixel = 0
lockBtn.Font = Enum.Font.GothamBold
lockBtn.TextSize = 12
lockBtn.AutoButtonColor = true
lockBtn.ZIndex = 7
local lockStroke = Instance.new("UIStroke")
lockStroke.Thickness = 1
lockStroke.Color = Color3.fromRGB(255, 255, 255)
lockStroke.Parent = lockBtn

local function updateLockText()
	lockBtn.Text = buttonsLocked and "UNLOCK" or "LOCK"
end

lockBtn.MouseButton1Click:Connect(function()
	buttonsLocked = not buttonsLocked
	updateLockText()
end)

updateLockText()

local sBtn = Instance.new("TextButton")
sBtn.Name = "SButton"
sBtn.Text = "OFF"
sBtn.Size = UDim2.new(0, 72, 0, 72)
sBtn.Position = UDim2.new(1, -120, 1, -140)
sBtn.Parent = gui
applyButtonStyle(sBtn)
attachDrag(sBtn)

local function refreshToggleText()
	sBtn.Text = enabled and "ON" or "OFF"
end

sBtn.MouseButton1Click:Connect(function()
	toggle()
	refreshToggleText()
end)

refreshToggleText()