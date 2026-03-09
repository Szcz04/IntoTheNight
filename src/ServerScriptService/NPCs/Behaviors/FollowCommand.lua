local FollowCommand = {}
FollowCommand.__index = FollowCommand

function FollowCommand.new()
	return setmetatable({}, FollowCommand)
end

function FollowCommand:Start(controller, context)
	self._controller = controller
	self._command = context and context.command or nil
	self._endsAt = context and context.endsAt or tick()
	self._context = context and context.context or {}
	self._lastSeatRetry = 0

	self:_ApplyCommandPose()
end

function FollowCommand:_ApplyCommandPose()
	if not self._command then
		return
	end

	if self._command == "FREEZE" then
		self._controller:StopMoving()
		self._controller:SetAnimationState("IDLE")
	elseif self._command == "JUMP" then
		self._controller:CommandJump()
		self._controller:SetAnimationState("IDLE")
	elseif self._command == "DANCE" then
		self._controller:SetAnimationState("DANCE")
	elseif self._command == "SIT" then
		self._controller:StopMoving()
		self._controller:CommandSit(true)
		self._controller:SetAnimationState("SIT")
	elseif self._command == "FACE_DIRECTION" then
		local dir = self._context.faceDirectionVector
		if typeof(dir) == "Vector3" then
			self._controller:FaceDirection(dir)
		end
		self._controller:SetAnimationState("IDLE")
	end
end

function FollowCommand:Step(controller, _)
	if self._command == "FREEZE" then
		controller:StopMoving()
	elseif self._command == "SIT" then
		if not controller:IsSeated() and tick() - self._lastSeatRetry >= 1 then
			controller:CommandSit(true)
			self._lastSeatRetry = tick()
		end
	elseif self._command == "DANCE" then
		-- TODO: Play looping dance animation once assets are available.
	elseif self._command == "FACE_DIRECTION" then
		local dir = self._context.faceDirectionVector
		if typeof(dir) == "Vector3" then
			controller:FaceDirection(dir)
		end
	end

	if tick() >= self._endsAt then
		return "done"
	end

	return nil
end

function FollowCommand:Stop()
	if self._command == "SIT" then
		self._controller:CommandSit(false)
	end
end

return FollowCommand
