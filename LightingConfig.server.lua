--[[
	Hadasphere LightingConfig - server (Script).
	Applies a moody myth-RP atmosphere at runtime (evening light, soft haze)
	with horror as seasoning -- never so dark the world is hard to read.
	Everything is guarded; a missing Atmosphere or a locked property can
	never stop the game from loading.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- fog sheets populated by apply(), driven by the fog event below
local fogSheets = {}
local AMBIENT = Color3.fromRGB(88, 96, 90)
local SHIFT_TOP = Color3.fromRGB(150, 150, 138)
local SHIFT_BOTTOM = Color3.fromRGB(40, 44, 42)
local FOG = Color3.fromRGB(52, 64, 82)

local function apply()
	pcall(function()
		Lighting.ClockTime = 15
	end)
	pcall(function()
		Lighting.GeographicLatitude = 45
	end)
	pcall(function()
		Lighting.Brightness = 1.1
	end)
	pcall(function()
		Lighting.ExposureCompensation = 0.9
	end)
	pcall(function()
		Lighting.Ambient = AMBIENT
	end)
	pcall(function()
		Lighting.OutdoorAmbient = AMBIENT
	end)
	pcall(function()
		Lighting.ColorShift_Top = SHIFT_TOP
	end)
	pcall(function()
		Lighting.ColorShift_Bottom = SHIFT_BOTTOM
	end)
	pcall(function()
		Lighting.FogColor = FOG
	end)
	pcall(function()
		Lighting.FogStart = 90
	end)
	pcall(function()
		Lighting.FogEnd = 550
	end)
	pcall(function()
		Lighting.GlobalShadows = true
	end)
	pcall(function()
		Lighting.EnvironmentDiffuseScale = 0.6
	end)
	pcall(function()
		Lighting.EnvironmentSpecularScale = 0.4
	end)

	-- soft haze, not a wall of fog
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmo then
		atmo = Instance.new("Atmosphere")
		atmo.Name = "HadasphereHaze"
		atmo.Parent = Lighting
	end
	pcall(function()
		atmo.Density = 0.18
	end)
	pcall(function()
		atmo.Offset = 0.5
	end)
	pcall(function()
		atmo.Color = FOG
	end)
	pcall(function()
		atmo.Decay = Color3.fromRGB(96, 104, 98)
	end)
	pcall(function()
		atmo.Glare = 0.1
	end)
	pcall(function()
		atmo.Haze = 1.8
	end)

	-- ambient floating dust (a subtle constant particle field around spawn
	-- areas makes an empty room read as "occupied by the dark")
	local emitterParent = Lighting:FindFirstChild("DustField")
	if not emitterParent then
		emitterParent = Instance.new("Attachment")
		emitterParent.Name = "DustField"
		emitterParent.Position = Vector3.new(0, 30, 0)
		emitterParent.Parent = Lighting
	end

	local spawn = game:GetService("Workspace"):FindFirstChild("SpawnLocation")
	if spawn and not spawn:FindFirstChild("DustEmitter") then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "DustEmitter"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.LightEmission = 0
		emitter.LightInfluence = 0
		emitter.Speed = NumberRange.new(0.2, 0.6)
		emitter.Lifetime = NumberRange.new(6, 10)
		emitter.Rate = 4
		emitter.Size = NumberSequence.new(0.15)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 0.95),
		})
		emitter.Color = ColorSequence.new(Color3.fromRGB(120, 140, 128))
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = spawn
	end

	-- fog sheets: large flat transparent parts at the map edge that
	-- drift inward during a fog event. Unlike particle emitters (which
	-- always look like discrete puffs), sheets create a continuous wall
	-- of fog that rolls in from outside the world.
	local fogAnchor = Workspace:FindFirstChild("FogAnchor")
	if not fogAnchor then
		fogAnchor = Instance.new("Part")
		fogAnchor.Name = "FogAnchor"
		fogAnchor.Anchored = true
		fogAnchor.CanCollide = false
		fogAnchor.Transparency = 1
		fogAnchor.Size = Vector3.new(1, 1, 1)
		local at = spawn and spawn.Position or Vector3.new(0, 10, 0)
		fogAnchor.CFrame = CFrame.new(at)
		fogAnchor.Parent = Workspace
	end

	local center = fogAnchor.CFrame.Position
	local sheetCount = 8
	local sheetRadius = 350
	local sheetSize = Vector3.new(400, 1, 400)
	for d = 0, sheetCount - 1 do
		local ang = (d / sheetCount) * math.pi * 2
		local off = Vector3.new(
			math.cos(ang) * sheetRadius,
			20,
			math.sin(ang) * sheetRadius
		)
		local sheet = Instance.new("Part")
		sheet.Name = "FogSheet"
		sheet.Anchored = true
		sheet.CanCollide = false
		sheet.Size = sheetSize
		sheet.Material = Enum.Material.SmoothPlastic
		sheet.Color = FOG
		sheet.Transparency = 0.92
		sheet.CFrame = CFrame.new(center + off, center)
		sheet.Parent = fogAnchor
		fogSheets[#fogSheets + 1] = {
			part = sheet,
			home = center + off,
			target = center + off * 0.22, -- drift to ~80 studs from center
		}
	end
end

apply()
print("[LightingConfig] dark atmosphere applied")

-- ============ fog event ============
-- The NPC lore: "the lights flicker on a nine-second cycle. When the ninth
-- second does not come, that is when the fog moves." So the fog is not a
-- background loop - it is an event: the lights stutter, then the fog sheets
-- roll in from beyond the world, squat over the map, and eventually pull back.
local CLEAR_END = 550
local CLEAR_START = 90
local FOGGED_END = 55
local FOGGED_START = 6
local EVENT_MIN = 80
local EVENT_MAX = 150
local ROLL_IN = 25
local HOLD_TIME = 45
local LIFT_TIME = 22

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function setFog(fogStart, fogEnd)
	pcall(function()
		Lighting.FogStart = fogStart
	end)
	pcall(function()
		Lighting.FogEnd = fogEnd
	end)
end

local function setAtmoDensity(d)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		pcall(function()
			atmo.Density = d
		end)
	end
end

local function tweenSheets(targetDist, duration)
	for _, s in ipairs(fogSheets) do
		local startPos = s.part.CFrame.Position
		local endPos = s.home + (s.target - s.home) * targetDist
		local steps = math.max(1, math.floor(duration / 0.25))
		for i = 1, steps do
			local t = i / steps
			s.part.CFrame = CFrame.new(lerp(startPos, endPos, t), s.part.CFrame.Position)
			task.wait(0.25)
		end
	end
end

local function broadcast(title, text)
	local TeamService = require(script.Parent:WaitForChild("TeamService"))
	pcall(TeamService.Setup)
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		pcall(function()
			TeamService.Notify:FireClient(plr, title, text)
		end)
	end
end

task.spawn(function()
	task.wait(8)
	local first = true
	while true do
		local clearTime = first and 15 or EVENT_MIN + math.random(0, EVENT_MAX - EVENT_MIN)
		first = false
		print("[LightingConfig] next fog event in " .. clearTime .. "s")
		task.wait(clearTime)

		-- 1) the lights stutter: the ninth second does not come
		print("[LightingConfig] lights flickering")
		for _ = 1, 3 do
			pcall(function()
				Lighting.Brightness = 0.45
			end)
			task.wait(0.12)
			pcall(function()
				Lighting.Brightness = 1.1
			end)
			task.wait(0.28)
		end
		broadcast("The lights flicker", "The ninth second never came. The fog is moving.")

		-- 2) fog sheets roll in from the edges
		print("[LightingConfig] fog rolling in")
		setFog(CLEAR_START, CLEAR_END)
		setAtmoDensity(0.18)
		tweenSheets(1, ROLL_IN)
		setFog(FOGGED_START, FOGGED_END)
		setAtmoDensity(0.55)

		-- 3) the fog squats over the map
		print("[LightingConfig] fog thick - holding")
		broadcast("Fog bank", "It rolled in from beyond the perimeter. Stay under the lights.")
		task.wait(HOLD_TIME)

		-- 4) the fog pulls back
		print("[LightingConfig] fog lifting")
		setFog(FOGGED_START, FOGGED_END)
		setAtmoDensity(0.55)
		tweenSheets(0, LIFT_TIME)
		setFog(CLEAR_START, CLEAR_END)
		setAtmoDensity(0.18)
		broadcast("The fog lifts", "Visibility is returning. The perimeter is clear.")
	end
end)
