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
		
		-- Check if hit part is a pickup item (or part of one)
		local isPickup, pickupItem = self:_IsPickupItem(hitPart)
		if isPickup and pickupItem then
			self:_HighlightItem(pickupItem)
			return
		end
	end
	
	-- No item found: clear highlight
	self:_ClearHighlight()
end

-- Check if part is a pickup item
function ItemPickup:_IsPickupItem(part)
	-- Check the part itself and its ancestors for "ItemPickup" tag
	local current = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, "ItemPickup") then
			-- Found tagged item - verify it has ItemId
			local itemId = current:GetAttribute("ItemId")
			if itemId and ItemDefinitions.IsValidItem(itemId) then
				return true, current -- Return both bool and the actual item
			end
		end
		current = current.Parent
	end
	
	return false, nil
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
	
	-- Get UUID of the specific item (handles duplicate names correctly)
	local itemUUID = self._highlightedItem:GetAttribute("ItemUUID")
	if not itemUUID then
		warn(string.format("[ItemPickup] Highlighted item %s has no UUID!", self._highlightedItem:GetFullName()))
		return
	end
	
	print(string.format("[ItemPickup] Attempting to pick up %s with UUID: %s", itemId, itemUUID))
	
	-- Let server handle both removal from world and addition to inventory
	local success = self._remoteFunction:InvokeServer("PickupItem", itemUUID)
	
	if success then
		print(string.format("[ItemPickup] Picked up %s", itemId))
		self:_ClearHighlight()
	else
		warn("[ItemPickup] Failed to pickup item (no space or already taken)")
	end
end

return ItemPickup
