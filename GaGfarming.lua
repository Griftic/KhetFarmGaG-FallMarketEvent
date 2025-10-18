-- =========================================================
-- Saad Helper - MOBILE-LITE (ASCII only) - v1.0
-- Works on mobile executors: no emojis, no accents, no getfenv.
-- If boot fails, shows a red error panel with the message.
-- Features kept: Gear Panel (scroll), Admin Abuse, TP->saadeboite,
-- Sell, Submit Cauldron, Buy All Seeds/Gear/Eggs, Lollipop x50,
-- Timers + Anti-AFK.
-- =========================================================
local function bootstrap(fn)
    local ok, err = pcall(fn)
    if ok then return end
    -- Minimal on-screen error panel for mobile
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 2)
    if not pg then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "Saad_Mobile_Error"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.Parent = pg
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(340, 90)
    frame.Position = UDim2.new(0.5, -170, 0.1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local corner = Instance.new("UICorner", frame)
    corner.CornerRadius = UDim.new(0, 10)
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -12, 0, 24)
    title.Position = UDim2.new(0, 6, 0, 6)
    title.Text = "Script failed to start"
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = frame
    local body = Instance.new("TextLabel")
    body.BackgroundTransparency = 1
    body.Size = UDim2.new(1, -12, 0, 50)
    body.Position = UDim2.new(0, 6, 0, 32)
    body.Text = tostring(err)
    body.TextWrapped = true
    body.TextColor3 = Color3.fromRGB(255, 230, 230)
    body.Font = Enum.Font.Gotham
    body.TextSize = 13
    body.Parent = frame
end

bootstrap(function()
    -- ============================ Services & locals
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local StarterGui = game:GetService("StarterGui")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")
    local Workspace = game:GetService("Workspace")
    local VirtualUser = game:GetService("VirtualUser")

    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- ============================ Config
    local DEFAULTS = { speed = 16, gravity = 196.2, jump = 50 }
    local ADMIN_AUTO_PERIOD = 30
    local BASE_AUTO_PERIOD = 60
    local ADMIN_TRIES_PER_ITEM = 30
    local ADMIN_LOLLIPOP_COUNT = 67

    local SEEDS = {
        "Carrot","Strawberry","Blueberry","Orange Tulip","Tomato","Corn","Daffodil","Watermelon",
        "Pumpkin","Apple","Bamboo","Coconut","Cactus","Dragon Fruit","Mango","Grape","Mushroom",
        "Pepper","Cacao","Beanstalk","Ember Lily","Sugar Apple","Burning Bud","Giant Pinecone",
        "Elder Strawberry","Romanesco","Crimson Thorn","Great Pumpkin"
    }
    local GEARS = {
        "Watering Can","Trading Ticket","Trowel","Recall Wrench","Basic Sprinkler","Advanced Sprinkler",
        "Medium Toy","Medium Treat","Godly Sprinkler","Magnifying Glass","Master Sprinkler",
        "Cleaning Spray","Cleansing Pet Shard","Favorite Tool","Harvest Tool","Friendship Pot",
        "Grandmaster Sprinkler","Levelup Lollipop"
    }
    local EGGS = { "Common Egg","Uncommon Egg","Rare Egg","Legendary Egg","Mythical Egg","Bug Egg","Jungle Egg" }

    local GEAR_SHOP_POS = Vector3.new(-288, 2, -15)
    local SELL_NPC_POS  = Vector3.new(87, 3, 0)

    -- ============================ State
    local adminAbuse = false
    local triesSeed, triesGear, triesEgg = 5, 5, 1
    local period = BASE_AUTO_PERIOD
    local autoSeeds, autoGear, autoEggs = true, true, true
    local seedsTimer, gearTimer, eggsTimer = period, period, period
    local seedsTimerLabel, gearTimerLabel, eggsTimerLabel

    local function nowPeriod()
        return adminAbuse and ADMIN_AUTO_PERIOD or BASE_AUTO_PERIOD
    end
    local function applyPeriod()
        period = nowPeriod()
        seedsTimer, gearTimer, eggsTimer = period, period, period
    end
    local function setAdminAbuse(on)
        adminAbuse = on and true or false
        triesSeed = adminAbuse and ADMIN_TRIES_PER_ITEM or 5
        triesGear = adminAbuse and ADMIN_TRIES_PER_ITEM or 5
        triesEgg  = adminAbuse and ADMIN_TRIES_PER_ITEM or 1
        applyPeriod()
    end

    -- ============================ Helpers
    local function msg(t)
        pcall(function()
            StarterGui:SetCore("ChatMakeSystemMessage", { Text = "[Saad] "..t, Color = Color3.fromRGB(210,230,255) })
        end)
    end
    local function getHRP()
        local c = player.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end
    local function teleportTo(vec3)
        local hrp = getHRP()
        if not hrp then return end
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.new()
            hrp.AssemblyAngularVelocity = Vector3.new()
        end)
        local ch = player.Character
        if ch and typeof(ch.PivotTo)=="function" then
            ch:PivotTo(CFrame.new(vec3))
        else
            hrp.CFrame = CFrame.new(vec3)
        end
    end
    local function fmt(sec)
        sec = math.max(0, math.floor((sec or 0)+0.5))
        local m = math.floor(sec/60); local s = sec%60
        return string.format("%d:%02d", m, s)
    end
    local function safeWait(path, timeout)
        local node = ReplicatedStorage
        for _,name in ipairs(path) do
            node = node:WaitForChild(name, timeout or 2)
            if not node then return nil end
        end
        return node
    end
    local function updateTimersText()
        if seedsTimerLabel then seedsTimerLabel.Text = "Next: "..fmt(seedsTimer) end
        if gearTimerLabel  then gearTimerLabel.Text  = "Next: "..fmt(gearTimer)  end
        if eggsTimerLabel  then eggsTimerLabel.Text  = "Next: "..fmt(eggsTimer)  end
    end

    -- ============================ Remotes
    local function rSell()      local r=safeWait({"GameEvents","Sell_Inventory"},2) return r and r:IsA("RemoteEvent") and r end
    local function rBuySeed()   local r=safeWait({"GameEvents","BuySeedStock"},2)   return r and r:IsA("RemoteEvent") and r end
    local function rBuyGear()   local r=safeWait({"GameEvents","BuyGearStock"},2)   return r and r:IsA("RemoteEvent") and r end
    local function rBuyEgg()    local r=safeWait({"GameEvents","BuyPetEgg"},2)      return r and r:IsA("RemoteEvent") and r end
    local function rfCauldron() local r=safeWait({"GameEvents","WitchesBrew","SubmitItemToCauldron"},2) return r and r:IsA("RemoteFunction") and r end

    local function submitAllCauldron()
        local rf = rfCauldron()
        if not rf then msg("Cauldron remote not found") return false end
        local ok,err = pcall(function() rf:InvokeServer("All") end)
        if ok then msg("Cauldron: Submit All OK") else msg("Cauldron error: "..tostring(err)) end
        return ok
    end

    -- ============================ Workers
    local function buyAllSeeds()
        local r = rBuySeed(); if not r then msg("BuySeedStock not found") return end
        msg("Buying all seeds...")
        for _,name in ipairs(SEEDS) do
            for i=1,triesSeed do pcall(function() r:FireServer("Shop", name) end) task.wait(0.03) end
        end
        msg("Seeds done")
    end
    local function buyAllGear()
        local r = rBuyGear(); if not r then msg("BuyGearStock not found") return end
        msg("Buying all gear...")
        for _,name in ipairs(GEARS) do
            local tries = (adminAbuse and name=="Levelup Lollipop") and ADMIN_LOLLIPOP_COUNT or triesGear
            for i=1,tries do pcall(function() r:FireServer(name) end) task.wait(0.03) end
        end
        msg("Gear done")
    end
    local function buyAllEggs()
        local r = rBuyEgg(); if not r then msg("BuyPetEgg not found") return end
        msg("Buying eggs...")
        for _,name in ipairs(EGGS) do
            for i=1,triesEgg do pcall(function() r:FireServer(name) end) task.wait(0.03) end
        end
        msg("Eggs done")
    end
    local function buyLollipop50()
        local r = rBuyGear(); if not r then msg("BuyGearStock not found") return end
        for i=1,50 do pcall(function() r:FireServer("Levelup Lollipop") end) task.wait(0.03) end
        msg("Lollipop x50 ok")
    end

    -- ============================ Auto timers
    task.spawn(function()
        -- start immediately one pass (optional)
        task.defer(function()
            if autoSeeds then task.spawn(buyAllSeeds) end
            if autoGear  then task.spawn(buyAllGear)  end
            if autoEggs  then task.spawn(buyAllEggs)  end
        end)
        while true do
            task.wait(1)
            if autoSeeds then seedsTimer = seedsTimer - 1 else seedsTimer = period end
            if autoGear  then gearTimer  = gearTimer  - 1 else gearTimer  = period end
            if autoEggs  then eggsTimer  = eggsTimer  - 1 else eggsTimer  = period end
            if autoSeeds and seedsTimer<=0 then buyAllSeeds(); seedsTimer = period end
            if autoGear  and gearTimer<=0  then buyAllGear();  gearTimer  = period end
            if autoEggs  and eggsTimer<=0  then buyAllEggs();  eggsTimer  = period end
            updateTimersText()
        end
    end)

    -- ============================ UI (ASCII only)
    local function corner(obj, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0, r or 8); c.Parent=obj end
    local function autoscale(sg)
        local cam = Workspace.CurrentCamera
        local scale = Instance.new("UIScale"); scale.Name="AutoScale"; scale.Parent = sg
        local function compute()
            local vp = (cam and cam.ViewportSize) or Vector2.new(1280,720)
            local s = vp.X / 1280
            if vp.Y < 720 or vp.X < 1100 then s = s * 0.9 end
            if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then s = s * 0.9 end
            return math.clamp(s, 0.55, 1.0)
        end
        local function refresh() scale.Scale = compute() end
        refresh()
        if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh) end
    end

    -- Main panel (small)
    local mainGui = Instance.new("ScreenGui")
    mainGui.Name = "Saad_Player_Tuner_Mobile"
    mainGui.ResetOnSpawn = false
    mainGui.IgnoreGuiInset = false
    mainGui.Parent = playerGui
    autoscale(mainGui)

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(300, 210)
    main.Position = UDim2.fromScale(0.03, 0.05)
    main.BackgroundColor3 = Color3.fromRGB(36,36,36)
    main.BorderSizePixel = 0
    main.Parent = mainGui
    corner(main, 10)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1,0,0,28)
    bar.BackgroundColor3 = Color3.fromRGB(28,28,28)
    bar.Parent = main
    corner(bar, 10)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1,-90,1,0)
    title.Position = UDim2.new(0,10,0,0)
    title.Text = "Saad Helper (Mobile)"
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = bar

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(24,24)
    close.Position = UDim2.new(1,-30,0,2)
    close.Text = "X"
    close.TextColor3 = Color3.new(1,1,1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 14
    close.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    close.Parent = bar
    corner(close, 6)
    close.MouseButton1Click:Connect(function() mainGui:Destroy() end)

    -- drag
    do
        local dragging, startPos, startInput
        bar.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
                dragging = true; startPos = main.Position; startInput = i
                i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end)
            end
        end)
        bar.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
                local delta = i.Position - startInput.Position
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
            end
        end)
    end

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1,-14,1,-40)
    container.Position = UDim2.new(0,7,0,34)
    container.BackgroundTransparency = 1
    container.Parent = main

    local function mkBtn(y, text, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 28)
        b.Position = UDim2.new(0, 0, 0, y)
        b.Text = text
        b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.BackgroundColor3 = color or Color3.fromRGB(90,120,210)
        b.Parent = container
        corner(b, 8)
        return b
    end

    local btnToggleGear = mkBtn(0,   "Open Gear Panel", Color3.fromRGB(60,180,60))
    local btnAntiAFK    = mkBtn(34,  "Anti-AFK: OFF",   Color3.fromRGB(100,130,100))
    local btnAdmin      = mkBtn(68,  "Admin Abuse: OFF",Color3.fromRGB(170,70,70))
    local btnSaadTP     = mkBtn(102, "TP to saadeboite",Color3.fromRGB(90,150,220))
    local btnSubmit     = mkBtn(136, "Submit All (Cauldron)", Color3.fromRGB(140,110,200))

    -- Anti AFK
    local antiAFK = false
    local idledConn; local antiThread
    local function setAntiAFK(on)
        if on == antiAFK then return end
        antiAFK = on
        btnAntiAFK.Text = antiAFK and "Anti-AFK: ON" or "Anti-AFK: OFF"
        btnAntiAFK.BackgroundColor3 = antiAFK and Color3.fromRGB(80,140,90) or Color3.fromRGB(100,130,100)
        if idledConn then idledConn:Disconnect(); idledConn=nil end
        if antiThread then task.cancel(antiThread); antiThread=nil end
        if antiAFK then
            idledConn = player.Idled:Connect(function()
                pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end)
            end)
            antiThread = task.spawn(function()
                while antiAFK do
                    task.wait(60)
                    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                    if hum then hum:Move(Vector3.new(0,0,-1), true); task.wait(0.3); hum:Move(Vector3.new(0,0,0), true) end
                end
            end)
        end
    end
    btnAntiAFK.MouseButton1Click:Connect(function() setAntiAFK(not antiAFK) end)

    btnSaadTP.MouseButton1Click:Connect(function()
        local target
        for _,pl in ipairs(Players:GetPlayers()) do
            if string.lower(pl.Name) == "saadeboite" then target = pl break end
        end
        if not target or not target.Character then msg("Player saadeboite not found") return end
        local hrp = target.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then msg("saadeboite HRP not found") return end
        teleportTo(hrp.Position + Vector3.new(0,3,0))
    end)

    btnAdmin.MouseButton1Click:Connect(function()
        setAdminAbuse(not adminAbuse)
        if adminAbuse then
            btnAdmin.BackgroundColor3 = Color3.fromRGB(80,170,80)
            btnAdmin.Text = "Admin Abuse: ON (30x/30s, Lolli 67x)"
            msg("Admin Abuse enabled")
        else
            btnAdmin.BackgroundColor3 = Color3.fromRGB(170,70,70)
            btnAdmin.Text = "Admin Abuse: OFF"
            msg("Admin Abuse disabled")
        end
    end)

    btnSubmit.MouseButton1Click:Connect(submitAllCauldron)

    -- ============================ Gear Panel (scroll, mobile)
    local gearGui = Instance.new("ScreenGui")
    gearGui.Name = "Saad_Gear_Panel"
    gearGui.ResetOnSpawn = false
    gearGui.IgnoreGuiInset = false
    gearGui.Enabled = false
    gearGui.Parent = playerGui
    autoscale(gearGui)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(280, 500)
    frame.Position = UDim2.fromScale(0.28, 0.05)
    frame.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
    frame.BorderSizePixel = 0
    frame.Parent = gearGui
    corner(frame, 10)

    local bar2 = Instance.new("Frame")
    bar2.Size = UDim2.new(1,0,0,28)
    bar2.BackgroundColor3 = Color3.fromRGB(40,40,70)
    bar2.Parent = frame
    corner(bar2, 10)

    local title2 = Instance.new("TextLabel")
    title2.BackgroundTransparency = 1
    title2.Size = UDim2.new(1,-60,1,0)
    title2.Position = UDim2.new(0,10,0,0)
    title2.Text = "GEAR SHOP"
    title2.TextColor3 = Color3.new(1,1,1)
    title2.Font = Enum.Font.GothamBold
    title2.TextSize = 13
    title2.TextXAlignment = Enum.TextXAlignment.Left
    title2.Parent = bar2

    local close2 = Instance.new("TextButton")
    close2.Size = UDim2.fromOffset(20,20)
    close2.Position = UDim2.new(1,-26,0,4)
    close2.Text = "X"
    close2.TextColor3 = Color3.new(1,1,1)
    close2.Font = Enum.Font.GothamBold
    close2.TextSize = 12
    close2.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    close2.Parent = bar2
    corner(close2, 6)
    close2.MouseButton1Click:Connect(function() gearGui.Enabled = false end)

    -- drag
    do
        local dragging, startPos, startInput
        bar2.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
                dragging = true; startPos = frame.Position; startInput = i
                i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end)
            end
        end)
        bar2.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
                local d = i.Position - startInput.Position
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end)
    end

    local content = Instance.new("ScrollingFrame")
    content.Size = UDim2.new(1,-14,1,-40)
    content.Position = UDim2.new(0,7,0,34)
    content.BackgroundTransparency = 1
    content.ScrollBarThickness = 6
    content.ScrollingDirection = Enum.ScrollingDirection.Y
    content.Parent = frame

    local function refreshCanvas()
        local maxY = 0
        for _,ch in ipairs(content:GetChildren()) do
            if ch:IsA("GuiObject") then
                local bottom = ch.Position.Y.Offset + ch.Size.Y.Offset
                if bottom > maxY then maxY = bottom end
            end
        end
        content.CanvasSize = UDim2.new(0,0,0, maxY + 10)
    end
    content.ChildAdded:Connect(function() task.defer(refreshCanvas) end)
    content.ChildRemoved:Connect(function() task.defer(refreshCanvas) end)

    local function mkBtn2(y, text, col)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 28)
        b.Position = UDim2.new(0, 0, 0, y)
        b.Text = text
        b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.BackgroundColor3 = col or Color3.fromRGB(90,120,210)
        b.Parent = content
        corner(b, 8)
        return b
    end

    local y = 0
    local bTPGear   = mkBtn2(y,   "TP to Gear Shop", Color3.fromRGB(60,180,60)); y = y + 34
    local bSell     = mkBtn2(y,   "Sell Inventory",  Color3.fromRGB(200,130,90)); y = y + 34
    local bSubmit   = mkBtn2(y,   "Submit All (Cauldron)", Color3.fromRGB(140,110,200)); y = y + 34

    local rowSeeds = Instance.new("Frame"); rowSeeds.Size = UDim2.new(1,0,0,28); rowSeeds.Position = UDim2.new(0,0,0,y); rowSeeds.BackgroundTransparency=1; rowSeeds.Parent=content; y=y+34
    local bBuySeeds = Instance.new("TextButton"); bBuySeeds.Size=UDim2.new(0.48,-4,1,0); bBuySeeds.Text="Buy All Seeds"; bBuySeeds.TextColor3=Color3.new(1,1,1); bBuySeeds.Font=Enum.Font.GothamBold; bBuySeeds.TextSize=12; bBuySeeds.BackgroundColor3=Color3.fromRGB(100,170,100); bBuySeeds.Parent=rowSeeds; corner(bBuySeeds,8)
    local bAutoSeeds = Instance.new("TextButton"); bAutoSeeds.Size=UDim2.new(0.22,-4,1,0); bAutoSeeds.Position=UDim2.new(0.48,4,0,0); bAutoSeeds.Text="Auto: ON"; bAutoSeeds.TextColor3=Color3.new(1,1,1); bAutoSeeds.Font=Enum.Font.GothamBold; bAutoSeeds.TextSize=12; bAutoSeeds.BackgroundColor3=Color3.fromRGB(70,160,90); bAutoSeeds.Parent=rowSeeds; corner(bAutoSeeds,8)
    seedsTimerLabel = Instance.new("TextLabel"); seedsTimerLabel.Size=UDim2.new(0.30,0,1,0); seedsTimerLabel.Position=UDim2.new(0.70,4,0,0); seedsTimerLabel.BackgroundColor3=Color3.fromRGB(60,65,95); seedsTimerLabel.TextColor3=Color3.fromRGB(220,230,255); seedsTimerLabel.Font=Enum.Font.Gotham; seedsTimerLabel.TextSize=12; seedsTimerLabel.Text="Next: "..fmt(seedsTimer); seedsTimerLabel.Parent=rowSeeds; corner(seedsTimerLabel,8)

    local rowGear = Instance.new("Frame"); rowGear.Size = UDim2.new(1,0,0,28); rowGear.Position = UDim2.new(0,0,0,y); rowGear.BackgroundTransparency=1; rowGear.Parent=content; y=y+34
    local bBuyGear = Instance.new("TextButton"); bBuyGear.Size=UDim2.new(0.48,-4,1,0); bBuyGear.Text="Buy All Gear"; bBuyGear.TextColor3=Color3.new(1,1,1); bBuyGear.Font=Enum.Font.GothamBold; bBuyGear.TextSize=12; bBuyGear.BackgroundColor3=Color3.fromRGB(120,140,200); bBuyGear.Parent=rowGear; corner(bBuyGear,8)
    local bAutoGear = Instance.new("TextButton"); bAutoGear.Size=UDim2.new(0.22,-4,1,0); bAutoGear.Position=UDim2.new(0.48,4,0,0); bAutoGear.Text="Auto: ON"; bAutoGear.TextColor3=Color3.new(1,1,1); bAutoGear.Font=Enum.Font.GothamBold; bAutoGear.TextSize=12; bAutoGear.BackgroundColor3=Color3.fromRGB(70,140,180); bAutoGear.Parent=rowGear; corner(bAutoGear,8)
    gearTimerLabel = Instance.new("TextLabel"); gearTimerLabel.Size=UDim2.new(0.30,0,1,0); gearTimerLabel.Position=UDim2.new(0.70,4,0,0); gearTimerLabel.BackgroundColor3=Color3.fromRGB(60,65,95); gearTimerLabel.TextColor3=Color3.fromRGB(220,230,255); gearTimerLabel.Font=Enum.Font.Gotham; gearTimerLabel.TextSize=12; gearTimerLabel.Text="Next: "..fmt(gearTimer); gearTimerLabel.Parent=rowGear; corner(gearTimerLabel,8)

    local rowEggs = Instance.new("Frame"); rowEggs.Size = UDim2.new(1,0,0,28); rowEggs.Position = UDim2.new(0,0,0,y); rowEggs.BackgroundTransparency=1; rowEggs.Parent=content; y=y+34
    local bBuyEggs = Instance.new("TextButton"); bBuyEggs.Size=UDim2.new(0.48,-4,1,0); bBuyEggs.Text="Buy Eggs"; bBuyEggs.TextColor3=Color3.new(1,1,1); bBuyEggs.Font=Enum.Font.GothamBold; bBuyEggs.TextSize=12; bBuyEggs.BackgroundColor3=Color3.fromRGB(150,120,200); bBuyEggs.Parent=rowEggs; corner(bBuyEggs,8)
    local bAutoEggs = Instance.new("TextButton"); bAutoEggs.Size=UDim2.new(0.22,-4,1,0); bAutoEggs.Position=UDim2.new(0.48,4,0,0); bAutoEggs.Text="Auto: ON"; bAutoEggs.TextColor3=Color3.new(1,1,1); bAutoEggs.Font=Enum.Font.GothamBold; bAutoEggs.TextSize=12; bAutoEggs.BackgroundColor3=Color3.fromRGB(120,100,160); bAutoEggs.Parent=rowEggs; corner(bAutoEggs,8)
    eggsTimerLabel = Instance.new("TextLabel"); eggsTimerLabel.Size=UDim2.new(0.30,0,1,0); eggsTimerLabel.Position=UDim2.new(0.70,4,0,0); eggsTimerLabel.BackgroundColor3=Color3.fromRGB(60,65,95); eggsTimerLabel.TextColor3=Color3.fromRGB(220,230,255); eggsTimerLabel.Font=Enum.Font.Gotham; eggsTimerLabel.TextSize=12; eggsTimerLabel.Text="Next: "..fmt(eggsTimer); eggsTimerLabel.Parent=rowEggs; corner(eggsTimerLabel,8)

    local bLolli = mkBtn2(y, "Buy Lollipop x50", Color3.fromRGB(200,140,90)); y = y + 34
    local adminRow = Instance.new("Frame"); adminRow.Size = UDim2.new(1,0,0,28); adminRow.Position = UDim2.new(0,0,0,y); adminRow.BackgroundTransparency=1; adminRow.Parent=content; y=y+34
    local bAdmin   = Instance.new("TextButton"); bAdmin.Size=UDim2.new(0.58,-4,1,0); bAdmin.Text="Admin Abuse: OFF"; bAdmin.TextColor3=Color3.new(1,1,1); bAdmin.Font=Enum.Font.GothamBold; bAdmin.TextSize=12; bAdmin.BackgroundColor3=Color3.fromRGB(170,70,70); bAdmin.Parent=adminRow; corner(bAdmin,8)
    local bSaadTP2 = Instance.new("TextButton"); bSaadTP2.Size=UDim2.new(0.42,0,1,0); bSaadTP2.Position=UDim2.new(0.58,4,0,0); bSaadTP2.Text="TP to saadeboite"; bSaadTP2.TextColor3=Color3.new(1,1,1); bSaadTP2.Font=Enum.Font.GothamBold; bSaadTP2.TextSize=12; bSaadTP2.BackgroundColor3=Color3.fromRGB(90,150,220); bSaadTP2.Parent=adminRow; corner(bSaadTP2,8)

    -- actions
    bTPGear.MouseButton1Click:Connect(function() teleportTo(GEAR_SHOP_POS) end)
    bSell.MouseButton1Click:Connect(function()
        local r = rSell(); if not r then msg("Sell remote not found") return end
        local hrp = getHRP(); if not hrp then return end
        local back = hrp.CFrame
        teleportTo(SELL_NPC_POS); task.wait(0.2); r:FireServer(); task.wait(0.05); hrp.CFrame = back
        msg("Sold inventory")
    end)
    bSubmit.MouseButton1Click:Connect(submitAllCauldron)
    bBuySeeds.MouseButton1Click:Connect(function() buyAllSeeds(); seedsTimer = period; updateTimersText() end)
    bBuyGear.MouseButton1Click:Connect(function() buyAllGear();  gearTimer  = period; updateTimersText() end)
    bBuyEggs.MouseButton1Click:Connect(function() buyAllEggs();  eggsTimer  = period; updateTimersText() end)
    bLolli.MouseButton1Click:Connect(buyLollipop50)
    bAdmin.MouseButton1Click:Connect(function()
        setAdminAbuse(not adminAbuse)
        if adminAbuse then
            bAdmin.BackgroundColor3 = Color3.fromRGB(80,170,80)
            bAdmin.Text = "Admin Abuse: ON (30x/30s, Lolli 67x)"
        else
            bAdmin.BackgroundColor3 = Color3.fromRGB(170,70,70)
            bAdmin.Text = "Admin Abuse: OFF"
        end
    end)
    bSaadTP2.MouseButton1Click:Connect(function() btnSaadTP:Activate() end)

    btnToggleGear.MouseButton1Click:Connect(function() gearGui.Enabled = not gearGui.Enabled end)

    -- Ready
    msg("Mobile-LITE loaded")
end)
