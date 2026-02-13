--[[
	CameraSetup: Configure first person camera with unlocked cursor
	
	Roblox domyślnie blokuje kursor w first person, więc:
	- Ustawiamy kamerę na first person programatically
	- Odblokowujemy kursor dla UI interaction
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Wait for character
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- Set first person camera (using Classic mode with zoom locked at 0.5)
player.CameraMaxZoomDistance = 0.5 -- First person distance
player.CameraMinZoomDistance = 0.5 -- Lock at first person

-- Use Classic mode (allows cursor unlock, unlike LockFirstPerson)
player.CameraMode = Enum.CameraMode.Classic

-- Lock cursor initially (first person gameplay)
UserInputService.MouseIconEnabled = true
UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

print("[CameraSetup] First person camera enabled (Classic mode, zoom locked)")

-- Re-apply on respawn
player.CharacterAdded:Connect(function(newCharacter)
	player.CameraMaxZoomDistance = 0.5
	player.CameraMinZoomDistance = 0.5
	player.CameraMode = Enum.CameraMode.Classic
	
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	print("[CameraSetup] Camera reset on respawn")
end)
