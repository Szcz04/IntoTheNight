local Players = game:GetService("Players")

local AvatarPool = {}
AvatarPool.__index = AvatarPool

local FALLBACK_USER_IDS = {
	1,
	261,
	48103520,
	156,
	20573078,
	124012122
}

function AvatarPool.new()
	local self = setmetatable({}, AvatarPool)

	self._descriptions = {}
	self._nextIndex = 1

	return self
end

function AvatarPool:BuildFromCurrentPlayers()
	self._descriptions = {}
	self._nextIndex = 1

	local collectedUserIds = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(collectedUserIds, player.UserId)
	end

	for _, userId in ipairs(FALLBACK_USER_IDS) do
		table.insert(collectedUserIds, userId)
	end

	for _, userId in ipairs(collectedUserIds) do
		local ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)

		if ok and description then
			table.insert(self._descriptions, description)
		end
	end

	print(string.format("[AvatarPool] Built avatar pool with %d descriptions", #self._descriptions))
end

function AvatarPool:GetNextDescription()
	if #self._descriptions == 0 then
		self:BuildFromCurrentPlayers()
	end

	if #self._descriptions == 0 then
		return nil
	end

	local description = self._descriptions[self._nextIndex]
	self._nextIndex = self._nextIndex + 1
	if self._nextIndex > #self._descriptions then
		self._nextIndex = 1
	end

	return description
end

return AvatarPool
