-- ForeverXP: Gear
-- Scores equipped gear against what a character of this level "should" wear
-- in the 1-60 world. Vanilla quest/dungeon items sit roughly at
-- itemLevel ~= requiredLevel + 3..5, so the expected average item level for a
-- level L character is about L + 3. Anything far below that is undergeared.

local _, ns = ...
local API = ns.API
local G = ns.NewModule("Gear")
ns.Gear = G

-- Slots that matter for leveling (skip shirt 4 and tabard 19).
G.SLOTS = {
    { id = 1,  name = "Head",      weight = 1.0 },
    { id = 2,  name = "Neck",      weight = 0.5 },
    { id = 3,  name = "Shoulder",  weight = 1.0 },
    { id = 5,  name = "Chest",     weight = 1.2 },
    { id = 6,  name = "Waist",     weight = 0.8 },
    { id = 7,  name = "Legs",      weight = 1.2 },
    { id = 8,  name = "Feet",      weight = 0.8 },
    { id = 9,  name = "Wrist",     weight = 0.6 },
    { id = 10, name = "Hands",     weight = 0.8 },
    { id = 11, name = "Ring 1",    weight = 0.4 },
    { id = 12, name = "Ring 2",    weight = 0.4 },
    { id = 13, name = "Trinket 1", weight = 0.2 },
    { id = 14, name = "Trinket 2", weight = 0.2 },
    { id = 15, name = "Back",      weight = 0.6 },
    { id = 16, name = "Main Hand", weight = 2.5 },
    { id = 17, name = "Off Hand",  weight = 0.8 },
    { id = 18, name = "Ranged",    weight = 0.4 },
}

-- Early levels have almost no gear slots filled; don't punish that.
local function slotExpectedAtLevel(slotID, level)
    if slotID == 1 and level < 20 then return false end        -- head
    if slotID == 3 and level < 16 then return false end        -- shoulder
    if (slotID == 2 or slotID == 11 or slotID == 12) and level < 20 then return false end
    if (slotID == 13 or slotID == 14) and level < 35 then return false end
    if slotID == 18 then return false end                      -- ranged/relic class dependent
    if slotID == 17 then return false end                      -- off hand class dependent
    return true
end

function G.ExpectedItemLevel(level)
    -- starter gear sits at ilvl ~= level; by the mid teens quest greens run ~3 above
    if level < 15 then return level + 1 end
    return level + 3
end

-- Pure scorer so it can be unit-tested.
-- items: list of { slot=, ilvl=, quality=, minLevel= } for equipped items.
function G.Score(level, items)
    local bySlot = {}
    for _, it in ipairs(items or {}) do bySlot[it.slot] = it end

    local wsum, wtotal = 0, 0
    local empties = {}
    local weak = {}
    local qualities = { [0] = 0, 0, 0, 0, 0, 0 }
    local weaponIlvl
    local expected = G.ExpectedItemLevel(level)

    for _, s in ipairs(G.SLOTS) do
        local it = bySlot[s.id]
        if it and it.ilvl and it.ilvl > 0 then
            wsum = wsum + it.ilvl * s.weight
            wtotal = wtotal + s.weight
            if it.quality then qualities[it.quality] = (qualities[it.quality] or 0) + 1 end
            if it.ilvl < expected - 10 then table.insert(weak, s.name) end
            if s.id == 16 then weaponIlvl = it.ilvl end
        elseif slotExpectedAtLevel(s.id, level) then
            table.insert(empties, s.name)
            -- an empty expected slot counts as a very low item
            wsum = wsum + math.max(expected - 15, 1) * s.weight
            wtotal = wtotal + s.weight
        end
    end

    local avg = wtotal > 0 and (wsum / wtotal) or 0
    local ratio = expected > 0 and (avg / expected) or 1
    local rating
    if avg == 0 then rating = "unknown"
    elseif ratio >= 1.08 then rating = "strong"
    elseif ratio >= 0.88 then rating = "ok"
    elseif ratio >= 0.72 then rating = "weak"
    else rating = "poor" end

    local weaponOutdated = weaponIlvl ~= nil and weaponIlvl < level - 6 and level >= 12
    if not weaponIlvl and level >= 5 then weaponOutdated = true end

    return {
        level = level,
        avg = ns.Round(avg, 1),
        expected = expected,
        ratio = ns.Round(ratio, 2),
        rating = rating,
        empties = empties,
        weakSlots = weak,
        weaponIlvl = weaponIlvl,
        weaponOutdated = weaponOutdated,
        qualities = qualities,
    }
end

function G:Scan()
    local level = API.PlayerLevel()
    local items = {}
    for _, s in ipairs(G.SLOTS) do
        local link = API.InventoryItemLink(s.id)
        if link then
            local ilvl, quality = API.ItemInfo(link)
            table.insert(items, { slot = s.id, ilvl = ilvl, quality = quality, link = link })
        end
    end
    self.last = G.Score(level, items)
    self.last.time = ns.Now()
    ns.Fire("GEAR_SCORED", self.last)
    return self.last
end

function G:Get()
    if not self.last or ns.Now() - (self.last.time or 0) > 60 then return self:Scan() end
    return self.last
end

function G.Describe(score)
    if not score or score.rating == "unknown" then return "Gear: unknown" end
    local colors = { strong = "|cff55ff55", ok = "|cffa0e0a0", weak = "|cffffcc55", poor = "|cffff6666" }
    local c = colors[score.rating] or "|cffffffff"
    return string.format("Gear: %s%s|r (avg ilvl %.0f, ~%d expected)", c, score.rating, score.avg, score.expected)
end

function G:OnLogin()
    ns.After(3, function() G:Scan() end)
    ns.Listen("GEAR_CHANGED", function() G:Scan() end)
    ns.Listen("LEVEL_UP", function() G:Scan() end)
end
