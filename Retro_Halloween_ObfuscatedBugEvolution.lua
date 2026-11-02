-- RETRO HALLOWEEN HUB - complete client script
-- HTTP access is required for the public server browser.
-- Server-authoritative collection, damage and rewards remain game-controlled.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local guiParent = playerGui
if type(gethui) == "function" then
    local ok, hiddenGui = pcall(gethui)
    if ok and typeof(hiddenGui) == "Instance" then guiParent = hiddenGui end
end
local previous = guiParent:FindFirstChild("RetroPullGUI")
if previous then previous:Destroy() end

local C = {
    OrbMode = "Medium", OrbMethod = "Teleport", OrbDelay = 0.15,
    AttemptsPerOrb = 3, SweepInterval = 2, TweenSpeed = 100,
    AcornMode = "Medium", FarmInterval = 0.15, FarmOffset = 0, BugHeight = 1.5, BugInterval = 0.15,
    AcornMethod = "Teleport", BugMethod = "Teleport", PlayerMethod = "Teleport",
    AcornTweenSpeed = 100, BugTweenSpeed = 80, PlayerTweenSpeed = 80,
    PlayerFollowHeight = 5, PlayerFollowInterval = 0.03,
    SafeHeight = 1000,
    PlayerTrigger = 20, PlayerRelease = 500, AntiHeight = 50,
    VoidHeight = workspace.FallenPartsDestroyHeight + 50,
    ServerRetryDelay = 10,
    WalkSpeed = 16,
}
local defaults = {}
for k, v in pairs(C) do defaults[k] = v end
local E = {Orbs=false, AutoFarm=false, KillBugs=false, KillPlayers=false, AntiPlayer=false,
    AntiVoid=true, SafeZone=false, CustomSpeed=false}
local M = {Motion="Movement: idle", AntiPlayer="Anti Player: OFF",
    AntiVoid="Anti Void: ON",
    SafeZone="Safe Zone: OFF"}
local T = {
    Background=Color3.fromRGB(17,10,23), Panel=Color3.fromRGB(31,17,39),
    Button=Color3.fromRGB(54,28,62), Orange=Color3.fromRGB(255,130,28),
    Purple=Color3.fromRGB(143,74,220), Text=Color3.fromRGB(255,235,208),
    Muted=Color3.fromRGB(190,160,198), Active=Color3.fromRGB(139,63,18),
}
local running, connections = true, {}
local version, trip, refuge, safePlatform, safeReturn, safeCharacter = 0
local activeTween, anchorState, noclipCharacter
local followedPlayer
local speedState
local biomeReturn
local biomeRowConnections = {}
local collisionStates = {}
local checkpoint, checkpointCharacter, lastRescue = nil, nil, 0
local buttons, labels, fields = {}, {}, {}
local selectedColors, knownColors, colorRows = {}, {}, {}
local defaultColorSelected = true
local refreshColors = function() end
local U = {Cards={}, Nav={}, Group="Farm", ActiveTab="Farm", SettingsRows={}, SettingTab="Orbs", ToastUntil=0,
    BugSelection={}, KnownBugs={}, BugRows={}, BugDefault=true,
    AcornSelection={}, KnownAcorns={}, AcornRows={}, AcornDefault=true}

-- Server browser state.
local serverResults, visitedServers, serverRowConnections = {}, {}, {}
local scanBusy, scanToken, autoHop, hopPending = false, 0, false, nil
local serverMessage = "Ready. Scan public servers with 1-3 players."
local renderServers, refreshServerControls

local function connect(signal, fn)
    local connection = signal:Connect(fn)
    table.insert(connections, connection)
    return connection
end
local function waitFor(seconds, expectedVersion)
    local deadline = os.clock() + seconds
    repeat
        if not running or (expectedVersion and expectedVersion ~= version) then return false end
        local remaining = deadline - os.clock()
        if remaining <= 0 then
            if seconds <= 0 then task.wait() end
            return running and (not expectedVersion or expectedVersion == version)
        end
        task.wait(math.min(0.05, remaining))
    until false
end
local function rootOf(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end
local function alive(character)
    local h = character and character:FindFirstChildOfClass("Humanoid")
    return character ~= nil and character == player.Character and rootOf(character) ~= nil
        and h ~= nil and h.Health > 0
end
local function restoreSpeed()
    local saved = speedState
    speedState = nil
    if saved then pcall(function() saved.Humanoid.WalkSpeed = saved.Original end) end
end
local function updateSpeed()
    local ch = player.Character
    local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
    if not E.CustomSpeed or not humanoid or humanoid.Health <= 0 then
        if speedState then restoreSpeed() end
        return
    end
    if not speedState or speedState.Humanoid ~= humanoid then
        restoreSpeed()
        speedState = {Humanoid = humanoid, Original = humanoid.WalkSpeed}
    end
    if humanoid.WalkSpeed ~= C.WalkSpeed then humanoid.WalkSpeed = C.WalkSpeed end
end
local function move(character, target)
    if not alive(character) then return false end
    return pcall(function()
        local root = rootOf(character)
        character:FindFirstChildOfClass("Humanoid").Sit = false
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        character:PivotTo(target * root.CFrame:Inverse() * character:GetPivot())
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    end)
end
local function restoreCollisions()
    noclipCharacter = nil
    for part, original in pairs(collisionStates) do
        pcall(function() part.CanCollide = original end)
    end
    table.clear(collisionStates)
end
local function applyNoclip(character)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if collisionStates[part] == nil then collisionStates[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end
connect(RunService.Stepped, function()
    if running and noclipCharacter then applyNoclip(noclipCharacter) end
end)
local function releaseAnchor()
    local saved = anchorState
    anchorState = nil
    if saved then pcall(function() saved.Root.Anchored = saved.Original end) end
end
local function anchor(character)
    local root = rootOf(character)
    if not root then return end
    if not anchorState or anchorState.Root ~= root then
        releaseAnchor()
        anchorState = {Root=root, Original=root.Anchored}
    end
    root.Anchored = true
end
local function stopTraversal()
    if activeTween then activeTween:Cancel(); activeTween = nil end
    restoreCollisions()
    releaseAnchor()
end
local function returnTrip()
    stopTraversal()
    local saved = trip
    trip = nil
    if saved and saved.Character == player.Character then return move(saved.Character, saved.CFrame) end
    return false
end
local function cancelMotion()
    version = version + 1
    stopTraversal()
    if not E.KillPlayers then followedPlayer = nil end
    if not refuge then returnTrip() end
end
local function beginTrip(character)
    if not alive(character) then return nil end
    if trip and trip.Character ~= character then trip = nil end
    if not trip then trip = {Character=character, CFrame=rootOf(character).CFrame} end
    return trip
end
local function canMove(character, expectedVersion)
    return running and version == expectedVersion and not refuge and not hopPending and alive(character)
end
local function platformTarget(part, character, rotation)
    local root, h = rootOf(character), character:FindFirstChildOfClass("Humanoid")
    local clearance = math.max(5, h.HipHeight + root.Size.Y/2 + 1)
    return CFrame.new(part.Position + Vector3.new(0, part.Size.Y/2 + clearance, 0)) * rotation
end
local function makePlatform(name, position, color)
    local part = Instance.new("Part")
    part.Name, part.Size = name .. "_" .. player.UserId, Vector3.new(50,2,50)
    part.Anchored, part.CanCollide = true, true
    part.Material, part.Color, part.Transparency = Enum.Material.Neon, color, 0.15
    part.Position, part.Parent = position, workspace
    return part
end
local function leaveSafe()
    if safeReturn and safeCharacter == player.Character then move(safeCharacter, safeReturn) end
    if safePlatform then safePlatform:Destroy() end
    safePlatform, safeReturn, safeCharacter = nil, nil, nil
    M.SafeZone = "Safe Zone: OFF"
end
local function enterSafe()
    local character = player.Character
    if not alive(character) then M.SafeZone="Safe Zone: character unavailable"; return false end
    local root = rootOf(character)
    safeReturn, safeCharacter = root.CFrame, character
    local ok, err = pcall(function()
        safePlatform = makePlatform("RetroSafeZone", root.Position+Vector3.new(0,C.SafeHeight,0),T.Orange)
        assert(move(character, platformTarget(safePlatform,character,root.CFrame.Rotation)))
    end)
    if not ok then warn("[Safe Zone]",err); leaveSafe(); return false end
    M.SafeZone="Safe Zone: ON"
    return true
end
local function nearestPlayer(position)
    local distance, name = math.huge, nil
    for _, other in ipairs(Players:GetPlayers()) do
        -- Ignore the intentionally followed player; other players still trigger protection.
        if other ~= player and not (E.KillPlayers and other == followedPlayer) then
            local ch = other.Character
            local root = rootOf(ch)
            local h = ch and ch:FindFirstChildOfClass("Humanoid")
            if root and h and h.Health > 0 then
                local d = (root.Position-position).Magnitude
                if d < distance then distance,name=d,other.DisplayName end
            end
        end
    end
    return distance,name
end
local function stopRefuge(restore)
    local saved = refuge
    refuge = nil
    version = version + 1
    stopTraversal()
    if saved then
        if restore and saved.Character == player.Character then move(saved.Character,saved.ReturnCFrame) end
        if saved.Platform then saved.Platform:Destroy() end
    end
    M.AntiPlayer=E.AntiPlayer and "Anti Player: monitoring" or "Anti Player: OFF"
end
local function startRefuge()
    local ch=player.Character
    if refuge or not alive(ch) then return end
    local root=rootOf(ch)
    local saved={Character=ch,ReturnCFrame=root.CFrame,Origin=root.Position}
    version=version+1
    stopTraversal()
    refuge=saved
    local ok,err=pcall(function()
        saved.Platform=makePlatform("RetroAntiPlayer",saved.Origin+Vector3.new(0,C.AntiHeight,0),T.Purple)
        saved.Target=platformTarget(saved.Platform,ch,saved.ReturnCFrame.Rotation)
        assert(move(ch,saved.Target))
    end)
    if not ok then warn("[Anti Player]",err); stopRefuge(true) end
end
local function gather(container, output)
    for _, object in ipairs(container:GetChildren()) do
        if object:IsA("BasePart") then table.insert(output,object)
        elseif object:IsA("Model") then
            if object:FindFirstChildWhichIsA("BasePart",true) then table.insert(output,object) end
        else gather(object,output) end
    end
end
local function getPart(object)
    if object:IsA("BasePart") then return object end
    if object:IsA("Model") then return object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart",true) end
end
local function positionOf(object)
    local part=getPart(object)
    return part and part.Position
end
local function colorInfo(object)
    local part=getPart(object)
    if not part then return nil end
    local color=part.Color
    return string.format("%d,%d,%d",math.floor(color.R*255+0.5),math.floor(color.G*255+0.5),
        math.floor(color.B*255+0.5)),color
end
local function colorName(color)
    local h,s,v=color:ToHSV()
    if v<0.16 then return "Black" end
    if s<0.14 then return v>0.85 and "White" or "Gray" end
    h=h*360
    if h<15 or h>=345 then return "Red" elseif h<45 then return "Orange"
    elseif h<70 then return "Yellow" elseif h<165 then return "Green"
    elseif h<195 then return "Cyan" elseif h<255 then return "Blue"
    elseif h<290 then return "Purple" end
    return "Pink"
end
local function colorSelected(key)
    if selectedColors[key]==nil then return defaultColorSelected end
    return selectedColors[key]
end
local function allowedOrb(object)
    local key=colorInfo(object)
    return key~=nil and colorSelected(key)
end
local function nearest(objects, origin, predicate)
    local index,distance=nil,math.huge
    for i,object in ipairs(objects) do
        if predicate(object) then
            local position=positionOf(object)
            if position then
                local d=(position-origin).Magnitude
                if d<distance then index,distance=i,d end
            end
        end
    end
    return index
end
local function travelOrb(ch, object, folder, token)
    if not canMove(ch,token) or not object:IsDescendantOf(folder) then return false end
    local position,root=positionOf(object),rootOf(ch)
    if not position or not root then return false end
    local target=CFrame.new(position)*root.CFrame.Rotation
    if C.OrbMethod=="Teleport" then return move(ch,target) end
    if C.TweenSpeed<=0 then return false end
    local distance=(position-root.Position).Magnitude
    if distance<0.05 then return move(ch,target) end
    restoreCollisions()
    noclipCharacter=ch
    applyNoclip(ch)
    local tween=TweenService:Create(root,TweenInfo.new(math.max(distance/C.TweenSpeed,0.001),
        Enum.EasingStyle.Linear),{CFrame=target})
    activeTween=tween
    tween:Play()
    while canMove(ch,token) and E.Orbs and not E.AutoFarm and not E.KillBugs and not E.KillPlayers
        and object:IsDescendantOf(folder) and tween.PlaybackState==Enum.PlaybackState.Playing do
        task.wait(0.01)
    end
    local arrived=tween.PlaybackState==Enum.PlaybackState.Completed
    if activeTween==tween then tween:Cancel(); activeTween=nil; restoreCollisions() end
    return arrived and canMove(ch,token)
end
-- Short tween segments follow moving targets without locking onto an old position.
local function followMove(ch, destination, token, method, speed)
    if not canMove(ch,token) then return false end
    if method=="Teleport" then return move(ch,destination) end
    releaseAnchor()
    local root=rootOf(ch)
    local distance=(destination.Position-root.Position).Magnitude
    if distance<0.1 then return true end
    if speed<=0 then return false end
    local duration=math.min(distance/speed,0.2)
    local fraction=math.min(1,speed*duration/distance)
    local endpoint=root.CFrame:Lerp(destination,fraction)
    restoreCollisions()
    noclipCharacter=ch
    applyNoclip(ch)
    local tween=TweenService:Create(root,TweenInfo.new(math.max(duration,0.001),Enum.EasingStyle.Linear),
        {CFrame=endpoint})
    activeTween=tween
    tween:Play()
    while canMove(ch,token) and tween.PlaybackState==Enum.PlaybackState.Playing do task.wait(0.01) end
    local completed=tween.PlaybackState==Enum.PlaybackState.Completed
    if activeTween==tween then
        tween:Cancel()
        activeTween=nil
        restoreCollisions()
    end
    return completed and canMove(ch,token)
end
local function acornTarget(object,ch)
    local ok,result=pcall(function()
        local box,size
        if object:IsA("Model") then box,size=object:GetBoundingBox()
        else box,size=object.CFrame,object.Size end
        local root,h=rootOf(ch),ch:FindFirstChildOfClass("Humanoid")
        local height=(math.abs(box.RightVector.Y)*size.X+math.abs(box.UpVector.Y)*size.Y
            +math.abs(box.LookVector.Y)*size.Z)/2
        return CFrame.new(box.Position+Vector3.new(0,height+h.HipHeight+root.Size.Y/2+0.1+C.FarmOffset,0))
            *root.CFrame.Rotation
    end)
    return ok and result or nil
end

-- Halloween user interface.
local function create(class,properties,parent)
    local object=Instance.new(class)
    for k,v in pairs(properties) do object[k]=v end
    object.Parent=parent
    return object
end
local function rounded(object,radius)
    create("UICorner",{CornerRadius=UDim.new(0,radius or 9)},object)
end
local function label(properties,parent)
    local p={BackgroundTransparency=1,TextColor3=T.Text,Font=Enum.Font.Gotham,TextSize=12}
    for k,v in pairs(properties) do p[k]=v end
    return create("TextLabel",p,parent)
end
local function button(title,size,position,parent)
    local b=create("TextButton",{Size=size,Position=position,BackgroundColor3=T.Button,Text=title,
        TextColor3=T.Text,Font=Enum.Font.GothamBold,TextSize=13,AutoButtonColor=true},parent)
    rounded(b)
    create("UIStroke",{Color=T.Purple,Transparency=0.65,Thickness=1},b)
    return b
end
local guiProperties={Name="RetroPullGUI",ResetOnSpawn=false,
    Enabled=true,DisplayOrder=10000,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling}
local guiReady,gui=pcall(function() return create("ScreenGui",guiProperties,guiParent) end)
if not guiReady then gui=create("ScreenGui",guiProperties,playerGui) end
local booted,bootError=xpcall(function()
local host=create("Frame",{Size=UDim2.fromOffset(680,760),Position=UDim2.fromScale(0.5,0.5),
    AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1},gui)
local scale=create("UIScale",{Scale=1},host)
U.chrome=create("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=T.Background},host)
rounded(U.chrome,16)
create("UIStroke",{Color=T.Orange,Thickness=2},U.chrome)
U.navFrame=create("Frame",{Position=UDim2.fromOffset(14,54),Size=UDim2.new(1,-28,0,74),
    BackgroundTransparency=1},U.chrome)
U.activity=create("Frame",{Position=UDim2.fromOffset(14,138),Size=UDim2.new(1,-28,0,78),
    BackgroundColor3=T.Panel},U.chrome)
rounded(U.activity,10)
label({Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-110,0,16),Text="CURRENT ACTION",
    TextSize=11,TextColor3=T.Muted,TextXAlignment=Enum.TextXAlignment.Left},U.activity)
U.phase=label({Position=UDim2.new(1,-106,0,8),Size=UDim2.fromOffset(94,18),Text="IDLE",
    TextSize=11,Font=Enum.Font.GothamBold,TextColor3=T.Orange,TextXAlignment=Enum.TextXAlignment.Right},U.activity)
U.action=label({Position=UDim2.fromOffset(12,29),Size=UDim2.new(1,-24,0,23),Text="Ready to start",
    Font=Enum.Font.GothamBold,TextSize=16,TextTruncate=Enum.TextTruncate.AtEnd,
    TextXAlignment=Enum.TextXAlignment.Left},U.activity)
U.actionDetail=label({Position=UDim2.fromOffset(12,54),Size=UDim2.new(1,-24,0,18),
    Text="Choose a feature below.",TextSize=12,TextColor3=T.Muted,
    TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left},U.activity)
U.stop=button("Stop all actions",UDim2.new(0.5,-20,0,38),UDim2.new(0,14,1,-50),U.chrome)
U.stop.BackgroundColor3=Color3.fromRGB(105,29,35)
U.footer=label({Position=UDim2.new(0.5,4,1,-50),Size=UDim2.new(0.5,-18,0,38),
    Text="HALLOWEEN EDITION\nMade by Retro",TextSize=11,TextColor3=T.Muted},U.chrome)
U.reopen=button("🎃",UDim2.fromOffset(60,60),UDim2.new(1,-72,0.5,-30),gui)
U.reopen.Name="PanelBubble"
U.reopen.Active=true
U.reopen.TextSize=28
U.reopen.ZIndex=20
U.reopen.AutoButtonColor=true
U.reopen.BackgroundColor3=T.Active
U.reopen:FindFirstChildWhichIsA("UICorner").CornerRadius=UDim.new(1,0)
U.reopen:FindFirstChildWhichIsA("UIStroke").Thickness=2
local function window(name)
    local f=create("Frame",{Name=name,Position=UDim2.fromOffset(14,228),Size=UDim2.new(1,-28,1,-292),
        BackgroundColor3=T.Background,Active=true},host)
    rounded(f,10)
    return f
end
local main,settings,servers,biomes=window("Main"),window("Settings"),window("ServerBrowser"),window("Biomes")
settings.Visible,servers.Visible,biomes.Visible=false,false,false
local function header(parent,title)
    local h=create("Frame",{Size=UDim2.new(1,0,0,48),BackgroundTransparency=1,Active=true},parent)
    label({Size=UDim2.new(1,-94,1,0),Position=UDim2.fromOffset(12,0),Text=title,
        TextColor3=T.Orange,Font=Enum.Font.GothamBold,TextSize=14,TextXAlignment=Enum.TextXAlignment.Left},h)
    return h
end
U.header=header(U.chrome,"🎃 RETRO  /  HALLOWEEN HUB")
local mainHeader=header(main,"FARM AUTOMATION")
local minimize=button("−",UDim2.fromOffset(30,28),UDim2.new(1,-72,0,10),mainHeader)
local close=button("×",UDim2.fromOffset(30,28),UDim2.new(1,-36,0,10),mainHeader)
minimize.Parent,close.Parent=U.header,U.header
U.intro=label({Position=UDim2.fromOffset(12,44),Size=UDim2.new(1,-24,0,48),TextWrapped=true,
    Text="Choose what to collect. The status above explains the current action.",TextSize=14,
    TextColor3=T.Muted,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},main)
local content=create("ScrollingFrame",{Position=UDim2.fromOffset(12,100),Size=UDim2.new(1,-24,1,-112),
    BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=4,ScrollBarImageColor3=T.Orange},main)
create("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder},content)
U.legacy=create("Frame",{Size=UDim2.new(),Visible=false},main)
local settingsButton=button("Settings",UDim2.new(),UDim2.new(),U.legacy)
local serversButton=button("Servers",UDim2.new(),UDim2.new(),U.legacy)
local biomesButton=button("Biomes",UDim2.new(),UDim2.new(),U.legacy)
local status=label({Size=UDim2.new(),Text="Ready."},U.legacy)
U.info={
    Orbs={Group="Farm",Setting="Orbs",Description="Collect the selected orb colors, then return to your saved position."},
    AutoFarm={Group="Farm",Setting="Acorns",Description="Stay on an Acorn until it disappears, then find the next one."},
    KillBugs={Group="Combat",Setting="Bugs",Description="Follow selected bug types until they disappear. Choose types in Edit settings."},
    KillPlayers={Group="Combat",Setting="Combat",Description="Follow the nearest living player. Switch targets when they die or leave."},
    AntiPlayer={Group="Safety",Setting="Safety",Description="Move to a temporary platform when another player gets too close."},
    AntiVoid={Group="Safety",Setting="Safety",Description="Return to a saved position if you fall below the rescue height."},
    SafeZone={Group="Safety",Setting="Safety",Description="Create a platform above you. Turning this off returns you to the saved starting position."},
    CustomSpeed={Group="Player",Setting="Player",Description="Use your chosen walking speed. Turning this off restores your previous speed."},
}
local function refreshToggle(key)
    local b=buttons[key]
    if not b then return end
    b.Text=E[key] and "Turn off" or "Turn on"
    b.BackgroundColor3=E[key] and T.Active or T.Button
end
local function addToggle(key,title,order)
    local info=U.info[key]
    local card=create("Frame",{Name=key,Size=UDim2.new(1,-8,0,172),BackgroundColor3=T.Panel,
        LayoutOrder=order,Visible=info.Group==U.Group},content)
    rounded(card,12)
    label({Position=UDim2.fromOffset(14,12),Size=UDim2.new(1,-130,0,25),Text=title,
        Font=Enum.Font.GothamBold,TextSize=16,TextXAlignment=Enum.TextXAlignment.Left},card)
    local description=label({Position=UDim2.fromOffset(14,46),Size=UDim2.new(1,-28,0,42),Text=info.Description,
        TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top},card)
    local b=button("",UDim2.fromOffset(94,34),UDim2.new(1,-108,0,10),card)
    local stateLabel=label({Position=UDim2.fromOffset(14,92),Size=UDim2.new(1,-28,0,20),
        Text="OFF • ready to start",TextSize=12,TextColor3=T.Muted,TextTruncate=Enum.TextTruncate.AtEnd,
        TextXAlignment=Enum.TextXAlignment.Left},card)
    local detailLabel=label({Position=UDim2.fromOffset(14,115),Size=UDim2.new(1,-28,0,18),
        Text="",TextSize=12,TextColor3=T.Muted,TextTruncate=Enum.TextTruncate.AtEnd,
        TextXAlignment=Enum.TextXAlignment.Left},card)
    local configure=button("Edit settings",UDim2.fromOffset(124,26),UDim2.fromOffset(14,140),card)
    U.Cards[key]={Frame=card,State=stateLabel,Detail=detailLabel,Description=description,Configure=configure}
    connect(configure.Activated,function()
        if U.goToSettings then U.goToSettings(info.Setting) end
    end)
    buttons[key],labels[key]=b,title
    refreshToggle(key)
    connect(b.Activated,function()
        if key=="SafeZone" then
            if refuge then stopRefuge(true) end
            cancelMotion()
            if E.SafeZone then E.SafeZone=false; leaveSafe() else E.SafeZone=enterSafe() end
        elseif key=="AntiPlayer" then
            E[key]=not E[key]
            if not E[key] and refuge then stopRefuge(true) end
            M.AntiPlayer=E[key] and "Anti Player: monitoring" or "Anti Player: OFF"
        elseif key=="AntiVoid" then
            E[key]=not E[key]
            M.AntiVoid=E[key] and "Anti Void: ON" or "Anti Void: OFF"
        elseif key=="CustomSpeed" then
            E[key]=not E[key]
            updateSpeed()
        else
            E[key]=not E[key]
            if key=="Orbs" or key=="AutoFarm" or key=="KillBugs" or key=="KillPlayers" then cancelMotion()
            end
        end
        refreshToggle(key)
    end)
end
addToggle("Orbs","Auto Farm Orbs",1)
addToggle("AutoFarm","Auto Farm Acorns",2)
addToggle("KillBugs","Kill Bugs",3)
addToggle("KillPlayers","Kill Players",4)
addToggle("AntiPlayer","Anti Player",5)
addToggle("AntiVoid","Anti Void",6)
addToggle("SafeZone","Safe Platform",7)
addToggle("CustomSpeed","Walk Speed",8)
U.guide=label({Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=14,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,Visible=false,
    Text="GET STARTED\n\n1. Open Farm or Combat and turn on one movement feature.\n\n2. Use Edit settings to choose Teleport or Tween, speed and height.\n\n3. Read CURRENT ACTION to see the target or why movement is paused.\n\n4. Use Stop all actions to stop and release movement. Anti Void stays enabled.\n\nPANEL CONTROLS\nTap the floating pumpkin bubble to close or reopen the whole panel on mobile or PC. On PC, Right Shift does the same thing. The bubble stays visible.\n\nMOVEMENT PRIORITY\nAnti Player protection > Follow Players > Follow Bugs > Acorns > Orbs.\nAn enabled feature lower in this list waits its turn.\n\nRETURNS\nFarms save a return point before moving. Turning them off returns you there.\n\nFAST MODE\nFast visits orbs for 0.01s. The game may miss some collections. Damage and spawn timing are game-controlled."},content)
local function showWindow(selected)
    main.Visible,settings.Visible,servers.Visible=selected==main,selected==settings,selected==servers
    biomes.Visible=selected==biomes
    U.ActiveTab=selected==main and U.Group or selected==settings and "Settings"
        or selected==servers and "Servers" or "Biomes"
    for name,tab in pairs(U.Nav) do
        tab.BackgroundColor3=name==U.ActiveTab and T.Active or T.Button
    end
end
U.navigate=function(name)
    if name=="Settings" then showWindow(settings)
    elseif name=="Servers" then showWindow(servers)
    elseif name=="Biomes" then showWindow(biomes)
    else
        U.Group=name
        for key,card in pairs(U.Cards) do card.Frame.Visible=U.info[key].Group==name end
        U.guide.Visible=name=="Guide"
        for _,child in ipairs(mainHeader:GetChildren()) do
            if child:IsA("TextLabel") then child.Text=name:upper() end
        end
        U.intro.Text=({Farm="Choose one farm. Other enabled farms wait their turn.",
            Combat="Follow a target using Teleport or Tween. The game controls bite damage.",
            Safety="Protection can pause farming automatically. Distances are editable.",
            Player="Control your character's walking speed independently of tween speed.",
            Guide="A quick explanation of the controls and priorities."})[name] or ""
        content.CanvasPosition=Vector2.zero
        showWindow(main)
    end
end
for index,name in ipairs({"Farm","Combat","Safety","Player","Biomes","Servers","Settings","Guide"}) do
    local column=(index-1)%4
    local row=math.floor((index-1)/4)
    local tab=button(name,UDim2.new(0.25,-6,0,34),UDim2.new(column*0.25,3,row*0.54,0),U.navFrame)
    U.Nav[name]=tab
    local selected=name
    connect(tab.Activated,function() U.navigate(selected) end)
end
U.navigate("Farm")
connect(U.stop.Activated,function()
    autoHop=false
    scanToken=scanToken+1
    for key in pairs(E) do E[key]=key=="AntiVoid" end
    if refuge then stopRefuge(true) end
    cancelMotion()
    leaveSafe()
    restoreSpeed()
    followedPlayer=nil
    for key in pairs(buttons) do refreshToggle(key) end
    if refreshServerControls then refreshServerControls() end
    U.ToastUntil=os.clock()+4
    U.Toast="All actions stopped. Anti Void is still on."
end)
local settingsHeader=header(settings,"🕸 HALLOWEEN SETTINGS")
local settingsBack=button("Back",UDim2.fromOffset(72,28),UDim2.new(1,-84,0,10),settingsHeader)
U.settingNav=create("ScrollingFrame",{Position=UDim2.fromOffset(12,48),Size=UDim2.new(1,-24,0,40),
    BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.X,
    ScrollingDirection=Enum.ScrollingDirection.X,ScrollBarThickness=3,ScrollBarImageColor3=T.Purple},settings)
create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),
    SortOrder=Enum.SortOrder.LayoutOrder},U.settingNav)
local scroll=create("ScrollingFrame",{Position=UDim2.fromOffset(12,96),Size=UDim2.new(1,-24,1,-158),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=T.Orange,
    CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},settings)
create("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},scroll)
local notice=label({Position=UDim2.new(0,12,1,-24),Size=UDim2.new(1,-24,0,18),
    Text="No maximum cap. Enter finite numbers.",TextSize=10},settings)
local modeButton=button("",UDim2.new(1,-8,0,40),UDim2.new(),scroll)
modeButton.LayoutOrder=1
local methodButton=button("",UDim2.new(1,-8,0,40),UDim2.new(),scroll)
methodButton.LayoutOrder=2
local acornModeButton=button("",UDim2.new(1,-8,0,40),UDim2.new(),scroll)
acornModeButton.LayoutOrder=3
local function refreshModes()
    modeButton.Text="Orb Speed: "..C.OrbMode.."  [Change]"
    methodButton.Text="Orb Method: "..C.OrbMethod.."  [Change]"
    acornModeButton.Text="Acorn Speed: "..C.AcornMode.."  [Change]"
    if U.MethodButtons then
        for key,data in pairs(U.MethodButtons) do data.Button.Text=data.Title..": "..C[key].."  [Change]" end
    end
end
connect(modeButton.Activated,function()
    C.OrbMode=({Slow="Medium",Medium="Fast",Fast="Slow",Custom="Slow"})[C.OrbMode] or "Slow"
    C.OrbDelay=({Slow=0.45,Medium=0.15,Fast=0.01})[C.OrbMode]
    if fields.OrbDelay then fields.OrbDelay.Text=tostring(C.OrbDelay) end
    if not E.AutoFarm and not E.KillBugs and not E.KillPlayers then cancelMotion() end
    refreshModes()
    notice.Text=C.OrbMode=="Fast" and "Fast: 0.01s contact; one visit per orb." or "Speed updated."
end)
connect(methodButton.Activated,function()
    C.OrbMethod=C.OrbMethod=="Teleport" and "Direct Tween + Noclip" or "Teleport"
    if not E.AutoFarm and not E.KillBugs and not E.KillPlayers then cancelMotion() end
    refreshModes()
end)
connect(acornModeButton.Activated,function()
    C.AcornMode=({Slow="Medium",Medium="Fast",Fast="Slow",Custom="Slow"})[C.AcornMode] or "Slow"
    C.FarmInterval=({Slow=0.45,Medium=0.15,Fast=0.01})[C.AcornMode]
    if fields.FarmInterval then fields.FarmInterval.Text=tostring(C.FarmInterval) end
    refreshModes()
    notice.Text="Acorns: "..C.AcornMode.." • follow interval "..C.FarmInterval.."s. Damage is game-controlled."
end)
refreshModes()
local dropdown=create("Frame",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundColor3=T.Panel,LayoutOrder=4},scroll)
rounded(dropdown)
U.SettingsRows={
    {Object=modeButton,Group="Orbs"},{Object=methodButton,Group="Orbs"},
    {Object=acornModeButton,Group="Acorns"},{Object=dropdown,Group="Orbs"},
}
local panelHelp=label({Size=UDim2.new(1,-8,0,64),TextWrapped=true,
    Text="PANEL CONTROLS  🎃\nTap the floating bubble on mobile or PC to open/close the panel. PC shortcut: Right Shift.",
    TextSize=13,TextXAlignment=Enum.TextXAlignment.Left},scroll)
panelHelp.LayoutOrder=90
table.insert(U.SettingsRows,{Object=panelHelp,Group="Player"})
U.MethodButtons={}
for index,entry in ipairs({{"AcornMethod","Acorn movement","Acorns"},
    {"BugMethod","Bug movement","Bugs"},{"PlayerMethod","Player movement","Combat"}}) do
    local key,title,group=table.unpack(entry)
    local control=button("",UDim2.new(1,-8,0,44),UDim2.new(),scroll)
    control.LayoutOrder=4+index
    U.MethodButtons[key]={Button=control,Title=title}
    table.insert(U.SettingsRows,{Object=control,Group=group})
    connect(control.Activated,function()
        C[key]=C[key]=="Teleport" and "Tween" or "Teleport"
        cancelMotion()
        refreshModes()
        notice.Text=title.." changed to "..C[key].."."
    end)
end
refreshModes()
-- Dynamic multi-select of bug Model names. New types follow the latest All/None choice.
U.bugPanel=create("Frame",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundColor3=T.Panel,LayoutOrder=4},scroll)
rounded(U.bugPanel)
table.insert(U.SettingsRows,{Object=U.bugPanel,Group="Bugs"})
create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},U.bugPanel)
U.bugButton=button("Bug Types ▼",UDim2.new(1,0,0,44),UDim2.new(),U.bugPanel)
U.bugButton.LayoutOrder=1
U.bugBody=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=false,LayoutOrder=2},U.bugPanel)
create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},U.bugBody)
U.bugActions=create("Frame",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,LayoutOrder=1},U.bugBody)
U.bugAll=button("Select All",UDim2.new(0.5,-8,1,0),UDim2.fromOffset(4,0),U.bugActions)
U.bugNone=button("Select None",UDim2.new(0.5,-8,1,0),UDim2.new(0.5,4,0,0),U.bugActions)
U.bugList=create("ScrollingFrame",{Size=UDim2.new(1,0,0,180),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=5,ScrollBarImageColor3=T.Orange,CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,LayoutOrder=2},U.bugBody)
create("UIListLayout",{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.Name},U.bugList)
U.bugEmpty=label({Name="000_Empty",Size=UDim2.new(1,-8,0,50),
    Text="Waiting for bug models in Workspace.Bugs...",TextWrapped=true},U.bugList)
U.bugSelected=function(name)
    local selected=U.BugSelection[name]
    if selected==nil then return U.BugDefault end
    return selected
end
U.refreshBugRows=function()
    local selected,total=0,0
    for name,info in pairs(U.KnownBugs) do
        total=total+1
        local active=U.bugSelected(name)
        if active then selected=selected+1 end
        local row=U.BugRows[name]
        if row then
            row.Text=(active and "[✓] " or "[ ] ")..name.."  •  "..info.Count.." available"
            row.BackgroundColor3=active and T.Active or T.Button
        end
    end
    U.bugButton.Text="Bug Types • "..selected.."/"..total..(U.bugBody.Visible and " ▲" or " ▼")
end
U.bugFiltersChanged=function()
    if E.KillBugs and not E.KillPlayers then cancelMotion() end
    U.refreshBugRows()
end
connect(U.bugButton.Activated,function() U.bugBody.Visible=not U.bugBody.Visible; U.refreshBugRows() end)
connect(U.bugAll.Activated,function() U.BugDefault=true; table.clear(U.BugSelection); U.bugFiltersChanged() end)
connect(U.bugNone.Activated,function() U.BugDefault=false; table.clear(U.BugSelection); U.bugFiltersChanged() end)
U.gatherBugs=function(container,output)
    for _,object in ipairs(container:GetChildren()) do
        if object:IsA("Model") then
            if object:FindFirstChildWhichIsA("BasePart",true) then table.insert(output,object) end
        elseif object:IsA("Folder") then U.gatherBugs(object,output) end
    end
end
U.scanBugs=function()
    for _,info in pairs(U.KnownBugs) do info.Count=0 end
    local folder=workspace:FindFirstChild("Bugs")
    local bugs={}
    if folder then U.gatherBugs(folder,bugs) end
    for _,bug in ipairs(bugs) do
        local name=bug.Name
        if not U.KnownBugs[name] then U.KnownBugs[name]={Count=0} end
        U.KnownBugs[name].Count=U.KnownBugs[name].Count+1
        if not U.BugRows[name] then
            local row=button("",UDim2.new(1,-8,0,44),UDim2.new(),U.bugList)
            row.Name=name
            U.BugRows[name]=row
            local chosenName=name
            connect(row.Activated,function()
                U.BugSelection[chosenName]=not U.bugSelected(chosenName)
                U.bugFiltersChanged()
            end)
        end
    end
    U.bugEmpty.Visible=next(U.KnownBugs)==nil
    U.refreshBugRows()
end
-- Dynamic multi-select of acorn Model names. New types follow the latest All/None choice.
U.acornPanel=create("Frame",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundColor3=T.Panel,LayoutOrder=4},scroll)
rounded(U.acornPanel)
table.insert(U.SettingsRows,{Object=U.acornPanel,Group="Acorns"})
create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},U.acornPanel)
U.acornButton=button("Acorn Types ▼",UDim2.new(1,0,0,44),UDim2.new(),U.acornPanel)
U.acornButton.LayoutOrder=1
U.acornBody=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=false,LayoutOrder=2},U.acornPanel)
create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},U.acornBody)
U.acornActions=create("Frame",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,LayoutOrder=1},U.acornBody)
U.acornAll=button("Select All",UDim2.new(0.5,-8,1,0),UDim2.fromOffset(4,0),U.acornActions)
U.acornNone=button("Select None",UDim2.new(0.5,-8,1,0),UDim2.new(0.5,4,0,0),U.acornActions)
U.acornList=create("ScrollingFrame",{Size=UDim2.new(1,0,0,180),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=5,ScrollBarImageColor3=T.Orange,CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,LayoutOrder=2},U.acornBody)
create("UIListLayout",{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.Name},U.acornList)
U.acornEmpty=label({Name="000_Empty",Size=UDim2.new(1,-8,0,50),
    Text="Waiting for acorn models in Workspace.Breakables...",TextWrapped=true},U.acornList)
U.acornSelected=function(name)
    local selected=U.AcornSelection[name]
    if selected==nil then return U.AcornDefault end
    return selected
end
U.refreshAcornRows=function()
    local selected,total=0,0
    for name,info in pairs(U.KnownAcorns) do
        total=total+1
        local active=U.acornSelected(name)
        if active then selected=selected+1 end
        local row=U.AcornRows[name]
        if row then
            row.Text=(active and "[✓] " or "[ ] ")..name.."  •  "..info.Count.." available"
            row.BackgroundColor3=active and T.Active or T.Button
        end
    end
    U.acornButton.Text="Acorn Types • "..selected.."/"..total..(U.acornBody.Visible and " ▲" or " ▼")
end
U.acornFiltersChanged=function()
    if E.AutoFarm and not E.KillPlayers and not E.KillBugs then cancelMotion() end
    U.refreshAcornRows()
end
connect(U.acornButton.Activated,function() U.acornBody.Visible=not U.acornBody.Visible; U.refreshAcornRows() end)
connect(U.acornAll.Activated,function() U.AcornDefault=true; table.clear(U.AcornSelection); U.acornFiltersChanged() end)
connect(U.acornNone.Activated,function() U.AcornDefault=false; table.clear(U.AcornSelection); U.acornFiltersChanged() end)
U.gatherAcorns=function(container,output)
    for _,object in ipairs(container:GetChildren()) do
        if object:IsA("Model") then
            if object:FindFirstChildWhichIsA("BasePart",true) then table.insert(output,object) end
        elseif object:IsA("Folder") then U.gatherAcorns(object,output) end
    end
end
U.scanAcorns=function()
    for _,info in pairs(U.KnownAcorns) do info.Count=0 end
    local folder=workspace:FindFirstChild("Breakables")
    local acorns={}
    if folder then U.gatherAcorns(folder,acorns) end
    for _,acorn in ipairs(acorns) do
        local name=acorn.Name
        if not U.KnownAcorns[name] then U.KnownAcorns[name]={Count=0} end
        U.KnownAcorns[name].Count=U.KnownAcorns[name].Count+1
        if not U.AcornRows[name] then
            local row=button("",UDim2.new(1,-8,0,44),UDim2.new(),U.acornList)
            row.Name=name
            U.AcornRows[name]=row
            local chosenName=name
            connect(row.Activated,function()
                U.AcornSelection[chosenName]=not U.acornSelected(chosenName)
                U.acornFiltersChanged()
            end)
        end
    end
    U.acornEmpty.Visible=next(U.KnownAcorns)==nil
    U.refreshAcornRows()
end
create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},dropdown)
local colorButton=button("Orb Colors ▼",UDim2.new(1,0,0,40),UDim2.new(),dropdown)
colorButton.LayoutOrder=1
local colorBody=create("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Visible=false,LayoutOrder=2},dropdown)
create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},colorBody)
local actions=create("Frame",{Size=UDim2.new(1,0,0,30),BackgroundTransparency=1,LayoutOrder=1},colorBody)
local allColors=button("Select All",UDim2.new(0.5,-8,1,0),UDim2.fromOffset(4,0),actions)
local noColors=button("Select None",UDim2.new(0.5,-8,1,0),UDim2.new(0.5,4,0,0),actions)
local colorList=create("ScrollingFrame",{Size=UDim2.new(1,0,0,170),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=T.Purple,CanvasSize=UDim2.new(),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,LayoutOrder=2},colorBody)
create("UIListLayout",{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.Name},colorList)
local emptyColors=label({Name="000_Empty",Size=UDim2.new(1,-8,0,42),Text="Waiting for Workspace.Orbs...",
    TextWrapped=true},colorList)
refreshColors=function()
    local count,total=0,0
    for key,info in pairs(knownColors) do
        total=total+1
        local chosen=colorSelected(key)
        if chosen then count=count+1 end
        local row=colorRows[key]
        if row then
            row.Text=(chosen and "[✓] " or "[ ] ")..colorName(info.Color).." • "..info.Count.."\nRGB "..key
            row.BackgroundColor3=chosen and T.Active or T.Button
        end
    end
    colorButton.Text="Orb Colors • "..count.."/"..total..(colorBody.Visible and " ▲" or " ▼")
end
local function filtersChanged()
    if not E.AutoFarm and not E.KillBugs and not E.KillPlayers then cancelMotion() end
    refreshColors()
end
connect(colorButton.Activated,function() colorBody.Visible=not colorBody.Visible; refreshColors() end)
connect(allColors.Activated,function() defaultColorSelected=true; table.clear(selectedColors); filtersChanged() end)
connect(noColors.Activated,function() defaultColorSelected=false; table.clear(selectedColors); filtersChanged() end)
local function scanColors()
    for _,info in pairs(knownColors) do info.Count=0 end
    local folder,objects=workspace:FindFirstChild("Orbs"),{}
    if folder then gather(folder,objects) end
    for _,object in ipairs(objects) do
        local key,color=colorInfo(object)
        if key then
            if not knownColors[key] then knownColors[key]={Color=color,Count=0} end
            knownColors[key].Count=knownColors[key].Count+1
            if not colorRows[key] then
                local row=create("Frame",{Name=key,Size=UDim2.new(1,-8,0,46),BackgroundTransparency=1},colorList)
                local swatch=create("Frame",{Size=UDim2.fromOffset(24,24),Position=UDim2.fromOffset(4,11),
                    BackgroundColor3=color},row)
                rounded(swatch,6)
                local choice=button("",UDim2.new(1,-36,1,0),UDim2.fromOffset(34,0),row)
                choice.TextSize=11
                colorRows[key]=choice
                local selectedKey=key
                connect(choice.Activated,function()
                    selectedColors[selectedKey]=not colorSelected(selectedKey); filtersChanged()
                end)
            end
        end
    end
    emptyColors.Visible=next(knownColors)==nil
    refreshColors()
end
local specs={
    {"WalkSpeed","Character Walk Speed (studs/second)","Enable Custom Walk Speed. Zero or positive; no maximum cap."},
    {"OrbDelay","Orb Contact Delay (seconds)","Fast uses 0.01s. Editing selects Custom."},
    {"AttemptsPerOrb","Attempts Per Orb","Fast visits each orb once.","integer"},
    {"SweepInterval","Target Search Interval (seconds)","Does not change the game's spawn timer."},
    {"TweenSpeed","Direct Tween Speed (studs/second)","Must be greater than zero.","positive"},
    {"FarmInterval","Acorn Follow Interval (seconds)","Editing selects Custom. Stays until the target disappears."},
    {"FarmOffset","Acorn Extra Height (studs)","Negative values allowed.","signed"},
    {"AcornTweenSpeed","Acorn Tween Speed (studs/second)","Used only when Acorn movement is Tween.","positive"},
    {"BugHeight","Bug Contact Height (studs)","Default: 1.5. Large heights may put you outside bite range."},
    {"BugInterval","Bug Contact Interval (seconds)","Default: 0.15s. Character stays unanchored while biting."},
    {"BugTweenSpeed","Bug Tween Speed (studs/second)","Used only when Bug movement is Tween.","positive"},
    {"PlayerFollowHeight","Player Follow Height (studs)","Default: 5 studs above the player's root."},
    {"PlayerFollowInterval","Player Follow Interval (seconds)","Anchored tracking. Anti Player ignores this target."},
    {"PlayerTweenSpeed","Player Tween Speed (studs/second)","Tween tracking stays unanchored.","positive"},
    {"PlayerTrigger","Anti Player Trigger Distance","Default: 20 studs."},
    {"PlayerRelease","Anti Player Release Distance","Measured from the trigger location. Default: 500."},
    {"AntiHeight","Anti Player Platform Height","Default: 50 studs."},
    {"VoidHeight","Anti Void Rescue Y","World Y coordinate for rescue.","signed"},
    {"SafeHeight","Safe Zone Height (studs)","Applied on next activation."},
    {"ServerRetryDelay","Auto Hop Retry Delay (seconds)","Wait between completed scans without matches.","positive"},
}
for order,spec in ipairs(specs) do
    local key,title,hint,kind=table.unpack(spec)
    local row=create("Frame",{Size=UDim2.new(1,-8,0,106),BackgroundColor3=T.Panel,LayoutOrder=order+10},scroll)
    rounded(row)
    local groups={WalkSpeed="Player",OrbDelay="Orbs",AttemptsPerOrb="Orbs",TweenSpeed="Orbs",
        SweepInterval="General",FarmInterval="Acorns",FarmOffset="Acorns",AcornTweenSpeed="Acorns",
        BugHeight="Bugs",BugInterval="Bugs",BugTweenSpeed="Bugs",PlayerFollowHeight="Combat",
        PlayerFollowInterval="Combat",PlayerTweenSpeed="Combat",PlayerTrigger="Safety",PlayerRelease="Safety",
        AntiHeight="Safety",VoidHeight="Safety",SafeHeight="Safety",ServerRetryDelay="Servers"}
    table.insert(U.SettingsRows,{Object=row,Group=groups[key] or "General"})
    label({Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-24,0,26),Text=title,
        Font=Enum.Font.GothamBold,TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},row)
    local box=create("TextBox",{Position=UDim2.fromOffset(12,39),Size=UDim2.new(1,-24,0,30),
        BackgroundColor3=T.Button,TextColor3=T.Text,Font=Enum.Font.Gotham,TextSize=14,
        Text=tostring(C[key]),ClearTextOnFocus=false},row)
    rounded(box,5)
    fields[key]=box
    label({Position=UDim2.fromOffset(12,74),Size=UDim2.new(1,-24,0,28),Text=hint,TextSize=12,
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},row)
    connect(box.FocusLost,function()
        local value=tonumber((box.Text:gsub(",",".")))
        local invalid=not value or value~=value or math.abs(value)==math.huge
        if not invalid then
            if kind=="integer" then invalid=value<1 or value%1~=0
            elseif kind=="positive" then invalid=value<=0
            elseif kind~="signed" then invalid=value<0 end
        end
        if invalid then
            box.Text=tostring(C[key]); box.TextColor3=Color3.fromRGB(255,130,130)
            notice.Text="Invalid number. The previous value was kept."
            return
        end
        C[key]=value
        box.TextColor3=T.Text
        box.Text=tostring(value)
        if key=="WalkSpeed" then updateSpeed() end
        if key=="OrbDelay" then C.OrbMode="Custom"; refreshModes() end
        if key=="FarmInterval" then C.AcornMode="Custom"; refreshModes() end
        notice.Text="Settings updated."
    end)
end
local reset=button("Restore Defaults",UDim2.new(1,-24,0,28),UDim2.new(0,12,1,-58),settings)
connect(reset.Activated,function()
    for key,value in pairs(defaults) do C[key]=value; if fields[key] then fields[key].Text=tostring(value) end end
    defaultColorSelected=true
    U.BugDefault=true
    table.clear(U.BugSelection)
    U.refreshBugRows()
    U.AcornDefault=true
    table.clear(U.AcornSelection)
    U.refreshAcornRows()
    if E.AutoFarm and not E.KillPlayers and not E.KillBugs then cancelMotion() end
    table.clear(selectedColors)
    filtersChanged(); refreshModes()
    notice.Text="Default settings restored."
end)
U.settingButtons={}
U.setSettingsFilter=function(group)
    U.SettingTab=group
    for _,entry in ipairs(U.SettingsRows) do
        entry.Object.Visible=group=="All" or entry.Group==group
            or (entry.Group=="General" and (group=="Orbs" or group=="Acorns" or group=="Combat"))
    end
    for name,control in pairs(U.settingButtons) do
        control.BackgroundColor3=name==group and T.Active or T.Button
    end
    scroll.CanvasPosition=Vector2.zero
end
for index,name in ipairs({"Orbs","Acorns","Bugs","Combat","Safety","Player","Servers","All"}) do
    local control=button(name,UDim2.fromOffset(92,34),UDim2.new(),U.settingNav)
    control.LayoutOrder=index
    U.settingButtons[name]=control
    local group=name
    connect(control.Activated,function() U.setSettingsFilter(group) end)
end
U.setSettingsFilter("Orbs")
U.goToSettings=function(group)
    U.setSettingsFilter(group)
    U.navigate("Settings")
end

-- Server Hop window. Counts are a snapshot before joining.
local serverHeader=header(servers,"🦇 HALLOWEEN SERVER HOP")
local serverBack=button("Back",UDim2.fromOffset(72,28),UDim2.new(1,-84,0,10),serverHeader)
label({Position=UDim2.fromOffset(12,52),Size=UDim2.new(1,-24,0,45),TextWrapped=true,
    Text="PUBLIC SERVERS • 1-3 PLAYERS\nSorted by lowest player count. Counts may change.",TextColor3=T.Orange},servers)
local scanButton=button("Scan Servers",UDim2.new(0.5,-16,0,36),UDim2.fromOffset(12,104),servers)
local autoButton=button("Auto Hop [OFF]",UDim2.new(0.5,-16,0,36),UDim2.new(0.5,4,0,104),servers)
local hopStatus=label({Position=UDim2.fromOffset(12,148),Size=UDim2.new(1,-24,0,70),
    Text=serverMessage,TextWrapped=true,TextSize=11},servers)
local serverList=create("ScrollingFrame",{Position=UDim2.fromOffset(12,226),Size=UDim2.new(1,-24,1,-270),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=T.Orange,
    CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},servers)
create("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},serverList)
label({Position=UDim2.new(0,12,1,-36),Size=UDim2.new(1,-24,0,26),TextSize=10,TextWrapped=true,
    Text="Current server excluded • Re-run the script after hopping."},servers)
local function setServerMessage(message)
    serverMessage=message
    if running then hopStatus.Text=message end
end
refreshServerControls=function()
    scanButton.Text=scanBusy and "Stop Scan" or "Scan Servers"
    autoButton.Text=autoHop and "Auto Hop [ON]" or "Auto Hop [OFF]"
    autoButton.BackgroundColor3=autoHop and T.Active or T.Button
end
local function httpGet(url)
    local candidates={}
    if type(request)=="function" then table.insert(candidates,request) end
    if type(http_request)=="function" then table.insert(candidates,http_request) end
    if type(syn)=="table" and type(syn.request)=="function" then table.insert(candidates,syn.request) end
    if type(http)=="table" and type(http.request)=="function" then table.insert(candidates,http.request) end
    if type(fluxus)=="table" and type(fluxus.request)=="function" then table.insert(candidates,fluxus.request) end
    local requestFunction=candidates[1]
    if type(requestFunction)=="function" then
        local response=requestFunction({Url=url,Method="GET"})
        if type(response)~="table" then error("HTTP request returned no response") end
        local code=tonumber(response.StatusCode or response.Status)
        if code and (code<200 or code>=300) then error("HTTP "..code) end
        if type(response.Body)~="string" then error("HTTP response body is missing") end
        return response.Body
    end
    local ok,body=pcall(function() return game:HttpGet(url) end)
    if not ok then error("HTTP unavailable or blocked: "..tostring(body)) end
    return body
end
local function scanRound()
    if scanBusy or not running then return false end
    scanBusy=true
    scanToken=scanToken+1
    local token=scanToken
    serverResults={}
    renderServers()
    refreshServerControls()
    local cursor,seen,cursors=nil,{},{}
    local pages,inspected=0,0
    local scanError
    repeat
        local url="https://games.roblox.com/v1/games/"..tostring(game.PlaceId)
            .."/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
        if cursor then url=url.."&cursor="..HttpService:UrlEncode(cursor) end
        local decoded
        for attempt=1,3 do
            if not running or token~=scanToken then break end
            local ok,result=pcall(function() return HttpService:JSONDecode(httpGet(url)) end)
            if ok and type(result)=="table" and type(result.data)=="table" then
                decoded=result
                break
            end
            scanError=ok and "Unexpected server API response" or tostring(result)
            if attempt<3 then
                setServerMessage("Request failed. Retrying "..attempt.."/3...")
                local deadline=os.clock()+2^attempt
                while running and token==scanToken and os.clock()<deadline do task.wait(0.1) end
            end
        end
        if not running or token~=scanToken or not decoded then break end
        scanError=nil
        pages=pages+1
        for _,server in ipairs(decoded.data) do
            inspected=inspected+1
            local count=tonumber(server.playing)
            local capacity=tonumber(server.maxPlayers)
            if type(server.id)=="string" and count and capacity and server.id~=game.JobId
                and count>=1 and count<=3 and count<capacity and not seen[server.id] then
                seen[server.id]=true
                table.insert(serverResults,{id=server.id,playing=count,maxPlayers=capacity})
            end
        end
        table.sort(serverResults,function(a,b)
            if a.playing~=b.playing then return a.playing<b.playing end
            return a.id<b.id
        end)
        renderServers()
        setServerMessage("Scanning • pages: "..pages.." • checked: "..inspected
            .."\nMatches with 1-3 players: "..#serverResults)
        -- Auto Hop can use the first lowest-count matching page immediately.
        if autoHop and #serverResults>0 then break end
        cursor=decoded.nextPageCursor
        if type(cursor)~="string" or cursor=="" or cursors[cursor] then cursor=nil end
        if cursor then
            cursors[cursor]=true
            local deadline=os.clock()+0.8
            while running and token==scanToken and os.clock()<deadline do task.wait(0.1) end
        end
    until not cursor or not running or token~=scanToken
    local cancelled=token~=scanToken
    scanBusy=false
    if running then
        refreshServerControls()
        if hopPending then
            -- Preserve the join status when an in-flight scan is cancelled.
        elseif cancelled then setServerMessage("Scan stopped • matches: "..#serverResults)
        elseif scanError then setServerMessage("Scan failed: "..scanError)
        else setServerMessage("Scan finished • "..#serverResults.." matching servers\n1-3 players before joining • lowest count first") end
    end
    return not cancelled and not scanError
end
local function runScan()
    local ok, result = pcall(scanRound)
    if not ok then
        scanBusy = false
        if running then
            refreshServerControls()
            setServerMessage("Scan failed: " .. tostring(result))
        end
        return false
    end
    return result
end
local function joinServer(server)
    if not running or hopPending then return false end
    if server.id==game.JobId then return false end
    visitedServers[server.id]=true
    hopPending={Id=server.id,Started=os.clock()}
    if scanBusy then scanToken=scanToken+1 end
    if refuge then stopRefuge(true) end
    cancelMotion()
    setServerMessage("Joining "..server.id:sub(1,8).."... • "..server.playing.." players in last scan")
    renderServers()
    local ok,err=pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId,server.id,player)
    end)
    if not ok then
        hopPending=nil
        setServerMessage("Join failed: "..tostring(err))
        renderServers()
    end
    return ok
end
renderServers=function()
    for _,connection in ipairs(serverRowConnections) do connection:Disconnect() end
    table.clear(serverRowConnections)
    for _,child in ipairs(serverList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    if #serverResults==0 then
        label({Size=UDim2.new(1,-8,0,65),Text="No matches yet.\nPress Scan Servers or enable Auto Hop.",
            TextWrapped=true,TextColor3=T.Muted},serverList)
    end
    for i,server in ipairs(serverResults) do
        local row=create("Frame",{Size=UDim2.new(1,-8,0,70),BackgroundColor3=T.Panel,LayoutOrder=i},serverList)
        rounded(row)
        label({Position=UDim2.fromOffset(10,5),Size=UDim2.new(1,-94,1,-10),
            Text=string.format("#%d • %d/%d players\nID: %s...\n%s",i,server.playing,server.maxPlayers,
                server.id:sub(1,12),visitedServers[server.id] and "Previously attempted" or "Public server"),
            TextSize=11,TextXAlignment=Enum.TextXAlignment.Left},row)
        local join=button(hopPending and hopPending.Id==server.id and "Joining" or "Join",
            UDim2.fromOffset(70,34),UDim2.new(1,-80,0.5,-17),row)
        local chosen=server
        table.insert(serverRowConnections,join.Activated:Connect(function() joinServer(chosen) end))
    end
end
connect(scanButton.Activated,function()
    if scanBusy then scanToken=scanToken+1; autoHop=false; refreshServerControls()
    elseif not hopPending then task.spawn(runScan) end
end)
connect(autoButton.Activated,function()
    autoHop=not autoHop
    if not autoHop then
        scanToken=scanToken+1
        setServerMessage(hopPending and "Search stopped. A teleport was already submitted." or "Auto Hop stopped.")
    else
        setServerMessage("Auto Hop enabled. Searching for the emptiest 1-3 player server...")
    end
    refreshServerControls()
end)
connect(TeleportService.TeleportInitFailed,function(who,result,errorMessage,placeId,options)
    if who==player and hopPending and placeId==game.PlaceId then
        local failedId=options and options.ServerInstanceId
        if failedId and failedId~="" and failedId~=hopPending.Id then return end
        hopPending=nil
        setServerMessage("Teleport failed: "..tostring(errorMessage)..(autoHop and " • trying another server" or ""))
        renderServers()
    end
end)
renderServers()
refreshServerControls()

-- Map folders are discovered at runtime; no guessed biome coordinates.
local biomeHeader=header(biomes,"🧭 BIOME TELEPORTS")
local biomeBack=button("Back",UDim2.fromOffset(72,28),UDim2.new(1,-84,0,10),biomeHeader)
label({Position=UDim2.fromOffset(12,52),Size=UDim2.new(1,-24,0,52),TextWrapped=true,TextSize=11,
    Text="Loaded areas from Workspace.Map\nA solid surface is chosen inside each area.\nManual teleports stop automatic movement."},biomes)
local refreshBiomesButton=button("Refresh Areas",UDim2.new(0.5,-16,0,36),UDim2.fromOffset(12,112),biomes)
local returnBiomeButton=button("Return Previous",UDim2.new(0.5,-16,0,36),UDim2.new(0.5,4,0,112),biomes)
local biomeStatus=label({Position=UDim2.fromOffset(12,156),Size=UDim2.new(1,-24,0,50),TextWrapped=true,
    Text="Select an area to teleport.",TextSize=11},biomes)
local biomeList=create("ScrollingFrame",{Position=UDim2.fromOffset(12,216),Size=UDim2.new(1,-24,1,-232),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=T.Orange,
    CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},biomes)
create("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},biomeList)

local function biomeLanding(area,ch)
    local root=rootOf(ch)
    local humanoid=ch and ch:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then return nil end
    local parts=area:GetDescendants()
    if area:IsA("BasePart") then table.insert(parts,area) end
    local best,bestScore=nil,-math.huge
    for _,part in ipairs(parts) do
        if part:IsA("BasePart") and part.CanCollide and part.Transparency<0.99 then
            local size=part.Size
            local horizontal=size.X*size.Z
            local score=math.log(1+horizontal)
            local name=part.Name:lower()
            -- Prefer floor-like objects rather than the top of a tree or wall.
            if name:find("ground",1,true) or name:find("floor",1,true)
                or name:find("grass",1,true) or name:find("sand",1,true)
                or name:find("terrain",1,true) then score=score+100 end
            if size.Y>math.max(size.X,size.Z) then score=score-20 end
            if score>bestScore then best,bestScore=part,score end
        end
    end
    if not best then return nil end
    local box,size=best.CFrame,best.Size
    local vertical=(math.abs(box.RightVector.Y)*size.X+math.abs(box.UpVector.Y)*size.Y
        +math.abs(box.LookVector.Y)*size.Z)/2
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={best}
    params.RespectCanCollide=true
    local origin=box.Position+Vector3.new(0,vertical+5,0)
    local hit=workspace:Raycast(origin,Vector3.new(0,-(vertical*2+10),0),params)
    if not hit or hit.Normal.Y<0.35 then return nil end
    local position=hit.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2+0.5,0)
    local exclusions={ch}
    if safePlatform then table.insert(exclusions,safePlatform) end
    if refuge and refuge.Platform then table.insert(exclusions,refuge.Platform) end
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances=exclusions
    overlap.RespectCanCollide=true
    -- A little less than the character footprint, with headroom above the landing.
    local clearance=CFrame.new(position+Vector3.new(0,0.5,0))
    for _,part in ipairs(workspace:GetPartBoundsInBox(clearance,Vector3.new(2,3,2),overlap)) do
        if part~=best and part.CanCollide then return nil end
    end
    return CFrame.new(position)*root.CFrame.Rotation
end
local function stopForManualTeleport()
    for _,key in ipairs({"Orbs","AutoFarm","KillBugs","KillPlayers"}) do
        E[key]=false
        refreshToggle(key)
    end
    followedPlayer=nil
    if refuge then stopRefuge(true) end
    cancelMotion()
    if E.SafeZone or safePlatform then
        leaveSafe()
        E.SafeZone=false
        refreshToggle("SafeZone")
    end
end
local function teleportBiome(area)
    local ch=player.Character
    if hopPending then biomeStatus.Text="Wait for Server Hop to finish."; return end
    if not alive(ch) then biomeStatus.Text="Character unavailable."; return end
    local map=workspace:FindFirstChild("Map")
    if not map or not area:IsDescendantOf(map) then
        biomeStatus.Text="Area unavailable. Refresh the list."
        return
    end
    local ok,destination=pcall(biomeLanding,area,ch)
    if not ok or not destination then
        biomeStatus.Text="No clear solid landing found in "..area.Name.."."
        return
    end
    stopForManualTeleport()
    local previousPosition=rootOf(ch).CFrame
    if move(ch,destination) then
        biomeReturn={Character=ch,CFrame=previousPosition}
        checkpointCharacter,checkpoint=ch,destination
        biomeStatus.Text="Teleported to "..area.Name.."."
    else biomeStatus.Text="Teleport failed." end
end
local function refreshBiomes()
    for _,connection in ipairs(biomeRowConnections) do connection:Disconnect() end
    table.clear(biomeRowConnections)
    for _,child in ipairs(biomeList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    local map=workspace:FindFirstChild("Map")
    if not map then biomeStatus.Text="Workspace.Map is not currently loaded."; return end
    local areas={}
    for _,area in ipairs(map:GetChildren()) do
        if area:IsA("Folder") or area:IsA("Model") or area:IsA("BasePart") then
            table.insert(areas,area)
        end
    end
    table.sort(areas,function(a,b) return a.Name:lower()<b.Name:lower() end)
    for index,area in ipairs(areas) do
        local row=button("Teleport to "..area.Name,UDim2.new(1,-8,0,44),UDim2.new(),biomeList)
        row.LayoutOrder=index
        local selected=area
        table.insert(biomeRowConnections,row.Activated:Connect(function() teleportBiome(selected) end))
    end
    biomeStatus.Text=#areas.." loaded areas. Choose a destination."
end
connect(refreshBiomesButton.Activated,refreshBiomes)
connect(returnBiomeButton.Activated,function()
    local saved=biomeReturn
    if hopPending then biomeStatus.Text="Wait for Server Hop to finish."; return end
    if not saved or saved.Character~=player.Character or not alive(saved.Character) then
        biomeStatus.Text="No previous location for this character."
        return
    end
    stopForManualTeleport()
    if move(saved.Character,saved.CFrame) then
        checkpointCharacter,checkpoint=saved.Character,saved.CFrame
        biomeReturn=nil
        biomeStatus.Text="Returned to the previous location."
    else biomeStatus.Text="Return failed." end
end)
connect(biomesButton.Activated,function() showWindow(biomes); refreshBiomes() end)
connect(biomeBack.Activated,function() showWindow(main) end)
connect(settingsButton.Activated,function() showWindow(settings); scanColors() end)
connect(serversButton.Activated,function() showWindow(servers) end)
connect(settingsBack.Activated,function() showWindow(main) end)
connect(serverBack.Activated,function() showWindow(main) end)
local minimized=false
U.setPanelVisible=function(visible)
    minimized=not visible
    host.Visible=visible
    U.reopen.Visible=true
    U.reopen.Text="🎃"
    U.reopen.BackgroundColor3=visible and T.Active or T.Purple
end
connect(minimize.Activated,function() U.setPanelVisible(minimized) end)
connect(U.reopen.Activated,function() U.setPanelVisible(minimized) end)
connect(UIS.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightShift and not UIS:GetFocusedTextBox() then
        U.setPanelVisible(minimized)
    end
end)
local dragging,dragInput,dragStart,startPosition=false
local function draggable(handle)
    connect(handle.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging,dragInput,dragStart,startPosition=true,input,input.Position,host.Position
        end
    end)
end
draggable(U.header); draggable(mainHeader); draggable(settingsHeader); draggable(serverHeader); draggable(biomeHeader)
connect(UIS.InputChanged,function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input==dragInput) then
        local delta=input.Position-dragStart
        host.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,
            startPosition.Y.Scale,startPosition.Y.Offset+delta.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
local function cleanup()
    if not running then return end
    running,autoHop=false,false
    scanToken=scanToken+1
    if refuge then stopRefuge(true) end
    cancelMotion(); leaveSafe(); stopTraversal()
    restoreSpeed()
    for k in pairs(E) do E[k]=false end
    for _,connection in ipairs(connections) do connection:Disconnect() end
    for _,connection in ipairs(serverRowConnections) do connection:Disconnect() end
    for _,connection in ipairs(biomeRowConnections) do connection:Disconnect() end
    table.clear(connections); table.clear(serverRowConnections)
    table.clear(biomeRowConnections)
end
connect(gui.Destroying,cleanup)
connect(close.Activated,function() gui:Destroy() end)
connect(player.CharacterRemoving,function()
    if refuge then stopRefuge(false) end
    version=version+1
    stopTraversal()
    restoreSpeed()
    biomeReturn=nil
    trip,checkpoint,checkpointCharacter,followedPlayer=nil,nil,nil,nil
    safeCharacter=nil
    leaveSafe()
    E.SafeZone=false
    refreshToggle("SafeZone")
end)
local function rememberCharacter(ch)
    task.spawn(function()
        local root=ch:WaitForChild("HumanoidRootPart",10)
        if running and root and ch==player.Character then checkpointCharacter,checkpoint=ch,root.CFrame end
    end)
end
connect(player.CharacterAdded,rememberCharacter)
if player.Character then rememberCharacter(player.Character) end

-- Safety monitoring.
task.spawn(function()
    while running do
        local ch=player.Character
        updateSpeed()
        if not hopPending then
            if E.AntiPlayer then
                if refuge then
                    local saved=refuge
                    if not alive(saved.Character) then stopRefuge(false)
                    else
                        local distance,name=nearestPlayer(saved.Origin)
                        local release=math.max(C.PlayerRelease,C.PlayerTrigger)
                        if distance>release then stopRefuge(true)
                        elseif saved.Platform and saved.Platform.Parent then
                            M.AntiPlayer="Anti Player: "..tostring(name).." • "..math.floor(distance).."/"..release
                            move(saved.Character,saved.Target)
                        else stopRefuge(true) end
                    end
                elseif alive(ch) then
                    local distance=nearestPlayer(rootOf(ch).Position)
                    if distance<=C.PlayerTrigger then startRefuge() else M.AntiPlayer="Anti Player: monitoring" end
                end
            elseif refuge then stopRefuge(true) end
            if alive(ch) then
                local root=rootOf(ch)
                if not trip and not refuge and not E.SafeZone and not activeTween and not anchorState
                    and root.Position.Y>C.VoidHeight+5 then
                    local params=RaycastParams.new()
                    params.FilterType=Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances={ch}
                    params.RespectCanCollide=true
                    if workspace:Raycast(root.Position,Vector3.new(0,-8,0),params)
                        and math.abs(root.AssemblyLinearVelocity.Y)<5 then
                        checkpointCharacter,checkpoint=ch,root.CFrame
                    end
                end
                if E.AntiVoid and root.Position.Y<C.VoidHeight and os.clock()-lastRescue>1 then
                    local target
                    if refuge and refuge.Character==ch then target=refuge.Target
                    elseif trip and trip.Character==ch then target=trip.CFrame
                    elseif safePlatform and safePlatform.Parent and safeCharacter==ch then
                        target=platformTarget(safePlatform,ch,root.CFrame.Rotation)
                    elseif checkpointCharacter==ch then target=checkpoint end
                    if target then
                        lastRescue=os.clock()
                        version=version+1
                        stopTraversal()
                        M.AntiVoid=move(ch,target) and "Anti Void: rescued" or "Anti Void: rescue failed"
                    else M.AntiVoid="Anti Void: no saved position" end
                end
            end
        end
        waitFor(0.1)
    end
end)

-- Track the nearest living player. Positioning does not apply server damage.
local function findPlayerTarget(origin)
    local selected, character, humanoid
    local distance = math.huge
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other.Parent == Players then
            local ch = other.Character
            local root = rootOf(ch)
            local h = ch and ch:FindFirstChildOfClass("Humanoid")
            if root and h and h.Health > 0 and ch:IsDescendantOf(workspace) then
                local current = (root.Position - origin).Magnitude
                if current < distance then
                    selected, character, humanoid, distance = other, ch, h, current
                end
            end
        end
    end
    return selected, character, humanoid
end
local function followPlayerStep()
    local ch, token = player.Character, version
    if not alive(ch) then
        releaseAnchor()
        followedPlayer = nil
        M.Motion = "Kill Players: waiting for character"
        waitFor(0.3, token)
        return
    end
    local target, targetCharacter, targetHumanoid = findPlayerTarget(rootOf(ch).Position)
    if not target then
        followedPlayer = nil
        returnTrip()
        M.Motion = "Kill Players: waiting for living players"
        waitFor(C.SweepInterval, token)
        return
    end
    followedPlayer = target
    beginTrip(ch)
    while canMove(ch, token) and E.KillPlayers
        and target.Parent == Players and target.Character == targetCharacter
        and targetCharacter:IsDescendantOf(workspace) and targetHumanoid.Health > 0 do
        local targetRoot = rootOf(targetCharacter)
        if not targetRoot then break end
        if C.PlayerMethod=="Teleport" then anchor(ch) else releaseAnchor() end
        local destination = CFrame.new(targetRoot.Position + Vector3.new(0, C.PlayerFollowHeight, 0))
            * rootOf(ch).CFrame.Rotation
        if not followMove(ch,destination,token,C.PlayerMethod,C.PlayerTweenSpeed) then break end
        M.Motion = "Kill Players: following " .. target.DisplayName
        if not waitFor(C.PlayerFollowInterval, token) then break end
    end
    releaseAnchor()
    -- Keep the intended target excluded during a temporary Anti Player refuge.
    if not refuge then followedPlayer = nil end
end
local function followStep(bugs)
    local ch,token=player.Character,version
    local folder=workspace:FindFirstChild(bugs and "Bugs" or "Breakables")
    local title=bugs and "Kill Bugs" or "Acorns"
    if not alive(ch) then M.Motion=title..": waiting for character"; waitFor(0.3,token); return end
    if not folder then returnTrip(); M.Motion=title..": folder not found"; waitFor(0.5,token); return end
    local objects={}
    if bugs then U.gatherBugs(folder,objects) else U.gatherAcorns(folder,objects) end
    local index=nearest(objects,rootOf(ch).Position,function(object)
        return object:IsDescendantOf(folder) and object~=ch and not object:IsDescendantOf(ch)
            and (bugs and U.bugSelected(object.Name) or not bugs and U.acornSelected(object.Name))
    end)
    if not index then returnTrip(); M.Motion=title..(bugs and ": waiting for selected bug types" or ": waiting for selected acorn types"); waitFor(C.SweepInterval,token); return end
    local target=objects[index]
    beginTrip(ch)
    while canMove(ch,token) and not E.KillPlayers
        and (bugs and E.KillBugs or not bugs and E.AutoFarm and not E.KillBugs)
        and folder:IsDescendantOf(workspace) and target:IsDescendantOf(folder) do
        local destination
        if bugs then
            local position=positionOf(target)
            if not position then break end
            -- Keep normal character physics during contact so the server can observe movement.
            releaseAnchor()
            destination=CFrame.new(position+Vector3.new(0,C.BugHeight,0))*rootOf(ch).CFrame.Rotation
        else destination=acornTarget(target,ch) end
        local method=bugs and C.BugMethod or C.AcornMethod
        local speed=bugs and C.BugTweenSpeed or C.AcornTweenSpeed
        if not destination or not followMove(ch,destination,token,method,speed) then break end
        M.Motion=bugs and (title..": following "..target.Name)
            or ("Acorns: "..C.AcornMode.." • farming "..target.Name)
        if not waitFor(bugs and C.BugInterval or C.FarmInterval,token) then break end
    end
    releaseAnchor()
end
local function collectOrbs()
    local ch,token=player.Character,version
    local folder=workspace:FindFirstChild("Orbs")
    if not alive(ch) then M.Motion="Orbs: waiting for character"; waitFor(0.3,token); return end
    if not folder then M.Motion="Orbs: folder not found"; waitFor(0.5,token); return end
    local objects,queue={},{}
    gather(folder,objects)
    for _,object in ipairs(objects) do if allowedOrb(object) then table.insert(queue,object) end end
    if #queue==0 then
        if trip then returnTrip() end
        M.Motion="Orbs: waiting for selected colors"
        waitFor(C.SweepInterval,token)
        return
    end
    local saved=beginTrip(ch)
    local total,visited,removed=#queue,0,0
    while canMove(ch,token) and E.Orbs and not E.AutoFarm and not E.KillBugs and not E.KillPlayers
        and folder:IsDescendantOf(workspace) and #queue>0 do
        local index=nearest(queue,rootOf(ch).Position,function(object)
            return object:IsDescendantOf(folder) and allowedOrb(object)
        end)
        if not index then break end
        local object=table.remove(queue,index)
        visited=visited+1
        M.Motion="Orbs: "..C.OrbMode.." • "..visited.."/"..total
        local attempts=C.OrbMode=="Fast" and 1 or C.AttemptsPerOrb
        for attempt=1,attempts do
            if not canMove(ch,token) or not E.Orbs or E.AutoFarm or E.KillBugs or E.KillPlayers then break end
            if not object:IsDescendantOf(folder) or not allowedOrb(object) then break end
            if not travelOrb(ch,object,folder,token) then break end
            if not waitFor(C.OrbMode=="Fast" and 0.01 or C.OrbDelay,token) then break end
            if not object:IsDescendantOf(folder) then break end
        end
        if not object:IsDescendantOf(folder) then removed=removed+1 end
    end
    restoreCollisions()
    if trip==saved and not refuge and token==version then
        M.Motion=returnTrip() and ("Returned • removed orbs: "..removed.."/"..total) or "Orbs: return unavailable"
    end
    waitFor(C.SweepInterval,token)
end
task.spawn(function()
    while running do
        local ok,err=pcall(function()
            if hopPending then M.Motion="Movement: paused for Server Hop"; waitFor(0.1)
            elseif refuge then M.Motion="Movement: paused by Anti Player"; waitFor(0.05)
            elseif E.KillPlayers then followPlayerStep()
            elseif E.KillBugs then followStep(true)
            elseif E.AutoFarm then followStep(false)
            elseif E.Orbs then collectOrbs()
            else if trip then returnTrip() end; M.Motion="Movement: idle"; waitFor(0.1) end
        end)
        if not ok then warn("[Retro Movement]",err); stopTraversal(); if not refuge then returnTrip() end; waitFor(0.5) end
    end
end)
task.spawn(function() while running do scanColors(); U.scanBugs(); U.scanAcorns(); waitFor(1) end end)
-- One Auto Hop worker; failed destinations are not automatically retried.
task.spawn(function()
    local nextScan=0
    while running do
        if hopPending and os.clock()-hopPending.Started>20 then
            hopPending=nil
            setServerMessage("Teleport did not complete. You can try another server.")
            renderServers()
        end
        if autoHop and not hopPending and not scanBusy then
            local candidate
            for _,server in ipairs(serverResults) do
                if not visitedServers[server.id] then candidate=server; break end
            end
            if candidate then joinServer(candidate)
            elseif os.clock()>=nextScan then
                runScan()
                nextScan=os.clock()+C.ServerRetryDelay
            end
        end
        waitFor(0.2)
    end
end)

-- Readable activity and feature states; no gameplay action is performed by this renderer.
U.movementKey=function()
    if E.KillPlayers then return "KillPlayers" end
    if E.KillBugs then return "KillBugs" end
    if E.AutoFarm then return "AutoFarm" end
    if E.Orbs then return "Orbs" end
end
U.detailFor=function(key)
    if key=="Orbs" then return C.OrbMode.." pace • "..C.OrbMethod.." • "..C.OrbDelay.."s contact" end
    if key=="AutoFarm" then return C.AcornMode.." pace • "..C.AcornMethod.." movement" end
    if key=="KillBugs" then return C.BugMethod.." • "..C.BugHeight.." studs above • unanchored contact" end
    if key=="KillPlayers" then return C.PlayerMethod.." • "..C.PlayerFollowHeight.." studs above the target" end
    if key=="AntiPlayer" then return "Trigger: "..C.PlayerTrigger.." studs • release: "..C.PlayerRelease.." studs" end
    if key=="AntiVoid" then return "Rescue below world Y "..C.VoidHeight end
    if key=="SafeZone" then return "Platform height: "..C.SafeHeight.." studs" end
    if key=="CustomSpeed" then return "Walking speed: "..C.WalkSpeed.." studs/second" end
    return ""
end
U.reflow=function()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local viewport=camera.ViewportSize
    if viewport.X<=24 or viewport.Y<=24 then return end
    -- Use physical pixels for fit, and enlarge text and touch targets on small displays.
    local factor=viewport.X<=900 and 1.10 or 1
    local width=math.min(700,(viewport.X-20)/factor)
    local height=math.min(820,(viewport.Y-20)/factor)
    if U.LastWidth==width and U.LastHeight==height and U.LastScale==factor then return end
    U.LastWidth,U.LastHeight,U.LastScale=width,height,factor
    scale.Scale=factor
    host.Size=UDim2.fromOffset(width,height)
    local compact=height<640
    local pageY=compact and 194 or 228
    local pageBottom=compact and 258 or 292
    U.activity.Size=UDim2.new(1,-28,0,compact and 48 or 78)
    U.actionDetail.Visible=not compact
    for _,page in ipairs({main,settings,servers,biomes}) do
        page.Position=UDim2.fromOffset(14,pageY)
        page.Size=UDim2.new(1,-28,1,-pageBottom)
    end
    -- Keep lists usable when the window has little vertical room.
    hopStatus.Size=UDim2.new(1,-24,0,compact and 38 or 70)
    serverList.Position=UDim2.fromOffset(12,compact and 190 or 226)
    serverList.Size=UDim2.new(1,-24,1,compact and -234 or -270)
    biomeList.Position=UDim2.fromOffset(12,compact and 200 or 216)
    biomeList.Size=UDim2.new(1,-24,1,compact and -216 or -232)
    U.intro.Visible=not compact
    content.Position=UDim2.fromOffset(12,compact and 50 or 100)
    content.Size=UDim2.new(1,-24,1,compact and -62 or -112)
    U.header:FindFirstChildWhichIsA("TextLabel").TextSize=width<400 and 13 or 16
    local extra=width<440 and 28 or 0
    for _,card in pairs(U.Cards) do
        card.Frame.Size=UDim2.new(1,-8,0,172+extra)
        card.Description.Size=UDim2.new(1,-28,0,42+extra)
        card.State.Position=UDim2.fromOffset(14,92+extra)
        card.Detail.Position=UDim2.fromOffset(14,115+extra)
        card.Configure.Position=UDim2.fromOffset(14,140+extra)
    end
end
U.render=function()
    U.reflow()
    local active=U.movementKey()
    local phase,action,detail="IDLE","Ready to start","Choose a feature, then use Turn on."
    local character=player.Character
    if hopPending then
        phase,action,detail="JOINING","Joining another server",serverMessage
    elseif refuge then
        phase,action,detail="ON HOLD","Waiting for nearby players to leave",M.AntiPlayer
    elseif active and not alive(character) then
        phase,action,detail="WAITING","Waiting for your character","The selected feature resumes after respawn."
    elseif active then
        phase="RUNNING"
        action=M.Motion
        detail=U.detailFor(active)..(trip and " • return point saved" or "")
        local lower=M.Motion:lower()
        if lower:find("idle",1,true) then action="Starting "..labels[active]
        elseif lower:find("waiting",1,true) then phase="WAITING"
        elseif lower:find("not found",1,true) or lower:find("unavailable",1,true) then phase="CHECK SETUP"
        elseif lower:find("returned",1,true) then phase="RETURNED" end
    elseif E.SafeZone then
        phase,action,detail="SAFE PLATFORM","Safe platform is enabled",U.detailFor("SafeZone")
    elseif autoHop or scanBusy then
        phase,action,detail="SCANNING","Searching public servers",serverMessage
    end
    if U.ToastUntil>os.clock() then action=U.Toast end
    U.phase.Text=phase
    U.action.Text=action
    U.actionDetail.Text=detail
    U.phase.TextColor3=(phase=="RUNNING" or phase=="RETURNED") and Color3.fromRGB(133,221,160) or T.Orange
    local enabledCount=0
    for key,card in pairs(U.Cards) do
        local state="OFF • ready to start"
        local stateColor=T.Muted
        if E[key] then
            enabledCount=enabledCount+1
            stateColor=Color3.fromRGB(133,221,160)
            if key=="Orbs" or key=="AutoFarm" or key=="KillBugs" or key=="KillPlayers" then
                if hopPending then state="PAUSED • joining a server"; stateColor=T.Orange
                elseif refuge then state="PAUSED • Anti Player protection"; stateColor=T.Orange
                elseif active~=key then state="PAUSED • "..labels[active].." has priority"; stateColor=T.Orange
                elseif not alive(character) then state="WAITING • character unavailable"; stateColor=T.Orange
                elseif phase=="CHECK SETUP" then state="CHECK SETUP • read Current Action above"; stateColor=T.Orange
                elseif phase=="RETURNED" then state="WAITING • next search starts automatically"
                else state=phase=="WAITING" and "WAITING • read Current Action above" or "ON • active movement feature" end
            elseif key=="AntiPlayer" then state=refuge and "PROTECTING • waiting for players to leave" or "ON • monitoring nearby players"
            elseif key=="AntiVoid" then state="ON • monitoring falls"
            elseif key=="SafeZone" then state=active and "ON • platform kept for your return" or "ON • platform created"
            elseif key=="CustomSpeed" then state="ON • custom walking speed applied" end
        end
        card.State.Text,card.State.TextColor3=state,stateColor
        card.Detail.Text=U.detailFor(key)
        refreshToggle(key)
    end
    U.footer.Text=enabledCount.." enabled • Anti Void "..(E.AntiVoid and "ON" or "OFF").."\nHalloween edition • Made by Retro"
end

task.spawn(function()
    while running do
        U.render()
        waitFor(0.1)
    end
end)
end, function(err) return tostring(err) end)
if not booted then
    warn("[Retro GUI startup]",bootError)
    local errorNotice=Instance.new("TextLabel")
    errorNotice.Name="StartupError"
    errorNotice.Size=UDim2.new(0,340,0,80)
    errorNotice.Position=UDim2.new(0.5,-170,0,35)
    errorNotice.BackgroundColor3=Color3.fromRGB(45,12,24)
    errorNotice.TextColor3=Color3.fromRGB(255,230,210)
    errorNotice.TextWrapped=true
    errorNotice.TextSize=13
    errorNotice.Text="Retro GUI failed to open:\n"..bootError
    errorNotice.Parent=gui
end
