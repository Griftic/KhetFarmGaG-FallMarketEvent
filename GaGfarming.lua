-- Saad helper pack v2.9 — Sliders + Reset + Noclip + Gear Panel + Anti-AFK
-- (TP, Sell (TP+retour+caméra figée), Buy All Seeds/Gear + Autos, BUY EVO (auto 1:50), BUY EGGS (auto 15:00))
-- +++++ EVO MANAGER (compact + bubble) +++++
-- Submit (Held) Evo I/II/III (ignore "seed", exclut "IV") + Plant EVO Seeds (comptage backpack, retries ≥5) à ta position (multi-passes auto)
-- UI: Récap des seeds non plantées (hors IV) — liste cochable retirée, tous I/II/III inclus
-- Minimize (—/▣) + Alt+M ; Toggle EVO: Alt+E + bouton « EVO »
-- >>> Nouveau: Réduction en bulle déplaçable (bouton ● + Alt+B), clic = ré-ouvrir
-- >>> Compact UI: statut placé juste sous le récap, hauteur totale réduite
-- >>> Fix: positions en scale (UDim2) + clamp écran + pcall UIStroke + Active sur labels
-- >>> Anti-AFK: nudge mouvement périodique + fallback VirtualUser Idled
-- >>> Planting delay: +20% (PLANT_DELAY_FACTOR = 1.2)
-- >>> Bouton ARROSAGE 4 FOIS dans EVO MANAGER
-- >>> Drag mobile: support Touch (UI déplaçable au doigt)

--// Services
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local StarterGui         = game:GetService("StarterGui")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Workspace          = game:GetService("Workspace")
local VirtualUser        = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player             = Players.LocalPlayer
local playerGui          = player:WaitForChild("PlayerGui")

--// Consts
local DEFAULT_GRAVITY, DEFAULT_JUMPPOWER, DEFAULT_WALKSPEED = 196.2, 50, 16
local GEAR_SHOP_POS     = Vector3.new(-288, 2, -15)
local SELL_NPC_POS      = Vector3.new(87,   3,   0)

-- Anti-AFK
local ANTI_AFK_PERIOD   = 60
local ANTI_AFK_DURATION = 0.35

-- Planting delay +20%
local PLANT_DELAY_FACTOR = 1.2
local function pwait(t) task.wait(t * PLANT_DELAY_FACTOR) end

-- Seeds/Gears definitions
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

-- Ecran clamp pour frames (évite off-screen)
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
local function findPlantRemote()
	local r=safeWait({"GameEvents","Plant_RE"},2)
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
		if autoBuyEvent and eventTimer<=0 then buyEventEvosWorker();eventTimer=AUTO_PERIOD_EVENT end
		if autoBuyEggs  and eggsTimer<=0  then buyAllEggsWorker();  eggsTimer =AUTO_PERIOD_EGGS  end
		updateTimerLabels()
	end
end)

-- Draggable (Mouse + Touch)
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

-- Helper to avoid CornerRadius typos
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
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(320, 290)
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
title.Size = UDim2.new(1, -150, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255,255,255)
title.Text = "🎚️ PLAYER TUNER"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local quickEvoBtn = Instance.new("TextButton")
quickEvoBtn.Size = UDim2.fromOffset(42, 26)
quickEvoBtn.Position = UDim2.new(1, -88, 0, 5)
quickEvoBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 150)
quickEvoBtn.TextColor3 = Color3.fromRGB(255,255,255)
quickEvoBtn.Text = "EVO"
quickEvoBtn.Font = Enum.Font.GothamBold
quickEvoBtn.TextSize = 12
quickEvoBtn.Parent = titleBar
rounded(quickEvoBtn, 0)

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
local fullSize = UDim2.fromOffset(320, 290)
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
antiAFKHint.Text = "Simule 'Z' / mouvement léger toutes 60s"
antiAFKHint.Parent = miscRow

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
gearFrame.Size = UDim2.fromOffset(260, 450)
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
gearTitle.Size = UDim2.new(1, -120, 1, 0)
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

local evoManagerBtn = Instance.new("TextButton")
evoManagerBtn.Size = UDim2.fromOffset(130, 20)
evoManagerBtn.Position = UDim2.new(1, -160, 0, 4)
evoManagerBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 150)
evoManagerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
evoManagerBtn.Text = "🔧 EVO MANAGER"
evoManagerBtn.Font = Enum.Font.GothamBold
evoManagerBtn.TextSize = 11
evoManagerBtn.Parent = gearTitleBar
rounded(evoManagerBtn,0)

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
seedsTimerLabel.Text = "⏳ Next: 5:00"
seedsTimerLabel.Font = Enum.Font.Gotham
seedsTimerLabel.TextSize = 12
seedsTimerLabel.Parent = seedsRow
rounded(seedsTimerLabel,8)

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
gearTimerLabel.Text = "⏳ Next: 5:00"
gearTimerLabel.Font = Enum.Font.Gotham
gearTimerLabel.TextSize = 12
gearTimerLabel.Parent = gearRow
rounded(gearTimerLabel,8)

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
eventTimerLabel.Text = "⏳ Next: 1:50"
eventTimerLabel.Font = Enum.Font.Gotham
eventTimerLabel.TextSize = 12
eventTimerLabel.Parent = eventRow
rounded(eventTimerLabel,8)

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
eggsTimerLabel.Text = "⏳ Next: 15:00"
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

-- ======== EVO MANAGER (COMPACT + BUBBLE) ========
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
player.CharacterAdded:Connect(function(char) character = char; humanoid = char:WaitForChild("Humanoid") end)
local backpack = player:WaitForChild("Backpack")

-- Remotes (Submit + Water)
local Tiered  = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("TieredPlants")
local Submit  = Tiered:WaitForChild("Submit")
local Water_RE = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("Water_RE")

-- Équiper arrosoir (&) puis arroser 4× au sol proche
local function equiperArrosoir()
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Ampersand, false, game); task.wait(0.1)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Ampersand, false, game)
	end)
	task.wait(0.5)
end
local function getGroundPosition()
	local c = player.Character; if not c then return nil end
	local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
	local origin = hrp.Position
	local result = workspace:Raycast(origin, Vector3.new(0,-10,0), (function()
		local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Blacklist; p.FilterDescendantsInstances = {c}; return p
	end)())
	local y = result and result.Position.Y + 0.001 or 0.13552188873291016
	return Vector3.new(hrp.Position.X, y, hrp.Position.Z)
end
local function arroser4Fois()
	equiperArrosoir()
	task.wait(0.2)
	local pos = getGroundPosition(); if not pos then return end
	for i=1,4 do pcall(function() Water_RE:FireServer(pos) end); if i<4 then task.wait(0.3) end end
end

-- Filtrage et parsing EVO
local function isEvoSeedTool(obj)
	return obj and obj:IsA("Tool") and obj.Name:lower():find("evo",1,true) and obj.Name:lower():find("seed",1,true)
end
local function canonicalEvoName(toolName)
	local s = tostring(toolName or "")
	s = s:gsub("%b[]",""):gsub("%b()","")
	s = s:gsub("[Ss][Ee][Ee][Dd][Ss]?", "")
	s = s:gsub("%s+[xX]%d+%s*$","")
	s = s:gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
	local base, roman = s:match("(Evo%s+[%w%s]+)%s+([IVXivx]+)")
	if base and roman then return (base:gsub("%s+"," ") .. " " .. roman:upper()):gsub("%s+"," ") end
	local head = s:match("^(Evo%s+.+)$")
	return (head or s):gsub("%s+"," ")
end
local function isEvoIVByName(evoName)
	if not evoName then return false end
	local s = tostring(evoName):upper()
	s = s:gsub("%b[]",""):gsub("%b()","")
	s = s:gsub("SEEDS?", ""):gsub("TOOL", "")
	s = s:gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
	local roman = s:match("%s([IVX]+)%s*$")
	return roman == "IV"
end
local function parseCountFromToolName(n)
	return tonumber(n:match("%(x(%d+)%)"))
	    or tonumber(n:match("%[x(%d+)%]"))
	    or tonumber(n:match("[^%d]x(%d+)%s*$"))
	    or tonumber(n:match("%s+[xX](%d+)%s*$"))
	    or 1
end

-- ✅ Nouveau critère compact: tout EVO I/II/III (pas "seed" tenu en main, pas IV) est éligible
local function isEligibleEvoToolName(toolName)
	local lname = toolName:lower()
	if lname:find("seed", 1, true) then return false end
	local canon = canonicalEvoName(toolName)
	if isEvoIVByName(canon) then return false end
	local r = canon:match("%s([IVX]+)%s*$")
	return (r == "I" or r == "II" or r == "III") and canon:lower():find("evo",1,true) ~= nil
end

-- Comptages / groupes
local function isIVTool(obj)
	return obj and obj:IsA("Tool") and isEvoSeedTool(obj) and isEvoIVByName(canonicalEvoName(obj.Name))
end
local function dropIVFromHands()
	local held = character:FindFirstChildOfClass("Tool")
	if held and isIVTool(held) then pcall(function() humanoid:UnequipTools() end); pwait(0.05); return true end
	return false
end
local function countRemainingForEvo(evoName)
	if not evoName or isEvoIVByName(evoName) then return 0 end
	local total = 0
	for _,obj in ipairs(backpack:GetChildren()) do
		if isEvoSeedTool(obj) then
			local name = canonicalEvoName(obj.Name)
			if not isEvoIVByName(name) and name == evoName then
				total = total + math.max(1, parseCountFromToolName(obj.Name))
			end
		end
	end
	return total
end
local function findAnySeedToolForEvo(evoName)
	for _,obj in ipairs(backpack:GetChildren()) do
		if isEvoSeedTool(obj) then
			local name = canonicalEvoName(obj.Name)
			if not isEvoIVByName(name) and name == evoName then
				return obj
			end
		end
	end
	return nil
end
local function getGroundPositionXZ(x, z)
	local origin = Vector3.new(x, 50, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -200, 0), (function()
		local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances = {character}; return p
	end)())
	if result then return Vector3.new(x, result.Position.Y + 0.01, z) end
	return Vector3.new(x, 0.13552284240722656, z)
end
local function collectEvoGroups()
	local map = {}
	for _,obj in ipairs(backpack:GetChildren()) do
		if isEvoSeedTool(obj) then
			local evoName = canonicalEvoName(obj.Name)
			if not isEvoIVByName(evoName) then
				map[evoName] = (map[evoName] or 0) + math.max(1, parseCountFromToolName(obj.Name))
			end
		end
	end
	local groups = {}
	for evoName,count in pairs(map) do table.insert(groups, {evoName=evoName, count=count}) end
	table.sort(groups, function(a,b) return a.evoName < b.evoName end)
	return groups
end

-- Equip/Submit
local function equipTool(tool, timeout)
	timeout = timeout or 5
	if not tool or isIVTool(tool) then return false end
	dropIVFromHands()
	local t0 = os.clock()
	humanoid:EquipTool(tool)
	while os.clock() - t0 < timeout do
		local held=character:FindFirstChildOfClass("Tool")
		if held==tool then
			if isIVTool(held) then humanoid:UnequipTools(); return false end
			return true
		end
		if held and isIVTool(held) then humanoid:UnequipTools() end
		task.wait()
	end
	return false
end
local function submitHeld() local ok,err=pcall(function() Submit:FireServer("Held") end); return ok,err end

-- ====== EVO UI compact (positions resserrées) ======
local evoGui = Instance.new("ScreenGui"); evoGui.Name="EvoManager"; evoGui.ResetOnSpawn=false; evoGui.IgnoreGuiInset=true; evoGui.Parent=playerGui

-- BUBBLE UI (hidden by default)
local bubbleBtn = Instance.new("Frame")
bubbleBtn.Name = "EvoBubble"
bubbleBtn.Size = UDim2.fromOffset(46, 46)
bubbleBtn.Position = UDim2.fromScale(0.88, 0.18)
bubbleBtn.BackgroundColor3 = Color3.fromRGB(95, 85, 140)
bubbleBtn.Visible = false
bubbleBtn.Parent = evoGui
rounded(bubbleBtn, 23)
local bubbleStroke = Instance.new("UIStroke"); bubbleStroke.Thickness=1.5; bubbleStroke.Color=Color3.fromRGB(210,210,235); bubbleStroke.Parent=bubbleBtn
local bubbleGlyph = Instance.new("TextLabel"); bubbleGlyph.Size=UDim2.fromScale(1,1); bubbleGlyph.BackgroundTransparency=1; bubbleGlyph.Text="EVO"; bubbleGlyph.Font=Enum.Font.GothamBold; bubbleGlyph.TextSize=14; bubbleGlyph.TextColor3=Color3.fromRGB(255,255,255); bubbleGlyph.Parent=bubbleBtn
makeDraggable(bubbleBtn, bubbleBtn)

local evoFrame = Instance.new("Frame")
evoFrame.Size = UDim2.fromOffset(420, 310)   -- << réduit de 370 -> 310
evoFrame.Position = UDim2.fromScale(0.62, 0.04)
evoFrame.BackgroundColor3=Color3.fromRGB(24,24,28); evoFrame.BorderSizePixel=0; evoFrame.Visible=false; evoFrame.Parent=evoGui
rounded(evoFrame,10)
pcall(function() local s=Instance.new("UIStroke"); s.Thickness=1; s.Color=Color3.fromRGB(70,70,80); s.Parent=evoFrame end)
makeDraggable(evoFrame, evoFrame)
clampOnScreen(evoFrame)

local evoTitle = Instance.new("TextLabel"); evoTitle.Size=UDim2.new(1,-70,0,26); evoTitle.Position=UDim2.new(0,12,0,6)
evoTitle.BackgroundTransparency=1; evoTitle.Font=Enum.Font.GothamSemibold; evoTitle.TextSize=16; evoTitle.TextXAlignment=Enum.TextXAlignment.Left
evoTitle.Text="🔧 EVO MANAGER — Submit Held (I/II/III) + Plant"; evoTitle.TextColor3=Color3.fromRGB(235,235,245); evoTitle.Parent=evoFrame

-- Bouton "en bulle"
local toBubbleBtn = Instance.new("TextButton"); toBubbleBtn.Size=UDim2.fromOffset(26,26); toBubbleBtn.Position=UDim2.new(1,-62,0,6)
toBubbleBtn.BackgroundColor3=Color3.fromRGB(55,55,75); toBubbleBtn.Text="●"; toBubbleBtn.Font=Enum.Font.GothamBold; toBubbleBtn.TextSize=16; toBubbleBtn.TextColor3=Color3.fromRGB(235,235,245); toBubbleBtn.Parent=evoFrame
rounded(toBubbleBtn,13)

local evoClose = Instance.new("TextButton"); evoClose.Size=UDim2.fromOffset(26,26); evoClose.Position=UDim2.new(1,-34,0,6)
evoClose.BackgroundColor3=Color3.fromRGB(45,45,55); evoClose.Text="✕"; evoClose.Font=Enum.Font.GothamBold; evoClose.TextSize=14; evoClose.TextColor3=Color3.fromRGB(235,235,245); evoClose.Parent=evoFrame
rounded(evoClose,0)

-- Ligne d’actions
local actionsRow = Instance.new("Frame")
actionsRow.Size = UDim2.new(1, -24, 0, 36)
actionsRow.Position = UDim2.new(0, 12, 0, 40)
actionsRow.BackgroundColor3 = Color3.fromRGB(28,28,34)
actionsRow.Parent = evoFrame
rounded(actionsRow, 10)

local rescanBtn = Instance.new("TextButton"); rescanBtn.Size=UDim2.new(0.48,-6,1,0); rescanBtn.Position=UDim2.new(0,6,0,4)
rescanBtn.BackgroundColor3=Color3.fromRGB(80,85,100); rescanBtn.Text="Rescan Backpack"; rescanBtn.Font=Enum.Font.GothamBold; rescanBtn.TextSize=14; rescanBtn.TextColor3=Color3.fromRGB(255,255,255); rescanBtn.Parent=actionsRow; rounded(rescanBtn,8)
local submitBtn = Instance.new("TextButton"); submitBtn.Size=UDim2.new(0.48,-6,1,0); submitBtn.Position=UDim2.new(0.52,0,0,4)
submitBtn.BackgroundColor3=Color3.fromRGB(60,120,255); submitBtn.Text="Submit (Held) I/II/III"; submitBtn.Font=Enum.Font.GothamBold; submitBtn.TextSize=14; submitBtn.TextColor3=Color3.fromRGB(255,255,255); submitBtn.Parent=actionsRow; rounded(submitBtn,8)

-- Bouton ARROSAGE 4× (plus proche de la section)
local water4xBtn = Instance.new("TextButton")
water4xBtn.Size = UDim2.new(1, -24, 0, 32)
water4xBtn.Position = UDim2.new(0, 12, 0, 80)
water4xBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 200)
water4xBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
water4xBtn.Text = "💦 ARROSER 4 FOIS à ma position (sol)"
water4xBtn.Font = Enum.Font.GothamBold
water4xBtn.TextSize = 13
water4xBtn.Parent = evoFrame
rounded(water4xBtn, 8)

-- Section plantation compacte
local plantingSection = Instance.new("Frame")
plantingSection.Size = UDim2.new(1, -24, 0, 122) -- << réduit
plantingSection.Position = UDim2.new(0, 12, 0, 116)
plantingSection.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
plantingSection.Parent = evoFrame
rounded(plantingSection, 10)

local plantingTitle = Instance.new("TextLabel")
plantingTitle.Size = UDim2.new(1, -16, 0, 18)
plantingTitle.Position = UDim2.new(0, 8, 0, 6)
plantingTitle.BackgroundTransparency = 1
plantingTitle.Font = Enum.Font.GothamSemibold
plantingTitle.TextSize = 14
plantingTitle.TextXAlignment = Enum.TextXAlignment.Left
plantingTitle.TextColor3 = Color3.fromRGB(220, 220, 230)
plantingTitle.Text = "🌱 ZONE DE PLANTATION"
plantingTitle.Parent = plantingSection

local posLabel = Instance.new("TextLabel")
posLabel.Size = UDim2.new(1, -16, 0, 16)
posLabel.Position = UDim2.new(0, 8, 0, 26)
posLabel.BackgroundTransparency = 1
posLabel.Font = Enum.Font.Gotham
posLabel.TextSize = 12
posLabel.TextXAlignment = Enum.TextXAlignment.Left
posLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
posLabel.Text = "Pos: (…)"
posLabel.Parent = plantingSection

local plantingButtonsContainer = Instance.new("Frame")
plantingButtonsContainer.Size = UDim2.new(1, -16, 0, 28)
plantingButtonsContainer.Position = UDim2.new(0, 8, 0, 44)
plantingButtonsContainer.BackgroundTransparency = 1
plantingButtonsContainer.Parent = plantingSection

local plantEvoBtn = Instance.new("TextButton")
plantEvoBtn.Size = UDim2.new(0.48, -4, 1, 0)
plantEvoBtn.Position = UDim2.new(0, 0, 0, 0)
plantEvoBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 90)
plantEvoBtn.Text = "🌱 Planter EVO Seeds"
plantEvoBtn.Font = Enum.Font.GothamBold
plantEvoBtn.TextSize = 12
plantEvoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plantEvoBtn.Parent = plantingButtonsContainer
rounded(plantEvoBtn, 8)

local plantMushroomBtn = Instance.new("TextButton")
plantMushroomBtn.Size = UDim2.new(0.48, -4, 1, 0)
plantMushroomBtn.Position = UDim2.new(0.52, 4, 0, 0)
plantMushroomBtn.BackgroundColor3 = Color3.fromRGB(160, 90, 160)
plantMushroomBtn.Text = "🍄 Planter Mushroom"
plantMushroomBtn.Font = Enum.Font.GothamBold
plantMushroomBtn.TextSize = 12
plantMushroomBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plantMushroomBtn.Parent = plantingButtonsContainer
rounded(plantMushroomBtn, 8)

-- Récap (resserré)
local recapSection = Instance.new("Frame")
recapSection.Size = UDim2.new(1, -16, 0, 32)
recapSection.Position = UDim2.new(0, 8, 0, 74)
recapSection.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
recapSection.Parent = plantingSection
rounded(recapSection, 8)

local recapTitle = Instance.new("TextLabel")
recapTitle.Size = UDim2.new(1, -8, 0, 14)
recapTitle.Position = UDim2.new(0, 4, 0, 3)
recapTitle.BackgroundTransparency = 1
recapTitle.Font = Enum.Font.GothamSemibold
recapTitle.TextSize = 12
recapTitle.TextXAlignment = Enum.TextXAlignment.Left
recapTitle.TextColor3 = Color3.fromRGB(220, 220, 235)
recapTitle.Text = "📋 Récap non plantés (hors IV) :"
recapTitle.Parent = recapSection

local recapFrame = Instance.new("ScrollingFrame")
recapFrame.Size = UDim2.new(1, -8, 0, 14)
recapFrame.Position = UDim2.new(0, 4, 0, 18)
recapFrame.BackgroundTransparency = 1
recapFrame.ScrollBarThickness = 4
recapFrame.Parent = recapSection
local recapList = Instance.new("UIListLayout")
recapList.Parent = recapFrame
recapList.Padding = UDim.new(0, 2)

-- Status COLLÉ sous le récap (fini le grand espace)
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 0, 16)
statusLbl.Position = UDim2.new(0, 8, 0, 106) -- 74 + 32 (recap) = 106
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextColor3 = Color3.fromRGB(200, 200, 210)
statusLbl.Text = "Prêt."
statusLbl.Parent = plantingSection

local function flash(frame, fromRGB, toRGB)
	frame.BackgroundColor3 = Color3.fromRGB(fromRGB[1],fromRGB[2],fromRGB[3])
	TweenService:Create(frame, TweenInfo.new(0.25), {BackgroundColor3=Color3.fromRGB(toRGB[1],toRGB[2],toRGB[3])}):Play()
end

-- Helpers recap
local function clearRecap()
	for _,child in ipairs(recapFrame:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
end
local function setRecap(items)
	clearRecap()
	if #items == 0 then
		local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1, 0, 0, 14); lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextColor3 = Color3.fromRGB(200,210,220)
		lbl.Text = "Tout planté ✅"; lbl.Parent = recapFrame; return
	end
	for _,it in ipairs(items) do
		local row = Instance.new("TextLabel"); row.Size = UDim2.new(1, 0, 0, 14); row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham; row.TextSize = 12; row.TextXAlignment = Enum.TextXAlignment.Left; row.TextColor3 = Color3.fromRGB(220,200,200)
		row.Text = string.format("%s — restants: %d", it.evoName, it.count); row.Parent = recapFrame
	end
end

-- Submit (Held) pour tout EVO I/II/III (pas IV)
local function getMatchingToolsForSubmit()
	local found={}
	for _,obj in ipairs(backpack:GetChildren()) do
		if obj:IsA("Tool") and isEligibleEvoToolName(obj.Name) then
			table.insert(found,obj)
		end
	end
	return found
end
local function processAllSubmit()
	local tools=getMatchingToolsForSubmit()
	if #tools==0 then statusLbl.Text="Aucune plante Evo I/II/III (IV exclues) en main/backpack."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local success,fail=0,0
	for i,tool in ipairs(tools) do
		statusLbl.Text=("Équipe %d/%d: %s"):format(i,#tools,tool.Name)
		if equipTool(tool,5) then
			local held = character:FindFirstChildOfClass("Tool")
			if held and isIVTool(held) then
				humanoid:UnequipTools()
				fail=fail+1; statusLbl.Text=("IV détectée, submit annulé pour: %s"):format(tool.Name)
				flash(evoFrame,{80,30,30},{24,24,28})
			else
				pwait(0.05)
				local ok,err=submitHeld()
				if ok then success=success+1; statusLbl.Text=("Soumis: %s ✓"):format(tool.Name)
				else fail=fail+1; statusLbl.Text=("Échec submit %s: %s"):format(tool.Name,tostring(err)); flash(evoFrame,{80,30,30},{24,24,28}) end
				pwait(0.12)
			end
		else
			fail=fail+1; statusLbl.Text=("Impossible d'équiper: %s"):format(tool.Name); flash(evoFrame,{80,30,30},{24,24,28})
		end
	end
	statusLbl.Text=("Submit terminé — %d succès, %d échecs."):format(success,fail)
	flash(evoFrame,{30,80,30},{24,24,28})
end

-- Filet de sécurité Plant_RE
local function safePlant(remote, pos, evoName)
	if isEvoIVByName(evoName) then return false, "IV filtered" end
	return pcall(function() remote:FireServer(pos, evoName) end)
end

-- Plant EVO Seeds (multi-passes + recap)
local function processPlantEvoSeeds()
	dropIVFromHands()
	local plantRemote = findPlantRemote()
	if not plantRemote then statusLbl.Text = "Remote Plant_RE introuvable."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local hrp = getHRP(); if not hrp then statusLbl.Text = "HRP introuvable."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local pos = getGroundPositionXZ(hrp.Position.X, hrp.Position.Z)

	local initialGroups = collectEvoGroups()
	if #initialGroups == 0 then statusLbl.Text = "Aucune EVO Seed (hors IV) dans le Backpack."; setRecap({}); flash(evoFrame,{80,30,30},{24,24,28}); return end
	local totalInitial, totalPlanted, pass, maxPasses = 0, 0, 0, 6
	for _,g in ipairs(initialGroups) do totalInitial = totalInitial + g.count end

	while true do
		pass = pass + 1
		local passProgress = 0
		local groups = collectEvoGroups()
		if #groups == 0 then break end

		for idx, g in ipairs(groups) do
			local evoName = g.evoName
			local remaining = countRemainingForEvo(evoName)
			if remaining > 0 then
				statusLbl.Text = ("[Pass %d] [%d/%d] %s — à planter: %d"):format(pass, idx, #groups, evoName, remaining)

				local equipOK = false
				for _=1,4 do
					dropIVFromHands()
					local tool = findAnySeedToolForEvo(evoName)
					if not tool then break end
					if equipTool(tool, 3) then
						local heldNow = character:FindFirstChildOfClass("Tool")
						if heldNow and isIVTool(heldNow) then
							humanoid:UnequipTools()
						else equipOK = true; break end
					end
					pwait(0.08)
				end

				if not equipOK then
					statusLbl.Text = ("[Pass %d] %s — impossible d'équiper, on continue. Reste: %d"):format(pass, evoName, remaining)
				else
					local plantedThis, noProgressStreak = 0, 0
					while remaining > 0 do
						local before = remaining
						local held = character:FindFirstChildOfClass("Tool")
						if held and isIVTool(held) then
							humanoid:UnequipTools()
							local t = findAnySeedToolForEvo(evoName); if t then equipTool(t, 2) end
						end
						local okPlant, perr = safePlant(plantRemote, pos, evoName)
						if okPlant and perr == nil then
							pwait(0.10)
							local after = countRemainingForEvo(evoName)
							local delta = before - after
							if delta > 0 then
								plantedThis += delta; totalPlanted += delta; passProgress += delta; noProgressStreak = 0; remaining = after
								statusLbl.Text = ("%s — plantés: %d | reste: %d"):format(evoName, plantedThis, remaining)
							else noProgressStreak += 1; remaining = after end
						else
							if perr == "IV filtered" then statusLbl.Text = ("%s — IV détectée (sécurité), skip. Reste %d."):format(evoName, remaining); break end
							noProgressStreak += 1
						end
						dropIVFromHands()
						if noProgressStreak >= 5 then statusLbl.Text = ("%s — pas de progrès après 5 tentatives, on passe (reste %d)."):format(evoName, remaining); break end
						if remaining > 0 then
							local held2 = character:FindFirstChildOfClass("Tool")
							if (not held2) or canonicalEvoName(held2.Name) ~= evoName or isIVTool(held2) then
								local t = findAnySeedToolForEvo(evoName); if t then equipTool(t, 2) end
							end
						end
						pwait(0.08)
					end
				end
			end
		end

		if passProgress <= 0 or pass >= maxPasses then break end
	end

	local leftoverGroups, totalLeft = {}, 0
	for _,g in ipairs(collectEvoGroups()) do
		if g.count > 0 then totalLeft += g.count; table.insert(leftoverGroups, {evoName=g.evoName, count=g.count}) end
	end
	setRecap(leftoverGroups)
	statusLbl.Text = ("Plant terminé — initial: %d, plantés: %d, restants: %d."):format(totalInitial, totalPlanted, totalLeft)
	if totalLeft == 0 then flash(evoFrame,{30,80,30},{24,24,28}) else flash(evoFrame,{80,30,30},{24,24,28}) end
end

-- Planter uniquement Mushroom
local function processPlantMushroomSeeds()
	dropIVFromHands()
	local plantRemote = findPlantRemote()
	if not plantRemote then statusLbl.Text = "Remote Plant_RE introuvable."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local hrp = getHRP(); if not hrp then statusLbl.Text = "HRP introuvable."; flash(evoFrame,{80,30,30},{24,24,28}); return end
	local pos = getGroundPositionXZ(hrp.Position.X, hrp.Position.Z)

	local totalPlanted, pass, maxPasses = 0, 0, 4
	while pass < maxPasses do
		pass += 1
		local passProgress = 0
		local groups = {}
		for _, obj in ipairs(backpack:GetChildren()) do
			if isEvoSeedTool(obj) then
				local evoName = canonicalEvoName(obj.Name)
				if not isEvoIVByName(evoName) and evoName:lower():find("mushroom",1,true) then
					local cnt = countRemainingForEvo(evoName)
					if cnt > 0 then table.insert(groups, {evoName=evoName, count=cnt}) end
				end
			end
		end
		if #groups == 0 then break end

		for _, g in ipairs(groups) do
			local evoName, remaining = g.evoName, g.count
			statusLbl.Text = string.format("[Mushroom Pass %d] %s — restant: %d", pass, evoName, remaining)

			local equipOK = false
			for _ = 1, 3 do
				dropIVFromHands()
				local tool = findAnySeedToolForEvo(evoName); if not tool then break end
				if equipTool(tool, 3) then
					local heldNow = character:FindFirstChildOfClass("Tool")
					if heldNow and isIVTool(heldNow) then humanoid:UnequipTools() else equipOK = true; break end
				end
				pwait(0.08)
			end

			if equipOK then
				local plantedThis, noProgressStreak = 0, 0
				while remaining > 0 do
					local before = remaining
					local held = character:FindFirstChildOfClass("Tool")
					if held and isIVTool(held) then
						humanoid:UnequipTools()
						local t = findAnySeedToolForEvo(evoName); if t then equipTool(t, 2) end
					end
					local okPlant, perr = safePlant(plantRemote, pos, evoName)
					if okPlant and perr == nil then
						pwait(0.10)
						local after = countRemainingForEvo(evoName)
						local delta = before - after
						if delta > 0 then
							plantedThis += delta; totalPlanted += delta; passProgress += delta; noProgressStreak = 0; remaining = after
							statusLbl.Text = string.format("%s — plantés: %d | reste: %d", evoName, plantedThis, remaining)
						else noProgressStreak += 1; remaining = after end
					else
						if perr == "IV filtered" then statusLbl.Text = string.format("%s — IV détectée, skip. Reste %d.", evoName, remaining); break end
						noProgressStreak += 1
					end
					dropIVFromHands()
					if noProgressStreak >= 5 then statusLbl.Text = string.format("%s — pas de progrès après 5 tentatives.", evoName); break end
					if remaining > 0 then
						local held2 = character:FindFirstChildOfClass("Tool")
						if (not held2) or canonicalEvoName(held2.Name) ~= evoName or isIVTool(held2) then
							local t = findAnySeedToolForEvo(evoName); if t then equipTool(t, 2) end
						end
					end
					pwait(0.08)
				end
			end
		end
		if passProgress <= 0 then break end
	end
	statusLbl.Text = string.format("Plantation Mushroom terminée — plantés: %d", totalPlanted)
	flash(evoFrame, {30, 80, 30}, {24, 24, 28})
end

-- Toggle EVO
local function toggleEvo()
	evoFrame.Visible = not evoFrame.Visible
	if evoFrame.Visible then
		bubbleBtn.Visible = false
		clampOnScreen(evoFrame)
	end
end

-- Switch en bulle
local function showBubble()
	evoFrame.Visible = false
	bubbleBtn.Visible = true
	clampOnScreen(bubbleBtn)
end

-- Wire EVO MANAGER + raccourcis
evoClose.MouseButton1Click:Connect(function() evoFrame.Visible=false end)
toBubbleBtn.MouseButton1Click:Connect(showBubble)
bubbleBtn.InputBegan:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
		bubbleBtn.Visible=false
		evoFrame.Visible=true
		clampOnScreen(evoFrame)
	end
end)

quickEvoBtn.MouseButton1Click:Connect(toggleEvo)
evoManagerBtn.MouseButton1Click:Connect(toggleEvo)
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E and (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
		toggleEvo()
	elseif input.KeyCode == Enum.KeyCode.B and (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
		if evoFrame.Visible then showBubble() else bubbleBtn.Visible=false; evoFrame.Visible=true; clampOnScreen(evoFrame) end
	end
end)

-- Boutons EVO
rescanBtn.MouseButton1Click:Connect(function()
	local groups = collectEvoGroups()
	local total = 0; for _,g in ipairs(groups) do total += g.count end
	statusLbl.Text = ("Scan EVO Seeds: %d type(s), total %d (IV exclues)."):format(#groups, total)
	local leftover = {}
	for _,g in ipairs(groups) do if g.count > 0 then table.insert(leftover, {evoName=g.evoName, count=g.count}) end end
	setRecap(leftover)
	if total>0 then flash(evoFrame,{30,80,30},{24,24,28}) else flash(evoFrame,{80,30,30},{24,24,28}) end
end)
submitBtn.MouseButton1Click:Connect(function()
	submitBtn.AutoButtonColor=false; submitBtn.BackgroundColor3=Color3.fromRGB(90,90,110)
	processAllSubmit()
	submitBtn.AutoButtonColor=true; submitBtn.BackgroundColor3=Color3.fromRGB(60,120,255)
end)
plantEvoBtn.MouseButton1Click:Connect(function()
	plantEvoBtn.AutoButtonColor=false; plantEvoBtn.BackgroundColor3=Color3.fromRGB(90,110,90)
	processPlantEvoSeeds()
	plantEvoBtn.AutoButtonColor=true; plantEvoBtn.BackgroundColor3=Color3.fromRGB(50,160,90)
end)
plantMushroomBtn.MouseButton1Click:Connect(function()
	plantMushroomBtn.AutoButtonColor=false; plantMushroomBtn.BackgroundColor3=Color3.fromRGB(130,90,130)
	processPlantMushroomSeeds()
	plantMushroomBtn.AutoButtonColor=true; plantMushroomBtn.BackgroundColor3=Color3.fromRGB(160,90,160)
end)
water4xBtn.MouseButton1Click:Connect(function()
	water4xBtn.AutoButtonColor = false
	water4xBtn.BackgroundColor3 = Color3.fromRGB(90, 110, 140)
	water4xBtn.Text = "💦 ARROSAGE EN COURS..."
	local ok = pcall(arroser4Fois)
	if ok then statusLbl.Text = "✅ Arrosage 4 fois terminé !"; flash(evoFrame, {30, 80, 30}, {24, 24, 28})
	else statusLbl.Text = "❌ Erreur lors de l'arrosage"; flash(evoFrame, {80, 30, 30}, {24, 24, 28}) end
	water4xBtn.AutoButtonColor = true
	water4xBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 200)
	water4xBtn.Text = "💦 ARROSER 4 FOIS à ma position (sol)"
end)

-- Maj coord affichées en live
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
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum then hum:Move(Vector3.new(0,0,0), true) end
	end
end)
task.spawn(function()
	while true do
		task.wait(ANTI_AFK_PERIOD)
		if antiAFKEnabled then
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

msg("✅ Saad helper pack chargé — EVO MANAGER compact+bulle (Alt+E / bouton EVO, ● ou Alt+B pour bulle). I/II/III inclus (IV exclus), récap resserré, arrosage 4×, Anti-AFK Ready.", Color3.fromRGB(170,230,255))
