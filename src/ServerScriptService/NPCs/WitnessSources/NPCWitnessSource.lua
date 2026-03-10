local Workspace = game:GetService("Workspace")

local NPCWitnessSource = {}
NPCWitnessSource.__index = NPCWitnessSource

NPCWitnessSource.Config = {
	MaxDistance = 70,
	MinDot = 0.25,
	MaxNPCsPerCheck = 12,
	CheckIntervalSeconds = 0.12
}

function NPCWitnessSource.new(npcManager, config)
	local self = setmetatable({}, NPCWitnessSource)

	config = config or {}
	self._npcManager = npcManager
	self._maxDistance = tonumber(config.maxDistance) or NPCWitnessSource.Config.MaxDistance
	self._minDot = tonumber(config.minDot) or NPCWitnessSource.Config.MinDot
	self._maxNPCsPerCheck = tonumber(config.maxNPCsPerCheck) or NPCWitnessSource.Config.MaxNPCsPerCheck
	self._checkInterval = tonumber(config.checkIntervalSeconds) or NPCWitnessSource.Config.CheckIntervalSeconds
	self._lastCheckAtByActor = {}
	self._roundRobinIndex = 1

	return self
end

function NPCWitnessSource:GetSourceId()
	return "npc"
end

function NPCWitnessSource:_GetActorRoot(actorPlayer)
	local character = actorPlayer and actorPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function NPCWitnessSource:_CanCheckActor(actorUserId, now)
	local last = self._lastCheckAtByActor[actorUserId]
	if last and now - last < self._checkInterval then
		return false
	end

	self._lastCheckAtByActor[actorUserId] = now
	return true
end

function NPCWitnessSource:_BuildControllersList()
	if not self._npcManager or not self._npcManager.GetControllers then
		return {}
	end

	local list = {}
	for _, controller in pairs(self._npcManager:GetControllers()) do
		table.insert(list, controller)
	end

	return list
end

function NPCWitnessSource:_HasLineOfSight(observerRoot, actorRoot)
	local direction = actorRoot.Position - observerRoot.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = {observerRoot.Parent}
	params.IgnoreWater = true

	local hit = Workspace:Raycast(observerRoot.Position, direction, params)
	if not hit then
		return true
	end

	return hit.Instance and hit.Instance:IsDescendantOf(actorRoot.Parent)
end

function NPCWitnessSource:_CanWitness(controller, actorRoot)
	if not controller or not controller.GetRootPart then
		return false
	end

	local observerRoot = controller:GetRootPart()
	if not observerRoot or not observerRoot.Parent then
		return false
	end

	local toActor = actorRoot.Position - observerRoot.Position
	local distance = toActor.Magnitude
	if distance <= 0 or distance > self._maxDistance then
		return false
	end

	local lookDir = observerRoot.CFrame.LookVector
	local dot = lookDir:Dot(toActor.Unit)
	if dot < self._minDot then
		return false
	end

	if not self:_HasLineOfSight(observerRoot, actorRoot) then
		return false
	end

	return true
end

function NPCWitnessSource:_SelectControllersForCheck(allControllers)
	local total = #allControllers
	if total <= self._maxNPCsPerCheck then
		return allControllers
	end

	local selected = {}
	for i = 0, self._maxNPCsPerCheck - 1 do
		local index = ((self._roundRobinIndex + i - 1) % total) + 1
		table.insert(selected, allControllers[index])
	end

	self._roundRobinIndex = ((self._roundRobinIndex + self._maxNPCsPerCheck - 1) % total) + 1
	return selected
end

function NPCWitnessSource:Evaluate(payload, now)
	local actorPlayer = payload.actorPlayer
	if not actorPlayer then
		return {}
	end

	if not self:_CanCheckActor(actorPlayer.UserId, now) then
		return {}
	end

	local actorRoot = self:_GetActorRoot(actorPlayer)
	if not actorRoot then
		return {}
	end

	local controllers = self:_BuildControllersList()
	controllers = self:_SelectControllersForCheck(controllers)

	local witnesses = {}
	for _, controller in ipairs(controllers) do
		if self:_CanWitness(controller, actorRoot) then
			local model = controller.GetModel and controller:GetModel() or nil
			table.insert(witnesses, {
				source = "npc",
				npcId = controller.GetId and controller:GetId() or nil,
				npcTier = controller.GetIntelligenceTier and controller:GetIntelligenceTier() or nil,
				npcModel = model,
				npcDisplayName = controller.GetDisplayName and controller:GetDisplayName() or (model and model.Name or "NPC")
			})
		end
	end

	return witnesses
end

return NPCWitnessSource
