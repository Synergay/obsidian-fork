-- AnimationViewer.lua — slide-out animation preview panel
-- Usage: loadstring(game:HttpGet(repo .. "addons/AnimationViewer.lua"))()

if getgenv().AnimViewer then
    pcall(function() getgenv().AnimViewer:Destroy() end)
end

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local UIS           = game:GetService("UserInputService")
local KFP           = game:GetService("KeyframeSequenceProvider")
local LP            = Players.LocalPlayer

-- ── Data ─────────────────────────────────────────────────────────────────────

local AnimRoot = game.ReplicatedStorage:FindFirstChild("Animations")

-- AnimTree[char][folder][animName] = animationId
local AnimTree = {}
local CharList = {}

if AnimRoot then
    for _, cf in ipairs(AnimRoot:GetChildren()) do
        if not cf:IsA("Folder") then continue end
        table.insert(CharList, cf.Name)
        AnimTree[cf.Name] = {}
        local rootAnims = {}
        for _, child in ipairs(cf:GetChildren()) do
            if child:IsA("Animation") then
                rootAnims[child.Name] = child.AnimationId
            elseif child:IsA("Folder") then
                AnimTree[cf.Name][child.Name] = {}
                -- include nested folders (e.g. Megumi/Mahoraga/Melee)
                for _, sub in ipairs(child:GetChildren()) do
                    if sub:IsA("Animation") then
                        AnimTree[cf.Name][child.Name][sub.Name] = sub.AnimationId
                    elseif sub:IsA("Folder") then
                        local subKey = child.Name .. "/" .. sub.Name
                        AnimTree[cf.Name][subKey] = {}
                        for _, a in ipairs(sub:GetDescendants()) do
                            if a:IsA("Animation") then
                                AnimTree[cf.Name][subKey][a.Name] = a.AnimationId
                            end
                        end
                    end
                end
            end
        end
        if next(rootAnims) then
            AnimTree[cf.Name]["General"] = rootAnims
        end
    end
end
table.sort(CharList)

-- Marker names this game commonly uses (from ListData.States)
local KNOWN_HIT_MARKERS = {
    hit = true, damage = true, deal = true, dmg = true,
}
local KNOWN_STATE_MARKERS = {
    iframe = true, iframes = true, cancel = true, stun = true,
    invincible = true, block = true,
}

-- ── Theme ─────────────────────────────────────────────────────────────────────

-- Matches Library.Scheme (Obsidian/Linoria): Code font, purple accent, square-ish
local C = {
    BG      = Color3.fromRGB(15, 15, 15),   -- BackgroundColor
    SURF    = Color3.fromRGB(25, 25, 25),   -- MainColor
    SURF2   = Color3.fromRGB(35, 35, 35),   -- MainColor, lifted
    BORDER  = Color3.fromRGB(40, 40, 40),   -- OutlineColor
    ACCENT  = Color3.fromRGB(125, 85, 255), -- AccentColor
    ACCDIM  = Color3.fromRGB(70, 48, 150),  -- dim accent
    TEXT    = Color3.fromRGB(255, 255, 255), -- FontColor
    DIM     = Color3.fromRGB(140, 140, 140),
    RED     = Color3.fromRGB(255, 50, 50),  -- RedColor
    GREEN   = Color3.fromRGB(72, 210, 110),
    YELLOW  = Color3.fromRGB(255, 205, 70),
    ORANGE  = Color3.fromRGB(255, 150, 50),
    PURPLE  = Color3.fromRGB(180, 120, 255),
}
local FONT     = Enum.Font.Code
local FONT_B   = Enum.Font.Code  -- library uses a single monospace weight

local PW  = 285   -- panel width
local PH  = 508   -- panel height
local TW  = 26    -- tab width
local TT  = 0.22  -- tween time

-- ── GUI root ─────────────────────────────────────────────────────────────────

local Gui = Instance.new("ScreenGui")
Gui.Name = "AnimViewer"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
Gui.DisplayOrder = 150
getgenv().AnimViewer = Gui

-- Try gethui → CoreGui → PlayerGui
if not pcall(function() Gui.Parent = (gethui or function() error() end)() end) then
    if not pcall(function() Gui.Parent = game:GetService("CoreGui") end) then
        Gui.Parent = LP.PlayerGui
    end
end

-- Container: slides left/right as a unit (tab + panel)
local Container = Instance.new("Frame")
Container.Name = "Container"
Container.Size = UDim2.new(0, TW + PW, 0, PH)
Container.Position = UDim2.new(1, -TW, 0.5, -PH / 2) -- closed: only tab showing
Container.BackgroundTransparency = 1
Container.BorderSizePixel = 0
Container.ZIndex = 50
Container.Parent = Gui

-- Tab handle
local Tab = Instance.new("TextButton")
Tab.Size = UDim2.new(0, TW, 1, 0)
Tab.BackgroundColor3 = C.SURF
Tab.BorderSizePixel = 0
Tab.Text = "◁"
Tab.TextColor3 = C.ACCENT
Tab.TextSize = 11
Tab.Font = FONT_B
Tab.ZIndex = 52
Tab.Parent = Container
Instance.new("UICorner", Tab).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", Tab).Color = C.BORDER

local TabStripe = Instance.new("Frame")
TabStripe.Size = UDim2.new(0, 2, 0.45, 0)
TabStripe.Position = UDim2.new(0, 0, 0.275, 0)
TabStripe.BackgroundColor3 = C.ACCENT
TabStripe.BorderSizePixel = 0
TabStripe.ZIndex = 53
TabStripe.Parent = Tab

-- Panel body
local Panel = Instance.new("Frame")
Panel.Size = UDim2.new(0, PW, 1, 0)
Panel.Position = UDim2.new(0, TW, 0, 0)
Panel.BackgroundColor3 = C.BG
Panel.BorderSizePixel = 0
Panel.ZIndex = 51
Panel.ClipsDescendants = true
Panel.Parent = Container
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 4)
local PanelStroke = Instance.new("UIStroke", Panel)
PanelStroke.Color = C.BORDER

-- Header
local Hdr = Instance.new("Frame")
Hdr.Size = UDim2.new(1, 0, 0, 38)
Hdr.BackgroundColor3 = C.SURF
Hdr.BorderSizePixel = 0
Hdr.ZIndex = 52
Hdr.Parent = Panel
Instance.new("UICorner", Hdr).CornerRadius = UDim.new(0, 4)

-- Fix lower corners of header (UICorner applies to all corners)
local HdrFix = Instance.new("Frame")
HdrFix.Size = UDim2.new(1, 0, 0, 8)
HdrFix.Position = UDim2.new(0, 0, 1, -8)
HdrFix.BackgroundColor3 = C.SURF
HdrFix.BorderSizePixel = 0
HdrFix.ZIndex = 52
HdrFix.Parent = Hdr

local HdrIcon = Instance.new("TextLabel")
HdrIcon.Size = UDim2.new(0, 28, 1, 0)
HdrIcon.Position = UDim2.new(0, 6, 0, 0)
HdrIcon.BackgroundTransparency = 1
HdrIcon.Text = "⬡"
HdrIcon.TextColor3 = C.ACCENT
HdrIcon.TextSize = 14
HdrIcon.Font = FONT_B
HdrIcon.ZIndex = 53
HdrIcon.Parent = Hdr

local HdrTitle = Instance.new("TextLabel")
HdrTitle.Size = UDim2.new(1, -40, 1, 0)
HdrTitle.Position = UDim2.new(0, 32, 0, 0)
HdrTitle.BackgroundTransparency = 1
HdrTitle.Text = "Animation Viewer"
HdrTitle.TextColor3 = C.TEXT
HdrTitle.TextSize = 13
HdrTitle.Font = FONT_B
HdrTitle.TextXAlignment = Enum.TextXAlignment.Left
HdrTitle.ZIndex = 53
HdrTitle.Parent = Hdr

-- Now-playing status in header (right side)
local HdrStatus = Instance.new("TextLabel")
HdrStatus.Size = UDim2.new(0, 90, 0, 14)
HdrStatus.Position = UDim2.new(1, -96, 0.5, -7)
HdrStatus.BackgroundTransparency = 1
HdrStatus.Text = ""
HdrStatus.TextColor3 = C.GREEN
HdrStatus.TextSize = 9
HdrStatus.Font = FONT
HdrStatus.TextXAlignment = Enum.TextXAlignment.Right
HdrStatus.TextTruncate = Enum.TextTruncate.AtEnd
HdrStatus.ZIndex = 53
HdrStatus.Parent = Hdr

-- Scroll frame (content lives here)
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, 0, 1, -38)
Scroll.Position = UDim2.new(0, 0, 0, 38)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 3
Scroll.ScrollBarImageColor3 = C.BORDER
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.ZIndex = 52
Scroll.Parent = Panel

local SLayout = Instance.new("UIListLayout", Scroll)
SLayout.SortOrder = Enum.SortOrder.LayoutOrder
SLayout.Padding = UDim.new(0, 4)

local SPad = Instance.new("UIPadding", Scroll)
SPad.PaddingLeft  = UDim.new(0, 8)
SPad.PaddingRight = UDim.new(0, 8)
SPad.PaddingTop   = UDim.new(0, 8)
SPad.PaddingBottom = UDim.new(0, 10)

-- ── UI Helpers ────────────────────────────────────────────────────────────────

local function applyCorner(inst, r)
    Instance.new("UICorner", inst).CornerRadius = UDim.new(0, r or 4)
end

local function makeSectionLabel(text, order)
    local f = Instance.new("Frame", Scroll)
    f.Size = UDim2.new(1, 0, 0, 14)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = text:upper()
    l.TextColor3 = C.DIM
    l.TextSize = 10
    l.Font = FONT_B
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 53
end

local function makeDivider(order)
    local d = Instance.new("Frame", Scroll)
    d.Size = UDim2.new(1, 0, 0, 1)
    d.BackgroundColor3 = C.BORDER
    d.BorderSizePixel = 0
    d.LayoutOrder = order
end

-- ── Dropdown factory ─────────────────────────────────────────────────────────
-- Returns a control object: { getValue, setValue, setItems, onChange, disable, enable }

local activeDropdown = nil -- currently open dropdown's close fn

local function makeDropdown(placeholder, order)
    local items   = {}
    local value   = nil
    local enabled = true
    local isOpen  = false
    local cbs     = {}
    local floatFrame = nil

    local host = Instance.new("Frame", Scroll)
    host.Size = UDim2.new(1, 0, 0, 30)
    host.BackgroundTransparency = 1
    host.LayoutOrder = order

    local btn = Instance.new("TextButton", host)
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundColor3 = C.SURF
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.ZIndex = 55
    applyCorner(btn)
    local bStroke = Instance.new("UIStroke", btn)
    bStroke.Color = C.BORDER

    local bLabel = Instance.new("TextLabel", btn)
    bLabel.Size = UDim2.new(1, -26, 1, 0)
    bLabel.Position = UDim2.new(0, 9, 0, 0)
    bLabel.BackgroundTransparency = 1
    bLabel.Text = placeholder
    bLabel.TextColor3 = C.DIM
    bLabel.TextSize = 12
    bLabel.Font = FONT
    bLabel.TextXAlignment = Enum.TextXAlignment.Left
    bLabel.TextTruncate = Enum.TextTruncate.AtEnd
    bLabel.ZIndex = 56

    local bArrow = Instance.new("TextLabel", btn)
    bArrow.Size = UDim2.new(0, 18, 1, 0)
    bArrow.Position = UDim2.new(1, -20, 0, 0)
    bArrow.BackgroundTransparency = 1
    bArrow.Text = "▾"
    bArrow.TextColor3 = C.DIM
    bArrow.TextSize = 11
    bArrow.Font = FONT_B
    bArrow.ZIndex = 56

    -- Search box (inside float, only visible when open)
    local searchText = ""

    local function closeDD()
        isOpen = false
        searchText = ""
        bArrow.Text = "▾"
        bStroke.Color = C.BORDER
        if floatFrame then
            floatFrame:Destroy()
            floatFrame = nil
        end
        if activeDropdown == closeDD then activeDropdown = nil end
    end

    local function buildList(filter)
        if not floatFrame then return end
        -- clear
        for _, c in ipairs(floatFrame:GetChildren()) do
            if c.Name == "Item" then c:Destroy() end
        end
        local listScroll = floatFrame:FindFirstChild("LS")
        if not listScroll then return end

        local filtered = {}
        local fl = filter:lower()
        for _, v in ipairs(items) do
            if fl == "" or v:lower():find(fl, 1, true) then
                table.insert(filtered, v)
            end
        end

        listScroll.CanvasSize = UDim2.new(0, 0, 0, #filtered * 26)

        for i, v in ipairs(filtered) do
            local item = Instance.new("TextButton", listScroll)
            item.Name = "Item"
            item.Size = UDim2.new(1, 0, 0, 26)
            item.BackgroundTransparency = 1
            item.Text = v
            item.TextColor3 = (v == value) and C.ACCENT or C.TEXT
            item.TextSize = 11
            item.Font = v == value and FONT or FONT
            item.TextXAlignment = Enum.TextXAlignment.Left
            item.LayoutOrder = i
            item.ZIndex = 302

            local ipad = Instance.new("UIPadding", item)
            ipad.PaddingLeft = UDim.new(0, 10)

            item.MouseEnter:Connect(function()
                if v ~= value then
                    item.BackgroundTransparency = 0
                    item.BackgroundColor3 = C.SURF2
                end
            end)
            item.MouseLeave:Connect(function()
                if v ~= value then item.BackgroundTransparency = 1 end
            end)
            item.MouseButton1Click:Connect(function()
                value = v
                bLabel.Text = v
                bLabel.TextColor3 = C.TEXT
                closeDD()
                for _, cb in ipairs(cbs) do cb(v) end
            end)
        end
    end

    local function openDD()
        if not enabled then return end
        if activeDropdown then activeDropdown() end
        if #items == 0 then return end
        isOpen = true
        activeDropdown = closeDD
        bArrow.Text = "▴"
        bStroke.Color = C.ACCENT

        -- Calculate screen position
        local abs  = btn.AbsolutePosition
        local sz   = btn.AbsoluteSize
        local listH = math.min(#items * 26, 156)
        local hasSearch = #items > 6
        local totalH = listH + (hasSearch and 28 or 0)

        floatFrame = Instance.new("Frame", Gui)
        floatFrame.BackgroundColor3 = C.SURF2
        floatFrame.BorderSizePixel = 0
        floatFrame.ZIndex = 300
        floatFrame.Size = UDim2.new(0, sz.X, 0, totalH)
        floatFrame.Position = UDim2.new(0, abs.X, 0, abs.Y + sz.Y + 2)
        applyCorner(floatFrame)
        local fStroke = Instance.new("UIStroke", floatFrame)
        fStroke.Color = C.ACCENT
        fStroke.Thickness = 1

        local yOff = 0
        if hasSearch then
            local sBox = Instance.new("TextBox", floatFrame)
            sBox.Size = UDim2.new(1, -8, 0, 22)
            sBox.Position = UDim2.new(0, 4, 0, 3)
            sBox.BackgroundColor3 = C.SURF
            sBox.BorderSizePixel = 0
            sBox.PlaceholderText = "Search..."
            sBox.PlaceholderColor3 = C.DIM
            sBox.Text = ""
            sBox.TextColor3 = C.TEXT
            sBox.TextSize = 11
            sBox.Font = FONT
            sBox.ClearTextOnFocus = false
            sBox.ZIndex = 304
            applyCorner(sBox, 4)
            local sPad = Instance.new("UIPadding", sBox)
            sPad.PaddingLeft = UDim.new(0, 6)
            sBox.Changed:Connect(function(prop)
                if prop == "Text" then
                    searchText = sBox.Text
                    buildList(searchText)
                end
            end)
            yOff = 28
        end

        local listScroll = Instance.new("ScrollingFrame", floatFrame)
        listScroll.Name = "LS"
        listScroll.Size = UDim2.new(1, 0, 0, listH)
        listScroll.Position = UDim2.new(0, 0, 0, yOff)
        listScroll.BackgroundTransparency = 1
        listScroll.BorderSizePixel = 0
        listScroll.ScrollBarThickness = 2
        listScroll.ScrollBarImageColor3 = C.BORDER
        listScroll.CanvasSize = UDim2.new(0, 0, 0, #items * 26)
        listScroll.ZIndex = 301
        local lLayout = Instance.new("UIListLayout", listScroll)
        lLayout.SortOrder = Enum.SortOrder.LayoutOrder

        buildList("")
    end

    btn.MouseButton1Click:Connect(function()
        if isOpen then closeDD() else openDD() end
    end)

    return {
        getValue  = function() return value end,
        setValue  = function(v)
            value = v
            bLabel.Text = v or placeholder
            bLabel.TextColor3 = v and C.TEXT or C.DIM
        end,
        setItems  = function(newItems)
            items = newItems
            if isOpen then closeDD() end
        end,
        onChange  = function(cb) table.insert(cbs, cb) end,
        disable   = function()
            enabled = false
            btn.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
            bLabel.TextColor3 = C.DIM
        end,
        enable    = function()
            enabled = true
            btn.BackgroundColor3 = C.SURF
        end,
        close     = closeDD,
    }
end

-- Close all dropdowns when clicking outside any dropdown or panel element
UIS.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if activeDropdown then
        -- defer so the item click fires first
        task.defer(function()
            if activeDropdown then activeDropdown() end
        end)
    end
end)

-- ── Info row helper ───────────────────────────────────────────────────────────

local function makeInfoRow(label, order)
    local f = Instance.new("Frame", Scroll)
    f.Size = UDim2.new(1, 0, 0, 20)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order

    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(0, 70, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = C.DIM
    lbl.TextSize = 11
    lbl.Font = FONT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 53

    local val = Instance.new("TextLabel", f)
    val.Size = UDim2.new(1, -74, 1, 0)
    val.Position = UDim2.new(0, 72, 0, 0)
    val.BackgroundTransparency = 1
    val.Text = "—"
    val.TextColor3 = C.TEXT
    val.TextSize = 11
    val.Font = FONT
    val.TextXAlignment = Enum.TextXAlignment.Left
    val.TextTruncate = Enum.TextTruncate.AtEnd
    val.ZIndex = 53

    return val
end

-- ── Layout ────────────────────────────────────────────────────────────────────

makeSectionLabel("Character", 1)
local charDD = makeDropdown("Select character…", 2)
charDD.setItems(CharList)

makeSectionLabel("Folder", 3)
local folderDD = makeDropdown("Select folder…", 4)

makeSectionLabel("Animation", 5)
local animDD = makeDropdown("Select animation…", 6)

makeDivider(7)
makeSectionLabel("Info", 8)

local idVal   = makeInfoRow("Anim ID",   9)
local durVal  = makeInfoRow("Duration",  10)
local loopVal = makeInfoRow("Looped",    11)

-- Copy ID button
local copyBtn
do
    local f = Instance.new("Frame", Scroll)
    f.Size = UDim2.new(1, 0, 0, 26)
    f.BackgroundTransparency = 1
    f.LayoutOrder = 12

    copyBtn = Instance.new("TextButton", f)
    copyBtn.Size = UDim2.new(1, 0, 1, 0)
    copyBtn.BackgroundColor3 = C.SURF2
    copyBtn.BorderSizePixel = 0
    copyBtn.Text = "  Copy Animation ID"
    copyBtn.TextColor3 = C.DIM
    copyBtn.TextSize = 11
    copyBtn.Font = FONT
    copyBtn.ZIndex = 53
    applyCorner(copyBtn)
end

makeDivider(13)
makeSectionLabel("Playback", 14)

-- Speed slider (0.1x – 3.0x, default 1.0x)
local speedVal = 1.0
local speedLabel, sliderTrack, sliderFill, sliderKnob
do
    local f = Instance.new("Frame", Scroll)
    f.Size = UDim2.new(1, 0, 0, 44)
    f.BackgroundTransparency = 1
    f.LayoutOrder = 15

    speedLabel = Instance.new("TextLabel", f)
    speedLabel.Size = UDim2.new(1, 0, 0, 18)
    speedLabel.BackgroundTransparency = 1
    speedLabel.Text = "Speed: 1.0×"
    speedLabel.TextColor3 = C.DIM
    speedLabel.TextSize = 11
    speedLabel.Font = FONT
    speedLabel.TextXAlignment = Enum.TextXAlignment.Left
    speedLabel.ZIndex = 53

    sliderTrack = Instance.new("Frame", f)
    sliderTrack.Size = UDim2.new(1, 0, 0, 6)
    sliderTrack.Position = UDim2.new(0, 0, 0, 28)
    sliderTrack.BackgroundColor3 = C.SURF2
    sliderTrack.BorderSizePixel = 0
    sliderTrack.ZIndex = 53
    applyCorner(sliderTrack, 3)

    sliderFill = Instance.new("Frame", sliderTrack)
    -- 1.0x = (1.0 - 0.1) / 2.9 ≈ 0.310
    sliderFill.Size = UDim2.new(0.310, 0, 1, 0)
    sliderFill.BackgroundColor3 = C.ACCENT
    sliderFill.BorderSizePixel = 0
    sliderFill.ZIndex = 54
    applyCorner(sliderFill, 3)

    sliderKnob = Instance.new("Frame", sliderTrack)
    sliderKnob.Size = UDim2.new(0, 12, 0, 12)
    sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    sliderKnob.Position = UDim2.new(0.310, 0, 0.5, 0)
    sliderKnob.BackgroundColor3 = Color3.new(1, 1, 1)
    sliderKnob.BorderSizePixel = 0
    sliderKnob.ZIndex = 55
    Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(1, 0)
end

-- Loop toggle
local loopEnabled = false
local loopTrack, loopKnob
do
    local f = Instance.new("Frame", Scroll)
    f.Size = UDim2.new(1, 0, 0, 28)
    f.BackgroundTransparency = 1
    f.LayoutOrder = 16

    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "Loop"
    lbl.TextColor3 = C.TEXT
    lbl.TextSize = 12
    lbl.Font = FONT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 53

    loopTrack = Instance.new("TextButton", f)
    loopTrack.Size = UDim2.new(0, 40, 0, 22)
    loopTrack.Position = UDim2.new(1, -40, 0.5, -11)
    loopTrack.BackgroundColor3 = C.SURF2
    loopTrack.BorderSizePixel = 0
    loopTrack.Text = ""
    loopTrack.ZIndex = 53
    Instance.new("UICorner", loopTrack).CornerRadius = UDim.new(1, 0)

    loopKnob = Instance.new("Frame", loopTrack)
    loopKnob.Size = UDim2.new(0, 16, 0, 16)
    loopKnob.Position = UDim2.new(0, 3, 0.5, -8)
    loopKnob.BackgroundColor3 = C.DIM
    loopKnob.BorderSizePixel = 0
    loopKnob.ZIndex = 54
    Instance.new("UICorner", loopKnob).CornerRadius = UDim.new(1, 0)
end

-- Play / Stop row
local playBtn, stopBtn
do
    local f = Instance.new("Frame", Scroll)
    f.Size = UDim2.new(1, 0, 0, 30)
    f.BackgroundTransparency = 1
    f.LayoutOrder = 17
    local hl = Instance.new("UIListLayout", f)
    hl.FillDirection = Enum.FillDirection.Horizontal
    hl.Padding = UDim.new(0, 6)

    playBtn = Instance.new("TextButton", f)
    playBtn.Size = UDim2.new(0.5, -3, 1, 0)
    playBtn.BackgroundColor3 = C.GREEN
    playBtn.BorderSizePixel = 0
    playBtn.Text = "▶  Play"
    playBtn.TextColor3 = Color3.fromRGB(8, 18, 12)
    playBtn.TextSize = 12
    playBtn.Font = FONT_B
    playBtn.ZIndex = 53
    applyCorner(playBtn)

    stopBtn = Instance.new("TextButton", f)
    stopBtn.Size = UDim2.new(0.5, -3, 1, 0)
    stopBtn.BackgroundColor3 = C.RED
    stopBtn.BorderSizePixel = 0
    stopBtn.Text = "■  Stop"
    stopBtn.TextColor3 = Color3.new(1, 1, 1)
    stopBtn.TextSize = 12
    stopBtn.Font = FONT_B
    stopBtn.ZIndex = 53
    applyCorner(stopBtn)
end

makeDivider(18)
makeSectionLabel("Hit Register", 19)

-- Hit register container (auto-sizes with markers)
local HitFrame = Instance.new("Frame", Scroll)
HitFrame.Size = UDim2.new(1, 0, 0, 30)
HitFrame.BackgroundColor3 = C.SURF
HitFrame.BorderSizePixel = 0
HitFrame.AutomaticSize = Enum.AutomaticSize.Y
HitFrame.LayoutOrder = 20
HitFrame.ZIndex = 52
applyCorner(HitFrame)

local HitLayout = Instance.new("UIListLayout", HitFrame)
HitLayout.SortOrder = Enum.SortOrder.LayoutOrder
HitLayout.Padding = UDim.new(0, 2)

local HitPad = Instance.new("UIPadding", HitFrame)
HitPad.PaddingLeft   = UDim.new(0, 8)
HitPad.PaddingRight  = UDim.new(0, 8)
HitPad.PaddingTop    = UDim.new(0, 6)
HitPad.PaddingBottom = UDim.new(0, 6)

local HitStatus = Instance.new("TextLabel", HitFrame)
HitStatus.Size = UDim2.new(1, 0, 0, 18)
HitStatus.BackgroundTransparency = 1
HitStatus.Text = "Select an animation to analyse"
HitStatus.TextColor3 = C.DIM
HitStatus.TextSize = 11
HitStatus.Font = FONT
HitStatus.TextXAlignment = Enum.TextXAlignment.Left
HitStatus.ZIndex = 53
HitStatus.LayoutOrder = 1

-- ── Logic ─────────────────────────────────────────────────────────────────────

local currentTrack  = nil
local currentAnimId = nil

local function stopAnim()
    if currentTrack then
        pcall(function() currentTrack:Stop(0.1) end)
        currentTrack = nil
    end
    HdrStatus.Text = ""
end

local function getAnimator()
    local char = LP.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum:FindFirstChildOfClass("Animator")
end

local function playAnim()
    local id = currentAnimId
    if not id then return end
    local anr = getAnimator()
    if not anr then return end

    stopAnim()

    local ao = Instance.new("Animation")
    ao.AnimationId = id
    local ok, tr = pcall(function() return anr:LoadAnimation(ao) end)
    ao:Destroy()
    if not ok then return end

    tr.Looped = loopEnabled
    tr:AdjustSpeed(speedVal)
    tr:Play()
    currentTrack = tr

    local name = animDD.getValue() or "Animation"
    HdrStatus.Text = "▶ " .. name

    tr.Stopped:Connect(function()
        if currentTrack == tr then
            currentTrack = nil
            HdrStatus.Text = ""
        end
    end)
end

-- Speed slider dragging
local sliderDragging = false

local function applySlider(x)
    local a = sliderTrack.AbsolutePosition.X
    local s = sliderTrack.AbsoluteSize.X
    local t = math.clamp((x - a) / s, 0, 1)
    speedVal = 0.1 + t * 2.9
    sliderFill.Size = UDim2.new(t, 0, 1, 0)
    sliderKnob.Position = UDim2.new(t, 0, 0.5, 0)
    speedLabel.Text = string.format("Speed: %.1f×", speedVal)
    if currentTrack then
        pcall(function() currentTrack:AdjustSpeed(speedVal) end)
    end
end

sliderTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        sliderDragging = true
        applySlider(i.Position.X)
    end
end)
UIS.InputChanged:Connect(function(i)
    if sliderDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        applySlider(i.Position.X)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        sliderDragging = false
    end
end)

-- Loop toggle
local function setLoopEnabled(v)
    loopEnabled = v
    TweenService:Create(loopKnob, TweenInfo.new(0.15), {
        Position = v and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3 = v and C.ACCENT or C.DIM,
    }):Play()
    TweenService:Create(loopTrack, TweenInfo.new(0.15), {
        BackgroundColor3 = v and C.ACCDIM or C.SURF2,
    }):Play()
    if currentTrack then
        pcall(function() currentTrack.Looped = loopEnabled end)
    end
end
loopTrack.MouseButton1Click:Connect(function() setLoopEnabled(not loopEnabled) end)

-- Hit register loading
local function clearHitFrame()
    for _, c in ipairs(HitFrame:GetChildren()) do
        if c ~= HitStatus and not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
            c:Destroy()
        end
    end
end

local function markerStyle(name)
    local n = name:lower()
    if KNOWN_HIT_MARKERS[n] or n:find("hit") or n:find("dmg") or n:find("damage") or n:find("deal") then
        return C.RED, "✕", true
    elseif KNOWN_STATE_MARKERS[n] or n:find("iframe") or n:find("invincib") then
        return C.ACCENT, "◈", false
    elseif n:find("stun") or n:find("cancel") then
        return C.YELLOW, "⚡", false
    elseif n:find("start") or n:find("begin") or n:find("active") then
        return C.GREEN, "▶", false
    elseif n:find("end") or n:find("finish") or n:find("stop") then
        return C.ORANGE, "■", false
    elseif n:find("vfx") or n:find("sfx") or n:find("effect") or n:find("sound") or n:find("particle") then
        return C.YELLOW, "✦", false
    elseif n:find("grab") or n:find("launch") or n:find("knockback") then
        return C.PURPLE, "↑", false
    end
    return C.TEXT, "·", false
end

local function addMarkerRow(time, name, value, order)
    local color, icon, bold = markerStyle(name)

    local row = Instance.new("Frame", HitFrame)
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.ZIndex = 53

    local function cell(txt, col, w, xalign, fnt)
        local l = Instance.new("TextLabel", row)
        l.Size = UDim2.new(0, w, 1, 0)
        l.BackgroundTransparency = 1
        l.Text = txt
        l.TextColor3 = col
        l.TextSize = 10
        l.Font = fnt or FONT
        l.TextXAlignment = xalign or Enum.TextXAlignment.Left
        l.ZIndex = 54
        return l
    end

    -- icon column
    local iconLbl = cell(icon, color, 14, Enum.TextXAlignment.Center, FONT_B)
    iconLbl.Position = UDim2.new(0, 0, 0, 0)

    -- time column
    local timeLbl = cell(string.format("%.3fs", time), C.DIM, 38, Enum.TextXAlignment.Left)
    timeLbl.Position = UDim2.new(0, 16, 0, 0)

    -- name column
    local displayName = name .. (value ~= "" and ("  " .. value) or "")
    local nameLbl = cell(displayName, color, 160, Enum.TextXAlignment.Left, bold and FONT_B or FONT)
    nameLbl.Position = UDim2.new(0, 56, 0, 0)
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- Highlight rows that look like hit frames
    if bold then
        local bg = Instance.new("Frame", row)
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
        bg.BackgroundTransparency = 0.88
        bg.BorderSizePixel = 0
        bg.ZIndex = 52
        applyCorner(bg, 3)
    end
end

local function loadHitData(animId)
    clearHitFrame()
    HitStatus.Text = "Loading keyframe data…"
    HitStatus.TextColor3 = C.DIM
    HitStatus.LayoutOrder = 1

    task.spawn(function()
        local ok, seq = pcall(function()
            return KFP:GetKeyframeSequenceAsync(animId)
        end)

        if not ok or not seq then
            HitStatus.Text = "Failed to load keyframe data"
            HitStatus.TextColor3 = C.RED
            return
        end

        local kfs = seq:GetKeyframes()
        table.sort(kfs, function(a, b) return a.Time < b.Time end)

        local dur = kfs[#kfs] and kfs[#kfs].Time or 0
        local markers = {}

        for _, kf in ipairs(kfs) do
            local ok2, mlist = pcall(function() return kf:GetMarkers() end)
            if ok2 then
                for _, m in ipairs(mlist) do
                    table.insert(markers, { t = kf.Time, n = m.Name, v = m.Value or "" })
                end
            end
        end

        -- Update info labels
        durVal.Text  = string.format("%.3f s", dur)
        loopVal.Text = seq.Loop and "Yes" or "No"

        -- Count hit-type markers
        local hitCount = 0
        for _, m in ipairs(markers) do
            local _, _, isHit = markerStyle(m.n)
            if isHit then hitCount += 1 end
        end

        if #markers == 0 then
            HitStatus.Text = string.format(
                "No markers  (%d keyframes, %.3fs)", #kfs, dur
            )
            HitStatus.TextColor3 = C.DIM
        else
            local extra = hitCount > 0 and string.format("  [%d hit]", hitCount) or ""
            HitStatus.Text = string.format("%d marker(s)%s:", #markers, extra)
            HitStatus.TextColor3 = C.TEXT
            for i, m in ipairs(markers) do
                addMarkerRow(m.t, m.n, m.v, i + 1)
            end
        end

        pcall(function() seq:Destroy() end)
    end)
end

-- ── Dropdown chains ───────────────────────────────────────────────────────────

local function resetInfo()
    currentAnimId = nil
    idVal.Text    = "—"
    durVal.Text   = "—"
    loopVal.Text  = "—"
    clearHitFrame()
    HitStatus.Text = "Select an animation to analyse"
    HitStatus.TextColor3 = C.DIM
    HitStatus.LayoutOrder = 1
end

charDD.onChange(function(char)
    folderDD.setValue(nil)
    animDD.setValue(nil)
    stopAnim()
    resetInfo()

    local tree = AnimTree[char]
    if not tree then return end
    local folders = {}
    for k in pairs(tree) do table.insert(folders, k) end
    table.sort(folders)
    folderDD.setItems(folders)
    animDD.setItems({})
end)

folderDD.onChange(function(folder)
    animDD.setValue(nil)
    resetInfo()

    local char = charDD.getValue()
    if not char then return end
    local anims = AnimTree[char] and AnimTree[char][folder]
    if not anims then return end
    local names = {}
    for k in pairs(anims) do table.insert(names, k) end
    table.sort(names)
    animDD.setItems(names)
end)

animDD.onChange(function(animName)
    local char   = charDD.getValue()
    local folder = folderDD.getValue()
    if not char or not folder then return end
    local id = AnimTree[char][folder][animName]
    if not id then return end

    currentAnimId = id
    idVal.Text    = id:gsub("rbxassetid://", "")
    durVal.Text   = "…"
    loopVal.Text  = "…"
    loadHitData(id)
end)

-- ── Button callbacks ──────────────────────────────────────────────────────────

playBtn.MouseButton1Click:Connect(playAnim)
stopBtn.MouseButton1Click:Connect(stopAnim)

copyBtn.MouseButton1Click:Connect(function()
    if not currentAnimId then return end
    pcall(function() setclipboard(currentAnimId) end)
    copyBtn.Text = "  ✓ Copied!"
    copyBtn.TextColor3 = C.GREEN
    task.delay(1.5, function()
        copyBtn.Text = "  Copy Animation ID"
        copyBtn.TextColor3 = C.DIM
    end)
end)

-- ── Panel open/close tween ────────────────────────────────────────────────────

local panelOpen  = false
local CLOSED_POS = UDim2.new(1, -TW,       0.5, -PH / 2)
local OPEN_POS   = UDim2.new(1, -(TW + PW), 0.5, -PH / 2)
local TWEEN_INFO = TweenInfo.new(TT, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

Tab.MouseButton1Click:Connect(function()
    panelOpen = not panelOpen
    TweenService:Create(Container, TWEEN_INFO, {
        Position = panelOpen and OPEN_POS or CLOSED_POS,
    }):Play()
    Tab.Text = panelOpen and "▷" or "◁"
    -- Accent stripe pulses on open
    TweenService:Create(TabStripe, TweenInfo.new(0.15), {
        BackgroundColor3 = panelOpen and C.GREEN or C.ACCENT,
    }):Play()
end)

print("[AnimViewer] Loaded — click the ◁ tab on the right edge to open")
