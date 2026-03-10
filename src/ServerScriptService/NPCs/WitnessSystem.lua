local Workspace = game:GetService("Workspace")

local WitnessSystem = {}
WitnessSystem.__index = WitnessSystem

WitnessSystem.Config = {
	PerActorActionThrottleSeconds = 0.2,
	MaxWitnessesPerEvent = 5,
	SuspicionPerExtraWitnessMultiplier = 0.2,
	SuspicionMultiplierCap = 2.5,
	DefaultReason = "WitnessedSuspiciousAction"
}

function WitnessSystem.new(config)
	local self = setmetatable({}, WitnessSystem)

	config = config or {}
	self._suspicionManager = config.suspicionManager
	self._sources = {}
	self._lastActionAtByKey = {}
	self._maxWitnessesPerEvent = tonumber(config.maxWitnessesPerEvent) or WitnessSystem.Config.MaxWitnessesPerEvent
	self._throttleSeconds = tonumber(config.perActorActionThrottleSeconds) or WitnessSystem.Config.PerActorActionThrottleSeconds
	self._perExtraWitnessMultiplier = tonumber(config.suspicionPerExtraWitnessMultiplier) or WitnessSystem.Config.SuspicionPerExtraWitnessMultiplier
	self._suspicionMultiplierCap = tonumber(config.suspicionMultiplierCap) or WitnessSystem.Config.SuspicionMultiplierCap

	self.ActionReported = Instance.new("BindableEvent")
	self.ActionWitnessed = Instance.new("BindableEvent")
	self.ActionIgnored = Instance.new("BindableEvent")
	self.SuspicionApplied = Instance.new("BindableEvent")

	print("[WitnessSystem] Initialized")
	return self
end

function WitnessSystem:_IsDebugEnabled()
	return Workspace:GetAttribute("WitnessDebugLogs") == true or Workspace:GetAttribute("NPCDebugLogs") == true
end

function WitnessSystem:_DebugLog(fmt, ...)
	if not self:_IsDebugEnabled() then
		return
	end

	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = tostring(fmt)
	end

	print(string.format("[WitnessSystem] %s", message))
end

function WitnessSystem:RegisterSource(source)
	if not source or type(source.Evaluate) ~= "function" then
		warn("[WitnessSystem] RegisterSource rejected invalid source")
		return false
	end

	local sourceId = tostring(source.GetSourceId and source:GetSourceId() or "unknown")
	table.insert(self._sources, source)
	print(string.format("[WitnessSystem] RegisterSource accepted: %s (total=%d)", sourceId, #self._sources))
	self:_DebugLog("Registered source: %s", sourceId)
	return true
end

function WitnessSystem:GetSourceCount()
	return #self._sources
end

function WitnessSystem:GetSourceIds()
	local ids = {}
	for _, source in ipairs(self._sources) do
		table.insert(ids, tostring(source.GetSourceId and source:GetSourceId() or "unknown"))
	end
	return ids
end

function WitnessSystem:_CanProcessAction(payload, now)
	local actor = payload and payload.actorPlayer
	if not actor then
		return true
	end

	local actionType = tostring(payload.actionType or "UnknownAction")
	local key = string.format("%d:%s", actor.UserId, actionType)
	local last = self._lastActionAtByKey[key]
	if last and now - last < self._throttleSeconds then
		return false
	end

	self._lastActionAtByKey[key] = now
	return true
end

function WitnessSystem:_CollectWitnesses(payload, now)
	local witnesses = {}
	for _, source in ipairs(self._sources) do
		local ok, sourceWitnesses = pcall(function()
			return source:Evaluate(payload, now)
		end)

		if ok and type(sourceWitnesses) == "table" then
			for _, witnessEntry in ipairs(sourceWitnesses) do
				table.insert(witnesses, witnessEntry)
				if #witnesses >= self._maxWitnessesPerEvent then
					break
				end
			end
		elseif not ok then
			warn(string.format("[WitnessSystem] Source evaluate failed: %s", tostring(sourceWitnesses)))
		end

		if #witnesses >= self._maxWitnessesPerEvent then
			break
		end
	end

	return witnesses
end

function WitnessSystem:EvaluateWitnesses(payload)
	if not payload or not payload.actorPlayer then
		return {
			witnessed = false,
			witnesses = {},
			error = "missing actorPlayer"
		}
	end

	local now = tick()
	local witnesses = self:_CollectWitnesses(payload, now)

	return {
		timestamp = now,
		actorPlayer = payload.actorPlayer,
		actionType = payload.actionType or "UnknownAction",
		actionContext = payload.actionContext,
		worldPosition = payload.worldPosition,
		witnessCount = #witnesses,
		witnessed = #witnesses > 0,
		witnesses = witnesses
	}
end

function WitnessSystem:ComputeSuspicionAmount(baseAmount, witnessCount)
	local base = math.max(0, tonumber(baseAmount) or 0)
	if base <= 0 then
		return 0, 1
	end

	local count = math.max(0, math.floor(tonumber(witnessCount) or 0))
	local multiplier = 1
	if count > 1 then
		multiplier = 1 + ((count - 1) * self._perExtraWitnessMultiplier)
	end

	multiplier = math.clamp(multiplier, 1, self._suspicionMultiplierCap)
	local adjusted = math.max(1, math.floor((base * multiplier) + 0.5))
	return adjusted, multiplier
end

function WitnessSystem:ProcessSuspiciousAction(payload)
	if not payload or not payload.actorPlayer then
		return {
			witnessed = false,
			error = "missing actorPlayer"
		}
	end

	local now = tick()
	if not self:_CanProcessAction(payload, now) then
		self:_DebugLog("Throttled action actor=%s type=%s", payload.actorPlayer.Name, tostring(payload.actionType))
		return {
			witnessed = false,
			throttled = true
		}
	end

	local witnesses = self:_CollectWitnesses(payload, now)

	local result = {
		timestamp = now,
		actorPlayer = payload.actorPlayer,
		actionType = payload.actionType or "UnknownAction",
		actionContext = payload.actionContext,
		worldPosition = payload.worldPosition,
		reason = payload.reason,
		suspicionAmount = tonumber(payload.suspicionAmount) or 0,
		witnessCount = #witnesses,
		witnessed = #witnesses > 0,
		witnesses = witnesses
	}

	self.ActionReported:Fire(result)

	if not result.witnessed then
		self:_DebugLog("No witness: actor=%s type=%s", payload.actorPlayer.Name, tostring(payload.actionType))
		self.ActionIgnored:Fire(result)
		return result
	end

	self:_DebugLog("Witnessed: actor=%s type=%s witnesses=%d", payload.actorPlayer.Name, tostring(payload.actionType), #witnesses)
	self.ActionWitnessed:Fire(result)
	self:_ApplySuspicion(result)

	return result
end

function WitnessSystem:_ApplySuspicion(result)
	if not self._suspicionManager then
		return
	end

	local actorPlayer = result.actorPlayer
	local amount, multiplier = self:ComputeSuspicionAmount(result.suspicionAmount, result.witnessCount or #(result.witnesses or {}))
	if amount <= 0 then
		return
	end

	local reason = result.reason or WitnessSystem.Config.DefaultReason
	self._suspicionManager:AddSuspicion(actorPlayer, amount, reason)
	self.SuspicionApplied:Fire(result)
	self:_DebugLog("Suspicion applied: actor=%s amount=%d multiplier=%.2f reason=%s", actorPlayer.Name, amount, multiplier, tostring(reason))
end

return WitnessSystem
