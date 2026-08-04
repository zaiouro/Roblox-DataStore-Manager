# Hadasphere — Roblox Scripter Application

> **Role applied for:** Scripter (Advanced) 📜
> **Author:** zaiouro
>
> All scripts are **original, written from scratch** — no free models, no AI-generated code, no stolen assets.

---

## 📦 Submission Summary

| Requirement | Status |
|---|---|
| 200+ lines of functional code | ✅ **3,499 lines total** (10 scripts, all functional) |
| Demonstration video of the system | 📹 **Link to demo video:** *(insert video link here)* |
| Proper coding structure (functions, events, loops, modular design) | ✅ See [Code Structure](#-code-structure) |
| Best practices | ✅ Modules, services, `task.*` scheduling, no memory leaks |
| Complex/advanced systems (not simple UI/combat/humanoid edits) | ✅ Autonomous NPC AI, chat network, stamina economy |

---

## 🎮 Project Overview

**Hadasphere** is a horror-suspense Roblox experience built as a full-stack Rojo project. This submission contains the complete server and client script layer:

- A **fully autonomous NPC (K-07)** with a simulated brain, natural-language understanding, memory, and personality
- A **proximity-based bubble chat network** replacing the default Roblox chat
- A **persistent player data system** (DataStores, stamina, sanity, staff levels)
- A **staff command & permissions framework**
- A complete **custom UI suite** (loading screen, HUD, settings menu, staff panel)

---

## 📜 Script Index

| Script | Lines | Role | Responsibility |
|---|---|---|---|
| `NPCBrain.server.lua` | 582 | Server | Autonomous NPC brain: state machine, NLU, knowledge base, personality, follow/stop behaviour, proximity chat integration |
| `UIManager.client.lua` | 1462 | Client | Full UI suite: loading screen, HUD (health/sanity/stamina), settings, staff panel, FPS counter, CRT overlay |
| `StaffManager.server.lua` | 338 | Server | Chat commands (`!team`, `!kick`, `!tp`, `!heal`, …), staff permissions, proximity chat relay, typing indicators |
| `PlayerDataService.lua` | 326 | Server | DataStore persistence, character stats, stamina (energy) drain/regen loop, jump stamina cost |
| `EmailChat.client.lua` | 306 | Client | Custom bubble chat: BillboardGui messages, typing indicators, chat input bar, staff/NPC colour coding |
| `TeamService.lua` | 133 | Server | Single source of truth: teams, spawns, remotes (`Chat`, `Typing`, `Sprint`, …), notify/assign helpers |
| `LightingConfig.server.lua` | 126 | Server | Runtime lighting/atmosphere: fog, haze, dust, colour grading |
| `PlayerConfig.lua` | 102 | Shared | Stat definitions, energy tuning, staff levels + permission matrix |
| `TeamConfig.lua` | 81 | Shared | Team definitions, spawn locations, required staff per team |
| `TeamManager.server.lua` | 43 | Server | Bootstrap: wires TeamService + PlayerDataService on join |

---

## 🧠 Flagship System: NPCBrain (`NPCBrain.server.lua`)

The centerpiece is a **582-line autonomous NPC brain** — not a dialogue tree:

- **State machine** (`IDLE / WANDER / CONVERSE / FOLLOW`) ticked every second with priority ordering
- **Natural Language Understanding**: keyword + interrogative-pattern intent classifier (greeting, question, follow, stop, joke, help…)
- **Knowledge base**: 15 lore topics the NPC answers from ("what is the fog?", "where am I?")
- **Memory & personality**: tracks the current talker, greeted players, mood drift, interaction count
- **Proximity chat integration**: hears players via the shared `Chat` remote, filters by distance (45 studs) and name-addressing ("K-07")
- **Thinking delay**: sends a visible `"..."` indicator, pauses 1.2–2.8 s, then replies
- **Movement**: throttled `MoveTo` pathfinding (never per-frame), smooth CFrame turning task at 20 Hz
- **Rig fixup**: auto-detects R6/R15, unanchors parts, adds Animator, raycasts to floor

### No memory leaks
- All long-lived connections are created once at the top level (no connect-inside-loop)
- Bubbles/typing indicators self-destroy after fading
- `PlayerRemoving` cleans up per-player state in every service
- Brain loop uses `task.wait(1.0)` — no `RunService.Heartbeat` spam from server AI

---

## 🗂 Code Structure

**Modular design** — each concern is a dedicated ModuleScript service:

```
ReplicatedStorage/Shared/     PlayerConfig, TeamConfig          (shared config)
ServerScriptService/          TeamService, PlayerDataService,
                              StaffManager, NPCBrain,
                              LightingConfig, TeamManager       (server services)
StarterPlayerScripts/         UIManager, EmailChat              (client UI)
```

**Patterns used across the codebase:**
- ModuleScript services with `require()` dependency injection (`TeamService.Setup()` idempotent bootstrap)
- Events over polling: RemoteEvents for `Chat`, `Typing`, `Sprint`, `StaffAction`, `Notify`
- `pcall` guards around DataStore and remote-heavy code
- `task.spawn` / `task.delay` for async work (NPC thinking, saves)
- Throttled replication (energy attribute only updates on meaningful change)
- `math.clamp`, sanitization, and defensive typing on all remote payloads

---

## ▶️ Running the Project

1. Install [Rojo](https://rojo.space/)
2. Open `default.project.json`-mapped folder structure with the Rojo VS Code extension, or import the scripts manually into Roblox Studio:
   - **ServerScriptService** ← server scripts
   - **ReplicatedStorage > Shared** ← shared modules
   - **StarterPlayer > StarterPlayerScripts** ← client scripts
3. Place a rig model named `Rig` (Humanoid + Head) in Workspace
4. Press **Play**

---

## 📹 Demonstration Video

*(paste link to your demo video showing the NPC chat system, NPC following, staff commands, and HUD)*

---

*Hadasphere © zaiouro — all code original. No free models or stolen assets.*
