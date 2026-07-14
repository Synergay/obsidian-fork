-- AutoBlock.lua — blocks 0.1s BEFORE an enemy animation's hit registers.
-- Watches every character in workspace.Characters (players AND dummies/NPCs). When
-- one plays an animation, we look up its hit-marker times from the keyframe data and
-- schedule BlockService.Activated to fire LEAD seconds *before* each hit, releasing
-- (Deactivated) HOLD seconds later.
--
-- Predictive, so it can't use the live GetMarkerReachedSignal (that fires AT the hit,
-- too late). Hit times come from KeyframeSequenceProvider, cached per animation id.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local KFP     = game:GetService("KeyframeSequenceProvider")
local LP      = Players.LocalPlayer
local CharsFolder = workspace:WaitForChild("Characters")

local RE          = RS:WaitForChild("Knit").Knit.Services.BlockService.RE
local Activated   = RE.Activated
local Deactivated = RE.Deactivated

-- Known-unblockable move IDs (server-side flag, can't be read from data — hand-maintained).
-- Falls back to "nothing is unblockable" if the fetch fails, so a hiccup won't break blocking.
local repo = "https://raw.githubusercontent.com/Synergay/obsidian-fork/main/"
local isUnblockable = select(2, pcall(function()
    return loadstring(game:HttpGet(repo .. "addons/Unblockable.lua"))()
end))
if type(isUnblockable) ~= "function" then isUnblockable = function() return false end end

local LEAD = 0.1  -- block this long before the hit
local HOLD = 0.1  -- keep block up this long after activating
-- ponytail: block window is [hit-LEAD, hit-LEAD+HOLD]. Raise HOLD if it drops before
-- the hit lands (e.g. HOLD = LEAD + 0.05 to stay up through the hit).

-- marker VALUEs of BLOCKABLE strikes only. Grabs/throws pass through block, so we
-- exclude them even though names like "HitboxDrag"/"DragThrow" contain "hit".
local function isBlockable(value)
    local v = tostring(value):lower()
    if v:find("throw") or v:find("drag") or v:find("launch") or v:find("slam")
        or v:find("pull") or v:find("grab") then
        return false
    end
    return v:find("hitbox") ~= nil
        or v:find("hit") ~= nil
        or v:find("blackflash") ~= nil
end

-- animId -> { hit times in seconds }, fetched once then cached
local hitCache = {}
local function getHitTimes(animId)
    local cached = hitCache[animId]
    if cached then return cached end
    local times = {}
    local ok, seq = pcall(function() return KFP:GetKeyframeSequenceAsync(animId) end)
    if ok and seq then
        for _, kf in ipairs(seq:GetKeyframes()) do
            for _, m in ipairs(kf:GetMarkers()) do
                if isBlockable(m.Value) then table.insert(times, kf.Time) end
            end
        end
        pcall(function() seq:Destroy() end)
    end
    hitCache[animId] = times
    return times
end

-- hold block while hits keep coming; release HOLD after the last one
local blocking, token = false, 0
local function block()
    if not blocking then
        blocking = true
        Activated:FireServer(nil)
    end
    token += 1
    local mine = token
    task.delay(HOLD, function()
        if mine == token then
            blocking = false
            Deactivated:FireServer()
        end
    end)
end

local function watch(char)
    if char == LP.Character then return end                 -- don't block on our own hits
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5))
    if not animator then return end
    animator.AnimationPlayed:Connect(function(track)
        local id = track.Animation and track.Animation.AnimationId
        if not id or id == "" then return end
        if isUnblockable(id) then return end   -- don't waste a block on a move that ignores it
        task.spawn(function()
            local times = getHitTimes(id)
            if #times == 0 then return end
            local speed = track.Speed
            if speed <= 0 then speed = 1 end
            for _, t in ipairs(times) do
                -- seconds from now until (hit - LEAD), adjusting for playback speed/progress
                local wait = (t - LEAD) / speed - track.TimePosition
                task.delay(math.max(0, wait), function()
                    if track.IsPlaying then block() end
                end)
            end
        end)
    end)
end

for _, char in ipairs(CharsFolder:GetChildren()) do task.spawn(watch, char) end
CharsFolder.ChildAdded:Connect(function(char) task.spawn(watch, char) end)
