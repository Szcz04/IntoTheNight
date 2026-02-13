--[[
	ItemDefinitions: Shared item configuration for inventory system
	
	Each item has:
		- Id: Unique identifier
		- Name: Display name
		- Width/Height: Grid size (in slots)
		- Color: Placeholder color for UI
		- Description: Tooltip text
		- MaxStack: Always 1 (no stacking)
		- WorldModel: Path to 3D model prefab for world drops
		- IsEquippable: Can be equipped in hand slot
]]

local ItemDefinitions = {}

-- Item types enum
ItemDefinitions.ItemTypes = {
	LOCKPICK = "Lockpick",
	BATTERY = "Battery",
	KEY = "Key",
	FLASHLIGHT = "Flashlight",
	MEDKIT = "Medkit"
}

-- Item definitions
ItemDefinitions.Items = {
	[ItemDefinitions.ItemTypes.LOCKPICK] = {
		Id = "Lockpick",
		Name = "Lockpick",
		Width = 1,
		Height = 1,
		Color = Color3.fromRGB(180, 180, 180), -- Gray
		Description = "Used to unlock locks",
		MaxStack = 1,
		WorldModel = "LockpickModel", -- Assume this is defined in ReplicatedStorage.ItemModels
		IsEquippable = false
	},
	
	[ItemDefinitions.ItemTypes.BATTERY] = {
		Id = "Battery",
		Name = "Battery",
		Width = 1,
		Height = 1,
		Color = Color3.fromRGB(255, 200, 50), -- Yellow
		Description = "Power source for flashlight",
		MaxStack = 1,
		WorldModel = "BatteryModel", -- Assume this is defined in ReplicatedStorage.ItemModels
		IsEquippable = false
	},
	
	[ItemDefinitions.ItemTypes.KEY] = {
		Id = "Key",
		Name = "Key",
		Width = 1,
		Height = 1,
		Color = Color3.fromRGB(255, 215, 0), -- Gold
		Description = "Opens doors",
		MaxStack = 1,
		WorldModel = "KeyModel", -- Assume this is defined in ReplicatedStorage.ItemModels
		IsEquippable = false
	},
	
	[ItemDefinitions.ItemTypes.FLASHLIGHT] = {
		Id = "Flashlight",
		Name = "Flashlight",
		Width = 3,
		Height = 1,
		Color = Color3.fromRGB(100, 100, 150), -- Blue-gray
		Description = "Illuminates dark areas",
		MaxStack = 1,
		WorldModel = "FlashlightModel", -- Assume this is defined in ReplicatedStorage.ItemModels
		IsEquippable = true,
		MaxCharge = 1.0, -- Full charge = 1.0
		DefaultCharge = 0.5 -- Starts with 50% charge
	},
	
	[ItemDefinitions.ItemTypes.MEDKIT] = {
		Id = "Medkit",
		Name = "Medkit",
		Width = 2,
		Height = 1,
		Color = Color3.fromRGB(200, 50, 50), -- Red
		Description = "Restores mental health",
		MaxStack = 1,
		WorldModel = "MedkitModel", -- Assume this is defined in ReplicatedStorage.ItemModels
		IsEquippable = false
	}
}

-- Helper function to get item definition
function ItemDefinitions.GetItem(itemId)
	return ItemDefinitions.Items[itemId]
end

-- Helper function to validate item exists
function ItemDefinitions.IsValidItem(itemId)
	return ItemDefinitions.Items[itemId] ~= nil
end

-- Get all item IDs
function ItemDefinitions.GetAllItemIds()
	local ids = {}
	for id, _ in pairs(ItemDefinitions.Items) do
		table.insert(ids, id)
	end
	return ids
end

-- Get default charge for an item (returns nil if item doesn't have charge)
function ItemDefinitions.GetDefaultCharge(itemId)
	local itemDef = ItemDefinitions.Items[itemId]
	if itemDef and itemDef.DefaultCharge then
		return itemDef.DefaultCharge
	end
	return nil
end

return ItemDefinitions
