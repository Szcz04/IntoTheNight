# AI Workflow Context - IntoTheNight

## Project Snapshot
- Engine: Roblox
- Language: Luau
- Tooling: Roblox Studio + Rojo + VS Code
- Workspace root: `IntoTheNight`

This file is the quick-start context for future AI workflows.
Use it before proposing changes.

## Current Design Direction (Important)
The project is being adapted into a **social stealth infiltration game** set during a house party.

Core loop:
1. Blend into NPC crowd behavior
2. Follow host-issued commands
3. Explore the house
4. Perform sabotage actions
5. Manage suspicion and avoid exposure

Design priority:
- Gameplay systems first (server-authoritative logic)
- Keep architecture stable
- Prefer low-risk refactors over rewrites

## Core Architecture
- `src/ServerScriptService/`: authoritative game systems
- `src/ReplicatedStorage/SharedModules/`: shared definitions/config
- `src/StarterPlayer/StarterPlayerScripts/`: client input/effects/UI

Pattern:
- Systems are modular and initialized in `MainServer.server.lua`
- Systems communicate via events and small APIs
- Existing integrations often pass dependencies through `.new(...)`

## Key Active Systems (Server)
- `GameState.lua`: round state machine (`WAITING`, `RUNNING`, `ENDING`)
- `SuspicionManager.lua`: per-player suspicion (0-100), thresholds, exposure
- `MovementTracker.lua`: player movement states (`IDLE`, `SNEAKING`, `WALKING`, `RUNNING`)
- `HostCommandSystem.lua`: periodic host commands + compliance checks + suspicion penalties
- `PowerManager.lua`: infrastructure power state + blackout timer logic
- `LightingController.lua`: reactive lighting based on power state
- `LeverSequence.lua`: sequence interaction puzzle (candidate sabotage subsystem)
- `InventoryManager.lua`: grid inventory + pickup/drop/equip/consume
- `FlashlightController.lua`: server flashlight attach/toggle/charge logic
- `DevCommands.server.lua`: fast iteration chat commands

## Key Active Systems (Client)
- `InventorySystem.client.lua`: inventory UI + drag/drop + pickup interactions
- `MovementControls.client.lua`: sprint/crouch input
- `FlashlightClient.client.lua`: client-side flashlight effects/controls
- `SuspicionEffects.client.lua`: suspicion cues and host-command feedback UX
- `CameraSetup.client.lua`: first-person camera setup

## Current Refactor Status
Completed:
- Suspicion naming migration completed (`SuspicionManager` and client cues are wired)
- Host command foundation exists (`HostCommandSystem`)
- Multiple scripts include "PROJECT DIRECTION NOTES" and TODO markers

Still pending / planned:
- Host command compliance depth improvements
- NPCBehaviorSystem integration
- CrowdClusterSystem integration
- WitnessSystem integration
- Replace remaining horror-era naming/flows where needed
- Container loot runtime implementation and stealth-oriented loot tuning

## Host Command System Notes
- Remote event: `ReplicatedStorage.Remotes.HostCommand`
- Commands currently include:
  - `FREEZE`
  - `JUMP`
  - `DANCE`
  - `SIT`
  - `FACE_DIRECTION`
- Loop:
  - starts in `RUNNING`
  - issues command every `30-60s`
  - command window `8-12s`
  - non-compliance adds suspicion

## Gameplay Semantics to Preserve
When editing systems, maintain these meanings:
- Suspicion rises from unnatural behavior
- Suspicion falls when blending in / compliance
- At high suspicion, players are noticed/exposed
- Host commands are social pressure events, not horror jumpscares

## Coding Guidance For Future AI Tasks
- Do not rewrite major systems unless explicitly requested
- Preserve event flow and existing dependency patterns
- Prefer targeted edits and compatibility wrappers
- Add TODOs for planned systems instead of speculative overengineering
- Keep server as source of truth for gameplay outcomes

## Integration Hotspots
- `MainServer.server.lua`: system wiring and lifecycle
- `DevCommands.server.lua`: add/testing hooks for new systems
- `SuspicionManager.lua`: central scoring and exposure logic
- `MovementTracker.lua`: movement-derived behavior telemetry
- `HostCommandSystem.lua`: command issuance and compliance checks

## Dev/Test Commands (Current)
Common chat commands include:
- `/startround`, `/endround`, `/state`
- `/checkmovement`, `/runstats`
- `/hostnext`, `/hostcmd <COMMAND>`
- plus other legacy debug commands

## Known Caveats
- Naming is now standardized on "suspicion" across active systems
- Some legacy files/features are transitional and should be migrated gradually
- Not all planned stealth systems are implemented yet (NPC crowd/witness logic)

## Recommended AI Workflow
1. Read this file first
2. Read `MainServer.server.lua` and target system file
3. Keep changes minimal and architecture-compatible
4. Validate with `DevCommands` and problem checks
5. Leave explicit TODOs for cross-system integrations
