local NPCIntelligenceTiers = {}

NPCIntelligenceTiers.Tiers = {
	Primitive = 1,
	Standard = 2,
	Advanced = 3
}

local POLICIES = {
	[NPCIntelligenceTiers.Tiers.Primitive] = {
		tier = NPCIntelligenceTiers.Tiers.Primitive,
		name = "Primitive",
		allowedBehaviors = {
			IDLE = true,
			SIT = true,
			WALK_NEAR = true,
			LOOK = true,
			LEAN = true
		},
		stayNearAssignedPoint = true,
		maxTravelDistance = 40,
		idleBias = 0.85,
		sitBias = 0.7,
		allowDynamicRetarget = false,
		reactsToEvents = false,
		reactsToOtherNPCs = false,
		preferredPointTypes = {"Sit", "Idle", "Talk"},
		idleDurationRange = {4, 9},
		sitDurationRange = {6, 12}
	},
	[NPCIntelligenceTiers.Tiers.Standard] = {
		tier = NPCIntelligenceTiers.Tiers.Standard,
		name = "Standard",
		allowedBehaviors = {
			IDLE = true,
			SIT = true,
			WALK_NEAR = true,
			INTERACT_SIMPLE = true,
			DANCE = true
		},
		stayNearAssignedPoint = false,
		maxTravelDistance = 110,
		idleBias = 0.2,
		sitBias = 0.45,
		allowDynamicRetarget = true,
		reactsToEvents = false,
		reactsToOtherNPCs = false,
		preferredPointTypes = {"Sit", "Talk", "Dance", "Idle"},
		idleDurationRange = {2, 6},
		sitDurationRange = {5, 9}
	},
	[NPCIntelligenceTiers.Tiers.Advanced] = {
		tier = NPCIntelligenceTiers.Tiers.Advanced,
		name = "Advanced",
		allowedBehaviors = {
			IDLE = true,
			SIT = true,
			WALK_NEAR = true,
			WALK_FAR = true,
			INTERACT_SIMPLE = true,
			INTERACT_REACTIVE = true,
			DANCE = true
		},
		stayNearAssignedPoint = false,
		maxTravelDistance = nil,
		idleBias = 0.2,
		sitBias = 0.35,
		allowDynamicRetarget = true,
		reactsToEvents = true,
		reactsToOtherNPCs = true,
		preferredPointTypes = {"Talk", "Sit", "Dance", "Idle"},
		idleDurationRange = {2, 5},
		sitDurationRange = {4, 8}
	}
}

function NPCIntelligenceTiers.ResolvePolicy(tier)
	local resolvedTier = tonumber(tier) or NPCIntelligenceTiers.Tiers.Standard
	return POLICIES[resolvedTier] or POLICIES[NPCIntelligenceTiers.Tiers.Standard]
end

function NPCIntelligenceTiers.CanPerform(policy, behaviorKey)
	if not policy or not behaviorKey then
		return false
	end

	return policy.allowedBehaviors[behaviorKey] == true
end

function NPCIntelligenceTiers.RandomDuration(range)
	local min = (range and range[1]) or 2
	local max = (range and range[2]) or min
	if max < min then
		max = min
	end
	return math.random(min, max)
end

return NPCIntelligenceTiers
