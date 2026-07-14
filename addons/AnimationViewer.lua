-- AnimationViewer.lua — animation browser built with the Obsidian/Linoria library itself.
-- Adds an "Animations" tab: pick character → folder → animation, play it on your
-- local character, tweak speed/loop, copy the id, and read hit-register keyframe markers.
--
-- Usage (after you've created your Window in Example.lua):
--   local AnimViewer = loadstring(game:HttpGet(repo .. "addons/AnimationViewer.lua"))()
--   AnimViewer(Library, Window)

return function(Library, Window)
    local Players = game:GetService("Players")
    local KFP     = game:GetService("KeyframeSequenceProvider")
    local LP      = Players.LocalPlayer
    local Options = Library.Options
    local Toggles = Library.Toggles

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
    -- Tag each keyframe marker so hit/damage frames stand out in the readout.
    local function markerTag(name)
        local n = name:lower()
        if n:find("hit") or n:find("dmg") or n:find("damage") or n:find("deal") then
            return "[HIT] "
        elseif n:find("iframe") or n:find("invincib") then
            return "[IFRAME] "
        elseif n:find("stun") or n:find("cancel") then
            return "[STUN] "
        elseif n:find("start") or n:find("begin") or n:find("active") then
            return "[START] "
        elseif n:find("end") or n:find("finish") or n:find("stop") then
            return "[END] "
        elseif n:find("grab") or n:find("launch") or n:find("knockback") then
            return "[GRAB] "
        elseif n:find("vfx") or n:find("sfx") or n:find("effect") or n:find("sound") or n:find("particle") then
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

    Left:AddLabel("AVId",     { Text = "ID: —",       DoesWrap = true })
    Left:AddLabel("AVDur",    { Text = "Duration: —", DoesWrap = false })
    Left:AddLabel("AVLooped", { Text = "Looped: —",   DoesWrap = false })

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
    HitBox:AddLabel("AVHits", {
        Text = "Select an animation to analyse its keyframe markers.",
        DoesWrap = true,
    })

    -- ── Hit-register loading ────────────────────────────────────────────────────
    local function loadHitData(animId)
        Options.AVHits:SetText("Loading keyframe data…")
        task.spawn(function()
            local ok, seq = pcall(function() return KFP:GetKeyframeSequenceAsync(animId) end)
            if not ok or not seq then
                Options.AVHits:SetText("Failed to load keyframe data.")
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

            Options.AVDur:SetText(string.format("Duration: %.3f s", dur))
            Options.AVLooped:SetText("Looped: " .. (seq.Loop and "Yes" or "No"))

            if #markers == 0 then
                Options.AVHits:SetText(string.format(
                    "No markers found.\n(%d keyframes, %.3fs)", #kfs, dur))
            else
                local hitCount = 0
                local lines = {}
                for _, m in ipairs(markers) do
                    local tag = markerTag(m.n)
                    if tag == "[HIT] " then hitCount += 1 end
                    local suffix = m.v ~= "" and ("  = " .. tostring(m.v)) or ""
                    table.insert(lines, string.format("%.3fs  %s%s%s",
                        m.t, tag, m.n, suffix))
                end
                local header = string.format("%d marker(s)%s\n\n", #markers,
                    hitCount > 0 and ("  ·  " .. hitCount .. " HIT") or "")
                Options.AVHits:SetText(header .. table.concat(lines, "\n"))
            end

            pcall(function() seq:Destroy() end)
        end)
    end

    -- ── Dependent dropdown chain ────────────────────────────────────────────────
    local function resetInfo()
        currentAnimId = nil
        Options.AVId:SetText("ID: —")
        Options.AVDur:SetText("Duration: —")
        Options.AVLooped:SetText("Looped: —")
        Options.AVHits:SetText("Select an animation to analyse its keyframe markers.")
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
        Options.AVId:SetText("ID: " .. id)
        Options.AVDur:SetText("Duration: …")
        Options.AVLooped:SetText("Looped: …")
        loadHitData(id)
    end)

    Library:OnUnload(stopAnim)

    return { Tab = Tab, AnimTree = AnimTree }
end
