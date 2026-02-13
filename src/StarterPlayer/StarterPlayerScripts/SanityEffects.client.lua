--[[
	SanityEffects: Client-side sanity visual and audio effects
	
	Effects by sanity level:
		Level 1 (Healthy): No effects
		Level 2 (Uneasy): Subtle mouse shake, slight red vignette
		Level 3 (Disturbed): Moderate mouse shake, medium red vignette, occasional audio
		Level 4 (Panicked): Strong mouse shake, heavy red vignette, frequent audio
		Level 5 (Broken): Extreme mouse shake, full red vignette, constant audio
	
	Modular configuration for easy tweaking
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local SanityEffects = {}

-- Configuration: Mouse shake intensity per level
local SHAKE_CONFIG = {
	[1] = 0,      -- Healthy: no shake
	[2] = 2,    -- Uneasy: subtle
	[3] = 4,    -- Disturbed: moderate
	[4] = 6,    -- Panicked: strong
	[5] = 8     -- Broken: extreme
}

-- Configuration: Vignette darkness per level (0-1)
local VIGNETTE_CONFIG = {
	[1] = 0,      -- Healthy: no vignette
	[2] = 0.15,   -- Uneasy: subtle
	[3] = 0.35,   -- Disturbed: noticeable
	[4] = 0.60,   -- Panicked: heavy
	[5] = 0.85    -- Broken: almost full screen
}

-- Configuration: Audio frequency per level (seconds between sounds)
local AUDIO_CONFIG = {
	[1] = 0,      -- Healthy: no audio
	[2] = 60,     -- Uneasy: every 60s
	[3] = 30,     -- Disturbed: every 30s
	[4] = 15,     -- Panicked: every 15s
	[5] = 5       -- Broken: every 5s
}

-- State
local currentSanity = 100
local currentLevel = 1
local shakeIntensity = 0
local vignetteAmount = 0

-- Connections
local shakeConnection = nil
local audioTimer = 0
local audioConnection = nil

-- UI Elements
local screenGui = nil
local vignetteFrame = nil

-- Initialize UI
function SanityEffects:Init()
	-- Create ScreenGui for vignette
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SanityEffects"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.Parent = player.PlayerGui
	
	-- Create red vignette container
	vignetteFrame = Instance.new("Frame")
	vignetteFrame.Name = "BlackVignette"
	vignetteFrame.Size = UDim2.new(1, 0, 1, 0)
	vignetteFrame.Position = UDim2.new(0, 0, 0, 0)
	vignetteFrame.BackgroundTransparency = 1
	vignetteFrame.BorderSizePixel = 0
	vignetteFrame.ZIndex = 100
	vignetteFrame.Parent = screenGui
	
	-- Create 4 edge frames (top, bottom, left, right) with gradients
	local edgeSize = 0.3 -- How far edges extend into screen (30%)
	
	-- Top edge
	local topEdge = Instance.new("Frame")
	topEdge.Name = "TopEdge"
	topEdge.Size = UDim2.new(1, 0, edgeSize, 0)
	topEdge.Position = UDim2.new(0, 0, 0, 0)
	topEdge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	topEdge.BackgroundTransparency = 1
	topEdge.BorderSizePixel = 0
	topEdge.Parent = vignetteFrame
	
	local topGradient = Instance.new("UIGradient")
	topGradient.Rotation = 90 -- Vertical
	topGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),   -- Top: opaque
		NumberSequenceKeypoint.new(1, 1)    -- Bottom: transparent
	})
	topGradient.Parent = topEdge
	
	-- Bottom edge
	local bottomEdge = Instance.new("Frame")
	bottomEdge.Name = "BottomEdge"
	bottomEdge.Size = UDim2.new(1, 0, edgeSize, 0)
	bottomEdge.Position = UDim2.new(0, 0, 1 - edgeSize, 0)
	bottomEdge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bottomEdge.BackgroundTransparency = 1
	bottomEdge.BorderSizePixel = 0
	bottomEdge.Parent = vignetteFrame
	
	local bottomGradient = Instance.new("UIGradient")
	bottomGradient.Rotation = 90 -- Vertical
	bottomGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),   -- Top: transparent
		NumberSequenceKeypoint.new(1, 0)    -- Bottom: opaque
	})
	bottomGradient.Parent = bottomEdge
	
	-- Left edge
	local leftEdge = Instance.new("Frame")
	leftEdge.Name = "LeftEdge"
	leftEdge.Size = UDim2.new(edgeSize, 0, 1, 0)
	leftEdge.Position = UDim2.new(0, 0, 0, 0)
	leftEdge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	leftEdge.BackgroundTransparency = 1
	leftEdge.BorderSizePixel = 0
	leftEdge.Parent = vignetteFrame
	
	local leftGradient = Instance.new("UIGradient")
	leftGradient.Rotation = 0 -- Horizontal
	leftGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),   -- Left: opaque
		NumberSequenceKeypoint.new(1, 1)    -- Right: transparent
	})
	leftGradient.Parent = leftEdge
	
	-- Right edge
	local rightEdge = Instance.new("Frame")
	rightEdge.Name = "RightEdge"
	rightEdge.Size = UDim2.new(edgeSize, 0, 1, 0)
	rightEdge.Position = UDim2.new(1 - edgeSize, 0, 0, 0)
	rightEdge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	rightEdge.BackgroundTransparency = 1
	rightEdge.BorderSizePixel = 0
	rightEdge.Parent = vignetteFrame
	
	local rightGradient = Instance.new("UIGradient")
	rightGradient.Rotation = 0 -- Horizontal
	rightGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),   -- Left: transparent
		NumberSequenceKeypoint.new(1, 0)    -- Right: opaque
	})
	rightGradient.Parent = rightEdge
	
	print("[SanityEffects] UI initialized")
	
	-- Listen for sanity updates from server
	self:_ConnectToServer()
	
	-- Start effect loops
	self:_StartMouseShake()
	self:_StartAudioLoop()
end

-- Connect to server RemoteEvent
function SanityEffects:_ConnectToServer()
	local sanityEvent = ReplicatedStorage:WaitForChild("SanityEvent")
	
	sanityEvent.OnClientEvent:Connect(function(action, data)
		if action == "Init" or action == "Update" then
			currentSanity = data.sanity
			currentLevel = data.level
			
			-- Update effect intensities
			shakeIntensity = SHAKE_CONFIG[currentLevel] or 0
			vignetteAmount = VIGNETTE_CONFIG[currentLevel] or 0
			
			-- Update vignette immediately
			self:_UpdateVignette()
			
			print(string.format("[SanityEffects] Sanity updated: %d (Level %d)", currentSanity, currentLevel))
			
		elseif action == "LevelChanged" then
			print(string.format("[SanityEffects] Level changed: %d → %d", data.oldLevel, data.level))
			-- Play transition sound/effect here if desired
			
		elseif action == "Eliminated" then
			warn("[SanityEffects] PLAYER ELIMINATED")
			-- Show death screen or other elimination effects
		end
	end)
	
	print("[SanityEffects] Connected to SanityEvent")
end

-- Start mouse shake effect
function SanityEffects:_StartMouseShake()
	if shakeConnection then
		return
	end
	
	local camera = workspace.CurrentCamera
	local shakeOffset = Vector3.new(0, 0, 0)
	local shakeTime = 0
	
	shakeConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if shakeIntensity <= 0 then
			-- No shake, reset camera
			camera.CFrame = camera.CFrame - shakeOffset
			shakeOffset = Vector3.new(0, 0, 0)
			return
		end
		
		-- Remove previous shake
		camera.CFrame = camera.CFrame - shakeOffset
		
		-- Calculate new shake
		shakeTime = shakeTime + deltaTime * 10
		local offsetX = math.sin(shakeTime * 2.1) * shakeIntensity * 0.05
		local offsetY = math.cos(shakeTime * 1.7) * shakeIntensity * 0.05
		local offsetZ = math.sin(shakeTime * 2.5) * shakeIntensity * 0.02
		
		shakeOffset = Vector3.new(offsetX, offsetY, offsetZ)
		
		-- Apply new shake
		camera.CFrame = camera.CFrame + shakeOffset
	end)
	
	print("[SanityEffects] Mouse shake started")
end

-- Update vignette transparency
function SanityEffects:_UpdateVignette()
	if not vignetteFrame then
		return
	end
	
	-- Update transparency of all 4 edge frames
	local targetTransparency = 1 - vignetteAmount
	
	local TweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	for _, edge in pairs(vignetteFrame:GetChildren()) do
		if edge:IsA("Frame") then
			local tween = TweenService:Create(edge, tweenInfo, {
				BackgroundTransparency = targetTransparency
			})
			tween:Play()
		end
	end
end

-- Start audio loop for schizo sounds
function SanityEffects:_StartAudioLoop()
	if audioConnection then
		return
	end
	
	audioTimer = 0
	
	audioConnection = RunService.Heartbeat:Connect(function(deltaTime)
		local audioFrequency = AUDIO_CONFIG[currentLevel]
		
		if not audioFrequency or audioFrequency == 0 then
			audioTimer = 0
			return
		end
		
		audioTimer = audioTimer + deltaTime
		
		if audioTimer >= audioFrequency then
			audioTimer = 0
			self:_PlaySchizoSound()
		end
	end)
	
	print("[SanityEffects] Audio loop started")
end

-- Play random schizo sound
function SanityEffects:_PlaySchizoSound()
	-- TODO: Add actual sound assets here
	print(string.format("[SanityEffects] Playing schizo sound (Level %d)", currentLevel))
	
	-- Placeholder: Play a random built-in sound for testing
	-- local sound = Instance.new("Sound")
	-- sound.SoundId = "rbxasset://sounds/..."
	-- sound.Volume = 0.3
	-- sound.Parent = player.PlayerGui
	-- sound:Play()
	-- sound.Ended:Connect(function() sound:Destroy() end)
end

-- Cleanup
function SanityEffects:Cleanup()
	if shakeConnection then
		shakeConnection:Disconnect()
		shakeConnection = nil
	end
	
	if audioConnection then
		audioConnection:Disconnect()
		audioConnection = nil
	end
	
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	
	print("[SanityEffects] Cleaned up")
end

-- Initialize on script load
SanityEffects:Init()

return SanityEffects
