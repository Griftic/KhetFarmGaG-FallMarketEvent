-- GaG — PetMover Controller (Strict PetsPhysical scan + Owner attribute)
-- Trouve tes PetMover dans workspace.PetsPhysical (directs OU imbriqués) si :GetAttribute("Owner") == ton pseudo (ou UserId)
-- Actions : Freeze ici | TP vers moi + Freeze (ultra-serré) | Unfreeze

--=========== Services ===========--
local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local SG      = game:GetService("StarterGui")
local RS      = game:GetService("RunService")

if not game:IsLoaded() then game.Loaded:Wait() end
local LP = Players.LocalPlayer

--=========== Utils ===========--
local function log(...) print("[PetMover]", ...) end
local function notify(msg)
	pcall(function() SG:SetCore("SendNotification", {Title="PetMover", Text=tostring(msg), Duration=2}) end)
	log(msg)
end

local function getChar()
	local ch = LP.Character or LP.CharacterAdded:Wait()
	ch:WaitForChild("HumanoidRootPart"); ch:WaitForChild("Humanoid")
	return ch
end

local function anyCFrame(inst)
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok and typeof(cf)=="CFrame" then return cf end
		if inst.PrimaryPart then return inst.PrimaryPart.CFrame end
		for _,d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then return d.CFrame end
		end
	elseif inst:IsA("BasePart") then
		return inst.CFrame
	else
		for _,d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then return d.CFrame end
		end
	end
	return CFrame.new()
end

local function pivotTo(root, cf)
	if root:IsA("Model") then
		local ok = pcall(function() root:PivotTo(cf) end)
		if not ok then
			local parts = {}
			for _,d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(parts, d) end
			end
			local primary = root.PrimaryPart or parts[1]
			if primary then
				local delta = cf * primary.CFrame:Inverse()
				for _,p in ipairs(parts) do p.CFrame = delta * p.CFrame end
			end
		end
	elseif root:IsA("BasePart") then
		root.CFrame = cf
	end
end

-- remonte jusqu’au conteneur direct sous PetsPhysical
local function rootUnderFolder(inst, folder)
	local p = inst
	while p and p.Parent and p.Parent ~= folder do p = p.Parent end
	if p and p.Parent == folder then return p end
	return nil
end

--=========== Matching Owner & PetMover ===========--
local function matchesOwnerValue(val)
	if val == nil then return false end
	local myName  = LP.Name
	local myId    = LP.UserId
	local t = typeof(val)
	if t == "string" then
		if val == myName or val == tostring(myId) then return true end
	elseif t == "number" then
		if val == myId then return true end
	elseif t == "Instance" then
		if val.Name == myName then return true end
	end
	return false
end

local OWNER_KEYS = {"Owner","owner","OWNER"}

local function hasOwnerAttrMatch(inst)
	for _,k in ipairs(OWNER_KEYS) do
		local ok, v = pcall(function() return inst:GetAttribute(k) end)
		if ok and v ~= nil and matchesOwnerValue(v) then return true, k, v end
	end
	-- Fallback: ValueObjects nommés Owner
	local sv = inst:FindFirstChild("Owner")
	if sv then
		if sv:IsA("StringValue") and matchesOwnerValue(sv.Value) then return true, "StringValue", sv.Value end
		if sv:IsA("ObjectValue") and matchesOwnerValue(sv.Value) then return true, "ObjectValue", sv.Value end
		if sv:IsA("IntValue") and matchesOwnerValue(sv.Value) then return true, "IntValue", sv.Value end
	end
	return false
end

local function nameLooksLikePetMover(s)
	if not s or s=="" then return false end
	s = s:lower()
	-- accepte "petmover", "pet_mover", "pet mover", "PetMover123"
	if s:find("petmover") then return true end
	-- parfois "mover" tout court pour les pets
	if s:find("mover") and s:find("pet") then return true end
	return false
end

local function findPetMoverDescendant(root)
	if nameLooksLikePetMover(root.Name) then return root end
	for _,d in ipairs(root:GetDescendants()) do
		if nameLooksLikePetMover(d.Name) then return d end
	end
	return nil
end

-- --- TIGHT CIRCLE CONFIG ---
local GAP_MULTIPLIER = 0.95  -- 1.00 = se touchent; <1.00 = léger chevauchement
local MIN_RADIUS     = 0.8   -- rayon mini si très peu de pets
local Y_OFFSET_PET   = 0.20  -- petit lift vertical pour éviter la collision sol

-- Diamètre approx du modèle (plan XZ)
local function getModelDiameter(root)
	if root:IsA("Model") then
		local ok,size = pcall(function() return root:GetExtentsSize() end)
		if ok and size then return math.max(size.X, size.Z) end
		if root.PrimaryPart then
			local s = root.PrimaryPart.Size
			return math.max(s.X, s.Z)
		end
	elseif root:IsA("BasePart") then
		local s = root.Size
		return math.max(s.X, s.Z)
	end
	return 2.0
end

--=========== Scan PetsPhysical ===========--
local PETS = {}   -- { {root=Instance, mover=Instance, name=string, frozen=bool, targetCF=CFrame} }

local function scanPets()
	PETS = {}
	local petsFolder = workspace:FindFirstChild("PetsPhysical") or workspace:FindFirstChild("petsphysical") or workspace:FindFirstChild("Pets_Physical")
	if not petsFolder then notify("workspace.PetsPhysical introuvable"); return end

	-- logs
	log("PetsPhysical trouvé:", petsFolder:GetFullName(), " | enfants:", #petsFolder:GetChildren())

	local seen = {}
	-- 1) Parcourt d’abord les enfants directs (cas le plus courant)
	for _,child in ipairs(petsFolder:GetChildren()) do
		local mover = findPetMoverDescendant(child)
		if mover then
			local ownMover = hasOwnerAttrMatch(mover)
			local ownRoot  = hasOwnerAttrMatch(child)
			if ownMover or ownRoot then
				local root = rootUnderFolder(mover, petsFolder) or child
				if root and not seen[root] then
					seen[root] = true
					table.insert(PETS, {
						root = root,
						mover = mover,
						name  = tostring(root.Name),
						frozen = false,
						targetCF = anyCFrame(root)
					})
					log("✓ Pet capturé:", root.Name, " | mover:", mover.Name)
				end
			end
		end
	end

	-- 2) Fallback total: parcourt tous les descendants pour rater aucun cas exotique
	if #PETS == 0 then
		for _,d in ipairs(petsFolder:GetDescendants()) do
			if nameLooksLikePetMover(d.Name) and hasOwnerAttrMatch(d) then
				local root = rootUnderFolder(d, petsFolder) or d
				if root and not seen[root] then
					seen[root] = true
					table.insert(PETS, {
						root = root,
						mover = d,
						name  = tostring(root.Name),
						frozen = false,
						targetCF = anyCFrame(root)
					})
					log("✓ Pet (fallback) :", root.Name, " | mover:", d.Name)
				end
			end
		end
	end

	table.sort(PETS, function(a,b) return a.name < b.name end)
	notify("Pets détectés: "..tostring(#PETS))
end

--=========== Freeze Loop ===========--
local freezeConn = nil
local function ensureFreezeLoop()
	if freezeConn then return end
	freezeConn = RS.Heartbeat:Connect(function()
		for _,p in ipairs(PETS) do
			if p.frozen and p.targetCF then
				pivotTo(p.root, p.targetCF)
			end
		end
	end)
end
local function maybeStopLoop()
	for _,p in ipairs(PETS) do if p.frozen then return end end
	if freezeConn then freezeConn:Disconnect(); freezeConn=nil end
end

--=========== Actions ===========--
local function freezeHereAll()
	if #PETS == 0 then notify("Aucun pet — clique « Scanner »"); return end
	for _,p in ipairs(PETS) do
		p.targetCF = anyCFrame(p.root)
		p.frozen = true
	end
	ensureFreezeLoop()
	notify("Freeze ici : "..tostring(#PETS).." pets gelés")
end

local function bringToMeAndFreezeAll()
	if #PETS == 0 then notify("Aucun pet — clique « Scanner »"); return end
	local hrp    = getChar().HumanoidRootPart
	local origin = hrp.CFrame

	-- Rayon calculé pour cercle ultra-serré (quasi touching)
	local sumD  = 0
	local diams = (table.create and table.create(#PETS)) or {}
	for i,p in ipairs(PETS) do
		local d = getModelDiameter(p.root)
		if d <= 0 then d = 2 end
		d = d * GAP_MULTIPLIER
		diams[i] = d
		sumD += d
	end
	local radius = math.max(MIN_RADIUS, sumD / (2 * math.pi))

	-- Placement: pas angulaire = (diamètre / rayon)
	local angle = 0
	for i,p in ipairs(PETS) do
		local d   = diams[i]
		local x   = math.cos(angle) * radius
		local z   = math.sin(angle) * radius
		local pos = origin.Position + Vector3.new(x, Y_OFFSET_PET, z)
		local cf  = CFrame.new(pos, origin.Position + origin.LookVector) -- regarde vers toi

		pivotTo(p.root, cf)
		p.targetCF = cf
		p.frozen   = true

		angle = angle + (d / radius) -- arc/r = delta angle
	end

	ensureFreezeLoop()
	notify(("TP vers toi + Freeze (ultra-serré) : %d pets • R=%.2f • gap=%.0f%%")
		:format(#PETS, radius, (GAP_MULTIPLIER-1)*100))
end

local function unfreezeAll()
	for _,p in ipairs(PETS) do p.frozen=false end
	maybeStopLoop()
	notify("Unfreeze : tous les pets libérés")
end

--=========== UI ===========--
local pg = LP:WaitForChild("PlayerGui")
local sg = Instance.new("ScreenGui")
sg.Name = "Saad_PetMover_UI"
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 10000
sg.Parent = pg

local reopen = Instance.new("TextButton")
reopen.Name="Reopen"; reopen.Visible=false
reopen.Text="🐾"; reopen.TextScaled=true
reopen.Size=UDim2.fromOffset(56,56)
reopen.Position=UDim2.fromOffset(16, sg.AbsoluteSize.Y-72)
reopen.BackgroundColor3=Color3.fromRGB(35,150,90)
reopen.TextColor3=Color3.fromRGB(245,245,250)
reopen.Parent=sg
Instance.new("UICorner", reopen).CornerRadius = UDim.new(0,16)
sg:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	reopen.Position = UDim2.fromOffset(16, sg.AbsoluteSize.Y - 72)
end)

local frame = Instance.new("Frame")
frame.Name="Main"; frame.Active=true
frame.Size=UDim2.fromOffset(640, 520)
frame.Position=UDim2.fromOffset(120, 120)
frame.BackgroundColor3=Color3.fromRGB(24,24,28)
frame.Parent=sg
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,16)

local titleBar = Instance.new("Frame", frame)
titleBar.Size = UDim2.new(1,0,0,44)
titleBar.BackgroundColor3 = Color3.fromRGB(32,32,38)
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,16)

local title = Instance.new("TextLabel", titleBar)
title.BackgroundTransparency=1
title.Size=UDim2.new(1,-140,1,0)
title.Position=UDim2.fromOffset(12,0)
title.Text="🐾 PetMover — Freeze ici / TP vers moi + Freeze / Unfreeze"
title.TextScaled=true
title.Font=Enum.Font.SourceSansBold
title.TextColor3=Color3.fromRGB(235,235,240)

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Text="✕"; closeBtn.TextScaled=true
closeBtn.Size=UDim2.fromOffset(40,40)
closeBtn.Position=UDim2.new(1,-44,0,2)
closeBtn.BackgroundColor3=Color3.fromRGB(60,25,25)
closeBtn.TextColor3=Color3.fromRGB(245,245,250)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,12)

-- drag
do
	local dragging=false; local dragStart; local startPos
	local function clamp(x,y) local s=sg.AbsoluteSize; local w=frame.AbsoluteSize.X; local h=frame.AbsoluteSize.Y
		return math.clamp(x,0,math.max(0,s.X-w)), math.clamp(y,0,math.max(0,s.Y-h)) end
	local function upd(i) local d=i.Position-dragStart; local nx,ny=clamp(startPos.X.Offset+d.X, startPos.Y.Offset+d.Y); frame.Position=UDim2.fromOffset(nx,ny) end
	titleBar.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=frame.Position end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then upd(i) end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
	end)
end

-- layout
local content = Instance.new("Frame", frame)
content.BackgroundTransparency=1
content.Size=UDim2.new(1,-20,1,-60)
content.Position=UDim2.fromOffset(10,54)

local left = Instance.new("Frame", content)
left.BackgroundTransparency=1
left.Size=UDim2.new(0.46,-6,1,0)
left.Position=UDim2.fromOffset(0,0)

local right = Instance.new("Frame", content)
right.BackgroundTransparency=1
right.Size=UDim2.new(0.54,0,1,0)
right.Position=UDim2.new(0.46,6,0,0)

local lList = Instance.new("UIListLayout", left)
lList.Padding = UDim.new(0,8)
lList.FillDirection = Enum.FillDirection.Vertical
lList.HorizontalAlignment = Enum.HorizontalAlignment.Left
lList.VerticalAlignment = Enum.VerticalAlignment.Top
lList.SortOrder = Enum.SortOrder.LayoutOrder

local pathLbl = Instance.new("TextLabel", left)
pathLbl.BackgroundTransparency=0.15
pathLbl.BackgroundColor3=Color3.fromRGB(30,30,36)
pathLbl.Text="Chemin: workspace.PetsPhysical"
pathLbl.TextScaled=true
pathLbl.Font=Enum.Font.SourceSans
pathLbl.TextColor3=Color3.fromRGB(220,220,230)
pathLbl.Size=UDim2.new(1,0,0,40)
Instance.new("UICorner", pathLbl).CornerRadius=UDim.new(0,10)

local statsLbl = Instance.new("TextLabel", left)
statsLbl.BackgroundTransparency=0.15
statsLbl.BackgroundColor3=Color3.fromRGB(30,30,36)
statsLbl.Text="Pets: — | Gelés: —"
statsLbl.TextScaled=true
statsLbl.Font=Enum.Font.SourceSans
statsLbl.TextColor3=Color3.fromRGB(200,200,210)
statsLbl.Size=UDim2.new(1,0,0,36)
Instance.new("UICorner", statsLbl).CornerRadius=UDim.new(0,10)

local row = Instance.new("Frame", left)
row.BackgroundTransparency=1
row.Size=UDim2.new(1,0,0,44)
local rowLayout = Instance.new("UIListLayout", row)
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0,8)
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top

local scanBtn = Instance.new("TextButton", row)
scanBtn.Text="Scanner"
scanBtn.TextScaled=true
scanBtn.Size=UDim2.new(0.31,0,1,0)
scanBtn.BackgroundColor3=Color3.fromRGB(35,150,90)
scanBtn.TextColor3=Color3.fromRGB(245,245,250)
Instance.new("UICorner", scanBtn).CornerRadius=UDim.new(0,10)

local freezeBtn = Instance.new("TextButton", row)
freezeBtn.Text="Freeze ici (tous)"
freezeBtn.TextScaled=true
freezeBtn.Size=UDim2.new(0.31,0,1,0)
freezeBtn.BackgroundColor3=Color3.fromRGB(50,60,120)
freezeBtn.TextColor3=Color3.fromRGB(245,245,250)
Instance.new("UICorner", freezeBtn).CornerRadius=UDim.new(0,10)

local bringFreezeBtn = Instance.new("TextButton", row)
bringFreezeBtn.Text="TP vers moi + Freeze"
bringFreezeBtn.TextScaled=true
bringFreezeBtn.Size=UDim2.new(0.31,0,1,0)
bringFreezeBtn.BackgroundColor3=Color3.fromRGB(120,80,20)
bringFreezeBtn.TextColor3=Color3.fromRGB(245,245,250)
Instance.new("UICorner", bringFreezeBtn).CornerRadius=UDim.new(0,10)

local unfreezeBtn = Instance.new("TextButton", left)
unfreezeBtn.Text="⛔ Unfreeze (tous)"
unfreezeBtn.TextScaled=true
unfreezeBtn.Size=UDim2.new(1,0,0,38)
unfreezeBtn.BackgroundColor3=Color3.fromRGB(120,35,35)
unfreezeBtn.TextColor3=Color3.fromRGB(245,245,250)
Instance.new("UICorner", unfreezeBtn).CornerRadius=UDim.new(0,10)

-- Liste
local listFrame = Instance.new("Frame", right)
listFrame.Size=UDim2.new(1,0,1,0)
listFrame.BackgroundTransparency=0.15
listFrame.BackgroundColor3=Color3.fromRGB(30,30,36)
Instance.new("UICorner", listFrame).CornerRadius=UDim.new(0,12)

local listScroll = Instance.new("ScrollingFrame", listFrame)
listScroll.Size=UDim2.new(1,-10,1,-10)
listScroll.Position=UDim2.fromOffset(5,5)
listScroll.BackgroundTransparency=1
listScroll.ScrollBarThickness=6
listScroll.CanvasSize=UDim2.new(0,0,0,0)

local lLayout2 = Instance.new("UIListLayout", listScroll)
lLayout2.Padding = UDim.new(0,4)
lLayout2.SortOrder = Enum.SortOrder.LayoutOrder
lLayout2.HorizontalAlignment = Enum.HorizontalAlignment.Left
lLayout2.VerticalAlignment = Enum.VerticalAlignment.Top

local function clearList()
	for _,c in ipairs(listScroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	listScroll.CanvasSize = UDim2.new(0,0,0,0)
end
local function addRow(i, p)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1,-6,0,28)
	row.BackgroundTransparency = 0.1
	row.BackgroundColor3 = Color3.fromRGB(38,38,44)
	row.Parent = listScroll
	Instance.new("UICorner", row).CornerRadius = UDim.new(0,8)

	local lay = Instance.new("UIListLayout", row)
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.Padding = UDim.new(0,6)
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Left
	lay.VerticalAlignment = Enum.VerticalAlignment.Top

	local function cell(w, txt, bold)
		local l = Instance.new("TextLabel", row)
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(w,0,1,0)
		l.Text = txt
		l.TextScaled = true
		l.Font = bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
		l.TextColor3 = Color3.fromRGB(225,225,230)
	end

	local cf = anyCFrame(p.root)
	local pos = cf.Position
	local dist = (pos - getChar().HumanoidRootPart.Position).Magnitude

	cell(0.08, ("#%d"):format(i), true)
	cell(0.38, p.name, true)
	cell(0.34, ("(%.1f, %.1f, %.1f)"):format(pos.X,pos.Y,pos.Z), false)
	cell(0.10, string.format("%.1f", dist), false)
	cell(0.08, p.frozen and "✓" or "—", true)
end
local function updateCanvas()
	task.defer(function()
		local tot = 0
		for _,c in ipairs(listScroll:GetChildren()) do
			if c:IsA("Frame") then tot += c.AbsoluteSize.Y + 4 end
		end
		listScroll.CanvasSize = UDim2.new(0,0,0,tot)
	end)
end

-- Boutons
local function refreshStats()
	local frozen = 0; for _,p in ipairs(PETS) do if p.frozen then frozen += 1 end end
	statsLbl.Text = ("Pets: %d | Gelés: %d"):format(#PETS, frozen)
end

local function doScan()
	local petsFolder = workspace:FindFirstChild("PetsPhysical") or workspace:FindFirstChild("petsphysical") or workspace:FindFirstChild("Pets_Physical")
	if not petsFolder then notify("workspace.PetsPhysical introuvable"); return end
	petsFolder:GetPropertyChangedSignal("Name"):Connect(function() end) -- garde la ref active dans certains executors
	scanPets()
	clearList(); for i,p in ipairs(PETS) do addRow(i,p) end; updateCanvas()
	refreshStats()
end

scanBtn.MouseButton1Click:Connect(function() doScan() end)
freezeBtn.MouseButton1Click:Connect(function() freezeHereAll(); refreshStats() end)
bringFreezeBtn.MouseButton1Click:Connect(function()
	bringToMeAndFreezeAll()
	clearList(); for i,p in ipairs(PETS) do addRow(i,p) end; updateCanvas()
	refreshStats()
end)
unfreezeBtn.MouseButton1Click:Connect(function() unfreezeAll(); refreshStats() end)

-- Close/reopen
closeBtn.MouseButton1Click:Connect(function() frame.Visible=false; reopen.Visible=true end)
reopen.MouseButton1Click:Connect(function() frame.Visible=true; reopen.Visible=false end)

-- Boot
notify("UI prête — Scan → Freeze ici / TP vers moi + Freeze / Unfreeze.")
doScan()
