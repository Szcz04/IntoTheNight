--[[
	SZABLON NOWEGO SYSTEMU
	
	Użyj tego jako bazę do tworzenia nowych modułów.
	
	KROK 1: Nazwa i odpowiedzialność
	- Nazwij moduł jasno (ContainerSystem, DoorSystem, MonsterAI, etc.)
	- Zdefiniuj JEDNĄ główną odpowiedzialność (Single Responsibility Principle)
	- Opisz co system ROBI i czego NIE ROBI
	
	KROK 2: Dependencies
	- Jakie inne moduły potrzebujesz? (PowerManager, GameState, etc.)
	- Czy potrzebujesz RemoteEvent/RemoteFunction do komunikacji client-server?
	
	KROK 3: State
	- Jakie dane musisz przechowywać?
	- Per-player? Global? Per-object?
	
	KROK 4: Events
	- Jakie eventy będziesz wystawiać dla innych systemów?
	- Na jakie eventy będziesz nasłuchiwać?
]]

-- Services (zawsze na górze)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Dependencies (inne moduły)
-- local GameState = require(script.Parent.GameState)
-- local PowerManager = require(script.Parent.PowerManager)

-- Module table (OOP przez metatables)
local NewSystem = {}
NewSystem.__index = NewSystem

--[[
	ENUMS / CONSTANTS
	
	Definiuj stałe i enumy NA POCZĄTKU.
	To ułatwia modyfikację wartości później.
]]
NewSystem.States = {
	IDLE = "IDLE",
	ACTIVE = "ACTIVE",
	DISABLED = "DISABLED"
}

-- Konfiguracja (łatwo edytowalne wartości)
local CONFIG = {
	COOLDOWN_TIME = 10,
	MAX_DISTANCE = 20,
	SPAWN_RATE = 0.5
}

--[[
	KONSTRUKTOR (.new)
	
	1. Przyjmij dependencies jako parametry (dependency injection)
	2. Stwórz self z setmetatable
	3. Zainicjalizuj state (zmienne prywatne z prefixem _)
	4. Stwórz eventy (BindableEvent dla komunikacji)
	5. Setup listeners (CollectionService, Players, inne systemy)
	6. Zwróć self
]]
function NewSystem.new(gameState, powerManager)
	local self = setmetatable({}, NewSystem)
	
	-- Store dependencies (ZAWSZE jako _private)
	self._gameState = gameState
	self._powerManager = powerManager
	
	-- Initialize state
	self._currentState = NewSystem.States.IDLE
	self._objects = {} -- Tracked objects: {objectId = {data}}
	self._playerData = {} -- Per-player data: {userId = {data}}
	
	-- Create events (dla komunikacji z innymi systemami)
	self.StateChanged = Instance.new("BindableEvent")
	self.ObjectActivated = Instance.new("BindableEvent")
	
	-- Setup RemoteEvents (jeśli potrzebujesz client-server communication)
	self._remoteEvent = self:_CreateRemoteEvent()
	-- self._remoteFunction = self:_CreateRemoteFunction()
	
	-- Setup listeners
	self:_SetupPlayerListeners()
	self:_SetupCollectionServiceListeners()
	self:_SetupDependencyListeners()
	
	-- Discovery (znajdź istniejące obiekty w workspace)
	self:_DiscoverObjects()
	
	print("[NewSystem] System initialized")
	
	return self
end

--[[
	PRIVATE METHODS (prefix _)
	
	Używaj _ dla metod które są tylko wewnętrzne.
	To pokazuje innym programistom "nie wywołuj tego z zewnątrz".
]]

-- Setup player join/leave listeners
function NewSystem:_SetupPlayerListeners()
	Players.PlayerAdded:Connect(function(player)
		self:_OnPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_OnPlayerRemoving(player)
	end)
	
	-- Initialize for existing players
	for _, player in Players:GetPlayers() do
		self:_OnPlayerAdded(player)
	end
end

-- Setup CollectionService tags (dla dynamicznych obiektów)
function NewSystem:_SetupCollectionServiceListeners()
	-- Przykład: nasłuchuj na obiekty z tagiem "MyTag"
	CollectionService:GetInstanceAddedSignal("MyTag"):Connect(function(instance)
		self:_RegisterObject(instance)
	end)
	
	CollectionService:GetInstanceRemovedSignal("MyTag"):Connect(function(instance)
		self:_UnregisterObject(instance)
	end)
end

-- Setup listeners dla innych systemów
function NewSystem:_SetupDependencyListeners()
	-- Przykład: reaguj na zmiany GameState
	if self._gameState then
		self._gameState.StateChanged.Event:Connect(function(newState, oldState)
			self:_OnGameStateChanged(newState, oldState)
		end)
	end
	
	-- Przykład: reaguj na zmiany PowerManager
	if self._powerManager then
		self._powerManager.PowerStateChanged.Event:Connect(function(newState, oldState)
			self:_OnPowerStateChanged(newState, oldState)
		end)
	end
end

-- Discover existing objects in workspace (CollectionService)
function NewSystem:_DiscoverObjects()
	local tagged = CollectionService:GetTagged("MyTag")
	
	for _, instance in ipairs(tagged) do
		self:_RegisterObject(instance)
	end
	
	print(string.format("[NewSystem] Discovered %d objects", #tagged))
end

-- Player joined
function NewSystem:_OnPlayerAdded(player)
	self._playerData[player.UserId] = {
		player = player,
		-- inne dane
	}
	
	-- Wait for character
	local character = player.Character or player.CharacterAdded:Wait()
	self:_OnCharacterAdded(player, character)
	
	-- Listen for respawns
	player.CharacterAdded:Connect(function(newCharacter)
		self:_OnCharacterAdded(player, newCharacter)
	end)
	
	print(string.format("[NewSystem] Player added: %s", player.Name))
end

-- Player left (CRITICAL: zawsze czyść dane!)
function NewSystem:_OnPlayerRemoving(player)
	self._playerData[player.UserId] = nil
	
	print(string.format("[NewSystem] Player removed: %s", player.Name))
end

-- Character spawned/respawned
function NewSystem:_OnCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	
	-- Update player data with new character references
	local data = self._playerData[player.UserId]
	if data then
		data.character = character
		data.humanoid = humanoid
		data.rootPart = rootPart
	end
end

-- Register object (z CollectionService)
function NewSystem:_RegisterObject(instance)
	-- Walidacja
	if not instance:IsA("BasePart") and not instance:IsA("Model") then
		warn(string.format("[NewSystem] Invalid object type: %s", instance.ClassName))
		return
	end
	
	-- Pobierz ID lub stwórz nowe
	local objectId = instance:GetAttribute("ObjectId") or instance:GetFullName()
	
	-- Store object data
	self._objects[objectId] = {
		instance = instance,
		state = "ready",
		-- inne dane
	}
	
	print(string.format("[NewSystem] Registered object: %s", instance.Name))
end

-- Unregister object
function NewSystem:_UnregisterObject(instance)
	local objectId = instance:GetAttribute("ObjectId") or instance:GetFullName()
	self._objects[objectId] = nil
	
	print(string.format("[NewSystem] Unregistered object: %s", instance.Name))
end

-- Create RemoteEvent for client-server communication
function NewSystem:_CreateRemoteEvent()
	local remoteEvent = ReplicatedStorage:FindFirstChild("NewSystemEvent")
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = "NewSystemEvent"
		remoteEvent.Parent = ReplicatedStorage
	end
	
	-- Handle client messages
	remoteEvent.OnServerEvent:Connect(function(player, action, ...)
		self:_HandleClientMessage(player, action, ...)
	end)
	
	return remoteEvent
end

-- Create RemoteFunction for client requests (z return value)
function NewSystem:_CreateRemoteFunction()
	local remoteFunction = ReplicatedStorage:FindFirstChild("NewSystemFunction")
	if not remoteFunction then
		remoteFunction = Instance.new("RemoteFunction")
		remoteFunction.Name = "NewSystemFunction"
		remoteFunction.Parent = ReplicatedStorage
	end
	
	-- Handle client requests
	remoteFunction.OnServerInvoke = function(player, action, ...)
		return self:_HandleClientRequest(player, action, ...)
	end
	
	return remoteFunction
end

-- Handle client messages (RemoteEvent)
function NewSystem:_HandleClientMessage(player, action, ...)
	if action == "Activate" then
		local objectId = ...
		self:ActivateObject(player, objectId)
		
	elseif action == "Deactivate" then
		local objectId = ...
		self:DeactivateObject(player, objectId)
		
	else
		warn(string.format("[NewSystem] Unknown action: %s", tostring(action)))
	end
end

-- Handle client requests (RemoteFunction - musi zwrócić wartość!)
function NewSystem:_HandleClientRequest(player, action, ...)
	if action == "GetObjectState" then
		local objectId = ...
		return self:GetObjectState(objectId)
		
	elseif action == "CanActivate" then
		local objectId = ...
		return self:CanActivate(player, objectId)
		
	else
		warn(string.format("[NewSystem] Unknown request: %s", tostring(action)))
		return nil
	end
end

-- React to GameState changes
function NewSystem:_OnGameStateChanged(newState, oldState)
	print(string.format("[NewSystem] GameState changed: %s → %s", oldState, newState))
	
	-- Przykład: reset when round ends
	if newState == self._gameState.States.ENDING then
		self:Reset()
	end
end

-- React to PowerManager changes
function NewSystem:_OnPowerStateChanged(newState, oldState)
	print(string.format("[NewSystem] PowerState changed: %s → %s", oldState, newState))
	
	-- Przykład: disable when power is off
	if newState == self._powerManager.PowerStates.OFF then
		self:SetState(NewSystem.States.DISABLED)
	else
		self:SetState(NewSystem.States.IDLE)
	end
end

--[[
	PUBLIC API
	
	Metody bez _ są "public" - inne systemy mogą je wywoływać.
	Dokumentuj co każda metoda robi i co zwraca.
]]

-- Set system state
function NewSystem:SetState(newState)
	if self._currentState == newState then
		return
	end
	
	local oldState = self._currentState
	self._currentState = newState
	
	-- Fire event (inne systemy mogą nasłuchiwać)
	self.StateChanged:Fire(newState, oldState)
	
	print(string.format("[NewSystem] State: %s → %s", oldState, newState))
end

-- Get current state
function NewSystem:GetState()
	return self._currentState
end

-- Activate object
function NewSystem:ActivateObject(player, objectId)
	local objectData = self._objects[objectId]
	if not objectData then
		warn(string.format("[NewSystem] Object %s not found", tostring(objectId)))
		return false
	end
	
	-- Validation
	if objectData.state ~= "ready" then
		print(string.format("[NewSystem] Object %s not ready", objectId))
		return false
	end
	
	-- Do something
	objectData.state = "active"
	
	-- Fire event
	self.ObjectActivated:Fire(player, objectId)
	
	print(string.format("[NewSystem] %s activated object %s", player.Name, objectId))
	return true
end

-- Deactivate object
function NewSystem:DeactivateObject(player, objectId)
	local objectData = self._objects[objectId]
	if not objectData then
		return false
	end
	
	objectData.state = "ready"
	
	print(string.format("[NewSystem] %s deactivated object %s", player.Name, objectId))
	return true
end

-- Get object state
function NewSystem:GetObjectState(objectId)
	local objectData = self._objects[objectId]
	return objectData and objectData.state or nil
end

-- Check if player can activate
function NewSystem:CanActivate(player, objectId)
	local objectData = self._objects[objectId]
	if not objectData then
		return false
	end
	
	-- Add your validation logic here
	return objectData.state == "ready"
end

-- Reset system (for new rounds)
function NewSystem:Reset()
	for objectId, objectData in pairs(self._objects) do
		objectData.state = "ready"
	end
	
	self:SetState(NewSystem.States.IDLE)
	
	print("[NewSystem] System reset")
end

-- Cleanup (jeśli kiedyś będziesz musiał wyłączyć system)
function NewSystem:Cleanup()
	self._objects = {}
	self._playerData = {}
	
	print("[NewSystem] Cleaned up")
end

return NewSystem
