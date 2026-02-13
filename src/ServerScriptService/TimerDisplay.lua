--[[
	TimerDisplay: Physical 3D timer showing countdown to death
	
	Displays remaining time from PowerManager on a SurfaceGui in the train.
	- Shows MM:SS format
	- Turns red and flashes when < 10 seconds remaining
	- Updates every frame during blackout
	
	Usage: Tag a Part in workspace with "TimerDisplay" tag,
	       or this module will find/create display automatically.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TimerDisplay = {}
TimerDisplay.__index = TimerDisplay

function TimerDisplay.new(powerManager)
	local self = setmetatable({}, TimerDisplay)
	
	self._powerManager = powerManager
	
	-- Display state
	self._displayPart = nil
	self._surfaceGui = nil
	self._timeLabel = nil
	self._pointLight = nil -- Small light to illuminate text in darkness
	
	-- Flash state for low time warning
	self._flashConnection = nil
	self._flashTimer = 0
	
	-- Find or create display
	self:_SetupDisplay()
	
	-- Subscribe to power timer ticks
	self._powerManager.PowerTimerTick.Event:Connect(function(timeRemaining)
		self:_UpdateDisplay(timeRemaining)
	end)
	
	-- Subscribe to power state changes
	self._powerManager.PowerStateChanged.Event:Connect(function(newState, oldState)
		self:_OnPowerStateChanged(newState, oldState)
	end)
	
	-- Set initial display based on power state
	local PowerStates = require(script.Parent.PowerManager).PowerStates
	if self._powerManager:GetPowerState() == PowerStates.ON then
		-- Power is ON: clear display
		if self._timeLabel then
			self._timeLabel.Text = ""
		end
	else
		-- Power is OFF: show remaining time
		self:_UpdateDisplay(self._powerManager:GetTimeRemaining())
	end
	
	print("[TimerDisplay] Timer display initialized")
	
	return self
end

-- Find or create the display Part with SurfaceGui
function TimerDisplay:_SetupDisplay()
	-- Try to find existing display with tag
	local taggedDisplays = CollectionService:GetTagged("TimerDisplay")
	if #taggedDisplays > 0 then
		self._displayPart = taggedDisplays[1]
		print("[TimerDisplay] Found existing display:", self._displayPart.Name)
	else
		warn("[TimerDisplay] No Part with 'TimerDisplay' tag found. Create a Part and tag it, or display will not show.")
		return
	end
	
	-- Find or create SurfaceGui
	self._surfaceGui = self._displayPart:FindFirstChildOfClass("SurfaceGui")
	if not self._surfaceGui then
		self._surfaceGui = Instance.new("SurfaceGui")
		self._surfaceGui.Face = Enum.NormalId.Front
		self._surfaceGui.AlwaysOnTop = false
		self._surfaceGui.Parent = self._displayPart
		print("[TimerDisplay] Created SurfaceGui")
	end
	
	-- Find or create TextLabel
	self._timeLabel = self._surfaceGui:FindFirstChildOfClass("TextLabel")
	if not self._timeLabel then
		self._timeLabel = Instance.new("TextLabel")
		self._timeLabel.Size = UDim2.new(1, 0, 1, 0)
		self._timeLabel.BackgroundTransparency = 1
		self._timeLabel.Font = Enum.Font.Code
		self._timeLabel.TextScaled = true
		self._timeLabel.TextColor3 = Color3.fromRGB(255, 0, 0) -- Default: Red
		
		-- Add bright stroke/outline for visibility in darkness
		self._timeLabel.TextStrokeTransparency = 0.3
		self._timeLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255) -- White glow
		
		self._timeLabel.Text = "60:00"
		self._timeLabel.Parent = self._surfaceGui
		print("[TimerDisplay] Created TextLabel")
	else
		-- Add stroke to existing label if not present
		if self._timeLabel.TextStrokeTransparency > 0.9 then
			self._timeLabel.TextStrokeTransparency = 0.3
			self._timeLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		end
		print("[TimerDisplay] Using existing TextLabel (preserving custom colors/fonts)")
	end
	
	-- Find or create SurfaceLight for illumination in darkness
	-- SurfaceLight is more stable than PointLight - it shines from the Face of the Part
	self._pointLight = self._displayPart:FindFirstChildOfClass("SurfaceLight")
	if not self._pointLight then
		self._pointLight = Instance.new("SurfaceLight")
		self._pointLight.Name = "TimerDisplayLight" -- Unique name to identify it
		self._pointLight.Face = self._surfaceGui.Face -- Same face as the GUI
		self._pointLight.Brightness = 2
		self._pointLight.Range = 8
		self._pointLight.Color = Color3.fromRGB(255, 50, 50) -- Dim red glow
		self._pointLight.Angle = 120 -- Wide angle to cover text
		self._pointLight.Enabled = false -- Start disabled
		self._pointLight.Parent = self._displayPart
		print("[TimerDisplay] Created SurfaceLight")
	end
	
	-- Add attribute to mark this light as timer-specific (so LightingController ignores it)
	self._pointLight:SetAttribute("TimerLight", true)
end

-- Update the display with current time remaining
function TimerDisplay:_UpdateDisplay(timeRemaining)
	if not self._timeLabel then
		return -- No display available
	end
	
	-- Format time as MM:SS
	local minutes = math.floor(timeRemaining / 60)
	local seconds = math.floor(timeRemaining % 60)
	local timeText = string.format("%02d:%02d", minutes, seconds)
	
	self._timeLabel.Text = timeText
	
	-- Flashing when critical (< 10s)
	if timeRemaining <= 10 then
		if not self._flashConnection then
			self:_StartFlashing()
		end
	else
		self:_StopFlashing()
	end
end

-- React to power state changes
function TimerDisplay:_OnPowerStateChanged(newState, oldState)
	local PowerStates = require(script.Parent.PowerManager).PowerStates
	
	if newState == PowerStates.ON then
		-- Power restored: clear display
		if self._timeLabel then
			self._timeLabel.Text = "" -- Nothing displayed when power is ON
		end
		self:_StopFlashing()
		
		-- Reset Part material to default and disable light
		if self._displayPart then
			self._displayPart.Material = Enum.Material.SmoothPlastic
		end
		
		if self._pointLight then
			self._pointLight.Enabled = false
		end
		
	elseif newState == PowerStates.OFF then
		-- Blackout started: show countdown and change Part to black Neon
		self:_UpdateDisplay(self._powerManager:GetTimeRemaining())
		
		if self._displayPart then
			self._displayPart.Material = Enum.Material.Neon
			self._displayPart.Color = Color3.fromRGB(0, 0, 0) -- Black
		end
		
		-- Enable PointLight to illuminate text in darkness
		if self._pointLight then
			self._pointLight.Enabled = true
		end
	end
end

-- Start flashing effect for critical time
function TimerDisplay:_StartFlashing()
	if self._flashConnection then
		return -- Already flashing
	end
	
	self._flashTimer = 0
	
	self._flashConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self._flashTimer = self._flashTimer + deltaTime
		
		-- Flash every 0.5 seconds
		if self._flashTimer >= 0.5 then
			self._flashTimer = 0
			
			-- Toggle visibility
			if self._timeLabel then
				self._timeLabel.TextTransparency = (self._timeLabel.TextTransparency == 0) and 0.5 or 0
			end
		end
	end)
end

-- Stop flashing effect
function TimerDisplay:_StopFlashing()
	if self._flashConnection then
		self._flashConnection:Disconnect()
		self._flashConnection = nil
		
		-- Reset transparency
		if self._timeLabel then
			self._timeLabel.TextTransparency = 0
		end
	end
end

return TimerDisplay
