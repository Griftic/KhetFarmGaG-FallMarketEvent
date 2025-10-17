-- =====================================================================
-- 🧰 Saad Helper Pack — Build Complet (Player Tuner + Gear + MiniPanel)
-- - ⌘/Ctrl + Clic = TP (Mac/Windows) — sans freeze caméra
-- - UI Player Tuner (sliders + noclip + anti-AFK + Gear Panel + Mini Panel)
-- - Gear Panel: Sell, Submit Cauldron, Buy All Seeds/Gear/Eggs + Auto/60s ON
-- - Seeds inclut "Great Pumpkin" — auto-buy actif (BuySeedStock "Shop", <Seed>)
-- - Bouton: Buy "Level Up Lollipop" x50 (essaie 2 noms possibles)
-- - Mini Panel v3.8 (✕ fermer / ▭ réduire) :
--     • 🌾 Auto-Harvest v5.5 — SCAN rayon, turbo, stop à 200 ✔ (+ Halloween ONLY)
--     • 🌾 Auto Harvest v2.4 — durée réglable (1–6s), backpack stop, OFF immédiat
--     • 🧪 Submit All (Cauldron) — robuste (RemoteFunction exact + fallback)
--     • 🎃 Submit Halloween → Jack
--     • 🧟 Event Pets/Eggs (Wolf, Spooky Egg, Reaper, Ghost Bear, Pumpkin Rat)
--     • 🌀 FARM AUTO (Submit → Harvest [1–5s] → Submit → Wait [3–50s] → loop)
-- - Raccourcis: H = toggle Auto Harvest v2.4 • J = toggle Auto Harvest v5.5
-- - ▶️ Player Tuner: bouton "🌾 Open Harvest v5 Panel"
-- - Tous les panels sont LIBREMENT déplaçables (mobile/PC), sans verrou.
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
local AUTO_PERIOD = 60 -- ❗ 60s

-- Seeds/Gears/Eggs
local SEEDS = {
	"Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon",
	"Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom",
	"Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone",
	"Elder Strawberry","Romanesco","Crimson Thorn",
	"Great Pumpkin"
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
local autoBuySeeds, autoBuyGear, autoBuyEggs = true, true, true
local seedsTimer, gearTimer, eggsTimer = AUTO_PERIOD, AUTO_PERIOD, AUTO_PERIOD

-- Anti-AFK (toggle)
local antiAFKEnabled = false
local antiAFKBtn
local antiAFK_IdledConn, antiAFKThread = nil, nil

local seedsTimerLabel, gearTimerLabel, eggsTimerLabel
local screenGui, gearGui
local gearFrame
local coordsLabel

-- ========= FARM AUTO settings =========
-- Ordre: Submit → Harvest (1–5s) → Submit → Wait (3–50s)
local farmHarvestSeconds = 3    -- slider 1..5
local farmWaitSeconds    = 10   -- slider 3..50
local farmAutoEnabled    = false
local farmAutoToken      = 0
local farmAutoThread     = nil

-- ========= Auto Harvest v2.4 duration (slider 1..6s) =========
local harv24DurationSeconds = 3

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
local function getHRP() local c = player.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function applySpeed(v)   currentSpeed=v;  local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed=v end end
local function applyGravity(v) currentGravity=v; workspace.Gravity=v end
local function applyJump(v)    currentJump=v;   local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid"); if h then h.JumpPower=v end end
local function resetDefaults() applySpeed(DEFAULT_WALKSPEED); applyGravity(DEFAULT_GRAVITY); applyJump(DEFAULT_JUMPPOWER); msg("↩️ Reset (16 / 196.2 / 50).", Color3.fromRGB(180,220,255)) end
local function teleportTo(p) local hrp=getHRP(); if not hrp then msg("❌ HRP introuvable.", Color3.fromRGB(255,100,100)) return end; hrp.CFrame=CFrame.new(p) end
local function fmtTime(sec) sec=math.max(0,math.floor(sec+0.5)) local m=math.floor(sec/60) local s=sec%60 return string.format("%d:%02d",m,s) end
local function lower(s) return typeof(s)=="string" and string.lower(s) or "" end
local function norm(s) s = lower(s or "") s = s:gsub("%p"," "):gsub("%s+"," ") return s end

-- ====== Free Drag helper (mobile/PC) — no clamp ======
local function makeDraggable(frame, handle)
	frame.Active = true; frame.Selectable = true
	handle = handle or frame
	handle.Active = true; handle.Selectable = true
	local dragging, dragStart, startPos = false, nil, nil
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			startPos  = frame.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local delta = i.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- AutoScale (sans clamp)
local function applyAutoScale(screenGuiX)
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
	local function refresh() scaleObj.Scale = computeScale() end
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

-- === Submit All (robuste) — respecte l'appel exact fourni ===
local function submitAllCauldron_Robust()
	-- Essai 1: chemin EXACT fourni
	for attempt = 1, 2 do
		local ok, _ = pcall(function()
			local args = { [1] = "All" }
			local rf = ReplicatedStorage
				:WaitForChild("GameEvents", 2)
				:WaitForChild("WitchesBrew", 2)
				:WaitForChild("SubmitItemToCauldron", 2)
			rf:InvokeServer(unpack(args))
		end)
		if ok then
			msg("🧪 Cauldron: Submit All OK (Exact).", Color3.fromRGB(180,230,200))
			return true
		else
			if attempt == 2 then
				-- Essai 2: fallback via helper
				local rf = getWitchesSubmitRemote()
				if rf then
					local ok2, err2 = pcall(function() rf:InvokeServer("All") end)
					if ok2 then
						msg("🧪 Cauldron: Submit All OK (Fallback).", Color3.fromRGB(180,230,200))
						return true
					else
						msg("Cauldron error: "..tostring(err2), Color3.fromRGB(255,160,140))
					end
				else
					msg("❌ WitchesBrew.SubmitItemToCauldron introuvable.", Color3.fromRGB(255,120,120))
				end
			else
				task.wait(0.15)
			end
		end
	end
	return false
end

-- =========================================================
-- =========== Backpack detector (robuste) =================
-- =========================================================
local BackpackCountValue, BackpackCapValue = nil, nil
local function isValueObject(x) return x and (x:IsA("IntValue") or x:IsA("NumberValue")) end
local COUNT_NAMES = { "count","current","amount","qty","quantity","items","inventory","backpack","bag","held","stored" }
local CAP_NAMES   = { "capacity","cap","max","maxcapacity","maxamount","limit","maxitems","maxinventory","maxbackpack" }
local function nameMatchAny(nm, list) nm = lower(nm) for _, k in ipairs(list) do if nm == k or string.find(nm, k, 1, true) then return true end end return false end
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

local function buyAllSeedsWorker()
	local r = getBuySeedRemote(); if not r then msg("❌ BuySeedStock introuvable.", Color3.fromRGB(255,120,120)); return end
	msg("🌱 Achat: toutes les graines… (Shop)")
	for _, seed in ipairs(SEEDS) do
		for i=1,MAX_TRIES_PER_SEED do
			pcall(function() r:FireServer("Shop", seed) end)
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

local function strHasAny(hay, keys) hay = norm(hay) for _,k in ipairs(keys) do if hay:find(norm(k), 1, true) then return true end end return false end
local function toolIsHalloweenFruit(tool)
	if not (tool and tool:IsA("Tool")) then return false end
	local nm = norm(tool.Name)
	for _, base in ipairs(HALLOWEEN_FRUITS) do if nm:find(norm(base), 1, true) then return true end end
	return false
end
local function toolHasHalloweenMutation(tool)
	if not (tool and tool:IsA("Tool")) then return false end
	if strHasAny(tool.Name, HALLOWEEN_MUT_KEYS) then return true end
	for _, v in ipairs(tool:GetDescendants()) do
		if v:IsA("StringValue") or v:IsA("IntValue") or v:IsA("BoolValue") or v:IsA("NumberValue") then
			if strHasAny(v.Name, HALLOWEEN_MUT_KEYS) or strHasAny(tostring(v.Value), HALLOWEEN_MUT_KEYS) then return true end
		elseif v:IsA("Folder") then
			if strHasAny(v.Name, {"mut","mutation","mutations"}) then
				for _, sv in ipairs(v:GetChildren()) do
					if sv:IsA("StringValue") and strHasAny(tostring(sv.Value), HALLOWEEN_MUT_KEYS) then return true end
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
	pcall(function() hum:UnequipTools() end); task.wait(0.05)
	local ok = pcall(function() hum:EquipTool(tool) end)
	if not ok then pcall(function() tool.Parent = player.Character end) end
	task.wait(0.12)
	return true
end
local function submitJackHeld()
	local r = safeWait({"GameEvents","SubmitJackOLanternItem"}, 2)
	if not r or not r:IsA("RemoteEvent") then msg("❌ SubmitJackOLanternItem introuvable.", Color3.fromRGB(255,120,120)) return false end
	local ok = pcall(function() r:FireServer("Held") end)
	return ok
end
local function submitHalloweenToJackOLantern()
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 2)
	if not backpack then msg("🎒 Backpack introuvable.", Color3.fromRGB(255,120,120)) return 0 end
	local submitted = 0
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			local isH = toolIsHalloweenFruit(tool)
			local isM = toolHasHalloweenMutation(tool)
			if (isH or isM) and not toolIsNonFruit(tool) then
				equipTool(tool); task.wait(0.06)
				if submitJackHeld() then submitted += 1; task.wait(0.12) end
			end
		end
	end
	if submitted > 0 then msg(("🎃 Jack O Lantern: %d fruit(s) soumis."):format(submitted), Color3.fromRGB(180,230,180))
	else msg("🎃 Jack O Lantern: rien à soumettre (fruits Halloween ou fruits à mutation Halloween).", Color3.fromRGB(230,200,180)) end
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
local function rounded(obj, r) local ui = Instance.new("UICorner"); ui.CornerRadius = UDim.new(0, r or 8); ui.Parent = obj; return ui end
local function tween(obj, props, t, style, dir) local info = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out) return TweenService:Create(obj, info, props) end

-- =========================================================
-- ===================== PLAYER TUNER ======================
-- =========================================================
screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlayerTuner"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui
applyAutoScale(screenGui)

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(320, 392)
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
local fullSize = UDim2.fromOffset(320, 392)
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
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; updateFromX(i.Position.X) i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end) end
	end)
	knob.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; updateFromX(i.Position.X) i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end) end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then updateFromX(i.Position.X) end
	end)
	setValue(initialValue, true)
	return { set = function(v) setValue(v, true) end }
end

local speedSlider   = createSlider(content, 0,   "Walk Speed (16–58)",   16, 58,   1,   currentSpeed,   applySpeed,   0)
local gravitySlider = createSlider(content, 70,  "Gravity (37.5–196.2)", 37.5,196.2, 0.1, currentGravity, applyGravity, 1)
local jumpSlider    = createSlider(content, 140, "Jump Power (45–82.5)", 45, 82.5, 0.5, currentJump,    applyJump,    1)

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

local miscRow = Instance.new("Frame"); miscRow.Size = UDim2.new(1, 0, 0, 36); miscRow.Position = UDim2.new(0, 0, 0, 236); miscRow.BackgroundTransparency = 1; miscRow.Parent = content
antiAFKBtn = Instance.new("TextButton")
antiAFKBtn.Size = UDim2.new(0.48, -4, 1, 0); antiAFKBtn.Position = UDim2.new(0, 0, 0, 0)
antiAFKBtn.BackgroundColor3 = Color3.fromRGB(100, 130, 100); antiAFKBtn.TextColor3 = Color3.fromRGB(255,255,255)
antiAFKBtn.Text = "🛡️ Anti-AFK: OFF"; antiAFKBtn.Font = Enum.Font.GothamBold; antiAFKBtn.TextSize = 13; antiAFKBtn.Parent = miscRow; rounded(antiAFKBtn,8)
local openMiniBtn = Instance.new("TextButton")
openMiniBtn.Size = UDim2.new(0.52, 0, 1, 0); openMiniBtn.Position = UDim2.new(0.48, 4, 0, 0)
openMiniBtn.BackgroundColor3 = Color3.fromRGB(140, 110, 200); openMiniBtn.TextColor3 = Color3.fromRGB(255,255,255)
openMiniBtn.Text = "⚙️ Open Saad Mini Panel"; openMiniBtn.Font = Enum.Font.GothamBold; openMiniBtn.TextSize = 13; openMiniBtn.Parent = miscRow; rounded(openMiniBtn,8)

local v5Row = Instance.new("Frame"); v5Row.Size = UDim2.new(1, 0, 0, 36); v5Row.Position = UDim2.new(0, 0, 0, 272); v5Row.BackgroundTransparency = 1; v5Row.Parent = content
local openV5Btn = Instance.new("TextButton")
openV5Btn.Size = UDim2.new(1, 0, 1, 0); openV5Btn.Position = UDim2.new(0, 0, 0, 0)
openV5Btn.BackgroundColor3 = Color3.fromRGB(90,120,210)
openV5Btn.TextColor3 = Color3.fromRGB(255,255,255)
openV5Btn.Text = "🌾 Open Harvest v5 Panel"
openV5Btn.Font = Enum.Font.GothamBold
openV5Btn.TextSize = 13
openV5Btn.Parent = v5Row
rounded(openV5Btn,8)

local hintRow = Instance.new("TextLabel")
hintRow.Size = UDim2.new(1, 0, 0, 22); hintRow.Position = UDim2.new(0, 0, 0, 308)
hintRow.BackgroundTransparency = 1; hintRow.TextXAlignment = Enum.TextXAlignment.Left
hintRow.Font = Enum.Font.Gotham; hintRow.TextSize = 12; hintRow.TextColor3 = Color3.fromRGB(200,220,255)
hintRow.Text = "⌘/Ctrl + clic = TP • H: Harvest v2.4  •  J: Harvest v5.5 (turbo + stop 200)"
hintRow.Parent = content

local function setAntiAFK(enabled)
	if enabled == antiAFKEnabled then return end
	antiAFKEnabled = enabled
	antiAFKBtn.Text = enabled and "🛡️ Anti-AFK: ON" or "🛡️ Anti-AFK: OFF"
	antiAFKBtn.BackgroundColor3 = enabled and Color3.fromRGB(80,140,90) or Color3.fromRGB(100,130,100)
	if antiAFK_IdledConn then antiAFK_IdledConn:Disconnect(); antiAFK_IdledConn=nil end
	if enabled then
		antiAFK_IdledConn = player.Idled:Connect(function()
			pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end)
		end)
	end
	if antiAFKThread then task.cancel(antiAFKThread); antiAFKThread=nil end
	if enabled then
		msg("🛡️ Anti-AFK activé (VirtualUser + micro-move).", Color3.fromRGB(180,230,180))
		antiAFKThread = task.spawn(function()
			while antiAFKEnabled do
				task.wait(ANTI_AFK_PERIOD)
				if not antiAFKEnabled then break end
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then hum:Move(Vector3.new(0,0,-1), true); task.wait(ANTI_AFK_DURATION); hum:Move(Vector3.new(0,0,0), true) end
			end
		end)
	else
		msg("🛡️ Anti-AFK désactivé.", Color3.fromRGB(230,200,180))
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum:Move(Vector3.new(0,0,0), true) end
	end
end
antiAFKBtn.MouseButton1Click:Connect(function() setAntiAFK(not antiAFKEnabled) end)

local function resetAll()
	resetDefaults()
	speedSlider.set(DEFAULT_WALKSPEED); gravitySlider.set(DEFAULT_GRAVITY); jumpSlider.set(DEFAULT_JUMPPOWER)
end
resetBtn.MouseButton1Click:Connect(resetAll)

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
	if isNoclipping and noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end
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
applyAutoScale(gearGui)

gearFrame = Instance.new("Frame")
local GEAR_FULL   = UDim2.fromOffset(280, 520)
local GEAR_COLLAP = UDim2.fromOffset(280, 28)
gearFrame.Size = GEAR_FULL
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
gearClose.Size = UDim2.fromOffset(20, 20)
gearClose.Position = UDim2.new(1, -26, 0, 4)
gearClose.BackgroundColor3 = Color3.fromRGB(255, 72, 72)
gearClose.TextColor3 = Color3.fromRGB(255,255,255)
gearClose.Text = "✕"
gearClose.Font = Enum.Font.GothamBold
gearClose.TextSize = 12
gearClose.Parent = gearTitleBar
rounded(gearClose,0)

local gearMin = Instance.new("TextButton")
gearMin.Size = UDim2.fromOffset(20, 20)
gearMin.Position = UDim2.new(1, -50, 0, 4)
gearMin.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
gearMin.TextColor3 = Color3.fromRGB(255,255,255)
gearMin.Text = "▭"
gearMin.Font = Enum.Font.GothamBold
gearMin.TextSize = 12
gearMin.Parent = gearTitleBar
rounded(gearMin,0)

local gearContent = Instance.new("Frame")
gearContent.Size = UDim2.new(1, -16, 1, -40)
gearContent.Position = UDim2.new(0, 8, 0, 36)
gearContent.BackgroundTransparency = 1
gearContent.Parent = gearFrame

makeDraggable(gearFrame, gearTitleBar)

local gearCollapsed = false
local function toggleGearMin()
	gearCollapsed = not gearCollapsed
	if gearCollapsed then
		gearContent.Visible = false
		TweenService:Create(gearFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = GEAR_COLLAP}):Play()
	else
		TweenService:Create(gearFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = GEAR_FULL}):Play()
		task.delay(0.2, function() gearContent.Visible = true end)
	end
end
gearMin.MouseButton1Click:Connect(toggleGearMin)

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
autoSeedsBtn.BackgroundColor3 = Color3.fromRGB(70,160,90)
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
autoGearBtn.BackgroundColor3 = Color3.fromRGB(70,140,180)
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
autoEggsBtn.BackgroundColor3 = Color3.fromRGB(120,100,160)
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
	submitAllCauldron_Robust()
end)
buyAllSeedsButton.MouseButton1Click:Connect(function() buyAllSeedsWorker(); seedsTimer = AUTO_PERIOD; updateTimerLabels() end)
buyAllGearButton.MouseButton1Click:Connect(function() buyAllGearWorker();  gearTimer  = AUTO_PERIOD; updateTimerLabels() end)
buyEggsButton.MouseButton1Click:Connect(function() buyAllEggsWorker();   eggsTimer = AUTO_PERIOD; updateTimerLabels() end)
lolliBtn.MouseButton1Click:Connect(buyLollipop50)

local function toggleGear() gearFrame.Visible = not gearFrame.Visible end
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
	plantWhitelist = { "plant","harvest","crop","fruit","vegetable","tree","bush","flower","pick","collect","gather","récolte","récolter","cueillir" },
	promptTextWhitelist = { "harvest","pick","collect","gather","récolter","cueillir" },
	promptBlacklist = { "fence","save","slot","skin","shop","buy","sell","chest","settings","rename","open","claim","craft","upgrade" },
}
local function containsAny(s, list) s = lower(s or "") for _, kw in ipairs(list) do if string.find(s, kw, 1, true) then return true end end return false end
local function isPlantPrompt(prompt)
	if not prompt or not prompt.Parent then return false end
	local action = lower(prompt.ActionText)
	local object = lower(prompt.ObjectText)
	for _, kw in ipairs(PromptHeur.promptTextWhitelist) do
		if string.find(action, kw, 1, true) or string.find(object, kw, 1, true) then
			local node = prompt.Parent
			for i=1,4 do if not node then break end; if containsAny(lower(node.Name), PromptHeur.promptBlacklist) then return false end; node = node.Parent end
			return true
		end
	end
	local node = prompt
	for i=1,4 do
		if not node then break end
		local nm = lower(node.Name)
		for _, bad in ipairs(PromptHeur.promptBlacklist) do if string.find(nm, bad, 1, true) then return false end end
		for _, good in ipairs(PromptHeur.plantWhitelist) do if string.find(nm, good, 1, true) then return true end end
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
	local holdDur = (prompt and prompt.HoldDuration) or 0
	local hold = math.max(holdCap or 0.25, 0.12)
	pcall(function()
		if prompt then
			prompt.Enabled = true
			prompt.MaxActivationDistance = 9999
			if prompt.RequiresLineOfSight ~= nil then prompt.RequiresLineOfSight = false end
		end
	end)
	local function tryFPP(arg)
		if not HAS_FIRE_PROX then return false end
		local ok = pcall(function()
			if arg ~= nil then _FPP(prompt, arg) else _FPP(prompt) end
		end)
		return ok
	end
	if HAS_FIRE_PROX then
		if tryFPP(true) or tryFPP(1) or tryFPP(0) or tryFPP(nil) then
			if holdDur and holdDur > 0 then task.wait(math.min(hold, holdDur)); tryFPP(true) end
			return
		end
	end
	pcall(function() if prompt then prompt.HoldDuration = 0 end end)
	VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game); task.wait(0.04)
	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

-- === Routine de harvest pour FARM AUTO (annulable) ===
local function performTimedHarvest(seconds, radius, holdCap, token)
	local dur = math.clamp(math.floor(tonumber(seconds) or 3), 1, 5) -- borne 1..5 (FARM AUTO)
	local r   = math.max(10, tonumber(radius)  or 26)
	local hc  = tonumber(holdCap) or 0.25
	local stopAt = os.clock() + dur
	local total = 0
	while os.clock() < stopAt do
		if token ~= farmAutoToken or not farmAutoEnabled then break end
		local prompts = getNearbyPlantPrompts(r, true)
		for _, p in ipairs(prompts) do
			if token ~= farmAutoToken or not farmAutoEnabled then break end
			safeFirePrompt(p, hc)
			total += 1
		end
		task.wait(0.12)
	end
	return total
end

-- =========================================================
-- =================== AUTO HARVEST v2.4 ===================
-- =========================================================
local AutoHarv24 = {
	enabled = false,
	uiBtn   = nil,
	config  = { radius=26, tick=0.12, holdCap=0.25, spamE=false, stopWhenBackpackFull=true },
}
function AutoHarv24:start()
	if self.enabled then return end
	self.enabled = true
	local runSecs = math.clamp(math.floor(harv24DurationSeconds or 3), 1, 6)
	if self.uiBtn and self.uiBtn.Parent then
		self.uiBtn.BackgroundColor3=Color3.fromRGB(100,180,80)
		self.uiBtn.Text=("🌾 Auto Harvest v2.4: ON  • r=%d • %ds"):format(self.config.radius, runSecs)
	end
	msg("🌾 AutoHarvest v2.4 ON.", Color3.fromRGB(180,230,180))

	-- Boucle limitée par le slider (1–6s) + conditions d’arrêt
	local stopAt = os.clock() + runSecs
	task.spawn(function()
		while self.enabled do
			-- arrêt durée
			if os.clock() >= stopAt then
				self:stop("durée atteinte")
				break
			end
			-- arrêt backpack plein (option)
			if self.config.stopWhenBackpackFull then
				local full, c, m = isBackpackFull()
				if full then
					self:stop(("MAX BACKPACK SPACE (%s/%s)"):format(tostring(c or "?"), tostring(m or "?")))
					break
				end
			end
			-- récolte proche
			local prompts = getNearbyPlantPrompts(self.config.radius, true)
			for _, prompt in ipairs(prompts) do
				if not self.enabled then break end
				safeFirePrompt(prompt, self.config.holdCap)
			end
			-- spam E optionnel
			if self.config.spamE then
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game); task.wait(0.03)
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
	if reason and reason ~= "" then
		msg("🌾 AutoHarvest v2.4 OFF — "..tostring(reason)..".", Color3.fromRGB(230,200,180))
	else
		msg("🌾 AutoHarvest v2.4 OFF.", Color3.fromRGB(230,200,180))
	end
end

-- =========================================================
-- =============== AUTO HARVEST v5.5 (avec Halloween) ======
-- =========================================================
local AutoHarv5 = { }
do
	local function containsAnyStrict(s, list) for _,w in ipairs(list) do if s:find(w, 1, true) then return true end end return false end

	local CONFIG = {
		SCAN_INTERVAL_NORMAL = 0.12,
		SCAN_INTERVAL_TURBO  = 0.020,
		HARVEST_BURST        = 3,
		MAX_PER_SCAN         = 24,
		RUN_LIMIT            = 200,
		SCAN_RADIUS          = 200,
	}

	local FRUIT_KEYWORDS = { "berry","mushroom","pumpkin","apple","grape","melon","corn","tomato","carrot","coconut","cactus","dragon","mango","pepper","cacao","bean","bamboo","vine","root","strawberry","blueberry","watermelon","romanesco","pinecone","lily","tulip","thorn","bud" }
	local NEG_ACTION     = { "buy","sell","open","talk","upgrade","use","feed","place","equip","shop" }
	local HALLOWEEN_KEYS = {
		"banesberry","bloodred mushroom","blood-red mushroom","blood red mushroom","chicken feed",
		"ghoul root","ghoulroot","great pumpkin","jack-o-lantern","jack o lantern","jack-o’-lantern","jack o’ lantern",
		"poison apple","poisoned apple","seer vine","seervine"
	}

	local STATE = {
		enabled = false,
		turbo = true,
		halloweenOnly = false,
		stats = { scanned = 0, harvested = 0 },
		runCount = 0,
		runLimit = CONFIG.RUN_LIMIT,
		scanRadius = CONFIG.SCAN_RADIUS,
		ALL_PROMPTS = {},
		IS_IN_SET = {},
		ui = nil,
	}

	local function labelFor(pp)
		local names = {}
		if pp.Parent then names[#names+1] = pp.Parent.Name end
		if pp.Parent and pp.Parent.Parent then names[#names+1] = pp.Parent.Parent.Name end
		local best = ""
		for _,s in ipairs(names) do if #s > #best then best = s end end
		return (best ~= "" and best) or (pp.ObjectText ~= "" and pp.ObjectText) or (pp.ActionText ~= "" and pp.ActionText) or "Unknown"
	end

	local function passHalloween(pp)
		if not STATE.halloweenOnly then return true end
		local obj = (pp.ObjectText or ""):lower()
		local lbl = labelFor(pp):lower()
		for _,k in ipairs(HALLOWEEN_KEYS) do
			if obj:find(k,1,true) or lbl:find(k,1,true) then return true end
		end
		return false
	end

	local function isHarvestPrompt(pp)
		if not (pp and pp:IsA("ProximityPrompt") and pp.Enabled) then return false end
		local action = (pp.ActionText or ""):lower()
		local object = (pp.ObjectText or ""):lower()
		if action == "" and object == "" then object = labelFor(pp):lower() end
		if containsAnyStrict(action, NEG_ACTION) or containsAnyStrict(object, NEG_ACTION) then return false end
		if action:find("harvest", 1, true) then
			return passHalloween(pp)
		end
		if action:find("collect", 1, true) or action:find("pick", 1, true) or action:find("gather", 1, true) then
			local l = (object ~= "" and object) or labelFor(pp):lower()
			local isFruitLike = containsAnyStrict(l, FRUIT_KEYWORDS)
			if not isFruitLike then return false end
			return passHalloween(pp)
		end
		return false
	end

	for _,d in ipairs(Workspace:GetDescendants()) do if d:IsA("ProximityPrompt") then STATE.IS_IN_SET[d]=true; table.insert(STATE.ALL_PROMPTS, d) end end
	Workspace.DescendantAdded:Connect(function(inst) if inst:IsA("ProximityPrompt") then STATE.IS_IN_SET[inst]=true; table.insert(STATE.ALL_PROMPTS, inst) end end)
	Workspace.DescendantRemoving:Connect(function(inst) if inst:IsA("ProximityPrompt") then STATE.IS_IN_SET[inst]=nil end end)

	local function firePrompt(pp)
		pcall(function() pp.HoldDuration = 0; pp.RequiresLineOfSight = false; pp.MaxActivationDistance = math.huge end)
		local ok = false
		if typeof(fireproximityprompt) == "function" then
			ok = pcall(fireproximityprompt, pp, 1)
			if not ok then ok = pcall(fireproximityprompt, pp) end
		end
		if not ok then
			pcall(function() pp.Enabled = false; task.wait(); pp.Enabled = true end)
			ok = true
		end
		return ok
	end
	local function confirmSuccess(pp)
		local beforeParent = pp.Parent
		local beforeEnabled = pp.Enabled
		task.wait(0.06)
		if not pp.Parent then return true end
		if not pp:IsDescendantOf(Workspace) then return true end
		if beforeEnabled and not pp.Enabled then return true end
		if beforeParent ~= pp.Parent then return true end
		return false
	end
	local function tryHarvest(pp)
		if not (pp and pp.Parent) then return false end
		for _=1, CONFIG.HARVEST_BURST do firePrompt(pp) end
		if confirmSuccess(pp) then STATE.stats.harvested += 1; STATE.runCount += 1; return true end
		return false
	end

	local function gather()
		local hrp = getHRP(); if not hrp then return {} end
		local list = {}
		local radius = STATE.scanRadius
		for i = #STATE.ALL_PROMPTS, 1, -1 do
			local pp = STATE.ALL_PROMPTS[i]
			if not STATE.IS_IN_SET[pp] or not (pp and pp.Parent) then
				table.remove(STATE.ALL_PROMPTS, i)
			else
				if isHarvestPrompt(pp) then
					local root = pp.Parent
					local pos
					if root:IsA("BasePart") then pos = root.Position
					else
						local bp = root:FindFirstChildWhichIsA("BasePart") or (root.Parent and root.Parent:FindFirstChildWhichIsA("BasePart"))
						pos = bp and bp.Position or hrp.Position
					end
					local dd = (hrp.Position - pos).Magnitude
					if dd <= radius then list[#list+1] = {pp = pp, dd = dd} end
				end
			end
		end
		table.sort(list, function(a,b) return a.dd < b.dd end)
		local out = {}
		local cap = math.min(CONFIG.MAX_PER_SCAN, #list)
		for i=1, cap do out[#out+1] = list[i].pp end
		STATE.stats.scanned = #out
		return out
	end

	local running = false
	local function mainLoop()
		if running then return end
		running = true
		while STATE.enabled do
			if STATE.runCount >= STATE.runLimit then
				STATE.enabled = false
				break
			end
			local list = gather()
			for _,pp in ipairs(list) do task.spawn(function() pcall(tryHarvest, pp) end) end
			task.wait(STATE.turbo and CONFIG.SCAN_INTERVAL_TURBO or CONFIG.SCAN_INTERVAL_NORMAL)
		end
		running = false
	end

	function AutoHarv5.isEnabled() return STATE.enabled end
	function AutoHarv5.start() if not STATE.enabled then STATE.enabled=true; STATE.runCount=0; task.spawn(mainLoop) end end
	function AutoHarv5.stop()  if STATE.enabled then STATE.enabled=false end end

	-- ========= UI DÉDIÉE v5.5 (with Halloween toggle) =========
	local function buildUI()
		if STATE.ui and STATE.ui.Parent then STATE.ui.Enabled = true; return STATE.ui end
		local gui = Instance.new("ScreenGui"); gui.Name = "Saad_AutoHarvest_v55"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.Parent = playerGui
		applyAutoScale(gui)

		local frame = Instance.new("Frame"); frame.Size = UDim2.new(0, 348, 0, 246); frame.Position = UDim2.new(0, 20, 0, 80); frame.BackgroundColor3 = Color3.fromRGB(22,22,26); frame.BorderSizePixel = 0; frame.Parent = gui
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

		local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -40, 0, 28); title.Position = UDim2.new(0, 12, 0, 6); title.Text = "🌾 Auto-Harvest v5.5"; title.TextColor3 = Color3.fromRGB(235,235,245); title.Font = Enum.Font.GothamBold; title.TextXAlignment = Enum.TextXAlignment.Left; title.TextSize = 18; title.Parent = frame

		local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0, 28, 0, 28); closeBtn.Position = UDim2.new(1, -32, 0, 6); closeBtn.BackgroundColor3 = Color3.fromRGB(45,45,55); closeBtn.Text = "✕"; closeBtn.TextColor3 = Color3.fromRGB(235,235,245); closeBtn.Font = Enum.Font.Gotham; closeBtn.TextSize = 16; closeBtn.Parent = frame
		Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,8)
		closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

		makeDraggable(frame, frame)

		local function toggleRow(y, label, default, cb)
			local holder = Instance.new("Frame"); holder.Size = UDim2.new(1, -24, 0, 28); holder.Position = UDim2.new(0, 12, 0, y); holder.BackgroundTransparency = 1; holder.Parent = frame
			local btn = Instance.new("TextButton"); btn.Size = UDim2.new(0, 28, 0, 28); btn.BackgroundColor3 = default and Color3.fromRGB(73,167,88) or Color3.fromRGB(70,70,78); btn.Text = ""; btn.Parent = holder; Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
			local lb = Instance.new("TextLabel"); lb.Size = UDim2.new(1, -40, 1, 0); lb.Position = UDim2.new(0, 40, 0, 0); lb.BackgroundTransparency = 1; lb.Text = label; lb.TextColor3 = Color3.fromRGB(220,220,230); lb.Font = Enum.Font.Gotham; lb.TextXAlignment = Enum.TextXAlignment.Left; lb.TextSize = 16; lb.Parent = holder
			local state = default
			btn.MouseButton1Click:Connect(function() state = not state; btn.BackgroundColor3 = state and Color3.fromRGB(73,167,88) or Color3.fromRGB(70,70,78); pcall(cb, state) end)
			pcall(cb, default)
			return holder
		end

		local y = 40
		toggleRow(y, "Activer Auto-Harvest", false, function(on) if on then AutoHarv5.start() else AutoHarv5.stop() end end); y = y + 32
		toggleRow(y, "Mode Turbo (cadence ++)", true, function(on) STATE.turbo = on end); y = y + 32
		toggleRow(y, "Harvest Halloween ONLY", false, function(on) STATE.halloweenOnly = on end); y = y + 32

		STATE.ui = gui
		return gui
	end

	function AutoHarv5.openUI()
		local g = buildUI()
		if g then g.Enabled = true end
	end
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
	applyAutoScale(gui)

	local frame = Instance.new("Frame")
	local MINI_FULL   = UDim2.fromOffset(400, 660)
	local MINI_COLLAP = UDim2.fromOffset(400, 36)
	frame.Size = MINI_FULL
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
	title.Size = UDim2.new(1, -120, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "⚙️ Saad Mini Panel — v3.8"
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

	local minBtn = Instance.new("TextButton")
	minBtn.Size = UDim2.fromOffset(26, 26)
	minBtn.Position = UDim2.new(1, -62, 0.5, -13)
	minBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
	minBtn.TextColor3 = Color3.fromRGB(255,255,255)
	minBtn.Text = "▭"
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.Parent = header
	rounded(minBtn, 6)

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -14, 1, -46)
	container.Position = UDim2.new(0, 7, 0, 42)
	container.BackgroundTransparency = 1
	container.Parent = frame

	makeDraggable(frame, header)

	local miniCollapsed = false
	local function toggleMini()
		miniCollapsed = not miniCollapsed
		if miniCollapsed then
			container.Visible = false
			TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = MINI_COLLAP}):Play()
		else
			TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = MINI_FULL}):Play()
			task.delay(0.2, function() container.Visible = true end)
		end
	end
	minBtn.MouseButton1Click:Connect(toggleMini)

	-- Row 1 : AutoHarvest v5.5 + Submit Cauldron
	local row1 = Instance.new("Frame"); row1.Size = UDim2.new(1, 0, 0, 40); row1.BackgroundTransparency = 1; row1.Parent = container
	local btnAutoV5 = Instance.new("TextButton")
	btnAutoV5.Size = UDim2.new(0.48, -4, 1, 0); btnAutoV5.Position = UDim2.new(0, 0, 0, 0)
	btnAutoV5.BackgroundColor3 = Color3.fromRGB(200, 120, 60); btnAutoV5.TextColor3 = Color3.fromRGB(255,255,255)
	btnAutoV5.Text = "🌾 Auto Harvest v5.5: OFF"; btnAutoV5.Font = Enum.Font.GothamBold; btnAutoV5.TextSize = 13; btnAutoV5.Parent = row1; rounded(btnAutoV5, 8)

	local btnSubmit = Instance.new("TextButton")
	btnSubmit.Size = UDim2.new(0.52, 0, 1, 0); btnSubmit.Position = UDim2.new(0.48, 4, 0, 0)
	btnSubmit.BackgroundColor3 = Color3.fromRGB(140, 110, 200); btnSubmit.TextColor3 = Color3.fromRGB(255,255,255)
	btnSubmit.Text = "🧪 Submit All (Cauldron)"
	btnSubmit.Font = Enum.Font.GothamBold
	btnSubmit.TextSize = 13
	btnSubmit.Parent = row1
	rounded(btnSubmit, 8)

	btnSubmit.MouseButton1Click:Connect(function()
		submitAllCauldron_Robust()
	end)

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

	-- Row 3 : 🎃 Submit Jack O Lantern
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

	-- PETS / EGGS (exact "Creepy Critters")
	local petsTitle = Instance.new("TextLabel")
	petsTitle.Size = UDim2.new(1, 0, 0, 20)
	petsTitle.Position = UDim2.new(0, 0, 0, 250)
	petsTitle.BackgroundTransparency = 1
	petsTitle.TextXAlignment = Enum.TextXAlignment.Left
	petsTitle.Text = "🎃 EVENT PETS / EGGS — (Creepy Critters)"
	petsTitle.TextColor3 = Color3.fromRGB(255,235,180)
	petsTitle.Font = Enum.Font.GothamBold
	petsTitle.TextSize = 13
	petsTitle.Parent = container

	local petsGrid = Instance.new("Frame")
	petsGrid.Size = UDim2.new(1, 0, 0, 100)
	petsGrid.Position = UDim2.new(0, 0, 0, 272)
	petsGrid.BackgroundTransparency = 1
	petsGrid.Parent = container

	local function mkPetBtn(xScale, yOff, label)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.48, -4, 0, 30)
		b.Position = UDim2.new(xScale, xScale==0 and 0 or 4, 0, yOff)
		b.BackgroundColor3 = Color3.fromRGB(95, 140, 200)
		b.TextColor3 = Color3.fromRGB(255,255,255)
		b.Text = "🛒 "..label.." (Creepy Critters)"
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.Parent = petsGrid
		rounded(b, 8)
		b.MouseButton1Click:Connect(function()
			b.AutoButtonColor=false; b.BackgroundColor3=Color3.fromRGB(75, 110, 160)
			task.spawn(function()
				local r = safeWait({"GameEvents","BuyEventShopStock"},2)
				if not r or not r:IsA("RemoteEvent") then
					msg("Remote BuyEventShopStock introuvable.", Color3.fromRGB(255,120,120))
				else
					local okAny=false
					for i=1,4 do
						local ok, _ = pcall(function()
							r:FireServer(label, "Creepy Critters")
						end)
						if ok then okAny=true; msg("🛍️ Achat: "..label.." (Creepy Critters) ✓", Color3.fromRGB(180,230,180)); break
						else task.wait(0.05) end
					end
					if not okAny then msg("⚠️ Achat échec: "..label.." (Creepy Critters)", Color3.fromRGB(255,160,140)) end
				end
			end)
			task.delay(0.25, function() b.AutoButtonColor=true; b.BackgroundColor3=Color3.fromRGB(95, 140, 200) end)
		end)
	end
	mkPetBtn(0.00, 0,  "Wolf")
	mkPetBtn(0.52, 0,  "Spooky Egg")
	mkPetBtn(0.00, 34, "Reaper")
	mkPetBtn(0.52, 34, "Ghost Bear")
	mkPetBtn(0.00, 68, "Pumpkin Rat")

	-- Row Auto v2.4 + hint
	local row4 = Instance.new("Frame"); row4.Size = UDim2.new(1, 0, 0, 70); row4.Position = UDim2.new(0, 0, 0, 380); row4.BackgroundTransparency = 1; row4.Parent = container
	local btnAutoV24 = Instance.new("TextButton")
	btnAutoV24.Size = UDim2.new(1, 0, 0, 32)
	btnAutoV24.BackgroundColor3 = Color3.fromRGB(200,120,60)
	btnAutoV24.TextColor3 = Color3.fromRGB(255,255,255)
	btnAutoV24.Text = "🌾 Auto Harvest v2.4: OFF"
	btnAutoV24.Font = Enum.Font.GothamBold
	btnAutoV24.TextSize = 13
	btnAutoV24.Parent = row4
	rounded(btnAutoV24, 8)
	AutoHarv24.uiBtn = btnAutoV24  -- 🔧 lie le bouton à v2.4 (pour le texte/couleur)

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 26)
	hint.Position = UDim2.new(0, 0, 0, 38)
	hint.BackgroundTransparency = 1
	hint.Text = "Raccourcis: H = v2.4 • J = v5.5 (turbo + stop 200)"
	hint.TextColor3 = Color3.fromRGB(160, 200, 255)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.Parent = row4

	-- 🔧 Slider v2.4 (1–6s) — juste sous le bouton
	local v24SliderRow = Instance.new("Frame"); v24SliderRow.Size = UDim2.new(1, 0, 0, 60); v24SliderRow.Position = UDim2.new(0, 0, 0, 420); v24SliderRow.BackgroundTransparency = 1; v24SliderRow.Parent = container
	local v24Slider = createSlider(v24SliderRow, 0, "🌾 v2.4 Run Duration (1–6s)", 1, 6, 1, harv24DurationSeconds, function(v)
		harv24DurationSeconds = v
		if AutoHarv24.enabled and AutoHarv24.uiBtn and AutoHarv24.uiBtn.Parent then
			AutoHarv24.uiBtn.Text=("🌾 Auto Harvest v2.4: ON  • r=%d • %ds"):format(AutoHarv24.config.radius, v)
		end
	end, 0)

	-- ===== Sliders FARM AUTO =====
	local slidersRow = Instance.new("Frame"); slidersRow.Size = UDim2.new(1, 0, 0, 120); slidersRow.Position = UDim2.new(0, 0, 0, 480); slidersRow.BackgroundTransparency = 1; slidersRow.Parent = container
	local harvestSlider = createSlider(slidersRow, 0,   "🌀 Harvest Duration (1–5s)",  1, 5, 1, farmHarvestSeconds, function(v) farmHarvestSeconds = v end, 0)
	local waitSlider    = createSlider(slidersRow, 60,  "⏳ Wait After Submit (3–50s)", 3, 50,1, farmWaitSeconds,    function(v) farmWaitSeconds = v end, 0)

	-- ===== FARM AUTO Button (Submit → Harvest → Submit → Wait) =====
	local rowAuto = Instance.new("Frame"); rowAuto.Size = UDim2.new(1, 0, 0, 40); rowAuto.Position = UDim2.new(0, 0, 0, 600); rowAuto.BackgroundTransparency = 1; rowAuto.Parent = container
	local farmAutoBtn = Instance.new("TextButton")
	farmAutoBtn.Size = UDim2.new(1, 0, 1, 0)
	farmAutoBtn.BackgroundColor3 = Color3.fromRGB(90, 160, 90)
	farmAutoBtn.TextColor3 = Color3.fromRGB(255,255,255)
	local function refreshFarmBtnText()
		farmAutoBtn.Text = string.format("🌀 FARM AUTO: %s  (Submit → Harvest %ds → Submit → Wait %ds)", farmAutoEnabled and "ON" or "OFF", farmHarvestSeconds, farmWaitSeconds)
	end
	refreshFarmBtnText()
	farmAutoBtn.Font = Enum.Font.GothamBold
	farmAutoBtn.TextSize = 13
	farmAutoBtn.Parent = rowAuto
	rounded(farmAutoBtn, 8)

	-- Annulation / OFF immédiat
	local function stopFarmAuto()
		if not farmAutoEnabled then return end
		farmAutoEnabled = false
		farmAutoToken += 1
		if farmAutoThread then
			pcall(function() task.cancel(farmAutoThread) end)
			farmAutoThread = nil
		end
		farmAutoBtn.BackgroundColor3 = Color3.fromRGB(90,160,90)
		refreshFarmBtnText()
		msg("🌀 FARM AUTO OFF.", Color3.fromRGB(230,200,180))
	end
	local function startFarmAuto()
		if farmAutoEnabled then return end
		farmAutoEnabled = true
		local myToken = farmAutoToken + 1; farmAutoToken = myToken
		farmAutoBtn.BackgroundColor3 = Color3.fromRGB(80,180,100)
		refreshFarmBtnText()
		msg("🌀 FARM AUTO ON.", Color3.fromRGB(180,230,180))
		farmAutoThread = task.spawn(function()
			while farmAutoEnabled and myToken == farmAutoToken do
				-- 0) Submit All (avant de commencer)
				if not farmAutoEnabled or myToken ~= farmAutoToken then break end
				submitAllCauldron_Robust()
				if not farmAutoEnabled or myToken ~= farmAutoToken then break end

				-- 1) Harvest (slider 1–5s)
				local harvested = performTimedHarvest(farmHarvestSeconds, 26, 0.25, myToken)
				if not farmAutoEnabled or myToken ~= farmAutoToken then break end
				if harvested <= 0 then
					msg("🌾 Peu/aucun prompt récolté — retry court (1s)…", Color3.fromRGB(255,200,150))
					performTimedHarvest(1, 26, 0.25, myToken)
					if not farmAutoEnabled or myToken ~= farmAutoToken then break end
				end

				-- 2) Submit All (après harvest)
				submitAllCauldron_Robust()
				if not farmAutoEnabled or myToken ~= farmAutoToken then break end

				-- 3) Pause (slider 3–50s) avec checks fréquents
				local t = math.clamp(math.floor(farmWaitSeconds), 3, 50)
				for i=1, t do
					if not farmAutoEnabled or myToken ~= farmAutoToken then break end
					task.wait(1)
				end
			end
		end)
	end

	farmAutoBtn.MouseButton1Click:Connect(function()
		if farmAutoEnabled then stopFarmAuto() else startFarmAuto() end
	end)

	-- Bind mini actions
	btnAutoV24.MouseButton1Click:Connect(function() if AutoHarv24.enabled then AutoHarv24:stop() else AutoHarv24:start() end end)
	btnAutoV5.MouseButton1Click:Connect(function()
		if AutoHarv5.isEnabled() then
			AutoHarv5.stop()
			btnAutoV5.BackgroundColor3 = Color3.fromRGB(200,120,60)
			btnAutoV5.Text = "🌾 Auto Harvest v5.5: OFF"
		else
			AutoHarv5.start()
			btnAutoV5.BackgroundColor3 = Color3.fromRGB(100,180,80)
			btnAutoV5.Text = "🌾 Auto Harvest v5.5: ON"
		end
	end)

	applyAutoScale(gui)
	miniPanelGui = gui
	return gui
end

-- Ouvreurs
openV5Btn.MouseButton1Click:Connect(function() AutoHarv5.openUI() end)
openMiniBtn.MouseButton1Click:Connect(function() local g = buildMiniPanel(); g.Enabled = not g.Enabled end)

-- =========================================================
-- ===================== HOTKEYS ===========================
-- =========================================================
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.H then
		if AutoHarv24.enabled then AutoHarv24:stop() else AutoHarv24:start() end
	elseif input.KeyCode == Enum.KeyCode.J then
		if AutoHarv5.isEnabled() then AutoHarv5.stop() else AutoHarv5.start() end
	end
end)

-- Ready
msg("✅ Saad Helper Pack chargé • UIs déplaçables • v2.4 durée (1–6s) OK • FARM AUTO (Submit→Harvest→Submit→Wait) + OFF instantané • Pets/Eggs 'Creepy Critters' OK.", Color3.fromRGB(170,230,255))
