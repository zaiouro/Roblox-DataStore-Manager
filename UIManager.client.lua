--[[
	Hadasphere UIManager - client (LocalScript in StarterPlayerScripts).
	Core-essential UI: loading screen, HUD (health / sanity / stamina),
	toast notifications, and the staff panel. Plain Roblox instances
	(no UI library). Builds everything under a single ScreenGui.
	Reads character attributes (Sanity, MaxSanity, MagAmmo, Reserve)
	and listens to ReplicatedStorage.HadasphereRemotes.Notify toasts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PlayerConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerConfig"))

local remotes = ReplicatedStorage:WaitForChild("HadasphereRemotes")
local notifyEvent = remotes:WaitForChild("Notify")
local staffActionEvent = remotes:WaitForChild("StaffAction")
local sprintEvent = remotes:WaitForChild("Sprint")
local chatRemote = remotes:WaitForChild("Chat")

-- ============ palette (BXBC-style dark terminal, blue scale from light to
-- dark: ice-white-blue text, deep navy panels, electric accent) ============
local COLORS = {
	bg = Color3.fromRGB(4, 9, 18),
	panel = Color3.fromRGB(10, 18, 34),
	line = Color3.fromRGB(36, 58, 96),
	text = Color3.fromRGB(188, 214, 240),
	dim = Color3.fromRGB(108, 138, 174),
	accent = Color3.fromRGB(88, 152, 228),
	green = Color3.fromRGB(88, 150, 130),
	red = Color3.fromRGB(190, 70, 70),
	blue = Color3.fromRGB(120, 170, 220),
	energy = Color3.fromRGB(170, 190, 235),
}

-- one typeface for the whole game: a clean monospace that reads like the
-- facility's own terminal logs. No mixing fonts anywhere.
local FONT = Enum.Font.Code

local gui = Instance.new("ScreenGui")
gui.Name = "HadasphereUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- hide the default Roblox HUD; everything comes from UIManager.
-- Chat is handled by EmailChat (its own UI) and stays hidden here.
local StarterGui = game:GetService("StarterGui")
local coreGuiNames = {
	"Health",
	"Backpack",
	"PlayerList",
	"EmotesMenu",
	"SelfView",
}
local function setCoreGui(enabled, names)
	for _, name in ipairs(names or coreGuiNames) do
		local ok, en = pcall(function()
			return Enum.CoreGuiType[name]
		end)
		if ok and en then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(en, enabled)
			end)
		end
	end
end
setCoreGui(false)

-- ============ third-person camera limits ============
-- Players can only zoom in/out so far, so third person stays tight and
-- atmospheric instead of letting people view the whole map from orbit.
local CAMERA = {
	MinZoomDistance = 5,
	MaxZoomDistance = 24,
}
local function applyCameraLimits()
	player.CameraMinZoomDistance = CAMERA.MinZoomDistance
	player.CameraMaxZoomDistance = CAMERA.MaxZoomDistance
end
applyCameraLimits()
player.CharacterAdded:Connect(applyCameraLimits)

local function mk(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent or gui
	return inst
end

-- ============ loading screen ============
local loading = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.bg,
	BorderSizePixel = 0,
	ZIndex = 10,
})

mk("TextLabel", {
	Text = "H A D A S P H E R E",
	Font = FONT,
	TextSize = 44,
	TextColor3 = COLORS.text,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	ZIndex = 11,
}, loading)

mk("TextLabel", {
	Text = "SIGNAL LOCKED - STANDBY",
	Font = FONT,
	TextSize = 12,
	TextColor3 = COLORS.dim,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	ZIndex = 11,
}, loading)

local loadBarBg = mk("Frame", {
	Size = UDim2.fromOffset(260, 4),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	ZIndex = 11,
}, loading)

mk("UICorner", { CornerRadius = UDim.new(0, 2) }, loadBarBg)

local loadBar = mk("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = COLORS.accent,
	BorderSizePixel = 0,
	ZIndex = 12,
}, loadBarBg)

mk("UICorner", { CornerRadius = UDim.new(0, 2) }, loadBar)

-- ============ HUD ============
local hud = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
})

-- CRT analog overlay (scanlines + vignette), rendered at ZIndex 0 behind all
-- HUD controls so it never intercepts clicks. Gives the world that
-- filmed-on-tape look without touching the menus.
local crt = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 0,
}, hud)

-- scanlines: thin dark bands every 1/38th of the screen
for i = 0, 37 do
	local line = mk("Frame", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0, i / 38),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, crt)
	line.ZIndex = 0
end

-- vignette: soften the four edges with gradients (subtle, never heavy)
local vignettes = {}
local function vignetteEdge(rotation, size, pos, darkAtStart)
	local f = mk("Frame", {
		Size = size,
		Position = pos,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 0,
	}, crt)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
	if darkAtStart then
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	else
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.45) })
	end
	g.Parent = f
	vignettes[#vignettes + 1] = f
	return f
end

vignetteEdge(90, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 0, 0), true) -- top
vignetteEdge(90, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 1, -28), false) -- bottom
vignetteEdge(0, UDim2.new(0, 28, 1, 0), UDim2.new(0, 0, 0, 0), true) -- left
vignetteEdge(180, UDim2.new(0, 28, 1, 0), UDim2.new(1, -28, 0, 0), true) -- right

-- watchdog: never let the loading screen trap the player, even if an
-- unexpected error halts this script before the boot sequence runs
task.delay(3.5, function()
	if loading.Parent then loading:Destroy() end
	hud.Visible = true
end)

-- top-center toasts container
local toastBox = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.new(0, 360, 0, 0),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, hud)

local function makeStatBar(parent, accentColor, layout)
	layout = layout or {}
	local bg = mk("Frame", {
		AnchorPoint = layout.anchor or Vector2.new(0, 1),
		Position = layout.pos or UDim2.new(0, 0, 1, -14),
		Size = layout.size or UDim2.fromOffset(230, 12),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
	}, parent)

	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, bg)
	mk("UIStroke", { Color = COLORS.line, Thickness = 1, Transparency = 0.4 }, bg)

	local fill = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
	}, bg)

	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, fill)

	local label = mk("TextLabel", {
		Text = "",
		Font = FONT,
		TextSize = layout.textSize or 13,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, bg)

	return { bg = bg, fill = fill, label = label }
end

-- health + sanity grouped together bottom-left, slim like the stamina bar
local healthBar = makeStatBar(hud, COLORS.red, {
	pos = UDim2.new(0, 14, 1, -30),
	size = UDim2.fromOffset(230, 10),
	textSize = 10,
})
local sanityBar = makeStatBar(hud, COLORS.blue, {
	pos = UDim2.new(0, 252, 1, -30),
	size = UDim2.fromOffset(230, 10),
	textSize = 10,
})

-- stamina bar fills the bottom of the screen
local energyBar = makeStatBar(hud, COLORS.energy, {
	anchor = Vector2.new(0.5, 1),
	pos = UDim2.new(0.5, 0, 1, -12),
	size = UDim2.new(1, -24, 0, 10),
	textSize = 10,
})

-- exhaustion indicator (above the stamina bar)
local exhaustedLabel = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -30),
	Text = "EXHAUSTED",
	Font = FONT,
	TextSize = 13,
	TextColor3 = COLORS.red,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 3,
}, hud)

-- frozen indicator (upper-center)
local frozenBanner = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Text = "FROZEN",
	Font = FONT,
	TextSize = 34,
	TextColor3 = COLORS.blue,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 6,
}, hud)

-- death overlay (full screen, above everything except boot screens)
local deathOverlay = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(10, 2, 2),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 9,
})

mk("TextLabel", {
	Text = "Y O U  D I E D",
	Font = FONT,
	TextSize = 46,
	TextColor3 = COLORS.red,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	ZIndex = 10,
}, deathOverlay)

mk("TextLabel", {
	Text = ">> signal lost <<",
	Font = FONT,
	TextSize = 14,
	TextColor3 = COLORS.dim,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.51),
	ZIndex = 10,
}, deathOverlay)

mk("TextLabel", {
	Text = "Respawning...",
	Font = FONT,
	TextSize = 14,
	TextColor3 = COLORS.dim,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.56),
	ZIndex = 10,
}, deathOverlay)

-- ============ HUD state ============
local humanoid

local function setHealthBar(pct, text)
	healthBar.label.Text = text
	healthBar.fill.Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1)
	healthBar.fill.BackgroundColor3 = pct > 0.4 and COLORS.red or COLORS.green
end

local function setSanityBar(pct, text)
	sanityBar.label.Text = text
	sanityBar.fill.Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1)
end

local function energyColor(pct)
	if pct >= 0.5 then
		local t = (pct - 0.5) / 0.5
		local r = math.floor(220 + (255 - 220) * t)
		local g = math.floor(60 + (255 - 60) * t)
		local b = math.floor(60 + (255 - 60) * t)
		return Color3.fromRGB(r, g, b)
	else
		local t = pct / 0.5
		local r = math.floor(10 + (220 - 10) * t)
		local g = math.floor(10 + (60 - 10) * t)
		local b = math.floor(10 + (60 - 10) * t)
		return Color3.fromRGB(r, g, b)
	end
end

local function setEnergyBar(pct, text)
	pct = math.clamp(pct, 0, 1)
	energyBar.label.Text = text
	energyBar.fill.Size = UDim2.fromScale(pct, 1)
	energyBar.fill.BackgroundColor3 = energyColor(pct)
end

local function bindCharacter(ch)
	humanoid = ch:WaitForChild("Humanoid")

	-- keep the jump realistic on every spawn (respawn resets it to default 50)
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = PlayerConfig.Movement.JumpHeight

	humanoid.HealthChanged:Connect(function(health)
		setHealthBar(health / humanoid.MaxHealth, string.format("%d / %d", math.ceil(health), humanoid.MaxHealth))
		deathOverlay.Visible = health <= 0
	end)
	setHealthBar(humanoid.Health / humanoid.MaxHealth, string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth))
	deathOverlay.Visible = humanoid.Health <= 0

	local function refreshAttrs()
		local sanity = ch:GetAttribute("Sanity") or 100
		local maxSanity = ch:GetAttribute("MaxSanity") or 100
		setSanityBar(sanity / maxSanity, string.format("%d / %d", math.floor(sanity), maxSanity))
		local energy = ch:GetAttribute("Energy") or 100
		local maxEnergy = ch:GetAttribute("MaxEnergy") or 100
		setEnergyBar(energy / maxEnergy, string.format("%d / %d", math.floor(energy), maxEnergy))
		exhaustedLabel.Visible = (ch:GetAttribute("Exhausted") or false) == true
		frozenBanner.Visible = (ch:GetAttribute("Frozen") or false) == true
	end

	ch:GetAttributeChangedSignal("Sanity"):Connect(refreshAttrs)
	ch:GetAttributeChangedSignal("MaxSanity"):Connect(refreshAttrs)
	ch:GetAttributeChangedSignal("Energy"):Connect(refreshAttrs)
	ch:GetAttributeChangedSignal("MaxEnergy"):Connect(refreshAttrs)
	ch:GetAttributeChangedSignal("Exhausted"):Connect(refreshAttrs)
	ch:GetAttributeChangedSignal("Frozen"):Connect(refreshAttrs)
	refreshAttrs()
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- ============ toasts ============
-- Toasts are stacked manually (no UIListLayout): automatic-size siblings
-- don't always report their height in time, which let toasts overlap.
local toasts = {} -- active toasts, oldest first

local function reflowToasts()
	local y = 0
	for _, t in ipairs(toasts) do
		t.canvas.Position = UDim2.fromOffset(0, y)
		y = y + (t.height or 0) + 8
	end
end

-- Toast heights are computed up front with TextService:GetTextSize instead of
-- measured after auto-size settles; auto-size labels report their height a
-- frame late, which let stacked toasts overlap.
local TOAST_W = 360
local TOAST_PADX, TOAST_PADY = 12, 10
local TOAST_GAP = 4 -- vertical gap between the title and body lines

local function toast(title, text, accent)
	local contentW = TOAST_W - TOAST_PADX * 2

	local titleH = TextService:GetTextSize(title, 14, FONT, Vector2.new(contentW, math.huge)).Y
	local bodyH = 0
	if text and text ~= "" then
		bodyH = TextService:GetTextSize(text, 13, FONT, Vector2.new(contentW, math.huge)).Y
	end
	local cardH = math.ceil(titleH + bodyH + (bodyH > 0 and TOAST_GAP or 0) + TOAST_PADY * 2 + 2)

	-- the toast is itself a CanvasGroup so we can fade + slide it
	local canvas = mk("CanvasGroup", {
		Size = UDim2.fromOffset(TOAST_W, cardH),
		Position = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
	}, toastBox)

	local card = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
	}, canvas)

	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
	mk("UIStroke", { Color = accent or COLORS.line, Thickness = 1, Transparency = 0.3 }, card)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, TOAST_PADY)
	pad.PaddingBottom = UDim.new(0, TOAST_PADY)
	pad.PaddingLeft = UDim.new(0, TOAST_PADX)
	pad.PaddingRight = UDim.new(0, TOAST_PADX)
	pad.Parent = card

	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, TOAST_GAP),
	}, card)

	mk("TextLabel", {
		Text = title,
		Font = FONT,
		TextSize = 14,
		TextColor3 = accent or COLORS.text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(contentW, titleH),
		LayoutOrder = 1,
	}, card)

	if bodyH > 0 then
		mk("TextLabel", {
			Text = text,
			Font = FONT,
			TextSize = 13,
			TextColor3 = COLORS.dim,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.fromOffset(contentW, bodyH),
			LayoutOrder = 2,
		}, card)
	end

	local entry = { canvas = canvas, height = cardH }
	toasts[#toasts + 1] = entry
	reflowToasts()

	local t1 = TweenService:Create(canvas, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	})
	t1:Play()

	task.delay(3.5, function()
		local t2 = TweenService:Create(canvas, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})
		t2:Play()
		t2.Completed:Wait()
		canvas:Destroy()
		for i, e in ipairs(toasts) do
			if e == entry then
				table.remove(toasts, i)
				break
			end
		end
		reflowToasts()
	end)
end

notifyEvent.OnClientEvent:Connect(function(title, text)
	toast(title, text, COLORS.accent)
end)

-- ============ staff panel ============
local function playerStaffLevel()
	return player:GetAttribute("StaffLevel") or 0
end

local staffPanel = mk("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 14),
	Size = UDim2.fromOffset(320, 0),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 11,
	AutomaticSize = Enum.AutomaticSize.Y,
})
mk("UICorner", { CornerRadius = UDim.new(0, 12) }, staffPanel)
mk("UIStroke", { Color = COLORS.line, Thickness = 1, Transparency = 0.3 }, staffPanel)
mk("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, staffPanel)
mk("UIListLayout", { Padding = UDim.new(0, 6) }, staffPanel)

local staffHeader = mk("TextLabel", {
	Text = "S T A F F   P A N E L",
	Font = FONT,
	TextSize = 14,
	TextColor3 = COLORS.text,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 30),
	LayoutOrder = 1,
}, staffPanel)

-- quick-fill command chips
local cmdBar
local cmdChips = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1,
	LayoutOrder = 2,
}, staffPanel)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
}, cmdChips)

-- role-aware gating: a staff member only sees what their role can do
local function can(action)
	local lvl = playerStaffLevel()
	local ok, res = pcall(function()
		return PlayerConfig.Can(lvl, action)
	end)
	return ok and res or false
end

local chips = {} -- { btn = TextButton, action = string }

local function chip(text, fill, action)
	local b = mk("TextButton", {
		Text = text,
		Font = FONT,
		TextSize = 10,
		TextColor3 = COLORS.text,
		BackgroundColor3 = COLORS.bg,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
	}, cmdChips)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
	if fill == nil then
		-- executes immediately
		b.Activated:Connect(function()
			chatRemote:FireServer("!heal all")
		end)
	else
		b.Activated:Connect(function()
			cmdBar.Text = fill
			cmdBar:CaptureFocus()
		end)
	end
	chips[#chips + 1] = { btn = b, action = action }
	return b
end

chip("ANNOUNCE", "announce ", "Announce")
chip("GIVE", "give <name> <item>", "GiveItem")
chip("SETTEAM", "setteam <name> <team>", "SetTeam")
chip("SETSTAFF", "setstaff <name> <lvl 0-3>", "SetStaff")
chip("HEAL ALL", nil, "Heal")

-- command bar (type a command without the ! and press Enter)
local cmdRow = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = COLORS.bg,
	BorderSizePixel = 0,
	LayoutOrder = 3,
}, staffPanel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, cmdRow)

cmdBar = mk("TextBox", {
	Size = UDim2.new(1, -66, 1, 0),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 12,
	TextColor3 = COLORS.text,
	PlaceholderText = "kick <name> | tp <name> | announce <msg>",
	PlaceholderColor3 = COLORS.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
}, cmdRow)
mk("UIPadding", { PaddingLeft = UDim.new(0, 10) }, cmdBar)

local cmdExec = mk("TextButton", {
	Text = "RUN",
	Font = FONT,
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = COLORS.accent,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -4, 0.5, 0),
	Size = UDim2.fromOffset(56, 24),
}, cmdRow)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, cmdExec)

local function runCommand()
	local text = cmdBar.Text:gsub("^%s+", ""):gsub("%s+$", "")
	cmdBar.Text = ""
	if #text == 0 then return end
	chatRemote:FireServer("!" .. text)
end
cmdExec.Activated:Connect(runCommand)
cmdBar.FocusLost:Connect(function(enter)
	if enter then runCommand() end
end)

local staffList = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 4,
}, staffPanel)

local staffListLayout = Instance.new("UIListLayout")
staffListLayout.Padding = UDim.new(0, 4)
staffListLayout.SortOrder = Enum.SortOrder.LayoutOrder
staffListLayout.Parent = staffList

local function staffButton(text, onActivated, row, width, order)
	local b = mk("TextButton", {
		Text = text,
		Font = FONT,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = COLORS.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, 24),
		LayoutOrder = order,
	}, row)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	b.Activated:Connect(onActivated)
	return b
end

local function refreshStaffList()
	for _, row in ipairs(staffList:GetChildren()) do
		if row:IsA("Frame") then
			row:Destroy()
		end
	end
	local order = 0
	for _, other in ipairs(Players:GetPlayers()) do
		order = order + 1
		local row = mk("Frame", {
			Size = UDim2.new(1, -16, 0, 34),
			BackgroundColor3 = COLORS.bg,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, staffList)
		mk("UICorner", { CornerRadius = UDim.new(0, 8) }, row)

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.Parent = row

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingRight = UDim.new(0, 8)
		rowPad.Parent = row

		mk("TextLabel", {
			Text = other.Name,
			Font = FONT,
			TextSize = 13,
			TextColor3 = COLORS.text,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
		}, row)

		-- only show actions this player's role is allowed to use
		if can("Teleport") then
			staffButton("TP", function()
				staffActionEvent:FireServer("Teleport", { target = other.Name })
			end, row, 36, 1)
		end
		if can("Freeze") then
			staffButton("Freeze", function()
				staffActionEvent:FireServer("Freeze", { target = other.Name })
			end, row, 52, 2)
		end
		if can("Heal") then
			staffButton("Heal", function()
				staffActionEvent:FireServer("Heal", { target = other.Name })
			end, row, 46, 3)
		end
		if can("Kick") then
			staffButton("Kick", function()
				staffActionEvent:FireServer("Kick", { target = other.Name })
			end, row, 44, 4)
		end
	end
end

local staffBtn = mk("TextButton", {
	Text = "STAFF",
	Font = FONT,
	TextSize = 12,
	TextColor3 = COLORS.text,
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(86, 28),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 14),
	ZIndex = 3,
}, hud)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, staffBtn)

staffBtn.Activated:Connect(function()
	if staffPanel.Visible then
		staffPanel.Visible = false
	else
		refreshStaffList()
		staffPanel.Visible = true
	end
end)

-- hide staff controls the player's role can't use
local function refreshStaffAccess()
	local lvl = playerStaffLevel()
	staffBtn.Visible = lvl >= 1
	if lvl < 1 then
		staffPanel.Visible = false
	end
	local role = PlayerConfig.StaffLevelInfo(lvl)
	staffHeader.Text = "S T A F F   P A N E L   [" .. (role and role.Name:upper() or "?") .. "]"
	staffHeader.TextColor3 = role and role.Color or COLORS.text
	for _, c in ipairs(chips) do
		c.btn.Visible = c.action and can(c.action) or true
	end
end
player:GetAttributeChangedSignal("StaffLevel"):Connect(refreshStaffAccess)
refreshStaffAccess()

-- keep the staff list in sync with joins/leaves while the panel is open
task.spawn(function()
	while true do
		task.wait(2)
		if staffPanel.Visible then
			refreshStaffList()
		end
	end
end)

-- ============ settings menu (no on-screen button; opens with M) ============
-- State + key handling live OUTSIDE the builder's pcall, so the M key always
-- responds even if the UI construction below fails and is swallowed. The
-- builder (further down) fills in settingsPanel and selectTab.
local settingsOpen = false
local settingsPanel
local selectTab

local function toggleSettings()
	settingsOpen = not settingsOpen
	if settingsPanel then settingsPanel.Visible = settingsOpen end
	if settingsOpen and selectTab then
		selectTab("general")
	end
end

-- M toggles the menu from anywhere; ESC closes it
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		toggleSettings()
	elseif input.KeyCode == Enum.KeyCode.Escape and settingsOpen then
		settingsOpen = false
		if settingsPanel then settingsPanel.Visible = false end
	end
end)

-- The whole settings UI build is wrapped in pcall so a settings error can
-- never trap the player on the loading screen; the error still shows in Output.
local _, settingsErr = pcall(function()
-- UserSettings can only be fetched through the global UserSettings() call;
-- GetService("UserSettings") may not exist on all Roblox versions.
local UserGameSettings
pcall(function()
	UserGameSettings = UserSettings():GetService("UserGameSettings")
end)
UserGameSettings = UserGameSettings or {} -- never let this nil out mid-build

local SCOLORS = {
	bg = Color3.fromRGB(5, 7, 6),
	panel = Color3.fromRGB(12, 16, 14),
	line = Color3.fromRGB(32, 42, 37),
	text = Color3.fromRGB(201, 211, 204),
	dim = Color3.fromRGB(104, 118, 109),
	accent = Color3.fromRGB(150, 44, 44),
}

-- settings overlay (fills in the top-level settingsPanel declared above)
settingsPanel = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(2, 2, 3),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 20,
})

local panel = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 520, 0, 400),
	BackgroundColor3 = SCOLORS.bg,
	BorderSizePixel = 0,
	ZIndex = 21,
}, settingsPanel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
mk("UIStroke", { Color = SCOLORS.line, Thickness = 1 }, panel)

-- header
local header = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = SCOLORS.panel,
	BorderSizePixel = 0,
}, panel)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, header)

mk("TextLabel", {
	Text = "S E T T I N G S",
	Font = FONT,
	TextSize = 15,
	TextColor3 = SCOLORS.text,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
}, header)

local closeBtn = mk("TextButton", {
	Text = "X",
	Font = FONT,
	TextSize = 14,
	TextColor3 = SCOLORS.dim,
	BackgroundColor3 = SCOLORS.panel,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(26, 26),
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)
closeBtn.Activated:Connect(function()
	settingsPanel.Visible = false
	settingsOpen = false
end)

-- tabs
local tabs = {
	{ name = "GENERAL", id = "general" },
	{ name = "DISPLAY", id = "display" },
	{ name = "AUDIO", id = "audio" },
	{ name = "CONTROLS", id = "controls" },
}

local tabBar = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0, 46),
	BackgroundTransparency = 1,
}, panel)

local tabButtons = {}
local tabUnderline = {}
local pages = {}

selectTab = function(id)
	for _, t in ipairs(tabs) do
		tabButtons[t.id].TextColor3 = t.id == id and SCOLORS.text or SCOLORS.dim
		tabUnderline[t.id].Visible = t.id == id
		pages[t.id].Visible = t.id == id
	end
end

for i, t in ipairs(tabs) do
	local btn = mk("TextButton", {
		Text = t.name,
		Font = FONT,
		TextSize = 12,
		TextColor3 = SCOLORS.dim,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, (i - 1) * 130, 0, 0),
		Size = UDim2.fromOffset(130, 40),
	}, tabBar)
	tabButtons[t.id] = btn

	mk("Frame", {
		Size = UDim2.new(0, 130, 0, 2),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = SCOLORS.accent,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
	}, btn)
	tabUnderline[t.id] = btn:FindFirstChildOfClass("Frame")

	local page = mk("Frame", {
		Size = UDim2.new(1, 0, 1, -100),
		Position = UDim2.new(0, 0, 0, 92),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	pages[t.id] = page

	-- stack page content vertically so rows never overlap
	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Padding = UDim.new(0, 6)
	pageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	pageLayout.Parent = page

	-- keep content off the panel edges so it reads as centered
	local pagePad = Instance.new("UIPadding")
	pagePad.PaddingTop = UDim.new(0, 10)
	pagePad.PaddingLeft = UDim.new(0, 18)
	pagePad.PaddingRight = UDim.new(0, 18)
	pagePad.Parent = page

	btn.Activated:Connect(function()
		selectTab(t.id)
	end)
end

-- toggle helper with a one-line description so players know what a setting
-- actually does before they flip it
local function makeToggle(parent, label, initial, onChange, desc)
	desc = desc or ""
	local hasDesc = #desc > 0
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, hasDesc and 40 or 34),
		BackgroundTransparency = 1,
	}, parent)

	mk("TextLabel", {
		Text = label,
		Font = FONT,
		TextSize = 13,
		TextColor3 = SCOLORS.text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 340, 0, 18),
		Position = UDim2.new(0, 0, 0, hasDesc and 2 or 7),
	}, row)

	if hasDesc then
		mk("TextLabel", {
			Text = desc,
			Font = FONT,
			TextSize = 10,
			TextColor3 = SCOLORS.dim,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.new(0, 340, 0, 16),
			Position = UDim2.new(0, 0, 0, 21),
		}, row)
	end

	local state = initial
	local onOff = mk("TextLabel", {
		Text = state and "ON" or "OFF",
		Font = FONT,
		TextSize = 13,
		TextColor3 = state and SCOLORS.accent or SCOLORS.dim,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, hasDesc and 2 or 7),
		Size = UDim2.fromOffset(40, 20),
	}, row)

	local tgl = mk("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
	}, row)
	tgl.Activated:Connect(function()
		state = not state
		onOff.Text = state and "ON" or "OFF"
		onOff.TextColor3 = state and SCOLORS.accent or SCOLORS.dim
		if onChange then onChange(state) end
	end)
	return row
end

-- vital stat bars are part of the game loop, so they are locked on and shown
-- as such rather than pretending a player can toggle them off
local function makeLocked(parent, label, desc)
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	}, parent)

	mk("TextLabel", {
		Text = label,
		Font = FONT,
		TextSize = 13,
		TextColor3 = SCOLORS.dim,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 340, 0, 18),
		Position = UDim2.new(0, 0, 0, 2),
	}, row)

	if desc and #desc > 0 then
		mk("TextLabel", {
			Text = desc,
			Font = FONT,
			TextSize = 10,
			TextColor3 = SCOLORS.dim,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.new(0, 340, 0, 16),
			Position = UDim2.new(0, 0, 0, 21),
		}, row)
	end

	mk("TextLabel", {
		Text = "ALWAYS ON",
		Font = FONT,
		TextSize = 11,
		TextColor3 = SCOLORS.accent,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, 11),
		Size = UDim2.fromOffset(80, 18),
	}, row)
	return row
end

-- FPS counter (top-right, toggled from DISPLAY)
local fpsLabel = mk("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 62),
	Text = "FPS --",
	Font = FONT,
	TextSize = 12,
	TextColor3 = SCOLORS.dim,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 3,
}, hud)
local fpsAccum, fpsFrames = 0, 0
RunService.RenderStepped:Connect(function(dt)
	if not fpsLabel.Visible then return end
	fpsAccum = fpsAccum + dt
	fpsFrames = fpsFrames + 1
	if fpsAccum >= 0.5 then
		fpsLabel.Text = "FPS " .. math.round(fpsFrames / fpsAccum)
		fpsAccum, fpsFrames = 0, 0
	end
end)

-- GENERAL page
local genPage = pages.general

-- chat bubbles are controlled by the EmailChat client via a player attribute
player:SetAttribute("ChatBubbles", true)
local function chatBubbleToggle(on)
	player:SetAttribute("ChatBubbles", on)
end

makeLocked(genPage, "Health & Sanity bars", "Core vitals. Always shown.")
makeLocked(genPage, "Stamina bar", "Core vitals. Always shown.")
makeToggle(genPage, "Chat bubbles", true, function(on)
	chatBubbleToggle(on)
end, "Speech bubbles above players.")

-- DISPLAY page
local dispPage = pages.display

makeToggle(dispPage, "Auto graphics quality", UserGameSettings.IsGraphicsQualitySliderEnabled or false, function(on)
	UserGameSettings.IsGraphicsQualitySliderEnabled = on
end, "Let Roblox pick quality for smooth play.")
makeToggle(dispPage, "HUD edge vignette", true, function(on)
	for _, v in ipairs(vignettes) do
		v.Visible = on
	end
end, "Darkens the screen edges.")
makeToggle(dispPage, "CRT scanlines", true, function(on)
	crt.Visible = on
end, "Filmed-on-tape overlay effect.")
makeToggle(dispPage, "FPS counter", false, function(on)
	fpsLabel.Visible = on
end, "Show frames per second, top-right.")

-- AUDIO page
local audPage = pages.audio

local volLabel = mk("TextLabel", {
	Text = "Master Volume: 100",
	Font = FONT,
	TextSize = 13,
	TextColor3 = SCOLORS.text,
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(0, 300, 0, 20),
	Position = UDim2.new(0, 0, 0, 7),
}, audPage)

local volSlider = mk("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0, 60),
	Size = UDim2.new(1, -40, 0, 6),
	BackgroundColor3 = SCOLORS.panel,
	BorderSizePixel = 0,
}, audPage)
mk("UICorner", { CornerRadius = UDim.new(0, 3) }, volSlider)

local volFill = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = SCOLORS.accent,
	BorderSizePixel = 0,
}, volSlider)
mk("UICorner", { CornerRadius = UDim.new(0, 3) }, volFill)

local function setVolume(v)
	UserGameSettings.MasterVolume = v
	volFill.Size = UDim2.fromScale(v, 1)
	volLabel.Text = "Master Volume: " .. math.round(v * 100)
end

local volKnob = mk("TextButton", {
	Text = "",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 2, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
}, volSlider)

local volDragging = false
volKnob.MouseButton1Down:Connect(function()
	volDragging = true
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if volDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local rel = math.clamp((input.Position.X - volSlider.AbsolutePosition.X) / volSlider.AbsoluteSize.X, 0, 1)
		setVolume(rel)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		volDragging = false
	end
end)
setVolume(UserGameSettings.MasterVolume or 1)

-- CONTROLS page
local ctlPage = pages.controls

local ctlRows = {
	{ "WASD", "Move" },
	{ "SHIFT", "Sprint" },
	{ "SPACE", "Jump" },
	{ "/ or T", "Chat" },
	{ "E", "Interact" },
	{ "M", "Open settings menu" },
	{ "ESC", "Close menus" },
}
for i, r in ipairs(ctlRows) do
	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, (i - 1) * 30),
	}, ctlPage)

	mk("TextLabel", {
		Text = r[2],
		Font = FONT,
		TextSize = 13,
		TextColor3 = SCOLORS.text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 200, 0, 20),
		Position = UDim2.new(0, 0, 0, 5),
	}, row)

	mk("TextLabel", {
		Text = r[1],
		Font = FONT,
		TextSize = 13,
		TextColor3 = SCOLORS.accent,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, 5),
		Size = UDim2.fromOffset(140, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
end

end)

if settingsErr then
	warn("[UIManager] Settings UI failed to init (non-fatal):", settingsErr)
else
	print("[UIManager] Settings UI ready")
end

-- ============ sprint (stamina drain) ============
local sprinting = false
local function setSprint(on)
	on = on == true
	if on == sprinting then return end
	sprinting = on
	sprintEvent:FireServer(on)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)

-- if the window loses focus while shift is held, stop sprinting
UserInputService.WindowFocusReleased:Connect(function()
	setSprint(false)
end)

-- mobile: RUN button (toggle)
if UserInputService.TouchEnabled then
	local sprintBtn = mk("TextButton", {
		Text = "RUN",
		Font = FONT,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = COLORS.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(90, 42),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -90),
		ZIndex = 4,
	}, hud)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, sprintBtn)
	local function refreshSprintBtn()
		sprintBtn.Text = sprinting and "STOP" or "RUN"
	end
	sprintBtn.Activated:Connect(function()
		setSprint(not sprinting)
		refreshSprintBtn()
	end)
	refreshSprintBtn()
end

-- ============ boot sequence ============
-- loading bar fill
local barTween = TweenService:Create(loadBar, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	Size = UDim2.fromScale(1, 1),
})
barTween:Play()

task.wait(1.6)

-- fade loading -> gameplay
local fade = TweenService:Create(loading, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
	BackgroundTransparency = 1,
})
fade:Play()
loading:SetAttribute("Fading", true)
task.wait(0.45)
loading:Destroy()

-- game starts immediately (no main menu)
hud.Visible = true

-- role reveal: show the player their assignment for a few seconds, fading the
-- text in and back out. Only runs once the place is fully loaded (game.Loaded),
-- the character exists with a root part, and the server has pushed StaffLevel,
-- so the reveal never appears before the player can see the world or guesses
-- the wrong role.
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local ch = player.Character
	local loadWait = 0
	while not ch and loadWait < 6 do
		task.wait(0.1)
		loadWait += 0.1
		ch = player.Character
	end
	if ch then
		ch:WaitForChild("HumanoidRootPart", 5)
	end

	local lvl = player:GetAttribute("StaffLevel")
	local attrWait = 0
	while lvl == nil and attrWait < 3 do
		task.wait(0.1)
		attrWait += 0.1
		lvl = player:GetAttribute("StaffLevel")
	end
	lvl = lvl or 0
	local roleInfo = PlayerConfig.StaffLevelInfo(lvl)

	local descText = (roleInfo.Description or "") .. "\n\nGood luck."
	local descH = TextService:GetTextSize(descText, 15, FONT, Vector2.new(408, math.huge)).Y
	local revealH = math.ceil(14 + 24 + 8 + 68 + 8 + 2 + 8 + descH + 14)

	local reveal = mk("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, revealH),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = 8,
	})

	-- translucent backing card so the world shows through while the text
	-- still reads clearly
	local card = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(9, 12, 11),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, reveal)

	mk("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	mk("UIStroke", { Color = COLORS.line, Thickness = 1, Transparency = 0.35 }, card)

	mk("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, card)

	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, card)

	mk("TextLabel", {
		Text = "YOU ARE",
		Font = FONT,
		TextSize = 15,
		TextColor3 = COLORS.text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 1,
	}, card)

	mk("TextLabel", {
		Text = (roleInfo.Name or "SUBJECT"):upper(),
		Font = FONT,
		TextSize = 56,
		TextColor3 = roleInfo.Color or COLORS.text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 68),
		LayoutOrder = 2,
	}, card)

	mk("Frame", {
		Size = UDim2.new(0.4, 0, 0, 2),
		BackgroundColor3 = COLORS.line,
		BorderSizePixel = 0,
		LayoutOrder = 3,
	}, card)

	mk("TextLabel", {
		Text = descText,
		Font = FONT,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(178, 190, 182),
		BackgroundTransparency = 1,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, descH),
		LayoutOrder = 4,
	}, card)

	local revealIn = TweenService:Create(reveal, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	})
	revealIn:Play()
	task.wait(2.4)
	local revealOut = TweenService:Create(reveal, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	})
	revealOut:Play()
	revealOut.Completed:Wait()
	reveal:Destroy()

	-- one-time hint: the settings menu lives on the M key, there is no on-screen
	-- button for it (shows right after the role reveal finishes)
	toast("PRESS M", "Opens the settings menu.", COLORS.dim)
end)

print("[UIManager] boot complete")
