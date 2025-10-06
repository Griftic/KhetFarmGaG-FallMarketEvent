-- Saad helper pack v3.0-LITE+AUTO — Player Tuner + Gear Panel + Acorn Collector
-- ⚙️ Modifs demandées :
-- 1) ✅ Auto-buy activé d’office au lancement (sans UI) : Seeds, Gear, Event EVO, Eggs (périodes: 2:30 / 2:30 / 0:55 / 7:30)
-- 2) ✅ Bouton de réduction (minimize) pour : Player Tuner, Gear Panel, Acorn Collector
-- 3) ✅ LITE optimisé mobile : no notifs écran, no son, pas d’ESP/pulsations, refresh allégé
-- 4) ✅ Auto-harvest (plantes) ignore Mushroom + stop si backpack plein + TP discret caméra figée

--==================================================
--=================  SETTINGS  =====================
--==================================================
local LIGHT_MODE = true                 -- 🟢 LITE activé (mobile-friendly)
local VERBOSE_LOG = false               -- logs chat réduits
local UI_REFRESH = 0.6                  -- intervalle MAJ UI (s)
local COORDS_REFRESH = 1.0              -- coords HUD (s)
local AUTO_SCAN_PERIOD = 33             -- auto-scan (sec) (29 -> 33 allégé)
local AUTO_HARVEST_TICK = 0.20          -- v2.4 mais allégé (0.12 -> 0.20)
local DISABLE_SOUNDS = true             -- pas de sons
local DISABLE_ESP = true                -- pas d'ESP
local GC_SWEEP_EVERY = 60               -- collecte mémoire périodique (sec)

-- Auto-buy (sans UI) — activé d’office
local AUTO_PERIOD_SEEDS = 150           -- 2:30
local AUTO_PERIOD_GEAR  = 150           -- 2:30
local AUTO_PERIOD_EVENT = 55            -- 0:55
local AUTO_PERIOD_EGGS  = 450           -- 7:30
local AUTO_BUY_SEEDS = true
local AUTO_BUY_GEAR  = true
local AUTO_BUY_EVENT = true
local AUTO_BUY_EGGS  = true

--==================================================
--=================  SERVICES  =====================
--==================================================
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

--==================================================
--=================  UTILS  ========================
--==================================================
local function msg(text, color)
	if not VERBOSE_LOG then return end
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color or Color3.fromRGB(200,200,255),
			Font = Enum.Font.Gotham,
			FontSize = Enum.FontSize.Size12,
		})
	end)
end

local function safeWait(path, timeout)
	local node=ReplicatedStorage
	for _,name in ipairs(path) do
		node = node:WaitForChild(name, timeout)
		if not node then return nil end
	end
	return node
end

local function getHRP()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec + 0.5))
	local m = math.floor(sec/60)
	local s = sec % 60
	return string.format("%d:%02d",m,s)
end

-- UI helpers
local function rounded(obj, r)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, r or 8)
	ui.Parent = obj
	return ui
end

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

local function makeButton(parent, text, size, pos, bg)
	local b = Instance.new("TextButton")
	b.Size = size; b.Position = pos
	b.BackgroundColor3 = bg or Color3.fromRGB(70,100,180)
	b.TextColor3 = Color3.fromRGB(255,255,255)
	b.Text = text; b.Font = Enum.Font.GothamBold; b.TextSize = 13
	b.Parent = parent; rounded(b,8)
	return b
end
local function makeLabel(parent, text, size, pos, color, bold)
	local l = Instance.new("TextLabel"); l.Size=size; l.Position=pos
	l.BackgroundTransparency = 1; l.TextColor3 = color or Color3.fromRGB(220,230,255)
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = bold and 16 or 12; l.Text = text; l.TextXAlignment=Enum.TextXAlignment.Left
	l.Parent = parent; return l
end
local function makeFrame(parent, size, pos, bg)
	local f=Instance.new("Frame"); f.Size=size; f.Position=pos; f.BackgroundColor3=bg or Color3.fromRGB(36,36,36); f.BorderSizePixel=0; f.Parent=parent; rounded(f,10); return f
end
local function attachMinimize(frame, titleBar, contentFrame, minBtn, fullSize, collapsedHeight)
	local isMin = false
	local collapsedSize = UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, collapsedHeight)
	local function setMin(v)
		isMin = v
		if isMin then
			contentFrame.Visible = false
			frame.Size = collapsedSize
			minBtn.Text = "▣"
		else
			frame.Size = fullSize
			contentFrame.Visible = true
			minBtn.Text = "—"
		end
	end
	minBtn.MouseButton1Click:Connect(function() setMin(not isMin) end)
	titleBar.InputBegan:Connect(function(i)
		-- double-tap/two quick taps on mobile could also minimize; keep simple: single tap on btn only
	end)
	setMin(false)
	return setMin
end

--==================================================
--=============  PLAYER TUNER (LITE)  ==============
--==================================================
local DEFAULT_GRAVITY, DEFAULT_JUMPPOWER, DEFAULT_WALKSPEED = 196.2, 50, 16
local currentSpeed, currentGravity, currentJump = 18, 147.1, 60
local isNoclipping, noclipConnection = false, nil

local function applySpeed(v)   currentSpeed=v;  local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed=v end end
local function applyGravity(v) currentGravity=v; workspace.Gravity=v end
local function applyJump(v)    currentJump=v;   local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid"); if h then h.JumpPower=v end end
local function resetDefaults() applySpeed(DEFAULT_WALKSPEED); applyGravity(DEFAULT_GRAVITY); applyJump(DEFAULT_JUMPPOWER); msg("↩️ Reset (16/196.2/50).") end

-- Caméra gel/restore super sûre
local camFreezeBusy = false
local function withFrozenCamera(fn)
	local cam = workspace.CurrentCamera
	if not cam then local ok=pcall(fn); if not ok then end; return end
	if camFreezeBusy then local ok=pcall(fn); if not ok then end; return end
	camFreezeBusy = true
	local origType, origSubject, origCF = cam.CameraType, cam.CameraSubject, cam.CFrame
	pcall(function() cam.CameraType = Enum.CameraType.Scriptable; cam.CFrame = origCF end)
	local ok = pcall(fn)
	if not ok then end
	pcall(function() cam.CameraSubject = origSubject end)
	pcall(function() cam.CFrame       = origCF      end)
	pcall(function() cam.CameraType    = origType    end)
	camFreezeBusy = false
end

-- Anti-AFK simple
local ANTI_AFK_PERIOD, ANTI_AFK_DURATION = 60, 0.35
local antiAFKEnabled = false
player.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0,0))
	end)
end)
task.spawn(function()
	while true do
		task.wait(ANTI_AFK_PERIOD)
		if antiAFKEnabled then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:Move(Vector3.new(0, 0, -1), true)
				task.wait(ANTI_AFK_DURATION)
				hum:Move(Vector3.new(0, 0, 0), true)
			end
		end
	end
end)

--==================================================
--=================  GEAR / REMOTES  ===============
--==================================================
local GEAR_SHOP_POS = Vector3.new(-288, 2, -15)
local SELL_NPC_POS  = Vector3.new(87, 3, 0)

local function teleportTo(p)
	local hrp=getHRP(); if not hrp then msg("❌ HRP introuvable."); return end
	hrp.CFrame=CFrame.new(p)
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
local function getBuyPetEggRemote() local r=safeWait({"GameEvents","BuyPetEgg"},2) return (r and r:IsA("RemoteEvent")) and r or nil end
local function getSubmitChipmunkRemote() local r=safeWait({"GameEvents","SubmitChipmunkFruit"},2) return (r and r:IsA("RemoteEvent")) and r or nil end

local SEED_TIER = "Tier 1"
local SEEDS = { "Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon","Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom","Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone","Elder Strawberry","Romanesco","Crimson Thorn" }
local GEARS = { "Watering Can","Trading Ticket","Trowel","Recall Wrench","Basic Sprinkler","Advanced Sprinkler","Medium Toy","Medium Treat","Godly Sprinkler","Magnifying Glass","Master Sprinkler","Cleaning Spray","Cleansing Pet Shard","Favorite Tool","Harvest Tool","Friendship Pot","Grandmaster Sprinkler","Level Up Lollipop" }
local EGGS  = { "Common Egg","Uncommon Egg","Rare Egg","Legendary Egg","Mythical Egg","Bug Egg","Jungle Egg" }
local MAX_TRIES_PER_SEED, MAX_TRIES_PER_GEAR = 20, 5

local function buyAllSeedsWorker()
	local r = getBuySeedRemote(); if not r then msg("❌ BuySeedStock introuvable."); return end
	for _, seed in ipairs(SEEDS) do
		for _=1,MAX_TRIES_PER_SEED do pcall(function() r:FireServer(SEED_TIER, seed) end) task.wait(0.05) end
	end
end
local function buyAllGearWorker()
	local r = getBuyGearRemote(); if not r then msg("❌ BuyGearStock introuvable."); return end
	for _, g in ipairs(GEARS) do
		for _=1,MAX_TRIES_PER_GEAR do pcall(function() r:FireServer(g) end) task.wait(0.06) end
	end
end
local EVO_LIST = { "Evo Beetroot I","Evo Blueberry I","Evo Pumpkin I","Evo Mushroom I" }
local function buyEventEvosWorker()
	local r = getBuyEventRemote(); if not r then msg("❌ BuyEventShopStock introuvable."); return end
	for _, name in ipairs(EVO_LIST) do pcall(function() r:FireServer(name, 1) end); task.wait(0.06) end
end
local function buyAllEggsWorker()
	local r = getBuyPetEggRemote(); if not r then msg("❌ BuyPetEgg introuvable."); return end
	for _, egg in ipairs(EGGS) do pcall(function() r:FireServer(egg) end); task.wait(0.06) end
end
local function submitAllChipmunk() local r = getSubmitChipmunkRemote(); if r then pcall(function() r:FireServer("All") end) end end

--==================================================
--=================  MAIN UI  ======================
--==================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SaadLite"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

local function makeDraggable(frame, handle)
	frame.Active=true; frame.Selectable=true; handle.Active=true; handle.Selectable=true
	local dragging=false; local dragStart; local startPos; local dragInputId
	local function update(input)
		local delta=input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	local function begin(input)
		dragging=true; dragStart=input.Position; startPos=frame.Position; dragInputId=input
		input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false; clampOnScreen(frame) end end)
	end
	handle.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then begin(i) end
	end)
	handle.InputChanged:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then if dragging then update(i) end end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i == dragInputId or i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then update(i) end
	end)
end

-- Player Tuner panel (compact) + minimize FIX
local mainFullSize = UDim2.fromOffset(300, 260)
local main = makeFrame(screenGui, mainFullSize, UDim2.fromScale(0.02, 0.04), Color3.fromRGB(36,36,36))
local title = makeFrame(main, UDim2.new(1,0,0,32), UDim2.fromOffset(0,0), Color3.fromRGB(28,28,28))
makeLabel(title, "🎚️ PLAYER TUNER (LITE)", UDim2.new(1,-90,1,0), UDim2.new(0,10,0,0), Color3.fromRGB(255,255,255), true)
local closeBtn = makeButton(title, "✕", UDim2.fromOffset(26,26), UDim2.new(1,-34,0,3), Color3.fromRGB(255,72,72))
local minimizeBtn = makeButton(title, "—", UDim2.fromOffset(26,26), UDim2.new(1,-66,0,3), Color3.fromRGB(110,110,110))

local content = makeFrame(main, UDim2.new(1,-20,1,-42), UDim2.new(0,10,0,38), Color3.fromRGB(36,36,36)); content.BackgroundTransparency=1
makeDraggable(main, title)
attachMinimize(main, title, content, minimizeBtn, mainFullSize, 32) -- ✅ FIX minimize Player Tuner

-- sliders simplifiés
local function simpleSlider(y, labelText, minValue, maxValue, step, initialValue, onChange)
	local frame = makeFrame(content, UDim2.new(1,0,0,52), UDim2.new(0,0,0,y), Color3.fromRGB(36,36,36)); frame.BackgroundTransparency=1
	local label = makeLabel(frame, labelText, UDim2.new(1,-90,0,18), UDim2.new(0,0,0,0), Color3.fromRGB(255,255,255), true)
	local value = makeLabel(frame, "", UDim2.new(0,80,0,18), UDim2.new(1,-80,0,0), Color3.fromRGB(180,220,255), false); value.TextXAlignment=Enum.TextXAlignment.Right
	local track = makeFrame(frame, UDim2.new(1,0,0,10), UDim2.new(0,0,0,26), Color3.fromRGB(64,64,64)); rounded(track,6)
	local fill  = makeFrame(track, UDim2.new(0,0,1,0), UDim2.new(0,0,0,0), Color3.fromRGB(0,170,255)); rounded(fill,6)
	local knob  = makeFrame(track, UDim2.fromOffset(16,16), UDim2.new(0,0,0.5,-8), Color3.fromRGB(230,230,230)); rounded(knob,16)

	local function clamp(v,a,b) return math.max(a, math.min(b, v)) end
	local function snap(v) return math.floor((v - minValue)/step + 0.5)*step + minValue end
	local function setVisual(pct, val) fill.Size=UDim2.new(pct,0,1,0); knob.Position=UDim2.new(pct,-8,0.5,-8); value.Text=tostring(math.floor(val*10+0.5)/10) end
	local function setValue(val, fire) val=clamp(snap(val),minValue,maxValue); local pct=(val-minValue)/(maxValue-minValue); setVisual(pct,val); if fire then onChange(val) end end

	local dragging=false
	local function updateFromX(x) local ap,as=track.AbsolutePosition.X, track.AbsoluteSize.X; if as<=0 then return end; local pct = math.clamp((x-ap)/as,0,1); local v=minValue+pct*(maxValue-minValue); setValue(v,true) end
	track.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			dragging=true; updateFromX(i.Position.X)
			i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false; clampOnScreen(main) end end)
		end
	end)
	knob.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			dragging=true; updateFromX(i.Position.X)
			i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false; clampOnScreen(main) end end)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
			updateFromX(i.Position.X)
		end
	end)
	setValue(initialValue,true)
	return { set=function(v) setValue(v,true) end }
end

local speedSlider   = simpleSlider(0,   "Walk Speed (16–58)",   16, 58,   1,   currentSpeed,   applySpeed)
local gravitySlider = simpleSlider(58,  "Gravity (37.5–196.2)", 37.5,196.2, 0.5, currentGravity, applyGravity)
local jumpSlider    = simpleSlider(116, "Jump Power (45–82.5)", 45, 82.5, 0.5, currentJump,    applyJump)

local rowBtn = makeFrame(content, UDim2.new(1,0,0,36), UDim2.new(0,0,0,174), Color3.fromRGB(36,36,36)); rowBtn.BackgroundTransparency=1
local resetBtn  = makeButton(rowBtn, "↩️ Reset", UDim2.new(0.33,-6,1,0), UDim2.new(0,0,0,0), Color3.fromRGB(70,100,180))
local noclipBtn = makeButton(rowBtn, "🚫 NO CLIP: OFF", UDim2.new(0.33,-6,1,0), UDim2.new(0.335,6,0,0), Color3.fromRGB(220,60,60))
local gearBtn   = makeButton(rowBtn, "🛒 Gear Panel", UDim2.new(0.33,0,1,0), UDim2.new(0.67,6,0,0), Color3.fromRGB(60,180,60))

local antiRow   = makeFrame(content, UDim2.new(1,0,0,36), UDim2.new(0,0,0,212), Color3.fromRGB(36,36,36)); antiRow.BackgroundTransparency=1
local antiAFKBtn= makeButton(antiRow, "🛡️ Anti-AFK: OFF", UDim2.new(0.6,-6,1,0), UDim2.new(0,0,0,0), Color3.fromRGB(100,130,100))
local openAcorn = makeButton(antiRow, "🌰 ACORN COLLECTOR", UDim2.new(0.4,0,1,0), UDim2.new(0.6,6,0,0), Color3.fromRGB(200,160,60))

resetBtn.MouseButton1Click:Connect(function()
	resetDefaults()
	speedSlider.set(DEFAULT_WALKSPEED); gravitySlider.set(DEFAULT_GRAVITY); jumpSlider.set(DEFAULT_JUMPPOWER)
end)
noclipBtn.MouseButton1Click:Connect(function()
	isNoclipping = not isNoclipping
	if isNoclipping then
		noclipBtn.BackgroundColor3=Color3.fromRGB(60,220,60); noclipBtn.Text="✅ NO CLIP: ON"
		if noclipConnection then noclipConnection:Disconnect() end
		noclipConnection = RunService.Stepped:Connect(function()
			local ch=player.Character; if not ch then return end
			for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
		end)
	else
		noclipBtn.BackgroundColor3=Color3.fromRGB(220,60,60); noclipBtn.Text="🚫 NO CLIP: OFF"
		if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end
		local ch=player.Character; if ch then for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
	end
end)
closeBtn.MouseButton1Click:Connect(function()
	if isNoclipping then isNoclipping=false; if noclipConnection then noclipConnection:Disconnect(); end end
	if screenGui then screenGui:Destroy() end
end)
antiAFKBtn.MouseButton1Click:Connect(function()
	antiAFKEnabled = not antiAFKEnabled
	antiAFKBtn.Text = antiAFKEnabled and "🛡️ Anti-AFK: ON" or "🛡️ Anti-AFK: OFF"
	antiAFKBtn.BackgroundColor3 = antiAFKEnabled and Color3.fromRGB(80,140,90) or Color3.fromRGB(100,130,100)
end)

--==================================================
--=================  GEAR PANEL  ===================
--==================================================
local gearGui = Instance.new("ScreenGui"); gearGui.Name="GearPanelLite"; gearGui.ResetOnSpawn=false; gearGui.IgnoreGuiInset=false; gearGui.Parent=playerGui
local gearFullSize = UDim2.fromOffset(250, 280)
local gearFrame = makeFrame(gearGui, gearFullSize, UDim2.fromScale(0.25, 0.05), Color3.fromRGB(50,50,80))
local gtitle = makeFrame(gearFrame, UDim2.new(1,0,0,28), UDim2.new(0,0,0,0), Color3.fromRGB(40,40,70))
makeLabel(gtitle, "🛒 GEAR SHOP (L)", UDim2.new(1,-70,1,0), UDim2.new(0,10,0,0), Color3.fromRGB(255,255,255), true)
local gclose = makeButton(gtitle, "✕", UDim2.fromOffset(20,20), UDim2.new(1,-26,0,4), Color3.fromRGB(255,72,72))
local gmin   = makeButton(gtitle, "—", UDim2.fromOffset(20,20), UDim2.new(1,-50,0,4), Color3.fromRGB(110,110,110)) -- ✅ minimize Gear
local gbody  = makeFrame(gearFrame, UDim2.new(1,-12,1,-38), UDim2.new(0,6,0,34), Color3.fromRGB(50,50,80)); gbody.BackgroundTransparency=1
makeDraggable(gearFrame, gtitle)
attachMinimize(gearFrame, gtitle, gbody, gmin, gearFullSize, 28) -- ✅

local tpGear  = makeButton(gbody, "📍 TP GEAR SHOP",      UDim2.new(1,0,0,28), UDim2.new(0,0,0,0),   Color3.fromRGB(60,180,60))
local sellBtn = makeButton(gbody, "🧺 SELL INVENTORY",    UDim2.new(1,0,0,28), UDim2.new(0,0,0,32),  Color3.fromRGB(200,130,90))
local chipBtn = makeButton(gbody, "🍁 SUBMIT ALL (Chip)", UDim2.new(1,0,0,28), UDim2.new(0,0,0,64),  Color3.fromRGB(90,140,210))
local seedsBtn= makeButton(gbody, "🌱 BUY ALL SEEDS",     UDim2.new(1,0,0,28), UDim2.new(0,0,0,96),  Color3.fromRGB(100,170,100))
local gearBtn2= makeButton(gbody, "🧰 BUY ALL GEAR",      UDim2.new(1,0,0,28), UDim2.new(0,0,0,128), Color3.fromRGB(120,140,200))
local evoBtn  = makeButton(gbody, "🍁 BUY EVO (x1)",      UDim2.new(1,0,0,28), UDim2.new(0,0,0,160), Color3.fromRGB(200,140,90))
local eggsBtn = makeButton(gbody, "🥚 BUY EGGS",          UDim2.new(1,0,0,28), UDim2.new(0,0,0,192), Color3.fromRGB(150,120,200))
local coordsLabel = makeLabel(gbody, "Position: (…)",     UDim2.new(1,0,0,18), UDim2.new(0,0,0,224), Color3.fromRGB(200,200,255), false)

gclose.MouseButton1Click:Connect(function() gearFrame.Visible=false end)
gearBtn.MouseButton1Click:Connect(function() gearFrame.Visible=not gearFrame.Visible; if gearFrame.Visible then clampOnScreen(gearFrame) end end)
tpGear.MouseButton1Click:Connect(function() teleportTo(GEAR_SHOP_POS) end)
sellBtn.MouseButton1Click:Connect(function()
	local r = getSellInventoryRemote(); if not r then return end
	local hrp = getHRP(); if not hrp then return end
	local back = hrp.CFrame
	withFrozenCamera(function()
		teleportTo(SELL_NPC_POS); task.wait(0.20); r:FireServer(); task.wait(0.05); hrp.CFrame = back
	end)
end)
chipBtn.MouseButton1Click:Connect(submitAllChipmunk)
seedsBtn.MouseButton1Click:Connect(buyAllSeedsWorker)
gearBtn2.MouseButton1Click:Connect(buyAllGearWorker)
evoBtn.MouseButton1Click:Connect(buyEventEvosWorker)
eggsBtn.MouseButton1Click:Connect(buyAllEggsWorker)

-- Live coords (ralenti)
task.spawn(function()
	local acc=0
	RunService.RenderStepped:Connect(function(dt)
		acc+=dt; if acc < COORDS_REFRESH then return end; acc=0
		local hrp = getHRP()
		if hrp then
			coordsLabel.Text = string.format("Position: (%d,%d,%d)", math.floor(hrp.Position.X), math.floor(hrp.Position.Y), math.floor(hrp.Position.Z))
		else
			coordsLabel.Text = "Position: (N/A)"
		end
	end)
end)

--==================================================
--============  ACORN COLLECTOR (LITE)  ============
--==================================================
local acornGui -- créé à la demande
local function ensureAcornGui()
	if acornGui and acornGui.Parent then return acornGui end

	local ac = {}
	ac.config = {
		acornName = "Acorn",
		normalSpawnInterval = 109, feverSpawnInterval = 30, acornDuration = 30,
		feverGroundDistance = 6, groundIgnoreHeight = 20, feverYTolerance = 2,
		instantTp = false, tpSpeed = 120, returnToStartAfterCollect = true,
		freezeCameraOnTP = true,
		stopHarvestWhenBackpackFull = true,
		autoHarvestRadius = 25,
		autoHarvestTick = AUTO_HARVEST_TICK,
		autoHarvestUsePrompts = true,
		promptHoldDuration = 0.25,
		plantWhitelist = { "plant","harvest","crop","fruit","vegetable","tree","bush","flower","pick","collect" },
		plantExclude  = { "mushroom" },
		promptTextWhitelist = { "harvest","pick","collect","récolter","cueillir" },
		promptBlacklist = { "fence","save","slot","skin","shop","buy","sell","chest","settings","rename","open","claim","craft","upgrade" },
		soundAlert = not DISABLE_SOUNDS,
		screenAlert = not LIGHT_MODE,
	}

	ac.nextSpawnTime = tick() + ac.config.normalSpawnInterval
	ac.currentAcorn = nil
	ac.autoTPOnDetect = true
	ac.autoHarvestEnabled = false
	ac.isNuttyFever = false
	ac.feverLastSeenAt = 0
	ac.acornCollected = 0
	ac.scanAutoEnabled = false
	ac.scanPeriod = AUTO_SCAN_PERIOD

	-- Backpack auto-detect
	ac.backpackCountValue, ac.backpackCapValue = nil, nil
	local function isVal(x) return x and (x:IsA("IntValue") or x:IsA("NumberValue")) end
	local COUNT_NAMES = { "count","current","amount","qty","quantity","items","inventory","backpack","bag","held","stored" }
	local CAP_NAMES   = { "capacity","cap","max","maxcapacity","maxamount","limit","maxitems","maxinventory","maxbackpack" }
	local function nameMatchAny(nm, list) nm=string.lower(tostring(nm or "")); for _,k in ipairs(list) do if nm==k or nm:find(k) then return true end end return false end
	local function tryAutoBindBackpack()
		if ac.backpackCountValue and ac.backpackCapValue then return true end
		local roots = { player, player:FindFirstChild("PlayerGui"), player:FindFirstChild("PlayerScripts"), ReplicatedStorage, Workspace }
		local bestScore, bestPair = -1, nil
		for _, root in ipairs(roots) do
			if root then
				for _, v in ipairs(root:GetDescendants()) do
					if isVal(v) then
						if nameMatchAny(v.Name, COUNT_NAMES) or nameMatchAny(v.Name, CAP_NAMES) then
							local parent=v.Parent or root
							local count = parent and parent:FindFirstChildWhichIsA("IntValue", true)
							local cap   = parent and parent:FindFirstChildWhichIsA("NumberValue", true)
							if count and cap and nameMatchAny(count.Name, COUNT_NAMES) and nameMatchAny(cap.Name, CAP_NAMES) then
								local c, m = tonumber(count.Value) or -1, tonumber(cap.Value) or -1
								if c>=0 and m>0 and c<=m then local sc=(m-c); if sc>bestScore then bestScore=sc; bestPair={count,cap} end end
							end
						end
					end
				end
			end
		end
		if bestPair then ac.backpackCountValue, ac.backpackCapValue = bestPair[1], bestPair[2]; return true end
		return false
	end
	local function isBackpackFull()
		if not (ac.backpackCountValue and ac.backpackCapValue) then tryAutoBindBackpack() end
		local c = ac.backpackCountValue and tonumber(ac.backpackCountValue.Value) or nil
		local m = ac.backpackCapValue   and tonumber(ac.backpackCapValue.Value)   or nil
		return (c and m and c>=m) and true or false, c, m
	end

	-- TP helpers
	local function hardSetPosition(position)
		local hrp=getHRP(); if not hrp then return end
		pcall(function() hrp.AssemblyLinearVelocity=Vector3.new(); hrp.AssemblyAngularVelocity=Vector3.new() end)
		local ch=player.Character
		if ch and typeof(ch.PivotTo)=="function" then ch:PivotTo(CFrame.new(position)) else hrp.CFrame=CFrame.new(position) end
	end
	local function teleportTween(position)
		local hrp=getHRP(); if not hrp then return end
		if ac.config.instantTp then hardSetPosition(position); return end
		local startPos = hrp.Position
		local distance = (position - startPos).Magnitude
		local travelTime = math.max(distance / ac.config.tpSpeed, 0.05)
		TweenService:Create(hrp, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(position)}):Play()
	end

	-- Choix du meilleur acorn (Fever = priorité Y±tolérance + sol)
	local function isYAlignedWithPlayer(acornPart)
		local hrp = getHRP(); if not hrp or not acornPart then return false end
		return math.abs(acornPart.Position.Y - hrp.Position.Y) <= ac.config.feverYTolerance
	end
	local function isGrounded(acorn)
		if not acorn or not acorn.Parent then return false end
		local origin=acorn.Position; local direction=Vector3.new(0,-200,0)
		local params=RaycastParams.new(); params.FilterDescendantsInstances={acorn}; params.FilterType=Enum.RaycastFilterType.Exclude; params.IgnoreWater=false
		local result=Workspace:Raycast(origin,direction,params)
		if result then local dist=(origin-result.Position).Magnitude; return dist <= ac.config.feverGroundDistance else return false end
	end
	local function bestAcornCandidate(a,b)
		if not a then return b end; if not b then return a end
		local hrp = getHRP()
		local da = hrp and (a.Position - hrp.Position).Magnitude or math.huge
		local db = hrp and (b.Position - hrp.Position).Magnitude or math.huge
		if ac.isNuttyFever then
			local aY, bY = isYAlignedWithPlayer(a), isYAlignedWithPlayer(b)
			if aY ~= bY then return aY and a or b end
			local ag, bg = isGrounded(a), isGrounded(b)
			if ag ~= bg then return ag and a or b end
		end
		return (da <= db) and a or b
	end
	local function isAcornBasePart(inst)
		if not inst then return nil end
		if inst.Name ~= ac.config.acornName then return nil end
		if inst:IsA("BasePart") then return inst end
		if inst:IsA("Model") then return inst:FindFirstChildWhichIsA("BasePart") end
		return nil
	end

	-- Sélection + compteur (sans ESP en LITE)
	local acornCountLabel
	local function setCount(n) if acornCountLabel then acornCountLabel.Text=("🥜 Collected: %d"):format(n or 0) end end
	local function selectCurrentAcorn(candidate)
		if not candidate or not candidate.Parent then return end
		if not ac.currentAcorn or not ac.currentAcorn.Parent then
			ac.currentAcorn = candidate; return
		end
		local best = bestAcornCandidate(ac.currentAcorn, candidate)
		ac.currentAcorn = best
	end
	local function onAcornAppeared(bp)
		ac.isNuttyFever = true; ac.feverLastSeenAt = tick()
		ac.nextSpawnTime = tick() + (ac.isNuttyFever and ac.config.feverSpawnInterval or ac.config.normalSpawnInterval)
		if ac.isNuttyFever and not isYAlignedWithPlayer(bp) then return end
		if ac.isNuttyFever then local grounded = isGrounded(bp); if (not grounded) and (bp.Position.Y > ac.config.groundIgnoreHeight) then return end end
		selectCurrentAcorn(bp)
		if ac.autoTPOnDetect and ac.currentAcorn then
			task.spawn(function()
				local hrp=getHRP(); if not hrp then return end
				local originalPos=hrp.Position
				local function doCollect()
					local targetPos = ac.currentAcorn.Position + Vector3.new(0,3,0)
					hrp.AssemblyLinearVelocity = Vector3.new(); hrp.AssemblyAngularVelocity = Vector3.new()
					hrp.CFrame = CFrame.new(targetPos); task.wait(0.10)
					pcall(function()
						local prompt = ac.currentAcorn:FindFirstChildOfClass("ProximityPrompt"); if prompt then pcall(fireproximityprompt, prompt) end
						local click  = ac.currentAcorn:FindFirstChildOfClass("ClickDetector");   if click  then pcall(fireclickdetector,  click)  end
					end)
					task.wait(0.15)
					if ac.config.returnToStartAfterCollect then hrp.CFrame = CFrame.new(originalPos) end
				end
				if ac.config.freezeCameraOnTP then withFrozenCamera(doCollect) else doCollect() end
			end)
		end
	end
	local function onAcornDisappeared(inst)
		if ac.currentAcorn and (inst == ac.currentAcorn or ac.currentAcorn:IsDescendantOf(inst)) then
			ac.currentAcorn = nil; ac.acornCollected += 1; setCount(ac.acornCollected)
		end
	end

	-- Hooks spawn/despawn
	Workspace.DescendantAdded:Connect(function(inst) local bp=isAcornBasePart(inst); if bp then onAcornAppeared(bp) end end)
	Workspace.DescendantRemoving:Connect(onAcornDisappeared)

	-- Scan (light)
	local function scanMapAcorn()
		local best=nil
		for _, obj in ipairs(Workspace:GetDescendants()) do
			local bp = isAcornBasePart(obj)
			if bp then
				local y = bp.Position.Y
				if y >= 1 and y <= 4 then best = bestAcornCandidate(best, bp); break end
			end
		end
		if not best then
			for _, obj in ipairs(Workspace:GetDescendants()) do
				local bp = isAcornBasePart(obj)
				if bp then best = bestAcornCandidate(best, bp); break end
			end
		end
		if best then onAcornAppeared(best); return true, best end
		return false, nil
	end

	-- AUTO HARVEST (v2.4 light)
	local function lower(s) if typeof(s)=="string" then return string.lower(s) end return "" end
	local function containsAny(s, list) for _,kw in ipairs(list) do if s:find(kw) then return true end end return false end
	local function isPlantPrompt(prompt)
		if not prompt or not prompt.Parent then return false end
		local action = lower(prompt.ActionText); local object = lower(prompt.ObjectText)
		if containsAny(action, ac.config.plantExclude) or containsAny(object, ac.config.plantExclude) then return false end
		for _,kw in ipairs(ac.config.promptTextWhitelist) do
			if action:find(kw) or object:find(kw) then
				local node = prompt.Parent; local steps=0
				while node and steps<4 do
					local nm=lower(node.Name)
					if containsAny(nm, ac.config.plantExclude) then return false end
					steps+=1; node=node.Parent
				end
				return true
			end
		end
		local node=prompt; local steps=0
		while node and steps<4 do
			local nm = lower(node.Name)
			for _,bad in ipairs(ac.config.promptBlacklist) do if nm:find(bad) then return false end end
			if containsAny(nm, ac.config.plantExclude) then return false end
			for _,good in ipairs(ac.config.plantWhitelist) do if nm:find(good) then return true end end
			node = node.Parent; steps+=1
		end
		return false
	end

	local function getNearbyPlantPrompts(radius)
		local prompts = {}
		local hrp=getHRP(); if not hrp then return prompts end
		local params = OverlapParams.new(); params.FilterDescendantsInstances={player.Character}; params.FilterType=Enum.RaycastFilterType.Blacklist
		local parts = {}
		pcall(function() parts = Workspace:GetPartBoundsInRadius(hrp.Position, radius, params) end)
		local seen={}
		for _, part in ipairs(parts) do
			if part and part.Parent and not seen[part.Parent] then
				seen[part.Parent]=true
				for _, child in ipairs(part.Parent:GetDescendants()) do
					if child:IsA("ProximityPrompt") and isPlantPrompt(child) then table.insert(prompts, child) end
				end
			end
		end
		return prompts
	end

	task.spawn(function()
		while true do
			if ac.autoHarvestEnabled then
				if ac.config.stopHarvestWhenBackpackFull then
					local full,c,_ = isBackpackFull()
					if full then
						ac.autoHarvestEnabled=false
					else
						local prompts = ac.config.autoHarvestUsePrompts and getNearbyPlantPrompts(ac.config.autoHarvestRadius) or {}
						for _, prompt in ipairs(prompts) do
							pcall(fireproximityprompt, prompt)
							if prompt.HoldDuration and prompt.HoldDuration > 0 then
								task.wait(math.min(prompt.HoldDuration, ac.config.promptHoldDuration))
								pcall(fireproximityprompt, prompt)
							end
						end
					end
				end
				task.wait(ac.config.autoHarvestTick)
			else
				task.wait(0.25)
			end
		end
	end)

	-- UI (compact) + ✅ Minimize
	acornGui = Instance.new("ScreenGui"); acornGui.Name="AcornLite"; acornGui.ResetOnSpawn=false; acornGui.IgnoreGuiInset=false; acornGui.Parent=playerGui
	local acFull = UDim2.new(0, 320, 0, 420)
	local Main = makeFrame(acornGui, acFull, UDim2.new(1,-330,0.5,-210), Color3.fromRGB(25,25,30))
	local Header = makeFrame(Main, UDim2.new(1,0,0,40), UDim2.new(0,0,0,0), Color3.fromRGB(30,30,38))
	makeLabel(Header, "🌰 Acorn Collector (L)", UDim2.new(1,-90,1,0), UDim2.new(0,12,0,0), Color3.fromRGB(255,200,0), true)
	local Close = makeButton(Header, "✖", UDim2.fromOffset(28,28), UDim2.new(1,-34,0.5,-14), Color3.fromRGB(220,50,50))
	local Min   = makeButton(Header, "—", UDim2.fromOffset(28,28), UDim2.new(1,-66,0.5,-14), Color3.fromRGB(110,110,110)) -- ✅ minimize Acorn
	local Body  = makeFrame(Main, UDim2.new(1,-16,1,-52), UDim2.new(0,8,0,46), Color3.fromRGB(25,25,30)); Body.BackgroundTransparency=1
	makeDraggable(Main, Header)
	attachMinimize(Main, Header, Body, Min, acFull, 40) -- ✅

	local TimerBox = makeFrame(Body, UDim2.new(1,0,0,90), UDim2.new(0,0,0,0), Color3.fromRGB(35,35,42))
	makeLabel(TimerBox, "⏱️ Prochain spawn (Chubby):", UDim2.new(1,-20,0,24), UDim2.new(0,10,0,6), Color3.fromRGB(255,255,255), true)
	local Countdown = makeLabel(TimerBox, "01:49", UDim2.new(0.5,-10,0,40), UDim2.new(0,8,0,40), Color3.fromRGB(255,200,0), false); Countdown.TextXAlignment=Enum.TextXAlignment.Center; Countdown.TextSize=28
	local acornCountLabel = makeLabel(TimerBox, "🥜 Collected: 0", UDim2.new(0.5,-10,0,40), UDim2.new(0.5,2,0,40), Color3.fromRGB(180,230,180), true); acornCountLabel.TextXAlignment=Enum.TextXAlignment.Center; acornCountLabel.TextSize=18

	local StatusBox = makeFrame(Body, UDim2.new(1,0,0,50), UDim2.new(0,0,0,96), Color3.fromRGB(35,35,42))
	local Status = makeLabel(StatusBox, "📍 Status: En veille…", UDim2.new(1,-20,1,-8), UDim2.new(0,10,0,4), Color3.fromRGB(200,200,200), false)

	local AutoCollectBtn = makeButton(Body, "🤖 Auto Collect: ON", UDim2.new(1,0,0,40), UDim2.new(0,0,0,154), Color3.fromRGB(60,200,60))
	local AutoTPBtn      = makeButton(Body, "⚡ Auto TP on Detect: ON", UDim2.new(1,0,0,40), UDim2.new(0,0,0,198), Color3.fromRGB(60,200,60))
	local AutoHarvestBtn = makeButton(Body, "🌾 Auto Harvest (plantes): OFF", UDim2.new(1,0,0,40), UDim2.new(0,0,0,242), Color3.fromRGB(200,120,60))

	local ScanRow   = makeFrame(Body, UDim2.new(1,0,0,40), UDim2.new(0,0,0,286), Color3.fromRGB(25,25,30)); ScanRow.BackgroundTransparency=1
	local ScanNow   = makeButton(ScanRow, "🔎 Scan Now (Y 1–4)", UDim2.new(0.48,-4,1,0), UDim2.new(0,0,0,0), Color3.fromRGB(90,140,210))
	local AutoScan  = makeButton(ScanRow, "📡 Auto-scan: OFF ("..tostring(ac.scanPeriod).."s)", UDim2.new(0.52,0,1,0), UDim2.new(0.48,4,0,0), Color3.fromRGB(80,100,140))

	Close.MouseButton1Click:Connect(function() acornGui.Enabled=false end)
	AutoCollectBtn.MouseButton1Click:Connect(function() -- en LITE : alias de TP on detect
		ac.autoTPOnDetect = not ac.autoTPOnDetect
		AutoCollectBtn.BackgroundColor3 = ac.autoTPOnDetect and Color3.fromRGB(60,200,60) or Color3.fromRGB(200,60,60)
		AutoCollectBtn.Text = ac.autoTPOnDetect and "🤖 Auto Collect: ON" or "🤖 Auto Collect: OFF"
		AutoTPBtn.BackgroundColor3 = AutoCollectBtn.BackgroundColor3
		AutoTPBtn.Text = ac.autoTPOnDetect and "⚡ Auto TP on Detect: ON" or "⚡ Auto TP on Detect: OFF"
	end)
	AutoTPBtn.MouseButton1Click:Connect(function()
		ac.autoTPOnDetect = not ac.autoTPOnDetect
		AutoTPBtn.BackgroundColor3 = ac.autoTPOnDetect and Color3.fromRGB(60,200,60) or Color3.fromRGB(200,60,60)
		AutoTPBtn.Text = ac.autoTPOnDetect and "⚡ Auto TP on Detect: ON" or "⚡ Auto TP on Detect: OFF"
		AutoCollectBtn.BackgroundColor3 = AutoTPBtn.BackgroundColor3
		AutoCollectBtn.Text = AutoTPBtn.Text:gsub("⚡","🤖"):gsub("on Detect: ","")
	end)
	AutoHarvestBtn.MouseButton1Click:Connect(function()
		ac.autoHarvestEnabled = not ac.autoHarvestEnabled
		AutoHarvestBtn.BackgroundColor3 = ac.autoHarvestEnabled and Color3.fromRGB(100,180,80) or Color3.fromRGB(200,120,60)
		AutoHarvestBtn.Text = ac.autoHarvestEnabled and ("🌾 Auto Harvest (plantes): ON  • r="..tostring(ac.config.autoHarvestRadius)) or "🌾 Auto Harvest (plantes): OFF"
	end)
	ScanNow.MouseButton1Click:Connect(function() scanMapAcorn() end)
	AutoScan.MouseButton1Click:Connect(function()
		ac.scanAutoEnabled = not ac.scanAutoEnabled
		AutoScan.BackgroundColor3 = ac.scanAutoEnabled and Color3.fromRGB(110,150,90) or Color3.fromRGB(80,100,140)
		AutoScan.Text = ac.scanAutoEnabled and ("📡 Auto-scan: ON ("..tostring(ac.scanPeriod).."s)") or ("📡 Auto-scan: OFF ("..tostring(ac.scanPeriod).."s)")
	end)

	-- Tick UI allégé
	task.spawn(function()
		while acornGui and acornGui.Parent do
			if not acornGui.Enabled then task.wait(0.3) else
				local timeLeft = ac.nextSpawnTime - tick()
				Countdown.Text = (timeLeft>0) and fmtTime(timeLeft) or "SPAWN ?"
				if ac.currentAcorn and ac.currentAcorn.Parent then
					Status.Text = "📍 Status: ACORN détecté" .. (ac.isNuttyFever and " (Fever)" or "")
					Status.TextColor3 = Color3.fromRGB(100,255,100)
				else
					Status.Text = "📍 Status: En veille / évènementiel"
					Status.TextColor3 = Color3.fromRGB(200,200,200)
				end
				task.wait(UI_REFRESH)
			end
		end
	end)

	-- Auto-scan worker (light)
	task.spawn(function()
		while acornGui and acornGui.Parent do
			if ac.scanAutoEnabled then
				script.Disabled = false
				scanMapAcorn()
				for i=1, ac.scanPeriod do if not ac.scanAutoEnabled then break end task.wait(1) end
			else
				task.wait(0.4)
			end
		end
	end)

	return acornGui
end

local function toggleAcornUI()
	local gui = ensureAcornGui()
	if not gui then return end
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		local frame = gui:FindFirstChildWhichIsA("Frame")
		if frame then clampOnScreen(frame) end
	end
end
openAcorn.MouseButton1Click:Connect(toggleAcornUI)

--==================================================
--==========  AUTO-BUY BACKGROUND (ON)  ============
--==================================================
local seedsTimer, gearTimer, eventTimer, eggsTimer =
	AUTO_PERIOD_SEEDS, AUTO_PERIOD_GEAR, AUTO_PERIOD_EVENT, AUTO_PERIOD_EGGS

task.spawn(function()
	while true do
		task.wait(1)
		if AUTO_BUY_SEEDS then seedsTimer = seedsTimer - 1 else seedsTimer = AUTO_PERIOD_SEEDS end
		if AUTO_BUY_GEAR  then gearTimer  = gearTimer  - 1 else gearTimer  = AUTO_PERIOD_GEAR  end
		if AUTO_BUY_EVENT then eventTimer = eventTimer - 1 else eventTimer = AUTO_PERIOD_EVENT end
		if AUTO_BUY_EGGS  then eggsTimer  = eggsTimer  - 1 else eggsTimer  = AUTO_PERIOD_EGGS  end

		if AUTO_BUY_SEEDS and seedsTimer<=0 then task.spawn(buyAllSeedsWorker); seedsTimer=AUTO_PERIOD_SEEDS end
		if AUTO_BUY_GEAR  and gearTimer<=0  then task.spawn(buyAllGearWorker);  gearTimer =AUTO_PERIOD_GEAR  end
		if AUTO_BUY_EVENT and eventTimer<=0 then task.spawn(buyEventEvosWorker); eventTimer=AUTO_PERIOD_EVENT end
		if AUTO_BUY_EGGS  and eggsTimer<=0  then task.spawn(buyAllEggsWorker);  eggsTimer =AUTO_PERIOD_EGGS  end
	end
end)

--==================================================
--===========  RESPAWN / GC / INIT  ================
--==================================================
applySpeed(currentSpeed); applyGravity(currentGravity); applyJump(currentJump)
player.CharacterAdded:Connect(function(char)
	char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = currentSpeed; hum.JumpPower = currentJump end
	workspace.Gravity = currentGravity
	if isNoclipping then task.wait(0.2); if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end; isNoclipping=false; end
end)

-- GC périodique
task.spawn(function()
	while true do
		task.wait(GC_SWEEP_EVERY)
		pcall(function() collectgarbage("collect") end)
	end
end)

-- Petits bindings Gear
gearBtn.MouseButton1Click:Connect(function()
	gearFrame.Visible = not gearFrame.Visible
	if gearFrame.Visible then clampOnScreen(gearFrame) end
end)
