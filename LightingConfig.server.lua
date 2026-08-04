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

	-- visible fog banks: Lighting fog can read as "nothing at all" on some
	-- setups, so we also scatter drifting smoke banks that literally roll
	-- in and out with the schedule. Anchored invisible part as the anchor
	-- so the emitters have a guaranteed parent.
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

	local BANK_OFFSETS = {
		Vector3.new(0, 14, 0),
		Vector3.new(70, 16, -45),
		Vector3.new(-80, 14, 30),
		Vector3.new(40, 10, -90),
		Vector3.new(-45, 18, 70),
		Vector3.new(0, 22, 120),
	}
	for _, off in ipairs(BANK_OFFSETS) do
		local e = Instance.new("ParticleEmitter")
		e.Name = "FogBank"
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.LightEmission = 0.12
		e.LightInfluence = 0
		e.Speed = NumberRange.new(0.4, 1.3)
		e.Lifetime = NumberRange.new(18, 26)
		e.Rate = 0.05
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 18),
			NumberSequenceKeypoint.new(1, 36),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 0.72),
		})
		e.Color = ColorSequence.new(FOG)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-3, 3)
		e.SpreadAngle = Vector2.new(45, 45)
		local attach = Instance.new("Attachment")
		attach.Position = off
		attach.Parent = fogAnchor
		e.Parent = attach
		fogBanks[#fogBanks + 1] = e
	end
end

apply()
print("[LightingConfig] dark atmosphere applied")

-- ============ fog schedule ============
-- The NPC lore says the fog "rolls in on a schedule, and lately it has been
-- coming in early". This makes it true: a repeating cycle where visibility
-- slowly collapses into heavy fog, holds, then lifts - and every cycle the
-- fog arrives a little early or a little late, so nobody can time it.
local FOG_CYCLE = 72        -- base seconds for one full clear->fog->clear cycle
local CLEAR_END = 550       -- best visibility (matches the apply() baseline)
local CLEAR_START = 90
local FOGGED_END = 60       -- thickest fog - walls of fog, but never blindness
local FOGGED_START = 8
local HOLD_TIME = 18        -- how long the fog squats on the map

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
	local rate = lerp(0.05, 14, t)
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

task.spawn(function()
	-- let the base atmosphere apply before the fog starts moving
	task.wait(6)
	while true do
		local cycle = FOG_CYCLE + math.random(-10, 10)
		print("[LightingConfig] fog cycle (" .. cycle .. "s) - rolling in")
		runPhase(16, CLEAR_START, CLEAR_END, FOGGED_START, FOGGED_END, 0.18, 0.55)
		print("[LightingConfig] fog thick - holding")
		runPhase(HOLD_TIME, FOGGED_START, FOGGED_END, FOGGED_START, FOGGED_END, 0.55, 0.55)
		print("[LightingConfig] fog lifting")
		runPhase(16, FOGGED_START, FOGGED_END, CLEAR_START, CLEAR_END, 0.55, 0.18)
		local clearHold = math.max(8, cycle - 16 - HOLD_TIME - 16)
		task.wait(clearHold)
	end
end)
