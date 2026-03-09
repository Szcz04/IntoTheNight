--[[
	Suspicion Cues / Effects

	Repurposed from legacy horror sanity effects into social-stealth readable cues:
	- Subtle edge tension by suspicion level (no camera distortion)
	- Compact suspicion meter + level label
	- Host command reminder panel with countdown
	- Gentle warning flash on command non-compliance penalties
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local SanityEffects = {}

local LEVEL_LABELS = {
	[1] = "SAFE",
	[2] = "NOTICED",
	[3] = "HOST ALERT",
	[4] = "EXPOSED"
}

-- Opacity and pulse are intentionally subtle to preserve stealth readability.
local EDGE_BASE_OPACITY = {
	[1] = 0.00,
	[2] = 0.08,
	[3] = 0.16,
	[4] = 0.26
}

local EDGE_PULSE_AMPLITUDE = {
	[1] = 0.00,
	[2] = 0.02,
	[3] = 0.04,
	[4] = 0.07
}

local LEVEL_COLORS = {
	[1] = Color3.fromRGB(130, 170, 130),
	[2] = Color3.fromRGB(200, 165, 95),
	[3] = Color3.fromRGB(215, 120, 70),
	[4] = Color3.fromRGB(200, 70, 70)
}

local HOST_HINTS = {
	FREEZE = "Stay still until the timer ends.",
	JUMP = "Jump at least once.",
	DANCE = "Move continuously for a short moment.",
	SIT = "Sit at least once before time runs out.",
	FACE_DIRECTION = "Face the called direction briefly."
}

local currentSuspicion = 0
local currentLevel = 1

local targetEdgeOpacity = 0
local currentEdgeOpacity = 0
local edgePulseTime = 0

local activeHostCommand = nil

local connections = {}

local screenGui
local edgesContainer
local edgeFrames = {}
local meterFill
local meterLabel
local reasonLabel
local hostPanel
local hostTitle
local hostTimer
local hostHint
local flashFrame

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function getLevelFromSuspicion(suspicion)
	if suspicion >= 100 then
		return 4
	elseif suspicion >= 70 then
		return 3
	elseif suspicion >= 40 then
		return 2
	end

	return 1
end

local function formatReason(reason)
	if not reason or reason == "" then
		return ""
	end

	if string.find(reason, "FailedHostCommand:", 1, true) then
		local cmd = string.gsub(reason, "FailedHostCommand:", "")
		return "Noticed ignoring host command: " .. cmd
	end

	return reason
end

local function createEdge(parent, name, size, position, rotation, firstAlpha, secondAlpha)
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Size = size
	edge.Position = position
	edge.BackgroundColor3 = LEVEL_COLORS[1]
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Parent = parent

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, firstAlpha),
		NumberSequenceKeypoint.new(1, secondAlpha)
	})
	gradient.Parent = edge

	table.insert(edgeFrames, edge)
	return edge
end

function SanityEffects:_CreateUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SuspicionCues"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 20
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player:WaitForChild("PlayerGui")

	edgesContainer = Instance.new("Frame")
	edgesContainer.Name = "EdgeTension"
	edgesContainer.Size = UDim2.new(1, 0, 1, 0)
	edgesContainer.BackgroundTransparency = 1
	edgesContainer.BorderSizePixel = 0
	edgesContainer.Parent = screenGui

	local edgeSize = 0.24
	createEdge(edgesContainer, "TopEdge", UDim2.new(1, 0, edgeSize, 0), UDim2.new(0, 0, 0, 0), 90, 0, 1)
	createEdge(edgesContainer, "BottomEdge", UDim2.new(1, 0, edgeSize, 0), UDim2.new(0, 0, 1 - edgeSize, 0), 90, 1, 0)
	createEdge(edgesContainer, "LeftEdge", UDim2.new(edgeSize, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0, 0, 1)
	createEdge(edgesContainer, "RightEdge", UDim2.new(edgeSize, 0, 1, 0), UDim2.new(1 - edgeSize, 0, 0, 0), 0, 1, 0)

	local meterPanel = Instance.new("Frame")
	meterPanel.Name = "SuspicionMeter"
	meterPanel.AnchorPoint = Vector2.new(0, 0)
	meterPanel.Position = UDim2.new(0, 18, 0, 18)
	meterPanel.Size = UDim2.new(0, 270, 0, 56)
	meterPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	meterPanel.BackgroundTransparency = 0.12
	meterPanel.BorderSizePixel = 0
	meterPanel.ZIndex = 10
	meterPanel.Parent = screenGui

	local meterCorner = Instance.new("UICorner")
	meterCorner.CornerRadius = UDim.new(0, 8)
	meterCorner.Parent = meterPanel

	local meterStroke = Instance.new("UIStroke")
	meterStroke.Thickness = 1
	meterStroke.Transparency = 0.45
	meterStroke.Color = Color3.fromRGB(120, 120, 120)
	meterStroke.Parent = meterPanel

	meterLabel = Instance.new("TextLabel")
	meterLabel.Name = "MeterLabel"
	meterLabel.Size = UDim2.new(1, -18, 0, 22)
	meterLabel.Position = UDim2.new(0, 10, 0, 6)
	meterLabel.BackgroundTransparency = 1
	meterLabel.TextXAlignment = Enum.TextXAlignment.Left
	meterLabel.Font = Enum.Font.GothamBold
	meterLabel.TextSize = 14
	meterLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	meterLabel.Text = "Suspicion 0 | SAFE"
	meterLabel.ZIndex = 11
	meterLabel.Parent = meterPanel

	local meterBar = Instance.new("Frame")
	meterBar.Name = "MeterBar"
	meterBar.Size = UDim2.new(1, -20, 0, 12)
	meterBar.Position = UDim2.new(0, 10, 0, 30)
	meterBar.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	meterBar.BorderSizePixel = 0
	meterBar.ZIndex = 11
	meterBar.Parent = meterPanel

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = meterBar

	meterFill = Instance.new("Frame")
	meterFill.Name = "MeterFill"
	meterFill.Size = UDim2.new(0, 0, 1, 0)
	meterFill.BackgroundColor3 = LEVEL_COLORS[1]
	meterFill.BorderSizePixel = 0
	meterFill.ZIndex = 12
	meterFill.Parent = meterBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = meterFill

	reasonLabel = Instance.new("TextLabel")
	reasonLabel.Name = "ReasonLabel"
	reasonLabel.Size = UDim2.new(1, -20, 0, 14)
	reasonLabel.Position = UDim2.new(0, 10, 1, -16)
	reasonLabel.BackgroundTransparency = 1
	reasonLabel.TextXAlignment = Enum.TextXAlignment.Left
	reasonLabel.Font = Enum.Font.Gotham
	reasonLabel.TextSize = 12
	reasonLabel.TextColor3 = Color3.fromRGB(205, 205, 205)
	reasonLabel.TextTransparency = 1
	reasonLabel.Text = ""
	reasonLabel.ZIndex = 11
	reasonLabel.Parent = meterPanel

	hostPanel = Instance.new("Frame")
	hostPanel.Name = "HostCommandCue"
	hostPanel.AnchorPoint = Vector2.new(0.5, 0)
	hostPanel.Position = UDim2.new(0.5, 0, 0, 16)
	hostPanel.Size = UDim2.new(0, 410, 0, 64)
	hostPanel.BackgroundColor3 = Color3.fromRGB(17, 20, 26)
	hostPanel.BackgroundTransparency = 0.1
	hostPanel.BorderSizePixel = 0
	hostPanel.Visible = false
	hostPanel.ZIndex = 20
	hostPanel.Parent = screenGui

	local hostCorner = Instance.new("UICorner")
	hostCorner.CornerRadius = UDim.new(0, 8)
	hostCorner.Parent = hostPanel

	local hostStroke = Instance.new("UIStroke")
	hostStroke.Thickness = 2
	hostStroke.Transparency = 0.25
	hostStroke.Color = Color3.fromRGB(205, 172, 110)
	hostStroke.Parent = hostPanel

	hostTitle = Instance.new("TextLabel")
	hostTitle.Name = "HostTitle"
	hostTitle.Size = UDim2.new(1, -128, 0, 24)
	hostTitle.Position = UDim2.new(0, 12, 0, 6)
	hostTitle.BackgroundTransparency = 1
	hostTitle.TextXAlignment = Enum.TextXAlignment.Left
	hostTitle.Font = Enum.Font.GothamBold
	hostTitle.TextSize = 17
	hostTitle.TextColor3 = Color3.fromRGB(240, 220, 180)
	hostTitle.Text = "HOST COMMAND"
	hostTitle.ZIndex = 21
	hostTitle.Parent = hostPanel

	hostTimer = Instance.new("TextLabel")
	hostTimer.Name = "Timer"
	hostTimer.Size = UDim2.new(0, 108, 0, 24)
	hostTimer.Position = UDim2.new(1, -114, 0, 6)
	hostTimer.BackgroundTransparency = 1
	hostTimer.TextXAlignment = Enum.TextXAlignment.Right
	hostTimer.Font = Enum.Font.GothamBold
	hostTimer.TextSize = 16
	hostTimer.TextColor3 = Color3.fromRGB(255, 232, 175)
	hostTimer.Text = "0.0s"
	hostTimer.ZIndex = 21
	hostTimer.Parent = hostPanel

	hostHint = Instance.new("TextLabel")
	hostHint.Name = "Hint"
	hostHint.Size = UDim2.new(1, -24, 0, 24)
	hostHint.Position = UDim2.new(0, 12, 0, 32)
	hostHint.BackgroundTransparency = 1
	hostHint.TextXAlignment = Enum.TextXAlignment.Left
	hostHint.Font = Enum.Font.Gotham
	hostHint.TextSize = 14
	hostHint.TextColor3 = Color3.fromRGB(220, 220, 220)
	hostHint.Text = ""
	hostHint.ZIndex = 21
	hostHint.Parent = hostPanel

	flashFrame = Instance.new("Frame")
	flashFrame.Name = "WarningFlash"
	flashFrame.Size = UDim2.new(1, 0, 1, 0)
	flashFrame.BackgroundColor3 = Color3.fromRGB(220, 90, 90)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.ZIndex = 15
	flashFrame.Parent = screenGui

	print("[SanityEffects] Suspicion cue UI initialized")
end

function SanityEffects:_ShowReason(text)
	if not reasonLabel then
		return
	end

	reasonLabel.Text = text
	TweenService:Create(reasonLabel, TweenInfo.new(0.12), {
		TextTransparency = 0
	}):Play()

	task.delay(2.5, function()
		if not reasonLabel or reasonLabel.Text ~= text then
			return
		end

		TweenService:Create(reasonLabel, TweenInfo.new(0.35), {
			TextTransparency = 1
		}):Play()
	end)
end

function SanityEffects:_WarningFlash(alpha)
	if not flashFrame then
		return
	end

	flashFrame.BackgroundTransparency = 1
	TweenService:Create(flashFrame, TweenInfo.new(0.08), {
		BackgroundTransparency = 1 - alpha
	}):Play()

	task.delay(0.08, function()
		if flashFrame then
			TweenService:Create(flashFrame, TweenInfo.new(0.45), {
				BackgroundTransparency = 1
			}):Play()
		end
	end)
end

function SanityEffects:_UpdateMeter(animated)
	if not meterFill or not meterLabel then
		return
	end

	local ratio = math.clamp(currentSuspicion / 100, 0, 1)
	local levelName = LEVEL_LABELS[currentLevel] or "UNKNOWN"
	local color = LEVEL_COLORS[currentLevel] or LEVEL_COLORS[1]

	meterLabel.Text = string.format("Suspicion %d | %s", currentSuspicion, levelName)

	local target = {
		Size = UDim2.new(ratio, 0, 1, 0),
		BackgroundColor3 = color
	}

	if animated then
		TweenService:Create(meterFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), target):Play()
	else
		meterFill.Size = target.Size
		meterFill.BackgroundColor3 = target.BackgroundColor3
	end

	targetEdgeOpacity = EDGE_BASE_OPACITY[currentLevel] or 0

	for _, edge in ipairs(edgeFrames) do
		edge.BackgroundColor3 = color
	end
end

function SanityEffects:_ApplySuspicionUpdate(data)
	currentSuspicion = math.clamp(tonumber(data.suspicion or data.sanity) or 0, 0, 100)
	currentLevel = tonumber(data.level) or getLevelFromSuspicion(currentSuspicion)
	self:_UpdateMeter(true)

	local reasonText = formatReason(data.reason)
	if reasonText ~= "" then
		self:_ShowReason(reasonText)
	end

	if string.find(reasonText, "Noticed ignoring host command", 1, true) then
		self:_WarningFlash(0.18)
	end
end

function SanityEffects:_OnSuspicionEvent(action, data)
	data = data or {}

	if action == "Init" or action == "Update" then
		self:_ApplySuspicionUpdate(data)
	elseif action == "LevelChanged" then
		local level = tonumber(data.level)
		if level then
			currentLevel = level
		end
		self:_UpdateMeter(true)
		self:_WarningFlash(0.1)
	elseif action == "Exposed" or action == "Eliminated" then
		currentLevel = 4
		currentSuspicion = 100
		self:_UpdateMeter(true)
		self:_ShowReason("You are exposed.")
		self:_WarningFlash(0.24)
	end
end

function SanityEffects:_OnHostCommandEvent(action, payload)
	payload = payload or {}

	if action == "CommandStarted" then
		activeHostCommand = payload
		hostPanel.Visible = true

		local commandName = tostring(payload.name or "UNKNOWN")
		hostTitle.Text = "HOST COMMAND: " .. commandName

		local hint = HOST_HINTS[commandName] or "Follow the host command."
		if commandName == "FACE_DIRECTION" and payload.context and payload.context.faceDirectionName then
			hint = string.format("Face %s briefly.", tostring(payload.context.faceDirectionName))
		end
		hostHint.Text = hint
		self:_WarningFlash(0.08)

	elseif action == "CommandEnded" or action == "CommandStopped" then
		activeHostCommand = nil
		hostPanel.Visible = false
		hostTimer.Text = "0.0s"
	end
end

function SanityEffects:_ConnectToServer()
	local suspicionEvent = ReplicatedStorage:FindFirstChild("SuspicionEvent")
	if not suspicionEvent then
		suspicionEvent = ReplicatedStorage:WaitForChild("SuspicionEvent", 20)
	end

	if suspicionEvent then
		table.insert(connections, suspicionEvent.OnClientEvent:Connect(function(action, data)
			self:_OnSuspicionEvent(action, data)
		end))
		print("[SanityEffects] Connected to SuspicionEvent")
	end

	-- Legacy bridge listener while older scripts still publish SanityEvent.
	local legacyEvent = ReplicatedStorage:FindFirstChild("SanityEvent")
	if legacyEvent then
		table.insert(connections, legacyEvent.OnClientEvent:Connect(function(action, data)
			self:_OnSuspicionEvent(action, data)
		end))
		print("[SanityEffects] Connected to SanityEvent (legacy)")
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	end

	local hostCommandEvent = remotes and remotes:FindFirstChild("HostCommand")
	if not hostCommandEvent and remotes then
		hostCommandEvent = remotes:WaitForChild("HostCommand", 20)
	end

	if hostCommandEvent then
		table.insert(connections, hostCommandEvent.OnClientEvent:Connect(function(action, payload)
			self:_OnHostCommandEvent(action, payload)
		end))
		print("[SanityEffects] Connected to HostCommand remote")
	end
end

function SanityEffects:_StartRenderLoop()
	table.insert(connections, RunService.RenderStepped:Connect(function(deltaTime)
		local lerpAlpha = math.clamp(deltaTime * 6, 0, 1)
		currentEdgeOpacity = currentEdgeOpacity + (targetEdgeOpacity - currentEdgeOpacity) * lerpAlpha

		edgePulseTime = edgePulseTime + deltaTime * 2.5
		local amplitude = EDGE_PULSE_AMPLITUDE[currentLevel] or 0
		local pulse = ((math.sin(edgePulseTime) + 1) * 0.5) * amplitude
		local finalOpacity = math.clamp(currentEdgeOpacity + pulse, 0, 0.5)
		local finalTransparency = 1 - finalOpacity

		for _, edge in ipairs(edgeFrames) do
			edge.BackgroundTransparency = finalTransparency
		end

		if activeHostCommand and hostPanel.Visible then
			local endsAt = tonumber(activeHostCommand.endsAt) or 0
			local remaining = math.max(0, endsAt - tick())
			hostTimer.Text = string.format("%.1fs", remaining)
		end
	end))
end

function SanityEffects:Init()
	self:_CreateUI()
	self:_ConnectToServer()
	self:_StartRenderLoop()
	self:_UpdateMeter(false)
	print("[SanityEffects] Suspicion cues initialized")
end

function SanityEffects:Cleanup()
	for _, connection in ipairs(connections) do
		disconnectConnection(connection)
	end
	connections = {}

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end

	activeHostCommand = nil
	print("[SanityEffects] Cleaned up")
end

SanityEffects:Init()

return SanityEffects
