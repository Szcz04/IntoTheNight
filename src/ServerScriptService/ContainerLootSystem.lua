--SPAWNS ALL CONTAINERS ACCORDING TO PRECONFIGURED POINTS AND LOOT ACCORDING TO CHANCE
--TRACKS CONTAINERS AND THEIR LOOTS
--Can Also be used to spawn loot in the world without containers (e.g. dropped items, loot piles, etc.)
--Loot with no containers preconfigured points are called LootSpawns and are tracked separately from containers
--ContainerLootSystem is responsible for spawning containers and loot, and tracking them in the world.

-- PROJECT DIRECTION NOTES:
-- - Use this system for handcrafted house stash points and sabotage-resource pacing.
-- - TODO: implement runtime spawn/open flow (currently stubbed) before design tuning.
-- - TODO: bias loot tables toward social stealth tools (distraction items, disguise props, sabotage tools).
-- - TODO: integrate pickup/open actions with SuspicionSystem when done in view of NPC/host.


local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LootDefinitions = require(ReplicatedStorage.SharedModules.ContainerLootDefinitions)
local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)




local ContainerLootSystem = {}
ContainerLootSystem.__index = ContainerLootSystem

return ContainerLootSystem
