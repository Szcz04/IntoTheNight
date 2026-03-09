local SitAtInterestPoint = {}
SitAtInterestPoint.__index = SitAtInterestPoint

function SitAtInterestPoint.new()
	return setmetatable({}, SitAtInterestPoint)
end

function SitAtInterestPoint:Start(controller, context)
	self._controller = controller
	self._point = context and context.point or nil
	self._elapsed = 0
	self._timeout = (context and context.timeout) or 14
	self._sitDuration = (context and context.duration) or (self._point and self._point.sitDuration) or 6
	self._phase = "MOVE"
	self._target = nil
	self._stallElapsed = 0
	self._stallTimeout = (context and context.stallTimeout) or 1.8
	self._repathEvery = (context and context.repathEvery) or 0.8
	self._nextRepathAt = 0

	local target = controller:GetInterestPointApproachPosition(self._point)
	self._target = target
	if not target then
		self._phase = "DONE"
		return
	end

	self._approachRadius = (self._point and self._point.approachRadius) or 4
	controller:SetAnimationState("WALK")
	controller:MoveTo(target)
end

function SitAtInterestPoint:Step(controller, dt)
	self._elapsed = self._elapsed + dt

	if self._phase == "DONE" then
		return "done"
	end

	if self._elapsed >= self._timeout then
		return "timeout"
	end

	if self._phase == "MOVE" then
		local target = self._target
		if not target then
			return "done"
		end

		if controller:IsNearPosition(target, self._approachRadius) then
			if self._point and self._point.seat then
				controller:TrySitAtSeat(self._point.seat)
			end
			controller:SetAnimationState("SIT")
			self._phase = "SIT"
			self._elapsed = 0
		end

		local speed, moveDir = controller:GetMovementSnapshot()
		if speed <= 0.35 and moveDir <= 0.05 then
			self._stallElapsed = self._stallElapsed + dt
			if self._elapsed >= self._nextRepathAt then
				controller:MoveTo(target)
				self._nextRepathAt = self._elapsed + self._repathEvery
			end

			if self._stallElapsed >= self._stallTimeout then
				controller:_DebugLog(
					"SitMoveStuck point=%s stall=%.2f",
					self._point and self._point.instance and self._point.instance.Name or "?",
					self._stallElapsed
				)
				return "timeout"
			end
		else
			self._stallElapsed = 0
		end
		return nil
	end

	if self._phase == "SIT" then
		if self._point and self._point.seat and not controller:IsSeatedOn(self._point.seat) then
			controller:TrySitAtSeat(self._point.seat)
		end

		if self._elapsed >= self._sitDuration then
			return "done"
		end
	end

	return nil
end

function SitAtInterestPoint:Stop()
	if self._controller then
		self._controller:CommandSit(false)
	end
end

return SitAtInterestPoint
