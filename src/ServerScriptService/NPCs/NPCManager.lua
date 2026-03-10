local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local InterestPointService = require(script.Parent.InterestPointService)
local AvatarPool = require(script.Parent.AvatarPool)
local NPCNamePool = require(script.Parent.NPCNamePool)
local NPCIntelligenceTiers = require(script.Parent.NPCIntelligenceTiers)
local NPCController = require(script.Parent.NPCController)

local NPCManager = {}
NPCManager.__index = NPCManager

local DEFAULT_RIG_TYPE = Enum.HumanoidRigType.R15
local NPC_COLLISION_GROUP = "NPC"
local SPAWN_POINT_TAG = "NPCSpawnPoint"

function NPCManager.new(gameState, hostCommandSystem)
	local self = setmetatable({}, NPCManager)

	self._gameState = gameState
	self._hostCommandSystem = hostCommandSystem

	self._controllers = {}
	self._npcFolder = Workspace:FindFirstChild("NPCGuests")
	if not self._npcFolder then
		self._npcFolder = Instance.new("Folder")
		self._npcFolder.Name = "NPCGuests"
		self._npcFolder.Parent = Workspace
	end

	self._interestPointService = InterestPointService.new()
	self._avatarPool = AvatarPool.new()
	self._namePool = NPCNamePool.new()

	self._desiredNpcCount = 8
	self._nextNpcId = 1
	self._isRunning = false
	self._spawnPoints = {}
	self._spawnAssignments = {}
	self._tierWeights = {
		primitive = 0.5,
		standard = 0.35,
		advanced = 0.15
	}
	self._forcedTier = nil

	self:_DiscoverSpawnPoints()
	self:_BindSpawnPointSignals()
	self:_BindGameState()

	print("[NPCManager] Initialized")
	return self
end

function NPCManager:_BindGameState()
	if not self._gameState or not self._gameState.StateChanged then
		return
	end

	self._gameState.StateChanged.Event:Connect(function(newState)
		if newState == "RUNNING" then
			self:Start()
		elseif newState == "ENDING" or newState == "WAITING" then
			self:Stop()
		end
	end)
end

function NPCManager:Start()
	if self._isRunning then
		return
	end

	self._isRunning = true
	self._avatarPool:BuildFromCurrentPlayers()
	self:_EnsureNpcCount()
	print("[NPCManager] Started")
end

function NPCManager:Stop()
	if not self._isRunning then
		return
	end

	self._isRunning = false
	self._spawnAssignments = {}
	for id, controller in pairs(self._controllers) do
		controller:Stop()
		self._controllers[id] = nil
		self._spawnAssignments[id] = nil
	end

	for _, npc in ipairs(self._npcFolder:GetChildren()) do
		npc:Destroy()
	end

	print("[NPCManager] Stopped")
end

function NPCManager:_EnsureNpcCount()
	while self._isRunning and self:_GetNpcCount() < self._desiredNpcCount do
		self:_SpawnNpc()
	end

	self:_TrimNpcCount()
end

function NPCManager:_TrimNpcCount()
	if not self._isRunning then
		return
	end

	local ids = {}
	for id in pairs(self._controllers) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return a > b
	end)

	local overBy = #ids - self._desiredNpcCount
	for i = 1, math.max(overBy, 0) do
		local id = ids[i]
		local controller = self._controllers[id]
		if controller then
			controller:Stop()
			self._controllers[id] = nil
			self._spawnAssignments[id] = nil
		end

		local model = self._npcFolder:FindFirstChild(string.format("Guest_%02d", id))
		if model then
			model:Destroy()
		end
	end
end

function NPCManager:_GetNpcCount()
	local count = 0
	for _ in pairs(self._controllers) do
		count = count + 1
	end
	return count
end

function NPCManager:_SpawnNpc()
	local npcId = self._nextNpcId
	self._nextNpcId = self._nextNpcId + 1
	local initialTier = self:_ChooseTierForNpc()
	local spawnPoint = self:_ChooseSpawnPointForTier(initialTier)
	local intelligenceTier = self:_ResolveTierForSpawnPoint(initialTier, spawnPoint)
	local leashRadius = self:_ResolveLeashRadiusForSpawnPoint(spawnPoint, intelligenceTier)
	local spawnCFrame = self:_GetRandomSpawnCFrame(spawnPoint)
	local spawnAnchorPosition = spawnPoint and spawnPoint.Position or spawnCFrame.Position

	local description = self._avatarPool:GetNextDescription()

	local model = self:_CreateNpcModel(npcId, description, spawnCFrame)
	if not model then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		model:Destroy()
		return
	end

	local displayName = self._namePool:GetNextName(npcId)
	humanoid.DisplayName = displayName
	model:SetAttribute("NPCDisplayName", displayName)
	model:SetAttribute("NPCIntelligenceTier", intelligenceTier)
	if spawnPoint then
		model:SetAttribute("NPCSpawnPoint", spawnPoint.Name)
	end

	humanoid.WalkSpeed = 6
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local controller = NPCController.new({
		id = npcId,
		model = model,
		humanoid = humanoid,
		root = root,
		intelligenceTier = intelligenceTier,
		spawnAnchorPosition = spawnAnchorPosition,
		spawnPointName = spawnPoint and spawnPoint.Name or "NPCSpawn",
		leashRadius = leashRadius,
		interestPointService = self._interestPointService,
		hostCommandSystem = self._hostCommandSystem
	})

	self._controllers[npcId] = controller
	self._spawnAssignments[npcId] = spawnPoint and spawnPoint.Name or "NPCSpawn"
	controller:Start()
end

function NPCManager:_ChooseTierForNpc()
	if self._forcedTier then
		return self._forcedTier
	end

	local roll = math.random()
	if roll <= self._tierWeights.primitive then
		return NPCIntelligenceTiers.Tiers.Primitive
	end

	if roll <= self._tierWeights.primitive + self._tierWeights.standard then
		return NPCIntelligenceTiers.Tiers.Standard
	end

	return NPCIntelligenceTiers.Tiers.Advanced
end

function NPCManager:_ResolveTierForSpawnPoint(initialTier, spawnPoint)
	if self._forcedTier then
		return self._forcedTier
	end

	if not spawnPoint then
		return initialTier
	end

	local tierValue = spawnPoint:GetAttribute("IntelligenceTier") or spawnPoint:GetAttribute("Tier")
	local parsedTier = self:_ParseTierValue(tierValue)
	if parsedTier then
		return parsedTier
	end

	return initialTier
end

function NPCManager:_ResolveLeashRadiusForSpawnPoint(spawnPoint, intelligenceTier)
	if not spawnPoint then
		return nil
	end

	local perTierAttribute = nil
	if intelligenceTier == NPCIntelligenceTiers.Tiers.Primitive then
		perTierAttribute = "PrimitiveLeashRadius"
	elseif intelligenceTier == NPCIntelligenceTiers.Tiers.Standard then
		perTierAttribute = "StandardLeashRadius"
	elseif intelligenceTier == NPCIntelligenceTiers.Tiers.Advanced then
		perTierAttribute = "AdvancedLeashRadius"
	end

	local specific = perTierAttribute and tonumber(spawnPoint:GetAttribute(perTierAttribute)) or nil
	if specific and specific > 0 then
		return specific
	end

	local generic = tonumber(spawnPoint:GetAttribute("LeashRadius"))
	if generic and generic > 0 then
		return generic
	end

	return nil
end

function NPCManager:_ChooseSpawnPointForTier(targetTier)
	local all = self:_GetValidSpawnPoints()
	if #all == 0 then
		return nil
	end

	local matching = {}
	for _, spawnPoint in ipairs(all) do
		local tierValue = spawnPoint:GetAttribute("IntelligenceTier") or spawnPoint:GetAttribute("Tier")
		local parsedTier = self:_ParseTierValue(tierValue)
		if not parsedTier or parsedTier == targetTier then
			table.insert(matching, spawnPoint)
		end
	end

	if #matching == 0 then
		matching = all
	end

	return self:_PickLeastLoadedSpawnPoint(matching)
end

function NPCManager:_PickLeastLoadedSpawnPoint(spawnPoints)
	local loadByName = self:_GetSpawnPointLoads()
	local lowestLoad = math.huge
	local lowest = {}

	for _, spawnPoint in ipairs(spawnPoints) do
		local name = spawnPoint.Name
		local load = loadByName[name] or 0
		if load < lowestLoad then
			lowestLoad = load
			lowest = {spawnPoint}
		elseif load == lowestLoad then
			table.insert(lowest, spawnPoint)
		end
	end

	if #lowest == 0 then
		return self:_PickWeightedSpawnPoint(spawnPoints)
	end

	return lowest[math.random(1, #lowest)]
end

function NPCManager:_GetSpawnPointLoads()
	local loads = {}
	for _, spawnPoint in ipairs(self:_GetValidSpawnPoints()) do
		loads[spawnPoint.Name] = 0
	end

	for npcId in pairs(self._controllers) do
		local spawnName = self._spawnAssignments[npcId]
		if spawnName then
			loads[spawnName] = (loads[spawnName] or 0) + 1
		end
	end

	return loads
end

function NPCManager:_PickWeightedSpawnPoint(spawnPoints)
	local totalWeight = 0
	for _, spawnPoint in ipairs(spawnPoints) do
		local weight = tonumber(spawnPoint:GetAttribute("Weight")) or 1
		if weight > 0 then
			totalWeight = totalWeight + weight
		end
	end

	if totalWeight <= 0 then
		return spawnPoints[math.random(1, #spawnPoints)]
	end

	local roll = math.random() * totalWeight
	local current = 0
	for _, spawnPoint in ipairs(spawnPoints) do
		local weight = tonumber(spawnPoint:GetAttribute("Weight")) or 1
		if weight > 0 then
			current = current + weight
			if roll <= current then
				return spawnPoint
			end
		end
	end

	return spawnPoints[#spawnPoints]
end

function NPCManager:_ParseTierValue(tierValue)
	if tierValue == nil then
		return nil
	end

	if typeof(tierValue) == "number" then
		local asNumber = math.floor(tierValue)
		if asNumber == NPCIntelligenceTiers.Tiers.Primitive
			or asNumber == NPCIntelligenceTiers.Tiers.Standard
			or asNumber == NPCIntelligenceTiers.Tiers.Advanced then
			return asNumber
		end
		return nil
	end

	if typeof(tierValue) == "string" then
		local normalized = string.lower(string.gsub(tierValue, "%s+", ""))
		if normalized == "primitive" or normalized == "1" then
			return NPCIntelligenceTiers.Tiers.Primitive
		elseif normalized == "standard" or normalized == "2" then
			return NPCIntelligenceTiers.Tiers.Standard
		elseif normalized == "advanced" or normalized == "3" then
			return NPCIntelligenceTiers.Tiers.Advanced
		end
	end

	return nil
end

function NPCManager:_GetValidSpawnPoints()
	local points = {}
	for instance in pairs(self._spawnPoints) do
		if instance and instance.Parent and instance:IsA("BasePart") then
			table.insert(points, instance)
		end
	end
	return points
end

function NPCManager:_DiscoverSpawnPoints()
	for _, instance in ipairs(CollectionService:GetTagged(SPAWN_POINT_TAG)) do
		self:_RegisterSpawnPoint(instance)
	end
end

function NPCManager:_BindSpawnPointSignals()
	CollectionService:GetInstanceAddedSignal(SPAWN_POINT_TAG):Connect(function(instance)
		self:_RegisterSpawnPoint(instance)
	end)

	CollectionService:GetInstanceRemovedSignal(SPAWN_POINT_TAG):Connect(function(instance)
		self._spawnPoints[instance] = nil
	end)
end

function NPCManager:_RegisterSpawnPoint(instance)
	if not instance:IsA("BasePart") then
		return
	end

	self._spawnPoints[instance] = true
end

function NPCManager:_NormalizeTierWeights()
	local primitive = math.max(0, tonumber(self._tierWeights.primitive) or 0)
	local standard = math.max(0, tonumber(self._tierWeights.standard) or 0)
	local advanced = math.max(0, tonumber(self._tierWeights.advanced) or 0)
	local total = primitive + standard + advanced

	if total <= 0 then
		self._tierWeights.primitive = 0.5
		self._tierWeights.standard = 0.35
		self._tierWeights.advanced = 0.15
		return
	end

	self._tierWeights.primitive = primitive / total
	self._tierWeights.standard = standard / total
	self._tierWeights.advanced = advanced / total
end

function NPCManager:GetTierWeights()
	return {
		primitive = self._tierWeights.primitive,
		standard = self._tierWeights.standard,
		advanced = self._tierWeights.advanced
	}
end

function NPCManager:SetTierWeights(primitiveWeight, standardWeight, advancedWeight)
	if primitiveWeight == nil or standardWeight == nil or advancedWeight == nil then
		return false
	end

	self._tierWeights.primitive = tonumber(primitiveWeight)
	self._tierWeights.standard = tonumber(standardWeight)
	self._tierWeights.advanced = tonumber(advancedWeight)

	if not self._tierWeights.primitive or not self._tierWeights.standard or not self._tierWeights.advanced then
		return false
	end

	self:_NormalizeTierWeights()
	return true
end

function NPCManager:SetForcedTier(tier)
	if tier == nil then
		self._forcedTier = nil
		return true
	end

	local parsedTier = tonumber(tier)
	if parsedTier ~= NPCIntelligenceTiers.Tiers.Primitive
		and parsedTier ~= NPCIntelligenceTiers.Tiers.Standard
		and parsedTier ~= NPCIntelligenceTiers.Tiers.Advanced then
		return false
	end

	self._forcedTier = parsedTier
	return true
end

function NPCManager:GetForcedTier()
	return self._forcedTier
end

function NPCManager:GetTierStats()
	local stats = {
		[NPCIntelligenceTiers.Tiers.Primitive] = 0,
		[NPCIntelligenceTiers.Tiers.Standard] = 0,
		[NPCIntelligenceTiers.Tiers.Advanced] = 0
	}

	for _, controller in pairs(self._controllers) do
		local tier = controller.GetIntelligenceTier and controller:GetIntelligenceTier() or NPCIntelligenceTiers.Tiers.Standard
		if stats[tier] ~= nil then
			stats[tier] = stats[tier] + 1
		end
	end

	return stats
end

function NPCManager:GetDebugSnapshot()
	local snapshot = {}
	for id, controller in pairs(self._controllers) do
		local tier = controller.GetIntelligenceTier and controller:GetIntelligenceTier() or NPCIntelligenceTiers.Tiers.Standard
		table.insert(snapshot, {
			id = id,
			tier = tier
		})
	end

	table.sort(snapshot, function(a, b)
		return a.id < b.id
	end)

	return snapshot
end

function NPCManager:_CreateNpcModel(npcId, description, spawnCFrame)
	spawnCFrame = spawnCFrame or self:_GetRandomSpawnCFrame(nil)

	local model = nil
	if description then
		local ok, createdModel = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, DEFAULT_RIG_TYPE)
		end)
		if ok then
			model = createdModel
		end
	end

	if not model then
		local ok, createdModel = pcall(function()
			local fallbackDescription = Instance.new("HumanoidDescription")
			return Players:CreateHumanoidModelFromDescription(fallbackDescription, DEFAULT_RIG_TYPE)
		end)
		if not ok or not createdModel then
			warn(string.format("[NPCManager] Failed to create humanoid rig for NPC %d", npcId))
			return nil
		end
		model = createdModel
	end

	model.Name = string.format("Guest_%02d", npcId)

	model:PivotTo(spawnCFrame)
	self:_AssignCollisionGroup(model, NPC_COLLISION_GROUP)
	model.Parent = self._npcFolder

	return model
end

function NPCManager:_GetRandomSpawnCFrame(spawnPart)
	if not spawnPart then
		spawnPart = Workspace:FindFirstChild("NPCSpawn")
	end
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return CFrame.new(0, 5, 0)
	end

	local half = spawnPart.Size * 0.5
	local localOffset = Vector3.new(
		(math.random() * 2 - 1) * half.X,
		half.Y,
		(math.random() * 2 - 1) * half.Z
	)

	local worldPosition = spawnPart.CFrame:PointToWorldSpace(localOffset) + Vector3.new(0, 3, 0)
	local lookAt = worldPosition + spawnPart.CFrame.LookVector
	return CFrame.new(worldPosition, lookAt)
end

function NPCManager:_AssignCollisionGroup(model, groupName)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local ok = pcall(function()
				descendant.CollisionGroup = groupName
			end)
			if not ok then
				warn(string.format("[NPCManager] Could not assign collision group '%s'", groupName))
				return
			end
		end
	end
end

function NPCManager:GetControllers()
	return self._controllers
end

function NPCManager:GetControllerById(npcId)
	return self._controllers[npcId]
end

function NPCManager:GetActiveNpcCount()
	return self:_GetNpcCount()
end

function NPCManager:GetDesiredNpcCount()
	return self._desiredNpcCount
end

function NPCManager:SetDesiredNpcCount(count)
	local parsed = tonumber(count)
	if not parsed then
		return false
	end

	self._desiredNpcCount = math.clamp(math.floor(parsed), 0, 50)
	if self._isRunning then
		self:_EnsureNpcCount()
	end

	return true
end

function NPCManager:RespawnAll()
	local wasRunning = self._isRunning
	self:Stop()
	if wasRunning then
		self:Start()
	end
end

return NPCManager
