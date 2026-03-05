--[[
	InventoryManager: Server-side inventory system
	
	Manages player inventories with grid-based placement:
		- 6x8 grid (6 columns, 8 rows = 48 slots)
		- Items can be rotated (swap width/height)
		- Validates placement (no overlap, within bounds)
		- Persistent per-player storage
	
	Grid coordinates: (1,1) = top-left, (6,8) = bottom-right
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)
local FlashlightController = require(script.Parent.FlashlightController)

local InventoryManager = {}
InventoryManager.__index = InventoryManager

-- Grid configuration
local GRID_WIDTH = 6
local GRID_HEIGHT = 4

function InventoryManager.new()
	local self = setmetatable({}, InventoryManager)
	
	-- Player inventories: {userId = {items = {}, grid = {}}}
	self._inventories = {}
	
	-- World item charge tracking: {uuid = {charge = 0.5, timestamp = tick()}}
	self._worldItemCharges = {}
	
	-- Flashlight controller (server-side)
	self._flashlightController = FlashlightController.new()
	
	-- RemoteEvents for client communication
	self._remoteEvent = ReplicatedStorage:FindFirstChild("InventoryEvent")
	if not self._remoteEvent then
		self._remoteEvent = Instance.new("RemoteEvent")
		self._remoteEvent.Name = "InventoryEvent"
		self._remoteEvent.Parent = ReplicatedStorage
	end
	
	self._remoteFunction = ReplicatedStorage:FindFirstChild("InventoryFunction")
	if not self._remoteFunction then
		self._remoteFunction = Instance.new("RemoteFunction")
		self._remoteFunction.Name = "InventoryFunction"
		self._remoteFunction.Parent = ReplicatedStorage
	end
	
	-- Handle client requests
	self._remoteFunction.OnServerInvoke = function(player, action, ...)
		return self:_HandleClientRequest(player, action, ...)
	end
	
	-- Initialize inventories for existing players
	for _, player in Players:GetPlayers() do
		self:_InitializeInventory(player)
	end
	
	-- Initialize for new players
	Players.PlayerAdded:Connect(function(player)
		self:_InitializeInventory(player)
	end)
	
	-- Clean up on player leave
	Players.PlayerRemoving:Connect(function(player)
		self._inventories[player.UserId] = nil
	end)
	
	-- Cleanup old world item charges (every 5 minutes, remove charges older than 10 minutes)
	task.spawn(function()
		while true do
			task.wait(300) -- 5 minutes
			local currentTime = tick()
			local removed = 0
			
			for uuid, data in pairs(self._worldItemCharges) do
				if currentTime - data.timestamp > 600 then -- 10 minutes
					self._worldItemCharges[uuid] = nil
					removed = removed + 1
				end
			end
			
			if removed > 0 then
				print(string.format("[InventoryManager] Cleaned up %d old charge entries", removed))
			end
		end
	end)
	
	-- Charge drain system for flashlights
	RunService.Heartbeat:Connect(function(deltaTime)
		self._flashlightController:ProcessChargeDrain(deltaTime)
		
		-- Sync equippedCharge with actual flashlight charge after drain
		for userId, inventory in pairs(self._inventories) do
			if inventory.equipped == "Flashlight" then
				local player = Players:GetPlayerByUserId(userId)
				if player then
					local flashlightData = self._flashlightController:GetFlashlightData(player)
					if flashlightData then
						inventory.equippedCharge = flashlightData.charge
					end
				end
			end
		end
	end)
	
	-- Initialize UUID for existing world items (for manual testing)
	self:_InitializeExistingItems()
	
	print("[InventoryManager] Inventory system initialized (Grid: 6x8)")
	
	return self
end

-- Initialize UUID for existing items in world (for testing with manually placed items)
function InventoryManager:_InitializeExistingItems()
	local initialized = 0
	local total = 0
	
	for _, item in CollectionService:GetTagged("ItemPickup") do
		total = total + 1
		-- Only initialize if item doesn't already have UUID
		if not item:GetAttribute("ItemUUID") then
			local uuid = HttpService:GenerateGUID(false)
			item:SetAttribute("ItemUUID", uuid)
			initialized = initialized + 1
			print(string.format("[InventoryManager] ✓ Added UUID %s to %s (ItemId: %s)", uuid, item:GetFullName(), tostring(item:GetAttribute("ItemId"))))
			
			-- Also make sure ItemId exists
			if not item:GetAttribute("ItemId") then
				warn(string.format("[InventoryManager] Item %s has ItemPickup tag but no ItemId!", item:GetFullName()))
			end
		else
			print(string.format("[InventoryManager] Item %s already has UUID: %s", item:GetFullName(), item:GetAttribute("ItemUUID")))
		end
	end
	
	print(string.format("[InventoryManager] Found %d items with ItemPickup tag, initialized %d UUIDs", total, initialized))
end

-- Initialize empty inventory for player
function InventoryManager:_InitializeInventory(player)
	local userId = player.UserId
	
	self._inventories[userId] = {
		items = {},      -- {itemId, x, y, width, height, isRotated, charge}
		grid = {},       -- 2D array marking occupied slots
		equipped = nil,  -- itemId of equipped item (or nil)
		equippedCharge = nil -- charge level of equipped item if it has charge
	}
	
	-- Initialize empty grid
	for y = 1, GRID_HEIGHT do
		self._inventories[userId].grid[y] = {}
		for x = 1, GRID_WIDTH do
			self._inventories[userId].grid[y][x] = nil -- nil = empty slot
		end
	end
	
	print(string.format("[InventoryManager] Initialized inventory for %s", player.Name))
end

-- Handle client requests
function InventoryManager:_HandleClientRequest(player, action, ...)
	if action == "GetInventory" then
		return self:GetInventory(player)
	elseif action == "AddItem" then
		local itemId, x, y, isRotated, chargeUUID = ...
		return self:AddItem(player, itemId, x, y, isRotated, chargeUUID)
	elseif action == "RemoveItem" then
		local itemIndex = ...
		return self:RemoveItem(player, itemIndex)
	elseif action == "MoveItem" then
		local itemIndex, newX, newY, newRotated = ...
		return self:MoveItem(player, itemIndex, newX, newY, newRotated)
	elseif action == "CanPlaceItem" then
		local itemId, x, y, isRotated, ignoreIndex = ...
		return self:CanPlaceItem(player, itemId, x, y, isRotated, ignoreIndex)
	elseif action == "DropItem" then
		local itemIndex = ...
		return self:DropItem(player, itemIndex)
	elseif action == "EquipItem" then
		local itemIndex = ...
		return self:EquipItem(player, itemIndex)
	elseif action == "UnequipItem" then
		local x, y = ...
		return self:UnequipItem(player, x, y)
	elseif action == "GetEquipped" then
		return self:GetEquipped(player)
	elseif action == "PickupItem" then
		local worldItemPath = ...
		return self:PickupItem(player, worldItemPath)
	elseif action == "ChargeFlashlight" then
		local flashlightTarget, batteryIndex = ...
		return self:ChargeFlashlight(player, flashlightTarget, batteryIndex)
	elseif action == "UpdateFlashlightCharge" then
		local newCharge = ...
		return self:UpdateFlashlightCharge(player, newCharge)
	end
	
	warn(string.format("[InventoryManager] Unknown action: %s", tostring(action)))
	return nil
end

-- Get player's full inventory
function InventoryManager:GetInventory(player)
	local inventory = self._inventories[player.UserId]
	if not inventory then
		warn(string.format("[InventoryManager] No inventory for %s", player.Name))
		return nil
	end
	
	return inventory.items
end

-- Check if item can be placed at position
function InventoryManager:CanPlaceItem(player, itemId, x, y, isRotated, ignoreIndex)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return false end
	
	-- Get dimensions (swap if rotated)
	local width = isRotated and itemDef.Height or itemDef.Width
	local height = isRotated and itemDef.Width or itemDef.Height
	
	-- Check bounds
	if x < 1 or y < 1 or x + width - 1 > GRID_WIDTH or y + height - 1 > GRID_HEIGHT then
		return false
	end
	
	-- Check for overlaps
	for checkY = y, y + height - 1 do
		for checkX = x, x + width - 1 do
			local occupant = inventory.grid[checkY][checkX]
			if occupant ~= nil then
				-- If ignoring specific item (for moving), check if occupant is that item
				if not ignoreIndex or occupant ~= ignoreIndex then
					return false
				end
			end
		end
	end
	
	return true
end

-- Helper: Mark grid space as occupied by item
function InventoryManager:_MarkGridSpace(inventory, item)
	for checkY = item.y, item.y + item.height - 1 do
		for checkX = item.x, item.x + item.width - 1 do
			-- Find item index
			local itemIndex = nil
			for i, invItem in ipairs(inventory.items) do
				if invItem == item then
					itemIndex = i
					break
				end
			end
			inventory.grid[checkY][checkX] = itemIndex
		end
	end
end

-- Helper: Clear grid space occupied by item
function InventoryManager:_ClearGridSpace(inventory, item)
	for checkY = item.y, item.y + item.height - 1 do
		for checkX = item.x, item.x + item.width - 1 do
			inventory.grid[checkY][checkX] = nil
		end
	end
end

-- Add item to inventory at specific position
function InventoryManager:AddItem(player, itemId, x, y, isRotated, chargeUUID)
	if not ItemDefinitions.IsValidItem(itemId) then
		warn(string.format("[InventoryManager] Invalid item: %s", tostring(itemId)))
		return false
	end
	
	if not self:CanPlaceItem(player, itemId, x, y, isRotated) then
		print(string.format("[InventoryManager] Cannot place %s at (%d,%d) for %s", itemId, x, y, player.Name))
		return false
	end
	
	local inventory = self._inventories[player.UserId]
	local itemDef = ItemDefinitions.GetItem(itemId)
	
	-- Get dimensions
	local width = isRotated and itemDef.Height or itemDef.Width
	local height = isRotated and itemDef.Width or itemDef.Height
	
	-- Add item to inventory
	local item = {
		itemId = itemId,
		x = x,
		y = y,
		width = width,
		height = height,
		isRotated = isRotated or false
	}
	
	-- Add charge if item supports it
	local defaultCharge = ItemDefinitions.GetDefaultCharge(itemId)
	if defaultCharge then
		-- Check if this item has stored charge from world (via UUID)
		local storedCharge = nil
		if chargeUUID and self._worldItemCharges[chargeUUID] then
			storedCharge = self._worldItemCharges[chargeUUID].charge
			self._worldItemCharges[chargeUUID] = nil -- Cleanup
			print(string.format("[InventoryManager] Restored charge %.0f%% from UUID %s", storedCharge * 100, chargeUUID))
		end
		
		item.charge = storedCharge or defaultCharge
	end
	
	table.insert(inventory.items, item)
	local itemIndex = #inventory.items
	
	-- Mark grid slots as occupied
	for checkY = y, y + height - 1 do
		for checkX = x, x + width - 1 do
			inventory.grid[checkY][checkX] = itemIndex
		end
	end
	
	print(string.format("[InventoryManager] Added %s to %s at (%d,%d)", itemId, player.Name, x, y))
	
	-- Notify client with full inventory update
	self._remoteEvent:FireClient(player, "InventoryUpdated", inventory.items, inventory.equipped)
	
	return true
end

-- Remove item from inventory
function InventoryManager:RemoveItem(player, itemIndex)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	local item = inventory.items[itemIndex]
	if not item then
		warn(string.format("[InventoryManager] Item index %d not found", itemIndex))
		return false
	end
	
	-- Clear grid slots
	for checkY = item.y, item.y + item.height - 1 do
		for checkX = item.x, item.x + item.width - 1 do
			inventory.grid[checkY][checkX] = nil
		end
	end
	
	-- Remove item
	table.remove(inventory.items, itemIndex)
	
	-- Update grid references (indices shifted after removal)
	for y = 1, GRID_HEIGHT do
		for x = 1, GRID_WIDTH do
			local occupant = inventory.grid[y][x]
			if occupant and occupant > itemIndex then
				inventory.grid[y][x] = occupant - 1
			end
		end
	end
	
	print(string.format("[InventoryManager] Removed item %d from %s", itemIndex, player.Name))
	
	-- Notify client with full inventory update
	self._remoteEvent:FireClient(player, "InventoryUpdated", inventory.items, inventory.equipped)
	
	return true
end

-- Move item to new position (with optional rotation)
function InventoryManager:MoveItem(player, itemIndex, newX, newY, newRotated)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	local item = inventory.items[itemIndex]
	if not item then return false end
	
	-- Check if new position is valid (ignore current item's position)
	if not self:CanPlaceItem(player, item.itemId, newX, newY, newRotated, itemIndex) then
		return false
	end
	
	-- Clear old position
	for checkY = item.y, item.y + item.height - 1 do
		for checkX = item.x, item.x + item.width - 1 do
			inventory.grid[checkY][checkX] = nil
		end
	end
	
	-- Update item
	local itemDef = ItemDefinitions.GetItem(item.itemId)
	local width = newRotated and itemDef.Height or itemDef.Width
	local height = newRotated and itemDef.Width or itemDef.Height
	
	item.x = newX
	item.y = newY
	item.width = width
	item.height = height
	item.isRotated = newRotated
	
	-- Mark new position
	for checkY = newY, newY + height - 1 do
		for checkX = newX, newX + width - 1 do
			inventory.grid[checkY][checkX] = itemIndex
		end
	end
	
	print(string.format("[InventoryManager] Moved item %d to (%d,%d) rotated=%s", itemIndex, newX, newY, tostring(newRotated)))
	
	-- Notify client with full inventory update
	self._remoteEvent:FireClient(player, "InventoryUpdated", inventory.items, inventory.equipped)
	
	return true
end

-- Get grid dimensions
function InventoryManager.GetGridSize()
	return GRID_WIDTH, GRID_HEIGHT
end

-- Clear all items (for testing)
function InventoryManager:ClearInventory(player)
	self:_InitializeInventory(player)
	self._remoteEvent:FireClient(player, "InventoryCleared")
	print(string.format("[InventoryManager] Cleared inventory for %s", player.Name))
end

-- Drop item into world
function InventoryManager:DropItem(player, itemIndex)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	local item = inventory.items[itemIndex]
	if not item then
		warn(string.format("[InventoryManager] Item index %d not found", itemIndex))
		return false
	end
	
	-- Get player position
	local character = player.Character
	if not character then return false end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return false end
	
	-- Spawn item in world (5 studs in front of player)
	local dropPosition = humanoidRootPart.CFrame * CFrame.new(0, 0, -5)
	self:_SpawnWorldItem(item.itemId, dropPosition, item.charge)
	
	-- Remove from inventory
	self:RemoveItem(player, itemIndex)
	
	print(string.format("[InventoryManager] %s dropped %s", player.Name, item.itemId))
	return true
end

-- Spawn item pickup in world
function InventoryManager:_SpawnWorldItem(itemId, cframe, charge)
	local ItemDefinitions = require(game:GetService("ReplicatedStorage").SharedModules.ItemDefinitions)
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return end
	
	local worldItem
	
	-- Try to use prefab model if available
	if itemDef.WorldModel then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local ItemModels = ReplicatedStorage:FindFirstChild("ItemModels")
		
		print(string.format("[InventoryManager] Looking for model: %s", itemDef.WorldModel))
		
		if not ItemModels then
			warn("[InventoryManager] ItemModels folder not found in ReplicatedStorage!")
		else
			print(string.format("[InventoryManager] ItemModels found. Children: %s", table.concat((function()
				local names = {}
				for _, child in ItemModels:GetChildren() do
					table.insert(names, child.Name .. " (" .. child.ClassName .. ")")
				end
				return names
			end)(), ", ")))
			
			local prefab = ItemModels:FindFirstChild(itemDef.WorldModel)
			if not prefab then
				warn(string.format("[InventoryManager] Prefab '%s' not found in ItemModels!", itemDef.WorldModel))
			else
				print(string.format("[InventoryManager] Found prefab: %s (%s)", prefab.Name, prefab.ClassName))
				
				-- Clone the prefab
				worldItem = prefab:Clone()
				worldItem:SetPrimaryPartCFrame(cframe)
				
				-- Make sure it has PrimaryPart set
				if not worldItem.PrimaryPart then
					warn(string.format("[InventoryManager] Model %s has no PrimaryPart!", itemDef.WorldModel))
					-- Use first Part as fallback
					for _, child in worldItem:GetChildren() do
						if child:IsA("BasePart") then
							worldItem.PrimaryPart = child
							break
						end
					end
				end
				
				print(string.format("[InventoryManager] ✓ Using prefab model for %s", itemId))
			end
		end
	end
	
	-- Fallback: create simple part if no prefab
	if not worldItem then
		worldItem = Instance.new("Part")
		worldItem.Name = itemDef.Name
		worldItem.Size = Vector3.new(1, 1, 1)
		worldItem.Color = itemDef.Color
		worldItem.CFrame = cframe
		print(string.format("[InventoryManager] Using fallback part for %s", itemId))
	end
	
	-- Setup for pickup
	-- Add unique UUID for identification (critical when multiple items have same name)
	local itemUUID = HttpService:GenerateGUID(false)
	
	if worldItem:IsA("Model") then
		-- Model: add tag and attributes to Model itself
		CollectionService:AddTag(worldItem, "ItemPickup")
		worldItem:SetAttribute("ItemId", itemId)
		worldItem:SetAttribute("ItemUUID", itemUUID)
		print(string.format("[InventoryManager] ✓ Assigned UUID %s to spawned %s (Model)", itemUUID, itemId))
		
		-- Enable physics on all parts
		for _, part in worldItem:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = true
			end
		end
	else
		-- Part: enable physics
		worldItem.Anchored = false
		worldItem.CanCollide = true
		CollectionService:AddTag(worldItem, "ItemPickup")
		worldItem:SetAttribute("ItemId", itemId)
		worldItem:SetAttribute("ItemUUID", itemUUID)
		print(string.format("[InventoryManager] ✓ Assigned UUID %s to spawned %s (Part)", itemUUID, itemId))
	end
	
	-- Store charge for items with charge (like flashlight)
	if charge then
		local uuid = HttpService:GenerateGUID(false)
		worldItem:SetAttribute("ChargeUUID", uuid)
		self._worldItemCharges[uuid] = {
			charge = charge,
			timestamp = tick()
		}
		print(string.format("[InventoryManager] Stored charge %.0f%% with UUID %s", charge * 100, uuid))
	end
	
	worldItem.Parent = workspace
	
	print(string.format("[InventoryManager] Spawned %s in world (physics enabled)", itemId))
end

-- Equip item from inventory
function InventoryManager:EquipItem(player, itemIndex)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	local item = inventory.items[itemIndex]
	if not item then
		warn(string.format("[InventoryManager] Item %d does not exist", itemIndex))
		return false
	end
	
	-- Check if item is equippable
	local itemDef = ItemDefinitions.GetItem(item.itemId)
	if not itemDef or not itemDef.IsEquippable then
		warn(string.format("[InventoryManager] Item %s is not equippable", item.itemId))
		return false
	end
	
	-- Unequip current item if any
	if inventory.equipped then
		warn("[InventoryManager] Already have equipped item - unequip first")
		return false
	end
	
	-- Remove from grid and inventory
	self:_ClearGridSpace(inventory, item)
	table.remove(inventory.items, itemIndex)
	
	-- Set as equipped and save charge if applicable
	inventory.equipped = item.itemId
	if item.charge then
		inventory.equippedCharge = item.charge
	end
	
	print(string.format("[InventoryManager] %s equipped %s", player.Name, item.itemId))
	
	-- If flashlight, attach to character (server-side, visible to all!)
	if item.itemId == "Flashlight" then
		self._flashlightController:AttachFlashlight(player, item.charge or 0.5)
	end
	
	-- Notify client with charge info
	self._remoteEvent:FireClient(player, "InventoryUpdated", self:GetInventory(player), item.itemId)
	
	return true
end

-- Unequip item to inventory
function InventoryManager:UnequipItem(player, x, y)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	if not inventory.equipped then
		warn("[InventoryManager] No equipped item")
		return false
	end
	
	local itemId = inventory.equipped
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return false end
	
	-- Check if we can place at position
	if not self:CanPlaceItem(player, itemId, x, y, false) then
		warn(string.format("[InventoryManager] Cannot place %s at (%d,%d)", itemId, x, y))
		return false
	end
	
	-- Add to inventory
	local item = {
		itemId = itemId,
		x = x,
		y = y,
		width = itemDef.Width,
		height = itemDef.Height,
		isRotated = false
	}
	
	-- Restore charge if item had it
	if inventory.equippedCharge then
		item.charge = inventory.equippedCharge
	end
	
	table.insert(inventory.items, item)
	self:_MarkGridSpace(inventory, item)
	
	-- If flashlight, remove from character
	if itemId == "Flashlight" then
		self._flashlightController:RemoveFlashlight(player)
	end
	
	-- Clear equipped slot
	inventory.equipped = nil
	inventory.equippedCharge = nil
	
	print(string.format("[InventoryManager] %s unequipped %s to (%d,%d)", player.Name, itemId, x, y))
	
	-- Notify client
	self._remoteEvent:FireClient(player, "InventoryUpdated", self:GetInventory(player), nil)
	
	return true
end

-- Get equipped item
function InventoryManager:GetEquipped(player)
	local inventory = self._inventories[player.UserId]
	if not inventory then return nil end
	
	return inventory.equipped
end

-- Spawn item in world at player position (for dev commands)
function InventoryManager:SpawnItemAtPlayer(player, itemId)
	local character = player.Character
	if not character then 
		warn("[InventoryManager] Player has no character")
		return false 
	end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then 
		warn("[InventoryManager] Character has no HumanoidRootPart")
		return false 
	end
	
	-- Spawn 5 studs in front of player, 2 studs up
	local spawnCFrame = hrp.CFrame * CFrame.new(0, 2, -5)
	self:_SpawnWorldItem(itemId, spawnCFrame, nil)
	
	print(string.format("[InventoryManager] Spawned %s for %s", itemId, player.Name))
	return true
end

-- Charge flashlight with battery
function InventoryManager:ChargeFlashlight(player, flashlightTarget, batteryIndex)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	-- Get battery item
	local battery = inventory.items[batteryIndex]
	if not battery or battery.itemId ~= "Battery" then
		warn("[InventoryManager] Invalid battery item")
		return false
	end
	
	-- Get flashlight item (either from inventory or equipped)
	local flashlight = nil
	local isEquipped = false
	local currentCharge = 0
	
	if flashlightTarget == "equipped" then
		-- Charging equipped flashlight
		if inventory.equipped ~= "Flashlight" then
			warn("[InventoryManager] No flashlight equipped")
			return false
		end
		isEquipped = true
		
		-- Get ACTUAL charge from FlashlightController (not stale inventory value)
		local flashlightData = self._flashlightController:GetFlashlightData(player)
		if flashlightData then
			currentCharge = flashlightData.charge
			-- Sync inventory with actual value
			inventory.equippedCharge = currentCharge
		else
			-- Fallback to inventory value
			currentCharge = inventory.equippedCharge or 0.5
		end
		flashlight = { charge = currentCharge }
	else
		-- Charging flashlight in inventory
		flashlight = inventory.items[flashlightTarget]
		if not flashlight or flashlight.itemId ~= "Flashlight" then
			warn("[InventoryManager] Invalid flashlight item")
			return false
		end
		currentCharge = flashlight.charge or 0.5
	end
	
	-- Check if flashlight is already fully charged
	local itemDef = ItemDefinitions.GetItem("Flashlight")
	if currentCharge == nil then
		currentCharge = itemDef.DefaultCharge
	end
	
	if currentCharge >= itemDef.MaxCharge then
		print("[InventoryManager] Flashlight already fully charged")
		return false
	end
	
	-- Add charge (25% per battery)
	local newCharge = math.min(currentCharge + 0.25, itemDef.MaxCharge)
	
	if isEquipped then
		inventory.equippedCharge = newCharge
		-- Update the actual flashlight model through FlashlightController
		self._flashlightController:UpdateCharge(player, newCharge)
	else
		flashlight.charge = newCharge
	end
	
	-- Remove battery
	self:RemoveItem(player, batteryIndex)
	
	print(string.format("[InventoryManager] Charged flashlight to %.0f%%", newCharge * 100))
	
	-- Notify client with updated charge
	self._remoteEvent:FireClient(player, "FlashlightCharged", newCharge)
	self._remoteEvent:FireClient(player, "InventoryUpdated", inventory.items, inventory.equipped)
	
	return true
end

-- Update flashlight charge (for drain during use)
function InventoryManager:UpdateFlashlightCharge(player, newCharge)
	local inventory = self._inventories[player.UserId]
	if not inventory then return false end
	
	-- Only update if flashlight is equipped
	if inventory.equipped == "Flashlight" then
		inventory.equippedCharge = newCharge
		-- Update through FlashlightController (server-side)
		self._flashlightController:UpdateCharge(player, newCharge)
		print(string.format("[InventoryManager] Updated equipped flashlight charge to %.0f%%", newCharge * 100))
		return true
	end
	
	return false
end

-- Atomically pickup item from world (removes from world FIRST, then adds to inventory)
function InventoryManager:PickupItem(player, itemUUID)
	print(string.format("[InventoryManager] PickupItem called by %s with UUID: %s", player.Name, tostring(itemUUID)))
	
	-- Find world item by UUID (not by name, to handle duplicate names)
	local worldItem = nil
	
	if itemUUID then
		local allItems = CollectionService:GetTagged("ItemPickup")
		print(string.format("[InventoryManager] Searching through %d items with ItemPickup tag", #allItems))
		
		-- Search all items with ItemPickup tag for matching UUID
		for _, item in allItems do
			local itemStoredUUID = item:GetAttribute("ItemUUID")
			print(string.format("[InventoryManager] Checking item %s - UUID: %s (match: %s)", item:GetFullName(), tostring(itemStoredUUID), tostring(itemStoredUUID == itemUUID)))
			
			if itemStoredUUID == itemUUID then
				worldItem = item
				print(string.format("[InventoryManager] ✓ Found matching item: %s", item:GetFullName()))
				break
			end
		end
	else
		warn("[InventoryManager] No UUID provided to PickupItem!")
	end
	
	if not worldItem or not worldItem.Parent then
		warn(string.format("[InventoryManager] World item not found or already picked up (UUID: %s)", tostring(itemUUID)))
		return false
	end
	
	-- Get item data
	local itemId = worldItem:GetAttribute("ItemId")
	if not itemId then
		warn("[InventoryManager] World item has no ItemId")
		return false
	end
	
	-- Get charge UUID if exists
	local chargeUUID = worldItem:GetAttribute("ChargeUUID")
	
	-- CRITICAL: Remove from world FIRST to prevent double pickup
	worldItem.Parent = nil
	
	-- Find available slot
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then
		-- Failed - restore item
		worldItem.Parent = workspace
		return false
	end
	
	-- Try to find slot
	local slotX, slotY = nil, nil
	
	-- Try normal orientation
	for y = 1, GRID_HEIGHT - itemDef.Height + 1 do
		for x = 1, GRID_WIDTH - itemDef.Width + 1 do
			if self:CanPlaceItem(player, itemId, x, y, false) then
				slotX, slotY = x, y
				break
			end
		end
		if slotX then break end
	end
	
	-- Try rotated if normal didn't work
	if not slotX and itemDef.Width ~= itemDef.Height then
		for y = 1, GRID_HEIGHT - itemDef.Width + 1 do
			for x = 1, GRID_WIDTH - itemDef.Height + 1 do
				if self:CanPlaceItem(player, itemId, x, y, true) then
					slotX, slotY = x, y
					break
				end
			end
			if slotX then break end
		end
	end
	
	if not slotX then
		-- No space - restore item to world
		worldItem.Parent = workspace
		warn("[InventoryManager] No space in inventory for " .. itemId)
		return false
	end
	
	-- Add to inventory
	local success = self:AddItem(player, itemId, slotX, slotY, false, chargeUUID)
	
	if success then
		-- Destroy world item permanently
		worldItem:Destroy()
		print(string.format("[InventoryManager] %s picked up %s", player.Name, itemId))
		return true
	else
		-- Failed to add - restore to world
		worldItem.Parent = workspace
		return false
	end
end

return InventoryManager
