--[[
	Hadasphere PlayerConfig - shared module (server + client).
	Player stat definitions (health / sanity / energy / ammo),
	energy (stamina) drain rates, and staff levels + permissions.
	StaffLevel is a Player attribute (0 = subject, 1 = junior staff,
	2 = security, 3 = director). Mirrors TeamConfig.RequiredStaff.
]]

local PlayerConfig = {}

-- base stat defaults (per-character attributes)
PlayerConfig.DefaultStats = {
	MaxHealth = 100,
	MaxSanity = 100,
	MaxEnergy = 100,
	Sanity = 100,
	Energy = 100,
	MagAmmo = 0,
	Reserve = 0,
}

-- movement tuning
PlayerConfig.Movement = {
	JumpHeight = 5, -- default is 50; low = small, human-feeling hop
}

-- energy (stamina) tuning: drain while moving, regen while idle
PlayerConfig.Energy = {
	WalkSpeed = 16,
	RunSpeed = 22,
	ExhaustSpeed = 10, -- forced slow speed when exhausted
	TiredSpeed = 14,   -- slowest "tired jog" speed (just under the walk/run blend)
	TiredThreshold = 30, -- below this energy, movement starts slowing down
	IdleRegen = 8,     -- energy/sec recovered while standing still
	DrainWalk = 4,     -- energy/sec spent while walking
	DrainRun = 8,      -- energy/sec spent while running
	ExhaustThreshold = 5, -- below this, forced into ExhaustSpeed
	RecoverThreshold = 25, -- above this, allowed to run again
	JumpCost = 15,     -- energy spent per jump
	JumpCooldown = 0.8, -- seconds between jumps
}

-- communication tuning: spoken (chat) range in studs
PlayerConfig.Communication = {
	ChatRange = 60, -- players further away don't hear/see the message
}

-- staff level metadata (index by level)
PlayerConfig.StaffLevels = {
	{
		Level = 0,
		Name = "Subject",
		Color = Color3.fromRGB(150, 150, 160),
		Description = "Search, help, escape. That's all you need to do.",
	},
	{
		Level = 1,
		Name = "Staff",
		Color = Color3.fromRGB(90, 160, 255),
		Description = "Keep order. Enforce the rules. Report what doesn't belong.",
	},
	{
		Level = 2,
		Name = "Head",
		Color = Color3.fromRGB(200, 90, 90),
		Description = "Direct the staff. Contain the strange. Keep the base quiet.",
	},
	{
		Level = 3,
		Name = "Director",
		Color = Color3.fromRGB(160, 120, 255),
		Description = "You run the facility. Everyone answers to you.",
	},
}

-- which staff actions are allowed at each level
PlayerConfig.Permissions = {
	Kick = 2,
	Ban = 3,
	Teleport = 2,
	Freeze = 2,
	GiveItem = 1,
	Heal = 1,
	SetTeam = 1,
	SetStaff = 3,
	Announce = 1,
	ManageBase = 3,
}

function PlayerConfig.StaffLevelInfo(level)
	for _, info in ipairs(PlayerConfig.StaffLevels) do
		if info.Level == level then return info end
	end
	return PlayerConfig.StaffLevels[1]
end

function PlayerConfig.Can(level, action)
	local required = PlayerConfig.Permissions[action]
	return required ~= nil and level >= required
end

return PlayerConfig
