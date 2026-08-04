--[[
	Hadasphere TeamService - server-only module (ModuleScript).
	Single source of truth for the team system:
	  - creates Teams + per-team SpawnLocations
	  - creates HadasphereRemotes folder (SetTeam, Notify, StaffAction)
	  - assignTeam / staffLevel / notify helpers used by the
	    TeamManager, PlayerService, and StaffManager scripts.
]]

local _Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TeamConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeamConfig"))

local TeamService = {}

-- wipe any pre-existing teams + spawns (safe re-run in Studio play mode)
local function cleanSlate()
	for _, t in ipairs(Teams:GetTeams()) do
		t:Destroy()
	end
	local oldSpawns = Workspace:FindFirstChild("TeamSpawns")
	if oldSpawns then oldSpawns:Destroy() end
end

-- remotes folder (rebuilt each time to stay in sync with the code)
local remotes
local function buildRemotes()
	local old = ReplicatedStorage:FindFirstChild("HadasphereRemotes")
	if old then old:Destroy() end
	remotes = Instance.new("Folder")
	remotes.Name = "HadasphereRemotes"
	remotes.Parent = ReplicatedStorage

	local function makeRemote(name, class)
		local r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
		return r
	end

	TeamService.SetTeam = makeRemote("SetTeam", "RemoteEvent")
	TeamService.Notify = makeRemote("Notify", "RemoteEvent")
	TeamService.StaffAction = makeRemote("StaffAction", "RemoteEvent")
	TeamService.Sprint = makeRemote("Sprint", "RemoteEvent")
	TeamService.Chat = makeRemote("Chat", "RemoteEvent")
	TeamService.Typing = makeRemote("Typing", "RemoteEvent")
end

local teamInstances = {}
local setupDone = false

local function makeTeam(name, def)
	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = def.Color
	team.AutoAssignable = false
	team.Parent = Teams

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = name .. "Spawn"
	spawn.TeamColor = def.Color
	spawn.Neutral = false
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = def.Spawn
	spawn.Duration = 5
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = Workspace:FindFirstChild("TeamSpawns")

	teamInstances[name] = team
	return team
end

function TeamService.Setup()
	if setupDone then return teamInstances end
	setupDone = true
	cleanSlate()
	buildRemotes()

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "TeamSpawns"
	spawnFolder.Parent = Workspace

	for name, def in pairs(TeamConfig.Teams) do
		makeTeam(name, def)
	end
	return teamInstances
end

function TeamService.GetTeamInstance(name)
	return teamInstances[name]
end

function TeamService.staffLevel(plr)
	return plr:GetAttribute("StaffLevel") or 0
end

function TeamService.notify(plr, title, text)
	if TeamService.Notify then
		TeamService.Notify:FireClient(plr, title, text)
	end
end

-- authoritative team assignment; returns true on success
function TeamService.assignTeam(plr, teamName, silent)
	if not TeamConfig.IsTeam(teamName) then return false end
	local def = TeamConfig.GetTeam(teamName)
	if TeamService.staffLevel(plr) < def.RequiredStaff then
		if not silent then
			TeamService.notify(plr, "Access denied", "You are not authorised to join " .. teamName .. ".")
		end
		return false
	end
	local team = teamInstances[teamName]
	if not team then return false end
	plr.Team = team
	if not silent then
		TeamService.notify(plr, "Team", "You are now part of " .. teamName .. ".")
	end
	return true
end

-- choose the best team a player qualifies for by staff level
function TeamService.AutoTeamName(plr)
	local level = TeamService.staffLevel(plr)
	return TeamConfig.TeamForStaffLevel(level)
end

return TeamService
