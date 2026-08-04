--[[
	Hadasphere PlayerDataService - server-only module (ModuleScript).
	Player system:
	  - per-player Profile (PlayerData) with DataStore save/load
	  - character stat attributes (health / sanity / energy / ammo)
	  - energy (stamina) drain while moving, regen while idle
	  - persistence: StaffLevel, Team, and stats across sessions
]]

local _Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerConfig"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))

local PlayerDataService = {}

-- make sure remotes (Sprint, etc.) exist before connecting below
TeamService.Setup()

local KEY_PREFIX = "Player_"

local store
local storeOk, storeErr = pcall(function()
	return DataStoreService:GetDataStore("HadaspherePlayerData", "v1")
end)
if storeOk then
	store = storeErr
else
	store = nil
	warn("[PlayerData] DataStore unavailable, persistence disabled:", tostring(storeErr))
end

local profiles = {} -- [plr] = { data = { ... }, loaded = bool, sessionStart = tick() }

local function defaultData()
	return {
		StaffLevel = 0,
		Team = nil, -- persisted team (reapplied on join when allowed)
		Coins = 0,
		Stats = {
			MaxHealth = PlayerConfig.DefaultStats.MaxHealth,
			MaxSanity = PlayerConfig.DefaultStats.MaxSanity,
			MaxEnergy = PlayerConfig.DefaultStats.MaxEnergy,
		},
		Inventory = {}, -- reserved for future item system
	}
end

local function sanitize(data)
	local d = defaultData()
	if type(data) == "table" then
		d.StaffLevel = type(data.StaffLevel) == "number" and math.clamp(data.StaffLevel, 0, 3) or 0
		d.Team = type(data.Team) == "string" and data.Team or nil
		d.Coins = type(data.Coins) == "number" and data.Coins or 0
		if type(data.Stats) == "table" then
			d.Stats.MaxHealth = type(data.Stats.MaxHealth) == "number" and math.clamp(data.Stats.MaxHealth, 1, 1000) or 100
			d.Stats.MaxSanity = type(data.Stats.MaxSanity) == "number" and math.clamp(data.Stats.MaxSanity, 1, 1000) or 100
			d.Stats.MaxEnergy = type(data.Stats.MaxEnergy) == "number" and math.clamp(data.Stats.MaxEnergy, 1, 1000) or 100
		end
		if type(data.Inventory) == "table" then
			d.Inventory = data.Inventory
		end
	end
	return d
end

function PlayerDataService.GetProfile(plr)
	local prof = profiles[plr]
	if not prof then
		prof = { data = defaultData(), loaded = false, modified = false }
		profiles[plr] = prof
	end
	return prof
end

function PlayerDataService.GetData(plr)
	return PlayerDataService.GetProfile(plr).data
end

-- authoritatively set a player's staff level (persists + survives profile load)
function PlayerDataService.SetStaffLevel(plr, level)
	local prof = PlayerDataService.GetProfile(plr)
	prof.modified = true
	prof.data.StaffLevel = level
	plr:SetAttribute("StaffLevel", level)
end

function PlayerDataService.IsLoaded(plr)
	local prof = profiles[plr]
	return prof ~= nil and prof.loaded
end

local function saveProfile(plr)
	local prof = profiles[plr]
	if not prof or not prof.loaded or not store then return end
	prof.data.Team = plr.Team and plr.Team.Name or prof.data.Team
	local ok, err = pcall(function()
		store:SetAsync(KEY_PREFIX .. plr.UserId, prof.data)
	end)
	if not ok then
		warn("[PlayerData] save failed for", plr.Name, ":", err)
	end
end

-- apply persisted + default stats onto a fresh character
local function applyStats(ch, data)
	local hum = ch:FindFirstChild("Humanoid")
	if hum then
		hum.MaxHealth = data.Stats.MaxHealth
		hum.Health = hum.MaxHealth
		ch:SetAttribute("BaseSpeed", PlayerConfig.Energy.WalkSpeed)
	end
	ch:SetAttribute("MaxSanity", data.Stats.MaxSanity)
	ch:SetAttribute("Sanity", data.Stats.MaxSanity)
	ch:SetAttribute("MaxEnergy", data.Stats.MaxEnergy)
	ch:SetAttribute("Energy", data.Stats.MaxEnergy)
	ch:SetAttribute("MagAmmo", 0)
	ch:SetAttribute("Reserve", 0)
end

function PlayerDataService.ApplyCharacter(plr)
	local ch = plr.Character
	if not ch then return end
	local data = PlayerDataService.GetData(plr)
	applyStats(ch, data)
end

-- ============ energy (stamina) loop ============
local active = {}
local sprinting = {}
local energyRepl = {} -- [plr] = { value = num, last = clock } throttled replication

-- ============ jump (stamina cost + cooldown) ============
local JUMP_HEIGHT = PlayerConfig.Movement.JumpHeight or 5
local jumpState = {} -- [plr] = { ready = bool, suppressed = bool }

local function setupJump(plr, ch)
	local hum = ch:WaitForChild("Humanoid")
	hum.JumpHeight = JUMP_HEIGHT
	local jst = { ready = true, suppressed = false }
	jumpState[plr] = jst
	hum.Jumping:Connect(function(jumping)
		if not jumping then return end
		if not jst.ready then return end
		local energy = ch:GetAttribute("Energy") or 0
		if energy < PlayerConfig.Energy.JumpCost then return end
		-- allowed: burn stamina and enter cooldown
		ch:SetAttribute("Energy", energy - PlayerConfig.Energy.JumpCost)
		jst.ready = false
		task.delay(PlayerConfig.Energy.JumpCooldown, function()
			jst.ready = true
		end)
	end)
end

local function energyStep(plr, dt)
	local ch = plr.Character
	if not ch then return end
	local hum = ch:FindFirstChild("Humanoid")
	if not hum then return end

	local energy = ch:GetAttribute("Energy") or PlayerConfig.DefaultStats.MaxEnergy
	local maxEnergy = ch:GetAttribute("MaxEnergy") or PlayerConfig.DefaultStats.MaxEnergy

	local sprint = sprinting[plr] == true
	local exhausted = ch:GetAttribute("Exhausted") == true
	local baseSpeed = ch:GetAttribute("BaseSpeed") or PlayerConfig.Energy.WalkSpeed

	-- how tired we are (0 = fresh, 1 = about to collapse), only relevant
	-- while energy is below the tired threshold
	local tiredThreshold = PlayerConfig.Energy.TiredThreshold
	local exSpeed = PlayerConfig.Energy.ExhaustSpeed
	local function tired01()
		local span = tiredThreshold - PlayerConfig.Energy.ExhaustThreshold
		return math.clamp((tiredThreshold - energy) / span, 0, 1)
	end

	if sprint and not exhausted and energy > PlayerConfig.Energy.RecoverThreshold then
		-- running: burn stamina, move fast (slows down as fatigue builds so
		-- the run animation visibly degrades into a tired jog, then a walk)
		hum.WalkSpeed = PlayerConfig.Energy.RunSpeed
			- (PlayerConfig.Energy.RunSpeed - PlayerConfig.Energy.TiredSpeed) * tired01()
		energy = energy - PlayerConfig.Energy.DrainRun * dt
		if energy <= PlayerConfig.Energy.ExhaustThreshold then
			ch:SetAttribute("Exhausted", true)
		end
	else
		-- not sprinting (walking or idle): stamina regenerates
		if exhausted then
			hum.WalkSpeed = exSpeed
			if energy >= PlayerConfig.Energy.RecoverThreshold then
				ch:SetAttribute("Exhausted", false)
				hum.WalkSpeed = baseSpeed
			end
		elseif energy <= tiredThreshold then
			-- tiring: ease from walking speed down toward the exhausted speed,
			-- which forces the default animation into the walking cycle
			hum.WalkSpeed = baseSpeed - (baseSpeed - exSpeed) * tired01()
		else
			hum.WalkSpeed = baseSpeed
		end
		energy = energy + PlayerConfig.Energy.IdleRegen * dt
	end

	energy = math.clamp(energy, 0, maxEnergy)

	-- throttle replication: don't push the Energy attribute to every client
	-- every frame. Only resend when it moves meaningfully, or at least once
	-- per 0.1s so the HUD bar still updates smoothly.
	local repl = energyRepl[plr]
	if not repl then
		repl = { value = energy, last = os.clock() }
		energyRepl[plr] = repl
		ch:SetAttribute("Energy", energy)
	else
		local now = os.clock()
		if math.abs(energy - repl.value) >= 0.25 or now - repl.last >= 0.1 then
			repl.value = energy
			repl.last = now
			ch:SetAttribute("Energy", energy)
		end
	end

	-- gate jumping: suppress it during cooldown / when out of stamina.
	-- only touches JumpHeight when it has to, so the menu's movement lock
	-- (set by the client) is left alone while the player is allowed to jump.
	local jst = jumpState[plr]
	if jst then
		local canJump = jst.ready and energy >= PlayerConfig.Energy.JumpCost and not exhausted
		if canJump then
			if jst.suppressed then
				hum.JumpHeight = JUMP_HEIGHT
				jst.suppressed = false
			end
		else
			hum.JumpHeight = 0
			jst.suppressed = true
		end
	end
end

TeamService.Sprint.OnServerEvent:Connect(function(plr, on)
	sprinting[plr] = on == true
end)

RunService.Heartbeat:Connect(function(dt)
	for plr in pairs(active) do
		if plr.Parent then
			energyStep(plr, dt)
		else
			active[plr] = nil
		end
	end
end)

-- ============ lifecycle ============
local function onCharacterAdded(plr, ch)
	PlayerDataService.ApplyCharacter(plr)
	active[plr] = true
	setupJump(plr, ch)
end

local function loadPlayer(plr)
	local prof = PlayerDataService.GetProfile(plr)
	prof.loaded = false

	local ok, data
	if store then
		ok, data = pcall(function()
			return store:GetAsync(KEY_PREFIX .. plr.UserId)
		end)
	end

	-- if staff/admin changed the profile while it was loading, don't clobber it
	if not prof.modified then
		prof.data = sanitize(ok and data or nil)
	end
	prof.loaded = true

	-- apply persisted staff level + team
	-- (with no DataStore, respect a level already assigned this session)
	if store or (plr:GetAttribute("StaffLevel") or 0) == 0 then
		plr:SetAttribute("StaffLevel", prof.data.StaffLevel)
	end
	if prof.data.Team and TeamService.GetTeamInstance(prof.data.Team) then
		TeamService.assignTeam(plr, prof.data.Team, true)
	else
		TeamService.assignTeam(plr, TeamService.AutoTeamName(plr), true)
	end

	if plr.Character then
		PlayerDataService.ApplyCharacter(plr)
		active[plr] = true
	end
end

function PlayerDataService.PlayerAdded(plr)
	plr:SetAttribute("StaffLevel", 0)
	plr.CharacterAdded:Connect(function(ch)
		onCharacterAdded(plr, ch)
	end)
	task.spawn(loadPlayer, plr)
end

function PlayerDataService.PlayerRemoving(plr)
	saveProfile(plr)
	profiles[plr] = nil
	active[plr] = nil
	sprinting[plr] = nil
	jumpState[plr] = nil
end

-- autosave every 5 minutes for crash safety
task.spawn(function()
	while true do
		task.wait(300)
		for plr in pairs(profiles) do
			saveProfile(plr)
		end
	end
end)

return PlayerDataService
