--[[
	SanityManager: Per-player mental health system
	
	Sanity Levels:
		1 - Healthy (100-80%)
		2 - Uneasy (79-60%)
		3 - Disturbed (59-40%)
		4 - Panicked (39-20%)
		5 - Broken (19-0%) - Player is eliminated
	
	Features:
		- Per-player sanity tracking (0-100 scale)
		- Automatic level calculation based on percentage
		- Events for sanity changes and level changes
		- Player elimination at level 5
		- Damage and healing methods
		- Configurable elimination behavior
	
	Effects (handled by client-side SanityEffects.lua):
		- Mouse shake (intensity increases with level)
		- Screen vignette (red overlay, darker at higher levels)
		- Schizo audio (random sounds, frequency increases with level)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SanityManager = {}
SanityManager.__index = SanityManager

-- Sanity level thresholds (percentage)
SanityManager.Levels = {
	HEALTHY = 1,    -- 100-80%
	UNEASY = 2,     -- 79-60%
	DISTURBED = 3,  -- 59-40%
	PANICKED = 4,   -- 39-20%
	BROKEN = 5      -- 19-0%
}

function SanityManager.new(gameState)
	local self = setmetatable({}, SanityManager)
	
	self._gameState = gameState
	
	-- Per-player sanity data: {userId = {sanity, level, effects}}
	self._playerSanity = {}
	
	-- Configuration
	self._maxSanity = 100
	self._startingSanity = 100
	self._eliminateAtBroken = true -- Eliminate players at level 5
	
	-- Events for communication with clients
	self._remoteEvent = self:_CreateRemoteEvent()
	
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
	
	print("[SanityManager] Sanity system initialized")
	
	return self
end

-- Create RemoteEvent for client communication
function SanityManager:_CreateRemoteEvent()
	local remoteEvent = ReplicatedStorage:FindFirstChild("SanityEvent")
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = "SanityEvent"
		remoteEvent.Parent = ReplicatedStorage
		print("[SanityManager] Created SanityEvent RemoteEvent")
	end
	return remoteEvent
end

-- Player joined - initialize their sanity
function SanityManager:_OnPlayerAdded(player)
	self._playerSanity[player.UserId] = {
		sanity = self._startingSanity,
		level = self:_CalculateLevel(self._startingSanity),
		player = player
	}
	
	-- Notify client of initial sanity
	self:_SendToClient(player, "Init", {
		sanity = self._startingSanity,
		level = self:_CalculateLevel(self._startingSanity)
	})
	
	print(string.format("[SanityManager] Player %s initialized with sanity: %d (Level %d)", 
		player.Name, self._startingSanity, self:_CalculateLevel(self._startingSanity)))
end

-- Player left - cleanup
function SanityManager:_OnPlayerRemoving(player)
	self._playerSanity[player.UserId] = nil
	print(string.format("[SanityManager] Cleaned up sanity data for %s", player.Name))
end

-- Calculate sanity level from percentage
function SanityManager:_CalculateLevel(sanity)
	local percentage = (sanity / self._maxSanity) * 100
	
	if percentage >= 80 then
		return SanityManager.Levels.HEALTHY
	elseif percentage >= 60 then
		return SanityManager.Levels.UNEASY
	elseif percentage >= 40 then
		return SanityManager.Levels.DISTURBED
	elseif percentage >= 20 then
		return SanityManager.Levels.PANICKED
	else
		return SanityManager.Levels.BROKEN
	end
end

-- Get player's current sanity
function SanityManager:GetSanity(player)
	local data = self._playerSanity[player.UserId]
	return data and data.sanity or 0
end

-- Get player's current sanity level
function SanityManager:GetLevel(player)
	local data = self._playerSanity[player.UserId]
	return data and data.level or SanityManager.Levels.BROKEN
end

-- Damage player's sanity
function SanityManager:DamageSanity(player, amount)
	local data = self._playerSanity[player.UserId]
	if not data then
		return
	end
	
	local oldSanity = data.sanity
	local oldLevel = data.level
	
	-- Apply damage
	data.sanity = math.max(0, data.sanity - amount)
	data.level = self:_CalculateLevel(data.sanity)
	
	print(string.format("[SanityManager] %s took %d sanity damage: %d → %d (Level %d → %d)", 
		player.Name, amount, oldSanity, data.sanity, oldLevel, data.level))
	
	-- Notify client
	self:_SendToClient(player, "Update", {
		sanity = data.sanity,
		level = data.level,
		oldLevel = oldLevel
	})
	
	-- Check for level change
	if data.level ~= oldLevel then
		self:_OnLevelChanged(player, data.level, oldLevel)
	end
	
	-- Check for elimination
	if data.level == SanityManager.Levels.BROKEN and self._eliminateAtBroken then
		self:_EliminatePlayer(player)
	end
end

-- Heal player's sanity
function SanityManager:HealSanity(player, amount)
	local data = self._playerSanity[player.UserId]
	if not data then
		return
	end
	
	local oldSanity = data.sanity
	local oldLevel = data.level
	
	-- Apply healing
	data.sanity = math.min(self._maxSanity, data.sanity + amount)
	data.level = self:_CalculateLevel(data.sanity)
	
	print(string.format("[SanityManager] %s healed %d sanity: %d → %d (Level %d → %d)", 
		player.Name, amount, oldSanity, data.sanity, oldLevel, data.level))
	
	-- Notify client
	self:_SendToClient(player, "Update", {
		sanity = data.sanity,
		level = data.level,
		oldLevel = oldLevel
	})
	
	-- Check for level change
	if data.level ~= oldLevel then
		self:_OnLevelChanged(player, data.level, oldLevel)
	end
end

-- Set player's sanity directly
function SanityManager:SetSanity(player, sanity)
	local data = self._playerSanity[player.UserId]
	if not data then
		return
	end
	
	local oldLevel = data.level
	
	data.sanity = math.clamp(sanity, 0, self._maxSanity)
	data.level = self:_CalculateLevel(data.sanity)
	
	-- Notify client
	self:_SendToClient(player, "Update", {
		sanity = data.sanity,
		level = data.level,
		oldLevel = oldLevel
	})
	
	-- Check for level change
	if data.level ~= oldLevel then
		self:_OnLevelChanged(player, data.level, oldLevel)
	end
	
	-- Check for elimination
	if data.level == SanityManager.Levels.BROKEN and self._eliminateAtBroken then
		self:_EliminatePlayer(player)
	end
end

-- Send update to client
function SanityManager:_SendToClient(player, action, data)
	self._remoteEvent:FireClient(player, action, data)
end

-- Handle sanity level change
function SanityManager:_OnLevelChanged(player, newLevel, oldLevel)
	print(string.format("[SanityManager] %s sanity level changed: %d → %d", 
		player.Name, oldLevel, newLevel))
	
	-- Notify client of level change
	self:_SendToClient(player, "LevelChanged", {
		level = newLevel,
		oldLevel = oldLevel
	})
	
	-- TODO: Trigger specific effects based on level
	-- e.g., play sound, show warning message, etc.
end

-- Eliminate player (sanity reached 0)
function SanityManager:_EliminatePlayer(player)
	warn(string.format("[SanityManager] PLAYER ELIMINATED: %s (sanity broken)", player.Name))
	
	-- Notify client
	self:_SendToClient(player, "Eliminated", {})
	
	-- Mark player as eliminated (for future elimination system)
	local data = self._playerSanity[player.UserId]
	if data then
		data.eliminated = true
	end
	
	-- TODO: Integrate with proper elimination system when implemented
	-- For now, just log the elimination
	print(string.format("[SanityManager] %s marked as eliminated - awaiting elimination system integration", player.Name))
end

-- Reset all players' sanity (for new round)
function SanityManager:ResetAll()
	for userId, data in pairs(self._playerSanity) do
		data.sanity = self._startingSanity
		data.level = self:_CalculateLevel(self._startingSanity)
		
		self:_SendToClient(data.player, "Init", {
			sanity = data.sanity,
			level = data.level
		})
	end
	
	print("[SanityManager] Reset all players' sanity")
end

return SanityManager
