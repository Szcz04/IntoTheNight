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

	PROJECT DIRECTION NOTES:
	- Items should map to stealth intents: blend, distract, sabotage, access.
	- TODO: add stealth-oriented categories/tags (e.g., Disguise, Distraction, Sabotage, Evidence).
	- TODO: retire horror-only labels/effects where they do not support social infiltration gameplay.
]]

local ItemDefinitions = {}

-- Item categories
ItemDefinitions.Categories = {
	TOOL = "Tool",
	CONSUMABLE = "Consumable",
	KEY_ITEM = "KeyItem",
	LIGHT = "Light"
}

-- Item types enum
ItemDefinitions.ItemTypes = {
	LOCKPICK = "Lockpick",
	BATTERY = "Battery",
	KEY = "Key",
	FLASHLIGHT = "Flashlight",
	-- Food items (różne rodzaje jedzenia)
	APPLE = "Apple",
	BREAD = "Bread",
	CUPCAKE = "Cupcake",
	CHOCOLATE = "Chocolate",
	JUICE = "Juice"
}

-- Item definitions
ItemDefinitions.Items = {
	[ItemDefinitions.ItemTypes.LOCKPICK] = {
		Id = "Lockpick",
		Name = "Lockpick",
		Category = ItemDefinitions.Categories.TOOL,
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
		Category = ItemDefinitions.Categories.TOOL,
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
		Category = ItemDefinitions.Categories.KEY_ITEM,
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
		Category = ItemDefinitions.Categories.LIGHT,
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
	
	-- FOOD ITEMS - różne rodzaje jedzenia o różnych rozmiarach i efektywnościach
	
	[ItemDefinitions.ItemTypes.APPLE] = {
		Id = "Apple",
		Name = "Apple",
		Category = ItemDefinitions.Categories.CONSUMABLE,
		Width = 1,
		Height = 1,
		Color = Color3.fromRGB(200, 50, 50), -- Red
		Description = "Reduces suspicion by 20. Small but fresh.",
		MaxStack = 1,
		WorldModel = "AppleModel",
		IsEquippable = false,
		IsConsumable = true,
		HealAmount = 20 -- Redukuje 20 punktow podejrzenia
	},
	
	[ItemDefinitions.ItemTypes.BREAD] = {
		Id = "Bread",
		Name = "Bread",
		Category = ItemDefinitions.Categories.CONSUMABLE,
		Width = 2,
		Height = 1,
		Color = Color3.fromRGB(210, 180, 140), -- Tan
		Description = "Reduces suspicion by 35. Filling staple food.",
		MaxStack = 1,
		WorldModel = "BreadModel",
		IsEquippable = false,
		IsConsumable = true,
		HealAmount = 35 -- Redukuje 35 punktow podejrzenia
	},
	
	[ItemDefinitions.ItemTypes.CUPCAKE] = {
		Id = "Cupcake",
		Name = "Cupcake",
		Category = ItemDefinitions.Categories.CONSUMABLE,
		Width = 2,
		Height = 2,
		Color = Color3.fromRGB(150, 150, 150), -- Gray
		Description = "Reduces suspicion by 60. Preserved nutrition.",
		MaxStack = 1,
		WorldModel = "CupcakeModel",
		IsEquippable = false,
		IsConsumable = true,
		HealAmount = 60 -- Redukuje 60 punktow podejrzenia
	},
	
	[ItemDefinitions.ItemTypes.CHOCOLATE] = {
		Id = "Chocolate",
		Name = "Chocolate Bar",
		Category = ItemDefinitions.Categories.CONSUMABLE,
		Width = 1,
		Height = 1,
		Color = Color3.fromRGB(101, 67, 33), -- Brown
		Description = "Reduces suspicion by 15. Sweet comfort.",
		MaxStack = 1,
		WorldModel = "ChocolateModel",
		IsEquippable = false,
		IsConsumable = true,
		HealAmount = 15 -- Redukuje 15 punktow podejrzenia
	},
	
	[ItemDefinitions.ItemTypes.JUICE] = {
		Id = "Juice",
		Name = "Juice",
		Category = ItemDefinitions.Categories.CONSUMABLE,
		Width = 1,
		Height = 2,
		Color = Color3.fromRGB(100, 150, 255), -- Light blue
		Description = "Reduces suspicion by 25. Refreshing hydration.",
		MaxStack = 1,
		WorldModel = "JuiceModel",
		IsEquippable = false,
		IsConsumable = true,
		HealAmount = 25 -- Redukuje 25 punktow podejrzenia
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

-- Get items by category (np. wszystkie jedzenia)
function ItemDefinitions.GetItemsByCategory(category)
	local items = {}
	for id, itemDef in pairs(ItemDefinitions.Items) do
		if itemDef.Category == category then
			table.insert(items, itemDef)
		end
	end
	return items
end

-- Check if item is consumable (jedzenie)
function ItemDefinitions.IsConsumable(itemId)
	local itemDef = ItemDefinitions.Items[itemId]
	return itemDef and itemDef.IsConsumable == true
end

-- Get heal amount for consumable item
function ItemDefinitions.GetHealAmount(itemId)
	local itemDef = ItemDefinitions.Items[itemId]
	if itemDef and itemDef.HealAmount then
		return itemDef.HealAmount
	end
	return 0
end

-- Check if item belongs to a specific category
function ItemDefinitions.IsInCategory(itemId, category)
	local itemDef = ItemDefinitions.Items[itemId]
	return itemDef and itemDef.Category == category
end

return ItemDefinitions
