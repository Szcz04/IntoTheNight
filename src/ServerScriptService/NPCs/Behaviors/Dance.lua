local Dance = {}
Dance.__index = Dance

function Dance.new()
	return setmetatable({}, Dance)
end

function Dance:Start(controller, context)
	self._controller = controller
	self._duration = (context and context.duration) or math.random(4, 8)
	self._elapsed = 0

	controller:SetAnimationState("DANCE")
end

function Dance:Step(_, dt)
	self._elapsed = self._elapsed + dt
	if self._elapsed >= self._duration then
		return "done"
	end
	return nil
end

function Dance:Stop()
	-- TODO: Stop dance animation track when animation assets are added.
end

return Dance
