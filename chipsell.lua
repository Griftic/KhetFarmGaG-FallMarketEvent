--[[
  🐿️ Chipmunk Seller — v1.6 HOLD-TO-SELL + NIL
  • Scanne les "Idol Chipmunk ..." / "Farmer Chipmunk ..." (Backpack + Character).
  • VEND ainsi:
      1) (HOLD ON) Équipe d'abord le Tool par NOM EXACT (Backpack -> Character), en main.
      2) (NIL ON) Récupère l'instance via getnilinstances() par NOM EXACT.
         (NIL OFF) Utilise l'instance tenue/en sac.
      3) SellPet_RE:FireServer(unpack({[1]=Tool}))
  • UI simple + toggles en header: NIL (ON par défaut), HOLD (ON par défaut).
  • Boutons: Select/Deselect All, Refresh, Sell Selected, Sell par ligne, Minimize, Close.
]]--

-- ===== BOOT SAFE =====
local function waitGame()
	if game.IsLoaded and game:IsLoaded() then return end
	repeat task.wait(0.03) until game:IsLoaded()
end
waitGame()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer
repeat LocalPlayer = Players.LocalPlayer; task.wait() until LocalPlayer

-- Parent UI sûr
local function getGuiParent()
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then pg = LocalPlayer:WaitForChild("PlayerGui", 5) end
	if pg then return pg end
	local core; pcall(function() core = game:FindFirstChildOfClass("CoreGui") end)
	return core or LocalPlayer:WaitForChild("PlayerGui")
end
local GuiParent = getGuiParent()

-- Nettoyer ancienne UI
for _, gui in ipairs(GuiParent:GetChildren()) do
	if gui:IsA("ScreenGui") and gui.Name == "ChipmunkSellerUI" then gui:Destroy() end
end

-- ===== UTILS =====
local hasGetNil = (getnilinstances and typeof(getnilinstances) == "function") or false
local USE_NIL_MODE   = true   -- 💡 utilise getnilinstances() pour la vente
local HOLD_TO_SELL   = true   -- 💡 équipe d'abord le Tool avant la vente

local function safeIsA(inst, className)
	return typeof(inst) == "Instance" and inst.ClassName == className
end

local function isChipmunkName(name)
	if typeof(name) ~= "string" then return false end
	if string.find(name, "^Idol Chipmunk")   then return true, "Idol"   end
	if string.find(name, "^Farmer Chipmunk") then return true, "Farmer" end
	return false
end

-- Trouver Tool exact dans Backpack/Character
local function getToolExact_BagChar(name)
	if typeof(name) ~= "string" then return nil end
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then
		local t = bp:FindFirstChild(name)
		if safeIsA(t,"Tool") then return t end
	end
	local char = LocalPlayer.Character
	if char then
		local t = char:FindFirstChild(name)
		if safeIsA(t,"Tool") then return t end
	end
	return nil
end

-- getnilinstances pour récupérer l'instance par nom exact (si dispo)
local function getToolExact_Nil(name)
	if not hasGetNil or typeof(name) ~= "string" then return nil end
	for _, it in next, getnilinstances() do
		if typeof(it)=="Instance" and safeIsA(it,"Tool") and it.Name == name then
			return it
		end
	end
	return nil
end

-- Équipe le Tool par nom exact (Backpack -> Character)
local function equipToolByName(name, timeout)
	timeout = timeout or 2.0
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 2)

	-- déjà en main ?
	local held = char:FindFirstChild(name)
	if held and safeIsA(held,"Tool") then return held end

	local bp = LocalPlayer:FindFirstChild("Backpack")
	local tool = bp and bp:FindFirstChild(name)
	if not tool or not safeIsA(tool,"Tool") then
		-- si pas dans le sac, peut-être déjà au character (non "held")
		tool = char:FindFirstChild(name)
		if tool and safeIsA(tool,"Tool") then return tool end
	end

	if tool and humanoid then
		pcall(function() humanoid:UnequipTools() end)
		task.wait(0.05)
		pcall(function() humanoid:EquipTool(tool) end)
	end

	-- attendre qu'il soit en main
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local h = char:FindFirstChild(name)
		if h and safeIsA(h,"Tool") then return h end
		task.wait(0.05)
	end

	-- fallback: forcer le parent
	if tool and tool.Parent == bp then
		pcall(function() tool.Parent = char end)
	end
	t0 = os.clock()
	while os.clock() - t0 < 1.0 do
		local h = char:FindFirstChild(name)
		if h and safeIsA(h,"Tool") then return h end
		task.wait(0.05)
	end

	return char:FindFirstChild(name)
end

-- Scan listable (Backpack + Character). On ne liste pas les nil pour éviter les fantômes.
local function scanChipmunks()
	local out, seen = {}, {}
	local function add(inst)
		if not safeIsA(inst,"Tool") then return end
		local ok, kind = isChipmunkName(inst.Name)
		if not ok then return end
		local key = inst.Name .. "::" .. tostring(inst)
		if not seen[key] then
			seen[key] = true
			out[#out+1] = { name = inst.Name, kind = kind, ref = inst }
		end
	end
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then for _, it in ipairs(bp:GetChildren()) do add(it) end end
	local char = LocalPlayer.Character
	if char then for _, it in ipairs(char:GetChildren()) do add(it) end end

	table.sort(out, function(a,b)
		if a.kind == b.kind then return a.name < b.name end
		return a.kind < b.kind
	end)
	return out
end

-- Remote getter
local function getSellRemote()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then return nil end
	return ge:FindFirstChild("SellPet_RE")
end

-- ===== UI =====
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChipmunkSellerUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.DisplayOrder = 99999
ScreenGui.Parent = GuiParent

local function makeCorner(f, r)
	local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 10); c.Parent=f
end

local Window = Instance.new("Frame")
Window.Name = "Window"
Window.Size = UDim2.new(0, 560, 0, 460)
Window.Position = UDim2.new(0.5, -280, 0.5, -230)
Window.BackgroundColor3 = Color3.fromRGB(32, 34, 38)
Window.BorderSizePixel = 0
Window.Parent = ScreenGui
makeCorner(Window, 12)

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 26, 29)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Window

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 10, 0, 0)
Title.Size = UDim2.new(1, -210, 1, 0)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 22
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.Text = "🐿️ Chipmunk Seller (NIL ON • HOLD ON)"
Title.Parent = TitleBar

local function makeHeaderBtn(xOffset, label, w, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w or 58, 0, 28)
	b.Position = UDim2.new(1, -xOffset, 0, 4)
	b.Text = label
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 18
	b.TextColor3 = Color3.new(1,1,1)
	b.BackgroundColor3 = color or Color3.fromRGB(70, 75, 85)
	makeCorner(b, 6)
	b.Parent = TitleBar
	return b
end

local BtnClose = makeHeaderBtn(46, "X", 40, Color3.fromRGB(200,70,70))
local BtnMin   = makeHeaderBtn(92, "–", 40, Color3.fromRGB(70,75,85))
local BtnHold  = makeHeaderBtn(160, "HOLD", 58, HOLD_TO_SELL and Color3.fromRGB(115,173,255) or Color3.fromRGB(70,75,85))
local BtnNil   = makeHeaderBtn(224, "NIL", 58, USE_NIL_MODE and Color3.fromRGB(115,173,255) or Color3.fromRGB(70,75,85))

local Controls = Instance.new("Frame")
Controls.Position = UDim2.new(0, 10, 0, 44)
Controls.Size = UDim2.new(1, -20, 0, 32)
Controls.BackgroundTransparency = 1
Controls.Parent = Window

local function makeBtn(parent, x, label, w, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w or 120, 1, 0)
	b.Position = UDim2.new(0, x, 0, 0)
	b.Font = Enum.Font.SourceSans
	b.TextSize = 20
	b.TextColor3 = Color3.fromRGB(245,245,245)
	b.BackgroundColor3 = col or Color3.fromRGB(58,62,70)
	b.Text = label
	makeCorner(b, 6)
	b.Parent = parent
	return b
end
local BtnSelectAll   = makeBtn(Controls, 0,   "Select All",    120)
local BtnDeselectAll = makeBtn(Controls, 130, "Deselect All",  130)
local BtnRefresh     = makeBtn(Controls, 270, "Refresh",       100)
local BtnSell        = makeBtn(Controls, 380, "Sell Selected", 160, Color3.fromRGB(80,165,120))

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.new(0, 10, 0, 82)
Status.Size = UDim2.new(1, -20, 0, 22)
Status.Font = Enum.Font.SourceSans
Status.TextSize = 20
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextColor3 = Color3.fromRGB(200, 205, 210)
Status.Text = "UI loaded ✓ — Refresh to scan."
Status.Parent = Window

local Scroll = Instance.new("ScrollingFrame")
Scroll.Position = UDim2.new(0, 10, 0, 110)
Scroll.Size = UDim2.new(1, -20, 1, -140)
Scroll.BackgroundColor3 = Color3.fromRGB(24, 25, 28)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 8
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
makeCorner(Scroll, 8)
Scroll.Parent = Window

local UIL = Instance.new("UIListLayout")
UIL.Parent = Scroll
UIL.Padding = UDim.new(0, 6)
UIL.SortOrder = Enum.SortOrder.LayoutOrder

local Empty = Instance.new("TextLabel")
Empty.BackgroundTransparency = 1
Empty.Size = UDim2.new(1, -10, 0, 28)
Empty.Position = UDim2.new(0, 5, 0, 0)
Empty.Font = Enum.Font.SourceSansItalic
Empty.TextSize = 18
Empty.TextColor3 = Color3.fromRGB(180, 185, 190)
Empty.Text = "No chipmunks found."
Empty.Visible = false
Empty.Parent = Scroll

local Bubble = Instance.new("TextButton")
Bubble.Visible = false
Bubble.Size = UDim2.new(0, 52, 0, 52)
Bubble.Position = UDim2.new(0, 20, 1, -72)
Bubble.AnchorPoint = Vector2.new(0,0)
Bubble.Text = "🐿️"
Bubble.Font = Enum.Font.SourceSansBold
Bubble.TextSize = 28
Bubble.TextColor3 = Color3.new(1,1,1)
Bubble.BackgroundColor3 = Color3.fromRGB(115, 173, 255)
makeCorner(Bubble, 26)
Bubble.Parent = ScreenGui

-- Drag simple
do
	local dragging=false; local startPos; local dragStart
	TitleBar.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
			dragging=true; startPos=Window.Position; dragStart=input.Position
			input.Changed:Connect(function()
				if input.UserInputState==Enum.UserInputState.End then dragging=false end
			end)
		end
	end)
	TitleBar.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			Window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- ===== SELECTION =====
local selection = {} -- key -> bool
local itemsMap  = {} -- key -> {name, kind, ref}
local function keyFor(item) return item.name .. "::" .. tostring(item.ref or item.name) end

local function clearRows()
	for _, ch in ipairs(Scroll:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
end

-- Core: vendre (équipe si HOLD, puis vend; NIL ou BAG)
local function sellByName(name)
	local remote = getSellRemote()
	if not remote then Status.Text = "Remote not found (SellPet_RE)."; return false end

	-- 1) HOLD : équipe le tool par nom exact
	local heldTool = nil
	if HOLD_TO_SELL then
		heldTool = equipToolByName(name, 2.0) -- essaie ~2s
		if not (heldTool and safeIsA(heldTool,"Tool")) then
			Status.Text = "[HOLD] Could not equip: "..name
			return false
		end
	end

	-- 2) Résolution finale de l'instance à envoyer
	local toolToSend
	if USE_NIL_MODE then
		toolToSend = getToolExact_Nil(name) or heldTool or getToolExact_BagChar(name)
	else
		toolToSend = heldTool or getToolExact_BagChar(name) or getToolExact_Nil(name)
	end
	if not toolToSend then
		Status.Text = (USE_NIL_MODE and "[NIL] Not found: " or "[BAG] Not found: ")..name
		return false
	end

	-- 3) Appel remote EXACT comme ton snippet
	local args = { [1] = toolToSend }
	local ok, err = pcall(function()
		remote:FireServer(unpack(args))
	end)
	if not ok then
		Status.Text = "Error on "..name..": "..tostring(err)
		return false
	end
	return true
end

local function makeRow(item)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 42)
	row.BackgroundColor3 = Color3.fromRGB(36, 38, 43)
	row.BorderSizePixel = 0
	makeCorner(row, 8)
	row.Parent = Scroll

	local key = keyFor(item)
	itemsMap[key] = item
	if selection[key] == nil then selection[key] = false end

	local Box = Instance.new("TextButton")
	Box.Size = UDim2.new(0, 26, 0, 26)
	Box.Position = UDim2.new(0, 8, 0.5, -13)
	Box.Text = ""
	Box.BackgroundColor3 = selection[key] and Color3.fromRGB(115,173,255) or Color3.fromRGB(55,58,65)
	makeCorner(Box, 6)
	Box.Parent = row

	local Tick = Instance.new("TextLabel")
	Tick.BackgroundTransparency = 1
	Tick.Size = UDim2.new(1, 0, 1, 0)
	Tick.Text = "✓"
	Tick.Font = Enum.Font.SourceSansBold
	Tick.TextSize = 20
	Tick.TextColor3 = Color3.new(1,1,1)
	Tick.Visible = selection[key]
	Tick.Parent = Box

	local Name = Instance.new("TextLabel")
	Name.BackgroundTransparency = 1
	Name.Position = UDim2.new(0, 44, 0, 0)
	Name.Size = UDim2.new(1, -200, 1, 0)
	Name.Font = Enum.Font.SourceSans
	Name.TextSize = 18
	Name.TextXAlignment = Enum.TextXAlignment.Left
	Name.TextColor3 = Color3.fromRGB(235,235,240)
	Name.Text = "["..item.kind.."] "..item.name.."  ("..(USE_NIL_MODE and "NIL" or "BAG")..", "..(HOLD_TO_SELL and "HOLD" or "NO HOLD")..")"
	Name.Parent = row

	local SellOne = Instance.new("TextButton")
	SellOne.Size = UDim2.new(0, 110, 0, 28)
	SellOne.Position = UDim2.new(1, -118, 0.5, -14)
	SellOne.Text = "Equip & Sell"
	SellOne.Font = Enum.Font.SourceSansBold
	SellOne.TextSize = 18
	SellOne.TextColor3 = Color3.new(1,1,1)
	SellOne.BackgroundColor3 = Color3.fromRGB(80, 165, 120)
	makeCorner(SellOne, 6)
	SellOne.Parent = row

	local function refresh()
		Box.BackgroundColor3 = selection[key] and Color3.fromRGB(115,173,255) or Color3.fromRGB(55,58,65)
		Tick.Visible = selection[key]
		Name.Text = "["..item.kind.."] "..item.name.."  ("..(USE_NIL_MODE and "NIL" or "BAG")..", "..(HOLD_TO_SELL and "HOLD" or "NO HOLD")..")"
	end

	Box.MouseButton1Click:Connect(function()
		selection[key] = not selection[key]
		refresh()
	end)

	SellOne.MouseButton1Click:Connect(function()
		local ok = sellByName(item.name)
		if ok then
			Status.Text = "Sold: "..item.name
			selection[key] = false
			refresh()
		end
	end)
end

local function populate()
	clearRows()
	Empty.Visible = false
	itemsMap = {}

	local items = scanChipmunks()
	if #items == 0 then
		Empty.Visible = true
		Status.Text = "No chipmunks found."
		return
	end
	for _, it in ipairs(items) do makeRow(it) end
	Status.Text = ("Found %d chipmunk%s. Mode: %s, %s"):format(
		#items, (#items==1 and "" or "s"),
		(USE_NIL_MODE and "NIL" or "BAG"),
		(HOLD_TO_SELL and "HOLD" or "NO HOLD")
	)
end

-- Hooks inventaire
local function hookInv()
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then
		bp.ChildAdded:Connect(function(i) if safeIsA(i,"Tool") then task.wait(0.05) populate() end end)
		bp.ChildRemoved:Connect(function(i) if safeIsA(i,"Tool") then task.wait(0.05) populate() end end)
	end
	if LocalPlayer.Character then
		LocalPlayer.Character.ChildAdded:Connect(function(i) if safeIsA(i,"Tool") then task.wait(0.05) populate() end end)
		LocalPlayer.Character.ChildRemoved:Connect(function(i) if safeIsA(i,"Tool") then task.wait(0.05) populate() end end)
	end
	LocalPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.2)
		char.ChildAdded:Connect(function(i) if safeIsA(i,"Tool") then task.wait(0.05) populate() end end)
		char.ChildRemoved:Connect(function(i) if safeIsA(i,"Tool") then task.wait(0.05) populate() end end)
		populate()
	end)
end
hookInv()

-- Boutons
BtnRefresh.MouseButton1Click:Connect(function()
	Status.Text = "Refreshing..."
	populate()
end)

BtnSelectAll.MouseButton1Click:Connect(function()
	for k,_ in pairs(itemsMap) do selection[k] = true end
	populate()
	Status.Text = "All selected."
end)

BtnDeselectAll.MouseButton1Click:Connect(function()
	for k,_ in pairs(selection) do selection[k] = false end
	populate()
	Status.Text = "Selection cleared."
end)

local selling=false
BtnSell.MouseButton1Click:Connect(function()
	if selling then return end
	local batch = {}
	for k,on in pairs(selection) do if on and itemsMap[k] then table.insert(batch, itemsMap[k]) end end
	if #batch==0 then Status.Text = "Pick at least one chipmunk."; return end

	selling=true
	Status.Text = ("Selling %d selected... (%s, %s)"):format(
		#batch, (USE_NIL_MODE and "NIL" or "BAG"), (HOLD_TO_SELL and "HOLD" or "NO HOLD")
	)
	for i,item in ipairs(batch) do
		local ok = sellByName(item.name)
		if not ok then
			-- Status déjà mis à jour
		end
		task.wait(0.1)
	end
	for _,it in ipairs(batch) do selection[keyFor(it)] = false end
	populate()
	Status.Text = "Done."
	selling=false
end)

-- Minimize / Close
BtnMin.MouseButton1Click:Connect(function()
	Window.Visible = false
	Bubble.Visible = true
end)
Bubble.MouseButton1Click:Connect(function()
	Bubble.Visible = false
	Window.Visible = true
end)
BtnClose.MouseButton1Click:Connect(function()
	ScreenGui:Destroy()
end)

-- Toggles NIL / HOLD
local function refreshHeader()
	BtnNil.BackgroundColor3  = USE_NIL_MODE and Color3.fromRGB(115,173,255) or Color3.fromRGB(70,75,85)
	BtnHold.BackgroundColor3 = HOLD_TO_SELL and Color3.fromRGB(115,173,255) or Color3.fromRGB(70,75,85)
	Title.Text = "🐿️ Chipmunk Seller ("..
		(USE_NIL_MODE and "NIL ON" or "NIL OFF").." • "..
		(HOLD_TO_SELL and "HOLD ON" or "HOLD OFF")..")"
end
BtnNil.MouseButton1Click:Connect(function()
	USE_NIL_MODE = not USE_NIL_MODE
	refreshHeader()
	populate()
end)
BtnHold.MouseButton1Click:Connect(function()
	HOLD_TO_SELL = not HOLD_TO_SELL
	refreshHeader()
	populate()
end)
refreshHeader()

-- Lancer
populate()
