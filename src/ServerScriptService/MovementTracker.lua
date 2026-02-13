--[[
	MovementTracker: Tracks player movement and distinguishes between walking/running
	
	Movement States:
		IDLE - Player is standing still or moving very slowly
		SNEAKING - Player is crouching/moving slowly (stealth)
		WALKING - Player is walking (normal movement)
		RUNNING - Player is running/sprinting (fast movement)
	
	Features:
		- Per-player movement tracking
		- Real-time speed detection
		- Configurable speed thresholds
		- Movement state change events
		- Distance tracking over time periods
		- Integration with monster systems (whisper monster)
	
	Use cases:
		- Whisper monster: punish players who run during whisper phase
		- Stealth mechanics: different consequences for running vs walking
		- Audio system: footstep sounds based on movement state
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MovementTracker = {}
MovementTracker.__index = MovementTracker

-- Movement state enum
MovementTracker.States = {
	IDLE = "IDLE",
	SNEAKING = "SNEAKING",
	WALKING = "WALKING",
	RUNNING = "RUNNING"
}

-- Speed thresholds (studs per second)
-- Using hysteresis to prevent flickering between states
local SPEED_THRESHOLDS = {
	IDLE_MAX = 3,        -- Below this = IDLE
	SNEAKING_MIN = 2,    -- Need to exceed this to enter SNEAKING from IDLE
	SNEAKING_MAX = 11,   -- Below this = stay in SNEAKING
	WALKING_MIN = 14,    -- Need to exceed this to enter WALKING from SNEAKING
	WALKING_MAX = 19,    -- Below this = stay in WALKING
	RUNNING_MIN = 21,    -- Need to exceed this to enter RUNNING from WALKING
	-- Above RUNNING_MIN = RUNNING
}

function MovementTracker.new()
	local self = setmetatable({}, MovementTracker)
	
	-- Per-player tracking data
	-- {userId = {player, humanoid, state, speed, lastPosition, distanceMoved, monitoringEndTime}}
	self._playerData = {}
	
	-- Events
	self.MovementStateChanged = Instance.new("BindableEvent")
	
	-- Main tracking loop
	self._trackingConnection = nil
	
	-- Listen for players joining/leaving
	Players.PlayerAdded:Connect(function(player)
		self:_OnPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_OnPlayerRemoving(player)
	end)
	
	-- Initialize existing players
	for _, player in Players:GetPlayers() do
		self:_OnPlayerAdded(player)
	end
	
	-- Start tracking loop
	self:_StartTracking()
	
	print("[MovementTracker] Movement tracking system initialized")
	
	return self
end

-- Player joined - setup tracking
function MovementTracker:_OnPlayerAdded(player)
	-- Wait for character
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	
	self._playerData[player.UserId] = {
		player = player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		state = MovementTracker.States.IDLE,
		speed = 0,
		lastPosition = rootPart.Position,
		distanceMoved = 0,
		monitoringEndTime = 0,  -- For timed monitoring (whisper monster)
		totalRunDistance = 0     -- Distance moved while running
	}
	
	-- Listen for character respawn
	player.CharacterAdded:Connect(function(newCharacter)
		local newHumanoid = newCharacter:WaitForChild("Humanoid")
		local newRootPart = newCharacter:WaitForChild("HumanoidRootPart")
		
		local data = self._playerData[player.UserId]
		if data then
			data.character = newCharacter
			data.humanoid = newHumanoid
			data.rootPart = newRootPart
			data.state = MovementTracker.States.IDLE
			data.speed = 0
			data.lastPosition = newRootPart.Position
			data.distanceMoved = 0
			data.totalRunDistance = 0
		end
	end)
	
	print(string.format("[MovementTracker] Started tracking player: %s", player.Name))
end

-- Player left - cleanup
function MovementTracker:_OnPlayerRemoving(player)
	self._playerData[player.UserId] = nil
	print(string.format("[MovementTracker] Stopped tracking player: %s", player.Name))
end

-- Start main tracking loop
function MovementTracker:_StartTracking()
	if self._trackingConnection then
		return
	end
	
	local lastUpdateTime = tick()
	
	self._trackingConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local deltaTime = currentTime - lastUpdateTime
		lastUpdateTime = currentTime
		
		for userId, data in pairs(self._playerData) do
			if data.character and data.humanoid and data.humanoid.Health > 0 and data.rootPart then
				self:_UpdatePlayerMovement(data, deltaTime, currentTime)
			end
		end
	end)
	
	print("[MovementTracker] Tracking loop started")
end

-- Update single player's movement data
function MovementTracker:_UpdatePlayerMovement(data, deltaTime, currentTime)
	local currentPosition = data.rootPart.Position
	local previousPosition = data.lastPosition
	
	-- Calculate distance moved this frame
	local displacement = (currentPosition - previousPosition).Magnitude
	data.distanceMoved = data.distanceMoved + displacement
	
	-- Calculate speed (studs per second)
	data.speed = displacement / deltaTime
	
	-- Determine movement state based on speed (with hysteresis to prevent flickering)
	local newState = data.state -- Start with current state
	
	-- State machine with hysteresis
	if data.state == MovementTracker.States.IDLE then
		if data.speed > SPEED_THRESHOLDS.SNEAKING_MIN then
			if data.speed > SPEED_THRESHOLDS.RUNNING_MIN then
				newState = MovementTracker.States.RUNNING
			elseif data.speed > SPEED_THRESHOLDS.WALKING_MIN then
				newState = MovementTracker.States.WALKING
			else
				newState = MovementTracker.States.SNEAKING
			end
		end
		
	elseif data.state == MovementTracker.States.SNEAKING then
		if data.speed <= SPEED_THRESHOLDS.IDLE_MAX then
			newState = MovementTracker.States.IDLE
		elseif data.speed > SPEED_THRESHOLDS.WALKING_MIN then
			if data.speed > SPEED_THRESHOLDS.RUNNING_MIN then
				newState = MovementTracker.States.RUNNING
			else
				newState = MovementTracker.States.WALKING
			end
		end
		
	elseif data.state == MovementTracker.States.WALKING then
		if data.speed <= SPEED_THRESHOLDS.SNEAKING_MAX then
			if data.speed <= SPEED_THRESHOLDS.IDLE_MAX then
				newState = MovementTracker.States.IDLE
			else
				newState = MovementTracker.States.SNEAKING
			end
		elseif data.speed > SPEED_THRESHOLDS.RUNNING_MIN then
			newState = MovementTracker.States.RUNNING
		end
		
	elseif data.state == MovementTracker.States.RUNNING then
		if data.speed <= SPEED_THRESHOLDS.WALKING_MAX then
			if data.speed <= SPEED_THRESHOLDS.SNEAKING_MAX then
				if data.speed <= SPEED_THRESHOLDS.IDLE_MAX then
					newState = MovementTracker.States.IDLE
				else
					newState = MovementTracker.States.SNEAKING
				end
			else
				newState = MovementTracker.States.WALKING
			end
		end
	end
	
	-- Track running distance (for whisper monster)
	if newState == MovementTracker.States.RUNNING then
		data.totalRunDistance = data.totalRunDistance + displacement
	end
	
	-- Check for state change
	if newState ~= data.state then
		local oldState = data.state
		data.state = newState
		
		-- Fire state change event
		self.MovementStateChanged:Fire(data.player, newState, oldState)
		
		print(string.format("[MovementTracker] %s movement: %s → %s (%.1f studs/s)", 
			data.player.Name, oldState, newState, data.speed))
	end
	
	-- Update last position
	data.lastPosition = currentPosition
end

-- Get player's current movement state
function MovementTracker:GetState(player)
	local data = self._playerData[player.UserId]
	return data and data.state or MovementTracker.States.IDLE
end

-- Get player's current speed
function MovementTracker:GetSpeed(player)
	local data = self._playerData[player.UserId]
	return data and data.speed or 0
end

-- Get total distance moved by player
function MovementTracker:GetDistanceMoved(player)
	local data = self._playerData[player.UserId]
	return data and data.distanceMoved or 0
end

-- Start monitoring player for a specific duration (for whisper monster)
function MovementTracker:StartMonitoring(player, duration)
	local data = self._playerData[player.UserId]
	if not data then
		return
	end
	
	data.monitoringEndTime = tick() + duration
	data.totalRunDistance = 0  -- Reset run distance counter
	
	print(string.format("[MovementTracker] Started monitoring %s for %d seconds", player.Name, duration))
end

-- Check if player is currently being monitored
function MovementTracker:IsMonitoring(player)
	local data = self._playerData[player.UserId]
	if not data then
		return false
	end
	
	return tick() < data.monitoringEndTime
end

-- Get distance player ran during monitoring period
function MovementTracker:GetRunDistance(player)
	local data = self._playerData[player.UserId]
	return data and data.totalRunDistance or 0
end

-- Stop monitoring player early
function MovementTracker:StopMonitoring(player)
	local data = self._playerData[player.UserId]
	if not data then
		return
	end
	
	data.monitoringEndTime = 0
	print(string.format("[MovementTracker] Stopped monitoring %s", player.Name))
end

-- Reset distance counter for player
function MovementTracker:ResetDistance(player)
	local data = self._playerData[player.UserId]
	if not data then
		return
	end
	
	data.distanceMoved = 0
	data.totalRunDistance = 0
end

-- Get all players in a specific movement state
function MovementTracker:GetPlayersInState(state)
	local players = {}
	
	for userId, data in pairs(self._playerData) do
		if data.state == state then
			table.insert(players, data.player)
		end
	end
	
	return players
end

-- Cleanup
function MovementTracker:Cleanup()
	if self._trackingConnection then
		self._trackingConnection:Disconnect()
		self._trackingConnection = nil
	end
	
	self._playerData = {}
	
	print("[MovementTracker] Cleaned up")
end

return MovementTracker
