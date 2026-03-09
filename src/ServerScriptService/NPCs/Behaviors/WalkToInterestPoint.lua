local WalkToInterestPoint = {}
WalkToInterestPoint.__index = WalkToInterestPoint

function WalkToInterestPoint.new()
	return setmetatable({}, WalkToInterestPoint)
end

function WalkToInterestPoint:Start(controller, context)
	self._controller = controller
	self._point = context and context.point or nil
	self._arrived = false
	self._elapsed = 0
	self._timeout = (context and context.timeout) or 12
	self._target = nil
	self._arrivalBehavior = context and context.arrivalBehavior or nil
	self._stallElapsed = 0
	self._stallTimeout = (context and context.stallTimeout) or 1.8
	self._repathEvery = (context and context.repathEvery) or 0.8
	self._nextRepathAt = 0

	controller:SetAnimationState("WALK")

	if self._point then
		local minDistance = 0
		if string.lower(self._point.type or "") == "dance" then
			minDistance = (self._point.approachRadius or 4) + 6
		end

		local target = controller:GetInterestPointApproachPosition(self._point, {
			minDistance = minDistance,
			attempts = 8
		})
		self._target = target
		controller:_DebugLog(
			"WalkStart point=%s type=%s minDistance=%.2f target=%s",
			self._point.instance and self._point.instance.Name or "?",
			tostring(self._point.type),
			minDistance,
			target and string.format("(%.1f, %.1f, %.1f)", target.X, target.Y, target.Z) or "nil"
		)
		if target then
			controller:MoveTo(target)
		else
			self._arrived = true
		end
	else
		self._arrived = true
	end
end

function WalkToInterestPoint:Step(controller, dt)
	self._elapsed = self._elapsed + dt

	if self._arrived then
		return "done"
	end

	local target = self._target
	if target and controller:IsNearPosition(target, self._point.approachRadius or 4) then
		self._arrived = true
		controller:_DebugLog(
			"WalkArrived point=%s type=%s radius=%.2f",
			self._point and self._point.instance and self._point.instance.Name or "?",
			self._point and tostring(self._point.type) or "?",
			self._point and (self._point.approachRadius or 4) or 4
		)
		if self._arrivalBehavior == "DANCE" then
			return "arrived_dance"
		end
		return "done"
	end

	if target then
		local speed, moveDir = controller:GetMovementSnapshot()
		if speed <= 0.35 and moveDir <= 0.05 then
			self._stallElapsed = self._stallElapsed + dt
			if self._elapsed >= self._nextRepathAt then
				controller:MoveTo(target)
				self._nextRepathAt = self._elapsed + self._repathEvery
			end

			if self._stallElapsed >= self._stallTimeout then
				local near = controller:IsNearPosition(target, self._point and (self._point.approachRadius or 4) or 4)
				controller:_DebugLog(
					"WalkStuck point=%s type=%s stall=%.2f nearTarget=%s",
					self._point and self._point.instance and self._point.instance.Name or "?",
					self._point and tostring(self._point.type) or "?",
					self._stallElapsed,
					tostring(near)
				)
				return "timeout"
			end
		else
			self._stallElapsed = 0
		end
	end

	if self._elapsed >= self._timeout then
		controller:_DebugLog(
			"WalkTimeout point=%s type=%s timeout=%.2f",
			self._point and self._point.instance and self._point.instance.Name or "?",
			self._point and tostring(self._point.type) or "?",
			self._timeout
		)
		return "timeout"
	end

	return nil
end

function WalkToInterestPoint:Stop()
	-- No cleanup required.
end

return WalkToInterestPoint
