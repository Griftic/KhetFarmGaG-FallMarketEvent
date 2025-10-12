-- =====================================================================
-- 🧰 Saad Helper Pack — Build Complet (Player Tuner + Gear + MiniPanel)
-- - ⌘/Ctrl + Clic = TP (Mac/Windows) — sans freeze caméra
-- - UI Player Tuner (sliders + noclip + anti-AFK + Gear Panel + Mini Panel)
-- - Gear Panel: Sell, Submit Cauldron, Buy All Seeds/Gear/Eggs + Auto/60s ON
-- - Seeds inclut "Great Pumpkin" — auto-buy actif (BuySeedStock "Shop", <Seed>)
-- - Bouton: Buy "Level Up Lollipop" x50 (essaie 2 noms possibles)
-- - Mini Panel v3.2 (✕ fermer) :
--     • Auto Harvest v4 (hybride & robuste) — FIX (PromptShown + scan rayon)
--     • Auto Harvest v2.4 (prompts) -> STOP auto si backpack plein (valeurs OU popup GUI)
--       • ⚡ Remis en pleine puissance (+~50% vs original): tick 0.08, rayon 32, budget 12, fallback global ON
--       • Arrêt auto 3s après activation (conservé)
--     • Submit All (Cauldron)
--     • Event Seeds (Spooky) par plante
--     • 🎃 Submit Halloween → Jack (scan sac + mutations Spooky/Ghostly/Vamp) — *exclut eggs/gear*
-- - Raccourcis: H = toggle Auto Harvest v2.4 • J = toggle Auto Harvest v4
-- =====================================================================

--// Services
local Players                 = game:GetService("Players")
local UserInputService        = game:GetService("UserInputService")
local RunService              = game:GetService("RunService")
local StarterGui              = game:GetService("StarterGui")
local ReplicatedStorage       = game:GetService("ReplicatedStorage")
local TweenService            = game:GetService("TweenService")
local Workspace               = game:GetService("Workspace")
local VirtualUser             = game:GetService("VirtualUser")
local VirtualInputManager     = game:GetService("VirtualInputManager")
local ProximityPromptService  = game:GetService("ProximityPromptService")
local CollectionService       = game:GetService("CollectionService")
local SoundService            = game:GetService("SoundService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Consts
local DEFAULT_GRAVITY, DEFAULT_JUMPPOWER, DEFAULT_WALKSPEED = 196.2, 50, 16
local GEAR_SHOP_POS = Vector3.new(-288, 2, -15)
local SELL_NPC_POS  = Vector3.new(87, 3, 0)

-- Anti-AFK
local ANTI_AFK_PERIOD   = 60
local ANTI_AFK_DURATION = 0.35

-- Periods (auto-buy)
local AUTO_PERIOD = 60 -- ❗ 60s demandé

-- Seeds/Gears/Eggs
local SEED_TIER = "Tier 1" -- (conservé pour compat, mais achat via "Shop")
local SEEDS = {
	"Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon",
	"Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom",
	"Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone",
	"Elder Strawberry","Romanesco","Crimson Thorn",
	"Great Pumpkin" -- 🎃 demandé (shop)
}
local GEARS = {
	"Watering Can","Trading Ticket","Trowel","Recall Wrench","Basic Sprinkler","Advanced Sprinkler",
	"Medium Toy","Medium Treat","Godly Sprinkler","Magnifying Glass","Master Sprinkler",
	"Cleaning Spray","Cleansing Pet Shard","Favorite Tool","Harvest Tool","Friendship Pot",
	"Grandmaster Sprinkler","Level Up Lollipop"
}
local EGGS = { "Common Egg","Uncommon Egg","Rare Egg","Legendary Egg","Mythical Egg","Bug Egg","Jungle Egg" }

--// State
local currentSpeed, currentGravity, currentJump = 18, 147.1, 60
local isNoclipping, noclipConnection = false, nil
local autoBuySeeds, autoBuyGear, autoBuyEggs = true, true, true -- ✅ ON d’office
local seedsTimer, gearTimer, eggsTimer = AUTO_PERIOD, AUTO_PERIOD, AUTO_PERIOD

-- Anti-AFK state/threads
local antiAFKEnabled = false
local antiAFKBtn
local antiAFK_IdledConn = nil
local antiAFKThread = nil

local seedsTimerLabel, gearTimerLabel, eggsTimerLabel
local screenGui, gearGui
local gearFrame
local coordsLabel

-- =========================================================
-- ====================== Utils / Logs =====================
-- =========================================================
local function msg(text, color)
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = tostring(text),
			Color = color or Color3.fromRGB(200,230,255),
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
local function fmtTime(sec) sec=math.max(0,math.floor(sec+0.5)) local m=math.floor(sec/60) local s=sec%60 return string.format("%d:%02d",m,s) end
local function lower(s) return typeof(s)=="string" and string.lower(s) or "" end
local function norm(s) s = lower(s or "") s = s:gsub("%p"," "):gsub("%s+"," ") return s end

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

-- =========================================================
-- =================== Remotes helpers =====================
-- =========================================================
local function safeWait(path, timeout)
	local node=ReplicatedStorage
	for _,name in ipairs(path) do node=node:WaitForChild(name, timeout or 2) if not node then return nil end end
	return node
end
local function getSellInventoryRemote()  local r=safeWait({"GameEvents","Sell_Inventory"},2)                return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuySeedRemote()        local r=safeWait({"GameEvents","BuySeedStock"},2)                  return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyGearRemote()        local r=safeWait({"GameEvents","BuyGearStock"},2)                  return (r and r:IsA("RemoteEvent")) and r or nil end
local function getBuyPetEggRemote()      local r=safeWait({"GameEvents","BuyPetEgg"},2)                     return (r and r:IsA("RemoteEvent")) and r or nil end
local function getWitchesSubmitRemote()  local r=safeWait({"GameEvents","WitchesBrew","SubmitItemToCauldron"},2) return (r and r:IsA("RemoteFunction")) and r or nil end

-- =========================================================
-- =========== Backpack detector (robuste) =================
-- =========================================================
local BackpackCountValue, BackpackCapValue = nil, nil
local function isValueObject(x) return x and (x:IsA("IntValue") or x:IsA("NumberValue")) end
local COUNT_NAMES = { "count","current","amount","qty","quantity","items","inventory","backpack","bag","held","stored" }
local CAP_NAMES   = { "capacity","cap","max","maxcapacity","maxamount","limit","maxitems","maxinventory","maxbackpack" }
local function nameMatchAny(nm, list)
	nm = lower(nm)
	for _, k in ipairs(list) do if nm == k or string.find(nm, k, 1, true) then return true end end
	return false
end
local function tryAutoBindBackpack()
	BackpackCountValue, BackpackCapValue = nil, nil
	local roots = { player, player:FindFirstChild("PlayerGui"), player:FindFirstChild("PlayerScripts"), ReplicatedStorage, Workspace }
	local bestParent, bestScore = nil, -1
	local candidateMap = {}
	for _, root in ipairs(roots) do
		if root then
			for _, v in ipairs(root:GetDescendants()) do
				if isValueObject(v) then
					local par = v.Parent or root
					candidateMap[par] = candidateMap[par] or {count=nil, cap=nil}
					if nameMatchAny(v.Name, COUNT_NAMES) and not candidateMap[par].count then
						candidateMap[par].count = v
					elseif nameMatchAny(v.Name, CAP_NAMES) and not candidateMap[par].cap then
						candidateMap[par].cap = v
					end
				end
			end
		end
	end
	for par, pair in pairs(candidateMap) do
		local c, m = pair.count, pair.cap
		if isValueObject(c) and isValueObject(m) then
			local cv = tonumber(c.Value) or -1
			local mv = tonumber(m.Value) or -1
			if cv >= 0 and mv > 0 and cv <= mv and mv <= 1000000 then
				local score = (nameMatchAny(c.Name, {"backpack","inventory","bag"}) and 5 or 0)
				+ (nameMatchAny(m.Name, {"capacity","max"}) and 5 or 0)
				+ math.max(0, mv - cv)
				if score > bestScore then bestScore = score; bestParent = par end
			end
		end
	end
	if bestParent then
		BackpackCountValue = candidateMap[bestParent].count
		BackpackCapValue   = candidateMap[bestParent].cap
		return true
	end
	return false
end
local function isBackpackFull()
	if not (BackpackCountValue and BackpackCapValue) then tryAutoBindBackpack() end
	local c = BackpackCountValue and tonumber(BackpackCountValue.Value) or nil
	local m = BackpackCapValue   and tonumber(BackpackCapValue.Value)   or nil
	if c and m then return (c >= m), c, m end
	return false, c, m
end

-- =========================================================
-- =========== ⌘/Ctrl + Clic → Teleport (no-freeze) ========
-- =========================================================
local function BindMetaCtrlClickTeleport(opts)
	opts = opts or {}
	local instant  = opts.instant == true
	local tpSpeed  = opts.tpSpeed or 120
	local yOffset  = opts.yOffset or 3

	local function hardSetPosition(pos)
		local hrp = getHRP(); if not hrp then return end
		pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(); hrp.AssemblyAngularVelocity = Vector3.new() end)
		local ch = player.Character
		if ch and typeof(ch.PivotTo)=="function" then ch:PivotTo(CFrame.new(pos)) else hrp.CFrame = CFrame.new(pos) end
	end
	local function teleportTween(pos)
		local hrp = getHRP(); if not hrp then return end
		if instant then hardSetPosition(pos) return end
		local d = (pos - hrp.Position).Magnitude
		local t = math.max(d / tpSpeed, 0.05)
		TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)}):Play()
	end
	local function metaOrCtrlDown()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
	end
	local mouse = player:GetMouse()
	return mouse.Button1Down:Connect(function()
		if not metaOrCtrlDown() then return end
		local hit = mouse.Hit
		if hit then teleportTween(hit.Position + Vector3.new(0, yOffset, 0)) end
	end)
end
local _clickTPConn = BindMetaCtrlClickTeleport({ instant=false, tpSpeed=120, yOffset=3 })

-- =========================================================
-- ================== Auto-buy workers =====================
-- =========================================================
local MAX_TRIES_PER_SEED, MAX_TRIES_PER_GEAR = 5, 5

-- 🔧 PATCH: achat de graines via BuySeedStock("Shop", <Seed>) pour TOUTES les graines
local function buyAllSeedsWorker()
	local r = getBuySeedRemote(); if not r then msg("❌ BuySeedStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🌱 Achat: toutes les graines… (BuySeedStock: 'Shop', <Seed>)")
	for _, seed in ipairs(SEEDS) do
		for i=1,MAX_TRIES_PER_SEED do
			local args = { "Shop", seed }
			pcall(function() r:FireServer(unpack(args)) end)
			task.wait(0.06)
		end
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

local function buyAllEggsWorker()
	local r = getBuyPetEggRemote(); if not r then msg("❌ BuyPetEgg introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🥚 Achat: eggs…")
	for _, egg in ipairs(EGGS) do
		local ok, err = pcall(function() r:FireServer(egg) end)
		if ok then msg("✅ "..egg.." ok.", Color3.fromRGB(200,240,200)) else msg(("⚠️ %s échec: %s"):format(egg, tostring(err)), Color3.fromRGB(255,180,120)) end
		task.wait(0.06)
	end
	msg("🎉 Eggs terminé.")
end

-- Lollipop x50
local function buyLollipop50()
	local r = getBuyGearRemote(); if not r then msg("❌ BuyGearStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🍭 Achat: Level Up Lollipop x50 …")
	for i=1,50 do
		pcall(function() r:FireServer("Level Up Lollipop") end)
		pcall(function() r:FireServer("Levelup Lollipop") end)
		task.wait(0.06)
	end
	msg("✅ Lollipop x50 terminé.")
end

-- =========================================================
-- =========== 🎃 Jack-O-Lantern Submit (Auto) =============
-- =========================================================
local HALLOWEEN_FRUITS = {
	"Bloodred Mushroom","Jack O Lantern","Jack-O-Lantern","Ghoul Root","Chicken Feed",
	"Seer Vine","Poison Apple","Great Pumpkin","Banesberry"
}
local HALLOWEEN_MUT_KEYS = { "spooky","ghostly","vamp" }

local NON_FRUIT_KEYWORDS = {
	"egg","sprinkler","ticket","trowel","wrench","can","spray","shard","gear","seed","pet",
	"toy","treat","glass","pot","lollipop","favorite","friendship","recall","magnifying"
}

local function strHasAny(hay, keys)
	hay = norm(hay)
	for _,k in ipairs(keys) do
		if hay:find(norm(k), 1, true) then return true end
	end
	return false
end

local function toolIsHalloweenFruit(tool)
	if not (tool and tool:IsA("Tool")) then return false end
	local nm = norm(tool.Name)
	for _, base in ipairs(HALLOWEEN_FRUITS) do
		if nm:find(norm(base), 1, true) then return true end
	end
	return false
end

local function toolHasHalloweenMutation(tool)
	if not (tool and tool:IsA("Tool")) then return false end
	if strHasAny(tool.Name, HALLOWEEN_MUT_KEYS) then return true end
	for _, v in ipairs(tool:GetDescendants()) do
		if v:IsA("StringValue") or v:IsA("IntValue") or v:IsA("BoolValue") or v:IsA("NumberValue") then
			if strHasAny(v.Name, HALLOWEEN_MUT_KEYS) or strHasAny(tostring(v.Value), HALLOWEEN_MUT_KEYS) then
				return true
			end
		elseif v:IsA("Folder") then
			if strHasAny(v.Name, {"mut","mutation","mutations"}) then
				for _, sv in ipairs(v:GetChildren()) do
					if sv:IsA("StringValue") and strHasAny(tostring(sv.Value), HALLOWEEN_MUT_KEYS) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function toolIsNonFruit(tool)
	if not (tool and tool:IsA("Tool")) then return true end
	local nm = norm(tool.Name)
	return strHasAny(nm, NON_FRUIT_KEYWORDS)
end

local function equipTool(tool)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or not tool then return false end
	pcall(function() hum:UnequipTools() end)
	task.wait(0.05)
	local ok = pcall(function() hum:EquipTool(tool) end)
	if not ok then pcall(function() tool.Parent = player.Character end) end
	task.wait(0.12)
	return true
end

local function submitJackHeld()
	local r = safeWait({"GameEvents","SubmitJackOLanternItem"}, 2)
	if not r or not r:IsA("RemoteEvent") then
		msg("❌ SubmitJackOLanternItem introuvable.", Color3.fromRGB(255,120,120))
		return false
	end
	local ok = pcall(function() r:FireServer("Held") end)
	return ok
end

local function submitHalloweenToJackOLantern()
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 2)
	if not backpack then
		msg("🎒 Backpack introuvable.", Color3.fromRGB(255,120,120))
		return 0
	end
	local submitted = 0
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			local isH = toolIsHalloweenFruit(tool)
			local isM = toolHasHalloweenMutation(tool)
			if (isH or isM) and not toolIsNonFruit(tool) then
				equipTool(tool)
				task.wait(0.06)
				if submitJackHeld() then
					submitted += 1
					task.wait(0.12)
				end
			end
		end
	end
	if submitted > 0 then
		msg(("🎃 Jack O Lantern: %d fruit(s) soumis."):format(submitted), Color3.fromRGB(180,230,180))
	else
		msg("🎃 Jack O Lantern: rien à soumettre (uniquement fruits Halloween ou fruits à mutation Halloween).", Color3.fromRGB(230,200,180))
	end
	return submitted
end

-- =========================================================
-- ================== Timers auto-buy ON ===================
-- =========================================================
local function updateTimerLabels()
	if seedsTimerLabel then seedsTimerLabel.Text = "⏳ Next: "..fmtTime(seedsTimer) end
	if gearTimerLabel  then gearTimerLabel.Text  = "⏳ Next: "..fmtTime(gearTimer)  end
	if eggsTimerLabel  then eggsTimerLabel.Text  = "⏳ Next: "..fmtTime(eggsTimer)  end
end
task.spawn(function()
	task.defer(function()
		if autoBuySeeds then task.spawn(buyAllSeedsWorker) end
		if autoBuyGear  then task.spawn(buyAllGearWorker)  end
		if autoBuyEggs  then task.spawn(buyAllEggsWorker)  end
	end)
	while true do
		task.wait(1)
		if autoBuySeeds then seedsTimer -= 1 else seedsTimer = AUTO_PERIOD end
		if autoBuyGear  then gearTimer  -= 1 else gearTimer  = AUTO_PERIOD end
		if autoBuyEggs  then eggsTimer  -= 1 else eggsTimer  = AUTO_PERIOD end
		if autoBuySeeds and seedsTimer<=0 then buyAllSeedsWorker(); seedsTimer=AUTO_PERIOD end
		if autoBuyGear  and gearTimer<=0  then buyAllGearWorker();  gearTimer =AUTO_PERIOD end
		if autoBuyEggs  and eggsTimer<=0  then buyAllEggsWorker();  eggsTimer =AUTO_PERIOD end
		updateTimerLabels()
	end
end)

-- =========================================================
-- ====================== UI Helper ========================
-- =========================================================
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
local function rounded(obj, r) local ui = Instance.new("UICorner"); ui.CornerRadius = UDim.new(0, r or 8); ui.Parent = obj; return ui end
local function tween(obj, props, t, style, dir)
	local info = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	return TweenService:Create(obj, info, props)
end

-- =========================================================
-- ===================== PLAYER TUNER ======================
-- =========================================================
screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerTuner"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(320, 360)
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
local fullSize = UDim2.fromOffset(320, 360)
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

local function setMinimized(v)
	if v == isMinimized then return end
	isMinimized = v
	minimizeButton.Text = v and "▣" or "—"
	if v then
		for _, d in ipairs(content:GetDescendants()) do
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
			for _, d in ipairs(content:GetDescendants()) do
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

-- Row 1 Buttons
local buttonsRow = Instance.new("Frame"); buttonsRow.Size = UDim2.new(1, 0, 0, 36); buttonsRow.Position = UDim2.new(0, 0, 0, 200); buttonsRow.BackgroundTransparency = 1; buttonsRow.Parent = content
local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(0.33, -6, 1, 0); resetBtn.Position = UDim2.new(0, 0, 0, 0)
resetBtn.BackgroundColor3 = Color3.fromRGB(70,100,180); resetBtn.TextColor3 = Color3.fromRGB(255,255,255)
resetBtn.Text = "↩️ Reset Defaults"; resetBtn.Font = Enum.Font.GothamBold; resetBtn.TextSize = 13; resetBtn.Parent = buttonsRow; rounded(resetBtn,8)
local noclipBtn = Instance.new("TextButton")
noclipBtn.Size = UDim2.new(0.33, -6, 1, 0); noclipBtn.Position = UDim2.new(0.335, 6, 0, 0)
noclipBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60); noclipBtn.TextColor3 = Color3.fromRGB(255,255,255)
noclipBtn.Text = "🚫 NO CLIP: OFF"; noclipBtn.Font = Enum.Font.GothamBold; noclipBtn.TextSize = 13; noclipBtn.Parent = buttonsRow; rounded(noclipBtn,8)
local toggleGearBtn = Instance.new("TextButton")
toggleGearBtn.Size = UDim2.new(0.33, 0, 1, 0); toggleGearBtn.Position = UDim2.new(0.67, 6, 0, 0)
toggleGearBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 60); toggleGearBtn.TextColor3 = Color3.fromRGB(255,255,255)
toggleGearBtn.Text = "🛒 Toggle Gear Panel"; toggleGearBtn.Font = Enum.Font.GothamBold; toggleGearBtn.TextSize = 13; toggleGearBtn.Parent = buttonsRow; rounded(toggleGearBtn,8)

-- Row 2: Anti-AFK + Open Mini Panel
local miscRow = Instance.new("Frame"); miscRow.Size = UDim2.new(1, 0, 0, 36); miscRow.Position = UDim2.new(0, 0, 0, 236); miscRow.BackgroundTransparency = 1; miscRow.Parent = content
antiAFKBtn = Instance.new("TextButton")
antiAFKBtn.Size = UDim2.new(0.48, -4, 1, 0); antiAFKBtn.Position = UDim2.new(0, 0, 0, 0)
antiAFKBtn.BackgroundColor3 = Color3.fromRGB(100, 130, 100); antiAFKBtn.TextColor3 = Color3.fromRGB(255,255,255)
antiAFKBtn.Text = "🛡️ Anti-AFK: OFF"; antiAFKBtn.Font = Enum.Font.GothamBold; antiAFKBtn.TextSize = 13; antiAFKBtn.Parent = miscRow; rounded(antiAFKBtn,8)
local openMiniBtn = Instance.new("TextButton")
openMiniBtn.Size = UDim2.new(0.52, 0, 1, 0); openMiniBtn.Position = UDim2.new(0.48, 4, 0, 0)
openMiniBtn.BackgroundColor3 = Color3.fromRGB(140, 110, 200); openMiniBtn.TextColor3 = Color3.fromRGB(255,255,255)
openMiniBtn.Text = "⚙️ Open Saad Mini Panel"; openMiniBtn.Font = Enum.Font.GothamBold; openMiniBtn.TextSize = 13; openMiniBtn.Parent = miscRow; rounded(openMiniBtn,8)

-- Row 3: Hint
local hintRow = Instance.new("TextLabel")
hintRow.Size = UDim2.new(1, 0, 0, 22); hintRow.Position = UDim2.new(0, 0, 0, 272)
hintRow.BackgroundTransparency = 1; hintRow.TextXAlignment = Enum.TextXAlignment.Left
hintRow.Font = Enum.Font.Gotham; hintRow.TextSize = 12; hintRow.TextColor3 = Color3.fromRGB(200,220,255)
hintRow.Text = "⌘/Ctrl + clic = TP • H: Harvest v2.4  •  J: Harvest v4 (hybride)"
hintRow.Parent = content

-- ===== Anti-AFK Manager (corrigé) =====
local function setAntiAFK(enabled)
	if enabled == antiAFKEnabled then return end
	antiAFKEnabled = enabled
	antiAFKBtn.Text = enabled and "🛡️ Anti-AFK: ON" or "🛡️ Anti-AFK: OFF"
	antiAFKBtn.BackgroundColor3 = enabled and Color3.fromRGB(80,140,90) or Color3.fromRGB(100,130,100)

	if antiAFK_IdledConn then antiAFK_IdledConn:Disconnect(); antiAFK_IdledConn = nil end
	if enabled then
		antiAFK_IdledConn = player.Idled:Connect(function()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0,0))
			end)
		end)
	end

	if antiAFKThread then task.cancel(antiAFKThread); antiAFKThread = nil end
	if enabled then
		msg("🛡️ Anti-AFK activé (VirtualUser + micro-move périodique).", Color3.fromRGB(180,230,180))
		antiAFKThread = task.spawn(function()
			while antiAFKEnabled do
				task.wait(ANTI_AFK_PERIOD)
				if not antiAFKEnabled then break end
				local character = player.Character
				local hum = character and character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum:Move(Vector3.new(0, 0, -1), true)
					task.wait(ANTI_AFK_DURATION)
					hum:Move(Vector3.new(0, 0, 0), true)
				end
			end
		end)
	else
		msg("🛡️ Anti-AFK désactivé.", Color3.fromRGB(230,200,180))
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum:Move(Vector3.new(0,0,0), true) end
	end
end

antiAFKBtn.MouseButton1Click:Connect(function()
	setAntiAFK(not antiAFKEnabled)
end)

-- ===== Boutons Player Tuner =====
resetBtn.MouseButton1Click:Connect(function()
	resetDefaults()
	speedSlider.set(DEFAULT_WALKSPEED)
	gravitySlider.set(DEFAULT_GRAVITY)
	jumpSlider.set(DEFAULT_JUMPPOWER)
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
		msg("🚫 NO CLIP activé.")
	else
		noclipBtn.BackgroundColor3=Color3.fromRGB(220,60,60); noclipBtn.Text="🚫 NO CLIP: OFF"
		if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end
		local ch=player.Character; if ch then for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
		msg("✅ NO CLIP désactivé.")
	end
end)

closeButton.MouseButton1Click:Connect(function()
	if isNoclipping then if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end end
	setAntiAFK(false)
	if gearGui then gearGui:Destroy() end
	if screenGui then screenGui:Destroy() end
end)

-- ================= GEAR UI =================
gearGui = Instance.new("ScreenGui")
gearGui.Name = "GearPanel"
gearGui.ResetOnSpawn = false
gearGui.IgnoreGuiInset = false
gearGui.Parent = playerGui

gearFrame = Instance.new("Frame")
gearFrame.Size = UDim2.fromOffset(280, 520)
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

-- Submit All (Cauldron)
local submitCauldronBtn = Instance.new("TextButton")
submitCauldronBtn.Size = UDim2.new(1, 0, 0, 26)
submitCauldronBtn.Position = UDim2.new(0, 0, 0, 94)
submitCauldronBtn.BackgroundColor3 = Color3.fromRGB(140, 110, 200)
submitCauldronBtn.TextColor3 = Color3.fromRGB(255,255,255)
submitCauldronBtn.Text = "🧪 SUBMIT ALL (Cauldron)"
submitCauldronBtn.Font = Enum.Font.GothamBold
submitCauldronBtn.TextSize = 12
submitCauldronBtn.Parent = gearContent
rounded(submitCauldronBtn,8)

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
autoSeedsBtn.BackgroundColor3 = Color3.fromRGB(70,160,90) -- ON
autoSeedsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoSeedsBtn.Text = "Auto: ON"
autoSeedsBtn.Font = Enum.Font.GothamBold
autoSeedsBtn.TextSize = 12
autoSeedsBtn.Parent = seedsRow
rounded(autoSeedsBtn,8)

seedsTimerLabel = Instance.new("TextLabel")
seedsTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
seedsTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
seedsTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
seedsTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
seedsTimerLabel.Text = "⏳ Next: 1:00"
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
autoGearBtn.BackgroundColor3 = Color3.fromRGB(70,140,180) -- ON
autoGearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoGearBtn.Text = "Auto: ON"
autoGearBtn.Font = Enum.Font.GothamBold
autoGearBtn.TextSize = 12
autoGearBtn.Parent = gearRow
rounded(autoGearBtn,8)

gearTimerLabel = Instance.new("TextLabel")
gearTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
gearTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
gearTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
gearTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
gearTimerLabel.Text = "⏳ Next: 1:00"
gearTimerLabel.Font = Enum.Font.Gotham
gearTimerLabel.TextSize = 12
gearTimerLabel.Parent = gearRow
rounded(gearTimerLabel,8)

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
autoEggsBtn.BackgroundColor3 = Color3.fromRGB(120,100,160) -- ON
autoEggsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoEggsBtn.Text = "Auto: ON"
autoEggsBtn.Font = Enum.Font.GothamBold
autoEggsBtn.TextSize = 12
autoEggsBtn.Parent = eggsRow
rounded(autoEggsBtn,8)

eggsTimerLabel = Instance.new("TextLabel")
eggsTimerLabel.Size = UDim2.new(0.30, 0, 1, 0)
eggsTimerLabel.Position = UDim2.new(0.70, 4, 0, 0)
eggsTimerLabel.BackgroundColor3 = Color3.fromRGB(60, 65, 95)
eggsTimerLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
eggsTimerLabel.Text = "⏳ Next: 1:00"
eggsTimerLabel.Font = Enum.Font.Gotham
eggsTimerLabel.TextSize = 12
eggsTimerLabel.Parent = eggsRow
rounded(eggsTimerLabel,8)

-- Lollipop x50
local lolliBtn = Instance.new("TextButton")
lolliBtn.Size = UDim2.new(1, 0, 0, 26)
lolliBtn.Position = UDim2.new(0, 0, 0, 222)
lolliBtn.BackgroundColor3 = Color3.fromRGB(200, 140, 90)
lolliBtn.TextColor3 = Color3.fromRGB(255,255,255)
lolliBtn.Text = "🍭 BUY LOLLIPOP x50"
lolliBtn.Font = Enum.Font.GothamBold
lolliBtn.TextSize = 12
lolliBtn.Parent = gearContent
rounded(lolliBtn,8)

-- gear actions
tpGear.MouseButton1Click:Connect(function() teleportTo(GEAR_SHOP_POS) end)
sellBtn.MouseButton1Click:Connect(function()
	local r = getSellInventoryRemote()
	if not r then msg("❌ Remote Sell_Inventory introuvable.", Color3.fromRGB(255,120,120)); return end
	local hrp = getHRP(); if not hrp then msg("❌ HRP introuvable.", Color3.fromRGB(255,120,120)); return end
	local back = hrp.CFrame
	teleportTo(SELL_NPC_POS); task.wait(0.20); r:FireServer(); task.wait(0.05); hrp.CFrame = back
	msg("🧺 Inventaire vendu (TP/retour).", Color3.fromRGB(220,200,140))
end)
submitCauldronBtn.MouseButton1Click:Connect(function()
	local r = getWitchesSubmitRemote()
	if not r then msg("❌ WitchesBrew.SubmitItemToCauldron introuvable.", Color3.fromRGB(255,120,120)); return end
	local ok, res = pcall(function() return r:InvokeServer("All") end)
	if ok then msg("🧪 Cauldron: Submit All OK.", Color3.fromRGB(180,230,200))
	else msg("Cauldron error: "..tostring(res), Color3.fromRGB(255,160,140)) end
end)
buyAllSeedsButton.MouseButton1Click:Connect(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD; updateTimerLabels() end)
buyAllGearButton.MouseButton1Click:Connect(function() buyAllGearWorker();  gearTimer  = AUTO_PERIOD; updateTimerLabels() end)
buyEggsButton.MouseButton1Click:Connect(function() buyAllEggsWorker();   eggsTimer = AUTO_PERIOD; updateTimerLabels() end)
lolliBtn.MouseButton1Click:Connect(buyLollipop50)

autoSeedsBtn.MouseButton1Click:Connect(function()
	autoBuySeeds = not autoBuySeeds
	autoSeedsBtn.BackgroundColor3 = autoBuySeeds and Color3.fromRGB(70,160,90) or Color3.fromRGB(80,90,120)
	autoSeedsBtn.Text = autoBuySeeds and "Auto: ON" or "Auto: OFF"
	if autoBuySeeds then task.spawn(function() buyAllSeedsWorker(); seedsTimer=AUTO_PERIOD; updateTimerLabels() end) end
	updateTimerLabels()
end)
local function toggleGear() gearFrame.Visible = not gearFrame.Visible; if gearFrame.Visible then clampOnScreen(gearFrame) end end
gearClose.MouseButton1Click:Connect(function() gearFrame.Visible = false end)
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

-- =========================================================
-- ====== Heuristiques & primitives Harvest communes =======
-- =========================================================
local _FPP = (rawget(_G or getfenv(), "fireproximityprompt")) or _G.fireproximityprompt or _G.FireProximityPrompt or getfenv().fireproximityprompt or fireproximityprompt
local HAS_FIRE_PROX = (typeof(_FPP) == "function")

local PromptHeur = {
	plantWhitelist = { "plant","harvest","crop","fruit","vegetable","tree","bush","flower","pick","collect" },
	plantExclude   = { "mushroom","champignon" },
	promptTextWhitelist = { "harvest","pick","collect","récolter","cueillir" },
	promptBlacklist = { "fence","save","slot","skin","shop","buy","sell","chest","settings","rename","open","claim","craft","upgrade" },
}
local function containsAny(s, list) for _, kw in ipairs(list) do if string.find(s, kw, 1, true) then return true end end return false end
local function isPlantPrompt(prompt)
	if not prompt or not prompt.Parent then return false end
	local action = lower(prompt.ActionText)
	local object = lower(prompt.ObjectText)
	if containsAny(action, PromptHeur.plantExclude) or containsAny(object, PromptHeur.plantExclude) then return false end
	for _, kw in ipairs(PromptHeur.promptTextWhitelist) do
		if string.find(action, kw, 1, true) or string.find(object, kw, 1, true) then
			local node = prompt.Parent
			for i=1,4 do if not node then break end; if containsAny(lower(node.Name), PromptHeur.plantExclude) then return false end; node = node.Parent end
			return true
		end
	end
	local node = prompt
	for i=1,4 do
		if not node then break end
		local nm = lower(node.Name)
		for _, bad in ipairs(PromptHeur.promptBlacklist) do if string.find(nm, bad, 1, true) then return false end end
		if containsAny(nm, PromptHeur.plantWhitelist) then return true end
		node = node.Parent
	end
	return false
end
local function makeOverlapParamsExcludeCharacter()
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {player.Character}
	if Enum.RaycastFilterType and Enum.RaycastFilterType.Blacklist then params.FilterType = Enum.RaycastFilterType.Blacklist else params.FilterType = Enum.RaycastFilterType.Exclude end
	return params
end
local function getNearbyPlantPrompts(radius, allowGlobalFallback)
	if allowGlobalFallback == nil then allowGlobalFallback = true end
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
				if child:IsA("ProximityPrompt") and isPlantPrompt(child) then table.insert(prompts, child) end
			end
		end
	end
	if #prompts == 0 and allowGlobalFallback then
		for _, prompt in ipairs(Workspace:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") and isPlantPrompt(prompt) then
				local root = prompt.Parent
				local posPart = root and root:IsA("BasePart") and root or (root and root:FindFirstChildWhichIsA("BasePart"))
				local h = getHRP()
				if posPart and h and (posPart.Position - h.Position).Magnitude <= radius then table.insert(prompts, prompt) end
			end
		end
	end
	return prompts
end
local function safeFirePrompt(prompt, holdCap)
	if HAS_FIRE_PROX then
		local ok = pcall(function()
			prompt.MaxActivationDistance = 2000
			_FPP(prompt)
			if prompt.HoldDuration and prompt.HoldDuration > 0 then
				task.wait(math.min(holdCap or 0.25, prompt.HoldDuration))
				_FPP(prompt)
			end
		end)
		if ok then return end
	end
	VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game); task.wait(0.04)
	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

-- =========================================================
-- =================== ⚡ AUTO HARVEST v2.4 =================
-- ========== Pleine puissance (+~50% vs original) =========
-- =========================================================
local AutoHarv24 = {
	enabled = false,
	uiBtn   = nil,
	-- ⚡ Boost massif : tick↓ (0.08), rayon↑ (32), budget↑ (12), fallback global ON
	config  = { radius=32, tick=0.08, holdCap=0.28, spamE=false, stopWhenBackpackFull=true, budget=12, globalFallback=true },
}
function AutoHarv24:start()
	if self.enabled then return end
	self.enabled = true
	if self.uiBtn and self.uiBtn.Parent then
		self.uiBtn.BackgroundColor3=Color3.fromRGB(100,180,80)
		self.uiBtn.Text=("🌾 Auto Harvest v2.4: ON  • r=%d"):format(self.config.radius)
	end
	msg("⚡ AutoHarvest v2.4 TURBO ON — tick 0.08 • r=32 • budget=12 • fallback=ON (auto-stop 3s).", Color3.fromRGB(180,230,180))

	local startedAt = tick()
	task.delay(3, function()
		if self.enabled and (tick() - startedAt) >= 2.9 then
			self:stop("arrêt auto 3s")
		end
	end)

	task.spawn(function()
		while self.enabled do
			if self.config.stopWhenBackpackFull then
				local full, c, m = isBackpackFull()
				if full then
					self.enabled = false
					if self.uiBtn and self.uiBtn.Parent then
						self.uiBtn.BackgroundColor3=Color3.fromRGB(200,120,60)
						self.uiBtn.Text="🌾 Auto Harvest v2.4: OFF"
					end
					msg(("⚠️ MAX BACKPACK SPACE (%s/%s) — AutoHarvest v2.4 OFF"):format(tostring(c or "?"), tostring(m or "?")), Color3.fromRGB(255,180,120))
					break
				end
			end

			local prompts = getNearbyPlantPrompts(self.config.radius, self.config.globalFallback ~= false)
			local budget = self.config.budget or math.huge
			local count = 0
			for _, prompt in ipairs(prompts) do
				if count >= budget then break end
				safeFirePrompt(prompt, self.config.holdCap)
				count += 1
			end
			if self.config.spamE then
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game); task.wait(0.02)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
			end
			task.wait(self.config.tick)
		end
	end)
end
function AutoHarv24:stop(reason)
	if not self.enabled then return end
	self.enabled=false
	if self.uiBtn and self.uiBtn.Parent then
		self.uiBtn.BackgroundColor3=Color3.fromRGB(200,120,60)
		self.uiBtn.Text="🌾 Auto Harvest v2.4: OFF"
	end
	if reason then
		msg("🌾 AutoHarvest v2.4 OFF — "..tostring(reason)..".", Color3.fromRGB(230,200,180))
	else
		msg("🌾 AutoHarvest v2.4 OFF.", Color3.fromRGB(230,200,180))
	end
end

-- =========================================================
-- =============== AUTO HARVEST v4.3 (HOTFIX) ==============
-- =========================================================
local AutoHarv4 = {
	enabled=false, uiBtn=nil,
	radius=28,            -- scan
	tick=0.30,            -- cadence
	holdCap=0.22,         -- cap de maintien
	spamE=false,          -- fallback E
	promptCooldown=0.25,  -- anti-spam
	stopWhenBackpackFull=true,

	collected=0,
	_cd={}, _shownConn=nil, _trigConn=nil, _loopThread=nil
}

local function ah4Cooldown(self, id)
	local now = tick()
	if self._cd[id] and (now - self._cd[id]) < self.promptCooldown then return true end
	self._cd[id] = now
	return false
end
local function promptId(p)
	local id = tostring(p)
	if typeof(p.GetDebugId) == "function" then
		local ok, rid = pcall(function() return p:GetDebugId() end)
		if ok and rid then id = rid end
	end
	return id
end
function AutoHarv4:_setBtn(on)
	if not self.uiBtn or not self.uiBtn.Parent then return end
	if on then
		self.uiBtn.BackgroundColor3 = Color3.fromRGB(100,180,80)
		self.uiBtn.Text = ("🌾 Auto Harvest v4: ON  •  %d"):format(self.collected or 0)
	else
		self.uiBtn.BackgroundColor3 = Color3.fromRGB(200,120,60)
		self.uiBtn.Text = "🌾 Auto Harvest v4: OFF"
	end
end
function AutoHarv4:_scanOnce()
	if self.stopWhenBackpackFull then
		local full = select(1, isBackpackFull())
		if full then
			self:stop(true)
			msg("⚠️ MAX BACKPACK SPACE — AutoHarvest v4 OFF (valeurs)", Color3.fromRGB(255,180,120))
			return
		end
	end
	local prompts = getNearbyPlantPrompts(self.radius, true)
	local budget  = 6
	for _, p in ipairs(prompts) do
		if budget <= 0 then break end
		if p and p.Parent and isPlantPrompt(p) then
			local pid = promptId(p)
			if not ah4Cooldown(self, pid) then
				safeFirePrompt(p, self.holdCap)
				budget -= 1
			end
		end
	end
	if self.spamE then
		VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.E, false, game)
		task.wait(0.02)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end
end
function AutoHarv4:start()
	if self.enabled then return end
	self.enabled = true
	self.collected = 0
	self._cd = {}
	self:_setBtn(true)
	msg("🌾 AutoHarvest v4.3 ON — tick 0.30s + budget 6 + PromptShown.", Color3.fromRGB(180,230,180))

	self._shownConn = ProximityPromptService.PromptShown:Connect(function(p)
		if not self.enabled then return end
		if not p or not p.Parent then return end
		if not isPlantPrompt(p) then return end
		local pid = promptId(p)
		if not ah4Cooldown(self, pid) then
			safeFirePrompt(p, self.holdCap)
		end
	end)

	self._trigConn = ProximityPromptService.PromptTriggered:Connect(function(p, plr)
		if self.enabled and plr == Players.LocalPlayer and p and p.Parent and isPlantPrompt(p) then
			self.collected += 1
			self:_setBtn(true)
		end
	end)

	self._loopThread = task.spawn(function()
		while self.enabled do
			self:_scanOnce()
			task.wait(self.tick)
		end
	end)
end
function AutoHarv4:stop(silent)
	if not self.enabled then return end
	self.enabled = false
	if self._shownConn then self._shownConn:Disconnect() self._shownConn=nil end
	if self._trigConn  then self._trigConn:Disconnect()  self._trigConn=nil end
	if self._loopThread then task.cancel(self._loopThread) self._loopThread=nil end
	self._cd = {}
	self:_setBtn(false)
	if not silent then msg("🌾 AutoHarvest v4.3 OFF.", Color3.fromRGB(230,200,180)) end
end

-- =========================================================
-- ===================== MINI PANEL UI =====================
-- =========================================================
local miniPanelGui
local function buildMiniPanel()
	if miniPanelGui and miniPanelGui.Parent then return miniPanelGui end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SaadMiniPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(380, 360)
	frame.Position = UDim2.fromScale(0.02, 0.22)
	frame.BackgroundColor3 = Color3.fromRGB(30,30,38)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	rounded(frame, 10)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	header.Parent = frame
	rounded(header, 10)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -46, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "⚙️ Saad Mini Panel — v3.2"
	title.TextColor3 = Color3.fromRGB(255,255,255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.Position = UDim2.new(1, -32, 0.5, -13)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
	closeBtn.Text = "✕"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.Parent = header
	rounded(closeBtn, 6)
	closeBtn.MouseButton1Click:Connect(function() gui.Enabled=false end)

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -14, 1, -46)
	container.Position = UDim2.new(0, 7, 0, 42)
	container.BackgroundTransparency = 1
	container.Parent = frame

	-- Row 1 : AutoHarvest v4 + Submit Cauldron
	local row1 = Instance.new("Frame"); row1.Size = UDim2.new(1, 0, 0, 40); row1.BackgroundTransparency = 1; row1.Parent = container
	local btnAutoV4 = Instance.new("TextButton")
	btnAutoV4.Size = UDim2.new(0.48, -4, 1, 0); btnAutoV4.Position = UDim2.new(0, 0, 0, 0)
	btnAutoV4.BackgroundColor3 = Color3.fromRGB(200, 120, 60); btnAutoV4.TextColor3 = Color3.fromRGB(255,255,255)
	btnAutoV4.Text = "🌾 Auto Harvest v4: OFF"; btnAutoV4.Font = Enum.Font.GothamBold; btnAutoV4.TextSize = 13; btnAutoV4.Parent = row1; rounded(btnAutoV4, 8)
	AutoHarv4.uiBtn = btnAutoV4

	local btnSubmit = Instance.new("TextButton")
	btnSubmit.Size = UDim2.new(0.52, 0, 1, 0); btnSubmit.Position = UDim2.new(0.48, 4, 0, 0)
	btnSubmit.BackgroundColor3 = Color3.fromRGB(140, 110, 200); btnSubmit.TextColor3 = Color3.fromRGB(255,255,255)
	btnSubmit.Text = "🧪 Submit All (Cauldron)"; btnSubmit.Font = Enum.Font.GothamBold; btnSubmit.TextSize = 13; btnSubmit.Parent = row1; rounded(btnSubmit, 8)

	-- Row 2 : Event Seeds (Spooky)
	local titleSeeds = Instance.new("TextLabel")
	titleSeeds.Size = UDim2.new(1, 0, 0, 20); titleSeeds.Position = UDim2.new(0, 0, 0, 46)
	titleSeeds.BackgroundTransparency = 1; titleSeeds.TextXAlignment = Enum.TextXAlignment.Left
	titleSeeds.Text = "🎃 EVENT SEEDS (Spooky)"
	titleSeeds.TextColor3 = Color3.fromRGB(255,235,180)
	titleSeeds.Font = Enum.Font.GothamBold; titleSeeds.TextSize = 13; titleSeeds.Parent = container

	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, 0, 0, 132); grid.Position = UDim2.new(0, 0, 0, 68)
	grid.BackgroundTransparency = 1; grid.Parent = container

	local function mkSeedBtn(xScale, yOff, name)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.48, -4, 0, 30)
		b.Position = UDim2.new(xScale, xScale==0 and 0 or 4, 0, yOff)
		b.BackgroundColor3 = Color3.fromRGB(150, 95, 160)
		b.TextColor3 = Color3.fromRGB(255,255,255)
		b.Text = "🛍️ "..name
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.Parent = grid
		rounded(b, 8)
		b.MouseButton1Click:Connect(function()
			b.AutoButtonColor=false; b.BackgroundColor3=Color3.fromRGB(120, 75, 130)
			task.spawn(function()
				local r = safeWait({"GameEvents","BuyEventShopStock"},2) or safeWait({"GameEvents","FallMarketEvent","BuyEventShopStock"},2)
				if not r or not r:IsA("RemoteEvent") then
					msg("Remote BuyEventShopStock introuvable.", Color3.fromRGB(255,120,120))
				else
					local ok, err = pcall(function() r:FireServer(name, "Spooky Seeds") end)
					if ok then msg("Achat Event Seed: "..name, Color3.fromRGB(180,230,180))
					else msg("Échec Event Seed ("..name.."): "..tostring(err), Color3.fromRGB(255,160,140)) end
				end
			end)
			task.delay(0.25, function() b.AutoButtonColor=true; b.BackgroundColor3=Color3.fromRGB(150, 95, 160) end)
		end)
	end
	local EVENT_SEEDS = { "Bloodred Mushroom","Jack O Lantern","Ghoul Root","Chicken Feed","Seer Vine","Poison Apple" }
	local col, row = 0, 0
	for _, name in ipairs(EVENT_SEEDS) do
		mkSeedBtn(col==0 and 0 or 0.52, row*34, name)
		col = (col==0) and 1 or 0
		if col==0 then row = row + 1 end
	end

	-- Row 3 : 🎃 Submit Jack O Lantern (scan sac + mutations, exclut eggs)
	local rowJack = Instance.new("Frame"); rowJack.Size = UDim2.new(1, 0, 0, 40); rowJack.Position = UDim2.new(0, 0, 0, 206); rowJack.BackgroundTransparency = 1; rowJack.Parent = container
	local jackBtn = Instance.new("TextButton")
	jackBtn.Size = UDim2.new(1, 0, 1, 0)
	jackBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 80)
	jackBtn.TextColor3 = Color3.fromRGB(255,255,255)
	jackBtn.Text = "🎃 SUBMIT HALLOWEEN → Jack"
	jackBtn.Font = Enum.Font.GothamBold
	jackBtn.TextSize = 13
	jackBtn.Parent = rowJack
	rounded(jackBtn, 8)
	jackBtn.MouseButton1Click:Connect(function()
		jackBtn.AutoButtonColor=false; jackBtn.BackgroundColor3=Color3.fromRGB(170, 85, 70)
		task.spawn(function() submitHalloweenToJackOLantern() end)
		task.delay(0.25, function() jackBtn.AutoButtonColor=true; jackBtn.BackgroundColor3=Color3.fromRGB(200, 100, 80) end)
	end)

	-- Row 4 : Toggle v2.4 + Hint
	local row4 = Instance.new("Frame"); row4.Size = UDim2.new(1, 0, 0, 70); row4.Position = UDim2.new(0, 0, 0, 248); row4.BackgroundTransparency = 1; row4.Parent = container
	local btnAutoV24 = Instance.new("TextButton")
	btnAutoV24.Size = UDim2.new(1, 0, 0, 32)
	btnAutoV24.BackgroundColor3 = Color3.fromRGB(200,120,60)
	btnAutoV24.TextColor3 = Color3.fromRGB(255,255,255)
	btnAutoV24.Text = "🌾 Auto Harvest v2.4: OFF"
	btnAutoV24.Font = Enum.Font.GothamBold
	btnAutoV24.TextSize = 13
	btnAutoV24.Parent = row4
	rounded(btnAutoV24, 8)
	AutoHarv24.uiBtn = btnAutoV24

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 26)
	hint.Position = UDim2.new(0, 0, 0, 38)
	hint.BackgroundTransparency = 1
	hint.Text = "Raccourcis: H = v2.4 (auto-stop 3s) • J = v4 (hybride)"
	hint.TextColor3 = Color3.fromRGB(160, 200, 255)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.Parent = row4

	-- Binds
	btnAutoV4.MouseButton1Click:Connect(function() if AutoHarv4.enabled then AutoHarv4:stop() else AutoHarv4:start() end end)
	btnSubmit.MouseButton1Click:Connect(function()
		local r = getWitchesSubmitRemote()
		if not r then msg("WitchesBrew.SubmitItemToCauldron introuvable.", Color3.fromRGB(255,120,120)); return end
		local ok, res = pcall(function() return r:InvokeServer("All") end)
		if ok then msg("🧪 Cauldron: Submit All OK.", Color3.fromRGB(180,230,200))
		else msg("Cauldron error: "..tostring(res), Color3.fromRGB(255,160,140)) end
	end)
	btnAutoV24.MouseButton1Click:Connect(function() if AutoHarv24.enabled then AutoHarv24:stop() else AutoHarv24:start() end end)

	makeDraggable(frame, header)
	applyAutoScale(gui, {frame})
	miniPanelGui = gui
	return gui
end

openMiniBtn.MouseButton1Click:Connect(function()
	local g = buildMiniPanel()
	g.Enabled = not g.Enabled
end)

-- Hotkeys
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.H then
		if AutoHarv24.enabled then AutoHarv24:stop() else AutoHarv24:start() end
	elseif input.KeyCode == Enum.KeyCode.J then
		if AutoHarv4.enabled then AutoHarv4:stop() else AutoHarv4:start() end
	end
end)

-- Ready
applyAutoScale(screenGui, {mainFrame})
applyAutoScale(gearGui,   {gearFrame})
msg("✅ Saad Helper Pack chargé • Seeds/Gear/Eggs Auto: ON • ⌘/Ctrl+clic TP • Mini Panel ✕ • H=v2.4 ⚡ (auto-stop 3s) • J=v4 • 🎃 Jack Submit prêt.", Color3.fromRGB(170,230,255))
