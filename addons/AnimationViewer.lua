-- AnimationViewer.lua — animation browser built with the Obsidian/Linoria library itself.
-- Adds an "Animations" tab: pick character → folder → animation, play it on your
-- local character, tweak speed/loop, copy the id, and read hit-register keyframe markers.
--
-- Usage (after you've created your Window in Example.lua):
--   local AnimViewer = loadstring(game:HttpGet(repo .. "addons/AnimationViewer.lua"))()
--   AnimViewer(Library, Window)

return function(Library, Window)
    local Players   = game:GetService("Players")
    local KFP       = game:GetService("KeyframeSequenceProvider")
    local RunService= game:GetService("RunService")
    local LP        = Players.LocalPlayer
    local Options   = Library.Options
    local Toggles   = Library.Toggles
    local Scheme    = Library.Scheme

    -- Known-unblockable move IDs (server-side flag, not in the data). Shared with AutoBlock.
    local repo = "https://raw.githubusercontent.com/Synergay/obsidian-fork/main/"
    local isUnblockable = select(2, pcall(function()
        return loadstring(game:HttpGet(repo .. "addons/Unblockable.lua"))()
    end))
    if type(isUnblockable) ~= "function" then isUnblockable = function() return false end end

    -- ── Build animation tree ──────────────────────────────────────────────────
    -- AnimTree[char][folder][animName] = animationId
    local AnimRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
    local AnimTree, CharList = {}, {}

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
            if next(rootAnims) then AnimTree[cf.Name]["General"] = rootAnims end
        end
    end
    table.sort(CharList)

    local function sortedKeys(t)
        local k = {}
        for key in pairs(t or {}) do table.insert(k, key) end
        table.sort(k)
        return k
    end

    -- ── State ─────────────────────────────────────────────────────────────────
    local currentAnimId, currentTrack
    local currentDur, currentMarkers = 0, {}  -- filled by loadHitData, used by preview ticks

    local function getAnimator()
        local char = LP.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        return hum and hum:FindFirstChildOfClass("Animator")
    end

    local function stopAnim()
        if currentTrack then
            pcall(function() currentTrack:Stop(0.1) end)
            currentTrack = nil
        end
    end

    local function playAnim()
        if not currentAnimId then
            return Library:Notify("Select an animation first.", 3)
        end
        local anr = getAnimator()
        if not anr then
            return Library:Notify("No Animator found on your character.", 3)
        end
        stopAnim()
        local ao = Instance.new("Animation")
        ao.AnimationId = currentAnimId
        local ok, tr = pcall(function() return anr:LoadAnimation(ao) end)
        ao:Destroy()
        if not ok or not tr then
            return Library:Notify("Failed to load animation.", 3)
        end
        tr.Looped = Toggles.AVLoop and Toggles.AVLoop.Value or false
        tr:AdjustSpeed(Options.AVSpeed and Options.AVSpeed.Value or 1)
        tr:Play()
        currentTrack = tr
    end

    -- ── Hit-register marker styling ────────────────────────────────────────────
    -- This game stores timing in the marker VALUE, not the name:
    --   Name="Function" Value="Hitbox" / "Hit" / "Launch" / "Startup" / ...
    -- so tag against name+value combined.
    local function markerTag(name, value)
        local n = ((name or "") .. " " .. tostring(value or "")):lower()
        -- grab/throw family is unblockable — check FIRST so "HitboxDrag" etc. don't tag as [HIT]
        if n:find("grab") or n:find("launch") or n:find("throw") or n:find("drag")
            or n:find("knockback") or n:find("slam") or n:find("pull") then
            return "[GRAB] "
        elseif n:find("hitbox") or n:find("hit") or n:find("blackflash") or n:find("dmg") or n:find("damage") then
            return "[HIT] "
        elseif n:find("iframe") or n:find("invincib") then
            return "[IFRAME] "
        elseif n:find("stun") or n:find("cancel") or n:find("slow") then
            return "[STUN] "
        elseif n:find("start") or n:find("begin") or n:find("active") or n:find("create") then
            return "[START] "
        elseif n:find("end") or n:find("finish") or n:find("stop") then
            return "[END] "
        elseif n:find("vfx") or n:find("sfx") or n:find("effect") or n:find("sound")
            or n:find("particle") or n:find("point") then
            return "[FX] "
        end
        return ""
    end

    -- ── UI ──────────────────────────────────────────────────────────────────────
    local Tab   = Window:AddTab("Animations", "play")
    local Left  = Tab:AddLeftGroupbox("Browser", "list")
    local Right = Tab:AddRightGroupbox("Playback", "clapperboard")

    Left:AddDropdown("AVChar", {
        Values = CharList,
        Default = nil,
        AllowNull = true,
        Text = "Character",
        Searchable = true,
        Tooltip = "Select a character/folder from ReplicatedStorage.Animations",
    })

    Left:AddDropdown("AVFolder", {
        Values = {},
        Default = nil,
        AllowNull = true,
        Text = "Folder",
        Searchable = true,
    })

    Left:AddDropdown("AVAnim", {
        Values = {},
        Default = nil,
        AllowNull = true,
        Text = "Animation",
        Searchable = true,
    })

    Left:AddDivider()

    local lblId     = Left:AddLabel({ Text = "ID: —",       DoesWrap = true })
    local lblDur    = Left:AddLabel({ Text = "Duration: —", DoesWrap = false })
    local lblLooped = Left:AddLabel({ Text = "Looped: —",   DoesWrap = false })

    Left:AddButton({
        Text = "Copy Animation ID",
        Func = function()
            if not currentAnimId then
                return Library:Notify("No animation selected.", 3)
            end
            pcall(function() setclipboard(currentAnimId) end)
            Library:Notify("Copied " .. currentAnimId, 3)
        end,
    })

    -- Playback
    Right:AddSlider("AVSpeed", {
        Text = "Speed",
        Default = 1,
        Min = 0.1,
        Max = 3,
        Rounding = 2,
        Suffix = "×",
        Callback = function(v)
            if currentTrack then pcall(function() currentTrack:AdjustSpeed(v) end) end
        end,
    })

    Right:AddToggle("AVLoop", {
        Text = "Loop",
        Default = false,
        Callback = function(v)
            if currentTrack then pcall(function() currentTrack.Looped = v end) end
        end,
    })

    Right:AddButton({ Text = "▶ Play", Func = playAnim })
        :AddButton({ Text = "■ Stop", Func = stopAnim })

    Right:AddDivider()

    local HitBox = Tab:AddRightGroupbox("Hit Register", "crosshair")
    local lblHits = HitBox:AddLabel({
        Text = "Select an animation to analyse its keyframe markers.",
        DoesWrap = true,
    })

    -- ── 3D Preview ───────────────────────────────────────────────────────────────
    -- ViewportFrame showing a clone of your character performing the animation, with
    -- a scrub bar (green ticks = HIT markers) at the bottom.
    local PreviewBox = Tab:AddRightGroupbox("Preview", "eye")

    local vp = Instance.new("ViewportFrame")
    vp.Size            = UDim2.new(1, 0, 0, 200)
    vp.BackgroundColor3 = Scheme.BackgroundColor
    vp.BorderSizePixel = 0
    vp.Ambient         = Color3.fromRGB(160, 160, 160)
    vp.LightColor      = Color3.fromRGB(255, 255, 255)
    vp.Parent          = PreviewBox.Container
    Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 4)
    local vpStroke = Instance.new("UIStroke", vp)
    vpStroke.Color = Scheme.OutlineColor

    local world = Instance.new("WorldModel")
    world.Parent = vp
    local cam = Instance.new("Camera")
    cam.Parent = vp
    vp.CurrentCamera = cam

    -- Scrub bar
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, 0, 0, 12)
    bar.BackgroundColor3 = Scheme.MainColor
    bar.BorderSizePixel  = 0
    bar.Parent           = PreviewBox.Container
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
    Instance.new("UIStroke", bar).Color = Scheme.OutlineColor

    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Scheme.AccentColor
    fill.BorderSizePixel  = 0
    fill.Parent           = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)

    local ticksFolder = Instance.new("Folder")
    ticksFolder.Name   = "Ticks"
    ticksFolder.Parent = bar

    local previewChar, previewAnimator, previewTrack

    local function buildPreviewChar()
        if previewChar then previewChar:Destroy(); previewChar = nil end
        previewAnimator, previewTrack = nil, nil
        local src = LP.Character
        if not src then return end
        local ok, clone = pcall(function() return src:Clone() end)
        if not ok or not clone then return end
        -- strip scripts so nothing runs inside the viewport
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                d:Destroy()
            end
        end
        local hum = clone:FindFirstChildOfClass("Humanoid")
        local hrp = clone:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.PlatformStand = true
            previewAnimator = hum:FindFirstChildOfClass("Animator")
                or Instance.new("Animator", hum)
        end
        if hrp then hrp.Anchored = true end
        clone.Parent = world
        previewChar = clone
        -- frame the camera on the model
        local cf, size = clone:GetBoundingBox()
        local dist = math.max(size.X, size.Y, size.Z) * 2
        local look = hrp and hrp.CFrame.LookVector or Vector3.new(0, 0, -1)
        cam.CFrame = CFrame.new(cf.Position + look * dist + Vector3.new(0, size.Y * 0.15, 0), cf.Position)
    end

    local function rebuildTicks()
        ticksFolder:ClearAllChildren()
        if currentDur <= 0 then return end
        local moveUnblockable = isUnblockable(currentAnimId)
        for _, m in ipairs(currentMarkers) do
            local tag = markerTag(m.n, m.v)
            local color
            if tag == "[HIT] " then
                -- green if blockable, orange if the whole move ignores block (e.g. Rush)
                color = moveUnblockable and Color3.fromRGB(255, 140, 0) or Color3.fromRGB(60, 255, 90)
            elseif tag == "[GRAB] " then
                color = Color3.fromRGB(255, 140, 0)    -- orange: unblockable grab/throw
            end
            if color then
                local t = Instance.new("Frame")
                t.Size             = UDim2.new(0, 2, 1, 0)
                t.Position         = UDim2.new(math.clamp(m.t / currentDur, 0, 1), -1, 0, 0)
                t.BackgroundColor3 = color
                t.BorderSizePixel  = 0
                t.ZIndex           = 3
                t.Parent           = ticksFolder
            end
        end
    end

    local function previewStop()
        if previewTrack then pcall(function() previewTrack:Stop(0) end); previewTrack = nil end
    end

    local function previewPlay()
        if not currentAnimId then return Library:Notify("Select an animation first.", 3) end
        buildPreviewChar()
        if not previewAnimator then return Library:Notify("No character to preview.", 3) end
        previewStop()
        local ao = Instance.new("Animation")
        ao.AnimationId = currentAnimId
        local ok, tr = pcall(function() return previewAnimator:LoadAnimation(ao) end)
        ao:Destroy()
        if not ok or not tr then return Library:Notify("Failed to load preview.", 3) end
        tr.Looped = Toggles.AVLoop and Toggles.AVLoop.Value or false
        tr:AdjustSpeed(Options.AVSpeed and Options.AVSpeed.Value or 1)
        tr:Play()
        previewTrack = tr
    end

    PreviewBox:AddButton({ Text = "▶ Preview", Func = previewPlay })
        :AddButton({ Text = "■ Stop", Func = previewStop })

    -- drive the fill bar from the preview track each frame
    RunService.RenderStepped:Connect(function()
        if previewTrack and previewTrack.Length > 0 then
            fill.Size = UDim2.new(math.clamp(previewTrack.TimePosition / previewTrack.Length, 0, 1), 0, 1, 0)
        end
    end)

    -- click/drag the bar to scrub
    local dragging = false
    local function scrubTo(x)
        if not previewTrack or previewTrack.Length <= 0 then return end
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        previewTrack.TimePosition = rel * previewTrack.Length
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            scrubTo(i.Position.X)
        end
    end)
    bar.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    RunService.RenderStepped:Connect(function()
        if dragging then scrubTo(Players.LocalPlayer:GetMouse().X) end
    end)

    -- ── Hit-register loading ────────────────────────────────────────────────────
    local function loadHitData(animId)
        lblHits:SetText("Loading keyframe data…")
        task.spawn(function()
            local ok, seq = pcall(function() return KFP:GetKeyframeSequenceAsync(animId) end)
            if not ok or not seq then
                lblHits:SetText("Failed to load keyframe data.")
                return
            end

            local kfs = seq:GetKeyframes()
            table.sort(kfs, function(a, b) return a.Time < b.Time end)
            local dur = #kfs > 0 and kfs[#kfs].Time or 0

            local markers = {}
            for _, kf in ipairs(kfs) do
                local ok2, mlist = pcall(function() return kf:GetMarkers() end)
                if ok2 then
                    for _, m in ipairs(mlist) do
                        table.insert(markers, {
                            t = kf.Time, n = m.Name, v = m.Value or "",
                        })
                    end
                end
            end

            currentDur, currentMarkers = dur, markers
            rebuildTicks()

            lblDur:SetText(string.format("Duration: %.3f s", dur))
            lblLooped:SetText("Looped: " .. (seq.Loop and "Yes" or "No"))

            if #markers == 0 then
                lblHits:SetText(string.format(
                    "No markers found.\n(%d keyframes, %.3fs)", #kfs, dur))
            else
                local hitCount = 0
                local lines = {}
                for _, m in ipairs(markers) do
                    local tag = markerTag(m.n, m.v)
                    if tag == "[HIT] " then hitCount += 1 end
                    -- show the value (e.g. "Hitbox") since that's the meaningful token here
                    local label = m.v ~= "" and tostring(m.v) or m.n
                    table.insert(lines, string.format("%.3fs  %s%s", m.t, tag, label))
                end
                local header = string.format("%d marker(s)%s\n\n", #markers,
                    hitCount > 0 and ("  ·  " .. hitCount .. " HIT") or "")
                lblHits:SetText(header .. table.concat(lines, "\n"))
            end

            pcall(function() seq:Destroy() end)
        end)
    end

    -- ── Dependent dropdown chain ────────────────────────────────────────────────
    local function resetInfo()
        currentAnimId = nil
        currentDur, currentMarkers = 0, {}
        previewStop()
        rebuildTicks()
        fill.Size = UDim2.new(0, 0, 1, 0)
        lblId:SetText("ID: —")
        lblDur:SetText("Duration: —")
        lblLooped:SetText("Looped: —")
        lblHits:SetText("Select an animation to analyse its keyframe markers.")
    end

    Options.AVChar:OnChanged(function(char)
        Options.AVFolder:SetValues(sortedKeys(AnimTree[char]))
        Options.AVFolder:SetValue(nil)
        Options.AVAnim:SetValues({})
        Options.AVAnim:SetValue(nil)
        stopAnim()
        resetInfo()
    end)

    Options.AVFolder:OnChanged(function(folder)
        local char = Options.AVChar.Value
        local anims = char and AnimTree[char] and AnimTree[char][folder]
        Options.AVAnim:SetValues(sortedKeys(anims))
        Options.AVAnim:SetValue(nil)
        resetInfo()
    end)

    Options.AVAnim:OnChanged(function(animName)
        local char, folder = Options.AVChar.Value, Options.AVFolder.Value
        local id = char and folder and animName
            and AnimTree[char] and AnimTree[char][folder]
            and AnimTree[char][folder][animName]
        if not id then return end
        currentAnimId = id
        lblId:SetText("ID: " .. id)
        lblDur:SetText("Duration: …")
        lblLooped:SetText("Looped: …")
        loadHitData(id)
    end)

    Library:OnUnload(function()
        stopAnim()
        previewStop()
        if previewChar then previewChar:Destroy() end
    end)

    return { Tab = Tab, AnimTree = AnimTree }
end
