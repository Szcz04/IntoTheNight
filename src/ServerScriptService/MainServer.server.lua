--[[
	MainServer: Orchestrates core game systems
	
	Responsibilities:
		- Initialize all core systems
		- Wire up system interactions
		- Manage round flow (WAITING → RUNNING → ENDING)
		- Handle fail conditions
	
	Systems are modular. They communicate via events, not direct calls.

	PROJECT DIRECTION NOTES (Social Stealth House Party):
	- Keep this file as the central wiring point for stealth systems.
	- TODO: integrate HostCommandSystem (jump/dance/freeze commands).
	- TODO: integrate SuspicionManager as a first-class fail/win signal.
	- TODO: convert horror fail loops into social elimination/exposure flow.
	- TODO: phase out temporary _G access once dependencies are wired explicitly.
]]

print("=== IntoTheNight - Server Starting ===")

-- Services
local ServerScriptService = game:GetService("ServerScriptService")

-- Core modules
local GameState = require(ServerScriptService.GameState)
local PowerManager = require(ServerScriptService.PowerManager)
local LightingController = require(ServerScriptService.LightingController)
local AudioController = require(ServerScriptService.AudioController)
local LeverSequence = require(ServerScriptService.LeverSequence)
local SuspicionManager = require(ServerScriptService.SuspicionManager)
local MovementTracker = require(ServerScriptService.MovementTracker)
local WhisperMonster = require(ServerScriptService.WhisperMonster)
local InventoryManager = require(ServerScriptService.InventoryManager)
local HostCommandSystem = require(ServerScriptService.HostCommandSystem)
local NPCManager = require(ServerScriptService.NPCs.NPCManager)
local WitnessSystem = require(ServerScriptService.NPCs.WitnessSystem)
local NPCWitnessSource = require(ServerScriptService.NPCs.WitnessSources.NPCWitnessSource)
local CameraWitnessSource = require(ServerScriptService.NPCs.WitnessSources.CameraWitnessSource)
local NPCWitnessDialogueService = require(ServerScriptService.NPCs.NPCWitnessDialogueService)

-- Initialize systems
print("[MainServer] Initializing core systems...")

local gameState = GameState.new()
local powerManager = PowerManager.new()
local lightingController = LightingController.new(powerManager)
local audioController = AudioController.new(powerManager)
local leverSequence = LeverSequence.new(powerManager, gameState)
local suspicionManager = SuspicionManager.new(gameState)
local movementTracker = MovementTracker.new()
local whisperMonster = WhisperMonster.new(movementTracker, suspicionManager)
local inventoryManager = InventoryManager.new()
local hostCommandSystem = HostCommandSystem.new(gameState, movementTracker, suspicionManager)
local npcManager = NPCManager.new(gameState, hostCommandSystem)
local witnessSystem = WitnessSystem.new({
	suspicionManager = suspicionManager
})
local npcWitnessSource = NPCWitnessSource.new(npcManager)
local cameraWitnessSource = CameraWitnessSource.new()
local npcWitnessDialogueService = NPCWitnessDialogueService.new(witnessSystem, npcManager)

witnessSystem:RegisterSource(npcWitnessSource)
witnessSystem:RegisterSource(cameraWitnessSource)
hostCommandSystem:SetWitnessSystem(witnessSystem)

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
		suspicionManager:ResetAll()
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
_G.LeverSequence = leverSequence
_G.SuspicionManager = suspicionManager
_G.MovementTracker = movementTracker
_G.MovementTrackerModule = MovementTracker -- Module with States enum
_G.WhisperMonster = whisperMonster
_G.InventoryManager = inventoryManager
_G.LightingController = lightingController
_G.HostCommandSystem = hostCommandSystem
_G.NPCManager = npcManager
_G.WitnessSystem = witnessSystem
_G.NPCWitnessDialogueService = npcWitnessDialogueService

