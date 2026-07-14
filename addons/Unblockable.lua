-- Unblockable move animation IDs.
-- Blockability is server-side in JJS — it is NOT in the animation data, hitbox parts,
-- or any client module (verified: the only "unblockable" strings in the client are
-- patch notes). So strike-type unblockables like Rush are indistinguishable from a
-- normal jab by anything we can read. This hand-maintained list is the only reliable
-- source. Add moves as you find them; keys are the numeric part of the animation id
-- (rbxassetid:// prefix optional — lookups strip it).
--
-- Shared by AutoBlock.lua (skips these) and AnimationViewer.lua (marks them orange).

local ids = {
    "107554693613496",  -- Itadori / Rush
}

local set = {}
for _, id in ipairs(ids) do
    set[(tostring(id):gsub("%D", ""))] = true   -- store digits only
end

-- isUnblockable("rbxassetid://123") or ("123") -> bool
return function(animId)
    return set[(tostring(animId or ""):gsub("%D", ""))] == true
end
