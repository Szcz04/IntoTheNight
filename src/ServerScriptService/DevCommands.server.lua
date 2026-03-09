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

	PROJECT DIRECTION NOTES:
	- Keep this as fast iteration tooling during stealth-system migration.
	- TODO: add commands for suspicion state, host command trigger, and NPC witness simulation.
]]

local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

-- Wait for systems to initialize
task.wait(1)

local gameState = _G.GameState
local gameStateModule = _G.GameStateModule
local powerManager = _G.PowerManager
local lightingController = _G.LightingController

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

createCommand("/checksuspicion", function(player)
	local suspicionManager = _G.SuspicionManager
	if suspicionManager then
		local suspicion = suspicionManager:GetSuspicion(player)
		print(string.format("[DevCommands] %s suspicion: %d", player.Name, suspicion))
	else
		warn("[DevCommands] SuspicionManager not available")
	end
end, "Check your current suspicion level")

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

createCommand("/hostnext", function(player)
	local hostCommandSystem = _G.HostCommandSystem
	if hostCommandSystem then
		local command = hostCommandSystem:ForceIssueCommand(nil)
		if command then
			print(string.format("[DevCommands] %s forced random host command: %s", player.Name, command.name))
		else
			warn("[DevCommands] Could not issue host command (system stopped or command already active)")
		end
	else
		warn("[DevCommands] HostCommandSystem not available")
	end
end, "Force next random host command")

createCommand("/hostcmd", function(player, unfilteredMessage)
	local hostCommandSystem = _G.HostCommandSystem
	if not hostCommandSystem then
		warn("[DevCommands] HostCommandSystem not available")
		return
	end

	local requested = string.match(unfilteredMessage or "", "^%S+%s+(%S+)$")
	if not requested then
		warn("[DevCommands] Usage: /hostcmd <FREEZE|JUMP|DANCE|SIT|FACE_DIRECTION>")
		return
	end

	requested = string.upper(requested)
	local command = hostCommandSystem:ForceIssueCommand(requested)
	if command then
		print(string.format("[DevCommands] %s forced host command: %s", player.Name, command.name))
	else
		warn("[DevCommands] Failed to force host command (invalid name, system stopped, or command active)")
	end
end, "Force specific host command")

createCommand("/npccount", function(player)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	local active = npcManager:GetActiveNpcCount()
	local desired = npcManager:GetDesiredNpcCount()
	print(string.format("[DevCommands] %s checked NPC count: %d active / %d desired", player.Name, active, desired))
end, "Check active and desired NPC count")

createCommand("/npcsetcount", function(player, unfilteredMessage)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	local requested = tonumber(string.match(unfilteredMessage or "", "(%d+)"))
	if not requested then
		warn("[DevCommands] Usage: /npcsetcount <0-50>")
		return
	end

	local ok = npcManager:SetDesiredNpcCount(requested)
	if ok then
		print(string.format("[DevCommands] %s set desired NPC count to %d", player.Name, npcManager:GetDesiredNpcCount()))
	else
		warn("[DevCommands] Failed to set desired NPC count")
	end
end, "Set desired NPC count (usage: /npcsetcount 12)")

createCommand("/npcrespawn", function(player)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	npcManager:RespawnAll()
	print(string.format("[DevCommands] %s respawned all NPCs", player.Name))
end, "Respawn all active NPCs")

createCommand("/npctiers", function(player)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	local stats = npcManager:GetTierStats()
	local weights = npcManager:GetTierWeights()
	local forcedTier = npcManager:GetForcedTier()
	print(string.format(
		"[DevCommands] %s NPC tiers active: T1=%d T2=%d T3=%d | weights: P=%.2f S=%.2f A=%.2f | forced=%s",
		player.Name,
		stats[1] or 0,
		stats[2] or 0,
		stats[3] or 0,
		weights.primitive,
		weights.standard,
		weights.advanced,
		forcedTier and tostring(forcedTier) or "OFF"
	))
end, "Show NPC tier stats and spawn weights")

createCommand("/npctierweights", function(player, unfilteredMessage)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	local args = {}
	for token in string.gmatch(unfilteredMessage or "", "[^%s]+") do
		table.insert(args, token)
	end

	if #args < 4 then
		warn("[DevCommands] Usage: /npctierweights <primitive> <standard> <advanced>")
		return
	end

	local p = tonumber(args[2])
	local s = tonumber(args[3])
	local a = tonumber(args[4])
	if not p or not s or not a then
		warn("[DevCommands] Invalid weights. Example: /npctierweights 0.5 0.35 0.15")
		return
	end

	if p > 1 or s > 1 or a > 1 then
		p = p / 100
		s = s / 100
		a = a / 100
	end

	local ok = npcManager:SetTierWeights(p, s, a)
	if not ok then
		warn("[DevCommands] Failed to set tier weights")
		return
	end

	local weights = npcManager:GetTierWeights()
	print(string.format(
		"[DevCommands] %s updated tier weights to P=%.2f S=%.2f A=%.2f",
		player.Name,
		weights.primitive,
		weights.standard,
		weights.advanced
	))
end, "Set tier spawn weights (usage: /npctierweights 0.5 0.35 0.15)")

createCommand("/npcforcetier", function(player, unfilteredMessage)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	local requested = string.match(unfilteredMessage or "", "^%S+%s+(%S+)$")
	if not requested then
		warn("[DevCommands] Usage: /npcforcetier <1|2|3|primitive|standard|advanced|off>")
		return
	end

	requested = string.lower(requested)
	if requested == "off" or requested == "none" then
		npcManager:SetForcedTier(nil)
		print(string.format("[DevCommands] %s disabled forced NPC tier", player.Name))
		return
	end

	local tierMap = {
		["1"] = 1,
		["2"] = 2,
		["3"] = 3,
		primitive = 1,
		standard = 2,
		advanced = 3
	}

	local tier = tierMap[requested]
	if not tier then
		warn("[DevCommands] Invalid tier. Use 1,2,3,primitive,standard,advanced,off")
		return
	end

	local ok = npcManager:SetForcedTier(tier)
	if ok then
		print(string.format("[DevCommands] %s forced new NPCs to tier %d", player.Name, tier))
	else
		warn("[DevCommands] Failed to set forced tier")
	end
end, "Force next spawned NPC tiers (usage: /npcforcetier advanced)")

createCommand("/npcdebug", function(player)
	local npcManager = _G.NPCManager
	if not npcManager then
		warn("[DevCommands] NPCManager not available")
		return
	end

	local snapshot = npcManager:GetDebugSnapshot()
	if #snapshot == 0 then
		print(string.format("[DevCommands] %s NPC debug: no active NPCs", player.Name))
		return
	end

	print(string.format("[DevCommands] %s NPC debug snapshot (%d NPCs):", player.Name, #snapshot))
	for i = 1, math.min(#snapshot, 20) do
		local entry = snapshot[i]
		print(string.format("  NPC %02d -> Tier %d", entry.id, entry.tier))
	end
end, "Print active NPC ids and tiers")

createCommand("/npcdebuglogs", function(player, unfilteredMessage)
	local requested = string.match(string.lower(unfilteredMessage or ""), "^%S+%s+(%S+)$")
	local current = Workspace:GetAttribute("NPCDebugLogs") == true

	if requested == "on" then
		current = true
	elseif requested == "off" then
		current = false
	else
		current = not current
	end

	Workspace:SetAttribute("NPCDebugLogs", current)
	print(string.format("[DevCommands] %s set NPCDebugLogs=%s", player.Name, tostring(current)))
end, "Toggle NPC debug logs (usage: /npcdebuglogs [on|off])")

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
print("Type command in chat: /startround /cutpower /restorepower /endround /timecheck /state /sequence /resetlevers /damagesanity /healsanity /checksanity /checkmovement /monitor /runstats /whisper /hostnext /hostcmd /npccount /npcsetcount /npcrespawn /npctiers /npctierweights /npcforcetier /npcdebug /npcdebuglogs /giveitems /clearinventory /spawnflashlight /spawnbattery /spawnkey /spawnmedkit /spawnlockpick")
