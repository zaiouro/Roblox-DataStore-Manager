--[[
	Hadasphere NPC Brain - server (Script).
	Controls a rig placed in Workspace (default name "Rig").

	Simulated intelligence, not a dialogue tree:
	  - an autonomous brain ticks every second and picks a goal
	    (idle / wander / converse / follow) from its own "drives"
	  - it hears players speaking nearby (shared Chat remote) and
	    answers through the bubble chat, with a visible "thinking" pause
	  - personality, mood and short-term memory shape its replies
	  - "follow me" / "stop" change its behaviour mid-session

	The rig only needs a Humanoid + HumanoidRootPart + Head.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerConfig"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))

TeamService.Setup() -- make sure the remotes exist
local Chat = TeamService.Chat

-- ============ rig discovery ============
local function findRig()
	local named = Workspace:FindFirstChild("Rig")
	if named and named:FindFirstChildOfClass("Humanoid") and named:FindFirstChild("Head") then
		return named
	end
	for _, inst in ipairs(Workspace:GetChildren()) do
		if inst:IsA("Model") and not Players:GetPlayerFromCharacter(inst)
			and inst:FindFirstChildOfClass("Humanoid") and inst:FindFirstChild("Head") then
			return inst
		end
	end
	return nil
end

local rig = findRig()
local searchStart = os.clock()
while not rig and os.clock() - searchStart < 15 do
	task.wait(0.5)
	rig = findRig()
end

if not rig then
	warn("[NPCBrain] No rig found in Workspace. Place a rig named 'Rig' and press Play again.")
	return
end

print("[NPCBrain] Found rig: " .. rig.Name .. " in " .. rig.Parent:GetFullName())

local humanoid = rig:FindFirstChildOfClass("Humanoid")
local hrp = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
if not humanoid or not hrp then
	warn("[NPCBrain] Rig is missing a Humanoid or HumanoidRootPart.")
	return
end

-- ============ rig fixup ============
-- Rigs dragged into Workspace often misbehave: parts can be left anchored
-- (the model hovers / slides), the RigType can be wrong for the body, or the
-- model has no Animator so it skates around without a walking animation.
-- Normalise all of that once at spawn so the rig moves and animates like a
-- character no matter how it was built.
local fixOk, fixErr = pcall(function()
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local isR15 = rig:FindFirstChild("UpperTorso") ~= nil
	local wantType = isR15 and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6
	if humanoid.RigType ~= wantType then
		humanoid.RigType = wantType
	end

	-- unanchor everything so the physics/humanoid can actually move it
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	-- snap the rig down onto the floor so the feet touch ground (never hover)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig }
	local hit = Workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), Vector3.new(0, -250, 0), params)
	if hit then
		local targetY = hit.Position.Y + humanoid.HipHeight
		if hrp.Position.Y - targetY > 0.75 then
			hrp.CFrame = hrp.CFrame + Vector3.new(0, targetY - hrp.Position.Y, 0)
		end
	end
end)
if not fixOk then
	warn("[NPCBrain] Rig fixup failed (non-fatal):", fixErr)
end

-- NOTE: no manual animation tracks here. The rig now has a clean RigType +
-- Animator, so Roblox's own default idle/walk/run animations drive it from
-- the humanoid's movement state. Manually loading extra tracks on top of that
-- made the engine's controller and ours fight (arms swung while standing
-- still), so the engine is the single source of truth for locomotion.

-- ============ identity + personality ============
local NPC = {
	name = "K-07",
}

local _personality = {
	curiosity = 0.8,  -- how much it wants to engage
	sociability = 0.7, -- how much it likes talking
	wanderlust = 0.6, -- how restless it is
	mood = 0.55,      -- 0..1, drifts with interactions
}

local memory = {
	following = nil,   -- player we are following
	talker = nil,      -- player we are conversing with
	greeted = {},      -- userId -> last greet time
	interactions = 0,
	mood = 0.55,       -- 0..1, drifts with interactions
	lastConverse = 0,
	lastGreet = 0,
}

-- brain state (declared before the chat handler so both share the same local)
local state = "IDLE"
local lastWander = os.clock()
local lookTarget = nil -- point the rig should slowly turn toward (nil = don't)

-- ============ helpers ============
local CHAT_RANGE = PlayerConfig.Communication.ChatRange or 60
local HEAR_RANGE = 45

local function charRoot(plr)
	local ch = plr and plr.Character
	return ch and (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart) or nil
end

local function distToNPC(plr)
	local r = charRoot(plr)
	if not r then return math.huge end
	return (hrp.Position - r.Position).Magnitude
end

local function stopWalk()
	humanoid:MoveTo(hrp.Position)
end

-- instead of snapping CFrame (which looks robotic and fights the physics
-- engine), just tell the smooth-turning task where to look.
local function setLookTarget(p)
	lookTarget = p
end

local function pick(list)
	return list[math.random(#list)]
end

-- ============ knowledge base (answers "what/why/how is X") ============
-- K-07 is a security unit, so its knowledge is practical first, lore second:
-- it briefs operators on controls, vitals, teams and directions before it
-- ever talks about the fog.
local KB = {
	["how do i play"] = {
		"Simple: explore the facility, watch your vitals, and stick with your team. Ask me about controls, teams or how to stay alive and I'll brief you.",
		"Your job is to operate inside the facility. Mind your health, sanity and stamina, and use the M menu to check your settings and your team.",
	},
	["how do i move"] = {
		"WASD to move, mouse to look, Shift to sprint - it drains stamina, so rest when the bar runs low. Press M for the full control list.",
		"Movement is standard: WASD + mouse, Shift to sprint. The M menu has every keybind listed.",
	},
	["how do i chat"] = {
		"Press T or / to open the chat, type your message and hit Enter to send. I'll hear you if you stay close.",
		"Press T or / to talk. Enter sends, ESC closes the bar. Keep it within earshot and I'll pick it up.",
	},
	["how do i heal"] = {
		"Rest to recover stamina, stay calm to keep your sanity, and don't run head-first into the dark. Health first, heroics second.",
		"Your vitals recover with rest. Sprinting costs stamina, the fog costs sanity. Keep them above the line and you'll last the shift.",
	},
	["health"] = {
		"Health is your physical condition. Get hit and it drops; let it empty and your shift ends early. Sanity works the other way - the dark eats it.",
		"Vitals: health takes the hits, sanity drains in the dark, stamina runs on sprint. Watch all three bars in the corner of your HUD.",
	},
	["sanity"] = {
		"Sanity is what the facility taxes you for staying in the dark too long. Keep to the lights, take it slow, and it holds steady.",
		"The fog and the dark wear on your sanity. Stay where it's lit and you'll keep a clear head.",
	},
	["stamina"] = {
		"Sprint uses stamina. When the bar is empty, you walk. Stand still a few seconds and it refills.",
		"Stamina is your sprint meter. Short bursts, then a breather - it recovers fast when you hold still.",
	},
	["team"] = {
		"Operators work in teams. Open the M menu to see yours and your team colour - stay with your colour and you'll have backup.",
		"Teams are assigned through the menu. Your team colour tells you who to watch your back with.",
	},
	["staff"] = {
		"Staff run the facility. Their chat lines start with '!' - that's how they issue orders. Don't impersonate staff; I check.",
		"Staff commands start with '!' in chat. Everything else staff do, they do from the M menu.",
	},
	["where am i"] = {
		"You're in Hadasphere, a research facility. Spawn is under the lights ahead; the lower level is sealed off - that's Zone Nadir.",
		"This is Hadasphere. Stay near the lit corridors and the spawn point and you'll get your bearings fast.",
	},
	["exit"] = {
		"Exits are logged in Section B, but the log changes nightly. Realistically? Stay with your team - nobody exits this place alone.",
		"The exit routes are posted on Section B's board. They're re-posted every night because the building moves them.",
	},
	["fog"] = {
		"The fog rolls in on a schedule, and lately it's been early. When it comes, stay inside the lit zones.",
		"The fog is a hazard here - it eats light and patience. It's not weather; treat it like a patrol zone you don't enter.",
	},
	["hadasphere"] = {
		"Hadasphere is this facility's designation. It's a containment and research site, and the records don't agree with the building.",
		"The base calls itself Hadasphere. What it contains, it doesn't advertise - ask me about teams or controls instead.",
	},
	["zone nadir"] = {
		"Zone Nadir is the sealed lower level. The records say it's stable. I patrol it with the lights off and I don't file reports on it.",
		"Nadir is the lower level, sealed for containment. Access is restricted - even for security, which tells you something.",
	},
	["anomaly"] = {
		"Anomalies are inventory items that weren't in yesterday's count. The count grows every night. Report one and stay back from it.",
		"Anything that wasn't on the manifest is an anomaly. Log it and keep your distance.",
	},
	["door"] = {
		"Doors here keep their own count. If a door isn't where the blueprint says it is, use another.",
		"Three doors were added last night; the blueprints still say two. It's not the doors' fault - use the ones that stay put.",
	},
	["lights"] = {
		"Rule one: stay under the lights. The fog and whatever rides it don't like the lit zones.",
		"Light is your friend down here. The lights flicker on a nine-second cycle - when the ninth second doesn't come, move.",
	},
	["night"] = {
		"The night shift is the longest. Clocks in the east wing run a minute slow, which is how the staff tell the hours apart.",
		"Night shifts outlast the days down here. Keep a light on your person and a team at your back.",
	},
}

-- ============ replies (security-guard voice: professional, dry, helpful) ===
-- K-07 is posted to help operators, so replies answer questions first and
-- only lean on atmosphere when there is nothing practical to say.
local REPLIES = {
	greeting = {
		"K-07 on watch. You can speak freely, operator.",
		"Welcome, %s. Stay on the lit paths and you'll be fine.",
		"Good to see you, %s. Need a patrol briefing, or just passing through?",
	},
	whoami = {
		"I'm K-07, security for this facility. Ask me anything and I'll give you a straight answer.",
		"K-07, facility security. I keep the corridors clear and the operators informed.",
		"Designation K-07. I've walked every corridor here, so if you need directions, you've got the right unit.",
	},
	howareyou = {
		"Quiet shift. All clear on my sweep. What do you need?",
		"Copy. Everything's stable on my end. You holding up out there, %s?",
		"Fog's early again, but the perimeter holds. How about you?",
	},
	joke = {
		"Why doesn't security play cards with the facility? It keeps changing the deck.",
		"Knock knock. Who's there? Me. Door's locked. Move along.",
		"The vending machine is the only thing here that hasn't been compromised. I don't trust it either.",
	},
	thanks = {
		"Always, %s. That's what I'm here for.",
		"Copy that. Watch your vitals out there.",
	},
	bye = {
		"Stay safe, %s. Radio me if you need anything.",
		"Copy. I'm on patrol if you need me.",
	},
	help = {
		"I'm your guide around here. Ask me about controls, your team, how to stay alive, or where to go. Say 'follow me' and I'll walk with you, or 'stay' to post me here.",
		"Briefing: press M for the menu and controls, T or / to chat, E to interact. Ask me about your team, your vitals or where to go. 'Follow me' and I'm on your six.",
	},
	follow = {
		"Copy. Walking with you now - stay in sight.",
		"On your six, %s. Lead the way.",
		"Following. I'll cover the rear.",
	},
	stop = {
		"Copy. Posting up here. Radio me if you need me.",
		"Holding position. Call me if the dark gets loud.",
		"As you were. I'll hold this spot.",
	},
	controls = {
		"Controls: WASD to move, Shift to sprint, M for the menu, T or / to chat, E to interact. Everything else is listed in the M menu.",
		"Keybinds: WASD + mouse, Shift sprint, M menu, T or / chat, E interact. The M menu has the complete list.",
	},
	vitals = {
		"Watch your three bars: health takes the hits, stamina runs on sprint, sanity drains in the dark. Rest keeps all three stable.",
		"Your vitals are in the corner - health, sanity, stamina. Keep them up: stay lit, don't over-sprint, don't take hits.",
	},
	team = {
		"Teams are set up through the M menu. Your team colour tells you who's on your side - watch each other's backs.",
		"Your team shows in the M menu. Stay with your colour and you'll last longer down here.",
	},
	staff = {
		"Staff run this facility and their chat commands start with '!'. Legit staff show their rank - nobody else should be using those.",
		"Staff orders come through chat with a '!' prefix. If you're staff, the M menu has your panel.",
	},
	question = {
		"I don't have that on record. Ask me about controls, your team or how to stay alive.",
		"That one's outside my patrol notes. Try the M menu - it covers most operator questions.",
	},
	statement = {
		"Copy that. I'll factor it into the patrol.",
		"Noted, %s. Good to know.",
		"Copy. Watch the dark while you're down here.",
	},
	glitch = {
		"... the tape skips. What were we speaking of?",
		"... I lost a few seconds. Continue.",
		"... static. My apologies. Repeat the last part.",
	},
}

-- ============ language understanding ============
local function nlu(msg)
	local s = msg:lower()
	s = s:gsub("[%p%c]", " ")
	s = " " .. s .. " "

	local function has(...)
		for _, p in ipairs({ ... }) do
			if s:find(" " .. p .. " ", 1, true) then return true end
		end
		return false
	end

	if has("follow", "come with me", "come", "come here", "follow me") then
		return "follow"
	end
	if has("stop", "stay", "halt", "wait here", "go away", "leave", "stand still") then
		return "stop"
	end
	if has("hi", "hello", "hey", "yo", "greetings", "good morning", "good evening", "howdy") then
		return "greeting"
	end
	if has("who are you", "your name", "what are you", "who are u", "whats your name") then
		return "whoami"
	end
	if has("how are you", "how are u", "you ok", "you okay", "how do you feel", "you alright", "how r u") then
		return "howareyou"
	end
	if has("joke", "make me laugh", "something funny", "funny") then
		return "joke"
	end
	if has("thanks", "thank you", "thx", "appreciated", "ty") then
		return "thanks"
	end
	if has("bye", "goodbye", "see you", "later", "farewell") then
		return "bye"
	end
	if has("help", "what can you do") then
		return "help"
	end
	if has("controls", "keybinds", "keys", "how do i move", "how to move", "how do i sprint", "how to sprint", "how do i jump", "how to jump", "how do i chat", "how to chat", "how do i talk", "how to talk", "how do i open the menu") then
		return "controls"
	end
	if has("vitals", "health", "sanity", "stamina", "how do i heal", "how to heal", "how do i survive", "how to survive", "how do i get health", "im dying", "i'm dying", "how do i recover") then
		return "vitals"
	end
	if has("team", "teams", "faction", "factions", "which team", "join a team", "what team am i") then
		return "team"
	end
	if has("staff", "admin", "moderator", "commands", "what can staff do", "how do i become staff") then
		return "staff"
	end
	if has("facility", "this place", "where am i", "hadasphere", "zone nadir", "where are we", "what is this", "exit", "escape", "spawn", "where to go", "where should i go", "fog", "lights", "anomaly") then
		return "question" -- falls through to KB lookup
	end
	if s:find("?", 1, true) or s:match("%s(what|why|how|who|where|which|when|can|could|is|are|do|does|did)%s") then
		return "question"
	end
	return "statement"
end

-- ============ responding ============
local function respond(plr, intent, msg)
	memory.interactions = memory.interactions + 1
	memory.mood = math.clamp(memory.mood + 0.02, 0, 1)

	local text
	if intent == "question" then
		local s = msg:lower()
		text = nil
		for topic, list in pairs(KB) do
			if s:find(topic, 1, true) then
				text = pick(list)
				break
			end
		end
		text = text or pick(REPLIES.question)
	else
		text = pick(REPLIES[intent] or REPLIES.statement)
	end

	text = text:gsub("%%s", plr.DisplayName or plr.Name)

	-- occasional glitch once the conversation has been going a while
	if memory.interactions > 2 and math.random() < 0.08 then
		text = text .. " " .. pick(REPLIES.glitch)
	end
	return text
end

local function sendNpc(text)
	print("[NPCBrain] Sending: " .. text)
	local payload = {
		from = NPC.name,
		uid = -1,          -- sentinel: client knows uid -1 + npc means "not a player"
		npc = rig,
		npcName = rig.Name,
		text = text,
		staff = false,
	}
	for _, target in ipairs(Players:GetPlayers()) do
		local d = distToNPC(target)
		if target == memory.talker or d <= CHAT_RANGE then
			print("[NPCBrain] -> " .. target.Name .. " (dist=" .. math.floor(d) .. ", isTalker=" .. tostring(target == memory.talker) .. ")")
			Chat:FireClient(target, payload)
		end
	end
end

-- ============ hearing players ============
Chat.OnServerEvent:Connect(function(plr, msg)
	if typeof(msg) ~= "string" then return end
	msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
	if #msg == 0 or msg:sub(1, 1) == "!" then return end

	local d = distToNPC(plr)
	print("[NPCBrain] Heard from " .. plr.Name .. " (dist=" .. math.floor(d) .. "): " .. msg)
	local addressed = msg:lower():find(NPC.name:lower(), 1, true) ~= nil
	local known = memory.talker == plr or memory.following == plr
	if not addressed and d > HEAR_RANGE and not known then
		print("[NPCBrain] Ignored (too far, HEAR_RANGE=" .. HEAR_RANGE .. ", addressed=" .. tostring(addressed) .. ", known=" .. tostring(known) .. ")")
		return -- too far to be interesting, and they were not talking to us
	end

	-- engage: stop, face them, think, answer
	memory.talker = plr
	memory.lastConverse = os.clock()
	state = "CONVERSE"
	humanoid.WalkSpeed = 12
	stopWalk()
	local tRoot = charRoot(plr)
	if tRoot then setLookTarget(tRoot.Position) end

	task.spawn(function()
		sendNpc("...") -- thinking
		local thinkTime = 1.2 + math.random() * 1.6
		task.wait(thinkTime)
		if memory.talker ~= plr then
			print("[NPCBrain] Thinking cancelled - talker changed")
			return
		end
		local intent = nlu(msg)
		print("[NPCBrain] Intent: " .. intent)
		if intent == "follow" then
			memory.following = plr
		elseif intent == "stop" then
			memory.following = nil
		end
		sendNpc(respond(plr, intent, msg))
	end)
end)

-- ============ the brain (autonomous decisions) ============
-- Movement is throttled hard: Humanoid:MoveTo() is a server-side pathfinding
-- request, and snapping CFrame fights the physics engine. Re-issuing either
-- every second for no reason is the #1 way to lag a live server.
local currentGoal = nil
local lastPos = hrp.Position
local lastMovedAt = os.clock()

-- smooth turning: a low-frequency task gradually rotates the rig toward
-- lookTarget (only set while standing still) so it never snaps or twitches.
task.spawn(function()
	while true do
		task.wait(0.05)
		local t = lookTarget
		if t then
			local dir = Vector3.new(t.X - hrp.Position.X, 0, t.Z - hrp.Position.Z)
			local len = dir.Magnitude
			if len >= 0.1 then
				dir = dir / len
				local desired = CFrame.lookAt(hrp.Position, hrp.Position + dir)
				local angle = math.acos(math.clamp(hrp.CFrame.LookVector:Dot(desired.LookVector), -1, 1))
				if angle > 0.02 then
					local axis = hrp.CFrame.LookVector:Cross(dir)
					local dirSign = axis.Y >= 0 and 1 or -1
					local step = math.min(angle, 0.35)
					hrp.CFrame = hrp.CFrame * CFrame.Angles(0, step * dirSign, 0)
				end
			end
		end
	end
end)

local function setGoal(point, speed)
	humanoid.WalkSpeed = speed
	point = Vector3.new(point.X, hrp.Position.Y, point.Z)
	if currentGoal and (point - currentGoal).Magnitude < 3 then
		return -- basically the same goal; do not waste a pathfinding request
	end
	currentGoal = point
	lookTarget = nil -- let the walk animation handle facing while moving
	humanoid:MoveTo(point)
end

local function clearGoal()
	if currentGoal == nil then return end
	currentGoal = nil
	humanoid:MoveTo(hrp.Position) -- cancels any in-flight path
end

local function pickWanderPoint()
	local a = math.random() * math.pi * 2
	local r = 8 + math.random() * 20
	return hrp.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- make the NPC speak on its own when someone walks up to it
local function maybeGreet()
	local now = os.clock()
	if now - memory.lastGreet < 45 then return end
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		if memory.following == plr or memory.talker == plr then return end
		local d = distToNPC(plr)
		if d < 14 and (bestD == nil or d < bestD) then
			best = plr
			bestD = d
		end
	end
	if not best then return end
	if memory.greeted[best.UserId] and now - memory.greeted[best.UserId] < 180 then return end

	memory.greeted[best.UserId] = now
	memory.lastGreet = now
	memory.talker = best
	memory.lastConverse = now
	state = "CONVERSE"
	humanoid.WalkSpeed = 12
	stopWalk()
	local tRoot = charRoot(best)
	if tRoot then setLookTarget(tRoot.Position) end

	task.spawn(function()
		sendNpc("...")
		task.wait(0.9 + math.random() * 1.2)
		if memory.talker == best then
			sendNpc(pick(REPLIES.greeting):gsub("%%s", best.DisplayName or best.Name))
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(1.0)
		local now = os.clock()

		-- how much have we actually moved since the last tick?
		local moved = (hrp.Position - lastPos).Magnitude
		lastPos = hrp.Position
		if moved > 0.5 then lastMovedAt = now end

		-- patrol slower when nobody is close, but never freeze completely
		-- (a frozen NPC reads as "broken" even though it's just a design choice)
		local anyoneNear = false
		for _, plr in ipairs(Players:GetPlayers()) do
			if distToNPC(plr) < 150 then
				anyoneNear = true
				break
			end
		end
		if not anyoneNear then
			-- nobody watching: wander slowly so the NPC still looks alive
			local idleInterval = 10
			if now - lastWander > idleInterval then
				setGoal(pickWanderPoint(), 8)
				state = "WANDER"
				lastMovedAt = now
				lastWander = now
			end
		elseif memory.following then
			-- 1) following a player overrides everything
			local root = charRoot(memory.following)
			if not root then
				memory.following = nil
				state = "IDLE"
			else
				local d = (hrp.Position - root.Position).Magnitude
				if d > 9 then
					local dir = (hrp.Position - root.Position)
					dir = Vector3.new(dir.X, 0, dir.Z).Unit
					setGoal(root.Position + dir * 6, 14)
					state = "FOLLOW"
				else
					clearGoal()
					setLookTarget(root.Position)
					state = "FOLLOW"
				end
			end

		-- 2) conversing: stay put, face the talker, keep talking if they linger
		elseif state == "CONVERSE" then
			clearGoal()
			local tRoot = memory.talker and charRoot(memory.talker)
			if tRoot then
				setLookTarget(tRoot.Position)
			end
			local quiet = now - memory.lastConverse > 12
			local left = memory.talker and distToNPC(memory.talker) > 50
			if quiet or left then
				memory.talker = nil
				lookTarget = nil
				state = "IDLE"
			end

		-- 3) someone walked up: notice them
		elseif state == "IDLE" and now - memory.lastGreet > 30 then
			maybeGreet()

		-- 4) otherwise wander, lazily, only when someone could see it
		else
			-- if we have been standing still for 4+ seconds while trying to
			-- walk somewhere, the goal is unreachable - pick a new one soon
			local stuck = currentGoal ~= nil and now - lastMovedAt > 4
			local interval = state == "IDLE" and 4 or (stuck and 1 or 8)
			if now - lastWander > interval then
				setGoal(pickWanderPoint(), 10 + math.random() * 4)
				state = "WANDER"
				lastMovedAt = now
				lastWander = now
			end
		end
	end
end)

print("[NPCBrain] " .. NPC.name .. " is awake and thinking.")
