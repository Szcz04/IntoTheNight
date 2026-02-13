--[[
	InventoryDragDrop: Handles drag & drop and rotation for inventory items
	
	Features:
		- Click and hold to drag items
		- R key to rotate items (90° rotation, swaps width/height)
		- Validates placement before dropping
		- Visual feedback (ghost preview, valid/invalid colors)
	
	Depends on: InventoryUI (for grid references)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)

local InventoryDragDrop = {}
InventoryDragDrop.__index = InventoryDragDrop

-- Configuration
local SLOT_SIZE = 60
local SLOT_PADDING = 2
local GRID_WIDTH = 6
local GRID_HEIGHT = 8

-- Colors
local COLOR_VALID_PLACEMENT = Color3.fromRGB(50, 255, 50) -- Green
local COLOR_INVALID_PLACEMENT = Color3.fromRGB(255, 50, 50) -- Red

function InventoryDragDrop.new(inventoryUI)
	local self = setmetatable({}, InventoryDragDrop)
	
	self._player = Players.LocalPlayer
	self._inventoryUI = inventoryUI
	self._remoteFunction = ReplicatedStorage:WaitForChild("InventoryFunction")
	
	-- Drag state
	self._isDragging = false
	self._draggedItemIndex = nil
	self._draggedFrame = nil
	self._dragOffset = Vector2.new(0, 0)
	self._isRotated = false
	
	-- Ghost preview (shows where item will be placed)
	self._ghostFrame = nil
	
	-- Setup input
	self:_SetupInput()
	
	print("[InventoryDragDrop] Drag & drop system initialized")
	
	return self
end

-- Setup input listeners
function InventoryDragDrop:_SetupInput()
	-- Mouse button down: start dragging
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_TryStartDrag(input)
		elseif input.KeyCode == Enum.KeyCode.R then
			self:_TryRotate()
		end
	end)
	
	-- Mouse button up: stop dragging
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_StopDrag()
		end
	end)
	
	-- Mouse move: update drag position
	RunService.RenderStepped:Connect(function()
		if self._isDragging then
			self:_UpdateDrag()
		end
	end)
end

-- Try to start dragging an item
function InventoryDragDrop:_TryStartDrag(input)
	if not self._inventoryUI:IsOpen() then return end
	
	local mousePos = Vector2.new(input.Position.X, input.Position.Y)
	
	-- Check if mouse is over an item
	local itemIndex, itemFrame = self:_GetItemAtPosition(mousePos)
	if not itemIndex then return end
	
	-- Start dragging
	self._isDragging = true
	self._draggedItemIndex = itemIndex
	self._draggedFrame = itemFrame
	self._isRotated = false -- Reset rotation state
	
	-- Calculate offset from item's top-left corner
	local framePos = itemFrame.AbsolutePosition
	self._dragOffset = mousePos - framePos
	
	-- Increase ZIndex to bring item to front
	itemFrame.ZIndex = 10
	
	-- Create ghost preview
	self:_CreateGhostPreview(itemFrame)
	
	print(string.format("[InventoryDragDrop] Started dragging item %d", itemIndex))
end

-- Stop dragging and place item
function InventoryDragDrop:_StopDrag()
	if not self._isDragging then return end
	
	local gridPos = self:_GetGridPosition()
	
	if gridPos then
		-- Try to place item at grid position
		local success = self._remoteFunction:InvokeServer("MoveItem", self._draggedItemIndex, gridPos.X, gridPos.Y, self._isRotated)
		
		if success then
			print(string.format("[InventoryDragDrop] Placed item %d at (%d,%d) rotated=%s", self._draggedItemIndex, gridPos.X, gridPos.Y, tostring(self._isRotated)))
		else
			warn("[InventoryDragDrop] Invalid placement, item snapped back")
		end
	else
		print("[InventoryDragDrop] Dropped outside grid, item snapped back")
	end
	
	-- Reset drag state
	self._isDragging = false
	self._draggedItemIndex = nil
	if self._draggedFrame then
		self._draggedFrame.ZIndex = 3
		self._draggedFrame = nil
	end
	
	-- Remove ghost preview
	self:_DestroyGhostPreview()
end

-- Update drag position
function InventoryDragDrop:_UpdateDrag()
	if not self._draggedFrame then return end
	
	local mousePos = UserInputService:GetMouseLocation()
	local targetPos = mousePos - self._dragOffset
	
	-- Convert to relative position
	local container = self._draggedFrame.Parent
	local containerPos = container.AbsolutePosition
	local relativePos = targetPos - containerPos
	
	-- Update frame position
	self._draggedFrame.Position = UDim2.new(0, relativePos.X, 0, relativePos.Y)
	
	-- Update ghost preview
	self:_UpdateGhostPreview()
end

-- Get grid position from current mouse position
function InventoryDragDrop:_GetGridPosition()
	if not self._draggedFrame then return nil end
	
	local container = self._draggedFrame.Parent
	local containerPos = container.AbsolutePosition
	local mousePos = UserInputService:GetMouseLocation()
	local relativePos = mousePos - containerPos
	
	-- Convert pixel position to grid coordinates
	local gridX = math.floor(relativePos.X / (SLOT_SIZE + SLOT_PADDING)) + 1
	local gridY = math.floor(relativePos.Y / (SLOT_SIZE + SLOT_PADDING)) + 1
	
	-- Check if within bounds
	if gridX < 1 or gridX > GRID_WIDTH or gridY < 1 or gridY > GRID_HEIGHT then
		return nil
	end
	
	return Vector2.new(gridX, gridY)
end

-- Get item at mouse position
function InventoryDragDrop:_GetItemAtPosition(mousePos)
	local items = self._inventoryUI._items
	
	for index, frame in pairs(items) do
		local framePos = frame.AbsolutePosition
		local frameSize = frame.AbsoluteSize
		
		if mousePos.X >= framePos.X and mousePos.X <= framePos.X + frameSize.X and
		   mousePos.Y >= framePos.Y and mousePos.Y <= framePos.Y + frameSize.Y then
			return index, frame
		end
	end
	
	return nil, nil
end

-- Try to rotate current item
function InventoryDragDrop:_TryRotate()
	if not self._isDragging then return end
	
	-- Toggle rotation state
	self._isRotated = not self._isRotated
	
	-- Update ghost preview
	self:_UpdateGhostPreview()
	
	print(string.format("[InventoryDragDrop] Rotated item, isRotated=%s", tostring(self._isRotated)))
end

-- Create ghost preview frame
function InventoryDragDrop:_CreateGhostPreview(sourceFrame)
	if self._ghostFrame then
		self._ghostFrame:Destroy()
	end
	
	local ghost = sourceFrame:Clone()
	ghost.Name = "GhostPreview"
	ghost.ZIndex = 5
	ghost.BackgroundTransparency = 0.5
	ghost.Parent = sourceFrame.Parent
	
	self._ghostFrame = ghost
end

-- Update ghost preview position and color
function InventoryDragDrop:_UpdateGhostPreview()
	if not self._ghostFrame or not self._isDragging then return end
	
	local gridPos = self:_GetGridPosition()
	
	if gridPos then
		-- Get item info
		local items = self._remoteFunction:InvokeServer("GetInventory")
		local item = items[self._draggedItemIndex]
		if not item then return end
		
		-- Check if placement is valid
		local isValid = self._remoteFunction:InvokeServer("CanPlaceItem", item.itemId, gridPos.X, gridPos.Y, self._isRotated, self._draggedItemIndex)
		
		-- Update color based on validity
		if isValid then
			self._ghostFrame.BorderColor3 = COLOR_VALID_PLACEMENT
		else
			self._ghostFrame.BorderColor3 = COLOR_INVALID_PLACEMENT
		end
		
		-- Update size if rotated
		local itemDef = ItemDefinitions.GetItem(item.itemId)
		local width = self._isRotated and itemDef.Height or itemDef.Width
		local height = self._isRotated and itemDef.Width or itemDef.Height
		
		-- Snap to grid
		self._ghostFrame.Position = UDim2.new(0, (gridPos.X - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (gridPos.Y - 1) * (SLOT_SIZE + SLOT_PADDING))
		self._ghostFrame.Size = UDim2.new(0, width * SLOT_SIZE + (width - 1) * SLOT_PADDING, 0, height * SLOT_SIZE + (height - 1) * SLOT_PADDING)
	else
		-- Outside grid: hide ghost
		self._ghostFrame.Visible = false
		return
	end
	
	self._ghostFrame.Visible = true
end

-- Destroy ghost preview
function InventoryDragDrop:_DestroyGhostPreview()
	if self._ghostFrame then
		self._ghostFrame:Destroy()
		self._ghostFrame = nil
	end
end

return InventoryDragDrop
