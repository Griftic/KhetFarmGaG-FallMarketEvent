-- Saad helper pack v2.6 — Sliders + Reset + Noclip + Gear Panel
-- (TP, Submit, Sell (TP+retour+caméra figée), Buy All Seeds/Gear + Auto 5m immediate, BUY EVENT (custom cmds)) + Position HUD
-- Ajout: Minimize/Restore animé (bouton — / ▣) + Alt+M

--// Services
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local StarterGui         = game:GetService("StarterGui")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")

local player             = Players.LocalPlayer
local playerGui          = player:WaitForChild("PlayerGui")

--// Consts
local DEFAULT_GRAVITY, DEFAULT_JUMPPOWER, DEFAULT_WALKSPEED = 196.2, 50, 16
local GEAR_SHOP_POS     = Vector3.new(-288, 2, -15)
local FALL_BLOOM_POS    = Vector3.new(-65,  4, -15)
local FALL_ACTIVITY_POS = Vector3.new(-124, 3, -15)
local SELL_NPC_POS      = Vector3.new(87,   3,   0)

-- Seeds/Gears definitions
local SEED_TIER = "Tier 1"
local SEEDS = {
	"Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon",
	"Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom",
	"Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone",
	"Elder Strawberry","Romanesco"
}
local GEARS = {
	"Watering Can","Trading Ticket","Trowel","Recall Wrench","Basic Sprinkler","Advanced Sprinkler",
	"Medium Toy","Medium Treat","Godly Sprinkler","Magnifying Glass","Master Sprinkler",
	"Cleaning Spray","Cleansing Pet Shard","Favorite Tool","Harvest Tool","Friendship Pot",
	"Grandmaster Sprinkler","Level Up Lollipop"
}
local MAX_TRIES_PER_SEED, MAX_TRIES_PER_GEAR = 20, 5
local AUTO_PERIOD = 300 -- 5 min

-- ✅ EVENT: commandes EXACTES (Nom, Code) dans cet ordre
local EVENT_CMDS = {
    {"Maple Sprinkler", 2},
    {"Maple Leaf Charm", 2},
    {"Acorn Lollipop",  2},
    {"Red Panda",       3},
    {"Space Squirrel",  3},
    {"Fall Egg",        3}, -- ajouté
    {"Fall Seed Pack",  1},
    {"Maple Resin",     1},
    {"Golden Peach",    1},
    {"Maple Crate",     4}, -- ajouté
    {"Fall Crate",      4}, -- ajouté
}

--// State
local currentSpeed, currentGravity, currentJump = 18, 147.1, 60
local isNoclipping, noclipConnection = false, nil
local autoBuySeeds, autoBuyGear = false, false
local seedsTimer, gearTimer = AUTO_PERIOD, AUTO_PERIOD
local seedsTimerLabel, gearTimerLabel
local screenGui, gearGui, posGui
local gearFrame

--// Utils
local function msg(text, color)
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color or Color3.fromRGB(200,200,255),
			Font = Enum.Font.Gotham,
			FontSize = Enum.FontSize.Size12,
		})
	end)
end
local function getHRP() local c=Players.LocalPlayer.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function applySpeed(v)   currentSpeed=v;  local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed=v end end
local function applyGravity(v) currentGravity=v; workspace.Gravity=v end
local function applyJump(v)    currentJump=v;   local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid"); if h then h.JumpPower=v end end
local function resetDefaults() applySpeed(DEFAULT_WALKSPEED); applyGravity(DEFAULT_GRAVITY); applyJump(DEFAULT_JUMPPOWER); msg("↩️ Reset (16 / 196.2 / 50).", Color3.fromRGB(180,220,255)) end
local function teleportTo(p) local hrp=getHRP(); if not hrp then msg("❌ HRP introuvable.", Color3.fromRGB(255,100,100)) return end; hrp.CFrame=CFrame.new(p) end
local function withFrozenCamera(fn)
	local cam=workspace.CurrentCamera; local t,s,cf=cam.CameraType,cam.CameraSubject,cam.CFrame
	cam.CameraType=Enum.CameraType.Scriptable; cam.CFrame=cf
	local ok,err=pcall(fn)
	cam.CameraType,cam.CameraSubject,cam.CFrame=t,s,cf
	if not ok then warn(err) end
end
local function fmtTime(sec) sec=math.max(0,math.floor(sec+0.5)) local m=math.floor(sec/60) local s=sec%60 return string.format("%d:%02d",m,s) end

-- Remotes
local function safeWait(path, timeout)
	local node=ReplicatedStorage
	for _,name in ipairs(path) do node=node:WaitForChild(name, timeout) if not node then return nil end end
	return node
end
local function getSubmitAllPlantsRemote() local r=safeWait({"GameEvents","FallMarketEvent","SubmitAllPlants"},2) return (r and r:IsA("RemoteEvent")) and r or nil end
local function getSellInventoryRemote()  local r=safeWait({"GameEvents","Sell_Inventory"},2)               return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuySeedRemote()        local r=safeWait({"GameEvents","BuySeedStock"},2)                 return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyGearRemote()        local r=safeWait({"GameEvents","BuyGearStock"},2)                 return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyEventRemote()
	local r=safeWait({"GameEvents","BuyEventShopStock"},2); if r and r:IsA("RemoteEvent") then return r end
	r=safeWait({"GameEvents","FallMarketEvent","BuyEventShopStock"},2); return (r and r:IsA("RemoteEvent")) and r or nil
end

-- Noclip
local function toggleNoclip(btn)
	isNoclipping = not isNoclipping
	if isNoclipping then
		if btn then btn.BackgroundColor3=Color3.fromRGB(60,220,60); btn.Text="✅ NO CLIP: ON" end
		if noclipConnection then noclipConnection:Disconnect() end
		noclipConnection = RunService.Stepped:Connect(function()
			local ch=player.Character; if not ch then return end
			for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
		end)
		msg("🚫 NO CLIP activé.")
	else
		if btn then btn.BackgroundColor3=Color3.fromRGB(220,60,60); btn.Text="🚫 NO CLIP: OFF" end
		if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end
		local ch=player.Character; if ch then for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
		msg("✅ NO CLIP désactivé.")
	end
end

-- Workers
local function buyAllSeedsWorker()
	local r = getBuySeedRemote(); if not r then msg("❌ BuySeedStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🌱 Achat: toutes les graines…")
	for _, seed in ipairs(SEEDS) do
		for i=1,MAX_TRIES_PER_SEED do pcall(function() r:FireServer(SEED_TIER, seed) end) task.wait(0.05) end
		msg("✅ "..seed.." ok.", Color3.fromRGB(160,230,180)); task.wait(0.03)
	end
	msg("🎉 Seeds terminé.")
end

local function buyAllGearWorker()
	local r = getBuyGearRemote(); if not r then msg("❌ BuyGearStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🧰 Achat: tous les gears…")
	for _, g in ipairs(GEARS) do
		for i=1,MAX_TRIES_PER_GEAR do pcall(function() r:FireServer(g) end) task.wait(0.06) end
		msg("✅ "..g.." ok.", Color3.fromRGB(180,220,200)); task.wait(0.03)
	end
	msg("🎉 Gears terminé.")
end

-- ✅ EVENT worker: envoie EXACTEMENT ("Nom", Code)
local function buyAllEventItemsWorker()
	local remote = getBuyEventRemote()
	if not remote then
		msg("❌ Remote BuyEventShopStock introuvable.", Color3.fromRGB(255,120,120))
		return
	end
	msg("🍁 Exécution des commandes EVENT (codes spécifiques)…", Color3.fromRGB(230,200,140))

	for _, pair in ipairs(EVENT_CMDS) do
		local name, code = pair[1], pair[2]
		local ok, err = pcall(function()
			remote:FireServer(name, code)
		end)
		if ok then
			msg(("✅ %s (code=%d) envoyé."):format(name, code), Color3.fromRGB(200,240,200))
		else
			msg(("⚠️ %s (code=%d) échec: %s"):format(name, code, tostring(err)), Color3.fromRGB(255,180,120))
		end
		task.wait(0.06)
	end

	msg("🎉 COMMANDES EVENT terminées.", Color3.fromRGB(180,220,255))
end

-- Timers (autos)
local function updateTimerLabels()
	if seedsTimerLabel then seedsTimerLabel.Text = "⏳ Next: "..fmtTime(seedsTimer) end
	if gearTimerLabel  then gearTimerLabel.Text  = "⏳ Next: "..fmtTime(gearTimer)  end
end
task.spawn(function()
	while true do
		task.wait(1)
		if autoBuySeeds then
			seedsTimer -= 1
			if seedsTimer <= 0 then buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD end
		else
			seedsTimer = AUTO_PERIOD
		end
		if autoBuyGear then
			gearTimer -= 1
			if gearTimer <= 0 then buyAllGearWorker(); gearTimer = AUTO_PERIOD end
		else
			gearTimer = AUTO_PERIOD
		end
		updateTimerLabels()
	end
end)

-- Draggable
local function makeDraggable(frame, handle)
	local dragging, dragStart, startPos, dragInput = false, nil, nil, nil
	local function update(input)
		local d = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true; dragStart = i.Position; startPos = frame.Position
			i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	handle.InputChanged:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseMovement then dragInput = i end end)
	UserInputService.InputChanged:Connect(function(i) if dragging and i == dragInput then update(i) end end)
end

-- ================= MAIN UI =================
screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerTuner"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 300, 0, 250)
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.BackgroundColor3 = Color3.fromRGB(36,36,36)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(28,28,28)
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -110, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255,255,255)
title.Text = "🎚️ PLAYER TUNER"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 26, 0, 26)
closeButton.Position = UDim2.new(1, -34, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(255,72,72)
closeButton.TextColor3 = Color3.fromRGB(255,255,255)
closeButton.Text = "✕"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 14
closeButton.Parent = titleBar
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(1, 0)

-- ===== Minimize (—/▣) + Animation + Alt+M =====
local isMinimized = false
local fullSize = UDim2.new(0, 300, 0, 250)
local collapsedSize = UDim2.new(0, 300, 0, 36)
local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 26, 0, 26)
minimizeButton.Position = UDim2.new(1, -66, 0, 5) -- à gauche de ✕
minimizeButton.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.Text = "—"
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.TextSize = 14
minimizeButton.Parent = titleBar
Instance.new("UICorner", minimizeButton).CornerRadius = UDim.new(1, 0)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -20, 1, -46)
content.Position = UDim2.new(0, 10, 0, 40)
content.BackgroundTransparency = 1
content.Parent = mainFrame

makeDraggable(mainFrame, titleBar)

-- Animation helpers
local function tween(obj, props, t, style, dir)
	local info = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	return TweenService:Create(obj, info, props)
end

local function setMinimized(v)
	if v == isMinimized then return end
	isMinimized = v
	minimizeButton.Text = v and "▣" or "—"

	-- Fade content (tous descendants avec BackgroundTransparency/TextTransparency/ImageTransparency)
	local descendants = content:GetDescendants()
	local targets = {}
	for _, d in ipairs(descendants) do
		if d:IsA("Frame") or d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("ImageLabel") or d:IsA("ImageButton") then
			table.insert(targets, d)
		end
	end

	if v then
		-- Minimize: fade out + shrink height
		for _, d in ipairs(targets) do
			pcall(function()
				if d:IsA("TextLabel") or d:IsA("TextButton") then tween(d, {TextTransparency = 1}, 0.12):Play() end
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then tween(d, {ImageTransparency = 1}, 0.12):Play() end
				if d:IsA("Frame") then tween(d, {BackgroundTransparency = 1}, 0.12):Play() end
			end)
		end
		tween(mainFrame, {Size = collapsedSize}, 0.2):Play()
		task.delay(0.2, function() content.Visible = false end)
	else
		-- Restore: expand + fade in
		content.Visible = true
		tween(mainFrame, {Size = fullSize}, 0.2):Play()
		task.delay(0.05, function()
			for _, d in ipairs(targets) do
				pcall(function()
					if d:IsA("TextLabel") or d:IsA("TextButton") then tween(d, {TextTransparency = 0}, 0.15):Play() end
					if d:IsA("ImageLabel") or d:IsA("ImageButton") then tween(d, {ImageTransparency = 0}, 0.15):Play() end
					if d:IsA("Frame") then tween(d, {BackgroundTransparency = 0}, 0.15):Play() end
				end)
			end
		end)
	end
end

minimizeButton.MouseButton1Click:Connect(function()
	setMinimized(not isMinimized)
end)

-- Raccourci Alt+M
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.M and (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
		setMinimized(not isMinimized)
	end
end)

-- Sliders
local function createSlider(parent, y, labelText, minValue, maxValue, step, initialValue, onChange, decimals)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 60)
	frame.Position = UDim2.new(0, 0, 0, y)
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255,255,255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = labelText
	label.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 90, 0, 18)
	valueLabel.Position = UDim2.new(1, -90, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextColor3 = Color3.fromRGB(200,220,255)
	valueLabel.Font = Enum.Font.Gotham
	valueLabel.TextSize = 12
	valueLabel.Parent = frame

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 10)
	track.Position = UDim2.new(0, 0, 0, 26)
	track.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	track.BorderSizePixel = 0
	track.Parent = frame
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 6)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(0,170,255)
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	knob.BorderSizePixel = 0
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
	local function snap(v) return math.floor((v - minValue)/step + 0.5)*step + minValue end
	local function fmt(val) if decimals and decimals > 0 then return string.format("%."..tostring(decimals).."f", val) else return tostring(math.floor(val + 0.5)) end end
	local function setVisual(pct, val) fill.Size = UDim2.new(pct, 0, 1, 0); knob.Position = UDim2.new(pct, 0, 0.5, 0); valueLabel.Text = fmt(val) end
	local function setValue(val, fire)
		val = clamp(snap(val), minValue, maxValue)
		local pct = (val - minValue) / (maxValue - minValue)
		setVisual(pct, val)
		if fire and onChange then onChange(val) end
	end

	local dragging = false
	local function updateFromX(x)
		local ap = track.AbsolutePosition.X
		local as = track.AbsoluteSize.X
		if as <= 0 then return end
		local pct = math.max(0, math.min(1, (x - ap)/as))
		local val = minValue + pct*(maxValue - minValue)
		setValue(val, true)
	end

	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true; updateFromX(i.Position.X)
			i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	knob.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true; updateFromX(i.Position.X)
			i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then updateFromX(i.Position.X) end
	end)

	setValue(initialValue, true)
	return { set = function(v) setValue(v, true) end }
end

local speedSlider   = createSlider(content, 0,   "Walk Speed (16–58)",   16, 58,   1,   currentSpeed,   applySpeed,   0)
local gravitySlider = createSlider(content, 70,  "Gravity (37.5–196.2)", 37.5,196.2, 0.1, currentGravity, applyGravity, 1)
local jumpSlider    = createSlider(content, 140, "Jump Power (45–82.5)", 45, 82.5, 0.5, currentJump,    applyJump,    1)

-- Buttons row
local buttonsRow = Instance.new("Frame"); buttonsRow.Size = UDim2.new(1, 0, 0, 36); buttonsRow.Position = UDim2.new(0, 0, 0, 200)
buttonsRow.BackgroundTransparency = 1; buttonsRow.Parent = content

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(0.33, -6, 1, 0)
resetBtn.Position = UDim2.new(0, 0, 0, 0)
resetBtn.BackgroundColor3 = Color3.fromRGB(70,100,180)
resetBtn.TextColor3 = Color3.fromRGB(255,255,255)
resetBtn.Text = "↩️ Reset Defaults"
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 13
resetBtn.Parent = buttonsRow
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 8)

local noclipBtn = Instance.new("TextButton")
noclipBtn.Size = UDim2.new(0.33, -6, 1, 0)
noclipBtn.Position = UDim2.new(0.335, 6, 0, 0)
noclipBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
noclipBtn.TextColor3 = Color3.fromRGB(255,255,255)
noclipBtn.Text = "🚫 NO CLIP: OFF"
noclipBtn.Font = Enum.Font.GothamBold
noclipBtn.TextSize = 13
noclipBtn.Parent = buttonsRow
Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 8)

local toggleGearBtn = Instance.new("TextButton")
toggleGearBtn.Size = UDim2.new(0.33, 0, 1, 0)
toggleGearBtn.Position = UDim2.new(0.67, 6, 0, 0)
toggleGearBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
toggleGearBtn.TextColor3 = Color3.fromRGB(255,255,255)
toggleGearBtn.Text = "🛒 Toggle Gear Panel"
toggleGearBtn.Font = Enum.Font.GothamBold
toggleGearBtn.TextSize = 13
toggleGearBtn.Parent = buttonsRow
Instance.new("UICorner", toggleGearBtn).CornerRadius = UDim.new(0, 8)

resetBtn.MouseButton1Click:Connect(function()
	resetDefaults()
	speedSlider.set(DEFAULT_WALKSPEED)
	gravitySlider.set(DEFAULT_GRAVITY)
	jumpSlider.set(DEFAULT_JUMPPOWER)
end)
noclipBtn.MouseButton1Click:Connect(function() toggleNoclip(noclipBtn) end)

closeButton.MouseButton1Click:Connect(function()
	if isMinimized then setMinimized(false) end
	if isNoclipping then toggleNoclip(nil) end
	if gearGui then gearGui:Destroy() end
	if posGui then posGui:Destroy() end
	if screenGui then screenGui:Destroy() end
end)

-- ================= GEAR UI =================
gearGui = Instance.new("ScreenGui")
gearGui.Name = "GearPanel"
gearGui.ResetOnSpawn = false
gearGui.IgnoreGuiInset = true
gearGui.Parent = playerGui

gearFrame = Instance.new("Frame")
gearFrame.Size = UDim2.new(0, 230, 0, 340)
gearFrame.Position = UDim2.new(0, 320, 0, 10)
gearFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
gearFrame.BorderSizePixel = 0
gearFrame.Parent = gearGui
Instance.new("UICorner", gearFrame).CornerRadius = UDim.new(0, 10)

local gearTitleBar = Instance.new("Frame")
gearTitleBar.Size = UDim2.new(1, 0, 0, 28)
gearTitleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 70)
gearTitleBar.Parent = gearFrame
Instance.new("UICorner", gearTitleBar).CornerRadius = UDim.new(0, 10)

local gearTitle = Instance.new("TextLabel")
gearTitle.Size = UDim2.new(1, -60, 1, 0)
gearTitle.Position = UDim2.new(0, 10, 0, 0)
gearTitle.BackgroundTransparency = 1
gearTitle.TextColor3 = Color3.fromRGB(255,255,255)
gearTitle.Text = "🛒 GEAR SHOP"
gearTitle.Font = Enum.Font.GothamBold
gearTitle.TextSize = 13
gearTitle.TextXAlignment = Enum.TextXAlignment.Left
gearTitle.Parent = gearTitleBar

local gearClose = Instance.new("TextButton")
gearClose.Size = UDim2.new(0, 20, 0, 20)
gearClose.Position = UDim2.new(1, -26, 0, 4)
gearClose.BackgroundColor3 = Color3.fromRGB(255, 72, 72)
gearClose.TextColor3 = Color3.fromRGB(255,255,255)
gearClose.Text = "✕"
gearClose.Font = Enum.Font.GothamBold
gearClose.TextSize = 12
gearClose.Parent = gearTitleBar
Instance.new("UICorner", gearClose).CornerRadius = UDim.new(1, 0)

local gearContent = Instance.new("Frame")
gearContent.Size = UDim2.new(1, -16, 1, -40)
gearContent.Position = UDim2.new(0, 8, 0, 36)
gearContent.BackgroundTransparency = 1
gearContent.Parent = gearFrame
makeDraggable(gearFrame, gearTitleBar)

-- Gear content
local tpGear = Instance.new("TextButton")
tpGear.Size = UDim2.new(1, 0, 0, 30)
tpGear.Position = UDim2.new(0, 0, 0, 0)
tpGear.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
tpGear.TextColor3 = Color3.fromRGB(255,255,255)
tpGear.Text = "📍 TP GEAR SHOP"
tpGear.Font = Enum.Font.GothamBold
tpGear.TextSize = 13
tpGear.Parent = gearContent
Instance.new("UICorner", tpGear).CornerRadius = UDim.new(0, 8)

local coordsLabel = Instance.new("TextLabel")
coordsLabel.Size = UDim2.new(1, 0, 0, 22)
coordsLabel.Position = UDim2.new(0, 0, 0, 36)
coordsLabel.BackgroundTransparency = 1
coordsLabel.TextColor3 = Color3.fromRGB(200,200,255)
coordsLabel.TextXAlignment = Enum.TextXAlignment.Left
coordsLabel.Font = Enum.Font.Gotham
coordsLabel.TextSize = 12
coordsLabel.Text = "Position: (…)"
coordsLabel.Parent = gearContent

local tpBloom = Instance.new("TextButton")
tpBloom.Size = UDim2.new(1, 0, 0, 26)
tpBloom.Position = UDim2.new(0, 0, 0, 62)
tpBloom.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
tpBloom.TextColor3 = Color3.fromRGB(255,255,255)
tpBloom.Text = "🌸 TP FALL BLOOM"
tpBloom.Font = Enum.Font.GothamBold
tpBloom.TextSize = 12
tpBloom.Parent = gearContent
Instance.new("UICorner", tpBloom).CornerRadius = UDim.new(0, 8)

local tpActivity = Instance.new("TextButton")
tpActivity.Size = UDim2.new(1, 0, 0, 26)
tpActivity.Position = UDim2.new(0, 0, 0, 92)
tpActivity.BackgroundColor3 = Color3.fromRGB(120, 90, 160)
tpActivity.TextColor3 = Color3.fromRGB(255,255,255)
tpActivity.Text = "🏕️ TP FALL ACTIVITY"
tpActivity.Font = Enum.Font.GothamBold
tpActivity.TextSize = 12
tpActivity.Parent = gearContent
Instance.new("UICorner", tpActivity).CornerRadius = UDim.new(0, 8)

local submitBtn = Instance.new("TextButton")
submitBtn.Size = UDim2.new(1, 0, 0, 26)
submitBtn.Position = UDim2.new(0, 0, 0, 124)
submitBtn.BackgroundColor3 = Color3.fromRGB(90, 170, 200)
submitBtn.TextColor3 = Color3.fromRGB(255,255,255)
submitBtn.Text = "🌾 SUBMIT PLANTS"
submitBtn.Font = Enum.Font.GothamBold
submitBtn.TextSize = 12
submitBtn.Parent = gearContent
Instance.new("UICorner", submitBtn).CornerRadius = UDim.new(0, 8)

local sellBtn = Instance.new("TextButton")
sellBtn.Size = UDim2.new(1, 0, 0, 26)
sellBtn.Position = UDim2.new(0, 0, 0, 156)
sellBtn.BackgroundColor3 = Color3.fromRGB(200, 130, 90)
sellBtn.TextColor3 = Color3.fromRGB(255,255,255)
sellBtn.Text = "🧺 SELL INVENTORY"
sellBtn.Font = Enum.Font.GothamBold
sellBtn.TextSize = 12
sellBtn.Parent = gearContent
Instance.new("UICorner", sellBtn).CornerRadius = UDim.new(0, 8)

-- Seeds row
local seedsRow = Instance.new("Frame")
seedsRow.Size = UDim2.new(1, 0, 0, 26)
seedsRow.Position = UDim2.new(0, 0, 0, 188)
seedsRow.BackgroundTransparency = 1
seedsRow.Parent = gearContent

local buyAllSeedsButton = Instance.new("TextButton")
buyAllSeedsButton.Size = UDim2.new(0.48, -4, 1, 0)
buyAllSeedsButton.Position = UDim2.new(0, 0, 0, 0)
buyAllSeedsButton.BackgroundColor3 = Color3.fromRGB(100, 170, 100)
buyAllSeedsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyAllSeedsButton.Text = "🌱 BUY ALL SEEDS"
buyAllSeedsButton.Font = Enum.Font.GothamBold
buyAllSeedsButton.TextSize = 12
buyAllSeedsButton.Parent = seedsRow
Instance.new("UICorner", buyAllSeedsButton).CornerRadius = UDim.new(0, 8)

local autoSeedsBtn = Instance.new("TextButton")
autoSeedsBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoSeedsBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoSeedsBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoSeedsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoSeedsBtn.Text = "Auto: OFF"
autoSeedsBtn.Font = Enum.Font.GothamBold
autoSeedsBtn.TextSize = 12
autoSeedsBtn.Parent = seedsRow
Instance.new("UICorner", autoSeedsBtn).CornerRadius = UDim.new(0, 8)

seedsTimerLabel = Instance.new("TextLabel")
seedsTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
seedsTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
seedsTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
seedsTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
seedsTimerLabel.Text = "⏳ Next: 5:00"
seedsTimerLabel.Font = Enum.Font.Gotham
seedsTimerLabel.TextSize = 12
seedsTimerLabel.Parent = seedsRow
Instance.new("UICorner", seedsTimerLabel).CornerRadius = UDim.new(0, 8)

-- Gear row
local gearRow = Instance.new("Frame")
gearRow.Size = UDim2.new(1, 0, 0, 26)
gearRow.Position = UDim2.new(0, 0, 0, 220)
gearRow.BackgroundTransparency = 1
gearRow.Parent = gearContent

local buyAllGearButton = Instance.new("TextButton")
buyAllGearButton.Size = UDim2.new(0.48, -4, 1, 0)
buyAllGearButton.Position = UDim2.new(0, 0, 0, 0)
buyAllGearButton.BackgroundColor3 = Color3.fromRGB(120, 140, 200)
buyAllGearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyAllGearButton.Text = "🧰 BUY ALL GEAR"
buyAllGearButton.Font = Enum.Font.GothamBold
buyAllGearButton.TextSize = 12
buyAllGearButton.Parent = gearRow
Instance.new("UICorner", buyAllGearButton).CornerRadius = UDim.new(0, 8)

local autoGearBtn = Instance.new("TextButton")
autoGearBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoGearBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoGearBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoGearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoGearBtn.Text = "Auto: OFF"
autoGearBtn.Font = Enum.Font.GothamBold
autoGearBtn.TextSize = 12
autoGearBtn.Parent = gearRow
Instance.new("UICorner", autoGearBtn).CornerRadius = UDim.new(0, 8)

gearTimerLabel = Instance.new("TextLabel")
gearTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
gearTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
gearTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
gearTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
gearTimerLabel.Text = "⏳ Next: 5:00"
gearTimerLabel.Font = Enum.Font.Gotham
gearTimerLabel.TextSize = 12
gearTimerLabel.Parent = gearRow
Instance.new("UICorner", gearTimerLabel).CornerRadius = UDim.new(0, 8)

-- Event row (custom cmds)
local eventRow = Instance.new("Frame")
eventRow.Size = UDim2.new(1, 0, 0, 26)
eventRow.Position = UDim2.new(0, 0, 0, 252)
eventRow.BackgroundTransparency = 1
eventRow.Parent = gearContent

local buyAllEventButton = Instance.new("TextButton")
buyAllEventButton.Size = UDim2.new(1, 0, 1, 0)
buyAllEventButton.Position = UDim2.new(0, 0, 0, 0)
buyAllEventButton.BackgroundColor3 = Color3.fromRGB(200, 140, 90)
buyAllEventButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyAllEventButton.Text = "🍁 BUY EVENT (custom cmds)"
buyAllEventButton.Font = Enum.Font.GothamBold
buyAllEventButton.TextSize = 12
buyAllEventButton.Parent = eventRow
Instance.new("UICorner", buyAllEventButton).CornerRadius = UDim.new(0, 8)

-- gear actions
tpGear.MouseButton1Click:Connect(function() teleportTo(GEAR_SHOP_POS) end)
tpBloom.MouseButton1Click:Connect(function() teleportTo(FALL_BLOOM_POS) end)
tpActivity.MouseButton1Click:Connect(function() teleportTo(FALL_ACTIVITY_POS) end)

submitBtn.MouseButton1Click:Connect(function()
	local r = getSubmitAllPlantsRemote()
	if r then r:FireServer(); msg("✅ SubmitAllPlants envoyé.", Color3.fromRGB(120,220,255))
	else msg("❌ Remote SubmitAllPlants introuvable.", Color3.fromRGB(255,120,120)) end
end)

sellBtn.MouseButton1Click:Connect(function()
	local r = getSellInventoryRemote()
	if not r then msg("❌ Remote Sell_Inventory introuvable.", Color3.fromRGB(255,120,120)); return end
	local hrp = getHRP(); if not hrp then msg("❌ HRP introuvable.", Color3.fromRGB(255,120,120)); return end
	local back = hrp.CFrame
	withFrozenCamera(function()
		teleportTo(SELL_NPC_POS)
		task.wait(0.20)
		r:FireServer()
		task.wait(0.05)
		hrp.CFrame = back
	end)
	msg("🧺 Inventaire vendu (TP/retour).", Color3.fromRGB(220,200,140))
end)

-- manual buys
buyAllSeedsButton.MouseButton1Click:Connect(function()
	buyAllSeedsWorker()
	seedsTimer = AUTO_PERIOD
	updateTimerLabels()
end)
buyAllGearButton.MouseButton1Click:Connect(function()
	buyAllGearWorker()
	gearTimer = AUTO_PERIOD
	updateTimerLabels()
end)
buyAllEventButton.MouseButton1Click:Connect(function()
	buyAllEventItemsWorker()
end)

-- AUTOS (immediate execute on ON)
autoSeedsBtn.MouseButton1Click:Connect(function()
	autoBuySeeds = not autoBuySeeds
	if autoBuySeeds then
		autoSeedsBtn.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
		autoSeedsBtn.Text = "Auto: ON"
		seedsTimer = AUTO_PERIOD
		msg("⏱️ Auto-buy SEEDS activé (5 min). Exécution maintenant…")
		task.spawn(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD; updateTimerLabels() end)
	else
		autoSeedsBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
		autoSeedsBtn.Text = "Auto: OFF"
		msg("⏹️ Auto-buy SEEDS désactivé.")
	end
	updateTimerLabels()
end)

autoGearBtn.MouseButton1Click:Connect(function()
	autoBuyGear = not autoBuyGear
	if autoBuyGear then
		autoGearBtn.BackgroundColor3 = Color3.fromRGB(70, 140, 180)
		autoGearBtn.Text = "Auto: ON"
		gearTimer = AUTO_PERIOD
		msg("⏱️ Auto-buy GEAR activé (5 min). Exécution maintenant…")
		task.spawn(function() buyAllGearWorker(); gearTimer = AUTO_PERIOD; updateTimerLabels() end)
	else
		autoGearBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
		autoGearBtn.Text = "Auto: OFF"
		msg("⏹️ Auto-buy GEAR désactivé.")
	end
	updateTimerLabels()
end)

gearClose.MouseButton1Click:Connect(function() gearFrame.Visible = false end)
toggleGearBtn.MouseButton1Click:Connect(function() gearFrame.Visible = not gearFrame.Visible end)

-- ================= POSITION HUD =================
posGui = Instance.new("ScreenGui")
posGui.Name = "PositionHUD"
posGui.ResetOnSpawn = false
posGui.IgnoreGuiInset = true
posGui.Parent = playerGui

local posFrame = Instance.new("Frame")
posFrame.Size = UDim2.new(0, 230, 0, 26)
posFrame.Position = UDim2.new(0, 10, 1, -36)
posFrame.BackgroundColor3 = Color3.fromRGB(25,25,35)
posFrame.BackgroundTransparency = 0.2
posFrame.BorderSizePixel = 0
posFrame.Parent = posGui
Instance.new("UICorner", posFrame).CornerRadius = UDim.new(0, 8)

local posLabel = Instance.new("TextLabel")
posLabel.Size = UDim2.new(1, -10, 1, 0)
posLabel.Position = UDim2.new(0, 8, 0, 0)
posLabel.BackgroundTransparency = 1
posLabel.TextColor3 = Color3.fromRGB(210,225,255)
posLabel.Font = Enum.Font.Gotham
posLabel.TextSize = 12
posLabel.TextXAlignment = Enum.TextXAlignment.Left
posLabel.Text = "XYZ: (…)"
posLabel.Parent = posFrame

makeDraggable(posFrame, posFrame)

-- live coords + mirror
do
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt; if acc < 0.2 then return end; acc = 0
		local hrp = getHRP()
		if hrp then
			local p = hrp.Position
			local xyz = string.format("%d, %d, %d", math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
			posLabel.Text = "XYZ: "..xyz
			if coordsLabel then coordsLabel.Text = "Position: ("..xyz..")" end
		else
			posLabel.Text = "XYZ: N/A"
			if coordsLabel then coordsLabel.Text = "Position: (N/A)" end
		end
	end)
end

-- apply initial values
applySpeed(currentSpeed); applyGravity(currentGravity); applyJump(currentJump); updateTimerLabels()

-- re-apply on respawn
player.CharacterAdded:Connect(function(char)
	char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = currentSpeed; hum.JumpPower = currentJump end
	workspace.Gravity = currentGravity
	if isNoclipping then task.wait(0.2); toggleNoclip(nil); toggleNoclip(nil) end
end)

msg("✅ Saad helper pack chargé. Minimize animé (—/▣, Alt+M). Event: commandes custom. Seeds/Gear: autos en 5 min si activés.", Color3.fromRGB(170,230,255))
