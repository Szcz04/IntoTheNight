--[[
	MainClient: Client-side system orchestrator
	
	Initializes all client systems:
		- SanityEffects (visual/audio effects)
		- MovementControls (sprint/crouch)
		- InventoryUI (grid display)
		- InventoryDragDrop (drag & drop + rotation)
		- ItemPickup (raycast detection)
]]

--[[
	MainClient: Client systems info
	
	All client systems run independently:
		- SanityEffects.client.lua (visual/audio effects)
		- MovementControls.client.lua (sprint/crouch)
		- InventorySystem.client.lua (complete inventory solution)
	
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
