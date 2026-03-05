--[[
	FlashlightClient: Client-side flashlight UI/effects handler
	
	Responsibilities:
		- Handle toggle light input (mouse click)
		- Play sound effects when light toggles
		- Create LOCAL SpotLight for smooth, lag-free lighting (hybrid system)
		- Update spotlight direction based on camera look
		- Listen to server events (attached/removed/toggled)
	
	HYBRID SYSTEM:
		- CLIENT: Local SpotLight (smooth, no lag) - only visible to owner
		- SERVER: Replicated SpotLight - visible to other players
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera

-- Flashlight configuration
local LIGHT_COLOR = Color3.fromRGB(255, 240, 200)
local LIGHT_BRIGHTNESS = 2
local LIGHT_RANGE = 40

-- Sound IDs (placeholders - replace with actual sound IDs)
local SOUND_FLASHLIGHT_ON = "rbxasset://sounds/switch.wav"
local SOUND_FLASHLIGHT_OFF = "rbxasset://sounds/switch.wav"
local SOUND_BATTERY_EMPTY = "rbxasset://sounds/button.wav"

-- State tracking
local hasFlashlightEquipped = false
local currentCharge = 0.5
local isLightOn = false

-- Client-side spotlight (local, smooth, no lag)
local localSpotlight = nil
local localSpotlightPivot = nil
local lensReference = nil
local flashlightModel = nil
local viewModel = nil  -- FPS-style viewmodel (attached to camera)
local viewModelChargeIndicators = {}  -- Charge indicators on viewmodel

-- RemoteEvent for server communication
local flashlightEvent = ReplicatedStorage:WaitForChild("FlashlightEvent")

-- Play a sound
local function playSound(soundId)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.5
	sound.Parent = workspace
	sound:Play()
	
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- Update charge indicators on viewmodel
local function updateViewModelChargeIndicators()
	if #viewModelChargeIndicators == 0 then return end
	
	local chargePercent = currentCharge * 100
	
	for i, indicator in ipairs(viewModelChargeIndicators) do
		local threshold = (4 - i) * 25 -- 75%, 50%, 25%, 0%
		
		if chargePercent > threshold then
			-- Active (green)
			indicator.Transparency = 0
			indicator.Color = Color3.fromRGB(0, 255, 0)
			indicator.Material = Enum.Material.Neon
		else
			-- Inactive (dim)
			indicator.Transparency = 0.5
			indicator.Color = Color3.fromRGB(50, 50, 50)
			indicator.Material = Enum.Material.SmoothPlastic
		end
	end
end

-- Handle toggle light action (mouse click or mobile button)
local function handleToggleLight(actionName, inputState, inputObject)
	-- Only trigger on button down (not up or hold)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	
	-- Don't toggle if inventory is open (mouse unlocked)
	-- Return PASS so drag&drop system can use the input
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return Enum.ContextActionResult.Pass  -- Changed from Sink to Pass
	end
	
	-- Check if flashlight is equipped
	if not hasFlashlightEquipped then
		return Enum.ContextActionResult.Pass
	end
	
	-- Send toggle request to server
	flashlightEvent:FireServer("ToggleLight")
	
	return Enum.ContextActionResult.Sink
end

-- Create local (client-side) spotlight for smooth lighting
local function createLocalSpotlight()
	-- Find flashlight model in character
	if not character then return end
	flashlightModel = character:FindFirstChild("EquippedFlashlight")
	if not flashlightModel then
		warn("[FlashlightClient] EquippedFlashlight model not found in character")
		return
	end
	
	-- Hide original flashlight model from local player (others still see it)
	for _, part in flashlightModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1  -- Make invisible to local player
		end
	end
	
	-- Disable server-side spotlight for local player (to prevent double lighting)
	local serverSpotlightPivot = flashlightModel:FindFirstChild("SpotlightPivot")
	if serverSpotlightPivot then
		local serverSpotlight = serverSpotlightPivot:FindFirstChild("FlashlightBeam")
		if serverSpotlight and serverSpotlight:IsA("SpotLight") then
			serverSpotlight.Enabled = false  -- LOCALLY disabled (others still see it)
			print("[FlashlightClient] ✓ Disabled server spotlight locally")
		end
	end
	
	-- Clone flashlight model for FPS viewmodel
	viewModel = flashlightModel:Clone()
	viewModel.Name = "FlashlightViewModel"
	
	-- Make all parts non-collidable and visible
	for _, part in viewModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = true
			part.Massless = true
			part.LocalTransparencyModifier = 0
		elseif part:IsA("Motor6D") or part:IsA("Weld") or part:IsA("WeldConstraint") then
			-- Remove joints from viewmodel (we'll position it manually)
			part:Destroy()
		end
	end
	
	-- Remove server-side spotlight from viewmodel
	local serverPivot = viewModel:FindFirstChild("SpotlightPivot")
	if serverPivot then
		serverPivot:Destroy()
	end
	
	-- Parent to camera (renders on top of world)
	viewModel.Parent = camera
	
	-- Find lens for spotlight positioning
	local lens = viewModel:FindFirstChild("Lens", true)
	if not lens then
		lens = viewModel.PrimaryPart
	end
	
	if not lens then
		warn("[FlashlightClient] No Lens or PrimaryPart found in viewmodel")
		viewModel:Destroy()
		viewModel = nil
		return
	end
	
	lensReference = lens
	
	-- Find and store charge indicators from viewmodel
	viewModelChargeIndicators = {}
	for i = 1, 4 do
		local indicator = viewModel:FindFirstChild("ChargeIndicator" .. i, true)
		if indicator then
			table.insert(viewModelChargeIndicators, indicator)
		end
	end
	
	-- Update indicators to current charge level
	updateViewModelChargeIndicators()
	print(string.format("[FlashlightClient] Found %d charge indicators on viewmodel", #viewModelChargeIndicators))
	
	-- Create invisible pivot for spotlight rotation (follows camera)
	localSpotlightPivot = Instance.new("Part")
	localSpotlightPivot.Name = "LocalSpotlightPivot"
	localSpotlightPivot.Size = Vector3.new(0.1, 0.1, 0.1)
	localSpotlightPivot.Transparency = 1
	localSpotlightPivot.CanCollide = false
	localSpotlightPivot.Massless = true
	localSpotlightPivot.Anchored = true
	localSpotlightPivot.Parent = camera
	
	-- Create LOCAL SpotLight (only this client sees it)
	localSpotlight = Instance.new("SpotLight")
	localSpotlight.Name = "LocalFlashlightBeam"
	localSpotlight.Brightness = 0 -- Off by default
	localSpotlight.Range = LIGHT_RANGE
	localSpotlight.Angle = 60
	localSpotlight.Color = LIGHT_COLOR
	localSpotlight.Face = Enum.NormalId.Front
	localSpotlight.Enabled = true
	localSpotlight.Parent = localSpotlightPivot
	
	print("[FlashlightClient] ✓ Created FPS viewmodel flashlight")
end

-- Remove local spotlight
local function removeLocalSpotlight()
	if localSpotlight then
		localSpotlight:Destroy()
		localSpotlight = nil
	end
	if localSpotlightPivot then
		localSpotlightPivot:Destroy()
		localSpotlightPivot = nil
	end
	if viewModel then
		viewModel:Destroy()
		viewModel = nil
	end
	
	-- Clear charge indicators
	viewModelChargeIndicators = {}
	
	-- Restore visibility of original flashlight model
	if flashlightModel then
		for _, part in flashlightModel:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end
	end
	
	lensReference = nil
	flashlightModel = nil
	print("[FlashlightClient] Removed local spotlight")
end

-- Update local spotlight direction (follows camera for smooth aiming)
local debugCounter = 0
local function updateLocalSpotlightDirection()
	if not localSpotlightPivot or not lensReference or not camera or not viewModel then return end
	
	-- Position viewmodel like FPS weapon (bottom right of screen)
	-- Offset from camera: right, down, forward
	local cameraCFrame = camera.CFrame
	-- Position offset (X=right, Y=down, Z=forward) * Rotation (pitch, yaw, roll)
	local viewmodelOffset = CFrame.new(0.8, -0.8, -2) * CFrame.Angles(math.rad(90), math.rad(180), math.rad(-90))  -- Rotate 90° to face forward
	local viewmodelCFrame = cameraCFrame * viewmodelOffset
	
	-- Position all viewmodel parts relative to camera
	-- We need to maintain the model's internal structure
	if viewModel.PrimaryPart then
		-- Calculate offset: where should PrimaryPart be to get the desired viewmodel position
		local primaryPartOffset = viewModel.PrimaryPart.CFrame:Inverse() * lensReference.CFrame
		local targetPrimaryPartCFrame = viewmodelCFrame * primaryPartOffset:Inverse()
		
		-- Move entire model by moving PrimaryPart
		local currentCFrame = viewModel.PrimaryPart.CFrame
		local delta = targetPrimaryPartCFrame * currentCFrame:Inverse()
		
		for _, part in viewModel:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = delta * part.CFrame
			end
		end
	end
	
	-- Position spotlight at lens, pointing in camera direction
	local lensPos = lensReference.Position
	local cameraLook = cameraCFrame.LookVector
	localSpotlightPivot.CFrame = CFrame.new(lensPos, lensPos + cameraLook)
end

-- Update local spotlight brightness based on state
local function updateLocalSpotlightState()
	if not localSpotlight then return end
	
	if isLightOn then
		localSpotlight.Brightness = LIGHT_BRIGHTNESS
	else
		localSpotlight.Brightness = 0
	end
end

-- Listen to server events
flashlightEvent.OnClientEvent:Connect(function(action, ...)
	
	if action == "FlashlightAttached" then
		local charge = ...
		hasFlashlightEquipped = true
		currentCharge = charge or 0.5
		isLightOn = false
		
		-- Create LOCAL spotlight (smooth, client-side)
		task.wait(0.1) -- Wait for server model to replicate
		createLocalSpotlight()
		
		-- Bind toggle action (left mouse button)
		ContextActionService:BindAction(
			"ToggleFlashlight",
			handleToggleLight,
			false,
			Enum.UserInputType.MouseButton1
		)
		
		print(string.format("[FlashlightClient] ✓ Flashlight attached (charge: %.0f%%)", currentCharge * 100))
		
	elseif action == "FlashlightRemoved" then
		hasFlashlightEquipped = false
		isLightOn = false
		
		-- Remove local spotlight
		removeLocalSpotlight()
		
		-- Unbind toggle action
		ContextActionService:UnbindAction("ToggleFlashlight")
		
		print("[FlashlightClient] Flashlight removed")
		
	elseif action == "FlashlightToggled" then
		local targetPlayer, lightOn = ...
		
		-- Update state for this player's flashlight
		if targetPlayer == player then
			isLightOn = lightOn
			updateLocalSpotlightState()
			
			if lightOn then
				playSound(SOUND_FLASHLIGHT_ON)
				print("[FlashlightClient] Light ON")
			else
				playSound(SOUND_FLASHLIGHT_OFF)
				print("[FlashlightClient] Light OFF")
			end
		end
		
	elseif action == "FlashlightNoCharge" then
		playSound(SOUND_BATTERY_EMPTY)
		print("[FlashlightClient] No charge! Cannot turn on")
		
	elseif action == "FlashlightChargeUpdated" then
		local newCharge = ...
		currentCharge = newCharge
		updateViewModelChargeIndicators()  -- Update viewmodel indicators
		print(string.format("[FlashlightClient] Charge updated: %.0f%%", currentCharge * 100))
	end
end)

-- BACKUP: UserInputService input handling (in case ContextActionService fails)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not hasFlashlightEquipped then return end
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then return end
		
		flashlightEvent:FireServer("ToggleLight")
	end
end)

-- Update spotlight direction every frame (smooth, follows camera)
RunService.RenderStepped:Connect(function()
	if hasFlashlightEquipped and localSpotlightPivot then
		updateLocalSpotlightDirection()
	end
end)

print("[FlashlightClient] Flashlight client initialized (HYBRID system - local + server)")

