--[[
	SuspicionManager: Per-player social suspicion system

	Suspicion Levels:
		1 - SAFE (0-39)
		2 - NOTICED (40-69)
		3 - HOST_ALERT (70-99)
		4 - EXPOSED (100) - Player is exposed/eliminated

	Features:
		- Per-player suspicion tracking (0-100 scale)
		- Automatic level calculation based on thresholds
		- Events for suspicion updates and level changes
		- Exposure handling at maximum suspicion
		- Add/reduce/set methods with optional reasons

	Client feedback direction (not implemented here):
		- TODO: NPC stare indicators
		- TODO: subtle tension audio cues
		- TODO: suspicion HUD meter
		- TODO: host attention warning
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SuspicionManager = {}
SuspicionManager.__index = SuspicionManager

-- Suspicion level thresholds
SuspicionManager.Levels = {
	SAFE = 1,
	NOTICED = 2,
	HOST_ALERT = 3,
	EXPOSED = 4
}

function SuspicionManager.new(gameState)
	local self = setmetatable({}, SuspicionManager)

	self._gameState = gameState

	-- Per-player suspicion data: {userId = {suspicion, level, player, exposed}}
	self._playerSuspicion = {}

	-- Configuration
	self._maxSuspicion = 100
	self._startingSuspicion = 0
	self._exposeAtMax = true

	-- Events for communication with clients
	self._remoteEvent = self:_CreateRemoteEvent("SuspicionEvent")

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

	print("[SuspicionManager] Suspicion system initialized")

	return self
end

-- Create RemoteEvent for client communication
function SuspicionManager:_CreateRemoteEvent(eventName)
	local remoteEvent = ReplicatedStorage:FindFirstChild(eventName)
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = eventName
		remoteEvent.Parent = ReplicatedStorage
		print(string.format("[SuspicionManager] Created %s RemoteEvent", eventName))
	end
	return remoteEvent
end

-- Player joined - initialize their suspicion
function SuspicionManager:_OnPlayerAdded(player)
	self._playerSuspicion[player.UserId] = {
		suspicion = self._startingSuspicion,
		level = self:_CalculateLevel(self._startingSuspicion),
		player = player,
		exposed = false,
		eliminated = false -- Legacy compatibility with existing elimination checks
	}

	-- Notify client of initial suspicion
	self:_SendToClient(player, "Init", {
		suspicion = self._startingSuspicion,
		level = self:_CalculateLevel(self._startingSuspicion)
	})

	print(string.format("[SuspicionManager] Player %s initialized with suspicion: %d (Level %d)",
		player.Name, self._startingSuspicion, self:_CalculateLevel(self._startingSuspicion)))
end

-- Player left - cleanup
function SuspicionManager:_OnPlayerRemoving(player)
	self._playerSuspicion[player.UserId] = nil
	print(string.format("[SuspicionManager] Cleaned up suspicion data for %s", player.Name))
end

-- Calculate suspicion level from value
function SuspicionManager:_CalculateLevel(suspicion)
	if suspicion >= 100 then
		return SuspicionManager.Levels.EXPOSED
	elseif suspicion >= 70 then
		return SuspicionManager.Levels.HOST_ALERT
	elseif suspicion >= 40 then
		return SuspicionManager.Levels.NOTICED
	else
		return SuspicionManager.Levels.SAFE
	end
end

-- Get player's current suspicion
function SuspicionManager:GetSuspicion(player)
	local data = self._playerSuspicion[player.UserId]
	return data and data.suspicion or 0
end

-- Get player's current suspicion level
function SuspicionManager:GetLevel(player)
	local data = self._playerSuspicion[player.UserId]
	return data and data.level or SuspicionManager.Levels.EXPOSED
end

-- Increase player's suspicion
function SuspicionManager:AddSuspicion(player, amount, reason)
	local data = self._playerSuspicion[player.UserId]
	if not data then
		return
	end

	local delta = math.max(0, tonumber(amount) or 0)
	local oldSuspicion = data.suspicion
	local oldLevel = data.level

	-- TODO: increase suspicion when player runs in public zones (MovementTracker)
	-- TODO: increase suspicion when host command is ignored (HostCommandSystem)
	-- TODO: increase suspicion when observed performing sabotage (Witness/NPC observation)
	-- TODO: increase suspicion in restricted areas when witnessed

	data.suspicion = math.min(self._maxSuspicion, data.suspicion + delta)
	data.level = self:_CalculateLevel(data.suspicion)

	print(string.format("[SuspicionManager] %s gained %d suspicion (%s): %d -> %d (Level %d -> %d)",
		player.Name,
		delta,
		reason or "no reason",
		oldSuspicion,
		data.suspicion,
		oldLevel,
		data.level
	))

	self:_SendToClient(player, "Update", {
		suspicion = data.suspicion,
		level = data.level,
		oldLevel = oldLevel,
		reason = reason
	})

	if data.level ~= oldLevel then
		self:_OnLevelChanged(player, data.level, oldLevel)
	end

	if data.level == SuspicionManager.Levels.EXPOSED and self._exposeAtMax then
		self:_ExposePlayer(player, reason)
	end
end

-- Reduce player's suspicion
function SuspicionManager:ReduceSuspicion(player, amount, reason)
	local data = self._playerSuspicion[player.UserId]
	if not data then
		return
	end

	local delta = math.max(0, tonumber(amount) or 0)
	local oldSuspicion = data.suspicion
	local oldLevel = data.level

	-- TODO: passive suspicion decay while blending in crowds/complying

	data.suspicion = math.max(0, data.suspicion - delta)
	data.level = self:_CalculateLevel(data.suspicion)
	data.exposed = false
	data.eliminated = false

	print(string.format("[SuspicionManager] %s reduced %d suspicion (%s): %d -> %d (Level %d -> %d)",
		player.Name,
		delta,
		reason or "no reason",
		oldSuspicion,
		data.suspicion,
		oldLevel,
		data.level
	))

	self:_SendToClient(player, "Update", {
		suspicion = data.suspicion,
		level = data.level,
		oldLevel = oldLevel,
		reason = reason
	})

	if data.level ~= oldLevel then
		self:_OnLevelChanged(player, data.level, oldLevel)
	end
end

-- Set player's suspicion directly
function SuspicionManager:SetSuspicion(player, suspicion, reason)
	local data = self._playerSuspicion[player.UserId]
	if not data then
		return
	end

	local oldLevel = data.level
	local oldSuspicion = data.suspicion

	data.suspicion = math.clamp(tonumber(suspicion) or 0, 0, self._maxSuspicion)
	data.level = self:_CalculateLevel(data.suspicion)

	if data.level < SuspicionManager.Levels.EXPOSED then
		data.exposed = false
		data.eliminated = false
	end

	print(string.format("[SuspicionManager] %s suspicion set (%s): %d -> %d (Level %d -> %d)",
		player.Name,
		reason or "no reason",
		oldSuspicion,
		data.suspicion,
		oldLevel,
		data.level
	))

	self:_SendToClient(player, "Update", {
		suspicion = data.suspicion,
		level = data.level,
		oldLevel = oldLevel,
		reason = reason
	})

	if data.level ~= oldLevel then
		self:_OnLevelChanged(player, data.level, oldLevel)
	end

	if data.level == SuspicionManager.Levels.EXPOSED and self._exposeAtMax then
		self:_ExposePlayer(player, reason)
	end
end

-- Send update to client
function SuspicionManager:_SendToClient(player, action, data)
	self._remoteEvent:FireClient(player, action, data)
end

-- Handle suspicion level change
function SuspicionManager:_OnLevelChanged(player, newLevel, oldLevel)
	print(string.format("[SuspicionManager] %s suspicion level changed: %d -> %d",
		player.Name, oldLevel, newLevel))

	self:_SendToClient(player, "LevelChanged", {
		level = newLevel,
		oldLevel = oldLevel,
		suspicion = self:GetSuspicion(player)
	})
end

-- Mark player as exposed/eliminated (suspicion reached 100)
function SuspicionManager:_ExposePlayer(player, reason)
	local data = self._playerSuspicion[player.UserId]
	if not data or data.exposed then
		return
	end

	data.exposed = true
	data.eliminated = true -- Legacy compatibility

	warn(string.format("[SuspicionManager] PLAYER EXPOSED: %s (%s)", player.Name, reason or "suspicion maxed"))

	self:_SendToClient(player, "Exposed", {
		reason = reason,
		suspicion = data.suspicion
	})

	-- TODO: Integrate with proper elimination/exposure flow when implemented.
	-- For now, this only marks state and notifies clients/systems.
	print(string.format("[SuspicionManager] %s marked as exposed - awaiting elimination system integration", player.Name))
end

-- Reset all players' suspicion (for new round)
function SuspicionManager:ResetAll()
	for _, data in pairs(self._playerSuspicion) do
		data.suspicion = self._startingSuspicion
		data.level = self:_CalculateLevel(self._startingSuspicion)
		data.exposed = false
		data.eliminated = false

		self:_SendToClient(data.player, "Init", {
			suspicion = data.suspicion,
			level = data.level
		})
	end

	print("[SuspicionManager] Reset all players' suspicion")
end

return SuspicionManager