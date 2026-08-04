# zaiouro — Roblox Scripter

Hi! I'm **zaiouro**, a Roblox scripter. I build original, full-stack scripts for Roblox games — everything from autonomous NPCs and chat systems to player data and UI. All code is written by me from scratch (no free models, no stolen assets).

**Open to scripting commissions / hiring.**

---

## Skills

- **Luau scripting** — server & client, modular ModuleScript services
- **Systems I've built**: NPC AI, bubble chat, player data & persistence, stamina/energy systems, staff commands & permissions, full UI (HUD, settings, menus)
- **Remote events** — clean server↔client communication (chat, typing, sprint, staff actions)
- **Performance-minded** — throttled loops, no memory leaks, no per-frame polling
- **Rojo workflow** — develop in VS Code, sync to Roblox Studio

---

## Featured project: Hadasphere

A horror-suspense Roblox game. I wrote the complete script layer (~3,500 lines across 10 scripts):

| Script | What it does |
|---|---|
| `NPCBrain.server.lua` | Autonomous NPC (K-07): walks around, greets players, understands typed messages, answers questions about the world, follows you on command |
| `UIManager.client.lua` | Full UI: loading screen, HUD (health/sanity/stamina bars), settings menu, staff panel |
| `StaffManager.server.lua` | Chat commands (`!kick`, `!tp`, `!heal`, `!announce`...), staff permissions, chat relay |
| `PlayerDataService.lua` | Saved player data, health/sanity/stamina, energy drain & regen |
| `EmailChat.client.lua` | Bubble chat above heads, typing indicators, custom chat input bar |
| `TeamService.lua` | Teams, spawn points, shared remote events |
| `LightingConfig.server.lua` | Fog / lighting atmosphere |
| `PlayerConfig.lua` | Shared config: stats, stamina tuning, staff levels |
| `TeamConfig.lua` | Team definitions and spawns |
| `TeamManager.server.lua` | Boots up the team + player systems |

---

## Proof it works (verifiable in Studio)

No video — here's how to verify the systems yourself. The scripts print **live debug logs** to the Studio Output window:

### 0. Static analysis passes clean (Luau Language Server)
All 10 scripts pass full Roblox API type-checking + lint with **0 errors, 0 warnings**:

```
$ luau-lsp analyze --defs globalTypes.d.luau --sourcemap sourcemap.json --platform roblox
[INFO] Loading definitions file: @roblox - globalTypes.d.luau
[INFO] Loading Luau configuration from .luaurc
(no diagnostics)
```

### 1. NPC chat works
Type near the NPC (within 45 studs) or say "K-07". The Output window shows:
```
[NPCBrain] Heard from YourName (dist=12): hello k-07
[NPCBrain] Intent: greeting
[NPCBrain] Sending: Hello, YourName. You may speak freely.
[NPCBrain] -> YourName (dist=12, isTalker=true)
```
Then the reply appears as a bubble above the NPC's head.

### 2. NPC wakes up at game start
On Play, Output shows:
```
[NPCBrain] Found rig: Rig in Workspace
[NPCBrain] K-07 is awake and thinking.
```

### 3. Systems load cleanly
On Play, Output shows:
```
[TeamManager] Teams + player data ready.
[StaffManager] Staff system ready.
[EmailChat] ready
```

**How to run:** place the scripts in Roblox Studio (server scripts in ServerScriptService, shared modules in ReplicatedStorage → Shared, client scripts in StarterPlayer → StarterPlayerScripts), add a rig model named `Rig` in Workspace, press Play, and check the Output window.

---

## Contact

- **Discord:** zaiouro. (with dot)
- **Roblox:** https://www.roblox.com/users/3255975644/profile

*Thanks for reading! — zaiouro*
