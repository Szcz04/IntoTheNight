--[[
	InventoryUI: Client-side inventory interface
	
	Features:
		- 6x8 grid display with colored slot backgrounds
		- Slides in from right side on "I" key press
		- Shows items as colored frames
		- Drag & drop support (handled separately)
		- Blocks character movement when open
	
	UI Structure:
		ScreenGui
			└─ InventoryContainer (slides in/out)
				├─ GridContainer (6x8 slots)
				└─ ItemContainer (draggable items)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)

local InventoryUI = {}
InventoryUI.__index = InventoryUI

-- UI Configuration
local GRID_WIDTH = 6
local GRID_HEIGHT = 8
local SLOT_SIZE = 60 -- Pixels per slot
local SLOT_PADDING = 2 -- Gap between slots
local ANIMATION_TIME = 0.4 -- Slide animation duration

-- Colors
local COLOR_SLOT_EMPTY = Color3.fromRGB(30, 30, 35)
local COLOR_SLOT_BORDER = Color3.fromRGB(50, 50, 60)
local COLOR_BACKGROUND = Color3.fromRGB(20, 20, 25)

function InventoryUI.new()
	local self = setmetatable({}, InventoryUI)
	
	self._player = Players.LocalPlayer
	self._isOpen = false
	self._items = {} -- {itemIndex = frameInstance}
	
	-- Create UI first (doesn't need remotes)
	self:_CreateUI()
	
	-- Listen for input (works without remotes)
	self:_SetupInput()
	
	print("[InventoryUI] Inventory UI initialized (waiting for server...)")
	
	-- Wait for server communication in separate thread
	task.spawn(function()
		-- RemoteEvent/Function for server communication
		self._remoteEvent = ReplicatedStorage:WaitForChild("InventoryEvent", 10)
		self._remoteFunction = ReplicatedStorage:WaitForChild("InventoryFunction", 10)
		
		if not self._remoteEvent or not self._remoteFunction then
			warn("[InventoryUI] Failed to connect to server (InventoryEvent/InventoryFunction not found)")
			return
		end
		
		-- Listen for server updates
		self:_SetupServerListeners()
		
		-- Request initial inventory
		self:_RequestInventory()
		
		print("[InventoryUI] Connected to server")
	end)
	
	return self
end

-- Create UI structure
function InventoryUI:_CreateUI()
	-- Main ScreenGui
	self._screenGui = Instance.new("ScreenGui")
	self._screenGui.Name = "InventoryUI"
	self._screenGui.ResetOnSpawn = false
	self._screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._screenGui.Parent = self._player:WaitForChild("PlayerGui")
	
	-- Container (slides in/out from right)
	self._container = Instance.new("Frame")
	self._container.Name = "InventoryContainer"
	self._container.AnchorPoint = Vector2.new(1, 0.5)
	self._container.Position = UDim2.new(1.5, 0, 0.5, 0) -- Start off-screen (right)
	self._container.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH + 40, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT + 60)
	self._container.BackgroundColor3 = COLOR_BACKGROUND
	self._container.BorderSizePixel = 0
	self._container.Parent = self._screenGui
	
	-- Corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = self._container
	
	-- Title label
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0, 20, 0, 10)
	title.Size = UDim2.new(1, -40, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "EKWIPUNEK [I]"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.Parent = self._container
	
	-- Grid container
	self._gridContainer = Instance.new("Frame")
	self._gridContainer.Name = "GridContainer"
	self._gridContainer.Position = UDim2.new(0, 20, 0, 50)
	self._gridContainer.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT)
	self._gridContainer.BackgroundTransparency = 1
	self._gridContainer.Parent = self._container
	
	-- Create grid slots
	self:_CreateGrid()
	
	-- Item container (for draggable items, on top of grid)
	self._itemContainer = Instance.new("Frame")
	self._itemContainer.Name = "ItemContainer"
	self._itemContainer.Position = UDim2.new(0, 20, 0, 50)
	self._itemContainer.Size = UDim2.new(0, (SLOT_SIZE + SLOT_PADDING) * GRID_WIDTH, 0, (SLOT_SIZE + SLOT_PADDING) * GRID_HEIGHT)
	self._itemContainer.BackgroundTransparency = 1
	self._itemContainer.ZIndex = 2
	self._itemContainer.Parent = self._container
end

-- Create grid slots (background)
function InventoryUI:_CreateGrid()
	for y = 1, GRID_HEIGHT do
		for x = 1, GRID_WIDTH do
			local slot = Instance.new("Frame")
			slot.Name = string.format("Slot_%d_%d", x, y)
			slot.Position = UDim2.new(0, (x - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (y - 1) * (SLOT_SIZE + SLOT_PADDING))
			slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
			slot.BackgroundColor3 = COLOR_SLOT_EMPTY
			slot.BorderSizePixel = 1
			slot.BorderColor3 = COLOR_SLOT_BORDER
			slot.Parent = self._gridContainer
			
			-- Corner radius
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = slot
		end
	end
end

-- Setup input handling
function InventoryUI:_SetupInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.I then
			print("[InventoryUI] I key pressed")
			self:Toggle()
		end
	end)
	
	print("[InventoryUI] Input listener active (press I to toggle)")
end

-- Setup server event listeners
function InventoryUI:_SetupServerListeners()
	self._remoteEvent.OnClientEvent:Connect(function(action, ...)
		if action == "ItemAdded" then
			local item = ...
			self:_CreateItemFrame(item, #self._items + 1)
		elseif action == "ItemRemoved" then
			local itemIndex = ...
			self:_RemoveItemFrame(itemIndex)
		elseif action == "ItemMoved" then
			local itemIndex, item = ...
			self:_UpdateItemFrame(itemIndex, item)
		elseif action == "InventoryCleared" then
			self:_ClearAllItems()
		end
	end)
end

-- Request inventory from server
function InventoryUI:_RequestInventory()
	if not self._remoteFunction then
		warn("[InventoryUI] Cannot request inventory: no remote function")
		return
	end
	
	local success, items = pcall(function()
		return self._remoteFunction:InvokeServer("GetInventory")
	end)
	
	if success and items then
		for index, item in ipairs(items) do
			self:_CreateItemFrame(item, index)
		end
	else
		warn("[InventoryUI] Failed to request inventory:", items)
	end
end

-- Create item frame in UI
function InventoryUI:_CreateItemFrame(item, itemIndex)
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
	frame.Parent = self._itemContainer
	
	-- Corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	
	-- Item name label
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
	
	-- Store reference
	self._items[itemIndex] = frame
	
	print(string.format("[InventoryUI] Created item frame: %s at (%d,%d)", itemDef.Name, item.x, item.y))
end

-- Remove item frame
function InventoryUI:_RemoveItemFrame(itemIndex)
	local frame = self._items[itemIndex]
	if frame then
		frame:Destroy()
		self._items[itemIndex] = nil
		print(string.format("[InventoryUI] Removed item frame: %d", itemIndex))
	end
end

-- Update item frame position
function InventoryUI:_UpdateItemFrame(itemIndex, item)
	local frame = self._items[itemIndex]
	if not frame then return end
	
	-- Update position and size
	frame.Position = UDim2.new(0, (item.x - 1) * (SLOT_SIZE + SLOT_PADDING), 0, (item.y - 1) * (SLOT_SIZE + SLOT_PADDING))
	frame.Size = UDim2.new(0, item.width * SLOT_SIZE + (item.width - 1) * SLOT_PADDING, 0, item.height * SLOT_SIZE + (item.height - 1) * SLOT_PADDING)
	
	print(string.format("[InventoryUI] Updated item frame: %d to (%d,%d)", itemIndex, item.x, item.y))
end

-- Clear all items
function InventoryUI:_ClearAllItems()
	for _, frame in pairs(self._items) do
		frame:Destroy()
	end
	self._items = {}
	print("[InventoryUI] Cleared all items")
end

-- Toggle inventory open/closed
function InventoryUI:Toggle()
	if self._isOpen then
		self:Close()
	else
		self:Open()
	end
end

-- Open inventory
function InventoryUI:Open()
	if self._isOpen then return end
	self._isOpen = true
	
	-- Disable character movement
	local character = self._player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
		end
	end
	
	-- Slide in animation
	local tween = TweenService:Create(self._container, TweenInfo.new(ANIMATION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -20, 0.5, 0)
	})
	tween:Play()
	
	print("[InventoryUI] Opened inventory")
end

-- Close inventory
function InventoryUI:Close()
	if not self._isOpen then return end
	self._isOpen = false
	
	-- Re-enable character movement
	local character = self._player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16 -- Default walk speed
		end
	end
	
	-- Slide out animation
	local tween = TweenService:Create(self._container, TweenInfo.new(ANIMATION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(1.5, 0, 0.5, 0)
	})
	tween:Play()
	
	print("[InventoryUI] Closed inventory")
end

-- Check if inventory is open
function InventoryUI:IsOpen()
	return self._isOpen
end

return InventoryUI
