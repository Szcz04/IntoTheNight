local NPCStateMachine = {}
NPCStateMachine.__index = NPCStateMachine

function NPCStateMachine.new(controller)
	local self = setmetatable({}, NPCStateMachine)

	self._controller = controller
	self._baseBehavior = nil
	self._baseContext = nil
	self._overrideBehavior = nil
	self._overrideContext = nil

	return self
end

function NPCStateMachine:SetBaseBehavior(behavior, context)
	if self._baseBehavior and self._baseBehavior.Stop then
		self._baseBehavior:Stop()
	end

	self._baseBehavior = behavior
	self._baseContext = context or {}

	if self._baseBehavior and self._baseBehavior.Start then
		self._baseBehavior:Start(self._controller, self._baseContext)
	end
end

function NPCStateMachine:SetOverrideBehavior(behavior, context)
	if self._overrideBehavior and self._overrideBehavior.Stop then
		self._overrideBehavior:Stop()
	end

	self._overrideBehavior = behavior
	self._overrideContext = context or {}

	if self._overrideBehavior and self._overrideBehavior.Start then
		self._overrideBehavior:Start(self._controller, self._overrideContext)
	end
end

function NPCStateMachine:ClearOverrideBehavior()
	if self._overrideBehavior and self._overrideBehavior.Stop then
		self._overrideBehavior:Stop()
	end

	self._overrideBehavior = nil
	self._overrideContext = nil
end

function NPCStateMachine:Step(dt)
	local active = self._overrideBehavior or self._baseBehavior
	if not active or not active.Step then
		return nil
	end

	return active:Step(self._controller, dt)
end

function NPCStateMachine:HasOverride()
	return self._overrideBehavior ~= nil
end

return NPCStateMachine
