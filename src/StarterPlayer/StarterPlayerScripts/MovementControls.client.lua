--[[
	MovementControls: Sprint and crouch mechanics
	
	Controls:
		- Hold Shift: Sprint (increased speed)
		- Hold Ctrl: Crouch (decreased speed, lowered camera)
	
	Future: Add animations for sprinting and crouching

	PROJECT DIRECTION NOTES:
	- Movement controls are part of disguise performance in social stealth.
	- TODO: tie sprint/crouch behavior to suspicion gain based on context and host commands.
	- TODO: add command-driven input constraints (e.g., forced stop/freeze windows).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- Speed configuration
local NORMAL_SPEED = 16
local SPRINT_SPEED = 24
local CROUCH_SPEED = 8

-- Camera offset configuration
local NORMAL_CAMERA_OFFSET = Vector3.new(0, 0, 0)
local CROUCH_CAMERA_OFFSET = Vector3.new(0, -1.5, 0)

-- State
local isSprinting = false
local isCrouching = false
local cameraTransitionTween = nil

-- Update movement based on current state
local function UpdateMovement()
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	
	-- Cancel any ongoing camera tween
	if cameraTransitionTween then
		cameraTransitionTween:Cancel()
	end
	
	-- Determine target camera offset and speed
	local targetOffset
	local targetSpeed
	
	-- Priority: Crouching overrides sprinting
	if isCrouching then
		targetSpeed = CROUCH_SPEED
		targetOffset = CROUCH_CAMERA_OFFSET
	elseif isSprinting then
		targetSpeed = SPRINT_SPEED
		targetOffset = NORMAL_CAMERA_OFFSET
	else
		targetSpeed = NORMAL_SPEED
		targetOffset = NORMAL_CAMERA_OFFSET
	end
	
	-- Apply speed immediately
	humanoid.WalkSpeed = targetSpeed
	
	-- Smoothly tween camera offset
	local tweenInfo = TweenInfo.new(
		0.3,                        -- Duration: 0.3 seconds
		Enum.EasingStyle.Quad,      -- Smooth easing
		Enum.EasingDirection.Out    -- Ease out
	)
	
	cameraTransitionTween = TweenService:Create(humanoid, tweenInfo, {
		CameraOffset = targetOffset
	})
	
	cameraTransitionTween:Play()
end

-- Handle input
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return -- Don't process if typing in chat, etc.
	end
	
	-- Sprint (Shift)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = true
		UpdateMovement()
		print("[MovementControls] Sprint started")
	end
	
	-- Crouch (Ctrl)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		isCrouching = true
		UpdateMovement()
		print("[MovementControls] Crouch started")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- Stop Sprint
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
		UpdateMovement()
		print("[MovementControls] Sprint ended")
	end
	
	-- Stop Crouch
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		isCrouching = false
		UpdateMovement()
		print("[MovementControls] Crouch ended")
	end
end)

-- Handle character respawn
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	
	-- Reset state
	isSprinting = false
	isCrouching = false
	
	-- Set initial speed
	humanoid.WalkSpeed = NORMAL_SPEED
	humanoid.CameraOffset = NORMAL_CAMERA_OFFSET
	
	print("[MovementControls] Character respawned - controls reset")
end)

-- Initialize
humanoid.WalkSpeed = NORMAL_SPEED
humanoid.CameraOffset = NORMAL_CAMERA_OFFSET

print("[MovementControls] Movement controls initialized (Shift = Sprint, Ctrl = Crouch)")
