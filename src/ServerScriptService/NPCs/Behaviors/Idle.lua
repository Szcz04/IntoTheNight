local Idle = {}
Idle.__index = Idle

function Idle.new()
	return setmetatable({}, Idle)
end

function Idle:Start(controller, context)
	self._controller = controller
	self._duration = (context and context.duration) or math.random(2, 5)
	self._elapsed = 0
	controller:SetAnimationState("IDLE")
end

function Idle:Step(_, dt)
	self._elapsed = self._elapsed + dt
	if self._elapsed >= self._duration then
		return "done"
	end
	return nil
end

function Idle:Stop()
	-- No cleanup required.
end

return Idle
