--[[
	FlashlightController: Server-side flashlight management
	
	Manages flashlight attachment to player's character:
		- Attaches flashlight model to RightHand using Motor6D
		- Controls SpotLight (visible to all players)
		- Validates charge before toggling light
		- Broadcasts light state to all clients
	
	REPLICATED: Model is parented to character, visible to all players!

	PROJECT DIRECTION NOTES:
	- Keep as a stealth risk/reward tool (visibility aid vs detection risk).
	- TODO: integrate beam usage into suspicion calculations when seen by host/NPCs.
	- TODO: allow command-specific rules (flashlight use forbidden during certain host commands).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local FlashlightController = {}
FlashlightController.__index = FlashlightController

-- Configuration
local LIGHT_COLOR = Color3.fromRGB(255, 240, 200) -- Warm white
local LIGHT_BRIGHTNESS = 2
local LIGHT_RANGE = 40
local CHARGE_DRAIN_RATE = 0.01 -- 1% per second

function FlashlightController.new()
	local self = setmetatable({}, FlashlightController)
	
	-- Track attached flashlights: {userId = {model, isOn, charge, lens, spotlight, chargeIndicators}}
	self._attachedFlashlights = {}
	
	-- RemoteEvent for client communication
	self._remoteEvent = ReplicatedStorage:FindFirstChild("FlashlightEvent")
	if not self._remoteEvent then
		self._remoteEvent = Instance.new("RemoteEvent")
		self._remoteEvent.Name = "FlashlightEvent"
		self._remoteEvent.Parent = ReplicatedStorage
	end
	
	-- Handle client toggle requests
	self._remoteEvent.OnServerEvent:Connect(function(player, action, ...)
		if action == "ToggleLight" then
			self:ToggleLight(player)
		end
	end)
	
	-- Clean up on player leave
	Players.PlayerRemoving:Connect(function(player)
		self:RemoveFlashlight(player)
	end)
	
	print("[FlashlightController] Flashlight controller initialized")
	
	return self
end

-- Attach flashlight model to player's right hand
function FlashlightController:AttachFlashlight(player, charge)
	local userId = player.UserId
	
	-- Remove existing flashlight if any
	if self._attachedFlashlights[userId] then
		self:RemoveFlashlight(player)
	end
	
	local character = player.Character
	if not character then
		warn(string.format("[FlashlightController] %s has no character", player.Name))
		return false
	end
	
	local rightHand = character:FindFirstChild("RightHand")
	if not rightHand then
		warn(string.format("[FlashlightController] %s has no RightHand", player.Name))
		return false
	end
	
	-- Get flashlight model from ReplicatedStorage
	local ItemModels = ReplicatedStorage:FindFirstChild("ItemModels")
	if not ItemModels then
		warn("[FlashlightController] ItemModels folder not found!")
		return false
	end
	
	local flashlightPrefab = ItemModels:FindFirstChild("FlashlightModel")
	if not flashlightPrefab or not flashlightPrefab:IsA("Model") then
		warn("[FlashlightController] FlashlightModel not found or is not a Model!")
		return false
	end
	
	-- Clone the model
	local flashlightModel = flashlightPrefab:Clone()
	flashlightModel.Name = "EquippedFlashlight"
	
	-- Find primary part (handle)
	local handle = flashlightModel.PrimaryPart
	if not handle then
		-- Fallback: find first part
		for _, child in flashlightModel:GetChildren() do
			if child:IsA("BasePart") then
				handle = child
				flashlightModel.PrimaryPart = handle
				break
			end
		end
	end
	
	if not handle then
		warn("[FlashlightController] FlashlightModel has no valid parts!")
		flashlightModel:Destroy()
		return false
	end
	
	-- Find lens (where SpotLight will be)
	local lens = flashlightModel:FindFirstChild("Lens", true) or handle
	
	-- Create invisible pivot part for spotlight (rotates independently to follow head)
	local spotlightPivot = Instance.new("Part")
	spotlightPivot.Name = "SpotlightPivot"
	spotlightPivot.Size = Vector3.new(0.1, 0.1, 0.1)
	spotlightPivot.Transparency = 1
	spotlightPivot.CanCollide = false
	spotlightPivot.Massless = true
	spotlightPivot.Anchored = false
	spotlightPivot.CFrame = lens.CFrame
	spotlightPivot.Parent = flashlightModel
	
	-- Create attachments for AlignOrientation (proper rotation without physics chaos)
	local lensAttachment = Instance.new("Attachment")
	lensAttachment.Name = "LensAttachment"
	lensAttachment.Parent = lens
	
	local pivotAttachment = Instance.new("Attachment")
	pivotAttachment.Name = "PivotAttachment"
	pivotAttachment.Parent = spotlightPivot
	
	-- AlignPosition: keep pivot at lens position
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = pivotAttachment
	alignPosition.Attachment1 = lensAttachment
	alignPosition.MaxForce = 10000
	alignPosition.Responsiveness = 200
	alignPosition.Parent = spotlightPivot
	
	-- AlignOrientation: we'll update this to control rotation
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = pivotAttachment
	alignOrientation.Attachment1 = lensAttachment
	alignOrientation.MaxTorque = 10000
	alignOrientation.Responsiveness = 200
	alignOrientation.PrimaryAxisOnly = false
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Parent = spotlightPivot
	
	-- Create SpotLight (server-side, visible to OTHER players)
	local spotlight = Instance.new("SpotLight")
	spotlight.Name = "FlashlightBeam"
	spotlight.Brightness = 0 -- Off by default
	spotlight.Range = LIGHT_RANGE
	spotlight.Angle = 60
	spotlight.Color = LIGHT_COLOR
	spotlight.Face = Enum.NormalId.Front
	spotlight.Enabled = true
	spotlight.Parent = spotlightPivot
	
	-- Create charge indicators (4 small neon parts on handle)
	local chargeIndicators = self:_CreateChargeIndicators(handle)
	
	-- Attach to RightHand using Motor6D
	local motor = Instance.new("Motor6D")
	motor.Name = "FlashlightMotor"
	motor.Part0 = rightHand
	motor.Part1 = handle
	
	-- Position offset (adjust these values for your model!)
	-- Format: CFrame.new(X, Y, Z) * CFrame.Angles(pitch, yaw, roll)
	motor.C0 = CFrame.new(-0.2, -0.2, -0.5) * CFrame.Angles(0, math.rad(110), math.rad(10))
	motor.C1 = CFrame.new(0, 0, 0)
	
	motor.Parent = rightHand
	
	-- Make all parts non-collidable
	for _, part in flashlightModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
		end
	end
	
	-- Parent to character (THIS MAKES IT REPLICATED!)
	flashlightModel.Parent = character
	
	-- Store flashlight data
	self._attachedFlashlights[userId] = {
		model = flashlightModel,
		isOn = false,
		charge = charge or 0.5,
		lens = lens,
		spotlight = spotlight,
		spotlightPivot = spotlightPivot,
		alignOrientation = alignOrientation,
		pivotAttachment = pivotAttachment,
		chargeIndicators = chargeIndicators,
		motor = motor,
		player = player
	}
	
	-- Update charge indicators
	self:_UpdateChargeIndicators(userId)
	
	print(string.format("[FlashlightController] ✓ Attached flashlight to %s (charge: %.0f%%)", 
		player.Name, (charge or 0.5) * 100))
	
	-- Broadcast to all clients (for UI/sound effects)
	self._remoteEvent:FireClient(player, "FlashlightAttached", charge or 0.5)
	
	return true
end

-- Remove flashlight from player
function FlashlightController:RemoveFlashlight(player)
	local userId = player.UserId
	local flashlightData = self._attachedFlashlights[userId]
	
	if not flashlightData then
		return
	end
	
	-- Destroy model
	if flashlightData.model then
		flashlightData.model:Destroy()
	end
	
	-- Clean up table
	self._attachedFlashlights[userId] = nil
	
	print(string.format("[FlashlightController] Removed flashlight from %s", player.Name))
	
	-- Broadcast to client
	self._remoteEvent:FireClient(player, "FlashlightRemoved")
end

-- Toggle light on/off
function FlashlightController:ToggleLight(player)
	local userId = player.UserId
	local flashlightData = self._attachedFlashlights[userId]
	
	if not flashlightData then
		warn(string.format("[FlashlightController] %s has no flashlight attached", player.Name))
		return false
	end
	
	-- Check charge
	if not flashlightData.isOn and flashlightData.charge <= 0 then
		print(string.format("[FlashlightController] %s flashlight has no charge", player.Name))
		self._remoteEvent:FireClient(player, "FlashlightNoCharge")
		return false
	end
	
	-- Toggle
	flashlightData.isOn = not flashlightData.isOn
	
	if flashlightData.isOn then
		-- Turn ON
		flashlightData.spotlight.Brightness = LIGHT_BRIGHTNESS
		if flashlightData.lens then
			flashlightData.lens.Material = Enum.Material.Neon
			flashlightData.lens.Color = Color3.fromRGB(255, 255, 200)
		end
		print(string.format("[FlashlightController] %s light ON", player.Name))
	else
		-- Turn OFF
		flashlightData.spotlight.Brightness = 0
		if flashlightData.lens then
			flashlightData.lens.Material = Enum.Material.Plastic
			flashlightData.lens.Color = Color3.fromRGB(200, 200, 255)
		end
		print(string.format("[FlashlightController] %s light OFF", player.Name))
	end
	
	-- Broadcast to all clients (so they can play sounds/effects)
	self._remoteEvent:FireAllClients("FlashlightToggled", player, flashlightData.isOn)
	
	return true
end

-- Update flashlight charge (called by InventoryManager)
function FlashlightController:UpdateCharge(player, newCharge)
	local userId = player.UserId
	local flashlightData = self._attachedFlashlights[userId]
	
	if not flashlightData then
		return false
	end
	
	flashlightData.charge = math.clamp(newCharge, 0, 1)
	self:_UpdateChargeIndicators(userId)
	
	-- Auto turn off if depleted
	if flashlightData.charge <= 0 and flashlightData.isOn then
		flashlightData.isOn = false
		flashlightData.spotlight.Brightness = 0
		if flashlightData.lens then
			flashlightData.lens.Material = Enum.Material.Plastic
			flashlightData.lens.Color = Color3.fromRGB(200, 200, 255)
		end
		print(string.format("[FlashlightController] %s battery depleted - light OFF", player.Name))
		self._remoteEvent:FireAllClients("FlashlightToggled", player, false)
	end
	
	-- Notify client
	self._remoteEvent:FireClient(player, "FlashlightChargeUpdated", flashlightData.charge)
	
	return true
end

-- Get flashlight state
function FlashlightController:GetFlashlightData(player)
	return self._attachedFlashlights[player.UserId]
end

-- Create 4 charge indicator parts
function FlashlightController:_CreateChargeIndicators(handle)
	local indicators = {}
	local handleSize = handle.Size
	local spacing = 0.15
	local indicatorSize = Vector3.new(0.2, 0.05, 0.2)
	
	for i = 1, 4 do
		local indicator = Instance.new("Part")
		indicator.Name = "ChargeIndicator" .. i
		indicator.Size = indicatorSize
		indicator.Color = Color3.fromRGB(0, 255, 0)
		indicator.Material = Enum.Material.Neon
		indicator.Anchored = false
		indicator.CanCollide = false
		indicator.Massless = true
		
		-- Parent first (avoid physics issues)
		indicator.Parent = handle
		
		-- Weld to handle with offset (C0 controls position)
		local xOffset = (i - 2.5) * spacing
		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = indicator
		weld.C0 = CFrame.new(xOffset, handleSize.Y/2 + indicatorSize.Y/2, 0)
		weld.C1 = CFrame.new(0, 0, 0)
		weld.Parent = indicator
		
		table.insert(indicators, indicator)
	end
	
	return indicators
end

-- Update charge indicator visuals
function FlashlightController:_UpdateChargeIndicators(userId)
	local flashlightData = self._attachedFlashlights[userId]
	if not flashlightData then return end
	
	local chargePercent = flashlightData.charge * 100
	
	for i, indicator in ipairs(flashlightData.chargeIndicators) do
		local threshold = (4 - i) * 25 -- 75%, 50%, 25%, 0%
		
		if chargePercent > threshold then
			-- Active (green)
			indicator.Transparency = 0
			indicator.Color = Color3.fromRGB(0, 255, 0)
			indicator.Material = Enum.Material.Neon
		else
			-- Inactive (dim)
			indicator.Transparency = 0.5
			indicator.Color = Color3.fromRGB(50, 50, 50)
			indicator.Material = Enum.Material.SmoothPlastic
		end
	end
end

-- Update spotlight direction based on player's head orientation
function FlashlightController:_UpdateSpotlightDirection(userId)
	local flashlightData = self._attachedFlashlights[userId]
	if not flashlightData then return end
	
	local player = flashlightData.player
	if not player or not player.Character then return end
	
	local head = player.Character:FindFirstChild("Head")
	if not head then return end
	
	local pivotAttachment = flashlightData.pivotAttachment
	if not pivotAttachment then return end
	
	-- Raycast from head position in look direction (accurate aiming)
	local headPosition = head.Position
	local headLookVector = head.CFrame.LookVector
	
	-- Raycast to find where player is looking
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	
	local raycastResult = workspace:Raycast(headPosition, headLookVector * 100, raycastParams)
	
	-- Direction to aim spotlight
	local direction = headLookVector
	if raycastResult then
		-- Aim at hit point for more accuracy
		direction = (raycastResult.Position - headPosition).Unit
	end
	
	-- Create CFrame pointing in raycast direction
	-- Add 180 degree rotation to fix inverted orientation
	local targetCFrame = CFrame.new(Vector3.new(0, 0, 0), direction) * CFrame.Angles(0, math.rad(180), 0)
	
	-- Set attachment CFrame (rotation only, position is handled by AlignPosition)
	pivotAttachment.CFrame = targetCFrame
end

-- Charge drain system (call this in Heartbeat)
function FlashlightController:ProcessChargeDrain(deltaTime)
	for userId, flashlightData in pairs(self._attachedFlashlights) do
		-- Update spotlight direction every frame (follows head look)
		self:_UpdateSpotlightDirection(userId)
		
		if flashlightData.isOn and flashlightData.charge > 0 then
			local oldCharge = flashlightData.charge
			flashlightData.charge = math.max(0, flashlightData.charge - CHARGE_DRAIN_RATE * deltaTime)
			self:_UpdateChargeIndicators(userId)
			
			-- Check if we crossed a threshold (25%, 50%, 75%) to notify client
			local oldPercent = oldCharge * 100
			local newPercent = flashlightData.charge * 100
			local thresholds = {75, 50, 25}
			local shouldNotify = false
			
			for _, threshold in ipairs(thresholds) do
				if oldPercent > threshold and newPercent <= threshold then
					shouldNotify = true
					break
				end
			end
			
			-- Notify client if crossed threshold
			if shouldNotify then
				local player = Players:GetPlayerByUserId(userId)
				if player then
					self._remoteEvent:FireClient(player, "FlashlightChargeUpdated", flashlightData.charge)
				end
			end
			
			-- Auto turn off at 0%
			if flashlightData.charge <= 0 then
				flashlightData.isOn = false
				flashlightData.spotlight.Brightness = 0
				if flashlightData.lens then
					flashlightData.lens.Material = Enum.Material.Plastic
					flashlightData.lens.Color = Color3.fromRGB(200, 200, 255)
				end
				
				local player = Players:GetPlayerByUserId(userId)
				if player then
					print(string.format("[FlashlightController] %s battery depleted", player.Name))
					self._remoteEvent:FireAllClients("FlashlightToggled", player, false)
					self._remoteEvent:FireClient(player, "FlashlightNoCharge")
					self._remoteEvent:FireClient(player, "FlashlightChargeUpdated", 0)  -- Notify with 0% charge
				end
			end
		end
	end
end

return FlashlightController
