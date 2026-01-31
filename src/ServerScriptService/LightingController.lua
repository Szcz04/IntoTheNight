--[[
	LightingController: Reacts to PowerManager state changes
	
	Handles immediate, brutal lighting changes when power fails.
	No tweening. No polish. Just dark.
	
	This module REACTS to power state, it doesn't control it.
]]

local Lighting = game:GetService("Lighting")

local LightingController = {}
LightingController.__index = LightingController

function LightingController.new(powerManager)
	local self = setmetatable({}, LightingController)
	
	self._powerManager = powerManager
	
	-- Store default lighting values
	self._defaultBrightness = 2
	self._defaultAmbient = Color3.fromRGB(138, 138, 138)
	self._defaultOutdoorAmbient = Color3.fromRGB(127, 127, 127)
	
	-- Blackout values (brutal darkness)
	self._blackoutBrightness = 0
	self._blackoutAmbient = Color3.fromRGB(0, 0, 0)
	self._blackoutOutdoorAmbient = Color3.fromRGB(5, 5, 10) -- Slight blue tint for "moon"
	
	-- Subscribe to power state changes
	self._powerManager.PowerStateChanged.Event:Connect(function(newState, oldState)
		self:_OnPowerStateChanged(newState, oldState)
	end)
	
	-- Set initial lighting
	self:_ApplyLightingForPowerState(self._powerManager:GetPowerState())
	
	return self
end

-- React to power state changes
function LightingController:_OnPowerStateChanged(newState, oldState)
	print(string.format("[LightingController] Power changed: %s → %s", oldState, newState))
	self:_ApplyLightingForPowerState(newState)
end

-- Apply lighting based on power state
function LightingController:_ApplyLightingForPowerState(powerState)
	local PowerStates = require(script.Parent.PowerManager).PowerStates
	
	if powerState == PowerStates.ON then
		-- Power is on: normal lighting
		Lighting.Brightness = self._defaultBrightness
		Lighting.Ambient = self._defaultAmbient
		Lighting.OutdoorAmbient = self._defaultOutdoorAmbient
		Lighting.ClockTime = 12 -- Daytime
		print("[LightingController] Lights ON")
		
	elseif powerState == PowerStates.OFF then
		-- Power is off: brutal darkness
		Lighting.Brightness = self._blackoutBrightness
		Lighting.Ambient = self._blackoutAmbient
		Lighting.OutdoorAmbient = self._blackoutOutdoorAmbient
		Lighting.ClockTime = 0 -- Midnight
		print("[LightingController] LIGHTS OFF - BLACKOUT")
	end
end

return LightingController
