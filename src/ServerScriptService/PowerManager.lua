--[[
	PowerManager: Controls the power state and blackout logic
	
	PowerState:
		ON  - Power is active, lights work
		OFF - Blackout, darkness, danger
	
	Tracks time without power. Does NOT manipulate Lighting directly.
	Other systems react to power state changes.

	PROJECT DIRECTION NOTES:
	- Keep as house infrastructure state (lights/music/security), not only death timer.
	- TODO: treat blackout as stealth opportunity/risk (suspicion modifier), not hard fail.
	- TODO: expose sabotage-friendly APIs (temporary outage, localized outage, recovery delay).
]]

local PowerManager = {}
PowerManager.__index = PowerManager

-- Power state enum
PowerManager.PowerStates = {
	ON = "ON",
	OFF = "OFF"
}

function PowerManager.new()
	local self = setmetatable({}, PowerManager)
	
	-- Current power state
	self._powerState = PowerManager.PowerStates.ON
	
	-- Time tracking
	self._timeWithoutPower = 0
	self._maxTimeWithoutPower = 60 -- 60 seconds until death
	
	-- Events
	self.PowerStateChanged = Instance.new("BindableEvent")
	self.PowerTimerTick = Instance.new("BindableEvent") -- Fires each second while power is off
	self.PowerTimeout = Instance.new("BindableEvent") -- Fires when time runs out
	
	-- Internal timer
	self._timerRunning = false
	self._timerConnection = nil
	
	return self
end

-- Get current power state
function PowerManager:GetPowerState()
	return self._powerState
end

-- Get remaining time without power
function PowerManager:GetTimeRemaining()
	return math.max(0, self._maxTimeWithoutPower - self._timeWithoutPower)
end

-- Set power state (ON or OFF)
function PowerManager:SetPowerState(newState)
	if self._powerState == newState then
		return
	end
	
	local oldState = self._powerState
	self._powerState = newState
	
	print(string.format("[PowerManager] Power: %s → %s", oldState, newState))
	
	-- Broadcast change
	self.PowerStateChanged:Fire(newState, oldState)
	
	-- Start or stop timer
	if newState == PowerManager.PowerStates.OFF then
		self:_StartTimer()
	else
		self:_StopTimer()
		self._timeWithoutPower = 0 -- Reset timer when power restored
	end
end

-- Cut power (shorthand for SetPowerState(OFF))
function PowerManager:CutPower()
	self:SetPowerState(PowerManager.PowerStates.OFF)
end

-- Restore power (shorthand for SetPowerState(ON))
function PowerManager:RestorePower()
	self:SetPowerState(PowerManager.PowerStates.ON)
end

-- Add penalty time (for wrong lever sequence, etc.)
function PowerManager:AddPenaltyTime(seconds)
	if self._powerState == PowerManager.PowerStates.OFF then
		self._timeWithoutPower = self._timeWithoutPower + seconds
		print(string.format("[PowerManager] Added %ds penalty. New time without power: %.1fs", 
			seconds, self._timeWithoutPower))
		
		-- Immediately check if this puts us over the limit
		if self._timeWithoutPower >= self._maxTimeWithoutPower then
			print("[PowerManager] Penalty caused timeout!")
			self.PowerTimeout:Fire()
			self:_StopTimer()
		end
	end
end

-- Start the death timer
function PowerManager:_StartTimer()
	if self._timerRunning then
		return
	end
	
	self._timerRunning = true
	self._timeWithoutPower = 0
	
	print("[PowerManager] Timer started. Death in " .. self._maxTimeWithoutPower .. " seconds")
	
	-- Tick every second
	self._timerConnection = game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
		if self._powerState == PowerManager.PowerStates.OFF then
			self._timeWithoutPower = self._timeWithoutPower + deltaTime
			
			-- Broadcast tick (other systems can use this for UI updates)
			self.PowerTimerTick:Fire(self:GetTimeRemaining())
			
			-- Check if time is up
			if self._timeWithoutPower >= self._maxTimeWithoutPower then
				print("[PowerManager] TIME'S UP. Players are dead.")
				self.PowerTimeout:Fire()
				self:_StopTimer()
			end
		end
	end)
end

-- Stop the death timer
function PowerManager:_StopTimer()
	if not self._timerRunning then
		return
	end
	
	self._timerRunning = false
	
	if self._timerConnection then
		self._timerConnection:Disconnect()
		self._timerConnection = nil
	end
	
	print("[PowerManager] Timer stopped")
end

-- Reset the manager (call when round ends)
function PowerManager:Reset()
	self:_StopTimer()
	self._timeWithoutPower = 0
	self._powerState = PowerManager.PowerStates.ON
	print("[PowerManager] Reset to default state")
end

return PowerManager
