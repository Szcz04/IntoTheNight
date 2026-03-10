---
description: "Load IntoTheNight game context - Roblox horror with lobby-based matchmaking and train travel"
name: "game-context"
---

You are working on **IntoTheNight**, a Roblox horror game with the following core design:

## Game Structure
- **Lobby-based matchmaking**: Groups of up to 4 players form parties
- **Train travel mechanic**: Players board a train that moves through various levels
- **Level progression**: Players exit the train at stops and enter different train cars to progress to new levels

## Core Systems
- **Suspicion System**: NPC suspicion/escalation mechanic
- **Inventory System**: Item management and storage
- **Power Management**: Electrical systems and generators
- **Lighting Controller**: Dynamic lighting based on power state
- **Whisper Monster**: AI-driven horror entity
- **Flashlight System**: Player tool with battery management
- **Lever Sequence**: Puzzle/interaction system

## Architecture
- **Server-side**: `ServerScriptService/` contains game logic managers
- **Client-side**: `StarterPlayer/StarterPlayerScripts/` handles UI and player interactions
- **Shared**: `ReplicatedStorage/SharedModules/` for cross-boundary code
- **Modularity**: Systems follow dependency injection pattern with `.new()` constructors

## Tech Stack
- Managed via Rojo (`rojo serve`)
- Luau (Roblox Lua dialect)
- Client-server architecture with RemoteEvents/RemoteFunctions

When implementing features, maintain the existing modular system architecture and dependency patterns.
