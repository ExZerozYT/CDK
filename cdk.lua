local pg = game.Players.LocalPlayer.PlayerGui
local old = pg:FindFirstChild('CKDAutoGUI')
if old then old:Destroy() end

local Act  = game:GetService('ReplicatedStorage').MatchRemotes.Act
local Sync = game:GetService('ReplicatedStorage').MatchRemotes.Sync
local TS   = game:GetService('TweenService')
local VirtualUser = game:GetService('VirtualUser')
local MatchPath = require(game:GetService('ReplicatedStorage').CandyTD.MatchPath)
local player = game.Players.LocalPlayer
local myId   = player.UserId
local candyGui = pg:WaitForChild('CandyTD', 10)
if not candyGui then return end

-- ===== ANTI AFK =====
local function enableAntiAFK()
    local conn = getgenv and getgenv()._CKD_AntiAFK
    if conn then conn:Disconnect() end
    local newConn = player.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0,0))
    end)
    if getgenv then getgenv()._CKD_AntiAFK = newConn end
end
enableAntiAFK()

local MAX_LVL = 99
local upgradeCount = 0
local lastCycle = 0

-- ===== AUTO DETECT SLOTS =====
local function detectSlots()
    local slots = {}
    for _, child in ipairs(candyGui:GetChildren()) do
        if child.Name:find('Card$') and child:IsA('TextButton') then
            local kind = child.Name:gsub('Card$','')
            local slotNum, displayName, maxLimit = nil, kind, 3
            for _, v in ipairs(child:GetDescendants()) do
                if v:IsA('TextLabel') then
                    local n = tonumber(v.Text)
                    if n and n >= 1 and n <= 6 and not slotNum then slotNum = n end
                    if v.Name == 'Name' and v.Text ~= '' then displayName = v.Text end
                    local cur, lim = v.Text:match('(%d+)/(%d+)')
                    if lim then maxLimit = tonumber(lim) or maxLimit end
                end
            end
            if not slotNum then
                local px = child.AbsolutePosition.X
                if     px < 90  then slotNum = 1
                elseif px < 175 then slotNum = 2
                elseif px < 260 then slotNum = 3
                elseif px < 345 then slotNum = 4
                elseif px < 430 then slotNum = 5
                else                 slotNum = 6 end
            end
            displayName = displayName:gsub('TD$',''):gsub('Card$','')
            if slotNum then
                slots[slotNum] = {slot=slotNum, kind=kind, label=displayName, card=child.Name, maxLimit=maxLimit}
            end
        end
    end
    local ordered = {}
    for i = 1, 6 do
        if slots[i] then table.insert(ordered, slots[i]) end
    end
    return ordered
end

local SLOTS = detectSlots()

-- ===== SMART PLACEMENT =====
local cachedLayout, cachedMapKey = nil, nil

local function getMapLayout()
    local ctd = workspace:FindFirstChild('CandyTD')
    local mapKey = nil
    if ctd then
        for _, child in ipairs(ctd:GetChildren()) do
            local name = child.Name:lower()
            if     name:find('crystal') then mapKey = 'crystal'
            elseif name:find('ice')     then mapKey = 'ice'
            elseif name:find('fire')    then mapKey = 'fire'
            elseif name:find('lemon')   then mapKey = 'lemon'
            elseif name:find('lich')    then mapKey = 'lich'
            elseif name:find('night')   then mapKey = 'nightosphere'
            elseif name:find('haunt')   then mapKey = 'haunt' end
            if mapKey then break end
        end
    end
    if cachedLayout and cachedMapKey == mapKey then return cachedLayout end
    local ok, layout = pcall(function() return MatchPath.get(mapKey) end)
    if ok and layout then
        cachedLayout, cachedMapKey = layout, mapKey
        return layout
    end
    return MatchPath.get()
end

local function computeSmartValidSpots()
    local layout = getMapLayout()
    if not layout or not layout.designPath then return {} end
    local path = layout.designPath
    local spots = {}
    for dist = 10, path.length - 15, 6 do
        local pt, dir = path:at(dist)
        local normal = Vector3.new(-dir.Z, 0, dir.X)
        for _, side in ipairs({-1, 1}) do
            for offset = 8, 22, 3 do
                local testPos = (pt + normal * side * offset) * MatchPath.W
                if MatchPath.canPlace(layout, testPos, {}) then
                    table.insert(spots, {x=math.floor(testPos.X), z=math.floor(testPos.Z), dist=dist, offset=offset})
                end
            end
        end
    end
    table.sort(spots, function(a, b)
        return a.dist == b.dist and a.offset < b.offset or a.dist < b.dist
    end)
    return spots
end

-- ===== SAVE / LOAD =====
local SAVE_FILE = 'CKD_smart_settings.txt'
local targetPlace = {}
local targetLevel = {}
local rotationData = {targetRounds=3, currentRound=0, storyStage=1, mode='dungeon'}
-- Master toggle & dungeon toggle
local masterON = true   -- เปิด/ปิด ทั้งระบบ
local dungeonON = false  -- เปิด/ปิด ลงดันเจี้ยนอัตโนมัติ

local function saveSettings(toggleStates)
    local data = {}
    for i = 1, #SLOTS do
        table.insert(data, string.format("%d:%d", targetPlace[i] or 0, targetLevel[i] or 0))
    end
    for i = 1, 4 do
        table.insert(data, toggleStates[i] and '1' or '0')
    end
    table.insert(data, string.format("ROT:%d:%d:%d:%s", rotationData.targetRounds, rotationData.currentRound, rotationData.storyStage, rotationData.mode))
    table.insert(data, masterON and '1' or '0')
    table.insert(data, dungeonON and '1' or '0')
    local kinds = {}
    for _, s in ipairs(SLOTS) do table.insert(kinds, s.kind) end
    table.insert(data, table.concat(kinds, '|'))
    pcall(writefile, SAVE_FILE, table.concat(data, ','))
end

local function loadSettings()
    local toggles = {true, true, true, false}
    for i = 1, #SLOTS do
        targetPlace[i] = 0
        targetLevel[i] = 0
    end
    local ok, content = pcall(readfile, SAVE_FILE)
    if not ok or not content or content == '' then return toggles end
    local parts = content:split(',')
    local savedKinds = parts[#parts] or ''
    local currentKinds = {}
    for _, s in ipairs(SLOTS) do table.insert(currentKinds, s.kind) end
    if savedKinds == table.concat(currentKinds, '|') then
        for i = 1, #SLOTS do
            local pStr, lStr = (parts[i] or ''):match("(%d+):(%d+)")
            if pStr and lStr then
                targetPlace[i] = tonumber(pStr) or 0
                targetLevel[i] = tonumber(lStr) or 0
            end
        end
    end
    for i = 1, 4 do
        if parts[#SLOTS + i] then toggles[i] = parts[#SLOTS + i] == '1' end
    end
    for _, part in ipairs(parts) do
        local tr, cr, ss, m = part:match("ROT:(%d+):(%d+):(%d+):(%a+)")
        if tr then
            rotationData.targetRounds = tonumber(tr) or 3
            rotationData.currentRound = tonumber(cr) or 0
            rotationData.storyStage   = tonumber(ss) or 1
            rotationData.mode         = m
        end
    end
    -- Load master & dungeon toggles (second from last before kinds)
    local masterIdx = #SLOTS + 5
    local dungeonIdx = #SLOTS + 6
    if parts[masterIdx]  then masterON  = parts[masterIdx]  == '1' end
    if parts[dungeonIdx] then dungeonON = parts[dungeonIdx] == '1' end
    return toggles
end

local toggleStates = loadSettings()

-- ===== UI =====
local ROWS = #SLOTS
local W = 360
local H = 60 + 36 + 8 + (ROWS * 44) + 12 + 42 + 10 + (4 * 38) + 20 + 42 + 16

local screen = Instance.new('ScreenGui')
screen.Name = 'CKDAutoGUI'
screen.ResetOnSpawn = false
screen.DisplayOrder = 999
screen.Parent = pg

local frame = Instance.new('Frame', screen)
frame.Size = UDim2.new(0, W, 0, H)
frame.Position = UDim2.new(0, 16, 0.5, -H/2)
frame.BackgroundColor3 = Color3.fromRGB(15, 17, 26)
frame.BackgroundTransparency = 0.06
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 16)
local frameStroke = Instance.new('UIStroke', frame)
frameStroke.Color = Color3.fromRGB(255,255,255)
frameStroke.Transparency = 0.88
frameStroke.Thickness = 1.2
local grad = Instance.new('UIGradient', frame)
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 25, 38)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 22))
})
grad.Rotation = 45

-- Header
local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundTransparency = 1

local title = Instance.new('TextLabel', header)
title.Position = UDim2.new(0, 16, 0, 8)
title.Size = UDim2.new(0, 160, 0, 18)
title.BackgroundTransparency = 1
title.Text = "Candy Kingdom Auto"
title.TextColor3 = Color3.fromRGB(255,255,255)
title.TextSize = 15
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left

local subTitle = Instance.new('TextLabel', header)
subTitle.Position = UDim2.new(0, 16, 0, 28)
subTitle.Size = UDim2.new(0, 160, 0, 14)
subTitle.BackgroundTransparency = 1
subTitle.Text = "ROTATION & ANTI-AFK ✅"
subTitle.TextColor3 = Color3.fromRGB(52, 211, 153)
subTitle.TextSize = 9
subTitle.Font = Enum.Font.GothamBold
subTitle.TextXAlignment = Enum.TextXAlignment.Left

-- stat badge
local badge = Instance.new('Frame', header)
badge.Position = UDim2.new(1, -118, 0, 12)
badge.Size = UDim2.new(0, 102, 0, 26)
badge.BackgroundColor3 = Color3.fromRGB(255,255,255)
badge.BackgroundTransparency = 0.94
badge.BorderSizePixel = 0
Instance.new('UICorner', badge).CornerRadius = UDim.new(0,13)
local bStroke = Instance.new('UIStroke', badge)
bStroke.Color = Color3.fromRGB(99,102,241)
bStroke.Transparency = 0.5
bStroke.Thickness = 1
local statusLbl = Instance.new('TextLabel', badge)
statusLbl.Size = UDim2.new(1,0,1,0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = string.format("⚔️ %d/%d  |  ⚡ %d", rotationData.currentRound, rotationData.targetRounds, upgradeCount)
statusLbl.TextColor3 = Color3.fromRGB(200,210,255)
statusLbl.TextSize = 10
statusLbl.Font = Enum.Font.GothamBold

-- ===== MASTER POWER BUTTON =====
local masterBtnY = 52
local masterBtn = Instance.new('TextButton', frame)
masterBtn.Position = UDim2.new(0, 14, 0, masterBtnY)
masterBtn.Size = UDim2.new(1, -28, 0, 32)
masterBtn.BorderSizePixel = 0
masterBtn.Text = ""
masterBtn.AutoButtonColor = false
Instance.new('UICorner', masterBtn).CornerRadius = UDim.new(0, 10)
local mStroke = Instance.new('UIStroke', masterBtn)
mStroke.Thickness = 1.5
local mIcon = Instance.new('TextLabel', masterBtn)
mIcon.Position = UDim2.new(0, 10, 0, 0)
mIcon.Size = UDim2.new(0, 22, 1, 0)
mIcon.BackgroundTransparency = 1
mIcon.TextSize = 16
mIcon.Font = Enum.Font.GothamBold
local mText = Instance.new('TextLabel', masterBtn)
mText.Position = UDim2.new(0, 36, 0, 0)
mText.Size = UDim2.new(0, 180, 1, 0)
mText.BackgroundTransparency = 1
mText.TextSize = 13
mText.Font = Enum.Font.GothamBold
mText.TextXAlignment = Enum.TextXAlignment.Left
local mDot = Instance.new('Frame', masterBtn)
mDot.Size = UDim2.new(0, 10, 0, 10)
mDot.Position = UDim2.new(1, -22, 0.5, -5)
mDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
mDot.BorderSizePixel = 0
Instance.new('UICorner', mDot).CornerRadius = UDim.new(1, 0)

local function refreshMasterBtn()
    if masterON then
        masterBtn.BackgroundColor3 = Color3.fromRGB(20, 40, 28)
        mStroke.Color = Color3.fromRGB(52, 211, 153)
        mStroke.Transparency = 0.3
        mIcon.Text = "⚡"
        mText.Text = "SYSTEM : ON  — กำลังทำงาน"
        mText.TextColor3 = Color3.fromRGB(52, 211, 153)
        mDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
    else
        masterBtn.BackgroundColor3 = Color3.fromRGB(35, 20, 20)
        mStroke.Color = Color3.fromRGB(239, 68, 68)
        mStroke.Transparency = 0.4
        mIcon.Text = "⏸"
        mText.Text = "SYSTEM : OFF — หยุดทำงาน"
        mText.TextColor3 = Color3.fromRGB(239, 68, 68)
        mDot.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
    end
end
refreshMasterBtn()
masterBtn.MouseButton1Click:Connect(function()
    masterON = not masterON
    refreshMasterBtn()
    saveSettings(toggleStates)
end)

-- Divider after master button
local divM = Instance.new('Frame', frame)
divM.Position = UDim2.new(0, 14, 0, masterBtnY + 36)
divM.Size = UDim2.new(1, -28, 0, 1)
divM.BackgroundColor3 = Color3.fromRGB(255,255,255)
divM.BackgroundTransparency = 0.88
divM.BorderSizePixel = 0

-- Column Titles
local colHeaderY = masterBtnY + 40
local colHeader = Instance.new('Frame', frame)
colHeader.Position = UDim2.new(0, 14, 0, colHeaderY)
colHeader.Size = UDim2.new(1, -28, 0, 18)
colHeader.BackgroundTransparency = 1
local function mkH(txt, x, w, align)
    local l = Instance.new('TextLabel', colHeader)
    l.Position = UDim2.new(0, x, 0, 0)
    l.Size = UDim2.new(0, w, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = txt
    l.TextColor3 = Color3.fromRGB(130, 135, 155)
    l.TextSize = 10
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = align or Enum.TextXAlignment.Left
end
mkH("UNIT", 6, 110)
mkH("PLACE QTY", 126, 100, Enum.TextXAlignment.Center)
mkH("UPGRADE LV", 228, 100, Enum.TextXAlignment.Center)

local divSlot = Instance.new('Frame', frame)
divSlot.Position = UDim2.new(0, 14, 0, colHeaderY + 20)
divSlot.Size = UDim2.new(1, -28, 0, 1)
divSlot.BackgroundColor3 = Color3.fromRGB(255,255,255)
divSlot.BackgroundTransparency = 0.9
divSlot.BorderSizePixel = 0

-- Stepper
local function createStepper(parent, x, width, initVal, maxVal, isLevel, onChange)
    local box = Instance.new('Frame', parent)
    box.Position = UDim2.new(0, x, 0.5, -12)
    box.Size = UDim2.new(0, width, 0, 24)
    box.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
    box.BackgroundTransparency = 0.4
    box.BorderSizePixel = 0
    Instance.new('UICorner', box).CornerRadius = UDim.new(0, 7)
    local btnM = Instance.new('TextButton', box)
    btnM.Position = UDim2.new(0, 2, 0, 2)
    btnM.Size = UDim2.new(0, 20, 0, 20)
    btnM.BackgroundColor3 = Color3.fromRGB(32, 35, 50)
    btnM.BorderSizePixel = 0
    btnM.Text = "–"
    btnM.TextColor3 = Color3.fromRGB(210, 215, 230)
    btnM.TextSize = 12
    btnM.Font = Enum.Font.GothamBold
    Instance.new('UICorner', btnM).CornerRadius = UDim.new(0, 5)
    local valLbl = Instance.new('TextLabel', box)
    valLbl.Position = UDim2.new(0, 22, 0, 0)
    valLbl.Size = UDim2.new(1, -44, 1, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.TextSize = 11
    valLbl.Font = Enum.Font.GothamBold
    local btnP = Instance.new('TextButton', box)
    btnP.Position = UDim2.new(1, -22, 0, 2)
    btnP.Size = UDim2.new(0, 20, 0, 20)
    btnP.BackgroundColor3 = Color3.fromRGB(32, 35, 50)
    btnP.BorderSizePixel = 0
    btnP.Text = "+"
    btnP.TextColor3 = Color3.fromRGB(210, 215, 230)
    btnP.TextSize = 12
    btnP.Font = Enum.Font.GothamBold
    Instance.new('UICorner', btnP).CornerRadius = UDim.new(0, 5)
    local current = initVal
    local function refresh()
        if isLevel then
            if current >= MAX_LVL then valLbl.Text = "MAX"; valLbl.TextColor3 = Color3.fromRGB(52,211,153)
            elseif current <= 0   then valLbl.Text = "OFF"; valLbl.TextColor3 = Color3.fromRGB(120,125,145)
            else valLbl.Text = "Lv "..current; valLbl.TextColor3 = Color3.fromRGB(251,191,36) end
        else
            if current <= 0 then valLbl.Text = "0"; valLbl.TextColor3 = Color3.fromRGB(120,125,145)
            else valLbl.Text = current.." ตัว"; valLbl.TextColor3 = Color3.fromRGB(96,165,250) end
        end
    end
    refresh()
    btnM.MouseButton1Click:Connect(function()
        if isLevel then
            if current >= MAX_LVL then current = 10 elseif current > 0 then current = current - 1 end
        else
            if current > 0 then current = current - 1 end
        end
        refresh(); onChange(current)
    end)
    btnP.MouseButton1Click:Connect(function()
        if isLevel then
            if current == 0 then current = 1 elseif current < MAX_LVL then current = current + 1 end
        else
            if current < maxVal then current = current + 1 end
        end
        refresh(); onChange(current)
    end)
end

-- Slot Rows
local startY = colHeaderY + 26
for i, slot in ipairs(SLOTS) do
    local cardY = startY + ((i - 1) * 44)
    local card = Instance.new('Frame', frame)
    card.Position = UDim2.new(0, 14, 0, cardY)
    card.Size = UDim2.new(1, -28, 0, 38)
    card.BackgroundColor3 = Color3.fromRGB(23, 26, 38)
    card.BackgroundTransparency = 0.5
    card.BorderSizePixel = 0
    Instance.new('UICorner', card).CornerRadius = UDim.new(0, 10)
    local cStroke = Instance.new('UIStroke', card)
    cStroke.Color = Color3.fromRGB(255,255,255)
    cStroke.Transparency = 0.93
    cStroke.Thickness = 1
    local numPill = Instance.new('Frame', card)
    numPill.Position = UDim2.new(0, 6, 0.5, -9)
    numPill.Size = UDim2.new(0, 18, 0, 18)
    numPill.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
    numPill.BackgroundTransparency = 0.2
    numPill.BorderSizePixel = 0
    Instance.new('UICorner', numPill).CornerRadius = UDim.new(0, 5)
    local numLbl = Instance.new('TextLabel', numPill)
    numLbl.Size = UDim2.new(1,0,1,0)
    numLbl.BackgroundTransparency = 1
    numLbl.Text = tostring(slot.slot)
    numLbl.TextColor3 = Color3.fromRGB(255,255,255)
    numLbl.TextSize = 10
    numLbl.Font = Enum.Font.GothamBold
    local uLbl = Instance.new('TextLabel', card)
    uLbl.Position = UDim2.new(0, 30, 0, 0)
    uLbl.Size = UDim2.new(0, 86, 1, 0)
    uLbl.BackgroundTransparency = 1
    uLbl.Text = slot.label
    uLbl.TextColor3 = Color3.fromRGB(230, 235, 245)
    uLbl.TextSize = 11
    uLbl.Font = Enum.Font.GothamMedium
    uLbl.TextXAlignment = Enum.TextXAlignment.Left
    uLbl.TextTruncate = Enum.TextTruncate.AtEnd
    createStepper(card, 120, 96, targetPlace[i], slot.maxLimit or 3, false, function(v)
        targetPlace[i] = v; saveSettings(toggleStates)
    end)
    createStepper(card, 224, 100, targetLevel[i], MAX_LVL, true, function(v)
        targetLevel[i] = v; saveSettings(toggleStates)
    end)
end

-- ===== DUNGEON ROTATION BANNER =====
local rotBannerY = startY + (ROWS * 44) + 6
local rotFrame = Instance.new('Frame', frame)
rotFrame.Position = UDim2.new(0, 14, 0, rotBannerY)
rotFrame.Size = UDim2.new(1, -28, 0, 42)
rotFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
rotFrame.BackgroundTransparency = 0.3
rotFrame.BorderSizePixel = 0
Instance.new('UICorner', rotFrame).CornerRadius = UDim.new(0, 10)
local rStroke = Instance.new('UIStroke', rotFrame)
rStroke.Color = Color3.fromRGB(99, 102, 241)
rStroke.Transparency = 0.6
rStroke.Thickness = 1
local rotTitle = Instance.new('TextLabel', rotFrame)
rotTitle.Position = UDim2.new(0, 10, 0, 4)
rotTitle.Size = UDim2.new(0, 150, 0, 16)
rotTitle.BackgroundTransparency = 1
rotTitle.Text = "DUNGEON ROTATION"
rotTitle.TextColor3 = Color3.fromRGB(165, 180, 252)
rotTitle.TextSize = 10
rotTitle.Font = Enum.Font.GothamBold
rotTitle.TextXAlignment = Enum.TextXAlignment.Left
local rotInfo = Instance.new('TextLabel', rotFrame)
rotInfo.Position = UDim2.new(0, 10, 0, 20)
rotInfo.Size = UDim2.new(0, 180, 0, 16)
rotInfo.BackgroundTransparency = 1
rotInfo.Text = string.format("ลงดัน %d/%d -> สตอรี่ด่าน %d", rotationData.currentRound, rotationData.targetRounds, rotationData.storyStage)
rotInfo.TextColor3 = Color3.fromRGB(220, 225, 245)
rotInfo.TextSize = 10
rotInfo.Font = Enum.Font.GothamMedium
rotInfo.TextXAlignment = Enum.TextXAlignment.Left

-- Stepper story stage
local rotStepper = Instance.new('Frame', rotFrame)
rotStepper.Position = UDim2.new(1, -114, 0.5, -12)
rotStepper.Size = UDim2.new(0, 106, 0, 24)
rotStepper.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
rotStepper.BackgroundTransparency = 0.4
rotStepper.BorderSizePixel = 0
Instance.new('UICorner', rotStepper).CornerRadius = UDim.new(0, 7)
local rBtnM = Instance.new('TextButton', rotStepper)
rBtnM.Position = UDim2.new(0, 2, 0, 2)
rBtnM.Size = UDim2.new(0, 20, 0, 20)
rBtnM.BackgroundColor3 = Color3.fromRGB(32, 35, 50)
rBtnM.BorderSizePixel = 0
rBtnM.Text = "–"
rBtnM.TextColor3 = Color3.fromRGB(210, 215, 230)
rBtnM.TextSize = 12
rBtnM.Font = Enum.Font.GothamBold
Instance.new('UICorner', rBtnM).CornerRadius = UDim.new(0, 5)
local rValLbl = Instance.new('TextLabel', rotStepper)
rValLbl.Position = UDim2.new(0, 22, 0, 0)
rValLbl.Size = UDim2.new(1, -44, 1, 0)
rValLbl.BackgroundTransparency = 1
rValLbl.Text = "Stage "..rotationData.storyStage
rValLbl.TextColor3 = Color3.fromRGB(251, 191, 36)
rValLbl.TextSize = 10
rValLbl.Font = Enum.Font.GothamBold
local rBtnP = Instance.new('TextButton', rotStepper)
rBtnP.Position = UDim2.new(1, -22, 0, 2)
rBtnP.Size = UDim2.new(0, 20, 0, 20)
rBtnP.BackgroundColor3 = Color3.fromRGB(32, 35, 50)
rBtnP.BorderSizePixel = 0
rBtnP.Text = "+"
rBtnP.TextColor3 = Color3.fromRGB(210, 215, 230)
rBtnP.TextSize = 12
rBtnP.Font = Enum.Font.GothamBold
Instance.new('UICorner', rBtnP).CornerRadius = UDim.new(0, 5)
rBtnM.MouseButton1Click:Connect(function()
    if rotationData.storyStage > 1 then
        rotationData.storyStage = rotationData.storyStage - 1
        rValLbl.Text = "Stage "..rotationData.storyStage
        rotInfo.Text = string.format("ลงดัน %d/%d -> สตอรี่ด่าน %d", rotationData.currentRound, rotationData.targetRounds, rotationData.storyStage)
        saveSettings(toggleStates)
    end
end)
rBtnP.MouseButton1Click:Connect(function()
    if rotationData.storyStage < 38 then
        rotationData.storyStage = rotationData.storyStage + 1
        rValLbl.Text = "Stage "..rotationData.storyStage
        rotInfo.Text = string.format("ลงดัน %d/%d -> สตอรี่ด่าน %d", rotationData.currentRound, rotationData.targetRounds, rotationData.storyStage)
        saveSettings(toggleStates)
    end
end)

-- ===== DUNGEON ON/OFF TOGGLE BUTTON =====
local dungeonBtnY = rotBannerY + 48
local dungeonBtn = Instance.new('TextButton', frame)
dungeonBtn.Position = UDim2.new(0, 14, 0, dungeonBtnY)
dungeonBtn.Size = UDim2.new(1, -28, 0, 32)
dungeonBtn.BorderSizePixel = 0
dungeonBtn.Text = ""
dungeonBtn.AutoButtonColor = false
Instance.new('UICorner', dungeonBtn).CornerRadius = UDim.new(0, 10)
local dStroke = Instance.new('UIStroke', dungeonBtn)
dStroke.Thickness = 1.5
local dIcon = Instance.new('TextLabel', dungeonBtn)
dIcon.Position = UDim2.new(0, 10, 0, 0)
dIcon.Size = UDim2.new(0, 22, 1, 0)
dIcon.BackgroundTransparency = 1
dIcon.TextSize = 16
dIcon.Font = Enum.Font.GothamBold
local dText = Instance.new('TextLabel', dungeonBtn)
dText.Position = UDim2.new(0, 36, 0, 0)
dText.Size = UDim2.new(0, 200, 1, 0)
dText.BackgroundTransparency = 1
dText.TextSize = 12
dText.Font = Enum.Font.GothamBold
dText.TextXAlignment = Enum.TextXAlignment.Left
local dDot = Instance.new('Frame', dungeonBtn)
dDot.Size = UDim2.new(0, 10, 0, 10)
dDot.Position = UDim2.new(1, -22, 0.5, -5)
dDot.BackgroundColor3 = Color3.fromRGB(52, 211, 153)
dDot.BorderSizePixel = 0
Instance.new('UICorner', dDot).CornerRadius = UDim.new(1, 0)

local function refreshDungeonBtn()
    if dungeonON then
        dungeonBtn.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
        dStroke.Color = Color3.fromRGB(99, 102, 241)
        dStroke.Transparency = 0.3
        dIcon.Text = "🏰"
        dText.Text = "AUTO DUNGEON : เปิด"
        dText.TextColor3 = Color3.fromRGB(165, 180, 252)
        dDot.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
    else
        dungeonBtn.BackgroundColor3 = Color3.fromRGB(30, 24, 24)
        dStroke.Color = Color3.fromRGB(120, 125, 145)
        dStroke.Transparency = 0.5
        dIcon.Text = "🏰"
        dText.Text = "AUTO DUNGEON : ปิด"
        dText.TextColor3 = Color3.fromRGB(120, 125, 145)
        dDot.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
    end
end
refreshDungeonBtn()
dungeonBtn.MouseButton1Click:Connect(function()
    dungeonON = not dungeonON
    refreshDungeonBtn()
    saveSettings(toggleStates)
end)

-- Divider before sub-toggles
local div2Y = dungeonBtnY + 38
local div2 = Instance.new('Frame', frame)
div2.Position = UDim2.new(0, 14, 0, div2Y)
div2.Size = UDim2.new(1, -28, 0, 1)
div2.BackgroundColor3 = Color3.fromRGB(255,255,255)
div2.BackgroundTransparency = 0.9
div2.BorderSizePixel = 0

-- Sub-Toggles
local TOGGLE_CONFIG = {
    {title="Auto Place Units",    icon="🏗️", color=Color3.fromRGB(99, 102, 241)},
    {title="Auto Next Wave",      icon="⏩",  color=Color3.fromRGB(59, 130, 246)},
    {title="Auto Play / Rotate",  icon="🔁",  color=Color3.fromRGB(168, 85, 247)},
    {title="Auto Return Hub",     icon="🚪",  color=Color3.fromRGB(239, 68, 68)},
}
for i, conf in ipairs(TOGGLE_CONFIG) do
    local btnY = div2Y + 8 + ((i - 1) * 38)
    local tBtn = Instance.new('TextButton', frame)
    tBtn.Position = UDim2.new(0, 14, 0, btnY)
    tBtn.Size = UDim2.new(1, -28, 0, 32)
    tBtn.BackgroundColor3 = Color3.fromRGB(23, 26, 38)
    tBtn.BackgroundTransparency = 0.5
    tBtn.BorderSizePixel = 0
    tBtn.Text = ""
    tBtn.AutoButtonColor = false
    Instance.new('UICorner', tBtn).CornerRadius = UDim.new(0, 8)
    local tStroke = Instance.new('UIStroke', tBtn)
    tStroke.Thickness = 1
    local tIcon = Instance.new('TextLabel', tBtn)
    tIcon.Position = UDim2.new(0, 10, 0, 0)
    tIcon.Size = UDim2.new(0, 20, 1, 0)
    tIcon.BackgroundTransparency = 1
    tIcon.Text = conf.icon
    tIcon.TextSize = 13
    tIcon.Font = Enum.Font.GothamMedium
    local tText = Instance.new('TextLabel', tBtn)
    tText.Position = UDim2.new(0, 36, 0, 0)
    tText.Size = UDim2.new(0, 180, 1, 0)
    tText.BackgroundTransparency = 1
    tText.Text = conf.title
    tText.TextColor3 = Color3.fromRGB(220, 225, 235)
    tText.TextSize = 12
    tText.Font = Enum.Font.GothamMedium
    tText.TextXAlignment = Enum.TextXAlignment.Left
    local switch = Instance.new('Frame', tBtn)
    switch.Position = UDim2.new(1, -38, 0.5, -8)
    switch.Size = UDim2.new(0, 28, 0, 16)
    switch.BorderSizePixel = 0
    Instance.new('UICorner', switch).CornerRadius = UDim.new(1, 0)
    local dot = Instance.new('Frame', switch)
    dot.Size = UDim2.new(0, 12, 0, 12)
    dot.Position = UDim2.new(0, 2, 0.5, -6)
    dot.BackgroundColor3 = Color3.fromRGB(255,255,255)
    dot.BorderSizePixel = 0
    Instance.new('UICorner', dot).CornerRadius = UDim.new(1, 0)
    local function refreshSwitch()
        local active = toggleStates[i]
        if active then
            switch.BackgroundColor3 = conf.color
            tStroke.Color = conf.color
            tStroke.Transparency = 0.6
            TS:Create(dot, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(1, -14, 0.5, -6)}):Play()
        else
            switch.BackgroundColor3 = Color3.fromRGB(45, 48, 65)
            tStroke.Color = Color3.fromRGB(255,255,255)
            tStroke.Transparency = 0.94
            TS:Create(dot, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0, 2, 0.5, -6)}):Play()
        end
    end
    refreshSwitch()
    tBtn.MouseButton1Click:Connect(function()
        toggleStates[i] = not toggleStates[i]
        refreshSwitch()
        saveSettings(toggleStates)
    end)
end

-- ===== GAME LOGIC =====
local function request(a, ...)
    local ok, r = pcall(Act.InvokeServer, Act, a, ...)
    if ok and type(r) == 'table' then return r end
    return {ok = false}
end

local function executeStrategy()
    if not masterON then return end
    local ok, data = pcall(Sync.InvokeServer, Sync)
    if not ok or type(data) ~= 'table' then return end
    local money = data.money or 0
    local counts = {}
    for _, t in ipairs(data.towers or {}) do
        if t.owner == myId then counts[t.kind] = (counts[t.kind] or 0) + 1 end
    end
    if toggleStates[1] and not data.running then
        local smartSpots = computeSmartValidSpots()
        if #smartSpots > 0 then
            for i, slot in ipairs(SLOTS) do
                local desiredCount = targetPlace[i] or 0
                local currentCount = counts[slot.kind] or 0
                if currentCount < desiredCount then
                    local card = candyGui:FindFirstChild(slot.card)
                    if card and card.Visible then
                        local cost = 0
                        for _, v in ipairs(card:GetDescendants()) do
                            if v:IsA('TextLabel') and v.Text:find('^%$') then
                                cost = tonumber(v.Text:match('%d+')) or cost; break
                            end
                        end
                        while currentCount < desiredCount and money >= cost do
                            local placed = false
                            for _, pos in ipairs(smartSpots) do
                                local r = request('place', slot.kind, pos.x, pos.z)
                                if r.ok then
                                    placeCount = (placeCount or 0) + 1
                                    money = money - cost
                                    currentCount = currentCount + 1
                                    counts[slot.kind] = currentCount
                                    statusLbl.Text = string.format("⚔️ %d/%d  |  ⚡ %d", rotationData.currentRound, rotationData.targetRounds, upgradeCount)
                                    placed = true; task.wait(0.12); break
                                end
                            end
                            if not placed then break end
                        end
                    end
                end
            end
        end
    end
    for _, tower in ipairs(data.towers or {}) do
        if tower.owner == myId then
            local slotIdx = nil
            for s, slot in ipairs(SLOTS) do
                if slot.kind == tower.kind then slotIdx = s; break end
            end
            if slotIdx then
                local desiredLevel = targetLevel[slotIdx] or 0
                if desiredLevel > 0 and tower.level < desiredLevel then
                    local r = request('upgrade', tower.id)
                    if r.ok then
                        upgradeCount = upgradeCount + 1
                        statusLbl.Text = string.format("⚔️ %d/%d  |  ⚡ %d", rotationData.currentRound, rotationData.targetRounds, upgradeCount)
                    end
                    task.wait(0.18)
                end
            end
        end
    end
end

local isHandlingOverlay = false
local function doOverlay()
    if not masterON then return end
    if isHandlingOverlay then return end
    local overlay = candyGui:FindFirstChild('Overlay')
    if not overlay or not overlay.Visible then return end
    isHandlingOverlay = true
    local nxt = overlay:FindFirstChild('Next')
    if nxt and nxt.Visible and toggleStates[2] then
        request('next'); task.wait(2); isHandlingOverlay = false; return
    end
    -- Dungeon rotation (only if dungeonON)
    if toggleStates[3] and dungeonON then
        rotationData.currentRound = rotationData.currentRound + 1
        saveSettings(toggleStates)
        statusLbl.Text = string.format("⚔️ %d/%d  |  ⚡ %d", rotationData.currentRound, rotationData.targetRounds, upgradeCount)
        rotInfo.Text = string.format("ลงดัน %d/%d -> สตอรี่ด่าน %d", rotationData.currentRound, rotationData.targetRounds, rotationData.storyStage)
        print(string.format('[CKD] Round %d/%d done!', rotationData.currentRound, rotationData.targetRounds))
        if rotationData.currentRound >= rotationData.targetRounds then
            print(string.format('[CKD] Reached %d rounds! -> Story Stage %d', rotationData.targetRounds, rotationData.storyStage))
            rotationData.currentRound = 0
            rotationData.mode = "story"
            saveSettings(toggleStates)
            local returnRem = game:GetService('ReplicatedStorage').MatchRemotes:FindFirstChild('ReturnToHub')
            if returnRem then returnRem:FireServer() end
            task.wait(5); isHandlingOverlay = false; return
        else
            local play = overlay:FindFirstChild('PlayAgain')
            if play and play.Visible then
                request('again'); task.wait(3); isHandlingOverlay = false; return
            end
        end
    elseif toggleStates[3] and not dungeonON then
        -- auto replay ปกติ ไม่นับดันเจี้ยน
        local play = overlay:FindFirstChild('PlayAgain')
        if play and play.Visible then
            request('again'); task.wait(3); isHandlingOverlay = false; return
        end
    end
    local hub = overlay:FindFirstChild('ReturnToHub')
    if hub and hub.Visible and toggleStates[4] then
        request('hub'); task.wait(3)
    end
    isHandlingOverlay = false
end

local function doStartWave()
    if not masterON then return end
    if not toggleStates[1] then return end
    local sw = candyGui:FindFirstChild('StartWave')
    if sw and sw.Visible then task.wait(1.5); request('start') end
end

print('[CKD Auto] ✅ Loaded — Master:'..(masterON and 'ON' or 'OFF')..' | Dungeon:'..(dungeonON and 'ON' or 'OFF'))

local lastCycle2 = 0
while task.wait(0.5) do
    pcall(function()
        if tick() - lastCycle2 > 1.2 then
            lastCycle2 = tick()
            task.spawn(executeStrategy)
            task.spawn(doStartWave)
        end
        doOverlay()
    end)
end
