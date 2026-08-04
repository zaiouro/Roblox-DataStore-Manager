--[[
	Hadasphere BubbleChat - client (LocalScript in StarterPlayerScripts).
	Replaces the default Roblox chat with restyled bubble chat:
	  - messages appear as speech bubbles above each player's head
	  - up to 4 bubbles stack per player, then fade out
	  - press / or T (or Enter) to open the input and speak
	  - Enter sends, ESC closes
	  - staff messages are tinted gold
	Disables the default Roblox chat UI (window + input bar).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- bubble visibility can be toggled from the settings menu (UIManager sets the
-- "ChatBubbles" attribute on the local player)
local bubblesEnabled = player:GetAttribute("ChatBubbles") ~= false

-- fully replace the default chat (classic + modern TextChatService).
-- ChatInputBarConfiguration / ChatWindowConfiguration are properties (not
-- children) in modern Roblox, so guard every access with pcall.
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
pcall(function()
	TextChatService:SetChatInputBarEnabled(false)
end)
pcall(function()
	TextChatService.ChatInputBarConfiguration.Enabled = false
end)
pcall(function()
	TextChatService.ChatWindowConfiguration.Enabled = false
end)

local remotes = ReplicatedStorage:WaitForChild("HadasphereRemotes")
local chatRemote = remotes:WaitForChild("Chat")
local typingRemote = remotes:WaitForChild("Typing")

print("[EmailChat] ready")

local gui = Instance.new("ScreenGui")
gui.Name = "HadasphereBubbleChat"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2 -- above the main HUD gui
gui.Parent = playerGui

local COLORS = {
	bg = Color3.fromRGB(4, 9, 18),
	panel = Color3.fromRGB(11, 20, 38),
	line = Color3.fromRGB(38, 62, 104),
	text = Color3.fromRGB(188, 214, 240),
	dim = Color3.fromRGB(108, 138, 174),
	accent = Color3.fromRGB(88, 152, 228),
	npc = Color3.fromRGB(150, 200, 255),
	staff = Color3.fromRGB(255, 205, 90),
}

local function mk(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent or gui
	return inst
end

local function escapeRichText(text)
	return (tostring(text):gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
end

-- bubble chat --------------------------------------------------------------
-- each message gets its own BillboardGui above the sender's head; newer
-- messages stack higher. AlwaysOnTop keeps them visible from any angle.

local _MAX_BUBBLES = 4
local BUBBLE_LIFE = 5
local activeBubbles = {} -- [userId] = count

local function headOf(sender)
	local ch = sender.Character
	return ch and ch:FindFirstChild("Head") or nil
end

-- resolve the NPC's head from the payload: the rig instance may not survive
-- the remote trip on every setup, so fall back to a workspace lookup by name
local function npcHeadOf(npcModel)
	if npcModel == nil then return nil end
	return npcModel:FindFirstChild("Head")
		or (npcModel.PrimaryPart and npcModel.PrimaryPart or npcModel:FindFirstChild("HumanoidRootPart"))
end

local function findNpcModel(data)
	local m = typeof(data.npc) == "Instance" and data.npc or nil
	if not m and typeof(data.npcName) == "string" then
		m = Workspace:FindFirstChild(data.npcName)
	end
	return m
end

local function pushBubble(uid, fromName, text, isStaff, npcModel)
	if not bubblesEnabled then return end
	local head
	if npcModel then
		head = npcHeadOf(npcModel)
	else
		local sender = Players:GetPlayerByUserId(uid)
		if not sender then return end
		head = headOf(sender)
	end
	if not head then
		print("[EmailChat] bubble skipped: no head (from=" .. fromName .. ", npc=" .. tostring(npcModel ~= nil) .. ")")
		return
	end
	print("[EmailChat] bubble shown: " .. fromName .. " -> " .. head:GetFullName())

	local count = activeBubbles[uid] or 0
	activeBubbles[uid] = count + 1

	local bill = Instance.new("BillboardGui")
	bill.Name = "ChatBubble"
	bill.Adornee = head
	bill.Size = UDim2.fromOffset(0, 0)
	bill.StudsOffset = Vector3.new(0, 3.2 + 0.55 * count, 0)
	bill.MaxDistance = 140
	bill.AlwaysOnTop = true
	bill.Parent = head

	local nameTag = isStaff and "[STAFF] " or (npcModel and "[" .. fromName .. "] " or "")
	local nameColor = isStaff and COLORS.staff or (npcModel and COLORS.npc or COLORS.accent)
	local bubble = Instance.new("TextLabel")
	bubble.BackgroundColor3 = isStaff and Color3.fromRGB(28, 24, 16) or COLORS.panel
	bubble.BorderSizePixel = 0
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.Size = UDim2.fromOffset(0, 0)
	bubble.Font = Enum.Font.Code
	bubble.TextSize = 14
	bubble.TextWrapped = true
	bubble.MaxVisibleLines = 4
	bubble.TextColor3 = COLORS.text
	bubble.RichText = true
	bubble.Text = "<font color='#" .. nameColor:ToHex() .. "'><b>" .. escapeRichText(nameTag .. fromName) .. ":</b></font> " .. escapeRichText(text)
	bubble.Parent = bill

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble

	local stroke = Instance.new("UIStroke")
	stroke.Color = isStaff and COLORS.staff or COLORS.line
	stroke.Thickness = 1
	stroke.Transparency = isStaff and 0.6 or 0.4
	stroke.Parent = bubble

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = bubble

	task.spawn(function()
		task.wait(BUBBLE_LIFE)
		activeBubbles[uid] = math.max(0, (activeBubbles[uid] or 1) - 1)
		if not bubble.Parent then return end
		local fade = TweenService:Create(bubble, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		fade:Play()
		fade.Completed:Wait()
		if bill.Parent then bill:Destroy() end
	end)
end

-- input (compose bar anchored bottom-center)
local bar = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0, 560, 0, 44),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Visible = false,
})
mk("UICorner", { CornerRadius = UDim.new(0, 12) }, bar)
mk("UIStroke", { Color = COLORS.accent, Thickness = 1, Transparency = 0.6 }, bar)
mk("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
}, bar)

local input = mk("TextBox", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	Text = "",
	TextSize = 15,
	TextColor3 = COLORS.text,
	PlaceholderText = "Type a message...",
	PlaceholderColor3 = COLORS.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
}, bar)

local composing = false

local function setComposing(on)
	composing = on
	bar.Visible = on
	if on then
		input:CaptureFocus()
	end
end

local function sendMessage()
	local text = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
	input.Text = ""
	setComposing(false)
	if #text == 0 then return end
	chatRemote:FireServer(text)
end

-- live typing indicator above a player's head (visible to everyone)
local typingGuis = {}

local function setTyping(uid, typing)
	if uid == player.UserId then return end
	local sender = uid and Players:GetPlayerByUserId(uid)
	if not sender then return end
	local head = headOf(sender)

	local existing = typingGuis[uid]
	if not typing or not head then
		if existing and existing.Parent then existing:Destroy() end
		typingGuis[uid] = nil
		return
	end
	if existing and existing.Parent then return end

	local bill = Instance.new("BillboardGui")
	bill.Name = "TypingIndicator"
	bill.Adornee = head
	bill.Size = UDim2.fromOffset(0, 0)
	bill.StudsOffset = Vector3.new(0, 3.5, 0)
	bill.MaxDistance = 140
	bill.Parent = head

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = COLORS.panel
	label.BorderSizePixel = 0
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.Font = Enum.Font.Code
	label.TextSize = 12
	label.TextColor3 = COLORS.npc
	label.Text = (sender.DisplayName or sender.Name) .. " is typing..."
	label.Parent = bill

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	typingGuis[uid] = bill
end

-- controls ---------------------------------------------------------------

input.Focused:Connect(function()
	typingRemote:FireServer(true)
end)

input.FocusLost:Connect(function(enterPressed)
	typingRemote:FireServer(false)
	if enterPressed then
		sendMessage()
	elseif composing then
		setComposing(false)
	end
end)

UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Slash or inp.KeyCode == Enum.KeyCode.T then
		setComposing(true)
	elseif (inp.KeyCode == Enum.KeyCode.Return or inp.KeyCode == Enum.KeyCode.KeypadEnter) and not composing then
		setComposing(true)
	elseif inp.KeyCode == Enum.KeyCode.Escape and composing then
		setComposing(false)
	end
end)

-- screen chat log (bottom-left, above the chat button) so you can always
-- see messages - including your own - regardless of camera angle
local logFrame = mk("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -64),
	Size = UDim2.new(0, 380, 0, 160),
	BackgroundTransparency = 1,
	ZIndex = 2,
})
local logLayout = mk("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 4),
}, logFrame)
logLayout:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() end)

local MAX_LOG = 6
local logLines = 0

local function pushLog(fromName, text, isStaff, isNpc)
	logLines = logLines + 1
	local line = mk("TextLabel", {
		Size = UDim2.new(0, 380, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 13,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Text = "<font color='#" .. (isStaff and COLORS.staff:ToHex() or (isNpc and COLORS.npc:ToHex() or COLORS.accent:ToHex())) .. "'><b>" .. escapeRichText(fromName) .. ":</b></font> " .. escapeRichText(text),
		TextColor3 = COLORS.text,
		LayoutOrder = logLines,
	}, logFrame)
	-- keep the newest messages; drop the oldest when over MAX_LOG
	local children = logFrame:GetChildren()
	for _, ch in ipairs(children) do
		if ch:IsA("TextLabel") and ch ~= line and ch.LayoutOrder < logLines - MAX_LOG then
			ch:Destroy()
		end
	end
end

chatRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local from = tostring(data.from or "?")
	local uid = type(data.uid) == "number" and data.uid or nil
	local text = tostring(data.text or "")
	local isStaff = data.staff == true
	local npcModel = findNpcModel(data)
	print("[EmailChat] rx from=" .. from .. " uid=" .. tostring(uid) .. " npc=" .. tostring(npcModel) .. " text=" .. text)
	if #text == 0 then return end
	setTyping(uid, false)
	pushBubble(uid, from, text, isStaff, npcModel)
	if text ~= "..." then
		pushLog(from, text, isStaff, npcModel ~= nil)
	end
end)

-- typing indicator relay
typingRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local uid = type(data.uid) == "number" and data.uid or nil
	if uid == nil then return end
	setTyping(uid, data.typing == true)
end)

-- clear bubble count when a player leaves
Players.PlayerRemoving:Connect(function(gone)
	activeBubbles[gone.UserId] = nil
end)

-- settings toggle (UIManager) can show/hide bubbles live
player:GetAttributeChangedSignal("ChatBubbles"):Connect(function()
	bubblesEnabled = player:GetAttribute("ChatBubbles") ~= false
end)
