local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local CAMERA_TAG = "WitnessCamera"

local CameraWitnessSource = {}
CameraWitnessSource.__index = CameraWitnessSource

CameraWitnessSource.Config = {
	MaxDistance = 120,
	FieldOfViewDegrees = 65,
	MaxCamerasPerCheck = 8,
	CheckIntervalSeconds = 0.2,
	FovAttributeName = "WitnessFOV",
	RangeAttributeName = "WitnessRange",
	EnabledAttributeName = "WitnessEnabled"
}

function CameraWitnessSource.new(config)
	local self = setmetatable({}, CameraWitnessSource)

	config = config or {}
	self._maxDistance = tonumber(config.maxDistance) or CameraWitnessSource.Config.MaxDistance
	self._fovDegrees = tonumber(config.fieldOfViewDegrees) or CameraWitnessSource.Config.FieldOfViewDegrees
	self._maxCamerasPerCheck = tonumber(config.maxCamerasPerCheck) or CameraWitnessSource.Config.MaxCamerasPerCheck
	self._checkInterval = tonumber(config.checkIntervalSeconds) or CameraWitnessSource.Config.CheckIntervalSeconds
	self._fovAttributeName = tostring(config.fovAttributeName or CameraWitnessSource.Config.FovAttributeName)
	self._rangeAttributeName = tostring(config.rangeAttributeName or CameraWitnessSource.Config.RangeAttributeName)
	self._enabledAttributeName = tostring(config.enabledAttributeName or CameraWitnessSource.Config.EnabledAttributeName)
	self._lastCheckAtByActor = {}
	self._roundRobinIndex = 1

	return self
end

function CameraWitnessSource:_IsDebugEnabled()
	return Workspace:GetAttribute("WitnessDebugLogs") == true or Workspace:GetAttribute("NPCDebugLogs") == true
end

function CameraWitnessSource:_DebugLog(fmt, ...)
	if not self:_IsDebugEnabled() then
		return
	end

	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = tostring(fmt)
	end

	print(string.format("[CameraWitnessSource] %s", message))
end

function CameraWitnessSource:GetSourceId()
	return "camera"
end

function CameraWitnessSource:_GetActorRoot(actorPlayer)
	local character = actorPlayer and actorPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function CameraWitnessSource:_CanCheckActor(actorUserId, now)
	local last = self._lastCheckAtByActor[actorUserId]
	if last and now - last < self._checkInterval then
		return false
	end

	self._lastCheckAtByActor[actorUserId] = now
	return true
end

function CameraWitnessSource:_GetCameras()
	local cameras = {}
	for _, instance in ipairs(CollectionService:GetTagged(CAMERA_TAG)) do
		if instance:IsA("BasePart") and instance.Parent then
			table.insert(cameras, instance)
		end
	end
	return cameras
end

function CameraWitnessSource:_SelectCamerasForCheck(cameras)
	local total = #cameras
	if total <= self._maxCamerasPerCheck then
		return cameras
	end

	local selected = {}
	for i = 0, self._maxCamerasPerCheck - 1 do
		local index = ((self._roundRobinIndex + i - 1) % total) + 1
		table.insert(selected, cameras[index])
	end

	self._roundRobinIndex = ((self._roundRobinIndex + self._maxCamerasPerCheck - 1) % total) + 1
	return selected
end

function CameraWitnessSource:_HasLineOfSight(cameraPart, actorRoot)
	local direction = actorRoot.Position - cameraPart.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = {
		cameraPart,
		cameraPart.Parent,
		actorRoot.Parent
	}
	params.IgnoreWater = true

	local hit = Workspace:Raycast(cameraPart.Position, direction, params)
	if not hit then
		return true
	end

	return hit.Instance and hit.Instance:IsDescendantOf(actorRoot.Parent)
end

function CameraWitnessSource:_CanWitness(cameraPart, actorRoot)
	local enabled = cameraPart:GetAttribute(self._enabledAttributeName)
	if enabled == false then
		return false, "camera disabled"
	end

	local effectiveMaxDistance = tonumber(cameraPart:GetAttribute(self._rangeAttributeName)) or self._maxDistance
	effectiveMaxDistance = math.max(1, effectiveMaxDistance)

	local effectiveFov = tonumber(cameraPart:GetAttribute(self._fovAttributeName)) or self._fovDegrees
	effectiveFov = math.clamp(effectiveFov, 5, 179)

	local toActor = actorRoot.Position - cameraPart.Position
	local distance = toActor.Magnitude
	if distance <= 0 or distance > effectiveMaxDistance then
		return false, string.format("distance %.1f > %.1f", distance, effectiveMaxDistance)
	end

	local lookDir = cameraPart.CFrame.LookVector
	local cosThreshold = math.cos(math.rad(effectiveFov * 0.5))
	local dot = lookDir:Dot(toActor.Unit)
	if dot < cosThreshold then
		return false, string.format("fov dot %.3f < %.3f", dot, cosThreshold)
	end

	if not self:_HasLineOfSight(cameraPart, actorRoot) then
		return false, "line of sight blocked"
	end

	return true, string.format("ok dist=%.1f dot=%.3f fov=%.1f range=%.1f", distance, dot, effectiveFov, effectiveMaxDistance)
end

function CameraWitnessSource:Evaluate(payload, now)
	local actorPlayer = payload.actorPlayer
	if not actorPlayer then
		return {}
	end

	if not self:_CanCheckActor(actorPlayer.UserId, now) then
		return {}
	end

	local actorRoot = self:_GetActorRoot(actorPlayer)
	if not actorRoot then
		return {}
	end

	local cameras = self:_GetCameras()
	if #cameras == 0 then
		self:_DebugLog("Evaluate actor=%s -> no tagged cameras", actorPlayer.Name)
		return {}
	end

	cameras = self:_SelectCamerasForCheck(cameras)
	self:_DebugLog("Evaluate actor=%s camerasChecked=%d", actorPlayer.Name, #cameras)

	local witnesses = {}
	for _, cameraPart in ipairs(cameras) do
		local canWitness, reason = self:_CanWitness(cameraPart, actorRoot)
		if canWitness then
			self:_DebugLog("Camera %s witness ok (%s)", cameraPart:GetFullName(), tostring(reason))
			table.insert(witnesses, {
				source = "camera",
				cameraName = cameraPart.Name,
				cameraPart = cameraPart
			})
		else
			self:_DebugLog("Camera %s rejected (%s)", cameraPart:GetFullName(), tostring(reason))
		end
	end

	return witnesses
end

return CameraWitnessSource
