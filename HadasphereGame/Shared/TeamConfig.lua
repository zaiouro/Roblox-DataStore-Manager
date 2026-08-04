--[[
	Hadasphere TeamConfig - shared module (server + client).
	Teams mirror the Discord roles (Subjects, Researchers, Medical,
	Engineering, Security, Directors). RequiredStaff gates who may join
	staff teams (player "StaffLevel" attribute, set in Studio per player).
]]

local TeamConfig = {}

TeamConfig.DefaultTeam = "Subjects"

TeamConfig.Teams = {
	Subjects = {
		Color = BrickColor.new("Institutional white"),
		RequiredStaff = 0,
		Description = "Test subjects of the facility.",
		Spawn = CFrame.new(0, 2, -264),
	},
	Researchers = {
		Color = BrickColor.new("Bright blue"),
		RequiredStaff = 1,
		Description = "Lab coats studying the anomaly.",
		Spawn = CFrame.new(264, 2, 0),
	},
	Medical = {
		Color = BrickColor.new("Bright red"),
		RequiredStaff = 1,
		Description = "Keep subjects alive. Long enough.",
		Spawn = CFrame.new(264, 2, -72),
	},
	Engineering = {
		Color = BrickColor.new("Bright orange"),
		RequiredStaff = 1,
		Description = "Keep the lights and doors running.",
		Spawn = CFrame.new(-93, 2, 225),
	},
	Security = {
		Color = BrickColor.new("Dark stone grey"),
		RequiredStaff = 2,
		Description = "Contain the subjects. At any cost.",
		Spawn = CFrame.new(20, 2, 0), -- main hall, east side
	},
	Directors = {
		Color = BrickColor.new("Bright violet"),
		RequiredStaff = 3,
		Description = "The ones who run the facility.",
		Spawn = CFrame.new(-9, 21.5, 28), -- tower floor 2 (west plate center)
	},
}

-- attributes applied to every new character on spawn
TeamConfig.DefaultAttributes = {
	Sanity = 100,
	MaxSanity = 100,
	Energy = 100,
	MaxEnergy = 100,
	MagAmmo = 0,
	Reserve = 0,
}

function TeamConfig.IsTeam(name)
	return TeamConfig.Teams[name] ~= nil
end

function TeamConfig.GetTeam(name)
	return TeamConfig.Teams[name]
end

function TeamConfig.TeamForStaffLevel(level)
	local best = TeamConfig.DefaultTeam
	local bestReq = -1
	for name, def in pairs(TeamConfig.Teams) do
		if def.RequiredStaff <= level and def.RequiredStaff > bestReq then
			best = name
			bestReq = def.RequiredStaff
		end
	end
	return best
end

return TeamConfig
