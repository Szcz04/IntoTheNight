--[[
	⚠️ DEPRECATED - NIE UŻYWANY ⚠️
	
	Ten skrypt jest przestarzały i nie jest już używany.
	Flashlight jest teraz zarządzany SERVER-SIDE przez:
		- FlashlightController.lua (server)
		- FlashlightClient.client.lua (client UI/sounds)
	
	Zachowany tylko do referencji. Można usunąć.
	
	---
	
	FlashlightEquip: Client-side flashlight equip system (OLD)
	
	Double-click on flashlight in inventory to equip/unequip
	Left click to toggle light on/off
	Uses Tool system for hand positioning
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local equippedFlashlight = nil -- Currently equipped Tool
local isLightOn = false
local currentCharge = 0.5 -- Default 50% charge
local chargeDecals = {} -- Array of 4 decals for charge display

-- Flashlight configuration
local LIGHT_COLOR = Color3.fromRGB(255, 240, 200) -- Warm white
local LIGHT_BRIGHTNESS = 2
local LIGHT_RANGE = 40
local CHARGE_DRAIN_RATE = 0.01 -- 1% per second when light is on

-- Sound IDs (placeholders - replace with actual sound IDs)
local SOUND_FLASHLIGHT_ON = "rbxasset://sounds/switch.wav" -- Replace with your sound ID
local SOUND_FLASHLIGHT_OFF = "rbxasset://sounds/switch.wav" -- Replace with your sound ID
local SOUND_BATTERY_EMPTY = "rbxasset://sounds/button.wav" -- Replace with your sound ID

-- Play a sound
local function playSound(soundId)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.5
	sound.Parent = workspace
	sound:Play()
	
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- Create 4 charge indicator parts on flashlight handle
local function createChargeDecals(handle)
	-- Clear old indicators
	for _, indicator in ipairs(chargeDecals) do
		if indicator then indicator:Destroy() end
	end
	chargeDecals = {}
	
	-- Create 4 small colored parts on top of handle as charge indicators
	local handleSize = handle.Size
	local spacing = 0.15 -- Space between indicators
	local indicatorWidth = 0.2
	local indicatorHeight = 0.05
	local indicatorDepth = 0.2
	
	for i = 1, 4 do
		local indicator = Instance.new("Part")
		indicator.Name = "ChargeIndicator" .. i
		indicator.Size = Vector3.new(indicatorWidth, indicatorHeight, indicatorDepth)
		indicator.Color = Color3.fromRGB(0, 255, 0) -- Green when charged
		indicator.Material = Enum.Material.Neon
		indicator.Anchored = false
		indicator.CanCollide = false
		
		-- Position on top of handle, spread horizontally
		local xOffset = (i - 2.5) * spacing
		indicator.CFrame = handle.CFrame * CFrame.new(xOffset, handleSize.Y/2 + indicatorHeight/2, 0)
		
		-- Weld to handle
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = indicator
		weld.Parent = indicator
		
		indicator.Parent = handle
		chargeDecals[i] = indicator
	end
	
	print("[FlashlightEquip] Created " .. #chargeDecals .. " charge indicators")
end

-- Update charge indicators based on current charge level
local function updateChargeDecals()
	local chargePercent = currentCharge * 100
	
	for i = 1, 4 do
		local threshold = (5 - i) * 25 -- 75%, 50%, 25%, 0%
		
		if chargePercent > threshold then
			-- Show this indicator (green/bright)
			if chargeDecals[i] then
				chargeDecals[i].Transparency = 0
				chargeDecals[i].Color = Color3.fromRGB(0, 255, 0) -- Green
				chargeDecals[i].Material = Enum.Material.Neon
			end
		else
			-- Dim this indicator
			if chargeDecals[i] then
				chargeDecals[i].Transparency = 0.5
				chargeDecals[i].Color = Color3.fromRGB(50, 50, 50) -- Dark gray
				chargeDecals[i].Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

-- GRIP SETTINGS - eksperymentuj z tymi wartościami!
-- Format: CFrame.new(X, Y, Z) * CFrame.Angles(X_rot, Y_rot, Z_rot)
-- X_rot: obrót góra/dół (pitch) - użyj math.rad(stopnie)
-- Y_rot: obrót lewo/prawo (yaw)
-- Z_rot: obrót na boki (roll)
local GRIP_OFFSET = CFrame.new(0, 3, 0.5) -- przesunięcie od ręki
local GRIP_ROTATION = CFrame.Angles(math.rad(0), math.rad(-90), math.rad(0)) -- obrót: (pitch, yaw, roll)
-- Spróbuj: (0, 0, -90) dla obrotu w lewo, (0, 0, 90) dla obrotu w prawo
-- lub (0, 90, 0) lub (0, -90, 0) jeśli to nie działa

-- Create flashlight tool
local function createFlashlightTool()
	local tool = Instance.new("Tool")
	tool.Name = "Flashlight"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = GRIP_OFFSET * GRIP_ROTATION
	
	print("[FlashlightEquip] Grip: " .. tostring(tool.Grip))
	
	-- Try to use user's model from ReplicatedStorage
	local ItemModels = ReplicatedStorage:FindFirstChild("ItemModels")
	local flashlightModel = ItemModels and ItemModels:FindFirstChild("FlashlightModel")
	
	local handle, lens, spotlight
	
	if flashlightModel and flashlightModel:IsA("Model") then
		-- Clone user's model
		local modelClone = flashlightModel:Clone()
		
		print("[FlashlightEquip] Found model, parts:")
		for _, child in modelClone:GetDescendants() do
			if child:IsA("BasePart") then
				print("  - " .. child.Name)
			end
		end
		
		-- Find or create handle
		handle = modelClone:FindFirstChild("Handle") or modelClone:FindFirstChild("Core") or modelClone.PrimaryPart
		if not handle then
			-- Use first part as handle
			for _, child in modelClone:GetChildren() do
				if child:IsA("BasePart") then
					handle = child
					break
				end
			end
		end
		
		if handle then
			print("[FlashlightEquip] Using handle: " .. handle.Name)
			
			-- Najpierw obrót wszystkich części względem Handle
			-- (jeśli Grip nie działa, obracamy sam model)
			local MANUAL_ROTATION = CFrame.Angles(math.rad(180), 0, math.rad(-90)) -- ZMIEŃ TEN KĄT!
			local handleCFrame = handle.CFrame
			
			for _, part in handle:GetDescendants() do
				if part:IsA("BasePart") and part ~= handle then
					-- Obrót względem centrum Handle
					local offset = handleCFrame:ToObjectSpace(part.CFrame)
					part.CFrame = handleCFrame * MANUAL_ROTATION * offset
				end
			end
			
			handle.Name = "Handle"
			handle.Parent = tool
			
			-- Move all other parts to handle
			for _, child in modelClone:GetChildren() do
				if child ~= handle then
					child.Parent = handle
				end
			end
			
			-- Find Lens part specifically (not LensHolder)
			lens = handle:FindFirstChild("Lens", true) -- Recursive search
			if not lens then
				lens = handle:FindFirstChild("LensHolder", true) or handle
			end
			
			print("[FlashlightEquip] Using lens: " .. lens.Name)
			print("[FlashlightEquip] Using custom model")
		end
		
		modelClone:Destroy()
	end
	
	-- Fallback: create simple flashlight if no model found
	if not handle then
		handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.3, 1.5, 0.3)
		handle.Color = Color3.fromRGB(100, 100, 150)
		handle.Parent = tool
		
		lens = Instance.new("Part")
		lens.Name = "Lens"
		lens.Size = Vector3.new(0.35, 0.1, 0.35)
		lens.Color = Color3.fromRGB(200, 200, 255)
		lens.Material = Enum.Material.Plastic
		lens.Transparency = 0.3
		lens.CFrame = handle.CFrame * CFrame.new(0, 0.8, 0)
		lens.Parent = handle
		
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = lens
		weld.Parent = handle
		
		print("[FlashlightEquip] Using fallback model")
	end
	
	-- Create spotlight on lens
	spotlight = Instance.new("SpotLight")
	spotlight.Name = "FlashlightBeam"
	spotlight.Brightness = 0 -- Off by default
	spotlight.Range = LIGHT_RANGE
	spotlight.Angle = 60
	spotlight.Color = LIGHT_COLOR
	spotlight.Face = Enum.NormalId.Right
	spotlight.Parent = lens
	
	-- Create charge indicator decals
	createChargeDecals(handle)
	updateChargeDecals()
	
	-- Toggle light on click
	tool.Activated:Connect(function()
		toggleLight(lens, spotlight)
	end)
	
	return tool
end

-- Toggle flashlight on/off
function toggleLight(lens, spotlight)
	-- Don't toggle if inventory is open (mouse is unlocked when inventory open)
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		print("[FlashlightEquip] Cannot toggle flashlight while inventory is open")
		return
	end
	
	-- Check if we have charge
	if not isLightOn and currentCharge <= 0 then
		print("[FlashlightEquip] No charge! Cannot turn on")
		playSound(SOUND_BATTERY_EMPTY)
		return
	end
	
	isLightOn = not isLightOn
	
	if isLightOn then
		-- Turn on
		lens.Material = Enum.Material.Neon
		lens.Color = Color3.fromRGB(255, 255, 200)
		spotlight.Brightness = LIGHT_BRIGHTNESS
		playSound(SOUND_FLASHLIGHT_ON)
		print("[FlashlightEquip] Light ON")
	else
		-- Turn off
		lens.Material = Enum.Material.Plastic
		lens.Color = Color3.fromRGB(200, 200, 255)
		spotlight.Brightness = 0
		playSound(SOUND_FLASHLIGHT_OFF)
		print("[FlashlightEquip] Light OFF")
	end
end

-- Equip flashlight
local function equipFlashlight()
	if equippedFlashlight then
		print("[FlashlightEquip] Flashlight already equipped")
		return
	end
	
	local tool = createFlashlightTool()
	tool.Parent = player.Backpack
	
	-- Auto-equip
	humanoid:EquipTool(tool)
	equippedFlashlight = tool
	
	print("[FlashlightEquip] Flashlight equipped")
end

-- Unequip flashlight
local function unequipFlashlight()
	if not equippedFlashlight then return end
	
	equippedFlashlight:Destroy()
	equippedFlashlight = nil
	isLightOn = false
	
	print("[FlashlightEquip] Flashlight unequipped")
end

-- Listen for equip requests from InventorySystem
local remoteEvent = ReplicatedStorage:WaitForChild("InventoryEvent")
remoteEvent.OnClientEvent:Connect(function(action, ...)
	if action == "EquipFlashlight" then
		equipFlashlight()
	elseif action == "UnequipFlashlight" then
		unequipFlashlight()
	elseif action == "FlashlightCharged" then
		local newCharge = ...
		currentCharge = newCharge
		updateChargeDecals()
		print(string.format("[FlashlightEquip] Flashlight charged to %.0f%%", newCharge * 100))
	end
end)

print("[FlashlightEquip] Flashlight system initialized")

-- Charge drain system
local lastChargeSyncTime = 0
local CHARGE_SYNC_INTERVAL = 2 -- Sync charge to server every 2 seconds

RunService.Heartbeat:Connect(function(deltaTime)
	if isLightOn and equippedFlashlight then
		-- Drain charge
		currentCharge = math.max(0, currentCharge - CHARGE_DRAIN_RATE * deltaTime)
		updateChargeDecals()
		
		-- Sync to server periodically
		local currentTime = tick()
		if currentTime - lastChargeSyncTime >= CHARGE_SYNC_INTERVAL then
			local remoteFunction = ReplicatedStorage:WaitForChild("InventoryFunction")
			remoteFunction:InvokeServer("UpdateFlashlightCharge", currentCharge)
			lastChargeSyncTime = currentTime
		end
		
		-- Auto turn off at 0%
		if currentCharge <= 0 then
			-- Find lens and spotlight to turn off
			local handle = equippedFlashlight:FindFirstChild("Handle")
			if handle then
				local lens = handle:FindFirstChild("Lens", true)
				local spotlight = lens and lens:FindFirstChild("FlashlightBeam")
				
				if lens and spotlight then
					isLightOn = false
					lens.Material = Enum.Material.Plastic
					lens.Color = Color3.fromRGB(200, 200, 255)
					spotlight.Brightness = 0
					print("[FlashlightEquip] Battery depleted - light OFF")
				end
			end
		end
	end
end)

return {
	Equip = equipFlashlight,
	Unequip = unequipFlashlight
}
