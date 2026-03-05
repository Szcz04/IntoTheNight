--[[
	DevCommands: Simple chat commands for testing during development
	
	Usage in-game chat:
		/startround - Start a game round
		/cutpower - Trigger blackout
		/restorepower - Restore power
		/endround - End current round
		/timecheck - Check remaining time
		/state - Check game state
	
	This is temporary for testing. Will be removed in production.
	Uses NEW TextChatService API (2024+)
]]

local TextChatService = game:GetService("TextChatService")

-- Wait for systems to initialize
task.wait(1)

local gameState = _G.GameState
local gameStateModule = _G.GameStateModule
local powerManager = _G.PowerManager

if not gameState or not powerManager then
	warn("[DevCommands] Systems not ready. Make sure MainServer has initialized.")
	return
end

print("[DevCommands] Creating dev commands...")

-- Helper function to create commands
local function createCommand(primaryAlias, callback, description)
	local command = Instance.new("TextChatCommand")
	command.PrimaryAlias = primaryAlias
	command.Parent = TextChatService
	
	-- Execute callback when command is triggered
	command.Triggered:Connect(function(textSource, unfilteredMessage)
		local player = textSource and game:GetService("Players"):GetPlayerByUserId(textSource.UserId)
		if player then
			print(string.format("[DevCommands] %s used: %s", player.Name, primaryAlias))
			callback(player, unfilteredMessage)
		end
	end)
	
	print(string.format("[DevCommands] Command registered: %s - %s", primaryAlias, description))
	return command
end

-- Create dev commands
createCommand("/startround", function(player)
	gameState:SetState(gameStateModule.States.RUNNING)
	print("[DevCommands] Round started by " .. player.Name)
end, "Start game round")

createCommand("/cutpower", function(player)
	powerManager:CutPower()
	print("[DevCommands] Power cut by " .. player.Name)
end, "Trigger blackout")

createCommand("/restorepower", function(player)
	powerManager:RestorePower()
	print("[DevCommands] Power restored by " .. player.Name)
end, "Restore power")

createCommand("/endround", function(player)
	gameState:SetState(gameStateModule.States.ENDING)
	print("[DevCommands] Round ended by " .. player.Name)
	task.wait(3)
	gameState:SetState(gameStateModule.States.WAITING)
end, "End current round")

createCommand("/timecheck", function(player)
	local timeLeft = powerManager:GetTimeRemaining()
	print(string.format("[DevCommands] %s checked time: %.1f seconds remaining", player.Name, timeLeft))
end, "Check remaining time")

createCommand("/state", function(player)
	local currentState = gameState:GetState()
	print(string.format("[DevCommands] %s checked state: %s", player.Name, currentState))
end, "Check game state")

createCommand("/sequence", function(player)
	local leverSequence = _G.LeverSequence
	if leverSequence then
		local sequence = leverSequence:GetCorrectSequence()
		print(string.format("[DevCommands] %s checked sequence: %s", player.Name, table.concat(sequence, " → ")))
	else
		warn("[DevCommands] LeverSequence not available")
	end
end, "Show correct lever sequence")

createCommand("/resetlevers", function(player)
	local leverSequence = _G.LeverSequence
	if leverSequence then
		leverSequence:ResetAllProgress()
		print(string.format("[DevCommands] %s reset all lever progress", player.Name))
	else
		warn("[DevCommands] LeverSequence not available")
	end
end, "Reset all lever progress")

createCommand("/damagesanity", function(player, unfilteredMessage)
	local sanityManager = _G.SanityManager
	if sanityManager then
		local amount = tonumber(string.match(unfilteredMessage, "%d+")) or 10
		sanityManager:DamageSanity(player, amount)
		print(string.format("[DevCommands] %s damaged sanity by %d", player.Name, amount))
	else
		warn("[DevCommands] SanityManager not available")
	end
end, "Damage sanity (usage: /damagesanity [amount])")

createCommand("/healsanity", function(player, unfilteredMessage)
	local sanityManager = _G.SanityManager
	if sanityManager then
		local amount = tonumber(string.match(unfilteredMessage, "%d+")) or 10
		sanityManager:HealSanity(player, amount)
		print(string.format("[DevCommands] %s healed sanity by %d", player.Name, amount))
	else
		warn("[DevCommands] SanityManager not available")
	end
end, "Heal sanity (usage: /healsanity [amount])")

createCommand("/checksanity", function(player)
	local sanityManager = _G.SanityManager
	if sanityManager then
		local sanity = sanityManager:GetSanity(player)
		local level = sanityManager:GetLevel(player)
		print(string.format("[DevCommands] %s sanity: %d (Level %d)", player.Name, sanity, level))
	else
		warn("[DevCommands] SanityManager not available")
	end
end, "Check your sanity level")

createCommand("/checkmovement", function(player)
	local movementTracker = _G.MovementTracker
	if movementTracker then
		local state = movementTracker:GetState(player)
		local speed = movementTracker:GetSpeed(player)
		local distance = movementTracker:GetDistanceMoved(player)
		print(string.format("[DevCommands] %s movement: %s (%.1f studs/s, %.1f studs total)", 
			player.Name, state, speed, distance))
	else
		warn("[DevCommands] MovementTracker not available")
	end
end, "Check your movement state")

createCommand("/monitor", function(player, unfilteredMessage)
	local movementTracker = _G.MovementTracker
	if movementTracker then
		local duration = tonumber(string.match(unfilteredMessage, "%d+")) or 10
		movementTracker:StartMonitoring(player, duration)
		print(string.format("[DevCommands] Started monitoring %s for %d seconds", player.Name, duration))
	else
		warn("[DevCommands] MovementTracker not available")
	end
end, "Monitor movement for X seconds (usage: /monitor [seconds])")

createCommand("/runstats", function(player)
	local movementTracker = _G.MovementTracker
	if movementTracker then
		local runDistance = movementTracker:GetRunDistance(player)
		local isMonitoring = movementTracker:IsMonitoring(player)
		print(string.format("[DevCommands] %s run distance: %.1f studs (monitoring: %s)", 
			player.Name, runDistance, tostring(isMonitoring)))
	else
		warn("[DevCommands] MovementTracker not available")
	end
end, "Check distance ran during monitoring")

createCommand("/whisper", function(player)
	local whisperMonster = _G.WhisperMonster
	if whisperMonster then
		if whisperMonster:IsActive() then
			warn(string.format("[DevCommands] Whisper event already active, ignoring %s's trigger", player.Name))
		else
			print(string.format("[DevCommands] %s triggered whisper event", player.Name))
			-- Run in separate thread to avoid blocking command
			task.spawn(function()
				whisperMonster:TriggerWhisper()
			end)
		end
	else
		warn("[DevCommands] WhisperMonster not available")
	end
end, "Trigger whisper monster event")

createCommand("/giveitems", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		-- Give a variety of items for testing
		inventoryManager:AddItem(player, "Lockpick", 1, 1, false)
		inventoryManager:AddItem(player, "Battery", 2, 1, false)
		inventoryManager:AddItem(player, "Key", 3, 1, false)
		inventoryManager:AddItem(player, "Flashlight", 1, 2, false)
		inventoryManager:AddItem(player, "Medkit", 4, 2, false)
		print(string.format("[DevCommands] Gave test items to %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Add test items to inventory")

createCommand("/clearinventory", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		inventoryManager:ClearInventory(player)
		print(string.format("[DevCommands] Cleared inventory for %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Clear all items from inventory")

createCommand("/spawnflashlight", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		inventoryManager:SpawnItemAtPlayer(player, "Flashlight")
		print(string.format("[DevCommands] Spawned Flashlight for %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Spawn a flashlight in front of you")

createCommand("/spawnbattery", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		inventoryManager:SpawnItemAtPlayer(player, "Battery")
		print(string.format("[DevCommands] Spawned Battery for %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Spawn a battery in front of you")

createCommand("/spawnkey", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		inventoryManager:SpawnItemAtPlayer(player, "Key")
		print(string.format("[DevCommands] Spawned Key for %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Spawn a key in front of you")

createCommand("/spawnmedkit", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		inventoryManager:SpawnItemAtPlayer(player, "Medkit")
		print(string.format("[DevCommands] Spawned Medkit for %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Spawn a medkit in front of you")

createCommand("/spawnlockpick", function(player)
	local inventoryManager = _G.InventoryManager
	if inventoryManager then
		inventoryManager:SpawnItemAtPlayer(player, "Lockpick")
		print(string.format("[DevCommands] Spawned Lockpick for %s", player.Name))
	else
		warn("[DevCommands] InventoryManager not available")
	end
end, "Spawn a lockpick in front of you")

print("[DevCommands] All dev commands active!")
print("Type command in chat: /startround /cutpower /restorepower /endround /timecheck /state /sequence /resetlevers /damagesanity /healsanity /checksanity /checkmovement /monitor /runstats /whisper /giveitems /clearinventory /spawnflashlight /spawnbattery /spawnkey /spawnmedkit /spawnlockpick")
