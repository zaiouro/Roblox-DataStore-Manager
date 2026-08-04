--[[
	Hadasphere LightingConfig - server (Script).
	Applies a moody myth-RP atmosphere at runtime (evening light, soft haze)
	with horror as seasoning -- never so dark the world is hard to read.
	Everything is guarded; a missing Atmosphere or a locked property can
	never stop the game from loading.
]]

local Lighting = game:GetService("Lighting")

-- desaturated, cold, mythic green-grey evening palette
local AMBIENT = Color3.fromRGB(88, 96, 90)
local SHIFT_TOP = Color3.fromRGB(150, 150, 138)
local SHIFT_BOTTOM = Color3.fromRGB(40, 44, 42)
local FOG = Color3.fromRGB(58, 66, 62)

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
		emitter.MaxDistance = 60
		emitter.Parent = spawn
	end
end

apply()
print("[LightingConfig] dark atmosphere applied")
