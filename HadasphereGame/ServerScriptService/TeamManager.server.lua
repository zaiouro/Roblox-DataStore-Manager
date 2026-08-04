--[[
	Hadasphere TeamManager - server bootstrap (Script).
	Loads TeamService (teams, spawns, remotes) and PlayerDataService
	(player data, character stats, energy), then wires the join-time
	team auto-assignment + SetTeam remote.
]]

local Players = game:GetService("Players")

local TeamService = require(script.Parent:WaitForChild("TeamService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

-- build teams, spawns, and remotes before any player joins
TeamService.Setup()

Players.PlayerAdded:Connect(function(plr)
	PlayerDataService.PlayerAdded(plr)
	-- quick default team while their profile loads
	if not plr.Team then
		TeamService.assignTeam(plr, "Subjects", true)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	PlayerDataService.PlayerRemoving(plr)
end)

-- handle players already in the game (Studio play / late-load)
for _, plr in ipairs(Players:GetPlayers()) do
	PlayerDataService.PlayerAdded(plr)
	if not plr.Team then
		TeamService.assignTeam(plr, "Subjects", true)
	end
end

print("[TeamManager] Teams + player data ready.")

task.wait(3)
local names = {}
for _, t in ipairs(game:GetService("Teams"):GetTeams()) do
	names[#names + 1] = t.Name
end
print("[TeamManager] Teams ready:", table.concat(names, ", "))
