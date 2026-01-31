--[[
	GameState: Single source of truth for the game round state
	
	States:
		WAITING - Players in lobby, no active run
		RUNNING - Train run active, systems live
		ENDING  - Round over, preparing to reset
	
	This module broadcasts state changes via events.
	Other systems subscribe and react accordingly.
]]

local GameState = {}
GameState.__index = GameState

-- State enum
GameState.States = {
	WAITING = "WAITING",
	RUNNING = "RUNNING",
	ENDING = "ENDING"
}

function GameState.new()
	local self = setmetatable({}, GameState)
	
	-- Current state
	self._currentState = GameState.States.WAITING
	
	-- Events for state changes
	self.StateChanged = Instance.new("BindableEvent")
	
	return self
end

-- Get current state (read-only access)
function GameState:GetState()
	return self._currentState
end

-- Transition to a new state
function GameState:SetState(newState)
	if self._currentState == newState then
		warn("[GameState] Already in state:", newState)
		return
	end
	
	local oldState = self._currentState
	self._currentState = newState
	
	print(string.format("[GameState] %s → %s", oldState, newState))
	
	-- Broadcast the change
	self.StateChanged:Fire(newState, oldState)
end

-- Check if in a specific state
function GameState:IsState(state)
	return self._currentState == state
end

return GameState
