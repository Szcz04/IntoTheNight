--[[
	════════════════════════════════════════════════════════════════
	PLAN: ContainerLootSystem
	════════════════════════════════════════════════════════════════
	
	CEL:
	- Losowy loot w containerach (skrzynie, szafki, szuflady)
	- Różne prawdopodobieństwa dla różnych itemów
	- Spawny w oznaczonych miejscach w wagonach
	
	════════════════════════════════════════════════════════════════
	KROK 1: SETUP W WORKSPACE
	════════════════════════════════════════════════════════════════
	
	W Roblox Studio, w każdym wagonie:
	
	1. Stwórz invisible Part (Size = Vector3.new(2, 2, 2))
	2. Ustaw:
	   - Transparency = 1
	   - CanCollide = false
	   - Anchored = true
	   - Name = "ContainerSpawn"
	3. Dodaj TAG "ContainerSpawn" (przez CollectionService)
	4. Dodaj ATTRIBUTES:
	   - ContainerType (String): "Chest", "Locker", "Drawer", "Crate"
	   - LootTable (String): "Common", "Rare", "Medical", "Tools"
	
	PRZYKŁAD ROZMIESZCZENIA:
	- Wagon 1: 3x ContainerSpawn (Common loot)
	- Wagon 2: 2x ContainerSpawn (Medical loot)
	- Wagon 3: 4x ContainerSpawn (Tools + Rare)
	
	════════════════════════════════════════════════════════════════
	KROK 2: LOOT TABLES (w ReplicatedStorage/SharedModules)
	════════════════════════════════════════════════════════════════
	
	Stwórz ContainerLootDefinitions.lua:
	
	local LootDefinitions = {}
	
	-- Loot tables z prawdopodobieństwami
	LootDefinitions.Tables = {
		Common = {
			{itemId = "Battery", weight = 30},      -- 30% szansy
			{itemId = "Medkit", weight = 20},       -- 20% szansy
			{itemId = "Flashlight", weight = 15},   -- 15% szansy
			{itemId = "Lockpick", weight = 25},     -- 25% szansy
			{itemId = nil, weight = 10}             -- 10% szansy na PUSTY
		},
		
		Rare = {
			{itemId = "Key", weight = 40},
			{itemId = "Flashlight", weight = 40},
			{itemId = "Medkit", weight = 10},
			{itemId = nil, weight = 10}
		},
		
		Medical = {
			{itemId = "Medkit", weight = 70},
			{itemId = "Battery", weight = 20},
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
	
	════════════════════════════════════════════════════════════════
	KROK 3: CONTAINER MODELS (w ReplicatedStorage/ItemModels)
	════════════════════════════════════════════════════════════════
	
	Stwórz modele containerów (lub użyj prostych Partów):
	- ChestModel (Model z PrimaryPart)
	- LockerModel
	- DrawerModel
	- CrateModel
	
	Każdy model powinien mieć:
	- PrimaryPart (główna część do pozycjonowania)
	- ClickDetector (w jakiejś części) - do otwierania
	- Opcjonalnie: animowane drzwi/wieko
	
	════════════════════════════════════════════════════════════════
	KROK 4: CONTAINERLOOTS SISTEM (ServerScriptService)
	════════════════════════════════════════════════════════════════
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LootDefinitions = require(ReplicatedStorage.SharedModules.ContainerLootDefinitions)
local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)

local ContainerLootSystem = {}
ContainerLootSystem.__index = ContainerLootSystem

-- Container states
ContainerLootSystem.States = {
	CLOSED = "CLOSED",      -- Nie został otwarty
	OPEN = "OPEN",          -- Został otwarty (loot wziĘty)
	LOOTED = "LOOTED",      -- Deprecated (używaj OPEN)
}

function ContainerLootSystem.new(gameState)
	local self = setmetatable({}, ContainerLootSystem)
	
	self._gameState = gameState
	
	-- Tracking spawned containers
	-- {spawnId = {containerModel, state, lootContent, spawnPoint}}
	self._containers = {}
	
	-- Events
	self.ContainerOpened = Instance.new("BindableEvent")
	
	-- RemoteEvent for client interaction
	self._remoteEvent = self:_CreateRemoteEvent()
	
	-- Find all spawn points
	self:_DiscoverSpawnPoints()
	
	-- Listen for GameState changes
	if self._gameState then
		self._gameState.StateChanged.Event:Connect(function(newState, oldState)
			self:_OnGameStateChanged(newState, oldState)
		end)
	end
	
	print("[ContainerLootSystem] System initialized")
	
	return self
end

function ContainerLootSystem:_CreateRemoteEvent()
	local remoteEvent = ReplicatedStorage:FindFirstChild("ContainerEvent")
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = "ContainerEvent"
		remoteEvent.Parent = ReplicatedStorage
	end
	
	remoteEvent.OnServerEvent:Connect(function(player, action, containerId)
		if action == "OpenContainer" then
			self:OpenContainer(player, containerId)
		end
	end)
	
	return remoteEvent
end

-- Find all ContainerSpawn points in workspace
function ContainerLootSystem:_DiscoverSpawnPoints()
	local spawnPoints = CollectionService:GetTagged("ContainerSpawn")
	
	print(string.format("[ContainerLootSystem] Found %d spawn points", #spawnPoints))
	
	-- Store spawn points (nie spawnuj containerów jeszcze!)
	for _, spawnPoint in ipairs(spawnPoints) do
		local spawnId = spawnPoint:GetAttribute("SpawnId") or HttpService:GenerateGUID(false)
		spawnPoint:SetAttribute("SpawnId", spawnId)
		
		local containerType = spawnPoint:GetAttribute("ContainerType") or "Chest"
		local lootTable = spawnPoint:GetAttribute("LootTable") or "Common"
		
		self._containers[spawnId] = {
			spawnPoint = spawnPoint,
			containerType = containerType,
			lootTable = lootTable,
			state = ContainerLootSystem.States.CLOSED,
			containerModel = nil,
			lootContent = nil
		}
		
		print(string.format("[ContainerLootSystem] Registered spawn: %s (%s, %s)", 
			spawnId, containerType, lootTable))
	end
end

-- Spawn all containers (call when round starts)
function ContainerLootSystem:SpawnAllContainers()
	for spawnId, data in pairs(self._containers) do
		self:_SpawnContainer(spawnId)
	end
	
	print("[ContainerLootSystem] All containers spawned")
end

-- Spawn single container at spawn point
function ContainerLootSystem:_SpawnContainer(spawnId)
	local data = self._containers[spawnId]
	if not data then return end
	
	local spawnPoint = data.spawnPoint
	local containerType = data.containerType
	
	-- Get container model from ReplicatedStorage
	local ItemModels = ReplicatedStorage:FindFirstChild("ItemModels")
	if not ItemModels then
		warn("[ContainerLootSystem] ItemModels folder not found!")
		return
	end
	
	local modelName = containerType .. "Model"
	local prefab = ItemModels:FindFirstChild(modelName)
	
	if not prefab then
		-- Fallback: use simple Part
		warn(string.format("[ContainerLootSystem] Model '%s' not found, using fallback", modelName))
		prefab = Instance.new("Part")
		prefab.Name = containerType
		prefab.Size = Vector3.new(2, 2, 2)
		prefab.Color = Color3.fromRGB(139, 69, 19) -- Brown
		prefab.Anchored = true
		
		-- Add ClickDetector
		local clickDetector = Instance.new("ClickDetector")
		clickDetector.Parent = prefab
	end
	
	-- Clone and position
	local containerModel = prefab:Clone()
	
	if containerModel:IsA("Model") then
		containerModel:SetPrimaryPartCFrame(spawnPoint.CFrame)
	else
		containerModel.CFrame = spawnPoint.CFrame
	end
	
	-- Set attributes for identification
	containerModel:SetAttribute("ContainerId", spawnId)
	
	-- Setup ClickDetector interaction
	local clickDetector = containerModel:FindFirstChildOfClass("ClickDetector", true)
	if clickDetector then
		clickDetector.MouseClick:Connect(function(player)
			self:OpenContainer(player, spawnId)
		end)
	else
		warn(string.format("[ContainerLootSystem] No ClickDetector in %s", containerType))
	end
	
	containerModel.Parent = workspace
	
	-- Roll loot content
	local lootTable = data.lootTable
	local rolledItem = LootDefinitions.RollLoot(lootTable)
	
	data.containerModel = containerModel
	data.lootContent = rolledItem
	data.state = ContainerLootSystem.States.CLOSED
	
	print(string.format("[ContainerLootSystem] Spawned %s at %s (Loot: %s)", 
		containerType, spawnId, tostring(rolledItem or "EMPTY")))
end

-- Player opens container
function ContainerLootSystem:OpenContainer(player, containerId)
	local data = self._containers[containerId]
	if not data then
		warn(string.format("[ContainerLootSystem] Container %s not found", tostring(containerId)))
		return
	end
	
	-- Check if already opened
	if data.state == ContainerLootSystem.States.OPEN then
		print(string.format("[ContainerLootSystem] %s already looted by %s", containerId, player.Name))
		self._remoteEvent:FireClient(player, "ContainerEmpty", containerId)
		return
	end
	
	-- Mark as opened
	data.state = ContainerLootSystem.States.OPEN
	
	-- Get loot
	local lootItem = data.lootContent
	
	if not lootItem then
		-- Empty container
		print(string.format("[ContainerLootSystem] %s opened EMPTY container %s", player.Name, containerId))
		self._remoteEvent:FireClient(player, "ContainerEmpty", containerId)
		return
	end
	
	-- Spawn loot item in world (near container)
	local containerModel = data.containerModel
	local spawnPos = containerModel:GetPrimaryPartCFrame() or containerModel.CFrame
	local dropPosition = spawnPos * CFrame.new(0, 2, 0) -- Spawn above container
	
	self:_SpawnLootItem(lootItem, dropPosition)
	
	-- Notify player
	print(string.format("[ContainerLootSystem] %s opened container %s (Loot: %s)", 
		player.Name, containerId, lootItem))
	
	self._remoteEvent:FireClient(player, "ContainerOpened", containerId, lootItem)
	
	-- Fire event (other systems can listen)
	self.ContainerOpened:Fire(player, containerId, lootItem)
	
	-- Optional: Change container appearance (open lid, etc.)
	self:_VisualizeOpen(containerModel)
end

-- Spawn loot item in world (integrate with InventoryManager)
function ContainerLootSystem:_SpawnLootItem(itemId, cframe)
	local ItemDefinitions = require(ReplicatedStorage.SharedModules.ItemDefinitions)
	local itemDef = ItemDefinitions.GetItem(itemId)
	if not itemDef then return end
	
	-- Use same logic as InventoryManager:_SpawnWorldItem
	local ItemModels = ReplicatedStorage:FindFirstChild("ItemModels")
	local prefab = ItemModels and ItemModels:FindFirstChild(itemDef.WorldModel)
	
	local worldItem
	
	if prefab then
		worldItem = prefab:Clone()
		if worldItem:IsA("Model") then
			worldItem:SetPrimaryPartCFrame(cframe)
		else
			worldItem.CFrame = cframe
		end
	else
		-- Fallback
		worldItem = Instance.new("Part")
		worldItem.Name = itemDef.Name
		worldItem.Size = Vector3.new(1, 1, 1)
		worldItem.Color = itemDef.Color
		worldItem.CFrame = cframe
	end
	
	-- Setup for pickup
	local itemUUID = HttpService:GenerateGUID(false)
	
	if worldItem:IsA("Model") then
		CollectionService:AddTag(worldItem, "ItemPickup")
		worldItem:SetAttribute("ItemId", itemId)
		worldItem:SetAttribute("ItemUUID", itemUUID)
		
		for _, part in worldItem:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = true
			end
		end
	else
		worldItem.Anchored = false
		worldItem.CanCollide = true
		CollectionService:AddTag(worldItem, "ItemPickup")
		worldItem:SetAttribute("ItemId", itemId)
		worldItem:SetAttribute("ItemUUID", itemUUID)
	end
	
	worldItem.Parent = workspace
	
	print(string.format("[ContainerLootSystem] Spawned loot item: %s (UUID: %s)", itemId, itemUUID))
end

-- Change container appearance when opened
function ContainerLootSystem:_VisualizeOpen(containerModel)
	-- Simple: change color to indicate opened
	if containerModel:IsA("BasePart") then
		containerModel.Color = Color3.fromRGB(100, 100, 100) -- Gray
	elseif containerModel:IsA("Model") and containerModel.PrimaryPart then
		containerModel.PrimaryPart.Color = Color3.fromRGB(100, 100, 100)
	end
	
	-- TODO: Add animations (open lid, slide drawer, etc.)
end

-- React to GameState changes
function ContainerLootSystem:_OnGameStateChanged(newState, oldState)
	-- Reset containers when new round starts
	if newState == self._gameState.States.RUNNING then
		self:Reset()
		self:SpawnAllContainers()
	end
end

-- Reset all containers (for new round)
function ContainerLootSystem:Reset()
	-- Destroy all spawned containers
	for spawnId, data in pairs(self._containers) do
		if data.containerModel then
			data.containerModel:Destroy()
			data.containerModel = nil
		end
		
		data.state = ContainerLootSystem.States.CLOSED
		data.lootContent = nil
	end
	
	print("[ContainerLootSystem] All containers reset")
end

return ContainerLootSystem

--[[
	════════════════════════════════════════════════════════════════
	KROK 5: INTEGRACJA W MAINSERVER
	════════════════════════════════════════════════════════════════
	
	W MainServer.server.lua, dodaj:
	
	local ContainerLootSystem = require(ServerScriptService.ContainerLootSystem)
	
	-- W sekcji Initialize systems:
	local containerLootSystem = ContainerLootSystem.new(gameState)
	
	-- Expose globally for testing:
	_G.ContainerLootSystem = containerLootSystem
	
	════════════════════════════════════════════════════════════════
	KROK 6: CLIENT-SIDE (StarterPlayerScripts)
	════════════════════════════════════════════════════════════════
	
	Opcjonalnie: Stwórz ContainerUI.client.lua dla:
	- Pokazywania "Press E to open" gdy patrzysz na container
	- Animacji otwierania
	- Powiadomienia "Found: Flashlight!"
	
	Możesz użyć podobnej logiki jak w ItemPickup.client.lua
	
	════════════════════════════════════════════════════════════════
	TESTOWANIE
	════════════════════════════════════════════════════════════════
	
	1. W Studio, stwórz kilka ContainerSpawn Parts
	2. Dodaj tag "ContainerSpawn"
	3. Ustaw attributes (ContainerType, LootTable)
	4. Uruchom serwer
	5. W konsoli:
	   _G.GameState:SetState(_G.GameStateModule.States.RUNNING)
	6. Kliknij na container
	7. Sprawdź czy item się spawnuje
]]
