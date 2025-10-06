-- Saad helper pack v3.0 + Acorn Collector v2.6
-- - Player Tuner + Gear Panel + Anti-AFK
-- - Bouton pour ouvrir l'UI "🌰 ACORN COLLECTOR"
-- - Acorn Collector: Nutty Fever aware, TP dur + retour XYZ, harvest plantes-only
-- - Compteur d'acorns + Timer calé Chubby (109s / 30s Fever)
-- - ⌘/Ctrl + clic pour TP/collect (Mac OK)
-- - Scanner d'acorn: bouton + auto-scan 29s (Y ∈ [1;4])
-- - AUTO-HARVEST = version v2.4 (celle qui marche chez toi), réintégrée telle quelle
-- - 🔕 MOD: Auto-harvest ignore Mushroom

--// Services
local Players             = game:GetService("Players")
local UserInputService    = game:GetService("UserInputService")
local RunService          = game:GetService("RunService")
local StarterGui          = game:GetService("StarterGui")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local TweenService        = game:GetService("TweenService")
local Workspace           = game:GetService("Workspace")
local VirtualUser         = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local SoundService        = game:GetService("SoundService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Consts
local DEFAULT_GRAVITY, DEFAULT_JUMPPOWER, DEFAULT_WALKSPEED = 196.2, 50, 16
local GEAR_SHOP_POS = Vector3.new(-288, 2, -15)
local SELL_NPC_POS  = Vector3.new(87, 3, 0)

-- Anti-AFK
local ANTI_AFK_PERIOD   = 60
local ANTI_AFK_DURATION = 0.35

-- Planting pacing
local PLANT_DELAY_FACTOR = 1.2
local function pwait(t) task.wait(t * PLANT_DELAY_FACTOR) end

-- Seeds/Gears
local SEED_TIER = "Tier 1"
local SEEDS = {
	"Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon",
	"Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom",
	"Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone",
	"Elder Strawberry","Romanesco","Crimson Thorn"
}
local GEARS = {
	"Watering Can","Trading Ticket","Trowel","Recall Wrench","Basic Sprinkler","Advanced Sprinkler",
	"Medium Toy","Medium Treat","Godly Sprinkler","Magnifying Glass","Master Sprinkler",
	"Cleaning Spray","Cleansing Pet Shard","Favorite Tool","Harvest Tool","Friendship Pot",
	"Grandmaster Sprinkler","Level Up Lollipop"
}
local EGGS = {
	"Common Egg","Uncommon Egg","Rare Egg","Legendary Egg","Mythical Egg","Bug Egg","Jungle Egg"
}

-- Auto périodes
local MAX_TRIES_PER_SEED, MAX_TRIES_PER_GEAR = 20, 5
local AUTO_PERIOD_SEEDS = 150
local AUTO_PERIOD_GEAR  = 150
local AUTO_PERIOD_EVENT = 55
local AUTO_PERIOD_EGGS  = 450

--// State
local currentSpeed, currentGravity, currentJump = 18, 147.1, 60
local isNoclipping, noclipConnection = false, nil
local autoBuySeeds, autoBuyGear, autoBuyEvent, autoBuyEggs = false, false, false, false
local seedsTimer, gearTimer, eventTimer, eggsTimer =
	AUTO_PERIOD_SEEDS, AUTO_PERIOD_GEAR, AUTO_PERIOD_EVENT, AUTO_PERIOD_EGGS

local antiAFKEnabled = false

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
	local c = player.Character
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

-- Clamp UI à l’écran
local function clampOnScreen(frame)
	task.defer(function()
		if not frame or not frame.Parent then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local abs = frame.AbsoluteSize
		local px = math.clamp(frame.AbsolutePosition.X, 0, math.max(0, vp.X - abs.X))
		local py = math.clamp(frame.AbsolutePosition.Y, 0, math.max(0, vp.Y - abs.Y))
		frame.Position = UDim2.fromOffset(px, py)
	end)
end

-- AutoScale
local function applyAutoScale(screenGuiX, clampTargets)
	local cam = workspace.CurrentCamera
	local scaleObj = screenGuiX:FindFirstChild("AutoScale") or Instance.new("UIScale")
	scaleObj.Name = "AutoScale"
	scaleObj.Parent = screenGuiX
	local function computeScale()
		local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
		local w, h = vp.X, vp.Y
		local baseWidth = 1280
		local s = w / baseWidth
		if h < 720 or w < 1100 then s = s * 0.9 end
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then s = s * 0.9 end
		return math.clamp(s, 0.55, 1.0)
	end
	local function refresh()
		scaleObj.Scale = computeScale()
		if clampTargets then
			for _, guiObj in ipairs(clampTargets) do
				if guiObj and guiObj.Parent then clampOnScreen(guiObj) end
			end
		end
	end
	refresh()
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh) end
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refresh)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(refresh)
end

-- Remotes
local function safeWait(path, timeout)
	local node=ReplicatedStorage
	for _,name in ipairs(path) do node=node:WaitForChild(name, timeout) if not node then return nil end end
	return node
end
local function getSellInventoryRemote()  local r=safeWait({"GameEvents","Sell_Inventory"},2)                return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuySeedRemote()        local r=safeWait({"GameEvents","BuySeedStock"},2)                  return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyGearRemote()        local r=safeWait({"GameEvents","BuyGearStock"},2)                  return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyEventRemote()
	local r=safeWait({"GameEvents","BuyEventShopStock"},2)
	if r and r:IsA("RemoteEvent") then return r end
	r=safeWait({"GameEvents","FallMarketEvent","BuyEventShopStock"},2)
	return (r and r:IsA("RemoteEvent")) and r or nil
end
local function getBuyPetEggRemote()
	local r=safeWait({"GameEvents","BuyPetEgg"},2)
	return (r and r:IsA("RemoteEvent")) and r or nil
end
local function getSubmitChipmunkRemote()
	local r = safeWait({"GameEvents","SubmitChipmunkFruit"},2)
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
		for i=1,MAX_TRIES_PER_SEED do pcall(function() r:FireServer(SEED_TIER, seed) end) pwait(0.05) end
		msg("✅ "..seed.." ok.", Color3.fromRGB(160,230,180)); pwait(0.03)
	end
	msg("🎉 Seeds terminé.")
end
local function buyAllGearWorker()
	local r = getBuyGearRemote(); if not r then msg("❌ BuyGearStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🧰 Achat: tous les gears…")
	for _, g in ipairs(GEARS) do
		for i=1,MAX_TRIES_PER_GEAR do pcall(function() r:FireServer(g) end) pwait(0.06) end
		msg("✅ "..g.." ok.", Color3.fromRGB(180,220,200)); pwait(0.03)
	end
	msg("🎉 Gears terminé.")
end

-- BUY EVO
local EVO_LIST = { "Evo Beetroot I","Evo Blueberry I","Evo Pumpkin I","Evo Mushroom I" }
local function buyEventEvosWorker()
	local remote = getBuyEventRemote()
	if not remote then msg("❌ Remote BuyEventShopStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🎃 Achat EVO (qty=1) …", Color3.fromRGB(230,200,140))
	for _, name in ipairs(EVO_LIST) do
		local ok, err = pcall(function() remote:FireServer(name, 1) end)
		if ok then msg(("✅ %s (x1) envoyé."):format(name), Color3.fromRGB(200,240,200))
		else msg(("⚠️ %s échec: %s"):format(name, tostring(err)), Color3.fromRGB(255,180,120)) end
		pwait(0.06)
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
		pwait(0.06)
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
		if autoBuySeeds then seedsTimer = seedsTimer - 1 else seedsTimer = AUTO_PERIOD_SEEDS end
		if autoBuyGear  then gearTimer  = gearTimer  - 1 else gearTimer  = AUTO_PERIOD_GEAR end
		if autoBuyEvent then eventTimer = eventTimer - 1 else eventTimer = AUTO_PERIOD_EVENT end
		if autoBuyEggs  then eggsTimer  = eggsTimer  - 1 else eggsTimer  = AUTO_PERIOD_EGGS end
		if autoBuySeeds and seedsTimer<=0 then buyAllSeedsWorker(); seedsTimer=AUTO_PERIOD_SEEDS end
		if autoBuyGear  and gearTimer<=0  then buyAllGearWorker();  gearTimer =AUTO_PERIOD_GEAR  end
		if autoBuyEvent and eventTimer<=0 then buyEventEvosWorker(); eventTimer=AUTO_PERIOD_EVENT end
		if autoBuyEggs  and eggsTimer<=0  then buyAllEggsWorker();  eggsTimer =AUTO_PERIOD_EGGS  end
		updateTimerLabels()
	end
end)

-- Draggable
local function makeDraggable(frame, handle)
	frame.Active = true; frame.Selectable = true
	handle.Active = true; handle.Selectable = true
	local dragging = false
	local dragStart, startPos, dragInputId
	local function update(input)
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	local function begin(input)
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
		dragInputId = input
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				clampOnScreen(frame)
			end
		end)
	end
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			begin(i)
		end
	end)
	handle.InputChanged:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
			if dragging then update(i) end
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i == dragInputId or i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			update(i)
		end
	end)
end

-- Helper
local function rounded(obj, r)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, r or 8)
	ui.Parent = obj
	return ui
end

-- ================= MAIN UI =================
screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerTuner"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false -- ✅
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(320, 326)
mainFrame.Position = UDim2.fromScale(0.02, 0.04)
mainFrame.BackgroundColor3 = Color3.fromRGB(36,36,36)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
rounded(mainFrame, 10)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(28,28,28)
titleBar.Parent = mainFrame
rounded(titleBar, 10)

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
closeButton.Size = UDim2.fromOffset(26, 26)
closeButton.Position = UDim2.new(1, -34, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(255,72,72)
closeButton.TextColor3 = Color3.fromRGB(255,255,255)
closeButton.Text = "✕"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 14
closeButton.Parent = titleBar
rounded(closeButton, 0)

local isMinimized = false
local fullSize = UDim2.fromOffset(320, 326)
local collapsedSize = UDim2.fromOffset(320, 36)
local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.fromOffset(26, 26)
minimizeButton.Position = UDim2.new(1, -66, 0, 5)
minimizeButton.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.Text = "—"
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.TextSize = 14
minimizeButton.Parent = titleBar
rounded(minimizeButton, 0)

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
	local track = Instance.new("Frame"); track.Size = UDim2.new(1, 0, 0, 10); track.Position = UDim2.new(0, 0, 0, 26); track.BackgroundColor3 = Color3.fromRGB(64,64,64); track.BorderSizePixel = 0; track.Parent = frame; rounded(track,6)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(0,170,255); fill.BorderSizePixel = 0; fill.Parent = track; rounded(fill,6)
	local knob = Instance.new("Frame"); knob.Size = UDim2.fromOffset(16, 16); knob.AnchorPoint = Vector2.new(0.5,0.5); knob.Position = UDim2.new(0, 0, 0.5, 0); knob.BackgroundColor3 = Color3.fromRGB(230,230,230); knob.BorderSizePixel = 0; knob.Parent = track; rounded(knob,16)
	local function clamp(v,a,b) return math.max(a, math.min(b, v)) end
	local function snap(v) return math.floor((v - minValue)/step + 0.5)*step + minValue end
	local function fmt(val) if decimals and decimals > 0 then return string.format("%."..tostring(decimals).."f", val) else return tostring(math.floor(val + 0.5)) end end
	local function setVisual(pct, val) fill.Size = UDim2.new(pct, 0, 1, 0); knob.Position = UDim2.new(pct, 0, 0.5, 0); valueLabel.Text = fmt(val) end
	local function setValue(val, fire) val = clamp(snap(val), minValue, maxValue); local pct = (val - minValue) / (maxValue - minValue); setVisual(pct, val); if fire and onChange then onChange(val) end end
	local dragging = false
	local function updateFromX(x) local ap,as = track.AbsolutePosition.X, track.AbsoluteSize.X; if as<=0 then return end; local pct = math.max(0, math.min(1, (x-ap)/as)); local val = minValue + pct*(maxValue-minValue); setValue(val, true) end
	track.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			dragging=true; updateFromX(i.Position.X)
			i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false; clampOnScreen(mainFrame) end end)
		end
	end)
	knob.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			dragging=true; updateFromX(i.Position.X)
			i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false; clampOnScreen(mainFrame) end end)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
			updateFromX(i.Position.X)
		end
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
rounded(resetBtn,8)

local noclipBtn = Instance.new("TextButton")
noclipBtn.Size = UDim2.new(0.33, -6, 1, 0)
noclipBtn.Position = UDim2.new(0.335, 6, 0, 0)
noclipBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
noclipBtn.TextColor3 = Color3.fromRGB(255,255,255)
noclipBtn.Text = "🚫 NO CLIP: OFF"
noclipBtn.Font = Enum.Font.GothamBold
noclipBtn.TextSize = 13
noclipBtn.Parent = buttonsRow
rounded(noclipBtn,8)

local toggleGearBtn = Instance.new("TextButton")
toggleGearBtn.Size = UDim2.new(0.33, 0, 1, 0)
toggleGearBtn.Position = UDim2.new(0.67, 6, 0, 0)
toggleGearBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
toggleGearBtn.TextColor3 = Color3.fromRGB(255,255,255)
toggleGearBtn.Text = "🛒 Toggle Gear Panel"
toggleGearBtn.Font = Enum.Font.GothamBold
toggleGearBtn.TextSize = 13
toggleGearBtn.Parent = buttonsRow
rounded(toggleGearBtn,8)

-- Row 2: Anti-AFK toggle
local miscRow = Instance.new("Frame"); miscRow.Size = UDim2.new(1, 0, 0, 36); miscRow.Position = UDim2.new(0, 0, 0, 236)
miscRow.BackgroundTransparency = 1; miscRow.Parent = content

local antiAFKBtn = Instance.new("TextButton")
antiAFKBtn.Size = UDim2.new(0.48, -4, 1, 0)
antiAFKBtn.Position = UDim2.new(0, 0, 0, 0)
antiAFKBtn.BackgroundColor3 = Color3.fromRGB(100, 130, 100)
antiAFKBtn.TextColor3 = Color3.fromRGB(255,255,255)
antiAFKBtn.Text = "🛡️ Anti-AFK: OFF"
antiAFKBtn.Font = Enum.Font.GothamBold
antiAFKBtn.TextSize = 13
antiAFKBtn.Parent = miscRow
rounded(antiAFKBtn,8)

local antiAFKHint = Instance.new("TextLabel")
antiAFKHint.Size = UDim2.new(0.52, 0, 1, 0)
antiAFKHint.Position = UDim2.new(0.48, 4, 0, 0)
antiAFKHint.BackgroundTransparency = 1
antiAFKHint.TextXAlignment = Enum.TextXAlignment.Left
antiAFKHint.Font = Enum.Font.Gotham
antiAFKHint.TextSize = 12
antiAFKHint.TextColor3 = Color3.fromRGB(200,220,200)
antiAFKHint.Text = "Simule mouvement toutes 60s"
antiAFKHint.Parent = miscRow

-- Row 3: Bouton ACORN
local acornRow = Instance.new("Frame"); acornRow.Size = UDim2.new(1, 0, 0, 36); acornRow.Position = UDim2.new(0, 0, 0, 272)
acornRow.BackgroundTransparency = 1; acornRow.Parent = content

local openAcornBtn = Instance.new("TextButton")
openAcornBtn.Size = UDim2.new(1, 0, 1, 0)
openAcornBtn.Position = UDim2.new(0, 0, 0, 0)
openAcornBtn.BackgroundColor3 = Color3.fromRGB(200, 160, 60)
openAcornBtn.TextColor3 = Color3.fromRGB(30,30,30)
openAcornBtn.Text = "🌰 ACORN COLLECTOR"
openAcornBtn.Font = Enum.Font.GothamBold
openAcornBtn.TextSize = 14
openAcornBtn.Parent = acornRow
rounded(openAcornBtn,8)

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
gearGui.IgnoreGuiInset = false -- ✅
gearGui.Parent = playerGui

gearFrame = Instance.new("Frame")
gearFrame.Size = UDim2.fromOffset(260, 500)
gearFrame.Position = UDim2.fromScale(0.26, 0.04)
gearFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
gearFrame.BorderSizePixel = 0
gearFrame.Parent = gearGui
rounded(gearFrame,10)

local gearTitleBar = Instance.new("Frame")
gearTitleBar.Size = UDim2.new(1, 0, 0, 28)
gearTitleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 70)
gearTitleBar.Parent = gearFrame
rounded(gearTitleBar,10)

local gearTitle = Instance.new("TextLabel")
gearTitle.Size = UDim2.new(1, -40, 1, 0)
gearTitle.Position = UDim2.new(0, 10, 0, 0)
gearTitle.BackgroundTransparency = 1
gearTitle.TextColor3 = Color3.fromRGB(255,255,255)
gearTitle.Text = "🛒 GEAR SHOP"
gearTitle.Font = Enum.Font.GothamBold
gearTitle.TextSize = 13
gearTitle.TextXAlignment = Enum.TextXAlignment.Left
gearTitle.Parent = gearTitleBar

local gearClose = Instance.new("TextButton")
gearClose.Size = UDim2.fromOffset(20, 20)
gearClose.Position = UDim2.new(1, -26, 0, 4)
gearClose.BackgroundColor3 = Color3.fromRGB(255, 72, 72)
gearClose.TextColor3 = Color3.fromRGB(255,255,255)
gearClose.Text = "✕"
gearClose.Font = Enum.Font.GothamBold
gearClose.TextSize = 12
gearClose.Parent = gearTitleBar
rounded(gearClose,0)

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
rounded(tpGear,8)

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
rounded(sellBtn,8)

-- SUBMIT ALL (Chipmunk)
local submitAllChipBtn = Instance.new("TextButton")
submitAllChipBtn.Size = UDim2.new(1, 0, 0, 26)
submitAllChipBtn.Position = UDim2.new(0, 0, 0, 94)
submitAllChipBtn.BackgroundColor3 = Color3.fromRGB(90, 140, 210)
submitAllChipBtn.TextColor3 = Color3.fromRGB(255,255,255)
submitAllChipBtn.Text = "🍁 SUBMIT ALL (Chipmunk)"
submitAllChipBtn.Font = Enum.Font.GothamBold
submitAllChipBtn.TextSize = 12
submitAllChipBtn.Parent = gearContent
rounded(submitAllChipBtn,8)

-- Seeds row
local seedsRow = Instance.new("Frame")
seedsRow.Size = UDim2.new(1, 0, 0, 26)
seedsRow.Position = UDim2.new(0, 0, 0, 126)
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
rounded(buyAllSeedsButton,8)

local autoSeedsBtn = Instance.new("TextButton")
autoSeedsBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoSeedsBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoSeedsBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoSeedsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoSeedsBtn.Text = "Auto: OFF"
autoSeedsBtn.Font = Enum.Font.GothamBold
autoSeedsBtn.TextSize = 12
autoSeedsBtn.Parent = seedsRow
rounded(autoSeedsBtn,8)

seedsTimerLabel = Instance.new("TextLabel")
seedsTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
seedsTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
seedsTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
seedsTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
seedsTimerLabel.Text = "⏳ Next: 2:30"
seedsTimerLabel.Font = Enum.Font.Gotham
seedsTimerLabel.TextSize = 12
seedsTimerLabel.Parent = seedsRow
rounded(seedsTimerLabel,8)

-- Gear row
local gearRow = Instance.new("Frame")
gearRow.Size = UDim2.new(1, 0, 0, 26)
gearRow.Position = UDim2.new(0, 0, 0, 158)
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
rounded(buyAllGearButton,8)

local autoGearBtn = Instance.new("TextButton")
autoGearBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoGearBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoGearBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoGearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoGearBtn.Text = "Auto: OFF"
autoGearBtn.Font = Enum.Font.GothamBold
autoGearBtn.TextSize = 12
autoGearBtn.Parent = gearRow
rounded(autoGearBtn,8)

gearTimerLabel = Instance.new("TextLabel")
gearTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
gearTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
gearTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
gearTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
gearTimerLabel.Text = "⏳ Next: 2:30"
gearTimerLabel.Font = Enum.Font.Gotham
gearTimerLabel.TextSize = 12
gearTimerLabel.Parent = gearRow
rounded(gearTimerLabel,8)

-- EVO row
local eventRow = Instance.new("Frame")
eventRow.Size = UDim2.new(1, 0, 0, 26)
eventRow.Position = UDim2.new(0, 0, 0, 190)
eventRow.BackgroundTransparency = 1
eventRow.Parent = gearContent

local buyEvoButton = Instance.new("TextButton")
buyEvoButton.Size = UDim2.new(0.48, -4, 1, 0)
buyEvoButton.Position = UDim2.new(0, 0, 0, 0)
buyEvoButton.BackgroundColor3 = Color3.fromRGB(200, 140, 90)
buyEvoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyEvoButton.Text = "🍁 BUY EVO (x1)"
buyEvoButton.Font = Enum.Font.GothamBold
buyEvoButton.TextSize = 12
buyEvoButton.Parent = eventRow
rounded(buyEvoButton,8)

local autoEventBtn = Instance.new("TextButton")
autoEventBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoEventBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoEventBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoEventBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoEventBtn.Text = "Auto: OFF"
autoEventBtn.Font = Enum.Font.GothamBold
autoEventBtn.TextSize = 12
autoEventBtn.Parent = eventRow
rounded(autoEventBtn,8)

eventTimerLabel = Instance.new("TextLabel")
eventTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
eventTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
eventTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
eventTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
eventTimerLabel.Text = "⏳ Next: 0:55"
eventTimerLabel.Font = Enum.Font.Gotham
eventTimerLabel.TextSize = 12
eventTimerLabel.Parent = eventRow
rounded(eventTimerLabel,8)

-- EGGS row
local eggsRow = Instance.new("Frame")
eggsRow.Size = UDim2.new(1, 0, 0, 26)
eggsRow.Position = UDim2.new(0, 0, 0, 222)
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
rounded(buyEggsButton,8)

local autoEggsBtn = Instance.new("TextButton")
autoEggsBtn.Size = UDim2.new(0.22, -4, 1, 0)
autoEggsBtn.Position = UDim2.new(0.48, 4, 0, 0)
autoEggsBtn.BackgroundColor3 = Color3.fromRGB(80, 90, 120)
autoEggsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoEggsBtn.Text = "Auto: OFF"
autoEggsBtn.Font = Enum.Font.GothamBold
autoEggsBtn.TextSize = 12
autoEggsBtn.Parent = eggsRow
rounded(autoEggsBtn,8)

eggsTimerLabel = Instance.new("TextLabel")
eggsTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
eggsTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
eggsTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
eggsTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
eggsTimerLabel.Text = "⏳ Next: 7:30"
eggsTimerLabel.Font = Enum.Font.Gotham
eggsTimerLabel.TextSize = 12
eggsTimerLabel.Parent = eggsRow
rounded(eggsTimerLabel,8)

-- gear actions
tpGear.MouseButton1Click:Connect(function() teleportTo(GEAR_SHOP_POS) end)
sellBtn.MouseButton1Click:Connect(function()
	local r = getSellInventoryRemote()
	if not r then msg("❌ Remote Sell_Inventory introuvable.", Color3.fromRGB(255,120,120)); return end
	local hrp = getHRP(); if not hrp then msg("❌ HRP introuvable.", Color3.fromRGB(255,120,120)); return end
	local back = hrp.CFrame
	withFrozenCamera(function()
		teleportTo(SELL_NPC_POS); pwait(0.20); r:FireServer(); pwait(0.05); hrp.CFrame = back
	end)
	msg("🧺 Inventaire vendu (TP/retour).", Color3.fromRGB(220,200,140))
end)

local function submitAllChipmunk()
	local r = getSubmitChipmunkRemote()
	if not r then msg("❌ Remote SubmitChipmunkFruit introuvable.", Color3.fromRGB(255,120,120)); return end
	local ok, err = pcall(function() r:FireServer("All") end)
	if ok then msg("✅ SubmitChipmunkFruit: All envoyé.", Color3.fromRGB(160,230,200))
	else msg("❌ Erreur SubmitChipmunkFruit: "..tostring(err), Color3.fromRGB(255,120,120)) end
end
submitAllChipBtn.MouseButton1Click:Connect(function()
	submitAllChipBtn.AutoButtonColor = false
	submitAllChipBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
	submitAllChipmunk()
	task.delay(0.2, function()
		submitAllChipBtn.AutoButtonColor = true
		submitAllChipBtn.BackgroundColor3 = Color3.fromRGB(90, 140, 210)
	end)
end)

buyAllSeedsButton.MouseButton1Click:Connect(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD_SEEDS; updateTimerLabels() end)
buyAllGearButton.MouseButton1Click:Connect(function() buyAllGearWorker();  gearTimer  = AUTO_PERIOD_GEAR;  updateTimerLabels() end)
buyEvoButton.MouseButton1Click:Connect(function() buyEventEvosWorker(); eventTimer = AUTO_PERIOD_EVENT; updateTimerLabels() end)
buyEggsButton.MouseButton1Click:Connect(function() buyAllEggsWorker();   eggsTimer = AUTO_PERIOD_EGGS;  updateTimerLabels() end)

autoSeedsBtn.MouseButton1Click:Connect(function()
	autoBuySeeds = not autoBuySeeds
	autoSeedsBtn.BackgroundColor3 = autoBuySeeds and Color3.fromRGB(70,160,90) or Color3.fromRGB(80,90,120)
	autoSeedsBtn.Text = autoBuySeeds and "Auto: ON" or "Auto: OFF"
	if autoBuySeeds then msg("⏱️ Auto-buy SEEDS activé (2:30). Exécution maintenant…"); task.spawn(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD_SEEDS; updateTimerLabels() end)
	else msg("⏹️ Auto-buy SEEDS désactivé.") end
	updateTimerLabels()
end)
autoGearBtn.MouseButton1Click:Connect(function()
	autoBuyGear = not autoBuyGear
	autoGearBtn.BackgroundColor3 = autoBuyGear and Color3.fromRGB(70,140,180) or Color3.fromRGB(80,90,120)
	autoGearBtn.Text = autoBuyGear and "Auto: ON" or "Auto: OFF"
	if autoBuyGear then msg("⏱️ Auto-buy GEAR activé (2:30). Exécution maintenant…"); task.spawn(function() buyAllGearWorker(); gearTimer = AUTO_PERIOD_GEAR; updateTimerLabels() end)
	else msg("⏹️ Auto-buy GEAR désactivé.") end
	updateTimerLabels()
end)
autoEventBtn.MouseButton1Click:Connect(function()
	autoBuyEvent = not autoBuyEvent
	autoEventBtn.BackgroundColor3 = autoBuyEvent and Color3.fromRGB(180,120,80) or Color3.fromRGB(80,90,120)
	autoEventBtn.Text = autoBuyEvent and "Auto: ON" or "Auto: OFF"
	if autoBuyEvent then msg("⏱️ Auto-buy EVO activé (0:55). Exécution maintenant…"); task.spawn(function() buyEventEvosWorker(); eventTimer = AUTO_PERIOD_EVENT; updateTimerLabels() end)
	else msg("⏹️ Auto-buy EVO désactivé.") end
	updateTimerLabels()
end)
autoEggsBtn.MouseButton1Click:Connect(function()
	autoBuyEggs = not autoBuyEggs
	autoEggsBtn.BackgroundColor3 = autoBuyEggs and Color3.fromRGB(120,100,160) or Color3.fromRGB(80,90,120)
	autoEggsBtn.Text = autoBuyEggs and "Auto: ON" or "Auto: OFF"
	if autoBuyEggs then msg("⏱️ Auto-buy EGGS activé (7:30). Exécution maintenant…"); task.spawn(function() buyAllEggsWorker(); eggsTimer = AUTO_PERIOD_EGGS; updateTimerLabels() end)
	else msg("⏹️ Auto-buy EGGS désactivé.") end
	updateTimerLabels()
end)

gearClose.MouseButton1Click:Connect(function() gearFrame.Visible = false end)
local function toggleGear() gearFrame.Visible = not gearFrame.Visible; if gearFrame.Visible then clampOnScreen(gearFrame) end end
toggleGearBtn.MouseButton1Click:Connect(toggleGear)

-- live coords
do
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc = acc + dt; if acc < 0.2 then return end; acc = 0
		local hrp = getHRP()
		if hrp then
			local x = math.floor(hrp.Position.X)
			local y = math.floor(hrp.Position.Y)
			local z = math.floor(hrp.Position.Z)
			coordsLabel.Text = ("Position: (%d, %d, %d)"):format(x,y,z)
		else
			coordsLabel.Text = "Position: (N/A)"
		end
	end)
end

-- =========== Anti-AFK ===========
player.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0,0))
	end)
end)
antiAFKBtn.MouseButton1Click:Connect(function()
	antiAFKEnabled = not antiAFKEnabled
	antiAFKBtn.Text = antiAFKEnabled and "🛡️ Anti-AFK: ON" or "🛡️ Anti-AFK: OFF"
	antiAFKBtn.BackgroundColor3 = antiAFKEnabled and Color3.fromRGB(80,140,90) or Color3.fromRGB(100,130,100)
	if antiAFKEnabled then
		msg("🛡️ Anti-AFK activé (nudge périodique + VirtualUser).", Color3.fromRGB(180,230,180))
	else
		msg("🛡️ Anti-AFK désactivé.", Color3.fromRGB(230,200,180))
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum:Move(Vector3.new(0,0,0), true) end
	end
end)
task.spawn(function()
	while true do
		task.wait(ANTI_AFK_PERIOD)
		if antiAFKEnabled then
			local character = player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:Move(Vector3.new(0, 0, -1), true)
				task.wait(ANTI_AFK_DURATION)
				hum:Move(Vector3.new(0, 0, 0), true)
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

-- ==== Auto-scale ====
applyAutoScale(screenGui, {mainFrame})
applyAutoScale(gearGui,   {gearFrame})

-- ===================================================================
-- =====================  ACORN COLLECTOR UI  ========================
-- ===================================================================
local acornGui -- ScreenGui (créé à la première ouverture)
local function ensureAcornGui()
	if acornGui and acornGui.Parent then return acornGui end

	local ac = {} -- namespace local

	-- Config Chubby (109s) + Fever (30s)
	ac.config = {
		acornName = "Acorn",
		normalSpawnInterval = 109,
		feverSpawnInterval  = 30,
		acornDuration       = 30,

		feverGroundDistance = 6,
		groundIgnoreHeight  = 20,
		feverYTolerance     = 2,

		instantTp = false,
		tpSpeed   = 120,
		returnToStartAfterCollect = true,

		autoHarvestRadius   = 25,
		autoHarvestTick     = 0.12,
		autoHarvestSpamE    = false, -- prompts only
		autoHarvestUsePrompts = true,
		promptHoldDuration  = 0.25,  -- ← valeur v2.4

		-- ✅ Whitelist sans "mushroom"
		plantWhitelist = { "plant","harvest","crop","fruit","vegetable","tree","bush","flower","pick","collect" },
		-- ✅ Exclusions explicites
		plantExclude = { "mushroom" },

		promptTextWhitelist = { "harvest","pick","collect","récolter","cueillir" },
		promptBlacklist = { "fence","save","slot","skin","shop","buy","sell","chest","settings","rename","open","claim","craft","upgrade" },

		soundAlert = true,
		screenAlert = true,
	}

	-- State
	ac.nextSpawnTime = tick() + ac.config.normalSpawnInterval
	ac.currentAcorn = nil
	ac.autoCollecting = false
	ac.autoTPOnDetect = true
	ac.teleportBusy = false
	ac.lastTeleportedAcorn = nil
	ac.esp = {}

	ac.isNuttyFever = false
	ac.lastSpawnTimestamps = {}
	ac.FEVER_INFER_WINDOW = 45
	ac.FEVER_INFER_GAP    = 35
	ac.feverLastSeenAt    = 0
	ac.FEVER_TIMEOUT      = 180

	ac.acornCollected = 0
	ac.pendingCollect = {}

	ac.scanAutoEnabled = false
	ac.scanPeriod      = 29

	-- Sounds
	ac.alertSound = Instance.new("Sound")
	ac.alertSound.SoundId = "rbxassetid://2767090"
	ac.alertSound.Volume = 0.5
	ac.alertSound.Parent = SoundService

	-- Helpers
	local function hardSetPosition(pos)
		local char = player.Character
		local hrp = getHRP()
		if not hrp then return end
		pcall(function()
			hrp.AssemblyLinearVelocity = Vector3.new()
			hrp.AssemblyAngularVelocity = Vector3.new()
		end)
		if char and typeof(char.PivotTo) == "function" then
			char:PivotTo(CFrame.new(pos))
		else
			hrp.CFrame = CFrame.new(pos)
		end
	end

	local function teleportTween(position)
		local hrp = getHRP()
		if not hrp or ac.teleportBusy then return end
		ac.teleportBusy = true
		if ac.config.instantTp then
			hardSetPosition(position)
			ac.teleportBusy = false
			return
		end
		local startPos = hrp.Position
		local distance = (position - startPos).Magnitude
		local travelTime = math.max(distance / ac.config.tpSpeed, 0.05)
		local tween = TweenService:Create(
			hrp,
			TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
			{CFrame = CFrame.new(position)}
		)
		tween:Play()
		tween.Completed:Connect(function()
			ac.teleportBusy = false
		end)
	end

	local function isGrounded(acorn)
		if not acorn or not acorn.Parent then return false, nil end
		local origin = acorn.Position
		local direction = Vector3.new(0, -200, 0)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {acorn}
		if Enum.RaycastFilterType and Enum.RaycastFilterType.Exclude then
			params.FilterType = Enum.RaycastFilterType.Exclude
		end
		params.IgnoreWater = false
		local result = Workspace:Raycast(origin, direction, params)
		if result then
			local dist = (origin - result.Position).Magnitude
			return dist <= ac.config.feverGroundDistance, dist
		else
			return false, nil
		end
	end

	local function isYAlignedWithPlayer(acorn)
		local hrp = getHRP()
		if not hrp or not acorn then return false end
		return math.abs(acorn.Position.Y - hrp.Position.Y) <= ac.config.feverYTolerance
	end

	local function createESP(acornPart)
		if ac.esp[acornPart] then return end
		local highlight = Instance.new("Highlight")
		highlight.Name = "AcornESP"
		highlight.Adornee = acornPart
		highlight.FillColor = Color3.fromRGB(255, 200, 0)
		highlight.FillTransparency = 0.4
		highlight.OutlineColor = Color3.fromRGB(255, 200, 0)
		highlight.OutlineTransparency = 0
		highlight.Parent = acornPart

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "AcornInfo"
		billboard.Adornee = acornPart
		billboard.Size = UDim2.new(0, 200, 0, 50)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = acornPart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.SourceSansBold
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Parent = billboard

		ac.esp[acornPart] = {highlight = highlight, billboard = billboard, label = label}

		task.spawn(function()
			while acornPart.Parent and ac.esp[acornPart] do
				local hrp = getHRP()
				if hrp then
					local distance = (acornPart.Position - hrp.Position).Magnitude
					local grounded = select(1, isGrounded(acornPart))
					local yFlag = ac.isNuttyFever and (isYAlignedWithPlayer(acornPart) and " (Y✓)" or " (Y✗)") or ""
					local gFlag = grounded and " (sol)" or ""
					ac.esp[acornPart].label.Text = string.format("🌰 ACORN%s%s\n%.1fm", yFlag, gFlag, distance)
					local pulse = math.sin(tick() * 4) * 0.2 + 0.25
					highlight.FillTransparency = pulse
				end
				task.wait(0.1)
			end
		end)
	end

	local function cleanupESP(acornPart)
		local e = ac.esp[acornPart]
		if not e then return end
		if e.highlight then e.highlight:Destroy() end
		if e.billboard then e.billboard:Destroy() end
		ac.esp[acornPart] = nil
	end

	-- UI counters
	local acornCountLabel
	local function setCount(n)
		if acornCountLabel then
			acornCountLabel.Text = ("🥜 Collected: %d"):format(n or 0)
		end
	end

	-- Collect (TP dur -> collect -> retour)
	local function collectAcorn(acornPart)
		if not acornPart or not acornPart.Parent then return end
		local hrp = getHRP()
		if not hrp then return end
		ac.pendingCollect[acornPart] = true

		local originalPos = hrp.Position
		hardSetPosition(acornPart.Position + Vector3.new(0,3,0))
		task.wait(0.10)

		pcall(function()
			local hrp2 = getHRP()
			if hrp2 then
				firetouchinterest(hrp2, acornPart, 0)
				task.wait(0.05)
				firetouchinterest(hrp2, acornPart, 1)
			end
		end)
		local prompt = acornPart:FindFirstChildOfClass("ProximityPrompt"); if prompt then pcall(fireproximityprompt, prompt) end
		local click  = acornPart:FindFirstChildOfClass("ClickDetector");   if click  then pcall(fireclickdetector,  click)  end

		task.wait(0.15)
		if ac.config.returnToStartAfterCollect and originalPos then
			hardSetPosition(originalPos)
		end
	end
	ac._collectAcorn = collectAcorn

	local function bestAcornCandidate(a, b)
		if not a then return b end
		if not b then return a end
		local hrp = getHRP()
		local da = hrp and (a.Position - hrp.Position).Magnitude or math.huge
		local db = hrp and (b.Position - hrp.Position).Magnitude or math.huge
		if ac.isNuttyFever then
			local aY = isYAlignedWithPlayer(a)
			local bY = isYAlignedWithPlayer(b)
			if aY ~= bY then return aY and a or b end
			local ag = select(1, isGrounded(a))
			local bg = select(1, isGrounded(b))
			if ag ~= bg then return ag and a or b end
			return (da <= db) and a or b
		else
			return (da <= db) and a or b
		end
	end

	local function onAcornDisappeared(inst)
		if ac.currentAcorn and (inst == ac.currentAcorn or (ac.currentAcorn:IsDescendantOf(inst))) then
			cleanupESP(ac.currentAcorn)
			ac.currentAcorn = nil
		end
		if ac.pendingCollect[inst] then
			ac.pendingCollect[inst] = nil
			ac.acornCollected += 1
			setCount(ac.acornCollected)
		end
	end

	local function isAcornBasePart(inst)
		if not inst then return nil end
		if inst.Name ~= ac.config.acornName then return nil end
		if inst:IsA("BasePart") then return inst end
		if inst:IsA("Model") then
			return inst:FindFirstChildWhichIsA("BasePart")
		end
		return nil
	end

	local function selectCurrentAcorn(candidate)
		if not candidate or not candidate.Parent then return end
		if not ac.currentAcorn or not ac.currentAcorn.Parent then
			ac.currentAcorn = candidate
			createESP(candidate)
			return
		end
		local best = bestAcornCandidate(ac.currentAcorn, candidate)
		if best ~= ac.currentAcorn then
			cleanupESP(ac.currentAcorn)
			ac.currentAcorn = best
			createESP(best)
		end
	end

	local function onAcornAppeared(bp)
		if not bp or not bp.Parent then return end
		-- heuristique fever
		local t = tick()
		table.insert(ac.lastSpawnTimestamps, t)
		local keep = {}
		for _, ts in ipairs(ac.lastSpawnTimestamps) do
			if t - ts <= ac.FEVER_INFER_WINDOW then table.insert(keep, ts) end
		end
		ac.lastSpawnTimestamps = keep
		if #ac.lastSpawnTimestamps >= 2 then
			local n = #ac.lastSpawnTimestamps
			local gap = ac.lastSpawnTimestamps[n] - ac.lastSpawnTimestamps[n-1]
			if gap <= ac.FEVER_INFER_GAP then
				ac.isNuttyFever = true
				ac.feverLastSeenAt = tick()
			end
		end
		ac.feverLastSeenAt = tick()
		ac.nextSpawnTime = tick() + (ac.isNuttyFever and ac.config.feverSpawnInterval or ac.config.normalSpawnInterval)

		-- Filtres
		if ac.isNuttyFever and not isYAlignedWithPlayer(bp) then return end
		if ac.isNuttyFever then
			local grounded = select(1, isGrounded(bp))
			if (not grounded) and (bp.Position.Y > ac.config.groundIgnoreHeight) then return end
		end

		if ac.config.soundAlert then ac.alertSound:Play() end
		if ac.config.screenAlert then
			StarterGui:SetCore("SendNotification", {
				Title = "🌰 ACORN SPAWNED" .. (ac.isNuttyFever and " (Fever)" or ""),
				Text = ac.isNuttyFever and ("Aligné Y±"..tostring(ac.config.feverYTolerance).." requis") or "Mode normal",
				Duration = 3,
				Icon = "rbxassetid://7733992358"
			})
		end

		selectCurrentAcorn(bp)

		if ac.autoTPOnDetect and ac.lastTeleportedAcorn ~= ac.currentAcorn and ac.currentAcorn then
			ac.lastTeleportedAcorn = ac.currentAcorn
			task.delay(0.12, function()
				if ac.currentAcorn and ac.currentAcorn.Parent then
					ac._collectAcorn(ac.currentAcorn)
				end
			end)
		end

		task.spawn(function()
			local ref = bp
			local start = tick()
			while ref.Parent and (tick() - start) < (ac.config.acornDuration + 5) do
				task.wait(0.25)
			end
			if ac.currentAcorn == ref then
				cleanupESP(ref)
				ac.currentAcorn = nil
			end
		end)
	end

	-- === Hooks spawn/despawn + Scan Y∈[1;4] ===
	Workspace.DescendantAdded:Connect(function(inst)
		local bp = isAcornBasePart(inst)
		if bp then
			if bp.Position.Y >= 1 and bp.Position.Y <= 4 then
				onAcornAppeared(bp)
			else
				onAcornAppeared(bp)
			end
		end
	end)
	Workspace.DescendantRemoving:Connect(onAcornDisappeared)

	-- Scan map: meilleur acorn avec Y∈[1;4]
	local function bestAcornCandidateWrap(a, b) return bestAcornCandidate(a, b) end
	local function scanMapAcorn()
		local best = nil
		for _, obj in ipairs(Workspace:GetDescendants()) do
			local bp = isAcornBasePart(obj)
			if bp then
				local y = bp.Position.Y
				if y >= 1 and y <= 4 then
					best = bestAcornCandidateWrap(best, bp)
				end
			end
		end
		if best then
			onAcornAppeared(best)
			return true, best
		end
		return false, nil
	end

	local function initialScan()
		local ok = select(1, scanMapAcorn())
		if not ok then
			local best = nil
			for _, obj in ipairs(Workspace:GetDescendants()) do
				local bp = isAcornBasePart(obj)
				if bp then best = bestAcornCandidateWrap(best, bp) end
			end
			if best then onAcornAppeared(best) end
		end
	end

	-- =================== AUTO HARVEST (version v2.4) ===================
	ac.autoHarvestEnabled = false

	local function lowerOrEmpty(s) if typeof(s)=="string" then return string.lower(s) end return "" end

	local function containsAny(s, list)
		for _, kw in ipairs(list) do
			if s:find(kw) then return true end
		end
		return false
	end

	local function isPlantPrompt(prompt)
		if not prompt or not prompt.Parent then return false end

		-- Textes du prompt
		local action = lowerOrEmpty(prompt.ActionText)
		local object = lowerOrEmpty(prompt.ObjectText)

		-- ❌ Exclusion prioritaire: ignore Mushroom par texte
		if containsAny(action, ac.config.plantExclude) or containsAny(object, ac.config.plantExclude) then
			return false
		end

		-- ✅ Texte de récolte explicite
		for _, kw in ipairs(ac.config.promptTextWhitelist) do
			if action:find(kw) or object:find(kw) then
				-- Double-check exclusion via ancêtres
				local node = prompt.Parent
				local steps = 0
				while node and steps < 4 do
					local nm = lowerOrEmpty(node.Name)
					if containsAny(nm, ac.config.plantExclude) then return false end
					steps += 1; node = node.Parent
				end
				return true
			end
		end

		-- Heuristique via noms/ancêtres
		local node = prompt
		local steps = 0
		while node and steps < 4 do
			local nameLower = lowerOrEmpty(node.Name)
			for _, bad in ipairs(ac.config.promptBlacklist) do if nameLower:find(bad) then return false end end
			if containsAny(nameLower, ac.config.plantExclude) then return false end -- ❌ exclu Mushroom
			for _, good in ipairs(ac.config.plantWhitelist) do if nameLower:find(good) then return true end end
			node = node.Parent; steps += 1
		end
		return false
	end

	local function makeOverlapParamsExcludeCharacter()
		local params = OverlapParams.new()
		params.FilterDescendantsInstances = {player.Character}
		if Enum.RaycastFilterType and Enum.RaycastFilterType.Blacklist then
			params.FilterType = Enum.RaycastFilterType.Blacklist
		else
			params.FilterType = Enum.RaycastFilterType.Exclude
		end
		return params
	end

	local function getNearbyPlantPrompts(radius)
		local prompts = {}
		local hrp = getHRP(); if not hrp then return prompts end

		local params = makeOverlapParamsExcludeCharacter()
		local parts = {}
		pcall(function() parts = Workspace:GetPartBoundsInRadius(hrp.Position, radius, params) end)

		local seenParents = {}
		for _, part in ipairs(parts) do
			if part and part.Parent and not seenParents[part.Parent] then
				seenParents[part.Parent] = true
				for _, child in ipairs(part.Parent:GetDescendants()) do
					if child:IsA("ProximityPrompt") and isPlantPrompt(child) then
						table.insert(prompts, child)
					end
				end
			end
		end

		-- Fallback léger si la sphère ne retourne rien
		if #prompts == 0 then
			for _, prompt in ipairs(Workspace:GetDescendants()) do
				if prompt:IsA("ProximityPrompt") and isPlantPrompt(prompt) then
					local root = prompt.Parent
					local posPart = root and root:IsA("BasePart") and root or (root and root:FindFirstChildWhichIsA("BasePart"))
					local h = getHRP()
					if posPart and h and (posPart.Position - h.Position).Magnitude <= radius then
						table.insert(prompts, prompt)
					end
				end
			end
		end
		return prompts
	end

	task.spawn(function()
		while true do
			if ac.autoHarvestEnabled then
				if ac.config.autoHarvestUsePrompts then
					local prompts = getNearbyPlantPrompts(ac.config.autoHarvestRadius)
					for _, prompt in ipairs(prompts) do
						pcall(fireproximityprompt, prompt)
						if prompt.HoldDuration and prompt.HoldDuration > 0 then
							task.wait(math.min(prompt.HoldDuration, ac.config.promptHoldDuration))
							pcall(fireproximityprompt, prompt)
						end
					end
				end
				if ac.config.autoHarvestSpamE then
					VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
					task.wait(0.03)
					VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
				end
				task.wait(ac.config.autoHarvestTick)
			else
				task.wait(0.2)
			end
		end
	end)
	-- =================== FIN AUTO HARVEST v2.4 ===================

	-- ================ UI ================
	acornGui = Instance.new("ScreenGui")
	acornGui.Name = "AcornCollectorGUI"
	acornGui.ResetOnSpawn = false
	acornGui.IgnoreGuiInset = false -- ✅
	acornGui.Enabled = true
	acornGui.Parent = playerGui

	local MainFrame = Instance.new("Frame")
	MainFrame.Size = UDim2.new(0, 340, 0, 560)
	MainFrame.Position = UDim2.new(1, -350, 0.5, -280)
	MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	MainFrame.BorderSizePixel = 0
	MainFrame.Parent = acornGui
	rounded(MainFrame, 12)

	local Header = Instance.new("Frame")
	Header.Size = UDim2.new(1, 0, 0, 45)
	Header.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	Header.BorderSizePixel = 0
	Header.Parent = MainFrame
	rounded(Header, 12)

	local Title = Instance.new("TextLabel")
	Title.Text = "🌰 Acorn Auto Collector"
	Title.Size = UDim2.new(1, -50, 1, 0)
	Title.Position = UDim2.new(0, 15, 0, 0)
	Title.BackgroundTransparency = 1
	Title.Font = Enum.Font.SourceSansBold
	Title.TextColor3 = Color3.fromRGB(255, 200, 0)
	Title.TextSize = 20
	Title.TextXAlignment = Enum.TextXAlignment.Left
	Title.Parent = Header

	local CloseButton = Instance.new("TextButton")
	CloseButton.Text = "✖"
	CloseButton.Size = UDim2.new(0, 35, 0, 35)
	CloseButton.Position = UDim2.new(1, -40, 0.5, -17.5)
	CloseButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	CloseButton.BorderSizePixel = 0
	CloseButton.Font = Enum.Font.SourceSansBold
	CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	CloseButton.TextSize = 20
	CloseButton.Parent = Header
	rounded(CloseButton, 8)

	local Container = Instance.new("Frame")
	Container.Size = UDim2.new(1, -20, 1, -55)
	Container.Position = UDim2.new(0, 10, 0, 50)
	Container.BackgroundTransparency = 1
	Container.Parent = MainFrame

	local TimerFrame = Instance.new("Frame")
	TimerFrame.Size = UDim2.new(1, 0, 0, 110)
	TimerFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	TimerFrame.BorderSizePixel = 0
	TimerFrame.Parent = Container
	rounded(TimerFrame,10)

	local TimerLabel = Instance.new("TextLabel")
	TimerLabel.Size = UDim2.new(1, -20, 0, 30)
	TimerLabel.Position = UDim2.new(0, 10, 0, 5)
	TimerLabel.BackgroundTransparency = 1
	TimerLabel.Font = Enum.Font.SourceSansBold
	TimerLabel.Text = "⏱️ Prochain spawn (Chubby):"
	TimerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TimerLabel.TextSize = 18
	TimerLabel.TextXAlignment = Enum.TextXAlignment.Left
	TimerLabel.Parent = TimerFrame

	local CountdownLabel = Instance.new("TextLabel")
	CountdownLabel.Size = UDim2.new(0.5, -10, 0, 40)
	CountdownLabel.Position = UDim2.new(0, 10, 0, 40)
	CountdownLabel.BackgroundTransparency = 1
	CountdownLabel.Font = Enum.Font.SourceSans
	CountdownLabel.Text = "01:49"
	CountdownLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
	CountdownLabel.TextSize = 30
	CountdownLabel.TextXAlignment = Enum.TextXAlignment.Center
	CountdownLabel.Parent = TimerFrame

	-- ne pas redéclarer 'local' ici, on réutilise la var externe
	acornCountLabel = Instance.new("TextLabel")
	acornCountLabel.Size = UDim2.new(0.5, -10, 0, 40)
	acornCountLabel.Position = UDim2.new(0.5, 0, 0, 40)
	acornCountLabel.BackgroundTransparency = 1
	acornCountLabel.Font = Enum.Font.SourceSansBold
	acornCountLabel.Text = "🥜 Collected: 0"
	acornCountLabel.TextColor3 = Color3.fromRGB(180, 230, 180)
	acornCountLabel.TextSize = 20
	acornCountLabel.TextXAlignment = Enum.TextXAlignment.Center
	acornCountLabel.Parent = TimerFrame

	local StatusFrame = Instance.new("Frame")
	StatusFrame.Size = UDim2.new(1, 0, 0, 60)
	StatusFrame.Position = UDim2.new(0, 0, 0, 120)
	StatusFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	StatusFrame.BorderSizePixel = 0
	StatusFrame.Parent = Container
	rounded(StatusFrame,10)

	local StatusLabel = Instance.new("TextLabel")
	StatusLabel.Size = UDim2.new(1, -20, 1, -10)
	StatusLabel.Position = UDim2.new(0, 10, 0, 5)
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.Font = Enum.Font.SourceSans
	StatusLabel.Text = "📍 Status: En veille..."
	StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	StatusLabel.TextSize = 16
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
	StatusLabel.TextWrapped = true
	StatusLabel.Parent = StatusFrame

	-- Boutons
	local AutoCollectBtn = Instance.new("TextButton")
	AutoCollectBtn.Size = UDim2.new(1, 0, 0, 45)
	AutoCollectBtn.Position = UDim2.new(0, 0, 0, 190)
	AutoCollectBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	AutoCollectBtn.BorderSizePixel = 0
	AutoCollectBtn.Text = "🤖 Auto Collect: OFF"
	AutoCollectBtn.Font = Enum.Font.SourceSansBold
	AutoCollectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoCollectBtn.TextSize = 18
	AutoCollectBtn.Parent = Container
	rounded(AutoCollectBtn,10)

	local AutoTPBtn = Instance.new("TextButton")
	AutoTPBtn.Size = UDim2.new(1, 0, 0, 45)
	AutoTPBtn.Position = UDim2.new(0, 0, 0, 245)
	AutoTPBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 60)
	AutoTPBtn.BorderSizePixel = 0
	AutoTPBtn.Text = "⚡ Auto TP on Detect: ON"
	AutoTPBtn.Font = Enum.Font.SourceSansBold
	AutoTPBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoTPBtn.TextSize = 18
	AutoTPBtn.Parent = Container
	rounded(AutoTPBtn,10)

	local AutoHarvestBtn = Instance.new("TextButton")
	AutoHarvestBtn.Size = UDim2.new(1, 0, 0, 45)
	AutoHarvestBtn.Position = UDim2.new(0, 0, 0, 300)
	AutoHarvestBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 60)
	AutoHarvestBtn.BorderSizePixel = 0
	AutoHarvestBtn.Text = "🌾 Auto Harvest (plantes): OFF"
	AutoHarvestBtn.Font = Enum.Font.SourceSansBold
	AutoHarvestBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoHarvestBtn.TextSize = 18
	AutoHarvestBtn.Parent = Container
	rounded(AutoHarvestBtn,10)

	local FeverBadge = Instance.new("TextLabel")
	FeverBadge.Size = UDim2.new(1, 0, 0, 35)
	FeverBadge.Position = UDim2.new(0, 0, 0, 355)
	FeverBadge.BackgroundColor3 = Color3.fromRGB(45, 40, 20)
	FeverBadge.BorderSizePixel = 0
	FeverBadge.Font = Enum.Font.SourceSansBold
	FeverBadge.Text = "🔥 Nutty Fever: OFF (109s)"
	FeverBadge.TextColor3 = Color3.fromRGB(255, 180, 80)
	FeverBadge.TextSize = 18
	FeverBadge.Parent = Container
	rounded(FeverBadge,10)

	local HintCtrl = Instance.new("TextLabel")
	HintCtrl.Size = UDim2.new(1, 0, 0, 30)
	HintCtrl.Position = UDim2.new(0, 0, 0, 395)
	HintCtrl.BackgroundTransparency = 1
	HintCtrl.Font = Enum.Font.SourceSansItalic
	HintCtrl.Text = "💡 Maintiens ⌘ Command (Mac) ou Ctrl et clique pour te TP"
	HintCtrl.TextColor3 = Color3.fromRGB(160, 200, 255)
	HintCtrl.TextSize = 16
	HintCtrl.Parent = Container

	-- Scanner
	local ScanRow = Instance.new("Frame")
	ScanRow.Size = UDim2.new(1, 0, 0, 45)
	ScanRow.Position = UDim2.new(0, 0, 0, 435)
	ScanRow.BackgroundTransparency = 1
	ScanRow.Parent = Container

	local ScanNowBtn = Instance.new("TextButton")
	ScanNowBtn.Size = UDim2.new(0.48, -4, 1, 0)
	ScanNowBtn.Position = UDim2.new(0, 0, 0, 0)
	ScanNowBtn.BackgroundColor3 = Color3.fromRGB(90, 140, 210)
	ScanNowBtn.TextColor3 = Color3.fromRGB(255,255,255)
	ScanNowBtn.Text = "🔎 Scan Now (Y 1–4)"
	ScanNowBtn.Font = Enum.Font.SourceSansBold
	ScanNowBtn.TextSize = 16
	ScanNowBtn.Parent = ScanRow
	rounded(ScanNowBtn,10)

	local AutoScanBtn = Instance.new("TextButton")
	AutoScanBtn.Size = UDim2.new(0.52, 0, 1, 0)
	AutoScanBtn.Position = UDim2.new(0.48, 4, 0, 0)
	AutoScanBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 140)
	AutoScanBtn.TextColor3 = Color3.fromRGB(255,255,255)
	AutoScanBtn.Text = "📡 Auto-scan: OFF (29s)"
	AutoScanBtn.Font = Enum.Font.SourceSansBold
	AutoScanBtn.TextSize = 16
	AutoScanBtn.Parent = ScanRow
	rounded(AutoScanBtn,10)

	-- Close → cache l'UI
	CloseButton.MouseButton1Click:Connect(function()
		acornGui.Enabled = false
	end)

	-- Toggles
	AutoCollectBtn.MouseButton1Click:Connect(function()
		ac.autoCollecting = not ac.autoCollecting
		AutoCollectBtn.BackgroundColor3 = ac.autoCollecting and Color3.fromRGB(60, 200, 60) or Color3.fromRGB(200, 60, 60)
		AutoCollectBtn.Text = ac.autoCollecting and "🤖 Auto Collect: ON" or "🤖 Auto Collect: OFF"
	end)

	AutoTPBtn.MouseButton1Click:Connect(function()
		ac.autoTPOnDetect = not ac.autoTPOnDetect
		AutoTPBtn.BackgroundColor3 = ac.autoTPOnDetect and Color3.fromRGB(60, 200, 60) or Color3.fromRGB(200, 60, 60)
		AutoTPBtn.Text = ac.autoTPOnDetect and "⚡ Auto TP on Detect: ON" or "⚡ Auto TP on Detect: OFF"
	end)

	AutoHarvestBtn.MouseButton1Click:Connect(function()
		ac.autoHarvestEnabled = not ac.autoHarvestEnabled
		AutoHarvestBtn.BackgroundColor3 = ac.autoHarvestEnabled and Color3.fromRGB(100, 180, 80) or Color3.fromRGB(200, 120, 60)
		AutoHarvestBtn.Text = ac.autoHarvestEnabled and ("🌾 Auto Harvest (plantes): ON  • r="..tostring(ac.config.autoHarvestRadius)) or "🌾 Auto Harvest (plantes): OFF"
	end)

	ScanNowBtn.MouseButton1Click:Connect(function()
		local ok, part = scanMapAcorn()
		if ok and part then
			StarterGui:SetCore("SendNotification", {
				Title = "🔎 Scan",
				Text = ("Acorn trouvé à Y=%.1f"):format(part.Position.Y),
				Duration = 2
			})
			selectCurrentAcorn(part)
			if ac.autoTPOnDetect then
				task.spawn(function() ac._collectAcorn(part) end)
			end
		else
			StarterGui:SetCore("SendNotification", { Title = "🔎 Scan", Text = "Aucun acorn (Y 1–4) trouvé.", Duration = 2 })
		end
	end)

	AutoScanBtn.MouseButton1Click:Connect(function()
		ac.scanAutoEnabled = not ac.scanAutoEnabled
		AutoScanBtn.BackgroundColor3 = ac.scanAutoEnabled and Color3.fromRGB(110, 150, 90) or Color3.fromRGB(80, 100, 140)
		AutoScanBtn.Text = ac.scanAutoEnabled and "📡 Auto-scan: ON (29s)" or "📡 Auto-scan: OFF (29s)"
	end)

	-- Drag
	makeDraggable(MainFrame, Header)

	-- Timer / status updater
	task.spawn(function()
		while acornGui and acornGui.Parent do
			if not acornGui.Enabled then task.wait(0.2) else
				local timeLeft = ac.nextSpawnTime - tick()
				if timeLeft > 0 then
					CountdownLabel.TextColor3 = ac.isNuttyFever and Color3.fromRGB(255, 200, 120) or Color3.fromRGB(255, 200, 0)
					CountdownLabel.Text = fmtTime(timeLeft)
				else
					CountdownLabel.Text = "SPAWN ?"
				end
				if ac.currentAcorn and ac.currentAcorn.Parent then
					StatusLabel.Text = "📍 Status: ACORN détecté — "..(ac.isNuttyFever and "priorité sol + Y±"..ac.config.feverYTolerance or "mode normal")
					StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
				else
					StatusLabel.Text = "📍 Status: En veille / évènementiel"
					StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
				end
				FeverBadge.Text = (ac.isNuttyFever and "🔥 Nutty Fever: ON (30s)") or "🔥 Nutty Fever: OFF (109s)"
				FeverBadge.BackgroundColor3 = ac.isNuttyFever and Color3.fromRGB(70, 45, 20) or Color3.fromRGB(45, 40, 20)
				task.wait(0.1)
			end
		end
	end)

	-- CTRL/⌘ + Clic pour TP/Collect
	do
		local mouse = player:GetMouse()
		local function metaOrCtrlDown()
			return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
		end
		mouse.Button1Down:Connect(function()
			if metaOrCtrlDown() then
				local target = mouse.Target
				if target then
					if target.Name == ac.config.acornName then
						ac._collectAcorn(target)
					else
						local hit = mouse.Hit
						if hit then
							local p = hit.Position + Vector3.new(0,3,0)
							if ac.config.instantTp then hardSetPosition(p) else teleportTween(p) end
						end
					end
				end
			end
		end)
	end

	-- Auto-scan worker (29s)
	task.spawn(function()
		while acornGui and acornGui.Parent do
			if ac.scanAutoEnabled then
				local ok, part = scanMapAcorn()
				if ok and part and (not ac.currentAcorn or ac.currentAcorn ~= part) then
					selectCurrentAcorn(part)
					if ac.autoTPOnDetect then task.spawn(function() ac._collectAcorn(part) end) end
				end
				for i=1, ac.scanPeriod do
					if not ac.scanAutoEnabled then break end
					task.wait(1)
				end
			else
				task.wait(0.2)
			end
		end
	end)

	-- Fever flags externes (si existants)
	local function tryBindExternalFeverFlags()
		local function consider(inst)
			if inst:IsA("BoolValue") then
				local nm = string.lower(inst.Name)
				if nm:find("nutty") or nm:find("fever") then
					inst.Changed:Connect(function()
						local active = inst.Value == true
						if ac.isNuttyFever ~= active then
							ac.isNuttyFever = active
							ac.feverLastSeenAt = tick()
							ac.nextSpawnTime = tick() + (ac.isNuttyFever and ac.config.feverSpawnInterval or ac.config.normalSpawnInterval)
						end
					end)
				end
			end
		end
		for _, container in ipairs({ReplicatedStorage, Workspace}) do
			for _, inst in ipairs(container:GetDescendants()) do consider(inst) end
			container.DescendantAdded:Connect(consider)
		end
	end

	task.spawn(function()
		while true do
			if ac.isNuttyFever and (tick() - ac.feverLastSeenAt) > ac.FEVER_TIMEOUT then
				ac.isNuttyFever = false
			end
			task.wait(2)
		end
	end)

	initialScan()
	tryBindExternalFeverFlags()
	setCount(ac.acornCollected)

	StarterGui:SetCore("SendNotification", {
		Title = "🌰 Acorn Collector",
		Text = "TP dur + retour XYZ • Timer 1:49 (Chubby) • ⌘/Ctrl+clic TP • Auto-scan 29s (Y 1–4)",
		Duration = 4
	})

	applyAutoScale(acornGui, {MainFrame})
	return acornGui
end

-- Toggle UI Acorn depuis le Player Tuner
local function toggleAcornUI()
	local gui = ensureAcornGui()
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		local frame = gui:FindFirstChildWhichIsA("Frame")
		if frame then clampOnScreen(frame) end
	end
end
openAcornBtn.MouseButton1Click:Connect(toggleAcornUI)

-- === Scales + ready msg ===
msg("✅ Saad helper pack chargé + 🌰 Acorn Collector v2.6 (auto-harvest v2.4 • ignore Mushroom • ⌘/Ctrl+clic • auto-scan 29s • Y 1–4).", Color3.fromRGB(170,230,255))
