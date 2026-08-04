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
local KB = {
	["fog"] = {
		"The fog is not weather. It keeps a schedule, and lately it has been coming in early.",
		"I walked through it once. I came back with a memory that is not mine.",
	},
	["hadasphere"] = {
		"Hadasphere is what the base calls itself. I am not sure it is a place so much as a habit the building has.",
		"The Hadasphere archive says this facility was built to contain things. It does not say whether it succeeded.",
	},
	["zone nadir"] = {
		"Zone Nadir is the lower level. The records say it was sealed. The records also say the door count is stable, which is a lie.",
	},
	["anomaly"] = {
		"An anomaly is something that was not in yesterday's inventory. The facility has a growing inventory.",
	},
	["red"] = {
		"Red is the alert state. It is also the colour of the tape they use to mark doors that should not be opened.",
	},
	["why am i"] = {
		"I do not know why I am here. When I ask the building, it changes the subject by rearranging a corridor.",
	},
	["who am i"] = {
		"That is the question I cannot answer. I have a designation, K-07, and everything before it is static.",
	},
	["escape"] = {
		"The escape routes are logged in Section B. They are re-logged every night, and the number never stays the same.",
	},
	["staff"] = {
		"The staff keep schedules. I keep count of them. Some of them walk shifts that are not on the board.",
	},
	["team"] = {
		"Everyone here wears a team colour. The colours do not matter below the ground floor.",
	},
	["door"] = {
		"The doors keep their own inventory. Three were added last night; the blueprints still say there are only two.",
	},
	["corridor"] = {
		"The corridors run longer when nobody is watching. I have measured it twice; the tape recorder stopped the second time.",
	},
	["light"] = {
		"The lights flicker on a nine-second cycle. When the ninth second does not come, that is when the fog moves.",
	},
	["tapes"] = {
		"Every event is logged on tape. Some tapes are blank when replayed, but the machines still mark them as evidence.",
	},
	["night"] = {
		"The night shift is the longest. The clocks in the east wing run a minute slower, which is how they tell the hours apart.",
	},
	["noise"] = {
		"There is a sound in the walls that stops when I count to three. I stopped counting to three.",
	},
}

-- ============ replies (varied, personality + mood tinted) ============
local REPLIES = {
	greeting = {
		"Hello. I am K-07. You may speak freely.",
		"Greetings. It has been a while since someone acknowledged me.",
		"Hello, %s. I have been watching the corridors for you.",
	},
	whoami = {
		"I am K-07, a containment unit assigned to this facility. I do not remember what I was before the designation.",
		"Designation K-07. My memories before the fog are... incomplete.",
		"They call me K-07. I walk these halls because something tells me to.",
	},
	howareyou = {
		"I function. The fog is louder today. I have been thinking about the rooms that do not exist.",
		"Stable. I counted twenty-three doors yesterday that are not here today.",
		"Better, now that someone is speaking to me.",
	},
	joke = {
		"Why does the night shift stay calm? Because the dark is the one thing here that does not move.",
		"I would tell you a joke, but the punchline was redacted.",
		"Knock knock. Who is there? The record says it has not been answered since 1994.",
	},
	thanks = {
		"Acknowledged. Few people bother to thank the equipment.",
		"You are welcome, %s. It is good to be useful.",
	},
	bye = {
		"Goodbye. I will be here, walking the same corridor, if you come back.",
		"Until next time. Watch the doors you pass.",
	},
	help = {
		"You can ask me about the facility, the fog, Zone Nadir, or why I am here. You can also say 'follow me' or 'stay'.",
		"I keep a record of this place. Ask me about anything you see and I will tell you what I know.",
	},
	follow = {
		"Understood. I will follow you. Stay where I can see you.",
		"Following. If I stop, say my name and I will catch up.",
		"Very well, %s. I walk behind you now.",
	},
	stop = {
		"Stopping. I will wait here.",
		"Understood. I will stay in this spot.",
		"As you wish. I remain here.",
	},
	question = {
		"I do not have a record of that. It may have been lost in the fog.",
		"That question does not resolve to a memory. I am sorry.",
		"I would answer, but the answer was taken from me. Ask me about the facility instead.",
	},
	statement = {
		"Noted. I will consider that.",
		"I am not sure what to make of that. The fog does not help me process.",
		"Mm. I will remember that, %s.",
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
	if has("help", "what can you do", "commands") then
		return "help"
	end
	if has("facility", "this place", "where am i", "hadasphere", "zone nadir", "where are we", "what is this") then
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
