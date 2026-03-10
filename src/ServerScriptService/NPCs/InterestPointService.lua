local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local InterestPointService = {}
InterestPointService.__index = InterestPointService

local DEBUG_LOG_ATTRIBUTE = "NPCDebugLogs"

local function isDebugEnabled()
	return Workspace:GetAttribute(DEBUG_LOG_ATTRIBUTE) == true
end

local function debugLog(fmt, ...)
	if not isDebugEnabled() then
		return
	end

	local ok, message = pcall(string.format, fmt, ...)
	if not ok then
		message = tostring(fmt)
	end

	print(string.format("[InterestPointService] %s", message))
end

function InterestPointService.new()
	local self = setmetatable({}, InterestPointService)

	self._points = {}

	self:_Discover()
	self:_BindDynamicPoints()

	return self
end

function InterestPointService:_BindDynamicPoints()
	CollectionService:GetInstanceAddedSignal("NPCInterestPoint"):Connect(function(instance)
		self:_RegisterPoint(instance)
	end)

	CollectionService:GetInstanceRemovedSignal("NPCInterestPoint"):Connect(function(instance)
		self:_UnregisterPoint(instance)
	end)
end

function InterestPointService:_Discover()
	for _, instance in ipairs(CollectionService:GetTagged("NPCInterestPoint")) do
		self:_RegisterPoint(instance)
	end
end

function InterestPointService:_RegisterPoint(instance)
	if not instance:IsA("BasePart") then
		return
	end

	if self._points[instance] then
		return
	end

	local pointType = instance:GetAttribute("Type") or "Idle"
	local capacity = tonumber(instance:GetAttribute("Capacity")) or 3
	capacity = math.max(1, math.floor(capacity))
	local sitDuration = tonumber(instance:GetAttribute("SitDuration")) or 6
	local approachRadius = tonumber(instance:GetAttribute("ApproachRadius")) or 4
	local seat = self:_ResolveSeatForPoint(instance)

	self._points[instance] = {
		instance = instance,
		type = tostring(pointType),
		capacity = capacity,
		occupants = {},
		sitDuration = math.max(1, sitDuration),
		approachRadius = math.max(2, approachRadius),
		seat = seat,
		searchPosition = seat and seat.Position or instance.Position
	}

	debugLog("Registered point name=%s type=%s capacity=%d", instance.Name, tostring(pointType), capacity)
end

function InterestPointService:_ResolveSeatForPoint(instance)
	if instance:IsA("Seat") then
		return instance
	end

	local seatName = instance:GetAttribute("SeatName")
	if typeof(seatName) == "string" and #seatName > 0 then
		local named = instance:FindFirstChild(seatName, true)
		if named and named:IsA("Seat") then
			return named
		end
	end

	return instance:FindFirstChildWhichIsA("Seat", true)
end

function InterestPointService:_UnregisterPoint(instance)
	self._points[instance] = nil
end

function InterestPointService:ReleasePoint(pointData, npcId)
	if not pointData or not pointData.instance then
		return
	end

	local point = self._points[pointData.instance]
	if not point then
		return
	end

	point.occupants[npcId] = nil
end

function InterestPointService:ClaimBestPoint(npcId, preferredTypes)
	return self:ClaimBestPointConstrained(npcId, preferredTypes, nil)
end

function InterestPointService:ClaimBestPointConstrained(npcId, preferredTypes, constraints)
	local candidates = {}
	constraints = constraints or {}
	local origin = constraints.origin
	local maxDistance = constraints.maxDistance
	local maxDistanceSquared = maxDistance and (maxDistance * maxDistance) or nil
	local lockedPoint = constraints.lockedPoint
	local requireSeat = constraints.requireSeat
	local avoidPoint = constraints.avoidPoint
	local rejectedByCapacity = 0
	local rejectedByDistance = 0

	for _, point in pairs(self._points) do
		if lockedPoint and point.instance ~= lockedPoint then
			continue
		end

		if avoidPoint and point.instance == avoidPoint then
			continue
		end

		if requireSeat and not point.seat then
			continue
		end

		local occupantCount = 0
		for _ in pairs(point.occupants) do
			occupantCount = occupantCount + 1
		end

		if occupantCount < point.capacity then
			if origin and maxDistanceSquared then
				local targetPos = self:_GetPointSearchPositionForOrigin(point, origin)
				if targetPos then
					local offset = targetPos - origin
					local distanceSquared = offset.X * offset.X + offset.Z * offset.Z
					if distanceSquared > maxDistanceSquared then
						rejectedByDistance = rejectedByDistance + 1
						continue
					end
				end
				if not targetPos then
					rejectedByDistance = rejectedByDistance + 1
					continue
				end
			end

			local preferredScore = 0
			if preferredTypes then
				for index, typeName in ipairs(preferredTypes) do
					if point.type == typeName then
						preferredScore = 100 - index
						break
					end
				end
			end

			table.insert(candidates, {
				point = point,
				score = preferredScore + math.random()
			})
		end

		if occupantCount >= point.capacity then
			rejectedByCapacity = rejectedByCapacity + 1
		end
	end

	if #candidates == 0 then
		debugLog(
			"ClaimMiss npc=%s preferred=%s maxDistance=%s reason=no_candidates distReject=%d capReject=%d",
			tostring(npcId),
			preferredTypes and table.concat(preferredTypes, ",") or "nil",
			tostring(maxDistance),
			rejectedByDistance,
			rejectedByCapacity
		)
		return nil
	end

	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	local chosen = candidates[1].point
	chosen.occupants[npcId] = true
	debugLog(
		"Claim npc=%s point=%s type=%s preferred=%s maxDistance=%s",
		tostring(npcId),
		chosen.instance and chosen.instance.Name or "?",
		tostring(chosen.type),
		preferredTypes and table.concat(preferredTypes, ",") or "nil",
		tostring(maxDistance)
	)
	return chosen
end

function InterestPointService:_GetPointSearchPosition(pointData)
	if not pointData then
		return nil
	end

	if (not pointData.seat or not pointData.seat.Parent) and pointData.instance and pointData.instance.Parent then
		pointData.seat = self:_ResolveSeatForPoint(pointData.instance)
	end

	if pointData.seat and pointData.seat.Parent then
		pointData.searchPosition = pointData.seat.Position
		return pointData.searchPosition
	end

	if pointData.instance and pointData.instance.Parent then
		pointData.searchPosition = pointData.instance.Position
		return pointData.searchPosition
	end

	return nil
end

function InterestPointService:_GetPointSearchPositionForOrigin(pointData, origin)
	if not pointData then
		return nil
	end

	if not origin then
		return self:_GetPointSearchPosition(pointData)
	end

	if (not pointData.seat or not pointData.seat.Parent) and pointData.instance and pointData.instance.Parent then
		pointData.seat = self:_ResolveSeatForPoint(pointData.instance)
	end

	if pointData.seat and pointData.seat.Parent then
		pointData.searchPosition = pointData.seat.Position
		return pointData.searchPosition
	end

	local part = pointData.instance
	if part and part.Parent then
		local localPoint = part.CFrame:PointToObjectSpace(origin)
		local half = part.Size * 0.5
		local clamped = Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
		local closest = part.CFrame:PointToWorldSpace(clamped)
		pointData.searchPosition = closest
		return closest
	end

	return nil
end

function InterestPointService:GetTargetPosition(pointData)
	if not pointData then
		return nil
	end

	if (not pointData.seat or not pointData.seat.Parent) and pointData.instance and pointData.instance.Parent then
		pointData.seat = self:_ResolveSeatForPoint(pointData.instance)
	end

	if pointData.seat and pointData.seat.Parent then
		pointData.searchPosition = pointData.seat.Position
		return pointData.seat.Position
	end

	if pointData.instance and pointData.instance.Parent then
		pointData.searchPosition = pointData.instance.Position
		return pointData.instance.Position
	end

	return nil
end

function InterestPointService:GetRandomPointInVolume(pointData)
	if not pointData then
		return nil
	end

	if pointData.seat and pointData.seat.Parent then
		return pointData.seat.Position
	end

	local part = pointData.instance
	if not part or not part.Parent then
		return nil
	end

	local halfSize = part.Size * 0.5
	local randomX = (math.random() * 2 - 1) * halfSize.X
	local randomZ = (math.random() * 2 - 1) * halfSize.Z
	local localOffset = Vector3.new(
		randomX,
		(math.random() * 2 - 1) * halfSize.Y,
		randomZ
	)

	local rayOrigin = part.CFrame:PointToWorldSpace(Vector3.new(randomX, halfSize.Y + 8, randomZ))
	local rayDirection = Vector3.new(0, -(part.Size.Y + 40), 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignore = {}
	local npcFolder = Workspace:FindFirstChild("NPCGuests")
	if npcFolder then
		table.insert(ignore, npcFolder)
	end
	raycastParams.FilterDescendantsInstances = ignore

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local world = nil
	if result then
		world = result.Position
	else
		world = part.CFrame:PointToWorldSpace(localOffset)
	end

	if string.lower(tostring(pointData.type or "")) == "dance" then
		debugLog(
			"RandomPoint dance point=%s sampled=(%.1f, %.1f, %.1f)",
			part.Name,
			world.X,
			world.Y,
			world.Z
		)
	end

	return world
end

function InterestPointService:FindNearestSeat(position, maxDistance)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local bestSeat = nil
	local bestDistance = maxDistance or 12

	for _, point in pairs(self._points) do
		local seat = point.seat
		if seat and seat.Parent and not seat.Occupant then
			local distance = (seat.Position - position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				bestSeat = seat
			end
		end
	end

	return bestSeat
end

return InterestPointService
