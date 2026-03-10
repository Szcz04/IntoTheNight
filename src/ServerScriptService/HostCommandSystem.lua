--[[
	HostCommandSystem: Periodic host-issued command loop for social stealth gameplay.

	Core behavior:
	- Starts when round enters RUNNING state
	- Issues random commands every 30-60 seconds
	- Command windows last 8-12 seconds
	- Evaluates player compliance at window end
	- Adds suspicion to non-compliant players

	Integrations:
	- GameState (start/stop lifecycle)
	- MovementTracker (behavior checks)
	- SuspicionManager (penalties)

	Networking:
	- ReplicatedStorage.Remotes.HostCommand (RemoteEvent)
	- Notifies clients when command starts/ends

	Future integration hooks:
	- TODO: NPCBehaviorSystem should perform host commands automatically.
	- TODO: CrowdClusterSystem should influence what counts as suspicious non-compliance.
	- TODO: WitnessSystem should modulate suspicion based on who observed the failure.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HostCommandSystem = {}
HostCommandSystem.__index = HostCommandSystem

HostCommandSystem.CommandNames = {
	"FREEZE",
	"JUMP",
	"DANCE",
	"SIT",
	"FACE_DIRECTION"
}

HostCommandSystem.Config = {
	IntervalMin = 30,
	IntervalMax = 60,
	DurationMin = 8,
	DurationMax = 12,
	DefaultSuspicionPenalty = 15,
	EvaluationDelaySeconds = 0.35,
	FreezeWitnessMemoryEnabled = true,
	FreezeWitnessSampleIntervalSeconds = 0.2,
	FaceDirectionHoldSeconds = 1.5,
	FaceDotThreshold = 0.75,
	DanceRequiredMovingSeconds = 2.0,
	FreezeAllowedStates = {
		IDLE = true,
		SNEAKING = true
	}
}

function HostCommandSystem.new(gameState, movementTracker, suspicionManager)
	local self = setmetatable({}, HostCommandSystem)

	self._gameState = gameState
	self._movementTracker = movementTracker
	self._suspicionManager = suspicionManager

	self._isRunning = false
	self._activeCommand = nil
	self._lastCommandName = nil
	self._loopThread = nil
	self._commandEndTime = 0

	self._playerProgress = {}
	self._sampleConnection = nil
	self._commandIdCounter = 0
	self._witnessSystem = nil

	self._remoteEvent = self:_CreateRemoteEvent()
	self.CommandStarted = Instance.new("BindableEvent")
	self.CommandEnded = Instance.new("BindableEvent")

	self.Commands = {
		FREEZE = {
			penalty = 10,
			check = function(player)
				return self:_CheckFreeze(player)
			end
		},
		JUMP = {
			penalty = 15,
			check = function(player)
				return self:_CheckJump(player)
			end
		},
		DANCE = {
			penalty = 12,
			check = function(player)
				return self:_CheckDance(player)
			end
		},
		SIT = {
			penalty = 12,
			check = function(player)
				return self:_CheckSit(player)
			end
		},
		FACE_DIRECTION = {
			penalty = 10,
			check = function(player)
				return self:_CheckFaceDirection(player)
			end
		}
	}

	self:_SetupGameStateHooks()
	self:_SetupPlayerHooks()

	print("[HostCommandSystem] Initialized")
	return self
end

function HostCommandSystem:SetWitnessSystem(witnessSystem)
	self._witnessSystem = witnessSystem
	print(string.format("[HostCommandSystem] Witness system attached: %s", tostring(witnessSystem ~= nil)))
end

function HostCommandSystem:_CreateRemoteEvent()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local remoteEvent = remotes:FindFirstChild("HostCommand")
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = "HostCommand"
		remoteEvent.Parent = remotes
	end

	return remoteEvent
end

function HostCommandSystem:_SetupGameStateHooks()
	if not self._gameState or not self._gameState.StateChanged then
		warn("[HostCommandSystem] GameState missing StateChanged event")
		return
	end

	self._gameState.StateChanged.Event:Connect(function(newState)
		if newState == "RUNNING" then
			self:Start()
		elseif newState == "ENDING" or newState == "WAITING" then
			self:Stop()
		end
	end)

	-- If the system initializes during an active round, start immediately.
	if self._gameState.GetState and self._gameState:GetState() == "RUNNING" then
		self:Start()
	end
end

function HostCommandSystem:_SetupPlayerHooks()
	for _, player in Players:GetPlayers() do
		self:_OnPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._playerProgress[player.UserId] = nil
	end)
end

function HostCommandSystem:_OnPlayerAdded(player)
	self._playerProgress[player.UserId] = self:_CreateProgressData(player)
end

function HostCommandSystem:_CreateProgressData(player)
	return {
		player = player,
		didJump = false,
		timeFacing = 0,
		timeDancing = 0,
		wasSitting = false,
		lastSampleTime = tick(),
		freezeWitnessed = false,
		freezeWitnessCount = 0,
		freezeWitnessAt = 0,
		lastFreezeWitnessSampleAt = 0
	}
end

function HostCommandSystem:Start()
	if self._isRunning then
		return
	end

	self._isRunning = true
	print("[HostCommandSystem] Started")

	self._loopThread = task.spawn(function()
		self:_RunLoop()
	end)
end

function HostCommandSystem:Stop()
	if not self._isRunning then
		return
	end

	self._isRunning = false
	self._activeCommand = nil
	self._commandEndTime = 0
	self:_StopSampling()

	-- Notify clients command flow stopped.
	self._remoteEvent:FireAllClients("CommandStopped")
	self.CommandEnded:Fire({
		name = "STOPPED",
		endedAt = tick()
	})
	print("[HostCommandSystem] Stopped")
end

function HostCommandSystem:_RunLoop()
	while self._isRunning do
		local waitSeconds = math.random(self.Config.IntervalMin, self.Config.IntervalMax)
		task.wait(waitSeconds)

		if not self._isRunning then
			break
		end

		self:IssueCommand(nil)
	end
end

function HostCommandSystem:_PickRandomCommandName(optionalName)
	if optionalName then
		if self.Commands[optionalName] then
			return optionalName
		end
		warn(string.format("[HostCommandSystem] Unknown command '%s', choosing random", tostring(optionalName)))
	end

	local candidates = {}
	for _, commandName in ipairs(self.CommandNames) do
		if commandName ~= self._lastCommandName then
			table.insert(candidates, commandName)
		end
	end

	if #candidates == 0 then
		candidates = self.CommandNames
	end

	return candidates[math.random(1, #candidates)]
end

function HostCommandSystem:_GetFaceDirectionTarget()
	local directions = {
		{ name = "North", vector = Vector3.new(0, 0, -1) },
		{ name = "South", vector = Vector3.new(0, 0, 1) },
		{ name = "East", vector = Vector3.new(1, 0, 0) },
		{ name = "West", vector = Vector3.new(-1, 0, 0) }
	}

	return directions[math.random(1, #directions)]
end

function HostCommandSystem:IssueCommand(forcedCommandName)
	if not self._isRunning then
		warn("[HostCommandSystem] IssueCommand called while system is stopped")
		return nil
	end

	if self._activeCommand then
		warn("[HostCommandSystem] Command already active, skipping new issue")
		return nil
	end

	local commandName = self:_PickRandomCommandName(forcedCommandName)
	local commandDef = self.Commands[commandName]
	if not commandDef then
		return nil
	end

	self._commandIdCounter = self._commandIdCounter + 1
	local duration = math.random(self.Config.DurationMin, self.Config.DurationMax)
	local evaluationDelay = math.max(0, tonumber(self.Config.EvaluationDelaySeconds) or 0)
	local context = {}

	if commandName == "FACE_DIRECTION" then
		local target = self:_GetFaceDirectionTarget()
		context.faceDirectionName = target.name
		context.faceDirectionVector = target.vector
	end

	self._activeCommand = {
		id = self._commandIdCounter,
		name = commandName,
		duration = duration,
		evaluationDelay = evaluationDelay,
		definition = commandDef,
		context = context,
		startedAt = tick()
	}

	self._lastCommandName = commandName
	self._commandEndTime = tick() + duration + evaluationDelay

	self:_ResetProgressForActivePlayers()
	self:_StartSampling()

	print(string.format("[HostCommandSystem] HOST COMMAND: %s (duration=%ds, evalDelay=%.2fs)", commandName, duration, evaluationDelay))

	self._remoteEvent:FireAllClients("CommandStarted", {
		id = self._activeCommand.id,
		name = commandName,
		duration = duration,
		endsAt = self._commandEndTime,
		context = context
	})

	self.CommandStarted:Fire({
		id = self._activeCommand.id,
		name = commandName,
		duration = duration,
		endsAt = self._commandEndTime,
		context = context
	})

	task.spawn(function()
		task.wait(duration + evaluationDelay)
		if self._activeCommand and self._activeCommand.id == self._commandIdCounter then
			self:EvaluatePlayers()
		end
	end)

	return self._activeCommand
end

function HostCommandSystem:_ResetProgressForActivePlayers()
	for _, player in Players:GetPlayers() do
		self._playerProgress[player.UserId] = self:_CreateProgressData(player)
	end
end

function HostCommandSystem:_StartSampling()
	self:_StopSampling()

	self._sampleConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_SamplePlayerProgress(deltaTime)
	end)
end

function HostCommandSystem:_StopSampling()
	if self._sampleConnection then
		self._sampleConnection:Disconnect()
		self._sampleConnection = nil
	end
end

function HostCommandSystem:_SamplePlayerProgress(deltaTime)
	if not self._activeCommand then
		return
	end

	local commandName = self._activeCommand.name

	for _, player in Players:GetPlayers() do
		local progress = self._playerProgress[player.UserId]
		if not progress then
			progress = self:_CreateProgressData(player)
			self._playerProgress[player.UserId] = progress
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if humanoid and humanoid.Health > 0 then
			if humanoid.Jump then
				progress.didJump = true
			end

			if humanoid.Sit then
				progress.wasSitting = true
			end

			if commandName == "DANCE" then
				local moveMagnitude = humanoid.MoveDirection.Magnitude
				local movementState = self._movementTracker and self._movementTracker:GetState(player) or "IDLE"
				if moveMagnitude > 0.2 and movementState ~= "RUNNING" then
					progress.timeDancing = progress.timeDancing + deltaTime
				end
			elseif commandName == "FREEZE" and rootPart then
				self:_SampleFreezeWitnessMemory(player, progress, humanoid, rootPart)
			elseif commandName == "FACE_DIRECTION" and rootPart then
				local targetVector = self._activeCommand.context.faceDirectionVector
				if targetVector then
					local look = rootPart.CFrame.LookVector
					local dot = look:Dot(targetVector)
					if dot >= self.Config.FaceDotThreshold then
						progress.timeFacing = progress.timeFacing + deltaTime
					end
				end
			end
		end
	end
end

function HostCommandSystem:_IsFreezeViolation(player, humanoid)
	if self._movementTracker then
		local state = self._movementTracker:GetState(player)
		if state then
			return self.Config.FreezeAllowedStates[state] ~= true
		end
	end

	if humanoid then
		return humanoid.MoveDirection.Magnitude > 0.15
	end

	return false
end

function HostCommandSystem:_SampleFreezeWitnessMemory(player, progress, humanoid, rootPart)
	if self.Config.FreezeWitnessMemoryEnabled ~= true then
		return
	end

	if not self._witnessSystem or not self._witnessSystem.EvaluateWitnesses then
		return
	end

	if not self:_IsFreezeViolation(player, humanoid) then
		return
	end

	local now = tick()
	local interval = math.max(0.05, tonumber(self.Config.FreezeWitnessSampleIntervalSeconds) or 0.2)
	if now - (progress.lastFreezeWitnessSampleAt or 0) < interval then
		return
	end
	progress.lastFreezeWitnessSampleAt = now

	local result = self._witnessSystem:EvaluateWitnesses({
		actorPlayer = player,
		actionType = "HostCommandFreezeMovement",
		actionContext = {
			phase = "sampling"
		},
		worldPosition = rootPart.Position
	})

	local witnessCount = #(result.witnesses or {})
	if witnessCount > 0 then
		progress.freezeWitnessed = true
		progress.freezeWitnessCount = math.max(progress.freezeWitnessCount or 0, witnessCount)
		progress.freezeWitnessAt = now
	end
end

function HostCommandSystem:EvaluatePlayers()
	if not self._activeCommand then
		return
	end

	local commandName = self._activeCommand.name
	local commandDef = self._activeCommand.definition

	for _, player in Players:GetPlayers() do
		local progress = self._playerProgress[player.UserId]
		local compliant = false
		if commandDef and commandDef.check then
			compliant = commandDef.check(player) == true
		end

		if not compliant and self._suspicionManager then
			local penalty = commandDef.penalty or self.Config.DefaultSuspicionPenalty
			if commandName == "FREEZE" and progress and progress.freezeWitnessed then
				local rememberedCount = math.max(1, tonumber(progress.freezeWitnessCount) or 1)
				local finalPenalty = penalty
				local multiplier = 1
				if self._witnessSystem and self._witnessSystem.ComputeSuspicionAmount then
					finalPenalty, multiplier = self._witnessSystem:ComputeSuspicionAmount(penalty, rememberedCount)
				end
				self._suspicionManager:AddSuspicion(
					player,
					finalPenalty,
					string.format("RememberedWitnessedFailedHostCommand:FREEZE:%d", rememberedCount)
				)
				print(string.format("[HostCommandSystem] FREEZE remembered witness applied for %s (witnesses=%d multiplier=%.2f penalty=%d)", player.Name, rememberedCount, multiplier, finalPenalty))
			elseif self._witnessSystem and self._witnessSystem.ProcessSuspiciousAction then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local result = self._witnessSystem:ProcessSuspiciousAction({
					actorPlayer = player,
					actionType = "HostCommandNonCompliance",
					actionContext = {
						commandName = commandName,
						commandId = self._activeCommand and self._activeCommand.id or -1
					},
					worldPosition = root and root.Position or nil,
					suspicionAmount = penalty,
					reason = "WitnessedFailedHostCommand:" .. commandName
				})

				if not result.witnessed then
					print(string.format("[HostCommandSystem] No witness for %s failing %s - no suspicion applied", player.Name, commandName))
				end
			else
				self._suspicionManager:AddSuspicion(player, penalty, "FailedHostCommand:" .. commandName)
			end
		end
	end

	self._remoteEvent:FireAllClients("CommandEnded", {
		id = self._activeCommand.id,
		name = commandName,
		endedAt = tick()
	})

	self.CommandEnded:Fire({
		id = self._activeCommand.id,
		name = commandName,
		endedAt = tick()
	})

	print(string.format("[HostCommandSystem] Command evaluated: %s", commandName))

	self._activeCommand = nil
	self._commandEndTime = 0
	self:_StopSampling()
end

function HostCommandSystem:_CheckFreeze(player)
	if not self._movementTracker then
		return false
	end

	local state = self._movementTracker:GetState(player)
	return self.Config.FreezeAllowedStates[state] == true
end

function HostCommandSystem:_CheckJump(player)
	local progress = self._playerProgress[player.UserId]
	return progress and progress.didJump == true
end

function HostCommandSystem:_CheckDance(player)
	local progress = self._playerProgress[player.UserId]
	return progress and progress.timeDancing >= self.Config.DanceRequiredMovingSeconds
end

function HostCommandSystem:_CheckSit(player)
	local progress = self._playerProgress[player.UserId]
	return progress and progress.wasSitting == true
end

function HostCommandSystem:_CheckFaceDirection(player)
	local progress = self._playerProgress[player.UserId]
	if not progress then
		return false
	end

	return progress.timeFacing >= self.Config.FaceDirectionHoldSeconds
end

function HostCommandSystem:GetActiveCommand()
	return self._activeCommand
end

function HostCommandSystem:SetEvaluationDelaySeconds(seconds)
	local parsed = tonumber(seconds)
	if not parsed then
		return false
	end

	self.Config.EvaluationDelaySeconds = math.clamp(parsed, 0, 5)
	print(string.format("[HostCommandSystem] EvaluationDelaySeconds set to %.2f", self.Config.EvaluationDelaySeconds))
	return true
end

function HostCommandSystem:GetEvaluationDelaySeconds()
	return tonumber(self.Config.EvaluationDelaySeconds) or 0
end

-- Dev helper: force a specific command now (if no command currently active).
function HostCommandSystem:ForceIssueCommand(commandName)
	return self:IssueCommand(commandName)
end

return HostCommandSystem
