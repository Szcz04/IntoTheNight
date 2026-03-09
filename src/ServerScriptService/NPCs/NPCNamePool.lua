local NPCNamePool = {}
NPCNamePool.__index = NPCNamePool

-- Add or replace names here to control NPC display names.
local DEFAULT_NAMES = {
	"Alex",
	"Jamie",
	"Taylor",
	"Morgan",
	"Riley",
	"Casey",
	"Jordan",
	"Avery",
	"Quinn",
	"Cameron",
	"Parker",
	"Reese"
}

function NPCNamePool.new(initialNames)
	local self = setmetatable({}, NPCNamePool)

	self._names = {}
	self._nextIndex = 1

	local sourceNames = initialNames or DEFAULT_NAMES
	for _, name in ipairs(sourceNames) do
		if typeof(name) == "string" and #name > 0 then
			table.insert(self._names, name)
		end
	end

	return self
end

function NPCNamePool:GetNextName(npcId)
	if #self._names == 0 then
		return string.format("Guest %02d", npcId)
	end

	local name = self._names[self._nextIndex]
	self._nextIndex = self._nextIndex + 1
	if self._nextIndex > #self._names then
		self._nextIndex = 1
	end

	return name
end

function NPCNamePool:SetNames(names)
	self._names = {}
	self._nextIndex = 1

	for _, name in ipairs(names or {}) do
		if typeof(name) == "string" and #name > 0 then
			table.insert(self._names, name)
		end
	end
end

return NPCNamePool
