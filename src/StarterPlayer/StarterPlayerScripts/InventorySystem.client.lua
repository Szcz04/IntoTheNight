--[[
	InventorySystem: Complete client-side inventory solution
	
	Features:
		- Grid-based UI (6x8) that slides from right
		- Drag & drop with rotation (R key)
		- Raycast item pickup (E key with white highlight)
		- Blocks movement when inventory open

	PROJECT DIRECTION NOTES:
	- Keep interactions quick and readable so players can stay socially blended.
	- TODO: prioritize sabotage/deception actions over inventory micromanagement during active stealth moments.
	- TODO: surface suspicion-safe vs suspicious item actions in UI hints.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)

local player = Players.LocalPlayer

-- UI Configuration
local GRID_WIDTH = 6
local GRID_HEIGHT = 4
local SLOT_SIZE = 60
local SLOT_PADDING = 2
local ANIMATION_TIME = 0.4

-- Colors
local COLOR_SLOT_EMPTY = Color3.fromRGB(30, 30, 35)
local COLOR_SLOT_BORDER = Color3.fromRGB(50, 50, 60)
local COLOR_BACKGROUND = Color3.fromRGB(20, 20, 25)
local COLOR_VALID_PLACEMENT = Color3.fromRGB(50, 255, 50)
local COLOR_INVALID_PLACEMENT = Color3.fromRGB(255, 50, 50)
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 255, 255)

-- Pickup configuration
local RAYCAST_DISTANCE = 10

-- State
local isOpen = false
local items = {}
local isDragging = false
local draggedItemIndex = nil
local draggedFrame = nil
local dragOffset = Vector2.new(0, 0)
local rotationOffset = Vector2.new(0, 0) -- Accumulated offset from rotations
local isRotated = false
local initialRotation = false -- Was item rotated when drag started?
local ghostFrame = nil
local highlightedItem = nil
local highlight = nil
local cursorUnlockLoop = nil -- Connection for cursor unlock loop
local equippedItemId = nil -- Currently equipped item
local dragFromEquipped = false -- Is drag from equipped slot?
local currentMousePos = Vector2.new(0, 0) -- Track mouse position consistently
local localGridOffset = Vector2.new(0, 0) -- Which sub-grid of item was clicked

-- Tooltip system
local tooltipVisible = false
local tooltipTimer = nil
local hoveredItemIndex = nil
local hoverConnections = {} -- {itemIndex = RBXScriptConnection}

-- UI Elements
local screenGui
local container
local gridContainer
local itemContainer
local equippedSlot
local equippedItemFrame
local tooltipFrame
local tooltipTitle
local tooltipDescription

-- RemoteEvent/Function
local remoteEvent
local remoteFunction

-- ========================================
-- UI Creation
-- ========================================

local function createUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = true -- Explicitly enable
	screenGui.DisplayOrder = 100 -- Put on top
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	print(string.format("[InventorySystem] Created ScreenGui (Enabled=%s, Parent=%s)", tostring(screenGui.Enabled), tostring(screenGui.Parent)))
	
	container = Instance.new("Frame")
	container.Name = "InventoryContainer"
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.Position = UDim2.new(1.5, 0, 0.5, 0)
	container.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH + 40, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT + 60)
	container.BackgroundColor3 = COLOR_BACKGROUND
	container.BorderSizePixel = 0
	container.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container
	
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0, 20, 0, 10)
	title.Size = UDim2.new(1, -40, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "EKWIPUNEK [B]"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.Parent = container
	
	gridContainer = Instance.new("Frame")
	gridContainer.Name = "GridContainer"
	gridContainer.Position = UDim2.new(0, 20, 0, 50)
	gridContainer.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Parent = container
	
	-- Create grid slots
	for y = 1, GRID_HEIGHT do
		for x = 1, GRID_WIDTH do
			local slot = Instance.new("Frame")
			slot.Name = string.format("Slot_%d_%d", x, y)
			slot.Position = UDim2.new(0, (x - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (y - 1) * (SLOT_SIZE + SLOT_PADDING))
			slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
			slot.BackgroundColor3 = COLOR_SLOT_EMPTY
			slot.BorderSizePixel = 1
			slot.BorderColor3 = COLOR_SLOT_BORDER
			slot.Parent = gridContainer
			
			local slotCorner = Instance.new("UICorner")
			slotCorner.CornerRadius = UDim.new(0, 4)
			slotCorner.Parent = slot
		end
	end
	
	itemContainer = Instance.new("Frame")
	itemContainer.Name = "ItemContainer"
	itemContainer.Position = UDim2.new(0, 20, 0, 50)
	itemContainer.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT)
	itemContainer.BackgroundTransparency = 1
	itemContainer.ZIndex = 2
	itemContainer.Parent = container
	
	-- Create equipped slot
	local equippedSlotSize = SLOT_SIZE * 2 + SLOT_PADDING
	
	equippedSlot = Instance.new("Frame")
	equippedSlot.Name = "EquippedSlot"
	equippedSlot.Position = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH + 40, 0, 50)
	equippedSlot.Size = UDim2.new(0, equippedSlotSize, 0, equippedSlotSize)
	equippedSlot.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	equippedSlot.BorderSizePixel = 2
	equippedSlot.BorderColor3 = Color3.fromRGB(100, 150, 200)
	equippedSlot.Parent = container
	
	local equippedCorner = Instance.new("UICorner")
	equippedCorner.CornerRadius = UDim.new(0, 8)
	equippedCorner.Parent = equippedSlot
	
	local equippedLabel = Instance.new("TextLabel")
	equippedLabel.Name = "Label"
	equippedLabel.Position = UDim2.new(0, 0, 1, 5)
	equippedLabel.Size = UDim2.new(1, 0, 0, 20)
	equippedLabel.BackgroundTransparency = 1
	equippedLabel.Text = "EQUIPPED"
	equippedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	equippedLabel.TextSize = 12
	equippedLabel.Font = Enum.Font.GothamBold
	equippedLabel.Parent = equippedSlot
	
	-- Container needs to be wider now
	container.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH + equippedSlotSize + 80, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT + 60)
	
	-- Tooltip (attached to cursor)
	tooltipFrame = Instance.new("Frame")
	tooltipFrame.Name = "Tooltip"
	tooltipFrame.Size = UDim2.new(0, 200, 0, 0) -- Height auto-sized
	tooltipFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	tooltipFrame.BorderSizePixel = 2
	tooltipFrame.BorderColor3 = Color3.fromRGB(100, 100, 120)
	tooltipFrame.ZIndex = 100
	tooltipFrame.Visible = false
	tooltipFrame.Parent = screenGui
	
	local tooltipCorner = Instance.new("UICorner")
	tooltipCorner.CornerRadius = UDim.new(0, 4)
	tooltipCorner.Parent = tooltipFrame
	
	tooltipTitle = Instance.new("TextLabel")
	tooltipTitle.Name = "Title"
	tooltipTitle.Size = UDim2.new(1, -16, 0, 25)
	tooltipTitle.Position = UDim2.new(0, 8, 0, 8)
	tooltipTitle.BackgroundTransparency = 1
	tooltipTitle.Text = ""
	tooltipTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	tooltipTitle.TextSize = 14
	tooltipTitle.Font = Enum.Font.GothamBold
	tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
	tooltipTitle.TextYAlignment = Enum.TextYAlignment.Top
	tooltipTitle.ZIndex = 101
	tooltipTitle.Parent = tooltipFrame
	
	tooltipDescription = Instance.new("TextLabel")
	tooltipDescription.Name = "Description"
	tooltipDescription.Size = UDim2.new(1, -16, 1, -41)
	tooltipDescription.Position = UDim2.new(0, 8, 0, 33)
	tooltipDescription.BackgroundTransparency = 1
	tooltipDescription.Text = ""
	tooltipDescription.TextColor3 = Color3.fromRGB(200, 200, 200)
	tooltipDescription.TextSize = 12
	tooltipDescription.Font = Enum.Font.Gotham
	tooltipDescription.TextXAlignment = Enum.TextXAlignment.Left
	tooltipDescription.TextYAlignment = Enum.TextYAlignment.Top
	tooltipDescription.TextWrapped = true
	tooltipDescription.ZIndex = 101
	tooltipDescription.Parent = tooltipFrame
	
	-- Update tooltip position with mouse (runs every frame)
	RunService.RenderStepped:Connect(function()
		if tooltipVisible then
			updateTooltipPosition()
		end
	end)
	
	print("[InventorySystem] UI created with equipped slot")
end

-- ========================================
-- UI Control
-- ========================================

local function openInventory()
	if isOpen then return end
	isOpen = true
	
	print("[InventorySystem] Opening inventory...")
	
	-- Force unlock cursor repeatedly (Roblox sometimes fights back)
	if cursorUnlockLoop then
		cursorUnlockLoop:Disconnect()
	end
	
	cursorUnlockLoop = RunService.RenderStepped:Connect(function()
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
	
	print("[InventorySystem] Forcing cursor unlock (loop active)")
	
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			print("[InventorySystem] Disabled character movement")
		end
	end
	
	local tween = TweenService:Create(container, TweenInfo.new(ANIMATION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -20, 0.5, 0)
	})
	tween:Play()
	
	print("[InventorySystem] Opened")
end

local function closeInventory()
	if not isOpen then return end
	isOpen = false
	
	-- Hide tooltip when closing inventory
	hideTooltip()
	
	-- Stop forcing cursor unlock
	if cursorUnlockLoop then
		cursorUnlockLoop:Disconnect()
		cursorUnlockLoop = nil
	end
	
	-- Lock cursor back (first person mode)
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	print("[InventorySystem] Cursor locked back")
	
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
		end
	end
	
	local tween = TweenService:Create(container, TweenInfo.new(ANIMATION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(1.5, 0, 0.5, 0)
	})
	tween:Play()
	
	print("[InventorySystem] Closed")
end

local function toggleInventory()
	if isOpen then
		closeInventory()
	else
		openInventory()
	end
end

-- ========================================
-- Item Display
-- ========================================

local function createItemFrame(item, itemIndex)
	local itemDef = ItemDefinitions.GetItem(item.itemId)
	if not itemDef then return end
	
	local frame = Instance.new("Frame")
	frame.Name = string.format("Item_%d", itemIndex)
	frame.Position = UDim2.new(0, (item.x - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (item.y - 1) * (SLOT_SIZE + SLOT_PADDING))
	frame.Size = UDim2.new(0, item.width * SLOT_SIZE + (item.width - 1) * SLOT_PADDING, 0, item.height * SLOT_SIZE + (item.height - 1) * SLOT_PADDING)
	frame.BackgroundColor3 = itemDef.Color
	frame.BorderSizePixel = 2
	frame.BorderColor3 = Color3.fromRGB(255, 255, 255)
	frame.ZIndex = 3
	frame.Parent = itemContainer
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = itemDef.Name
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 12
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true
	label.ZIndex = 4
	label.Parent = frame
	
	-- Hover detection for tooltip
	local isHovering = false
	
	local function checkHover()
		if not isOpen then return end
		if isDragging then return end -- Don't show tooltip while dragging
		
		-- Get mouse position accounting for GUI inset (topbar offset)
		local GuiService = game:GetService("GuiService")
		local mousePos = UserInputService:GetMouseLocation()
		local guiInset = GuiService:GetGuiInset()
		local adjustedMousePos = mousePos - guiInset
		
		local framePos = frame.AbsolutePosition
		local frameSize = frame.AbsoluteSize
		
		local inBounds = adjustedMousePos.X >= framePos.X and adjustedMousePos.X <= framePos.X + frameSize.X
			and adjustedMousePos.Y >= framePos.Y and adjustedMousePos.Y <= framePos.Y + frameSize.Y
		
		if inBounds and not isHovering then
			isHovering = true
			print(string.format("[InventorySystem] Mouse entered item %d (%s)", itemIndex, itemDef.Name))
			startTooltipTimer(itemIndex, item)
		elseif not inBounds and isHovering then
			isHovering = false
			print(string.format("[InventorySystem] Mouse left item %d", itemIndex))
			hideTooltip()
		end
	end
	
	local hoverConnection = RunService.RenderStepped:Connect(checkHover)
	hoverConnections[itemIndex] = hoverConnection
	
	items[itemIndex] = frame
end

local function removeItemFrame(itemIndex)
	local frame = items[itemIndex]
	if frame then
		-- Disconnect hover connection
		local hoverConnection = hoverConnections[itemIndex]
		if hoverConnection then
			hoverConnection:Disconnect()
			hoverConnections[itemIndex] = nil
		end
		
		-- Hide tooltip if this was the hovered item
		if hoveredItemIndex == itemIndex then
			hideTooltip()
		end
		
		frame:Destroy()
		items[itemIndex] = nil
	end
end

local function updateItemFrame(itemIndex, item)
	local frame = items[itemIndex]
	if not frame then return end
	
	frame.Position = UDim2.new(0, (item.x - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (item.y - 1) * (SLOT_SIZE + SLOT_PADDING))
	frame.Size = UDim2.new(0, item.width * SLOT_SIZE + (item.width - 1) * SLOT_PADDING, 0, item.height * SLOT_SIZE + (item.height - 1) * SLOT_PADDING)
end

local function clearAllItems()
	-- Disconnect all hover connections
	for _, connection in pairs(hoverConnections) do
		connection:Disconnect()
	end
	hoverConnections = {}
	
	-- Hide tooltip
	hideTooltip()
	
	for _, frame in pairs(items) do
		frame:Destroy()
	end
	items = {}
end

-- ========================================
-- Tooltip System
-- ========================================

local function showTooltip(itemIndex, item)
	if not isOpen then return end
	
	local itemDef = ItemDefinitions.GetItem(item.itemId)
	if not itemDef then return end
	
	-- Update tooltip content
	tooltipTitle.Text = itemDef.Name
	tooltipDescription.Text = itemDef.Description or "No description"
	
	-- Calculate tooltip height based on text
	local textBounds = tooltipDescription.TextBounds
	local tooltipHeight = 41 + textBounds.Y + 16 -- Title + description + padding
	tooltipFrame.Size = UDim2.new(0, 200, 0, tooltipHeight)
	
	-- Show tooltip
	tooltipVisible = true
	tooltipFrame.Visible = true
	hoveredItemIndex = itemIndex
	
	updateTooltipPosition()
	
	print(string.format("[InventorySystem] Showing tooltip for %s", itemDef.Name))
end

function hideTooltip()
	tooltipVisible = false
	tooltipFrame.Visible = false
	hoveredItemIndex = nil
	
	-- Cancel any pending timer
	if tooltipTimer then
		task.cancel(tooltipTimer)
		tooltipTimer = nil
	end
end

function updateTooltipPosition()
	-- Get mouse position accounting for GUI inset
	local GuiService = game:GetService("GuiService")
	local mousePos = UserInputService:GetMouseLocation()
	local guiInset = GuiService:GetGuiInset()
	local adjustedMousePos = mousePos - guiInset
	
	local offset = Vector2.new(15, 15) -- Offset from cursor
	
	-- Keep tooltip on screen
	local tooltipSize = tooltipFrame.AbsoluteSize
	local screenSize = screenGui.AbsoluteSize
	
	local x = adjustedMousePos.X + offset.X
	local y = adjustedMousePos.Y + offset.Y
	
	-- Prevent tooltip from going off right edge
	if x + tooltipSize.X > screenSize.X then
		x = adjustedMousePos.X - tooltipSize.X - 5
	end
	
	-- Prevent tooltip from going off bottom edge
	if y + tooltipSize.Y > screenSize.Y then
		y = adjustedMousePos.Y - tooltipSize.Y - 5
	end
	
	tooltipFrame.Position = UDim2.new(0, x, 0, y)
end

function startTooltipTimer(itemIndex, item)
	-- Cancel existing timer
	if tooltipTimer then
		task.cancel(tooltipTimer)
	end
	
	-- Start 1.5 second delay
	tooltipTimer = task.delay(1.5, function()
		showTooltip(itemIndex, item)
	end)
end

-- ========================================
-- Drag & Drop
-- ========================================

local function getGridPosition()
	if not draggedFrame then return nil end
	
	-- Use the actual frame position (which includes rotationOffset) instead of recalculating from mouse
	local framePos = draggedFrame.AbsolutePosition
	local containerPos = itemContainer.AbsolutePosition
	local relativePos = framePos - containerPos
	
	-- Calculate grid position from frame's top-left corner
	local gridX = math.floor(relativePos.X / (SLOT_SIZE + SLOT_PADDING)) + 1
	local gridY = math.floor(relativePos.Y / (SLOT_SIZE + SLOT_PADDING)) + 1
	
	if gridX < 1 or gridX > GRID_WIDTH or gridY < 1 or gridY > GRID_HEIGHT then
		return nil
	end
	
	return Vector2.new(gridX, gridY)
end

local function isMouseOverEquippedSlot()
	if not equippedSlot then return false end
	
	local slotPos = equippedSlot.AbsolutePosition
	local slotSize = equippedSlot.AbsoluteSize
	
	return currentMousePos.X >= slotPos.X and currentMousePos.X <= slotPos.X + slotSize.X and
	       currentMousePos.Y >= slotPos.Y and currentMousePos.Y <= slotPos.Y + slotSize.Y
end

local function getItemAtPosition(mousePos)
	-- Check equipped slot first
	if equippedItemFrame then
		local framePos = equippedItemFrame.AbsolutePosition
		local frameSize = equippedItemFrame.AbsoluteSize
		
		if mousePos.X >= framePos.X and mousePos.X <= framePos.X + frameSize.X and
		   mousePos.Y >= framePos.Y and mousePos.Y <= framePos.Y + frameSize.Y then
			return "equipped", equippedItemFrame
		end
	end
	
	-- Check grid items
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

local function createGhostPreview(sourceFrame)
	if ghostFrame then
		ghostFrame:Destroy()
	end
	
	local ghost = sourceFrame:Clone()
	ghost.Name = "GhostPreview"
	ghost.ZIndex = 5
	ghost.BackgroundTransparency = 0.5
	ghost.Parent = sourceFrame.Parent
	
	ghostFrame = ghost
end

local function updateGhostPreview()
	if not isDragging then return end
	if not ghostFrame then 
		print("[InventorySystem] Warning: ghostFrame is nil during drag")
		return 
	end
	
	-- Check if over equipped slot
	if isMouseOverEquippedSlot() and not dragFromEquipped then
		-- Check if item is equippable
		local itemList = remoteFunction:InvokeServer("GetInventory")
		-- Re-check ghostFrame after async server call
		if not ghostFrame then return end
		
		if itemList and draggedItemIndex then
			local item = itemList[draggedItemIndex]
			if item then
				local itemDef = ItemDefinitions.GetItem(item.itemId)
				if itemDef and itemDef.IsEquippable then
					ghostFrame.BorderColor3 = COLOR_VALID_PLACEMENT
				else
					ghostFrame.BorderColor3 = COLOR_INVALID_PLACEMENT
				end
			end
		end
		
		-- Position ghost over equipped slot
		local slotPos = equippedSlot.AbsolutePosition
		local containerPos = itemContainer.AbsolutePosition
		local relativePos = slotPos - containerPos
		
		ghostFrame.Position = UDim2.new(0, relativePos.X, 0, relativePos.Y)
		ghostFrame.Size = UDim2.new(0, equippedSlot.AbsoluteSize.X, 0, equippedSlot.AbsoluteSize.Y)
		ghostFrame.Visible = true
		return
	end
	
	-- Check grid position
	local gridPos = getGridPosition()
	
	if gridPos then
		if dragFromEquipped then
			-- Dragging from equipped to grid
			local equippedItemId = remoteFunction:InvokeServer("GetEquipped")
			-- Re-check ghostFrame after async server call
			if not ghostFrame then return end
			
			if equippedItemId then
				local isValid = remoteFunction:InvokeServer("CanPlaceItem", equippedItemId, gridPos.X, gridPos.Y, false, nil)
				-- Re-check ghostFrame after async server call
				if not ghostFrame then return end
				
				if isValid then
					ghostFrame.BorderColor3 = COLOR_VALID_PLACEMENT
				else
					ghostFrame.BorderColor3 = COLOR_INVALID_PLACEMENT
				end
				
				local itemDef = ItemDefinitions.GetItem(equippedItemId)
				ghostFrame.Position = UDim2.new(0, (gridPos.X - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (gridPos.Y - 1) * (SLOT_SIZE + SLOT_PADDING))
				ghostFrame.Size = UDim2.new(0, itemDef.Width * SLOT_SIZE + (itemDef.Width - 1) * SLOT_PADDING, 0, itemDef.Height * SLOT_SIZE + (itemDef.Height - 1) * SLOT_PADDING)
			end
		else
			-- Normal grid to grid
			local itemList = remoteFunction:InvokeServer("GetInventory")
			-- Re-check ghostFrame after async server call
			if not ghostFrame then return end
			
			local item = itemList[draggedItemIndex]
			if not item then return end
			
			local isValid = remoteFunction:InvokeServer("CanPlaceItem", item.itemId, gridPos.X, gridPos.Y, isRotated, draggedItemIndex)
			-- Re-check ghostFrame after async server call
			if not ghostFrame then return end
			
			if isValid then
				ghostFrame.BorderColor3 = COLOR_VALID_PLACEMENT
			else
				ghostFrame.BorderColor3 = COLOR_INVALID_PLACEMENT
			end
			
			local itemDef = ItemDefinitions.GetItem(item.itemId)
			local width = isRotated and itemDef.Height or itemDef.Width
			local height = isRotated and itemDef.Width or itemDef.Height
			
			ghostFrame.Position = UDim2.new(0, (gridPos.X - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (gridPos.Y - 1) * (SLOT_SIZE + SLOT_PADDING))
			ghostFrame.Size = UDim2.new(0, width * SLOT_SIZE + (width - 1) * SLOT_PADDING, 0, height * SLOT_SIZE + (height - 1) * SLOT_PADDING)
		end
		
		ghostFrame.Visible = true
	else
		ghostFrame.Visible = false
	end
end

local function destroyGhostPreview()
	if ghostFrame then
		ghostFrame:Destroy()
		ghostFrame = nil
	end
end

local function tryStartDrag(input)
	if not isOpen then return end
	
	-- Update mouse position (in case InputChanged hasn't fired yet)
	currentMousePos = Vector2.new(input.Position.X, input.Position.Y)
	
	local itemIndex, itemFrame = getItemAtPosition(currentMousePos)
	if not itemIndex then return end
	
	-- Check if dragging from equipped slot
	if itemIndex == "equipped" then
		dragFromEquipped = true
		draggedItemIndex = nil
	else
		dragFromEquipped = false
		draggedItemIndex = itemIndex
	end
	
	isDragging = true
	draggedFrame = itemFrame
	
	-- Hide tooltip when starting to drag
	hideTooltip()
	
	-- Check if item was already rotated
	if not dragFromEquipped and draggedItemIndex then
		local itemList = remoteFunction:InvokeServer("GetInventory")
		if itemList and itemList[draggedItemIndex] then
			initialRotation = itemList[draggedItemIndex].isRotated or false
		else
			initialRotation = false
		end
	else
		initialRotation = false
	end
	isRotated = initialRotation -- Start with item's current rotation state
	
	-- Calculate offset from exact click position
	local framePos = itemFrame.AbsolutePosition
	dragOffset = currentMousePos - framePos
	
	-- Calculate which sub-grid within the item was clicked
	local clickOffsetX = currentMousePos.X - framePos.X
	local clickOffsetY = currentMousePos.Y - framePos.Y
	localGridOffset = Vector2.new(
		math.floor(clickOffsetX / (SLOT_SIZE + SLOT_PADDING)),
		math.floor(clickOffsetY / (SLOT_SIZE + SLOT_PADDING))
	)
	
	-- If dragging from equipped slot, restore proper item size first
	if dragFromEquipped then
		local equippedItemId = remoteFunction:InvokeServer("GetEquipped")
		if equippedItemId then
			local itemDef = ItemDefinitions.GetItem(equippedItemId)
			if itemDef then
				-- Set to proper grid size
				local properWidth = itemDef.Width * SLOT_SIZE + (itemDef.Width - 1) * SLOT_PADDING
				local properHeight = itemDef.Height * SLOT_SIZE + (itemDef.Height - 1) * SLOT_PADDING
				itemFrame.Size = UDim2.new(0, properWidth, 0, properHeight)
			end
		end
		-- Move to itemContainer after resizing
		itemFrame.Parent = itemContainer
		
		-- Recalculate offset after moving to new parent
		local newFramePos = itemFrame.AbsolutePosition
		dragOffset = currentMousePos - newFramePos
		
		-- Recalculate sub-grid offset
		local newClickOffsetX = currentMousePos.X - newFramePos.X
		local newClickOffsetY = currentMousePos.Y - newFramePos.Y
		localGridOffset = Vector2.new(
			math.floor(newClickOffsetX / (SLOT_SIZE + SLOT_PADDING)),
			math.floor(newClickOffsetY / (SLOT_SIZE + SLOT_PADDING))
		)
	end
	
	itemFrame.ZIndex = 10
	createGhostPreview(itemFrame)
	
	print(string.format("[InventorySystem] Started dragging (fromEquipped=%s, index=%s)", tostring(dragFromEquipped), tostring(itemIndex)))
end

local function stopDrag()
	if not isDragging then return end
	
	local success = false
	
	-- Check if dropping battery onto flashlight (for charging)
	local targetItemIndex, _ = getItemAtPosition(currentMousePos)
	
	if targetItemIndex and draggedItemIndex and targetItemIndex ~= draggedItemIndex then
		-- Check if we're dropping battery on flashlight
		local itemList = remoteFunction:InvokeServer("GetInventory")
		if itemList then
			local draggedItem = itemList[draggedItemIndex]
			local targetItem = targetItemIndex == "equipped" and nil or itemList[targetItemIndex]
			
			-- Battery -> Flashlight in inventory
			if draggedItem and draggedItem.itemId == "Battery" and targetItem and targetItem.itemId == "Flashlight" then
				success = remoteFunction:InvokeServer("ChargeFlashlight", targetItemIndex, draggedItemIndex)
				if success then
					print("[InventorySystem] Charged flashlight in inventory")
				else
					print("[InventorySystem] Flashlight already fully charged or error")
				end
			-- Battery -> Equipped Flashlight
			elseif draggedItem and draggedItem.itemId == "Battery" and targetItemIndex == "equipped" then
				local equippedItemId = remoteFunction:InvokeServer("GetEquipped")
				if equippedItemId == "Flashlight" then
					success = remoteFunction:InvokeServer("ChargeFlashlight", "equipped", draggedItemIndex)
					if success then
						print("[InventorySystem] Charged equipped flashlight")
					else
						print("[InventorySystem] Flashlight already fully charged or error")
					end
				end
			end
		end
	end
	
	-- If charging was attempted and successful, skip normal drag logic
	if success then
		-- Reset drag state
		isDragging = false
		draggedItemIndex = nil
		dragFromEquipped = false
		if draggedFrame then
			draggedFrame.ZIndex = 3
			draggedFrame = nil
		end
		if ghostFrame then
			ghostFrame:Destroy()
			ghostFrame = nil
		end
		return
	end
	
	-- Determine where we're dropping
	if isMouseOverEquippedSlot() and not dragFromEquipped then
		-- Dropping into equipped slot from grid
		if draggedItemIndex then
			local itemList = remoteFunction:InvokeServer("GetInventory")
			if itemList then
				local item = itemList[draggedItemIndex]
				if item then
					local itemDef = ItemDefinitions.GetItem(item.itemId)
					if itemDef and itemDef.IsEquippable then
						-- Valid equippable item
						success = remoteFunction:InvokeServer("EquipItem", draggedItemIndex)
						if success then
							print(string.format("[InventorySystem] Equipped item %d (%s)", draggedItemIndex, item.itemId))
						end
					else
						print("[InventorySystem] Item is not equippable")
					end
				end
			end
		end
	elseif dragFromEquipped then
		-- Dropping from equipped slot to grid
		local gridPos = getGridPosition()
		if gridPos then
			success = remoteFunction:InvokeServer("UnequipItem", gridPos.X, gridPos.Y)
			if success then
				print(string.format("[InventorySystem] Unequipped to (%d,%d)", gridPos.X, gridPos.Y))
			end
		end
	else
		-- Normal grid to grid movement
		local gridPos = getGridPosition()
		if gridPos and draggedItemIndex then
			success = remoteFunction:InvokeServer("MoveItem", draggedItemIndex, gridPos.X, gridPos.Y, isRotated)
			if success then
				print(string.format("[InventorySystem] Placed item %d at (%d,%d)", draggedItemIndex, gridPos.X, gridPos.Y))
			else
				print("[InventorySystem] Invalid placement - snapping back")
			end
		end
	end
	
	-- If move failed, snap back
	if not success then
		if dragFromEquipped then
			-- Snap back to equipped slot
			if draggedFrame and equippedSlot then
				draggedFrame.Position = UDim2.new(0, 0, 0, 0)
				draggedFrame.Size = UDim2.new(1, 0, 1, 0)
				draggedFrame.Parent = equippedSlot
				print("[InventorySystem] Snapped back to equipped slot")
			end
		else
			-- Snap back to grid position
			local itemList = remoteFunction:InvokeServer("GetInventory")
			if itemList and draggedItemIndex then
				local item = itemList[draggedItemIndex]
				if item and draggedFrame then
					draggedFrame.Parent = itemContainer
					draggedFrame.Position = UDim2.new(0, (item.x - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (item.y - 1) * (SLOT_SIZE + SLOT_PADDING))
					draggedFrame.Size = UDim2.new(0, item.width * SLOT_SIZE + (item.width - 1) * SLOT_PADDING, 0, item.height * SLOT_SIZE + (item.height - 1) * SLOT_PADDING)
					print("[InventorySystem] Snapped back to grid")
				end
			end
		end
	end
	
	-- Reset drag state
	isDragging = false
	draggedItemIndex = nil
	dragFromEquipped = false
	initialRotation = false
	rotationOffset = Vector2.new(0, 0)
	localGridOffset = Vector2.new(0, 0)
	if draggedFrame then
		draggedFrame.ZIndex = 3
		draggedFrame = nil
	end
	
	-- Destroy ghost AFTER resetting state
	destroyGhostPreview()
	
	print("[InventorySystem] Drag ended, ghost destroyed")
end

local function updateDrag()
	if not draggedFrame then return end
	
	-- Position frame so click point stays at cursor
	local targetPos = currentMousePos - dragOffset + rotationOffset
	
	-- Make relative to container
	local containerPos = itemContainer.AbsolutePosition
	local relativePos = targetPos - containerPos
	
	draggedFrame.Position = UDim2.new(0, relativePos.X, 0, relativePos.Y)
	
	updateGhostPreview()
end

local function tryRotate()
	if not isDragging then return end
	if not draggedItemIndex and not dragFromEquipped then return end
	
	-- Get item info to know dimensions
	local itemId = nil
	if dragFromEquipped then
		itemId = remoteFunction:InvokeServer("GetEquipped")
	else
		local itemList = remoteFunction:InvokeServer("GetInventory")
		if itemList and itemList[draggedItemIndex] then
			itemId = itemList[draggedItemIndex].itemId
		end
	end
	
	if not itemId then return end
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return end
	
	-- Calculate position of clicked sub-grid in pixels (relative to item's top-left)
	local oldSubGridX = localGridOffset.X * (SLOT_SIZE + SLOT_PADDING)
	local oldSubGridY = localGridOffset.Y * (SLOT_SIZE + SLOT_PADDING)
	
	-- Toggle rotation
	isRotated = not isRotated
	
	-- Swap grid offset for rotation (clicked grid changes position in rotated item)
	-- Example: if clicked right grid (2,0) of 3x1 item, after rotation it becomes bottom grid (0,2) of 1x3
	localGridOffset = Vector2.new(localGridOffset.Y, localGridOffset.X)
	
	-- Calculate new position of that same sub-grid after rotation
	local newSubGridX = localGridOffset.X * (SLOT_SIZE + SLOT_PADDING)
	local newSubGridY = localGridOffset.Y * (SLOT_SIZE + SLOT_PADDING)
	
	-- Accumulate rotation offset to keep the clicked sub-grid under cursor
	local deltaX = newSubGridX - oldSubGridX
	local deltaY = newSubGridY - oldSubGridY
	rotationOffset = rotationOffset + Vector2.new(deltaX, deltaY)
	
	updateGhostPreview()
	
	print(string.format("[InventorySystem] Rotated item, isRotated=%s, localGridOffset=(%d,%d), rotationOffset=(%.1f,%.1f)", tostring(isRotated), localGridOffset.X, localGridOffset.Y, rotationOffset.X, rotationOffset.Y))
end

-- Try to drop item (right click)
local function tryDropItem(input)
	local itemIndex, itemFrame = getItemAtPosition(currentMousePos)
	
	if not itemIndex then return end
	
	-- Ask server to drop item
	local success = remoteFunction:InvokeServer("DropItem", itemIndex)
	
	if success then
		print(string.format("[InventorySystem] Dropped item %d", itemIndex))
	else
		warn("[InventorySystem] Failed to drop item")
	end
end

-- Display equipped item
local function updateEquippedDisplay(itemId)
	-- Remove old equipped item frame
	if equippedItemFrame then
		equippedItemFrame:Destroy()
		equippedItemFrame = nil
	end
	
	equippedItemId = itemId
	
	if not itemId then return end
	
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return end
	
	-- Create item display in equipped slot
	local frame = Instance.new("Frame")
	frame.Name = "EquippedItem"
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = itemDef.Color
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	frame.Parent = equippedSlot
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	
	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 5, 0, 5)
	label.Size = UDim2.new(1, -10, 1, -10)
	label.BackgroundTransparency = 1
	label.Text = itemDef.Name
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = frame
	
	equippedItemFrame = frame
	
	print(string.format("[InventorySystem] Updated equipped display: %s", itemId))
end

-- ========================================
-- Item Pickup
-- ========================================

local function isPickupItem(part)
	-- Walk up ancestors so pickup works for nested model structures.
	local current = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, "ItemPickup") then
			local itemId = current:GetAttribute("ItemId")
			if itemId and ItemDefinitions.IsValidItem(itemId) then
				return true, current
			end
		end
		current = current.Parent
	end
	
	return false, nil
end

local function highlightItem(item)
	if highlightedItem == item then return end
	
	clearHighlight()
	
	highlightedItem = item
	
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = HIGHLIGHT_COLOR
	highlight.OutlineTransparency = 0
	highlight.Parent = item
end

function clearHighlight()
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	highlightedItem = nil
end

local function updateRaycast()
	local character = player.Character
	if not character then return end
	
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local rayOrigin = camera.CFrame.Position
	local rayDirection = camera.CFrame.LookVector * RAYCAST_DISTANCE
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {character}
	
	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult then
		local hitPart = raycastResult.Instance
		
		local isItem, itemObject = isPickupItem(hitPart)
		if isItem then
			highlightItem(itemObject)
			return
		end
	end
	
	clearHighlight()
end

local function findAvailableSlot(itemId, isRot)
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return nil, nil end
	
	local width = isRot and itemDef.Height or itemDef.Width
	local height = isRot and itemDef.Width or itemDef.Height
	
	for y = 1, GRID_HEIGHT - height + 1 do
		for x = 1, GRID_WIDTH - width + 1 do
			local canPlace = remoteFunction:InvokeServer("CanPlaceItem", itemId, x, y, isRot)
			if canPlace then
				return x, y
			end
		end
	end
	
	return nil, nil
end

-- Try to consume hovered item (if it's consumable)
local function tryConsumeItem()
	-- Must be in inventory and hovering over an item
	if not isOpen or not hoveredItemIndex then
		return false
	end
	
	-- Get the hovered item data
	local itemList = remoteFunction:InvokeServer("GetInventory")
	if not itemList or not itemList[hoveredItemIndex] then
		return false
	end
	
	local item = itemList[hoveredItemIndex]
	local itemDef = ItemDefinitions.GetItem(item.itemId)
	
	-- Check if item is consumable
	if not itemDef or not itemDef.IsConsumable then
		return false
	end
	
	-- Consume the item
	local success = remoteFunction:InvokeServer("ConsumeItem", hoveredItemIndex)
	
	if success then
		print(string.format("[InventorySystem] Consumed %s", itemDef.Name))
		hideTooltip() -- Hide tooltip after consumption
		return true
	else
		warn(string.format("[InventorySystem] Failed to consume %s", itemDef.Name))
		return false
	end
end

local function tryPickup()
	if not highlightedItem then return end
	
	local itemId = highlightedItem:GetAttribute("ItemId")
	if not itemId then return end
	
	-- Get UUID of the specific item (handles duplicate names correctly)
	local itemUUID = highlightedItem:GetAttribute("ItemUUID")
	if not itemUUID then
		warn(string.format("[InventorySystem] Highlighted item %s has no UUID!", highlightedItem:GetFullName()))
		return
	end
	
	-- Send pickup request - server will handle removal and inventory add atomically
	local success = remoteFunction:InvokeServer("PickupItem", itemUUID)
	
	if success then
		print(string.format("[InventorySystem] Picked up %s", itemId))
		clearHighlight()
	else
		warn("[InventorySystem] Failed to pick up " .. itemId)
	end
end

-- ========================================
-- Server Communication
-- ========================================

local function requestInventory()
	if not remoteFunction then return end
	
	local success, itemList = pcall(function()
		return remoteFunction:InvokeServer("GetInventory")
	end)
	
	if success and itemList then
		for index, item in ipairs(itemList) do
			createItemFrame(item, index)
		end
	end
end

local function setupServerListeners()
	remoteEvent.OnClientEvent:Connect(function(action, ...)
		if action == "InventoryUpdated" then
			-- Full refresh with equipped item
			local itemList, equippedItemId = ...
			clearAllItems()
			if itemList then
				for index, item in ipairs(itemList) do
					createItemFrame(item, index)
				end
			end
			updateEquippedDisplay(equippedItemId)
		elseif action == "InventoryCleared" then
			clearAllItems()
		end
	end)
end

-- ========================================
-- Input Setup
-- ========================================

local function setupInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Debug: log B key presses
		if input.KeyCode == Enum.KeyCode.B then
			print(string.format("[InventorySystem] B key detected (gameProcessed=%s)", tostring(gameProcessed)))
		end
		
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.B then
			print("[InventorySystem] B key pressed - toggling inventory")
			toggleInventory()
		elseif input.KeyCode == Enum.KeyCode.R then
			tryRotate()
		elseif input.KeyCode == Enum.KeyCode.E then
			-- Try to consume hovered item first, if not then try to pickup
			if not tryConsumeItem() then
				tryPickup()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryStartDrag(input)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- Right click to drop item
			if isOpen then
				tryDropItem(input)
			end
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			stopDrag()
		end
	end)
	
	-- Track mouse position for consistent drag offset calculation
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			currentMousePos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	
	RunService.RenderStepped:Connect(function()
		if isDragging then
			updateDrag()
		else
			updateRaycast()
		end
	end)
	
	print("[InventorySystem] Input listeners active")
end

-- ========================================
-- Initialization
-- ========================================

createUI()
setupInput()

-- Connect to server
task.spawn(function()
	remoteEvent = ReplicatedStorage:WaitForChild("InventoryEvent", 10)
	remoteFunction = ReplicatedStorage:WaitForChild("InventoryFunction", 10)
	
	if not remoteEvent or not remoteFunction then
		warn("[InventorySystem] Failed to connect to server")
		return
	end
	
	setupServerListeners()
	requestInventory()
	
	-- Request equipped item
	local equippedItemId = remoteFunction:InvokeServer("GetEquipped")
	if equippedItemId then
		updateEquippedDisplay(equippedItemId)
	end
	
	print("[InventorySystem] Connected to server")
end)

print("[InventorySystem] Inventory system initialized")
