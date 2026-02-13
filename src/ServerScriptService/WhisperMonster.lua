--[[
	WhisperMonster: Audio-based monster that punishes movement
	
	Behavior:
		1. Plays whisper sound to all players
		2. Waits 1 second (grace period for player reaction)
		3. Tracks all players' movement for 10 seconds
		4. Calculates damage based on movement states:
			- RUNNING: 30 sanity damage (full time)
			- WALKING: 10 sanity damage (full time)
			- SNEAKING: 0 damage (safe)
			- IDLE: 0 damage (safe)
		5. Applies sanity damage proportionally
	
	Strategy: Players should crouch or stand still when they hear whispers
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local WhisperMonster = {}
WhisperMonster.__index = WhisperMonster

-- Damage configuration (for 10 full seconds in state)
local DAMAGE_CONFIG = {
	RUNNING = 30,  -- Maximum punishment for running
	WALKING = 10,  -- Moderate punishment for walking
	SNEAKING = 0,  -- Safe
	IDLE = 0       -- Safe
}

-- Timing configuration
local GRACE_PERIOD = 1    -- Seconds before tracking starts
local TRACKING_DURATION = 10  -- Seconds to track movement

function WhisperMonster.new(movementTracker, sanityManager)
	local self = setmetatable({}, WhisperMonster)
	
	self._movementTracker = movementTracker
	self._sanityManager = sanityManager
	
	-- Whisper sound (placeholder)
	self._whisperSound = nil
	self:_CreateWhisperSound()
	
	-- Active event tracking
	self._isActive = false
	self._trackingData = {} -- {userId = {timeInState = {IDLE=0, SNEAKING=0, WALKING=0, RUNNING=0}}}
	
	-- Listen to movement state changes during tracking
	self._movementConnection = nil
	
	print("[WhisperMonster] Whisper monster initialized")
	
	return self
end

-- Create placeholder whisper sound
function WhisperMonster:_CreateWhisperSound()
	-- Find or create sound in SoundService
	self._whisperSound = SoundService:FindFirstChild("WhisperSound")
	
	if not self._whisperSound then
		self._whisperSound = Instance.new("Sound")
		self._whisperSound.Name = "WhisperSound"
		-- TODO: Replace with actual whisper sound asset
		-- Placeholder: Use Roblox's built-in spooky sound
		self._whisperSound.SoundId = "rbxassetid://9120386436" -- Whisper placeholder
		self._whisperSound.Volume = 0.5
		self._whisperSound.Parent = SoundService
		print("[WhisperMonster] Created whisper sound (placeholder)")
	end
end

-- Trigger whisper event
function WhisperMonster:TriggerWhisper()
	if self._isActive then
		warn("[WhisperMonster] Whisper event already active, ignoring trigger")
		return
	end
	
	print("[WhisperMonster] 🔊 WHISPER EVENT TRIGGERED")
	self._isActive = true
	
	-- Play whisper sound for all players
	self:_PlayWhisperSound()
	
	-- Initialize tracking data for all players
	self:_InitializeTracking()
	
	-- Wait grace period
	print(string.format("[WhisperMonster] Grace period: %d second(s)...", GRACE_PERIOD))
	task.wait(GRACE_PERIOD)
	
	-- Start tracking movement
	print(string.format("[WhisperMonster] Tracking movement for %d seconds...", TRACKING_DURATION))
	self:_StartTracking()
	
	-- Wait tracking duration
	task.wait(TRACKING_DURATION)
	
	-- Stop tracking and calculate damage
	self:_StopTracking()
	self:_CalculateAndApplyDamage()
	
	self._isActive = false
	print("[WhisperMonster] Whisper event ended")
end

-- Play whisper sound to all players
function WhisperMonster:_PlayWhisperSound()
	if self._whisperSound then
		self._whisperSound:Play()
		print("[WhisperMonster] Playing whisper sound...")
	else
		warn("[WhisperMonster] No whisper sound available")
	end
end

-- Initialize tracking data for all players
function WhisperMonster:_InitializeTracking()
	self._trackingData = {}
	
	for _, player in Players:GetPlayers() do
		self._trackingData[player.UserId] = {
			player = player,
			timeInState = {
				IDLE = 0,
				SNEAKING = 0,
				WALKING = 0,
				RUNNING = 0
			},
			currentState = self._movementTracker:GetState(player),
			lastUpdateTime = tick()
		}
	end
	
	print(string.format("[WhisperMonster] Initialized tracking for %d players", #Players:GetPlayers()))
end

-- Start tracking player movement
function WhisperMonster:_StartTracking()
	local startTime = tick()
	local endTime = startTime + TRACKING_DURATION
	
	-- Track time spent in each state
	self._movementConnection = game:GetService("RunService").Heartbeat:Connect(function()
		local currentTime = tick()
		
		if currentTime >= endTime then
			return -- Will be disconnected in _StopTracking
		end
		
		for userId, data in pairs(self._trackingData) do
			local currentState = self._movementTracker:GetState(data.player)
			local deltaTime = currentTime - data.lastUpdateTime
			
			-- Add time to current state
			if data.timeInState[currentState] then
				data.timeInState[currentState] = data.timeInState[currentState] + deltaTime
			end
			
			data.currentState = currentState
			data.lastUpdateTime = currentTime
		end
	end)
end

-- Stop tracking
function WhisperMonster:_StopTracking()
	if self._movementConnection then
		self._movementConnection:Disconnect()
		self._movementConnection = nil
	end
	
	print("[WhisperMonster] Stopped tracking")
end

-- Calculate and apply damage based on movement
function WhisperMonster:_CalculateAndApplyDamage()
	print("[WhisperMonster] Calculating damage...")
	
	for userId, data in pairs(self._trackingData) do
		local player = data.player
		local timeInState = data.timeInState
		
		-- Calculate damage proportionally
		local totalDamage = 0
		
		for state, timeSpent in pairs(timeInState) do
			local damagePerSecond = (DAMAGE_CONFIG[state] or 0) / TRACKING_DURATION
			local stateDamage = damagePerSecond * timeSpent
			totalDamage = totalDamage + stateDamage
		end
		
		-- Round to integer
		totalDamage = math.floor(totalDamage + 0.5)
		
		-- Log breakdown
		print(string.format("[WhisperMonster] %s movement breakdown:", player.Name))
		print(string.format("  IDLE: %.1fs | SNEAKING: %.1fs | WALKING: %.1fs | RUNNING: %.1fs", 
			timeInState.IDLE, timeInState.SNEAKING, timeInState.WALKING, timeInState.RUNNING))
		print(string.format("  Total damage: %d sanity", totalDamage))
		
		-- Apply damage
		if totalDamage > 0 then
			self._sanityManager:DamageSanity(player, totalDamage)
			warn(string.format("[WhisperMonster] ⚠️ %s took %d sanity damage from whisper!", player.Name, totalDamage))
		else
			print(string.format("[WhisperMonster] ✓ %s survived safely (0 damage)", player.Name))
		end
	end
	
	self._trackingData = {}
end

-- Check if whisper event is currently active
function WhisperMonster:IsActive()
	return self._isActive
end

-- Change whisper sound asset
function WhisperMonster:SetWhisperSound(soundId)
	if self._whisperSound then
		self._whisperSound.SoundId = soundId
		print(string.format("[WhisperMonster] Updated whisper sound to: %s", soundId))
	end
end

return WhisperMonster
