--[[
	LightingController: Reacts to PowerManager state changes

	Controls individual lights in the train using CollectionService tags:
		- "TrainLight" = Main lights (ceiling, wall lights) - turn OFF during blackout
		- "EmergencyLight" = Red emergency lights - flicker irregularly during blackout
	
	Ambient lighting is dimmed but skybox remains visible through windows.
	Parts with Neon material are switched to SmoothPlastic when power is off.
	This module REACTS to power state, it doesn't control it.
]]

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LightingController = {}
LightingController.__index = LightingController

function LightingController.new(powerManager)
	local self = setmetatable({}, LightingController)
	
	self._powerManager = powerManager
	
	-- Store default ambient lighting values (global Lighting service)
	-- Power ON: Dark ambient so PointLights are the main light source
	self._defaultAmbient = Color3.fromRGB(20, 20, 25) -- Very dark, lights matter
	self._defaultOutdoorAmbient = Color3.fromRGB(40, 40, 60) -- Dim moonlight through windows
	self._defaultBrightness = 0.5 -- Low brightness, skybox visible but doesn't light interior
	
	-- Blackout ambient values (only slightly darker, ready for flashlight)
	self._blackoutAmbient = Color3.fromRGB(10, 10, 15) -- Slightly darker than power ON
	self._blackoutOutdoorAmbient = Color3.fromRGB(30, 30, 50) -- Moonlight still visible
	self._blackoutBrightness = 0.3 -- Slightly dimmer than power ON
	
	-- Track lights by tag
	self._trainLights = {} -- Main lights: { light = Light, part = Part }
	self._emergencyLights = {} -- Emergency lights: { light = Light, part = Part }
	
	-- Emergency light flicker state
	self._flickerConnection = nil
	self._flickerTimers = {} -- Per-light random timers
	
	-- Discover all tagged lights
	self:_DiscoverLights()
	
	-- Listen for new lights being added (dynamic loading)
	CollectionService:GetInstanceAddedSignal("TrainLight"):Connect(function(instance)
		self:_RegisterTrainLight(instance)
	end)
	
	CollectionService:GetInstanceAddedSignal("EmergencyLight"):Connect(function(instance)
		self:_RegisterEmergencyLight(instance)
	end)
	
	-- Subscribe to power state changes
	self._powerManager.PowerStateChanged.Event:Connect(function(newState, oldState)
		self:_OnPowerStateChanged(newState, oldState)
	end)
	
	-- Set initial lighting
	self:_ApplyLightingForPowerState(self._powerManager:GetPowerState())
	
	return self
end

-- Discover all existing lights in the workspace
function LightingController:_DiscoverLights()
	print("[LightingController] Discovering lights...")
	
	-- Find all TrainLight tagged objects
	for _, instance in CollectionService:GetTagged("TrainLight") do
		self:_RegisterTrainLight(instance)
	end
	
	-- Find all EmergencyLight tagged objects
	for _, instance in CollectionService:GetTagged("EmergencyLight") do
		self:_RegisterEmergencyLight(instance)
	end
	
	print(string.format("[LightingController] Found %d train lights, %d emergency lights", 
		#self._trainLights, #self._emergencyLights))
end

-- Register a train light (main lights)
function LightingController:_RegisterTrainLight(instance)
	local light = nil
	local part = nil
	
	-- Case 1: Tag is on a Part that contains a Light
	if instance:IsA("BasePart") then
		light = instance:FindFirstChildWhichIsA("Light")
		if light then
			-- Skip if this is the timer display light
			if light:GetAttribute("TimerLight") == true then
				print(string.format("[LightingController] ⊘ Skipping timer light in: %s", instance.Name))
				return
			end
			
			part = instance
			table.insert(self._trainLights, { light = light, part = part })
			print(string.format("[LightingController] ✓ Registered train light: %s (Light inside Part)", instance.Name))
		else
			warn(string.format("[LightingController] ✗ TrainLight tag on Part '%s' but no Light found inside!", instance.Name))
		end
	
	-- Case 2: Tag is directly on the Light object
	elseif instance:IsA("Light") then
		-- Skip if this is the timer display light
		if instance:GetAttribute("TimerLight") == true then
			print(string.format("[LightingController] ⊘ Skipping timer light: %s", instance.Name))
			return
		end
		
		light = instance
		part = light.Parent:IsA("BasePart") and light.Parent or nil
		table.insert(self._trainLights, { light = light, part = part })
		print(string.format("[LightingController] ✓ Registered train light: %s (Light directly tagged)", instance.Name))
	
	else
		warn(string.format("[LightingController] ✗ TrainLight tag on unsupported object type: %s (%s)", instance.Name, instance.ClassName))
	end
end

-- Register an emergency light
function LightingController:_RegisterEmergencyLight(instance)
	local light = nil
	local part = nil
	
	-- Case 1: Tag is on a Part that contains a Light
	if instance:IsA("BasePart") then
		light = instance:FindFirstChildWhichIsA("Light")
		if light then
			-- Skip if this is the timer display light
			if light:GetAttribute("TimerLight") == true then
				print(string.format("[LightingController] ⊘ Skipping timer light in: %s", instance.Name))
				return
			end
			
			part = instance
			table.insert(self._emergencyLights, { light = light, part = part })
			self._flickerTimers[light] = 0
			print(string.format("[LightingController] ✓ Registered emergency light: %s (Light inside Part)", instance.Name))
		else
			warn(string.format("[LightingController] ✗ EmergencyLight tag on Part '%s' but no Light found inside!", instance.Name))
		end
	
	-- Case 2: Tag is directly on the Light object
	elseif instance:IsA("Light") then
		-- Skip if this is the timer display light
		if instance:GetAttribute("TimerLight") == true then
			print(string.format("[LightingController] ⊘ Skipping timer light: %s", instance.Name))
			return
		end
		
		light = instance
		part = light.Parent:IsA("BasePart") and light.Parent or nil
		table.insert(self._emergencyLights, { light = light, part = part })
		self._flickerTimers[light] = 0
		print(string.format("[LightingController] ✓ Registered emergency light: %s (Light directly tagged)", instance.Name))
	
	else
		warn(string.format("[LightingController] ✗ EmergencyLight tag on unsupported object type: %s (%s)", instance.Name, instance.ClassName))
	end
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
		self:_PowerOn()
	elseif powerState == PowerStates.OFF then
		self:_Blackout()
	end
end

-- Turn on all lights (normal state)
function LightingController:_PowerOn()
	-- Turn on all train lights
	local trainLightsCount = 0
	for _, lightData in self._trainLights do
		lightData.light.Enabled = true
		lightData.light.Brightness = 1 -- Full brightness
		
		-- Set Part material to Neon (emissive)
		if lightData.part then
			lightData.part.Material = Enum.Material.Neon
		end
		
		trainLightsCount = trainLightsCount + 1
	end
	
	-- Turn off emergency lights and reset their Parts
	local emergencyLightsCount = 0
	for _, lightData in self._emergencyLights do
		lightData.light.Enabled = false
		
		-- Reset Part material to SmoothPlastic (in case it was stuck as Neon during flicker)
		if lightData.part then
			lightData.part.Material = Enum.Material.SmoothPlastic
		end
		
		emergencyLightsCount = emergencyLightsCount + 1
	end
	
	-- Stop emergency light flicker
	self:_StopFlicker()
	
	-- Restore normal ambient lighting
	Lighting.Ambient = self._defaultAmbient
	Lighting.OutdoorAmbient = self._defaultOutdoorAmbient
	Lighting.Brightness = self._defaultBrightness
	Lighting.ClockTime = 20 -- Evening
	
	print(string.format("[LightingController] Lights ON - %d train lights enabled, %d emergency lights disabled", 
		trainLightsCount, emergencyLightsCount))
end

-- Blackout state (power off)
function LightingController:_Blackout()
	-- Turn off all main train lights
	local disabledCount = 0
	for _, lightData in self._trainLights do
		lightData.light.Enabled = false
		
		-- Set Part material to SmoothPlastic (non-emissive)
		if lightData.part then
			lightData.part.Material = Enum.Material.SmoothPlastic
		end
		
		disabledCount = disabledCount + 1
		print(string.format("[LightingController] Disabled train light: %s", lightData.light.Name))
	end
	
	-- Start emergency lights with irregular flicker
	self:_StartFlicker()
	
	-- Dim ambient lighting (but keep skybox visible)
	Lighting.Ambient = self._blackoutAmbient
	Lighting.OutdoorAmbient = self._blackoutOutdoorAmbient
	Lighting.Brightness = self._blackoutBrightness
	Lighting.ClockTime = 20 -- Evening
	
	print(string.format("[LightingController] BLACKOUT - %d train lights disabled, emergency lights flickering", disabledCount))
end

-- Start irregular emergency light flicker
function LightingController:_StartFlicker()
	if self._flickerConnection then
		return -- Already flickering
	end
	
	print("[LightingController] Starting emergency light flicker")
	
	-- Reset all timers
	for light, _ in pairs(self._flickerTimers) do
		self._flickerTimers[light] = math.random() * 2 -- Random initial delay 0-2 seconds
	end
	
	-- Flicker loop (runs every frame)
	self._flickerConnection = RunService.Heartbeat:Connect(function(deltaTime)
		for _, lightData in self._emergencyLights do
			local light = lightData.light
			local part = lightData.part
			
			-- Update timer for this light
			self._flickerTimers[light] = self._flickerTimers[light] - deltaTime
			
			-- When timer hits zero, toggle light and reset timer
			if self._flickerTimers[light] <= 0 then
				light.Enabled = not light.Enabled
				
				-- Change Part material based on light state
				if part then
					if light.Enabled then
						part.Material = Enum.Material.Neon
						part.Color = Color3.fromRGB(255, 0, 0) -- Red
					else
						part.Material = Enum.Material.SmoothPlastic
					end
				end
				
				-- Random brightness when on (dim/flickering effect)
				if light.Enabled then
					light.Brightness = 0.3 + (math.random() * 0.4) -- 0.3 to 0.7 brightness
				end
				
				-- Random delay until next flicker (irregular timing)
				if light.Enabled then
					self._flickerTimers[light] = 0.1 + (math.random() * 0.5) -- 0.1-0.6s on
				else
					self._flickerTimers[light] = 0.3 + (math.random() * 2) -- 0.3-2.3s off
				end
			end
		end
	end)
end

-- Stop emergency light flicker
function LightingController:_StopFlicker()
	if self._flickerConnection then
		self._flickerConnection:Disconnect()
		self._flickerConnection = nil
		print("[LightingController] Stopped emergency light flicker")
	end
end

return LightingController
