--[[
	ItemPickup: Client-side item pickup system
	
	Features:
		- Raycast from camera to detect nearby items
		- White outline highlight when looking at item
		- E key to attempt pickup
		- Finds first available slot in inventory
		- Visual feedback for pickup success/failure
	
	Items must have:
		- "ItemPickup" tag (CollectionService)
		- "ItemId" StringValue attribute
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)

local ItemPickup = {}
ItemPickup.__index = ItemPickup

-- Configuration
local RAYCAST_DISTANCE = 10 -- Studs
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 255, 255) -- White outline

function ItemPickup.new(inventoryUI)
	local self = setmetatable({}, ItemPickup)
	
	self._player = Players.LocalPlayer
	self._inventoryUI = inventoryUI
	self._remoteFunction = ReplicatedStorage:WaitForChild("InventoryFunction")
	
	-- Current highlighted item
	self._highlightedItem = nil
	self._highlight = nil
	
	-- Setup input
	self:_SetupInput()
	
	-- Setup raycast loop
	self:_SetupRaycast()
	
	print("[ItemPickup] Item pickup system initialized")
	
	return self
end

-- Setup input listeners
function ItemPickup:_SetupInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.E then
			self:_TryPickup()
		end
	end)
end

-- Setup raycast loop
function ItemPickup:_SetupRaycast()
	RunService.RenderStepped:Connect(function()
		self:_UpdateRaycast()
	end)
end

-- Update raycast and highlight
function ItemPickup:_UpdateRaycast()
	local character = self._player.Character
	if not character then return end
	
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	-- Raycast from camera center
	local rayOrigin = camera.CFrame.Position
	local rayDirection = camera.CFrame.LookVector * RAYCAST_DISTANCE
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {character}
	
	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult then
		local hitPart = raycastResult.Instance
		
		-- Check if hit part is a pickup item
		if self:_IsPickupItem(hitPart) then
			self:_HighlightItem(hitPart)
			return
		end
	end
	
	-- No item found: clear highlight
	self:_ClearHighlight()
end

-- Check if part is a pickup item
function ItemPickup:_IsPickupItem(part)
	-- Check if part has "ItemPickup" tag
	if not CollectionService:HasTag(part, "ItemPickup") then
		return false
	end
	
	-- Check if part has valid ItemId attribute
	local itemId = part:GetAttribute("ItemId")
	if not itemId or not ItemDefinitions.IsValidItem(itemId) then
		return false
	end
	
	return true
end

-- Highlight item
function ItemPickup:_HighlightItem(item)
	if self._highlightedItem == item then return end
	
	-- Clear previous highlight
	self:_ClearHighlight()
	
	-- Create new highlight
	self._highlightedItem = item
	
	self._highlight = Instance.new("Highlight")
	self._highlight.FillTransparency = 1 -- No fill, only outline
	self._highlight.OutlineColor = HIGHLIGHT_COLOR
	self._highlight.OutlineTransparency = 0
	self._highlight.Parent = item
end

-- Clear highlight
function ItemPickup:_ClearHighlight()
	if self._highlight then
		self._highlight:Destroy()
		self._highlight = nil
	end
	self._highlightedItem = nil
end

-- Try to pickup highlighted item
function ItemPickup:_TryPickup()
	if not self._highlightedItem then
		return
	end
	
	local itemId = self._highlightedItem:GetAttribute("ItemId")
	if not itemId then
		warn("[ItemPickup] Highlighted item has no ItemId")
		return
	end
	
	-- Find first available slot
	local slotX, slotY = self:_FindAvailableSlot(itemId, false)
	
	if not slotX then
		-- Try rotated
		slotX, slotY = self:_FindAvailableSlot(itemId, true)
	end
	
	if slotX then
		-- Attempt to add item to inventory
		local success = self._remoteFunction:InvokeServer("AddItem", itemId, slotX, slotY, slotX ~= nil)
		
		if success then
			print(string.format("[ItemPickup] Picked up %s", itemId))
			
			-- Destroy world item
			self._highlightedItem:Destroy()
			self:_ClearHighlight()
		else
			warn("[ItemPickup] Failed to add item to inventory")
		end
	else
		warn("[ItemPickup] No space in inventory for " .. itemId)
		-- TODO: Show UI message to player
	end
end

-- Find first available slot for item
function ItemPickup:_FindAvailableSlot(itemId, isRotated)
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return nil, nil end
	
	local width = isRotated and itemDef.Height or itemDef.Width
	local height = isRotated and itemDef.Width or itemDef.Height
	
	-- Try each position in grid (top-left to bottom-right)
	for y = 1, 8 - height + 1 do -- GRID_HEIGHT = 8
		for x = 1, 6 - width + 1 do -- GRID_WIDTH = 6
			-- Check if item can be placed at this position
			local canPlace = self._remoteFunction:InvokeServer("CanPlaceItem", itemId, x, y, isRotated)
			if canPlace then
				return x, y
			end
		end
	end
	
	return nil, nil
end

return ItemPickup
