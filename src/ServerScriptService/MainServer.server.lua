--[[
	MainServer: Orchestrates core game systems
	
	Responsibilities:
		- Initialize all core systems
		- Wire up system interactions
		- Manage round flow (WAITING → RUNNING → ENDING)
		- Handle fail conditions
	
	Systems are modular. They communicate via events, not direct calls.
]]

print("=== IntoTheNight - Server Starting ===")

-- Services
local ServerScriptService = game:GetService("ServerScriptService")

-- Core modules
local GameState = require(ServerScriptService.GameState)
local PowerManager = require(ServerScriptService.PowerManager)
local LightingController = require(ServerScriptService.LightingController)
local AudioController = require(ServerScriptService.AudioController)

-- Initialize systems
print("[MainServer] Initializing core systems...")

local gameState = GameState.new()
local powerManager = PowerManager.new()
local lightingController = LightingController.new(powerManager)
local audioController = AudioController.new(powerManager)

print("[MainServer] All systems initialized")

-- Listen for game state changes
gameState.StateChanged.Event:Connect(function(newState, oldState)
	print(string.format("[MainServer] Game state changed: %s → %s", oldState, newState))
	
	if newState == GameState.States.RUNNING then
		-- Round started: power starts ON
		print("[MainServer] Round starting...")
		powerManager:RestorePower()
		
	elseif newState == GameState.States.ENDING then
		-- Round ended: reset systems
		print("[MainServer] Round ending...")
		powerManager:Reset()
	end
end)

-- Listen for power timeout (death condition)
powerManager.PowerTimeout.Event:Connect(function()
	print("[MainServer] POWER TIMEOUT - PLAYERS DEAD")
	
	-- Transition to ENDING state
	if gameState:IsState(GameState.States.RUNNING) then
		gameState:SetState(GameState.States.ENDING)
		
		-- Wait a few seconds, then reset to WAITING
		task.wait(3)
		gameState:SetState(GameState.States.WAITING)
		print("[MainServer] Ready for next round")
	end
end)

-- Expose systems globally for testing (temporary, will remove later)
_G.GameState = gameState
_G.GameStateModule = GameState -- Module with States enum
_G.PowerManager = powerManager
_G.PowerManagerModule = PowerManager -- Module with PowerStates enum

print("=== Server Ready ===")
print("Test commands:")
print('  _G.GameState:SetState(_G.GameStateModule.States.RUNNING) -- Start round')
print('  _G.PowerManager:CutPower() -- Trigger blackout')
print('  _G.PowerManager:RestorePower() -- Restore power')
print('  print(_G.PowerManager:GetTimeRemaining()) -- Check time left')
