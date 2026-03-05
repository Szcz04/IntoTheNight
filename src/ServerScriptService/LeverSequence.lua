--[[
	LeverSequence: Manages 4 levers that must be activated in correct order
	
	To restore power, players must activate 4 levers in the correct sequence.
	- Wrong lever adds 10 second penalty to death timer
	- Correct sequence restores power
	- Uses CollectionService tags to find levers in workspace
	
	Setup:
	1. Create 4 Lever models in workspace (with frame, light, pull structure)
	2. Tag them with "Lever" tag
	3. Set an IntValue attribute "LeverNumber" (1-4) on each Model
	4. This system will connect to existing ClickDetectors
	
	Lever structure expected:
	- Lever (Model) - tagged with "Lever", has "LeverNumber" attribute
	  - frame (Model with parts)
	  - light (Model with blinker part for visual feedback)
	  - pull (Model)
	    - hitbox (Part with ClickDetector)
	
	Later: Add monster "traces" as hints for correct order
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local LeverSequence = {}
LeverSequence.__index = LeverSequence

function LeverSequence.new(powerManager, gameState)
	local self = setmetatable({}, LeverSequence)
	
	self._powerManager = powerManager
	self._gameState = gameState
	
	-- Lever state
	self._levers = {} -- Array of {model, leverNumber, clickDetector, hitbox, blinker}
	self._correctSequence = {} -- e.g. {3, 1, 4, 2}
	self._playerProgress = {} -- {playerUserId = {currentStep, activatedLevers}}
	
	-- Discover and setup levers
	self:_DiscoverLevers()
	self:_GenerateSequence()
	self:_SetupClickDetectors()
	
	-- Listen to power state changes to reset levers
	self._powerManager.PowerStateChanged.Event:Connect(function(newState, oldState)
		self:_OnPowerStateChanged(newState, oldState)
	end)
	
	-- CRITICAL FIX: Clean up player progress when players leave (prevent memory leak)
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		if self._playerProgress[player.UserId] then
			self._playerProgress[player.UserId] = nil
			print(string.format("[LeverSequence] Cleaned up progress for %s", player.Name))
		end
	end)
	
	print("[LeverSequence] Lever system initialized with", #self._levers, "levers")
	
	return self
end

-- Find all lever Models with "Lever" tag
function LeverSequence:_DiscoverLevers()
	local taggedLevers = CollectionService:GetTagged("Lever")
	
	for _, leverModel in ipairs(taggedLevers) do
		if not leverModel:IsA("Model") then
			warn("[LeverSequence] Tagged object", leverModel.Name, "is not a Model. Skipping.")
			continue
		end
		
		local leverNumber = leverModel:GetAttribute("LeverNumber")
		
		if not leverNumber or leverNumber < 1 or leverNumber > 4 then
			warn("[LeverSequence] Lever", leverModel.Name, "has invalid or missing LeverNumber attribute (should be 1-4)")
			continue
		end
		
		-- Find hitbox with ClickDetector
		local pullModel = leverModel:FindFirstChild("pull")
		if not pullModel then
			warn("[LeverSequence] Lever", leverModel.Name, "missing 'pull' model")
			continue
		end
		
		local hitbox = pullModel:FindFirstChild("hitbox")
		if not hitbox then
			warn("[LeverSequence] Lever", leverModel.Name, "missing 'hitbox' part in pull model")
			continue
		end
		
		local clickDetector = hitbox:FindFirstChildOfClass("ClickDetector")
		if not clickDetector then
			warn("[LeverSequence] Lever", leverModel.Name, "missing ClickDetector in hitbox")
			continue
		end
		
		-- Find blinker for visual feedback (optional)
		local lightModel = leverModel:FindFirstChild("light")
		local blinker = lightModel and lightModel:FindFirstChild("blinker")
		
		-- Find lever sound (optional)
		local leverSound = hitbox:FindFirstChild("Lever sound")
		
		-- Initialize enabled attribute if not present
		if leverModel:GetAttribute("enabled") == nil then
			leverModel:SetAttribute("enabled", true) -- Start in UP position
		end
		
		table.insert(self._levers, {
			model = leverModel,
			leverNumber = leverNumber,
			clickDetector = clickDetector,
			hitbox = hitbox,
			blinker = blinker,
			leverSound = leverSound,
			initialCFrame = hitbox.CFrame, -- Store initial position
			isAnimating = false -- Prevent multiple clicks during animation
		})
		
		print("[LeverSequence] ✓ Registered lever #" .. leverNumber .. ":", leverModel.Name)
	end
	
	-- Sort by lever number for cleaner logs
	table.sort(self._levers, function(a, b)
		return a.leverNumber < b.leverNumber
	end)
	
	if #self._levers ~= 4 then
		warn("[LeverSequence] Expected 4 levers but found " .. #self._levers .. ". Add more Models with 'Lever' tag and LeverNumber attributes.")
	end
end

-- Generate random sequence for this round
function LeverSequence:_GenerateSequence()
	-- Create array [1, 2, 3, 4] and shuffle it
	local sequence = {1, 2, 3, 4}
	
	-- Fisher-Yates shuffle
	for i = #sequence, 2, -1 do
		local j = math.random(1, i)
		sequence[i], sequence[j] = sequence[j], sequence[i]
	end
	
	self._correctSequence = sequence
	print("[LeverSequence] Generated sequence:", table.concat(sequence, " → "))
end

-- Connect to existing ClickDetectors
function LeverSequence:_SetupClickDetectors()
	for _, leverData in ipairs(self._levers) do
		-- Connect to existing ClickDetector
		leverData.clickDetector.MouseClick:Connect(function(player)
			self:_OnLeverPulled(player, leverData)
		end)
	end
	
	print("[LeverSequence] Connected to", #self._levers, "ClickDetectors")
end

-- Handle lever pull by player
function LeverSequence:_OnLeverPulled(player, leverData)
	-- Prevent multiple clicks during animation
	if leverData.isAnimating then
		return
	end
	
	local PowerStates = require(script.Parent.PowerManager).PowerStates
	local currentPowerState = self._powerManager:GetPowerState()
	
	-- Case 1: Power is ON - reject with bounce back
	if currentPowerState == PowerStates.ON then
		print(string.format("[LeverSequence] Player %s tried to pull lever #%d during POWER ON - rejected", 
			player.Name, leverData.leverNumber))
		self:_BounceBackLever(leverData)
		return
	end
	
	-- Power is OFF - check sequence
	-- Initialize player progress if first time
	if not self._playerProgress[player.UserId] then
		self._playerProgress[player.UserId] = {
			currentStep = 1,
			activatedLevers = {}
		}
	end
	
	local progress = self._playerProgress[player.UserId]
	local expectedLever = self._correctSequence[progress.currentStep]
	
	-- Check if this is the correct lever
	if leverData.leverNumber == expectedLever then
		-- Correct lever!
		print(string.format("[LeverSequence] Player %s pulled CORRECT lever #%d (step %d/4)", 
			player.Name, leverData.leverNumber, progress.currentStep))
		
		table.insert(progress.activatedLevers, leverData.leverNumber)
		progress.currentStep = progress.currentStep + 1
		
		-- Visual feedback: green blinker (stays lit)
		if leverData.blinker then
			leverData.blinker.Color = Color3.fromRGB(0, 255, 0)
		end
		
		-- Animate lever pull
		self:_PullLever(leverData)
		
		-- Check if sequence complete
		if progress.currentStep > 4 then
			print("[LeverSequence] Sequence complete! Restoring power...")
			self:_OnSequenceComplete(player)
		end
	else
		-- Wrong lever!
		warn(string.format("[LeverSequence] Player %s pulled WRONG lever #%d (expected #%d)", 
			player.Name, leverData.leverNumber, expectedLever))
		
		-- Reset progress
		progress.currentStep = 1
		progress.activatedLevers = {}
		
		-- Bounce back the clicked wrong lever
		self:_BounceBackLever(leverData)
		
		-- Visual feedback: red blinker on wrong lever (temporary)
		self:_SetBlinkerColor(leverData, Color3.fromRGB(255, 0, 0))
		
		-- Reset ALL other levers to UP position and reset their blinkers
		for _, lever in ipairs(self._levers) do
			if not lever.model:GetAttribute("enabled") and lever ~= leverData then
				self:_ResetLever(lever)
			end
			
			-- Reset blinker to default color
			if lever.blinker and lever ~= leverData then
				lever.blinker.Color = Color3.fromRGB(255, 105, 107) -- Default red
			end
		end
		
		-- Add penalty to timer
		self:_AddPenalty(player)
	end
end

-- Pull lever down/up (toggle enabled state)
function LeverSequence:_PullLever(leverData)
	leverData.isAnimating = true
	
	local model = leverData.model
	local hitbox = leverData.hitbox
	local isEnabled = model:GetAttribute("enabled")
	
	-- Play sound
	if leverData.leverSound then
		leverData.leverSound:Play()
	end
	
	-- Determine direction based on current state
	local targetCFrame
	if isEnabled then
		-- Pull FORWARD (disable)
		targetCFrame = leverData.initialCFrame * CFrame.new(0, 0, 1.275)
		model:SetAttribute("enabled", false)
	else
		-- Pull BACK (enable)
		targetCFrame = leverData.initialCFrame * CFrame.new(0, 0, -1.275)
		model:SetAttribute("enabled", true)
	end
	
	-- Create and play tween
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine)
	local tween = TweenService:Create(hitbox, tweenInfo, {CFrame = targetCFrame})
	
	tween:Play()
	tween.Completed:Wait()
	
	leverData.isAnimating = false
end

-- Bounce lever back (wrong lever or power ON)
function LeverSequence:_BounceBackLever(leverData)
	leverData.isAnimating = true
	
	local hitbox = leverData.hitbox
	local isEnabled = leverData.model:GetAttribute("enabled")
	
	-- Play sound
	if leverData.leverSound then
		leverData.leverSound:Play()
	end
	
	-- Determine bounce direction
	local bounceCFrame
	if isEnabled then
		-- Try to pull forward, but bounce back
		bounceCFrame = leverData.initialCFrame * CFrame.new(0, 0, 0.3)
	else
		-- Try to pull back, but bounce forward
		bounceCFrame = leverData.initialCFrame * CFrame.new(0, 0, -0.3)
	end
	
	-- Quick bounce out
	local bounceInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local bounceTween = TweenService:Create(hitbox, bounceInfo, {CFrame = bounceCFrame})
	
	bounceTween:Play()
	bounceTween.Completed:Wait()
	
	-- Return to original position
	local returnInfo = TweenInfo.new(0.25, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	local returnTween = TweenService:Create(hitbox, returnInfo, {CFrame = leverData.initialCFrame})
	
	returnTween:Play()
	returnTween.Completed:Wait()
	
	leverData.isAnimating = false
end

-- Set blinker color with temporary flash
function LeverSequence:_SetBlinkerColor(leverData, flashColor)
	if not leverData.blinker then
		return
	end
	
	local originalColor = leverData.blinker.Color
	leverData.blinker.Color = flashColor
	
	task.delay(0.5, function()
		leverData.blinker.Color = originalColor
	end)
end

-- Add 10 second penalty for wrong lever
function LeverSequence:_AddPenalty(player)
	local penaltySeconds = 10
	self._powerManager:AddPenaltyTime(penaltySeconds)
	print(string.format("[LeverSequence] Added %ds penalty to timer for %s", penaltySeconds, player.Name))
	
	-- TODO: Show UI message to player
end

-- Sequence completed successfully
function LeverSequence:_OnSequenceComplete(player)
	-- Reset all player progress
	self._playerProgress = {}
	
	-- Restore power
	self._powerManager:RestorePower()
	
	print("[LeverSequence] Power restored by", player.Name)
	
	-- TODO: Play success sound/effect
	-- TODO: Award points to player
end

-- Reset lever states when power changes
function LeverSequence:_OnPowerStateChanged(newState, oldState)
	local PowerStates = require(script.Parent.PowerManager).PowerStates
	
	if newState == PowerStates.OFF then
		-- New blackout: generate new sequence and reset progress
		self:_GenerateSequence()
		self._playerProgress = {}
		print("[LeverSequence] New blackout - generated new sequence")
		
	elseif newState == PowerStates.ON then
		-- Power restored: reset all levers to UP position and reset blinkers
		for _, leverData in ipairs(self._levers) do
			if not leverData.model:GetAttribute("enabled") then
				-- Lever is DOWN, pull it back UP
				self:_ResetLever(leverData)
			end
			
			-- Reset blinker to default color (red for emergency levers)
			if leverData.blinker then
				leverData.blinker.Color = Color3.fromRGB(255, 105, 107) -- Default red
			end
		end
	end
end

-- Reset lever to UP position (used when power restored)
function LeverSequence:_ResetLever(leverData)
	if leverData.isAnimating then
		return
	end
	
	leverData.isAnimating = true
	
	local model = leverData.model
	local hitbox = leverData.hitbox
	
	-- Set to enabled state
	model:SetAttribute("enabled", true)
	
	-- Animate back to UP position
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine)
	local tween = TweenService:Create(hitbox, tweenInfo, {CFrame = leverData.initialCFrame})
	
	tween:Play()
	tween.Completed:Wait()
	
	leverData.isAnimating = false
end

-- Dev command: Get current correct sequence
function LeverSequence:GetCorrectSequence()
	return self._correctSequence
end

-- Dev command: Reset all player progress
function LeverSequence:ResetAllProgress()
	self._playerProgress = {}
	print("[LeverSequence] All player progress reset")
end

return LeverSequence
