# About me - Roblox Scripter

Hi! I'm **zaiouro**, a Roblox scripter applying for the **Beginner Scripter** role 📜

All of my code is original and written by me from scratch — no free models, no AI-generated code, no stolen assets.

---

## What I'm working on

**Hadasphere** — a horror-suspense Roblox game. I wrote the full script layer for it:

- An **autonomous NPC** (named K-07) that walks around, greets players, understands what you type, and answers questions about the game world. You can tell it to follow you or to stop.
- A **custom bubble chat system** — messages appear above players' heads, with typing indicators and special styling for staff and NPC messages.
- A **player system** with health, sanity, stamina (energy drains when you run, recovers when you rest), and saved data between sessions.
- A **staff system** with chat commands (`!kick`, `!tp`, `!heal`, `!announce`...) and permission levels.
- A **full UI suite** — loading screen, HUD bars, settings menu, staff panel.

---

## My scripts (10 scripts, ~3,500 lines total)

| Script | What it does |
|---|---|
| `NPCBrain.server.lua` | NPC brain: state machine, understands speech, memory, personality, follows you |
| `UIManager.client.lua` | All the UI: HUD, settings, loading screen, staff panel |
| `StaffManager.server.lua` | Chat commands, staff permissions, chat relay |
| `PlayerDataService.lua` | Saved player data, health/sanity/stamina, energy drain & regen |
| `EmailChat.client.lua` | Bubble chat above heads, typing indicator, chat input bar |
| `TeamService.lua` | Teams, spawn points, shared remote events |
| `LightingConfig.server.lua` | Fog / lighting atmosphere |
| `PlayerConfig.lua` | Shared config: stats, stamina tuning, staff levels |
| `TeamConfig.lua` | Team definitions and spawns |
| `TeamManager.server.lua` | Boots up the team + player systems |

---

## How my code is structured

- Each system is its own **module** (services) — teams, player data, staff, NPC each in their own file
- I use **functions, events, and loops** properly:
  - RemoteEvents for all chat/staff/player communication
  - NPC brain runs on a state machine loop (idle → wander → talk → follow)
  - Data saves run on timers, not every frame
- **No memory leaks**: events connect once, UI cleans up after itself, player data is cleaned when players leave

---

## 📹 Demonstration video

*(paste your demo video link here — showing the NPC talking, following you, and the chat bubbles)*

---

*Thanks for reading! — zaiouro*
