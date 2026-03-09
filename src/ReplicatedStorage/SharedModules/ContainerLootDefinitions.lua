local LootDefinitions = {}
	
-- PROJECT DIRECTION NOTES:
-- - Tune loot toward social stealth loop: blend in, explore, sabotage, avoid suspicion.
-- - TODO: replace horror-survival biased drops with deception/sabotage oriented item pools.
	
	-- Loot tables z prawdopodobieństwami
	LootDefinitions.Tables = {
		Common = {
			{itemId = "Battery", weight = 30},      -- 30% szansy
			{itemId = "Flashlight", weight = 15},   -- 15% szansy
			{itemId = "Lockpick", weight = 25},     -- 25% szansy
			{itemId = nil, weight = 10}             -- 10% szansy na PUSTY
		},
		
		Rare = {
			{itemId = "Key", weight = 40},
			{itemId = "Flashlight", weight = 40},
			{itemId = nil, weight = 20}
		},
		
		Food = {
			{itemId = "Bread", weight = 40},
			{itemId = "Apple", weight = 40},
			{itemId = "Chocolate", weight = 20},
			{itemId = "Juice", weight = 20},
			{itemId = "Cupcake", weight = 20},
			{itemId = nil, weight = 10}
		},
		
		Tools = {
			{itemId = "Lockpick", weight = 40},
			{itemId = "Battery", weight = 30},
			{itemId = "Flashlight", weight = 20},
			{itemId = nil, weight = 10}
		}
	}
	
	-- Helper: Wybierz losowy item z tabeli
	function LootDefinitions.RollLoot(tableName)
		local table = LootDefinitions.Tables[tableName]
		if not table then return nil end
		
		-- Calculate total weight
		local totalWeight = 0
		for _, entry in ipairs(table) do
			totalWeight = totalWeight + entry.weight
		end
		
		-- Roll random number
		local roll = math.random() * totalWeight
		local currentWeight = 0
		
		-- Find which item was rolled
		for _, entry in ipairs(table) do
			currentWeight = currentWeight + entry.weight
			if roll <= currentWeight then
				return entry.itemId -- może być nil (empty)
			end
		end
		
		return nil
	end
	
	return LootDefinitions