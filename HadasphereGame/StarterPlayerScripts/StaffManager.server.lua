--[[
	Hadasphere StaffManager - server (Script).
	Staff system:
	  - chat commands (!help, !team, !kick, !tp, !freeze, !heal, !give,
	    !announce, !staff, !setstaff) gated by StaffLevel permissions
	  - handles the StaffAction RemoteEvent used by the staff GUI
	  - uses TeamService (assign/notify) + PlayerDataService (persist)
]]

local Players = game:GetService("Players")
local _Chat = game:GetService("Chat")

local TeamService = require(script.Parent:WaitForChild("TeamService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local PlayerConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PlayerConfig"))

-- ensure teams + remotes exist regardless of script execution order
TeamService.Setup()

local StaffManager = {}

local function level(plr)
	return TeamService.staffLevel(plr)
end

local function perm(plr, action)
	return PlayerConfig.Can(level(plr), action)
end

local function findPlayer(name)
	name = (name or ""):lower()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Name:lower():sub(1, #name) == name then
			return plr
		end
	end
	return nil
end

local function charOf(plr)
	return plr.Character or nil
end

local function hrpOf(plr)
	local ch = charOf(plr)
	return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local function humanoidOf(plr)
	local ch = charOf(plr)
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function broadcast(title, text)
	for _, plr in ipairs(Players:GetPlayers()) do
		TeamService.notify(plr, title, text)
	end
end

-- ============ command implementations ============
local commands = {}

commands.help = function(plr)
	TeamService.notify(plr, "Staff commands",
		"!team <name>, !kick <name>, !tp <name> [to], !freeze <name>, "
		.. "!heal <name|all>, !give <name> <item>, !announce <msg>, "
		.. "!staff <name> <level>, !setstaff <name> <level>")
end

commands.team = function(plr, args)
	TeamService.assignTeam(plr, args[1], false)
end

commands.kick = function(plr, args)
	if not perm(plr, "Kick") then
		TeamService.notify(plr, "Access denied", "Kick requires the Head role.")
		return
	end
	local target = findPlayer(args[1])
	if not target then
		TeamService.notify(plr, "Kick", "Player not found.")
		return
	end
	if level(target) >= level(plr) and target ~= plr then
		TeamService.notify(plr, "Kick", "You cannot kick a player at or above your level.")
		return
	end
	target:Kick("[Staff] " .. plr.Name .. " kicked you" .. (args[2] and (": " .. args[2]) or "."))
end

commands.tp = function(plr, args)
	if not perm(plr, "Teleport") then
		TeamService.notify(plr, "Access denied", "Teleport requires the Head role.")
		return
	end
	local a = findPlayer(args[1])
	local b = args[2] and findPlayer(args[2]) or plr
	if not a or not b then
		TeamService.notify(plr, "Teleport", "Player not found.")
		return
	end
	local targetHrp = hrpOf(a)
	local destHrp = hrpOf(b)
	if not targetHrp or not destHrp then return end
	targetHrp.CFrame = destHrp.CFrame * CFrame.new(0, 3, 0)
	TeamService.notify(plr, "Teleport", a.Name .. " -> " .. b.Name)
end

commands.freeze = function(plr, args)
	if not perm(plr, "Freeze") then
		TeamService.notify(plr, "Access denied", "Freeze requires the Head role.")
		return
	end
	local target = findPlayer(args[1])
	if not target then
		TeamService.notify(plr, "Freeze", "Player not found.")
		return
	end
	local ch = charOf(target)
	if ch then ch:SetAttribute("Frozen", not (ch:GetAttribute("Frozen") or false)) end
	TeamService.notify(plr, "Freeze", target.Name .. (ch and ch:GetAttribute("Frozen") and " frozen." or " unfrozen."))
end

commands.heal = function(plr, args)
	if not perm(plr, "Heal") then
		TeamService.notify(plr, "Access denied", "Heal requires staff level.")
		return
	end
	local targets = {}
	if args[1] == "all" then
		targets = Players:GetPlayers()
	elseif args[1] then
		local t = findPlayer(args[1])
		if t then targets = { t } end
	else
		targets = { plr }
	end
	for _, t in ipairs(targets) do
		local hum = humanoidOf(t)
		if hum then hum.Health = hum.MaxHealth end
		local ch = charOf(t)
		if ch then
			ch:SetAttribute("Sanity", ch:GetAttribute("MaxSanity") or 100)
			ch:SetAttribute("Energy", ch:GetAttribute("MaxEnergy") or 100)
		end
	end
	TeamService.notify(plr, "Heal", "Restored " .. (#targets == 1 and targets[1].Name or #targets .. " players") .. ".")
end

commands.give = function(plr, args)
	if not perm(plr, "GiveItem") then
		TeamService.notify(plr, "Access denied", "Give requires staff level.")
		return
	end
	local target = args[1] and findPlayer(args[1]) or plr
	local item = args[2]
	if not item then
		TeamService.notify(plr, "Give", "Usage: !give <name> <item>")
		return
	end
	local data = PlayerDataService.GetData(target)
	data.Inventory = data.Inventory or {}
	data.Inventory[item] = (data.Inventory[item] or 0) + 1
	TeamService.notify(target, "Item received", item)
	TeamService.notify(plr, "Give", "Gave " .. item .. " to " .. target.Name)
end

commands.announce = function(plr, args)
	if not perm(plr, "Announce") then
		TeamService.notify(plr, "Access denied", "Announce requires staff level.")
		return
	end
	local msg = table.concat(args, " ")
	if msg == "" then return end
	broadcast("Announcement", msg)
end

commands.staff = function(plr, args)
	if not perm(plr, "SetStaff") then
		TeamService.notify(plr, "Access denied", "SetStaff requires the Director role.")
		return
	end
	local target = findPlayer(args[1])
	local newLevel = tonumber(args[2])
	if not target or not newLevel then
		TeamService.notify(plr, "SetStaff", "Usage: !setstaff <name> <level 0-3>")
		return
	end
	newLevel = math.clamp(math.floor(newLevel), 0, 3)
	PlayerDataService.SetStaffLevel(target, newLevel)
	TeamService.notify(plr, "SetStaff", target.Name .. " is now level " .. newLevel .. ".")
	TeamService.notify(target, "Staff level", "You are now level " .. newLevel .. ".")
end

-- ============ chat handler ============
local function onChat(plr, msg)
	msg = (msg or ""):gsub("^%s+", "")
	if msg:sub(1, 1) ~= "!" then return end
	local parts = {}
	for part in msg:gmatch("[^%s]+") do
		parts[#parts + 1] = part
	end
	local cmd = (parts[1] or ""):gsub("^!", ""):lower()
	local handler = commands[cmd]
	if not handler then
		TeamService.notify(plr, "Unknown command", "Type !help to see commands.")
		return
	end
	local ok, err = pcall(handler, plr, { table.unpack(parts, 2) })
	if not ok then
		warn("[StaffManager] command error:", err)
	end
end

Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		onChat(plr, msg)
	end)
end)

-- ============ staff GUI actions ============
local actions = {
	SetTeam = function(plr, payload)
		local teamName = payload.target
		if typeof(teamName) == "string" then
			TeamService.assignTeam(plr, teamName, false)
		end
	end,
	Kick = function(plr, payload)
		commands.kick(plr, { payload.target })
	end,
	Teleport = function(plr, payload)
		commands.tp(plr, { payload.target })
	end,
	Freeze = function(plr, payload)
		commands.freeze(plr, { payload.target })
	end,
	Heal = function(plr, payload)
		commands.heal(plr, payload.target == "all" and { "all" } or { payload.target })
	end,
	TeleportTo = function(plr, payload)
		local target = findPlayer(payload.target)
		local hrp = target and hrpOf(target) or nil
		local selfHrp = hrpOf(plr)
		if not hrp or not selfHrp or not perm(plr, "Teleport") then return end
		selfHrp.CFrame = hrp.CFrame * CFrame.new(0, 3, 0)
	end,
}

TeamService.StaffAction.OnServerEvent:Connect(function(plr, actionName, payload)
	if typeof(actionName) ~= "string" or type(payload) ~= "table" then return end
	local handler = actions[actionName]
	if not handler then return end
	local ok, err = pcall(handler, plr, payload)
	if not ok then
		warn("[StaffManager] action error:", err)
	end
end)

-- handle players already in game
for _, plr in ipairs(Players:GetPlayers()) do
	plr.Chatted:Connect(function(msg)
		onChat(plr, msg)
	end)
end

-- ============ email chat ============
-- In-game chat runs through this remote; the default Roblox chat UI is
-- replaced by the email-styled window on the client. Non-command messages
-- are broadcast as "emails" to the sender plus anyone within hearing range
-- (proximity chat — like talking in person).
local function charRoot(plr)
	local ch = plr and plr.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso") or ch.PrimaryPart
end

-- everyone the sender can "reach": the sender themselves, anyone close enough,
-- plus every staff member (staff can hear the whole facility)
local function chatTargets(plr)
	local root = charRoot(plr)
	local range = PlayerConfig.Communication.ChatRange
	local senderStaff = level(plr) > 0
	local targets = { plr }
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= plr then
			local oroot = charRoot(other)
			local near = root and oroot and (root.Position - oroot.Position).Magnitude <= range
			if senderStaff or near or level(other) > 0 then
				table.insert(targets, other)
			end
		end
	end
	return targets
end

TeamService.Chat.OnServerEvent:Connect(function(plr, msg)
	if typeof(msg) ~= "string" then return end
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #msg == 0 then return end
	if #msg > 200 then msg = msg:sub(1, 200) end
	if msg:sub(1, 1) == "!" then
		onChat(plr, msg)
		return
	end
	local payload = {
		from = plr.DisplayName or plr.Name,
		uid = plr.UserId,
		time = os.time(),
		text = msg,
		staff = level(plr) > 0,
	}
	for _, target in ipairs(chatTargets(plr)) do
		TeamService.Chat:FireClient(target, payload)
	end
end)

-- live typing indicator: relay start/stop to everyone within hearing range
TeamService.Typing.OnServerEvent:Connect(function(plr, typing)
	if type(typing) ~= "boolean" then return end
	for _, target in ipairs(chatTargets(plr)) do
		if target ~= plr then
			TeamService.Typing:FireClient(target, {
				uid = plr.UserId,
				typing = typing,
			})
		end
	end
end)

print("[StaffManager] Staff system ready.")

return StaffManager
