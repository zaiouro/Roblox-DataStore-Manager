--[[
	Hadasphere LightingConfig - server (Script).
	Applies a moody myth-RP atmosphere at runtime (evening light, soft haze)
	with horror as seasoning -- never so dark the world is hard to read.
	Everything is guarded; a missing Atmosphere or a locked property can
	never stop the game from loading.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- filled by apply() and driven by the fog schedule below
local fogBanks = {}

-- desaturated, cold, mythic green-grey evening palette
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

	-- visible fog banks: a wide ring of emitters around the play area, all
	-- drifting toward the centre. As the schedule ramps up, fog literally
	-- rolls in from every direction instead of popping up as a few balls.
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
	-- one wide ring far outside the play area: particles are born at the
	-- horizon and drift inward, so fog slowly approaches from beyond the
	-- world instead of popping up inside it
	local directions = 20
	local ringRadius = 320
	for d = 0, directions - 1 do
		local ang = (d / directions) * math.pi * 2
		local radius = ringRadius + math.random(-50, 50)
		local off = Vector3.new(
			math.cos(ang) * radius,
			10 + math.random() * 14,
			math.sin(ang) * radius
		)
		local e = Instance.new("ParticleEmitter")
		e.Name = "FogBank"
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.LightEmission = 0.12
		e.LightInfluence = 0
		-- slow drift inward; long lifetime so particles cross the whole ring
		e.Speed = NumberRange.new(2.5, 4.5)
		e.Lifetime = NumberRange.new(50, 70)
		e.Rate = 0.05
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 4),
			NumberSequenceKeypoint.new(1, 12),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 0.65),
			NumberSequenceKeypoint.new(1, 0.88),
		})
		e.Color = ColorSequence.new(FOG)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-3, 3)
		e.SpreadAngle = Vector2.new(50, 50)
		local attach = Instance.new("Attachment")
		attach.Position = off
		attach.Parent = fogAnchor
		-- face the centre so the fog travels inward (classic 2-arg CFrame)
		attach.CFrame = CFrame.new(center + off, center)
		e.Parent = attach
		fogBanks[#fogBanks + 1] = e
	end
end

apply()
print("[LightingConfig] dark atmosphere applied")

-- ============ fog event ============
-- The NPC lore: "the lights flicker on a nine-second cycle. When the ninth
-- second does not come, that is when the fog moves." So the fog is not a
-- background loop - it is an event: the lights stutter, then the fog rolls
-- in from beyond the world, squats over the map, and eventually pulls back.
local CLEAR_END = 550       -- best visibility (matches the apply() baseline)
local CLEAR_START = 90
local FOGGED_END = 55       -- thickest fog - dense, but never blindness
local FOGGED_START = 6
local EVENT_MIN = 80        -- seconds of clear between events
local EVENT_MAX = 150
local ROLL_IN = 25          -- fog takes its time arriving
local HOLD_TIME = 45        -- how long the fog squats on the map
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

-- drive the visible particle fog banks: 0 = clear, 1 = heavy fog
local function setFogIntensity(t)
	local rate = lerp(0.05, 3.5, t)
	for _, e in ipairs(fogBanks) do
		e.Rate = rate
	end
end

-- step a fog transition smoothly over `duration` seconds
local function runPhase(duration, fromStart, fromEnd, toStart, toEnd, fromDensity, toDensity)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local steps = math.max(1, math.floor(duration / 0.25))
	for i = 1, steps do
		local t = i / steps
		setFog(lerp(fromStart, toStart, t), lerp(fromEnd, toEnd, t))
		setFogIntensity(t)
		if atmo then
			pcall(function()
				atmo.Density = lerp(fromDensity, toDensity, t)
			end)
		end
		task.wait(0.25)
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
	-- let the base atmosphere apply before any event can start
	task.wait(8)
	while true do
		local clearTime = EVENT_MIN + math.random(0, EVENT_MAX - EVENT_MIN)
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

		-- 2) fog rolls in from beyond the world
		print("[LightingConfig] fog rolling in")
		runPhase(ROLL_IN, CLEAR_START, CLEAR_END, FOGGED_START, FOGGED_END, 0.18, 0.55)

		-- 3) the fog squats over the map
		print("[LightingConfig] fog thick - holding")
		runPhase(HOLD_TIME, FOGGED_START, FOGGED_END, FOGGED_START, FOGGED_END, 0.55, 0.55)

		-- 4) the fog pulls back
		print("[LightingConfig] fog lifting")
		runPhase(LIFT_TIME, FOGGED_START, FOGGED_END, CLEAR_START, CLEAR_END, 0.55, 0.18)
		broadcast("The fog lifts", "Visibility is returning. The perimeter is clear.")
	end
end)
