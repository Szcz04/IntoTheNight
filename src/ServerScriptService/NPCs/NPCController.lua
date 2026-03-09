local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NPCStateMachine = require(script.Parent.NPCStateMachine)
local NPCIntelligenceTiers = require(script.Parent.NPCIntelligenceTiers)

local Idle = require(script.Parent.Behaviors.Idle)
local WalkToInterestPoint = require(script.Parent.Behaviors.WalkToInterestPoint)
local SitAtInterestPoint = require(script.Parent.Behaviors.SitAtInterestPoint)
local Dance = require(script.Parent.Behaviors.Dance)
local FollowCommand = require(script.Parent.Behaviors.FollowCommand)

local NPCController = {}
NPCController.__index = NPCController

local DEFAULT_WALK_ANIMATION_ID = "rbxassetid://507777826"
local DEFAULT_IDLE_ANIMATION_ID = "rbxassetid://507766666"
local DEFAULT_SIT_ANIMATION_ID = "rbxassetid://2506281703"
local DEFAULT_DANCE_ANIMATION_IDS = {
	"rbxassetid://125261159495479",
	"rbxassetid://101751891207850"
}
local DEBUG_LOG_ATTRIBUTE = "NPCDebugLogs"
local WALK_STALL_SPEED_THRESHOLD = 0.75
local WALK_STALL_DIR_THRESHOLD = 0.05
local WALK_STALL_TIME = 0.35
local WALK_BLEND_SPEED_THRESHOLD = 0.45
local WALK_BLEND_DIR_THRESHOLD = 0.03

function NPCController.new(config)
	local self = setmetatable({}, NPCController)

	self._id = config.id
	self._model = config.model
	self._humanoid = config.humanoid
	self._root = config.root
	self._interestPointService = config.interestPointService
	self._hostCommandSystem = config.hostCommandSystem
	self._intelligenceTier = config.intelligenceTier or NPCIntelligenceTiers.Tiers.Standard
	self._tierPolicy = NPCIntelligenceTiers.ResolvePolicy(self._intelligenceTier)

	self._stateMachine = NPCStateMachine.new(self)
	self._activePoint = nil
	self._isRunning = false
	self._updateConnection = nil
	self._hostStartConnection = nil
	self._hostEndConnection = nil
	self._animator = nil
	self._walkAnimation = nil
	self._idleAnimation = nil
	self._sitAnimation = nil
	self._danceAnimations = nil
	self._activeTrack = nil
	self._activeTrackName = nil
	self._currentSeat = nil
	self._anchorPosition = self._root and self._root.Position or nil
	self._assignedPoint = nil
	self._lastPoint = nil
	self._currentAnimationState = nil
	self._lastMoveToTarget = nil
	self._lastWalkMovingAt = tick()
	self._lastWalkStallLogAt = 0

	return self
end

function NPCController:GetId()
	return self._id
end

function NPCController:_IsDebugEnabled()
	return Workspace:GetAttribute(DEBUG_LOG_ATTRIBUTE) == true
end

function NPCController:_DebugLog(fmt, ...)
	if not self:_IsDebugEnabled() then
		return
	end

	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = tostring(fmt)
	end

	print(string.format("[NPCController:%02d] %s", self._id or -1, message))
end

function NPCController:Start()
	if self._isRunning then
		return
	end

	self._isRunning = true
	self:_BindHostCommandEvents()
	self:_PickNextBaseBehavior()

	self._updateConnection = RunService.Heartbeat:Connect(function(dt)
		self:_Update(dt)
	end)
end

function NPCController:Stop()
	if not self._isRunning then
		return
	end

	self._isRunning = false

	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	if self._hostStartConnection then
		self._hostStartConnection:Disconnect()
		self._hostStartConnection = nil
	end

	if self._hostEndConnection then
		self._hostEndConnection:Disconnect()
		self._hostEndConnection = nil
	end

	self:_StopActiveAnimation()
	self:CommandSit(false)
	if self._humanoid then
		self._humanoid.AutoRotate = true
	end

	self:_ReleaseActivePoint()
end

function NPCController:_EnsureAnimator()
	if self._animator and self._animator.Parent == self._humanoid then
		return self._animator
	end

	if not self._humanoid then
		return nil
	end

	self._animator = self._humanoid:FindFirstChildOfClass("Animator")
	if not self._animator then
		self._animator = Instance.new("Animator")
		self._animator.Parent = self._humanoid
	end

	return self._animator
end

function NPCController:_StopActiveAnimation()
	if self._activeTrack then
		self:_DebugLog("Stop track '%s'", tostring(self._activeTrackName))
		self._activeTrack:Stop(0.15)
		self._activeTrack = nil
		self._activeTrackName = nil
	end
end

function NPCController:_PlayWalkAnimation()
	if not self._walkAnimation then
		self._walkAnimation = Instance.new("Animation")
		self._walkAnimation.AnimationId = DEFAULT_WALK_ANIMATION_ID
	end

	self:_PlayLoopedAnimation("WALK", self._walkAnimation, Enum.AnimationPriority.Movement)
end

function NPCController:_PlayIdleAnimation()
	if not self._idleAnimation then
		self._idleAnimation = Instance.new("Animation")
		self._idleAnimation.AnimationId = DEFAULT_IDLE_ANIMATION_ID
	end

	self:_PlayLoopedAnimation("IDLE", self._idleAnimation, Enum.AnimationPriority.Idle)
end

function NPCController:_PlaySitAnimation()
	if not self._sitAnimation then
		self._sitAnimation = Instance.new("Animation")
		self._sitAnimation.AnimationId = DEFAULT_SIT_ANIMATION_ID
	end

	self:_PlayLoopedAnimation("SIT", self._sitAnimation, Enum.AnimationPriority.Action)
end

function NPCController:_PlayWalkIdleBlendAnimation()
	if not self._idleAnimation then
		self._idleAnimation = Instance.new("Animation")
		self._idleAnimation.AnimationId = DEFAULT_IDLE_ANIMATION_ID
	end

	self:_PlayLoopedAnimation("WALK_IDLE_BLEND", self._idleAnimation, Enum.AnimationPriority.Movement)
end

function NPCController:_PlayDanceAnimation()
	if not self._danceAnimations then
		self._danceAnimations = {}
		for _, animationId in ipairs(DEFAULT_DANCE_ANIMATION_IDS) do
			if typeof(animationId) == "string" and #animationId > 0 then
				local animation = Instance.new("Animation")
				animation.AnimationId = animationId
				table.insert(self._danceAnimations, animation)
			end
		end
	end

	if #self._danceAnimations == 0 then
		self:_StopActiveAnimation()
		return
	end

	local chosen = self._danceAnimations[math.random(1, #self._danceAnimations)]
	self:_PlayLoopedAnimation("DANCE", chosen, Enum.AnimationPriority.Action)
end

function NPCController:_PlayLoopedAnimation(trackName, animation, priority)
	if self._activeTrackName == trackName and self._activeTrack and self._activeTrack.IsPlaying then
		return
	end

	local animator = self:_EnsureAnimator()
	if not animator then
		return
	end

	self:_StopActiveAnimation()

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return
	end

	track.Looped = true
	track.Priority = priority
	track:Play(0.15)

	self._activeTrack = track
	self._activeTrackName = trackName
	self:_DebugLog("Play track '%s' (priority=%s)", trackName, tostring(priority))
end

function NPCController:_BindHostCommandEvents()
	if not self._hostCommandSystem then
		return
	end

	if self._hostCommandSystem.CommandStarted and self._hostCommandSystem.CommandStarted.Event then
		self._hostStartConnection = self._hostCommandSystem.CommandStarted.Event:Connect(function(payload)
			self:_OnHostCommandStarted(payload)
		end)
	end

	if self._hostCommandSystem.CommandEnded and self._hostCommandSystem.CommandEnded.Event then
		self._hostEndConnection = self._hostCommandSystem.CommandEnded.Event:Connect(function(payload)
			self:_OnHostCommandEnded(payload)
		end)
	end
end

function NPCController:_OnHostCommandStarted(payload)
	local follow = FollowCommand.new()
	self._stateMachine:SetOverrideBehavior(follow, {
		command = payload and payload.name,
		endsAt = payload and payload.endsAt,
		context = payload and payload.context
	})
end

function NPCController:_OnHostCommandEnded(_)
	self._stateMachine:ClearOverrideBehavior()
	self:_PickNextBaseBehavior()
end

function NPCController:_Update(dt)
	local result = self._stateMachine:Step(dt)

	if self._root and self._humanoid then
		local speed = self._root.AssemblyLinearVelocity.Magnitude
		local moveDir = self._humanoid.MoveDirection.Magnitude

		if self._currentAnimationState == "WALK" then
			if speed > WALK_BLEND_SPEED_THRESHOLD or moveDir > WALK_BLEND_DIR_THRESHOLD then
				if self._activeTrackName ~= "WALK" then
					self:_PlayWalkAnimation()
				end
			else
				if self._activeTrackName ~= "WALK_IDLE_BLEND" then
					self:_PlayWalkIdleBlendAnimation()
				end
			end
		end

		if speed > WALK_STALL_SPEED_THRESHOLD or moveDir > WALK_STALL_DIR_THRESHOLD then
			self._lastWalkMovingAt = tick()
		elseif tick() - self._lastWalkMovingAt >= WALK_STALL_TIME and tick() - self._lastWalkStallLogAt >= 0.8 then
			self._lastWalkStallLogAt = tick()
			local distToTarget = -1
			if self._lastMoveToTarget then
				distToTarget = (self._root.Position - self._lastMoveToTarget).Magnitude
			end

			self:_DebugLog(
				"WALK track while near-stationary speed=%.2f moveDir=%.2f distToTarget=%.2f state=%s",
				speed,
				moveDir,
				distToTarget,
				tostring(self._currentAnimationState)
			)
		end
	end

	if result == "arrived_dance" then
		self:_DebugLog("StateMachine result arrived_dance")
		if not self._stateMachine:HasOverride() and NPCIntelligenceTiers.CanPerform(self._tierPolicy, "DANCE") then
			self._stateMachine:SetBaseBehavior(Dance.new(), {
				duration = math.random(4, 7)
			})
			return
		end
	end

	if result == "done" or result == "timeout" or result == "arrived_dance" then
		if result ~= "arrived_dance" then
			self:_DebugLog("StateMachine result %s", tostring(result))
		end
		if not self._stateMachine:HasOverride() then
			self:_PickNextBaseBehavior()
		end
	end
end

function NPCController:_PickNextBaseBehavior()
	self:_ReleaseActivePoint()
	local policy = self._tierPolicy

	if policy.stayNearAssignedPoint then
		self:_PickPrimitiveBehavior(policy)
		return
	end

	if NPCIntelligenceTiers.CanPerform(policy, "IDLE") and math.random() < policy.idleBias then
		self._stateMachine:SetBaseBehavior(Idle.new(), {
			duration = NPCIntelligenceTiers.RandomDuration(policy.idleDurationRange)
		})
		return
	end

	local point = self:_ClaimPointForPolicy(policy)
	if point then
		self:_SetBehaviorFromPoint(policy, point)
		return
	end

	if NPCIntelligenceTiers.CanPerform(policy, "DANCE") then
		self._stateMachine:SetBaseBehavior(Dance.new(), {
			duration = math.random(4, 7)
		})
		return
	end

	if NPCIntelligenceTiers.CanPerform(policy, "IDLE") then
		self._stateMachine:SetBaseBehavior(Idle.new(), {
			duration = NPCIntelligenceTiers.RandomDuration(policy.idleDurationRange)
		})
		return
	end

	self._stateMachine:SetBaseBehavior(Idle.new(), {
		duration = 3
	})
end

function NPCController:_PickPrimitiveBehavior(policy)
	if not self._assignedPoint and self._interestPointService then
		self._assignedPoint = self._interestPointService:ClaimBestPointConstrained(self._id, policy.preferredPointTypes, {
			origin = self._anchorPosition,
			maxDistance = policy.maxTravelDistance,
			requireSeat = false
		})
	end

	if self._assignedPoint then
		local shouldSit = self._assignedPoint.seat and NPCIntelligenceTiers.CanPerform(policy, "SIT") and math.random() < policy.sitBias
		if shouldSit then
			self._activePoint = self._assignedPoint
			self._stateMachine:SetBaseBehavior(SitAtInterestPoint.new(), {
				point = self._assignedPoint,
				timeout = 20,
				duration = NPCIntelligenceTiers.RandomDuration(policy.sitDurationRange)
			})
			return
		end
	end

	self._stateMachine:SetBaseBehavior(Idle.new(), {
		duration = NPCIntelligenceTiers.RandomDuration(policy.idleDurationRange)
	})
end

function NPCController:_ClaimPointForPolicy(policy)
	if not self._interestPointService then
		return nil
	end

	local constraints = {
		origin = self._anchorPosition,
		maxDistance = policy.maxTravelDistance,
		requireSeat = false,
		avoidPoint = self._lastPoint and self._lastPoint.instance or nil
	}

	if policy.allowDynamicRetarget and self._root then
		constraints.origin = self._root.Position
	end

	return self._interestPointService:ClaimBestPointConstrained(self._id, policy.preferredPointTypes, constraints)
end

function NPCController:_SetBehaviorFromPoint(policy, point)
	self._activePoint = point
	self._lastPoint = point

	if (point.seat or string.lower(point.type) == "sit") and NPCIntelligenceTiers.CanPerform(policy, "SIT") then
		self:_DebugLog("PickBehavior SIT point=%s type=%s", point.instance and point.instance.Name or "?", tostring(point.type))
		self._stateMachine:SetBaseBehavior(SitAtInterestPoint.new(), {
			point = point,
			timeout = 14,
			duration = NPCIntelligenceTiers.RandomDuration(policy.sitDurationRange)
		})
		return
	end

	if policy.maxTravelDistance == nil or NPCIntelligenceTiers.CanPerform(policy, "WALK_NEAR") then
		local arrivalBehavior = nil
		if string.lower(point.type) == "dance" and NPCIntelligenceTiers.CanPerform(policy, "DANCE") then
			arrivalBehavior = "DANCE"
		end

		self:_DebugLog(
			"PickBehavior WALK point=%s type=%s arrivalBehavior=%s",
			point.instance and point.instance.Name or "?",
			tostring(point.type),
			tostring(arrivalBehavior)
		)

		self._stateMachine:SetBaseBehavior(WalkToInterestPoint.new(), {
			point = point,
			timeout = 12,
			arrivalBehavior = arrivalBehavior
		})
		return
	end

	self._stateMachine:SetBaseBehavior(Idle.new(), {
		duration = NPCIntelligenceTiers.RandomDuration(policy.idleDurationRange)
	})
end

function NPCController:_ReleaseActivePoint()
	if self._activePoint and self._assignedPoint and self._activePoint.instance == self._assignedPoint.instance and self._tierPolicy.stayNearAssignedPoint then
		self._activePoint = nil
		return
	end

	if self._activePoint and self._interestPointService then
		self._interestPointService:ReleasePoint(self._activePoint, self._id)
	end
	self._activePoint = nil
end

function NPCController:SetAnimationState(stateName)
	if not self._humanoid then
		return
	end

	if self._currentAnimationState ~= stateName then
		self:_DebugLog("AnimationState %s -> %s", tostring(self._currentAnimationState), tostring(stateName))
	end
	self._currentAnimationState = stateName

	if stateName == "WALK" then
		self._humanoid.WalkSpeed = 8
		self._humanoid.AutoRotate = true
		self:_PlayWalkAnimation()
	elseif stateName == "DANCE" then
		self._humanoid.WalkSpeed = 3
		self._humanoid.AutoRotate = true
		self:_PlayDanceAnimation()
	elseif stateName == "SIT" then
		self._humanoid.WalkSpeed = 0
		self._humanoid.AutoRotate = false
		self:_PlaySitAnimation()
	else
		self._humanoid.WalkSpeed = 6
		self._humanoid.AutoRotate = true
		self:_PlayIdleAnimation()
	end
end

function NPCController:MoveTo(position)
	if self._humanoid then
		self._lastMoveToTarget = position
		if self._root then
			self:_DebugLog(
				"MoveTo target=(%.1f, %.1f, %.1f) dist=%.2f",
				position.X,
				position.Y,
				position.Z,
				(self._root.Position - position).Magnitude
			)
		end
		self._humanoid:MoveTo(position)
	end
end

function NPCController:GetMovementSnapshot()
	if not self._root or not self._humanoid then
		return 0, 0
	end

	local speed = self._root.AssemblyLinearVelocity.Magnitude
	local moveDir = self._humanoid.MoveDirection.Magnitude
	return speed, moveDir
end

function NPCController:StopMoving()
	if self._humanoid and self._root then
		self:_DebugLog("StopMoving at (%.1f, %.1f, %.1f)", self._root.Position.X, self._root.Position.Y, self._root.Position.Z)
		self._humanoid:MoveTo(self._root.Position)
	end
end

function NPCController:IsNearPosition(position, radius)
	if not self._root then
		return false
	end
	return (self._root.Position - position).Magnitude <= radius
end

function NPCController:CommandJump()
	if self._humanoid then
		self._humanoid.Jump = true
	end
end

function NPCController:CommandSit(sit)
	if not self._humanoid then
		return false
	end

	if not sit then
		self._humanoid.Sit = false
		self._currentSeat = nil
		return true
	end

	local seat = self:_FindNearestSeat(10)
	if not seat then
		return false
	end

	return self:TrySitAtSeat(seat)
end

function NPCController:_FindNearestSeat(maxDistance)
	if not self._root or not self._interestPointService or not self._interestPointService.FindNearestSeat then
		return nil
	end

	return self._interestPointService:FindNearestSeat(self._root.Position, maxDistance)
end

function NPCController:TrySitAtSeat(seat)
	if not self._humanoid or not seat or not seat:IsA("Seat") or not seat.Parent then
		return false
	end

	if self._root and (self._root.Position - seat.Position).Magnitude > 8 then
		self:MoveTo(seat.Position)
		return false
	end

	seat:Sit(self._humanoid)
	self._currentSeat = seat

	return self:IsSeatedOn(seat)
end

function NPCController:IsSeatedOn(seat)
	if not self._humanoid or not seat or not seat:IsA("Seat") then
		return false
	end

	return self._humanoid.SeatPart == seat
end

function NPCController:IsSeated()
	if not self._humanoid then
		return false
	end

	return self._humanoid.Sit or self._humanoid.SeatPart ~= nil
end

function NPCController:GetInterestPointTargetPosition(pointData)
	if self._interestPointService and self._interestPointService.GetTargetPosition then
		local position = self._interestPointService:GetTargetPosition(pointData)
		if position then
			return position
		end
	end

	return pointData and pointData.instance and pointData.instance.Position or nil
end

function NPCController:GetInterestPointApproachPosition(pointData, options)
	if typeof(options) == "number" then
		options = {
			minDistance = options,
			attempts = 8
		}
	end

	options = options or {}

	if self._interestPointService and self._interestPointService.GetRandomPointInVolume then
		local minDistance = tonumber(options.minDistance) or 0
		local attempts = math.max(1, tonumber(options.attempts) or 1)
		local best = nil
		local bestDistance = -1

		for _ = 1, attempts do
			local position = self._interestPointService:GetRandomPointInVolume(pointData)
			if position then
				if minDistance <= 0 or not self._root then
					return position
				end

				local distance = (self._root.Position - position).Magnitude
				if distance >= minDistance then
					return position
				end

				if distance > bestDistance then
					bestDistance = distance
					best = position
				end
			end
		end

		if best then
			return best
		end
	end

	return self:GetInterestPointTargetPosition(pointData)
end

function NPCController:GetIntelligenceTier()
	return self._intelligenceTier
end

function NPCController:FaceDirection(direction)
	if not self._root then
		return
	end

	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude <= 0 then
		return
	end

	local target = self._root.Position + horizontal.Unit
	self._root.CFrame = CFrame.new(self._root.Position, target)
end

return NPCController
