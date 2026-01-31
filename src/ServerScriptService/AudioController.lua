--[[
	AudioController: Simple audio feedback for game events
	
	Plays sounds in response to power state changes.
	Nothing fancy. Just immediate feedback.
]]

local SoundService = game:GetService("SoundService")

local AudioController = {}
AudioController.__index = AudioController

function AudioController.new(powerManager)
	local self = setmetatable({}, AudioController)
	
	self._powerManager = powerManager
	
	-- Subscribe to power state changes
	self._powerManager.PowerStateChanged.Event:Connect(function(newState, oldState)
		self:_OnPowerStateChanged(newState, oldState)
	end)
	
	return self
end

-- React to power state changes
function AudioController:_OnPowerStateChanged(newState, oldState)
	local PowerStates = require(script.Parent.PowerManager).PowerStates
	
	if newState == PowerStates.OFF then
		self:_PlayBlackoutSound()
	elseif newState == PowerStates.ON then
		self:_PlayPowerRestoredSound()
	end
end

-- Play sound when power cuts
function AudioController:_PlayBlackoutSound()
	print("[AudioController] POWER OUT - *electrical buzz*")
	-- TODO: Replace with actual sound asset when available
	-- For now, just a log. In Roblox, you'd create a Sound instance:
	-- local sound = Instance.new("Sound")
	-- sound.SoundId = "rbxassetid://XXXXXXX"
	-- sound.Parent = SoundService
	-- sound:Play()
end

-- Play sound when power restored
function AudioController:_PlayPowerRestoredSound()
	print("[AudioController] Power restored - *lights hum*")
	-- TODO: Replace with actual sound asset when available
end

return AudioController
