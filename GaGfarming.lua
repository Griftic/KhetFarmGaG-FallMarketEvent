-- Saad helper pack v2.7 — Sliders + Reset + Noclip + Gear Panel
-- (TP, Sell (TP+retour+caméra figée), Buy All Seeds/Gear + Autos, BUY EVO (auto 1:50), BUY EGGS (auto 15:00))
-- +++++ EVO MANAGER +++++
-- Submit (Held) Evo I/II/III (match partiel, ignore "seed" & exclut "IV") + Plant EVO Seeds via Plant_RE (Vector3, "Evo X I/II/III") à ta position (raycast sol)
-- Minimize animé (—/▣) + Alt+M

--// Services
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local StarterGui         = game:GetService("StarterGui")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Workspace          = game:GetService("Workspace")

local player             = Players.LocalPlayer
local playerGui          = player:WaitForChild("PlayerGui")

--// Consts
local DEFAULT_GRAVITY, DEFAULT_JUMPPOWER, DEFAULT_WALKSPEED = 196.2, 50, 16
local GEAR_SHOP_POS     = Vector3.new(-288, 2, -15)
local SELL_NPC_POS      = Vector3.new(87,   3,   0)

-- Seeds/Gears definitions
local SEED_TIER = "Tier 1"
local SEEDS = {
	"Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon",
	"Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom",
	"Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone",
	"Elder Strawberry","Romanesco","Crimson Thron"
}
local GEARS = {
	"Watering Can","Trading Ticket","Trowel","Recall Wrench","Basic Sprinkler","Advanced Sprinkler",
	"Medium Toy","Medium Treat","Godly Sprinkler","Magnifying Glass","Master Sprinkler",
	"Cleaning Spray","Cleansing Pet Shard","Favorite Tool","Harvest Tool","Friendship Pot",
	"Grandmaster Sprinkler","Level Up Lollipop"
}

-- Eggs list (buy via BuyPetEgg)
local EGGS = {
	"Common Egg","Uncommon Egg","Rare Egg","Legendary Egg","Mythical Egg","Bug Egg","Jungle Egg"
}

local MAX_TRIES_PER_SEED, MAX_TRIES_PER_GEAR = 20, 5
local AUTO_PERIOD_SEEDS   = 300   -- 5 min
local AUTO_PERIOD_GEAR    = 300   -- 5 min
local AUTO_PERIOD_EVENT   = 110   -- 1m50
local AUTO_PERIOD_EGGS    = 900   -- 15m

--// State
local currentSpeed, currentGravity, currentJump = 18, 147.1, 60
local isNoclipping, noclipConnection = false, nil
local autoBuySeeds, autoBuyGear, autoBuyEvent, autoBuyEggs = false, false, false, false
local seedsTimer, gearTimer, eventTimer, eggsTimer =
	AUTO_PERIOD_SEEDS, AUTO_PERIOD_GEAR, AUTO_PERIOD_EVENT, AUTO_PERIOD_EGGS

local seedsTimerLabel, gearTimerLabel, eventTimerLabel, eggsTimerLabel
local screenGui, gearGui
local gearFrame
local coordsLabel

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
local function getHRP()
	local c=Players.LocalPlayer.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
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
local function getSellInventoryRemote()  local r=safeWait({"GameEvents","Sell_Inventory"},2)               return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuySeedRemote()        local r=safeWait({"GameEvents","BuySeedStock"},2)                 return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyGearRemote()        local r=safeWait({"GameEvents","BuyGearStock"},2)                 return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyEventRemote()
	local r=safeWait({"GameEvents","BuyEventShopStock"},2); if r and r:IsA("RemoteEvent") then return r end
	r=safeWait({"GameEvents","FallMarketEvent","BuyEventShopStock"},2); return (r and r:IsA("RemoteEvent")) and r or nil
end
local function getBuyPetEggRemote()
	local r=safeWait({"GameEvents","BuyPetEgg"},2)
	return (r and r:IsA("RemoteEvent")) and r or nil
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

-- Workers seeds/gears/events/eggs
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

-- BUY EVO (event shop with code=5)
local EVO_LIST = { "Evo Pumpkin I","Evo Blueberry I","Evo Beetroot I","Evo Mushroom I" }
local function buyEventEvosWorker()
	local remote = getBuyEventRemote()
	if not remote then msg("❌ Remote BuyEventShopStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🎃 Achat EVO (code=5) …", Color3.fromRGB(230,200,140))
	for _, name in ipairs(EVO_LIST) do
		local ok, err = pcall(function() remote:FireServer(name, 5) end)
		if ok then msg(("✅ %s (code=5) envoyé."):format(name), Color3.fromRGB(200,240,200))
		else msg(("⚠️ %s échec: %s"):format(name, tostring(err)), Color3.fromRGB(255,180,120)) end
		task.wait(0.06)
	end
	msg("🎉 EVO terminé.", Color3.fromRGB(180,220,255))
end

local function buyAllEggsWorker()
	local remote = getBuyPetEggRemote()
	if not remote then msg("❌ Remote BuyPetEgg introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🥚 Achat: eggs…", Color3.fromRGB(220,200,150))
	for _, egg in ipairs(EGGS) do
		local ok, err = pcall(function() remote:FireServer(egg) end)
		if ok then msg("✅ "..egg.." ok.", Color3.fromRGB(200,240,200))
		else msg(("⚠️ %s échec: %s"):format(egg, tostring(err)), Color3.fromRGB(255,180,120)) end
		task.wait(0.06)
	end
	msg("🎉 Eggs terminé.")
end

-- Timers autos
local function updateTimerLabels()
	if seedsTimerLabel then seedsTimerLabel.Text = "⏳ Next: "..fmtTime(seedsTimer) end
	if gearTimerLabel  then gearTimerLabel.Text  = "⏳ Next: "..fmtTime(gearTimer)  end
	if eventTimerLabel then eventTimerLabel.Text = "⏳ Next: "..fmtTime(eventTimer) end
	if eggsTimerLabel  then eggsTimerLabel.Text  = "⏳ Next: "..fmtTime(eggsTimer)  end
end
task.spawn(function()
	while true do
		task.wait(1)
		if autoBuySeeds then seedsTimer -= 1 else seedsTimer = AUTO_PERIOD_SEEDS end
		if autoBuyGear  then gearTimer  -= 1 else gearTimer  = AUTO_PERIOD_GEAR end
		if autoBuyEvent then eventTimer -= 1 else eventTimer = AUTO_PERIOD_EVENT end
		if autoBuyEggs  then eggsTimer  -= 1 else eggsTimer  = AUTO_PERIOD_EGGS end
		if autoBuySeeds and seedsTimer<=0 then buyAllSeedsWorker(); seedsTimer=AUTO_PERIOD_SEEDS end
		if autoBuyGear  and gearTimer<=0  then buyAllGearWorker();  gearTimer =AUTO_PERIOD_GEAR  end
		if autoBuyEvent and eventTimer<=0 then buyEventEvosWorker();eventTimer=AUTO_PERIOD_EVENT end
		if autoBuyEggs  and eggsTimer<=0  then buyAllEggsWorker();  eggsTimer =AUTO_PERIOD_EGGS  end
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
minimizeButton.Position = UDim2.new(1, -66, 0, 5)
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

local function tween(obj, props, t, style, dir)
	local info = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	return TweenService:Create(obj, info, props)
end
local function setMinimized(v)
	if v == isMinimized then return end
	isMinimized = v
	minimizeButton.Text = v and "▣" or "—"
	local descendants = content:GetDescendants()
	local targets = {}
	for _, d in ipairs(descendants) do
		if d:IsA("Frame") or d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("ImageLabel") or d:IsA("ImageButton") then
			table.insert(targets, d)
		end
	end
	if v then
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
minimizeButton.MouseButton1Click:Connect(function() setMinimized(not isMinimized) end)
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.M and (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
		setMinimized(not isMinimized)
	end
end)

-- Sliders
local function createSlider(parent, y, labelText, minValue, maxValue, step, initialValue, onChange, decimals)
	local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 60); frame.Position = UDim2.new(0, 0, 0, y); frame.BackgroundTransparency = 1; frame.Parent = parent
	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 0, 18); label.BackgroundTransparency = 1; label.TextXAlignment = Enum.TextXAlignment.Left; label.TextColor3 = Color3.fromRGB(255,255,255); label.Font = Enum.Font.GothamBold; label.TextSize = 14; label.Text = labelText; label.Parent = frame
	local valueLabel = Instance.new("TextLabel"); valueLabel.Size = UDim2.new(0, 90, 0, 18); valueLabel.Position = UDim2.new(1, -90, 0, 0); valueLabel.BackgroundTransparency = 1; valueLabel.TextXAlignment = Enum.TextXAlignment.Right; valueLabel.TextColor3 = Color3.fromRGB(200,220,255); valueLabel.Font = Enum.Font.Gotham; valueLabel.TextSize = 12; valueLabel.Parent = frame
	local track = Instance.new("Frame"); track.Size = UDim2.new(1, 0, 0, 10); track.Position = UDim2.new(0, 0, 0, 26); track.BackgroundColor3 = Color3.fromRGB(64,64,64); track.BorderSizePixel = 0; track.Parent = frame; Instance.new("UICorner", track).CornerRadius = UDim.new(0, 6)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(0,170,255); fill.BorderSizePixel = 0; fill.Parent = track; Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
	local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 16, 0, 16); knob.AnchorPoint = Vector2.new(0.5,0.5); knob.Position = UDim2.new(0, 0, 0.5, 0); knob.BackgroundColor3 = Color3.fromRGB(230,230,230); knob.BorderSizePixel = 0; knob.Parent = track; Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local function clamp(v,a,b) return math.max(a, math.min(b, v)) end
	local function snap(v) return math.floor((v - minValue)/step + 0.5)*step + minValue end
	local function fmt(val) if decimals and decimals > 0 then return string.format("%."..tostring(decimals).."f", val) else return tostring(math.floor(val + 0.5)) end end
	local function setVisual(pct, val) fill.Size = UDim2.new(pct, 0, 1, 0); knob.Position = UDim2.new(pct, 0, 0.5, 0); valueLabel.Text = fmt(val) end
	local function setValue(val, fire) val = clamp(snap(val), minValue, maxValue); local pct = (val - minValue) / (maxValue - minValue); setVisual(pct, val); if fire and onChange then onChange(val) end end
	local dragging = false
	local function updateFromX(x) local ap,as = track.AbsolutePosition.X, track.AbsoluteSize.X; if as<=0 then return end; local pct = math.max(0, math.min(1, (x-ap)/as)); local val = minValue + pct*(maxValue-minValue); setValue(val, true) end
	track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; updateFromX(i.Position.X); i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end) end end)
	knob.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; updateFromX(i.Position.X); i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end) end end)
	UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then updateFromX(i.Position.X) end end)
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
	if screenGui then screenGui:Destroy() end
end)

-- ================= GEAR UI =================
gearGui = Instance.new("ScreenGui")
gearGui.Name = "GearPanel"
gearGui.ResetOnSpawn = false
gearGui.IgnoreGuiInset = true
gearGui.Parent = playerGui

gearFrame = Instance.new("Frame")
gearFrame.Size = UDim2.new(0, 260, 0, 450)
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
gearTitle.Size = UDim2.new(1, -160, 1, 0)
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

local evoManagerBtn = Instance.new("TextButton")
evoManagerBtn.Size = UDim2.new(0, 130, 0, 20)
evoManagerBtn.Position = UDim2.new(1, -160, 0, 4)
evoManagerBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 150)
evoManagerBtn.TextColor3 = Color3.fromRGB(255,255,255)
evoManagerBtn.Text = "🔧 EVO MANAGER"
evoManagerBtn.Font = Enum.Font.GothamBold
evoManagerBtn.TextSize = 11
evoManagerBtn.Parent = gearTitleBar
Instance.new("UICorner", evoManagerBtn).CornerRadius = UDim.new(1, 0)

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

coordsLabel = Instance.new("TextLabel")
coordsLabel.Size = UDim2.new(1, 0, 0, 22)
coordsLabel.Position = UDim2.new(0, 0, 0, 36)
coordsLabel.BackgroundTransparency = 1
coordsLabel.TextColor3 = Color3.fromRGB(200,200,255)
coordsLabel.TextXAlignment = Enum.TextXAlignment.Left
coordsLabel.Font = Enum.Font.Gotham
coordsLabel.TextSize = 12
coordsLabel.Text = "Position: (…)"
coordsLabel.Parent = gearContent

local sellBtn = Instance.new("TextButton")
sellBtn.Size = UDim2.new(1, 0, 0, 26)
sellBtn.Position = UDim2.new(0, 0, 0, 62)
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
seedsRow.Position = UDim2.new(0, 0, 0, 94)
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
gearRow.Position = UDim2.new(0, 0, 0, 126)
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

-- EVO row (event)
local eventRow = Instance.new("Frame")
eventRow.Size = UDim2.new(1, 0, 0, 26)
eventRow.Position = UDim2.new(0, 0, 0, 158)
eventRow.BackgroundTransparency = 1
eventRow.Parent = gearContent

local buyEvoButton = Instance.new("TextButton")
buyEvoButton.Size = UDim2.new(0.48, -4, 1, 0)
buyEvoButton.Position = UDim2.new(0, 0, 0, 0)
buyEvoButton.BackgroundColor3 = Color3.fromRGB(200, 140, 90)
buyEvoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyEvoButton.Text = "🍁 BUY EVO (code=5)"
buyEvoButton.Font = Enum.Font.GothamBold
buyEvoButton.TextSize = 12
buyEvoButton.Parent = eventRow
Instance.new("UICorner", buyEvoButton).CornerRadius = UDim.new(0, 8)

local autoEventBtn = Instance.new("TextButton")
autoEventBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoEventBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoEventBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoEventBtn.TextColor3 = Color3.fromRGB(255,255,255)
autoEventBtn.Text = "Auto: OFF"
autoEventBtn.Font = Enum.Font.GothamBold
autoEventBtn.TextSize = 12
autoEventBtn.Parent = eventRow
Instance.new("UICorner", autoEventBtn).CornerRadius = UDim.new(0, 8)

eventTimerLabel = Instance.new("TextLabel")
eventTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
eventTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
eventTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
eventTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
eventTimerLabel.Text = "⏳ Next: 1:50"
eventTimerLabel.Font = Enum.Font.Gotham
eventTimerLabel.TextSize = 12
eventTimerLabel.Parent = eventRow
Instance.new("UICorner", eventTimerLabel).CornerRadius = UDim.new(0, 8)

-- EGGS row
local eggsRow = Instance.new("Frame")
eggsRow.Size = UDim2.new(1, 0, 0, 26)
eggsRow.Position = UDim2.new(0, 0, 0, 190)
eggsRow.BackgroundTransparency = 1
eggsRow.Parent = gearContent

local buyEggsButton = Instance.new("TextButton")
buyEggsButton.Size = UDim2.new(0.48, -4, 1, 0)
buyEggsButton.Position = UDim2.new(0, 0, 0, 0)
buyEggsButton.BackgroundColor3 = Color3.fromRGB(150, 120, 200)
buyEggsButton.TextColor3 = Color3.fromRGB(255,255,255)
buyEggsButton.Text = "🥚 BUY EGGS"
buyEggsButton.Font = Enum.Font.GothamBold
buyEggsButton.TextSize = 12
buyEggsButton.Parent = eggsRow
Instance.new("UICorner", buyEggsButton).CornerRadius = UDim.new(0, 8)

local autoEggsBtn = Instance.new("TextButton")
autoEggsBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoEggsBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoEggsBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoEggsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoEggsBtn.Text = "Auto: OFF"
autoEggsBtn.Font = Enum.Font.GothamBold
autoEggsBtn.TextSize = 12
autoEggsBtn.Parent = eggsRow
Instance.new("UICorner", autoEggsBtn).CornerRadius = UDim.new(0, 8)

eggsTimerLabel = Instance.new("TextLabel")
eggsTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
eggsTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
eggsTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
eggsTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
eggsTimerLabel.Text = "⏳ Next: 15:00"
eggsTimerLabel.Font = Enum.Font.Gotham
eggsTimerLabel.TextSize = 12
eggsTimerLabel.Parent = eggsRow
Instance.new("UICorner", eggsTimerLabel).CornerRadius = UDim.new(0, 8)

-- gear actions
tpGear.MouseButton1Click:Connect(function() teleportTo(GEAR_SHOP_POS) end)
sellBtn.MouseButton1Click:Connect(function()
	local r = getSellInventoryRemote()
	if not r then msg("❌ Remote Sell_Inventory introuvable.", Color3.fromRGB(255,120,120)); return end
	local hrp = getHRP(); if not hrp then msg("❌ HRP introuvable.", Color3.fromRGB(255,120,120)); return end
	local back = hrp.CFrame
	withFrozenCamera(function()
		teleportTo(SELL_NPC_POS); task.wait(0.20); r:FireServer(); task.wait(0.05); hrp.CFrame = back
	end)
	msg("🧺 Inventaire vendu (TP/retour).", Color3.fromRGB(220,200,140))
end)

buyAllSeedsButton.MouseButton1Click:Connect(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD_SEEDS; updateTimerLabels() end)
buyAllGearButton.MouseButton1Click:Connect(function() buyAllGearWorker();  gearTimer  = AUTO_PERIOD_GEAR;  updateTimerLabels() end)
buyEvoButton.MouseButton1Click:Connect(function() buyEventEvosWorker(); eventTimer = AUTO_PERIOD_EVENT; updateTimerLabels() end)
buyEggsButton.MouseButton1Click:Connect(function() buyAllEggsWorker();   eggsTimer = AUTO_PERIOD_EGGS;  updateTimerLabels() end)

autoSeedsBtn.MouseButton1Click:Connect(function()
	autoBuySeeds = not autoBuySeeds
	autoSeedsBtn.BackgroundColor3 = autoBuySeeds and Color3.fromRGB(70,160,90) or Color3.fromRGB(80,90,120)
	autoSeedsBtn.Text = autoBuySeeds and "Auto: ON" or "Auto: OFF"
	if autoBuySeeds then msg("⏱️ Auto-buy SEEDS activé (5 min). Exécution maintenant…"); task.spawn(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD_SEEDS; updateTimerLabels() end)
	else msg("⏹️ Auto-buy SEEDS désactivé.") end
	updateTimerLabels()
end)
autoGearBtn.MouseButton1Click:Connect(function()
	autoBuyGear = not autoBuyGear
	autoGearBtn.BackgroundColor3 = autoBuyGear and Color3.fromRGB(70,140,180) or Color3.fromRGB(80,90,120)
	autoGearBtn.Text = autoBuyGear and "Auto: ON" or "Auto: OFF"
	if autoBuyGear then msg("⏱️ Auto-buy GEAR activé (5 min). Exécution maintenant…"); task.spawn(function() buyAllGearWorker(); gearTimer = AUTO_PERIOD_GEAR; updateTimerLabels() end)
	else msg("⏹️ Auto-buy GEAR désactivé.") end
	updateTimerLabels()
end)
autoEventBtn.MouseButton1Click:Connect(function()
	autoBuyEvent = not autoBuyEvent
	autoEventBtn.BackgroundColor3 = autoBuyEvent and Color3.fromRGB(180,120,80) or Color3.fromRGB(80,90,120)
	autoEventBtn.Text = autoBuyEvent and "Auto: ON" or "Auto: OFF"
	if autoBuyEvent then msg("⏱️ Auto-buy EVO activé (1:50). Exécution maintenant…"); task.spawn(function() buyEventEvosWorker(); eventTimer = AUTO_PERIOD_EVENT; updateTimerLabels() end)
	else msg("⏹️ Auto-buy EVO désactivé.") end
	updateTimerLabels()
end)
autoEggsBtn.MouseButton1Click:Connect(function()
	autoBuyEggs = not autoBuyEggs
	autoEggsBtn.BackgroundColor3 = autoBuyEggs and Color3.fromRGB(120,100,160) or Color3.fromRGB(80,90,120)
	autoEggsBtn.Text = autoBuyEggs and "Auto: ON" or "Auto: OFF"
	if autoBuyEggs then msg("⏱️ Auto-buy EGGS activé (15:00). Exécution maintenant…"); task.spawn(function() buyAllEggsWorker(); eggsTimer = AUTO_PERIOD_EGGS; updateTimerLabels() end)
	else msg("⏹️ Auto-buy EGGS désactivé.") end
	updateTimerLabels()
end)

gearClose.MouseButton1Click:Connect(function() gearFrame.Visible = false end)
local function toggleGear() gearFrame.Visible = not gearFrame.Visible end
toggleGearBtn.MouseButton1Click:Connect(toggleGear)

-- live coords
do
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt; if acc < 0.2 then return end; acc = 0
		local hrp = getHRP()
		coordsLabel.Text = hrp and ("Position: (%d, %d, %d)"):format(hrp.Position.X//1, hrp.Position.Y//1, hrp.Position.Z//1) or "Position: (N/A)"
	end)
end

-- ======== EVO MANAGER (Submit Held + Plant EVO Seeds à ta position) ========
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
player.CharacterAdded:Connect(function(char) character = char; humanoid = char:WaitForChild("Humanoid") end)
local backpack = player:WaitForChild("Backpack")

-- Remotes (Submit & Plant)
local Tiered  = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("TieredPlants")
local Submit  = Tiered:WaitForChild("Submit")

local function findPlantRemote()
	local GE = ReplicatedStorage:FindFirstChild("GameEvents"); if not GE then return nil end
	local r = GE:FindFirstChild("Plant_RE")
	return (r and r:IsA("RemoteEvent")) and r or nil
end

-- Cibles Submit
local TARGET_FAMILIES = {
    "Evo Beetroot I","Evo Beetroot II","Evo Beetroot III",
    "Evo Blueberry I","Evo Blueberry II","Evo Blueberry III",
    "Evo Pumpkin I","Evo Pumpkin II","Evo Pumpkin III",
    "Evo Mushroom I","Evo Mushroom II","Evo Mushroom III",
}
local selected = {}; for _,s in ipairs(TARGET_FAMILIES) do selected[string.lower(s)]=true end

-- EVO MANAGER UI
local evoGui = Instance.new("ScreenGui"); evoGui.Name="EvoManager"; evoGui.ResetOnSpawn=false; evoGui.IgnoreGuiInset=true; evoGui.Parent=playerGui
local evoFrame = Instance.new("Frame"); evoFrame.Size=UDim2.new(0, 440, 0, 360); evoFrame.Position=UDim2.new(0, 590, 0, 10)
evoFrame.BackgroundColor3=Color3.fromRGB(24,24,28); evoFrame.BorderSizePixel=0; evoFrame.Visible=false; evoFrame.Parent=evoGui
Instance.new("UICorner", evoFrame).CornerRadius=UDim.new(0,10)
local evoStroke=Instance.new("UIStroke"); evoStroke.Thickness=1; evoStroke.Color=Color3.fromRGB(70,70,80); evoStroke.Parent=evoFrame
makeDraggable(evoFrame, evoFrame)

local evoTitle = Instance.new("TextLabel"); evoTitle.Size=UDim2.new(1,-40,0,28); evoTitle.Position=UDim2.new(0,12,0,6)
evoTitle.BackgroundTransparency=1; evoTitle.Font=Enum.Font.GothamSemibold; evoTitle.TextSize=16; evoTitle.TextXAlignment=Enum.TextXAlignment.Left
evoTitle.Text="🔧 EVO MANAGER — Submit Held (I/II/III) + Plant EVO Seeds (à ta position)"; evoTitle.TextColor3=Color3.fromRGB(235,235,245); evoTitle.Parent=evoFrame

local evoClose = Instance.new("TextButton"); evoClose.Size=UDim2.new(0,26,0,26); evoClose.Position=UDim2.new(1,-34,0,6)
evoClose.BackgroundColor3=Color3.fromRGB(45,45,55); evoClose.Text="✕"; evoClose.Font=Enum.Font.GothamBold; evoClose.TextSize=14; evoClose.TextColor3=Color3.fromRGB(235,235,245); evoClose.Parent=evoFrame
Instance.new("UICorner", evoClose).CornerRadius = UDim.new(1,0)

-- Liste selectable (Submit Held)
local selectorHolder = Instance.new("Frame"); selectorHolder.Size=UDim2.new(1,-24,0,180); selectorHolder.Position=UDim2.new(0,12,0,40)
selectorHolder.BackgroundColor3=Color3.fromRGB(28,28,34); selectorHolder.Parent=evoFrame; Instance.new("UICorner", selectorHolder).CornerRadius=UDim.new(0,10)
local scroller = Instance.new("ScrollingFrame"); scroller.Size=UDim2.new(1,-8,1,-8); scroller.Position=UDim2.new(0,4,0,4); scroller.BackgroundTransparency=1; scroller.ScrollBarThickness=6; scroller.Parent=selectorHolder
local listLayout = Instance.new("UIListLayout"); listLayout.Parent=scroller; listLayout.Padding=UDim.new(0,6)
local function makeToggleRow(parent,labelText)
	local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,24); row.BackgroundTransparency=1; row.Parent=parent
	local chk=Instance.new("TextButton"); chk.Size=UDim2.new(0,24,1,0); chk.BackgroundColor3=Color3.fromRGB(50,120,80); chk.Text="✓"; chk.TextColor3=Color3.fromRGB(240,240,240); chk.Font=Enum.Font.GothamBold; chk.TextSize=14; chk.Parent=row; Instance.new("UICorner", chk).CornerRadius=UDim.new(0,6)
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-32,1,0); lbl.Position=UDim2.new(0,32,0,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.Gotham; lbl.TextSize=14; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.TextColor3=Color3.fromRGB(210,210,220); lbl.Text=labelText; lbl.Parent=row
	local key=string.lower(labelText)
	local function refresh() local on=selected[key]; chk.Text=on and "✓" or ""; chk.BackgroundColor3=on and Color3.fromRGB(50,120,80) or Color3.fromRGB(60,60,70) end
	local function toggle() selected[key]=not selected[key]; refresh() end
	refresh(); chk.MouseButton1Click:Connect(toggle); lbl.InputBegan:Connect(function(i) if i.UserInputType.Name=="MouseButton1" then toggle() end end)
end
for _, fam in ipairs(TARGET_FAMILIES) do makeToggleRow(scroller, fam) end

-- Boutons Submit
local rescanBtn = Instance.new("TextButton"); rescanBtn.Size=UDim2.new(0.48,-6,0,36); rescanBtn.Position=UDim2.new(0,12,0,230)
rescanBtn.BackgroundColor3=Color3.fromRGB(80,85,100); rescanBtn.Text="Rescan Backpack"; rescanBtn.Font=Enum.Font.GothamBold; rescanBtn.TextSize=14; rescanBtn.TextColor3=Color3.fromRGB(255,255,255); rescanBtn.Parent=evoFrame; Instance.new("UICorner",rescanBtn).CornerRadius=UDim.new(0,10)
local submitBtn = Instance.new("TextButton"); submitBtn.Size=UDim2.new(0.48,-6,0,36); submitBtn.Position=UDim2.new(0.52,0,0,230)
submitBtn.BackgroundColor3=Color3.fromRGB(60,120,255); submitBtn.Text="Submit sélection (Held)"; submitBtn.Font=Enum.Font.GothamBold; submitBtn.TextSize=14; submitBtn.TextColor3=Color3.fromRGB(255,255,255); submitBtn.Parent=evoFrame; Instance.new("UICorner",submitBtn).CornerRadius=UDim.new(0,10)

-- Section Plant EVO Seeds (à la position)
local plantBox = Instance.new("Frame"); plantBox.Size=UDim2.new(1,-24,0,100); plantBox.Position=UDim2.new(0,12,0,276); plantBox.BackgroundColor3=Color3.fromRGB(28,28,34); plantBox.Parent=evoFrame; Instance.new("UICorner", plantBox).CornerRadius=UDim.new(0,10)
local posLabel = Instance.new("TextLabel"); posLabel.Size=UDim2.new(1,-16,0,22); posLabel.Position=UDim2.new(0,8,0,8); posLabel.BackgroundTransparency=1
posLabel.Font=Enum.Font.Gotham; posLabel.TextSize=14; posLabel.TextXAlignment=Enum.TextXAlignment.Left; posLabel.TextColor3=Color3.fromRGB(220,220,230); posLabel.Text="Pos: (…)"
posLabel.Parent = plantBox

local plantEvoBtn = Instance.new("TextButton"); plantEvoBtn.Size=UDim2.new(1,-16,0,30); plantEvoBtn.Position=UDim2.new(0,8,0,36); plantEvoBtn.BackgroundColor3=Color3.fromRGB(50,160,90)
plantEvoBtn.Text="🌱 Planter les EVO Seeds à ma position"; plantEvoBtn.Font=Enum.Font.GothamBold; plantEvoBtn.TextSize=13; plantEvoBtn.TextColor3=Color3.fromRGB(255,255,255); plantEvoBtn.Parent=plantBox; Instance.new("UICorner",plantEvoBtn).CornerRadius=UDim.new(0,8)

local statusLbl = Instance.new("TextLabel"); statusLbl.Size=UDim2.new(1,-24,0,24); statusLbl.Position=UDim2.new(0,12,1,-30)
statusLbl.BackgroundTransparency=1; statusLbl.Font=Enum.Font.Gotham; statusLbl.TextSize=14; statusLbl.TextXAlignment=Enum.TextXAlignment.Left
statusLbl.TextColor3=Color3.fromRGB(200,200,210); statusLbl.Text="Prêt."; statusLbl.Parent=evoFrame

local function flash(frame, fromRGB, toRGB)
	frame.BackgroundColor3 = Color3.fromRGB(fromRGB[1],fromRGB[2],fromRGB[3])
	TweenService:Create(frame, TweenInfo.new(0.25), {BackgroundColor3=Color3.fromRGB(toRGB[1],toRGB[2],toRGB[3])}):Play()
end

-- ========= Submit (Held)
local function isSelectedMatch(toolName)
	local lname=string.lower(toolName)
	-- exclusions
	if string.find(lname,"seed",1,true) then return false end           -- jamais de "seed" pour Submit
	if string.find(lname," iv",1,true) or lname:match("iv$") then return false end  -- exclure toute version IV
	-- filtres sélectionnés
	for base,isOn in pairs(selected) do
		if isOn and string.find(lname, base, 1, true) then
			return true
		end
	end
	return false
end
local function getMatchingToolsForSubmit()
	local found={}
	for _,obj in ipairs(backpack:GetChildren()) do
		if obj:IsA("Tool") and isSelectedMatch(obj.Name) then table.insert(found,obj) end
	end
	return found
end
local function equipTool(tool, timeout)
	timeout=timeout or 5; local t0=os.clock()
	humanoid:EquipTool(tool)
	while os.clock()-t0<timeout do
		local held=character:FindFirstChildOfClass("Tool")
		if held==tool then return true end
		task.wait()
	end
	return false
end
local function submitHeld()
	local ok,err=pcall(function() Submit:FireServer("Held") end); return ok,err
end
local function processAllSubmit()
	local tools=getMatchingToolsForSubmit()
	if #tools==0 then statusLbl.Text="Aucune plante Evo I/II/III correspondante (IV exclues)."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local success,fail=0,0
	for i,tool in ipairs(tools) do
		statusLbl.Text=("Équipe %d/%d: %s"):format(i,#tools,tool.Name)
		if equipTool(tool,5) then
			task.wait(0.05)
			local ok,err=submitHeld()
			if ok then success+=1; statusLbl.Text=("Soumis: %s ✓"):format(tool.Name)
			else fail+=1; statusLbl.Text=("Échec submit %s: %s"):format(tool.Name,tostring(err)); flash(evoFrame,{80,30,30},{24,24,28}) end
			local t0=os.clock()
			repeat task.wait(0.1)
				local held=character:FindFirstChildOfClass("Tool")
				local still=backpack:FindFirstChild(tool.Name)~=nil
				if (not held or held~=tool) and not still then break end
			until os.clock()-t0>2
		else
			fail+=1; statusLbl.Text=("Impossible d'équiper: %s"):format(tool.Name); flash(evoFrame,{80,30,30},{24,24,28})
		end
		task.wait(0.12)
	end
	statusLbl.Text=("Submit terminé — %d succès, %d échecs."):format(success,fail)
	flash(evoFrame,{30,80,30},{24,24,28})
end

-- ========= Plant EVO Seeds (Plant_RE(Vector3, "Evo … I/II/III") à ta position)
local function canonicalEvoName(toolName)
	-- retire annotations [..], (..), mots "seed(s)", espaces inutiles
	local s = toolName:gsub("%b[]", ""):gsub("%b()", "")
	s = s:gsub("[Ss][Ee][Ee][Dd][Ss]?", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	-- essaie d'extraire "Evo <mot> <romain>"
	local evo = s:match("^(Evo%s+%a+%s+I+)$")
	      or s:match("(Evo%s+%a+%s+I+)")
	      or s:match("^(Evo%s+%a+%s+VI?I?)$")
	      or s:match("(Evo%s+%a+%s+VI?I?)")
	if evo then return evo:gsub("%s+"," ") end
	local base, roman = s:match("^(Evo%s+%a+)%s+([IVX]+)")
	if base and roman then return (base.." "..roman) end
	return s
end

local function getEvoSeedTools()
	local found={}
	for _,obj in ipairs(backpack:GetChildren()) do
		if obj:IsA("Tool") then
			local n=string.lower(obj.Name)
			if n:find("evo",1,true) and n:find("seed",1,true) then table.insert(found,obj) end
		end
	end
	return found
end

-- calcule position sol sous (X,Z) par raycast (fallback Y capturé)
local function getGroundPositionXZ(x, z)
	local origin = Vector3.new(x, 50, z)
	local direction = Vector3.new(0, -200, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local result = Workspace:Raycast(origin, direction, params)
	if result then
		return Vector3.new(x, result.Position.Y + 0.01, z)
	end
	return Vector3.new(x, 0.13552284240722656, z)
end

local function processPlantEvoSeeds()
	local seeds = getEvoSeedTools()
	if #seeds==0 then statusLbl.Text="Aucune EVO Seed dans le Backpack."; flash(evoFrame,{80,30,30},{24,24,28}); return end

	local hrp = getHRP(); if not hrp then statusLbl.Text="HRP introuvable."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local pos = getGroundPositionXZ(hrp.Position.X, hrp.Position.Z)

	local remote = findPlantRemote()
	if not remote then statusLbl.Text="Remote Plant_RE introuvable."; flash(evoFrame,{80,30,30},{24,24,28}); return end

	local succ, fail = 0, 0
	for i,tool in ipairs(seeds) do
		local evoName = canonicalEvoName(tool.Name)
		statusLbl.Text = ("Plante %d/%d: %s → (%.5f, %.5f, %.5f)"):format(i,#seeds,evoName,pos.X,pos.Y,pos.Z)
		humanoid:EquipTool(tool); task.wait(0.06)

		local ok, err = pcall(function()
			remote:FireServer(pos, evoName)  -- [Vector3, "Evo Beetroot I"]
		end)

		if ok then succ += 1; statusLbl.Text=("Planted ✓: %s"):format(evoName)
		else fail += 1; statusLbl.Text=("Échec plant %s: %s"):format(evoName, tostring(err)); flash(evoFrame,{80,30,30},{24,24,28}) end
		task.wait(0.10)
	end

	statusLbl.Text = ("Plant terminé — %d succès, %d échecs."):format(succ,fail)
	flash(evoFrame,{30,80,30},{24,24,28})
end

-- Wire EVO MANAGER UI
local evoManagerBtnRef = evoManagerBtn
evoManagerBtnRef.MouseButton1Click:Connect(function() evoFrame.Visible = not evoFrame.Visible end)
evoClose.MouseButton1Click:Connect(function() evoFrame.Visible=false end)

local rescanBtnRef, submitBtnRef, plantEvoBtnRef = rescanBtn, submitBtn, plantEvoBtn
rescanBtnRef.MouseButton1Click:Connect(function()
	local tools=getMatchingToolsForSubmit()
	statusLbl.Text=("Scan Submit: %d outil(s) correspondants (IV exclues)."):format(#tools)
	if #tools>0 then flash(evoFrame,{30,80,30},{24,24,28}) else flash(evoFrame,{80,30,30},{24,24,28}) end
end)
submitBtnRef.MouseButton1Click:Connect(function()
	submitBtnRef.AutoButtonColor=false; submitBtnRef.BackgroundColor3=Color3.fromRGB(90,90,110)
	processAllSubmit()
	submitBtnRef.AutoButtonColor=true; submitBtnRef.BackgroundColor3=Color3.fromRGB(60,120,255)
end)
plantEvoBtnRef.MouseButton1Click:Connect(function()
	plantEvoBtnRef.AutoButtonColor=false; plantEvoBtnRef.BackgroundColor3=Color3.fromRGB(90,110,90)
	processPlantEvoSeeds()
	plantEvoBtnRef.AutoButtonColor=true; plantEvoBtnRef.BackgroundColor3=Color3.fromRGB(50,160,90)
end)

-- Maj coord affichées en live dans l'EVO manager
task.spawn(function()
	while evoFrame and evoFrame.Parent do
		task.wait(0.2)
		if evoFrame.Visible then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local p = hrp.Position
				posLabel.Text = ("Pos: (%.2f, %.2f, %.2f) | Y sol auto"):format(p.X, p.Y, p.Z)
			else
				posLabel.Text = "Pos: (N/A)"
			end
		end
	end
end)

-- apply initial values + respawn handling
applySpeed(currentSpeed); applyGravity(currentGravity); applyJump(currentJump); updateTimerLabels()
player.CharacterAdded:Connect(function(char)
	char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = currentSpeed; hum.JumpPower = currentJump end
	workspace.Gravity = currentGravity
	if isNoclipping then task.wait(0.2); toggleNoclip(nil); toggleNoclip(nil) end
end)

msg("✅ Saad helper pack chargé + EVO MANAGER (Submit I/II/III, IV exclues) & Plant EVO Seeds via Plant_RE (Vector3 + nom canonique) à ta position (raycast). Ouvre via '🔧 EVO MANAGER'.", Color3.fromRGB(170,230,255))
