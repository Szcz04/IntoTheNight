--[[
	MainClient: Client systems info
	
	All client systems run independently:
		- SanityEffects.client.lua (visual/audio effects)
		- MovementControls.client.lua (sprint/crouch)
		- InventorySystem.client.lua (complete inventory solution with tooltips)
		- CameraSetup.client.lua (first person camera)
		- FlashlightClient.client.lua (flashlight mechanics)
		- FlashlightEquip.client.lua (flashlight equip system)
	
	No initialization needed - they auto-start!
]]

print("=== IntoTheNight - Client Starting ===")
print("[MainClient] All client systems running independently")
print("=== Client Ready ===")
print("Controls:")
print("  B - Toggle inventory")
print("  R - Rotate item (while dragging)")
print("  E - Pick up item (when looking at it)")
print("  Shift - Sprint")
print("  Ctrl - Crouch")
