local NPCIntelligenceTiers = require(script.Parent.NPCIntelligenceTiers)

local NPCWitnessDialogueService = {}
NPCWitnessDialogueService.__index = NPCWitnessDialogueService

local DIALOG_PACK = {
	default = {
		"I saw that.",
		"That looked suspicious.",
		"You are not blending in.",
		"Host is watching."
	},
	hostCommandFailure = {
		[NPCIntelligenceTiers.Tiers.Primitive] = {
			"Uh... that was wrong.",
			"You did not do it."
		},
		[NPCIntelligenceTiers.Tiers.Standard] = {
			"You ignored the host.",
			"That was obvious."
		},
		[NPCIntelligenceTiers.Tiers.Advanced] = {
			"Non-compliance noted.",
			"Everyone saw that mistake."
		}
	}
}

function NPCWitnessDialogueService.new(witnessSystem, npcManager, config)
	local self = setmetatable({}, NPCWitnessDialogueService)

	config = config or {}
	self._witnessSystem = witnessSystem
	self._npcManager = npcManager
	self._cooldownSeconds = tonumber(config.cooldownSeconds) or 2.5
	self._lastCommentAtByPlayer = {}
	self._connection = nil

	self:_Bind()
	print("[NPCWitnessDialogueService] Initialized")

	return self
end

function NPCWitnessDialogueService:_Bind()
	if not self._witnessSystem or not self._witnessSystem.ActionWitnessed then
		return
	end

	self._connection = self._witnessSystem.ActionWitnessed.Event:Connect(function(result)
		self:_OnActionWitnessed(result)
	end)
end

function NPCWitnessDialogueService:_IsOnCooldown(actorPlayer)
	local userId = actorPlayer and actorPlayer.UserId
	if not userId then
		return true
	end

	local now = tick()
	local last = self._lastCommentAtByPlayer[userId]
	if last and now - last < self._cooldownSeconds then
		return true
	end

	self._lastCommentAtByPlayer[userId] = now
	return false
end

function NPCWitnessDialogueService:_PickNpcWitness(result)
	local npcWitnesses = {}
	for _, witnessEntry in ipairs(result.witnesses or {}) do
		if witnessEntry.source == "npc" and witnessEntry.npcId then
			table.insert(npcWitnesses, witnessEntry)
		end
	end

	if #npcWitnesses == 0 then
		return nil
	end

	return npcWitnesses[math.random(1, #npcWitnesses)]
end

function NPCWitnessDialogueService:_PickLine(result, npcTier)
	if result.actionType == "HostCommandNonCompliance" then
		local tierPack = DIALOG_PACK.hostCommandFailure[npcTier]
		if tierPack and #tierPack > 0 then
			return tierPack[math.random(1, #tierPack)]
		end
	end

	return DIALOG_PACK.default[math.random(1, #DIALOG_PACK.default)]
end

function NPCWitnessDialogueService:_OnActionWitnessed(result)
	if not result or not result.actorPlayer then
		return
	end

	if self:_IsOnCooldown(result.actorPlayer) then
		return
	end

	local npcWitness = self:_PickNpcWitness(result)
	if not npcWitness then
		return
	end

	if not self._npcManager or not self._npcManager.GetControllerById then
		return
	end

	local controller = self._npcManager:GetControllerById(npcWitness.npcId)
	if not controller or not controller.ShowWitnessComment then
		return
	end

	local line = self:_PickLine(result, npcWitness.npcTier)
	controller:ShowWitnessComment(line, 2.8)
end

function NPCWitnessDialogueService:Destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

return NPCWitnessDialogueService
