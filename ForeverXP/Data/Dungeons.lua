-- ForeverXP: Dungeon database
--
-- In WoW: Forever, dungeon trash XP was reduced while dungeon *quest* XP and
-- rewards were increased, so the advisor always tells you to collect the
-- dungeon's quests before you zone in. New Forever dungeons are marked
-- confidence = "estimate" until their ranges settle.

local _, ns = ...

ns.DUNGEONS = {
    { name = "Ragefire Chasm",        faction = "Horde",    min = 13, max = 18, zone = "Orgrimmar",            questHub = "Orgrimmar (Cleft of Shadow)" },
    { name = "The Deadmines",         faction = "Alliance", min = 17, max = 24, zone = "Westfall",             questHub = "Sentinel Hill" },
    { name = "Wailing Caverns",       faction = "Both",     min = 17, max = 24, zone = "The Barrens",          questHub = "The Crossroads / cave entrance" },
    { name = "Shadowfang Keep",       faction = "Both",     min = 22, max = 30, zone = "Silverpine Forest",    questHub = "The Sepulcher (H) / Stormwind (A)" },
    { name = "Blackfathom Deeps",     faction = "Both",     min = 24, max = 32, zone = "Ashenvale",            questHub = "Auberdine (A) / Ratchet (H)" },
    { name = "The Stockade",          faction = "Alliance", min = 24, max = 32, zone = "Stormwind City",       questHub = "Stormwind / Lakeshire" },
    { name = "Gnomeregan",            faction = "Both",     min = 29, max = 38, zone = "Dun Morogh",           questHub = "Ironforge (Tinker Town) / Booty Bay (H)" },
    { name = "Razorfen Kraul",        faction = "Both",     min = 29, max = 38, zone = "The Barrens",          questHub = "Thunder Bluff / Ironforge" },
    { name = "Scarlet Monastery",     faction = "Both",     min = 34, max = 45, zone = "Tirisfal Glades",      questHub = "Undercity (H) / Southshore (A)" },
    { name = "Razorfen Downs",        faction = "Both",     min = 37, max = 46, zone = "The Barrens",          questHub = "Thunder Bluff / Darnassus" },
    { name = "Uldaman",               faction = "Both",     min = 41, max = 51, zone = "Badlands",             questHub = "Ironforge / Kargath + Badlands dig site" },
    { name = "Zul'Farrak",            faction = "Both",     min = 44, max = 54, zone = "Tanaris",              questHub = "Gadgetzan / Shimmering Flats" },
    { name = "Maraudon",              faction = "Both",     min = 46, max = 55, zone = "Desolace",             questHub = "Nijel's Point (A) / Shadowprey Village (H)" },
    { name = "The Temple of Atal'Hakkar", faction = "Both", min = 50, max = 56, zone = "Swamp of Sorrows",     questHub = "Stonard / Tanaris / Un'Goro" },
    { name = "Blackrock Depths",      faction = "Both",     min = 52, max = 60, zone = "Burning Steppes",      questHub = "Thorium Point / Morgan's Vigil / Flame Crest" },
    { name = "Blackmaw Hold",         faction = "Both",     min = 55, max = 60, zone = "Mount Hyjal",          questHub = "Hyjal hub", tags = { "forever" }, confidence = "estimate" },
    { name = "Lower Blackrock Spire", faction = "Both",     min = 55, max = 60, zone = "Burning Steppes",      questHub = "Morgan's Vigil / Flame Crest" },
    { name = "Dire Maul",             faction = "Both",     min = 56, max = 60, zone = "Feralas",              questHub = "Feathermoon / Camp Mojache" },
    { name = "Shaper's Terrace",      faction = "Both",     min = 58, max = 60, zone = "Un'Goro Crater",       questHub = "Marshal's Refuge", tags = { "forever" }, confidence = "estimate" },
    { name = "Scholomance",           faction = "Both",     min = 58, max = 60, zone = "Western Plaguelands",  questHub = "Chillwind Camp / The Bulwark" },
    { name = "Stratholme",            faction = "Both",     min = 58, max = 60, zone = "Eastern Plaguelands",  questHub = "Light's Hope Chapel" },
}

for i, d in ipairs(ns.DUNGEONS) do
    d.key = ns.ZoneKey(d.name)
    d.index = i
    d.confidence = d.confidence or "high"
    d.tags = d.tags or {}
end

-- Dungeons appropriate for a level, best first. A dungeon is "ideal" when the
-- player sits in the lower half of its range (bosses still give full XP and
-- quest rewards are upgrades).
function ns.DungeonsForLevel(level, faction)
    local out = {}
    for _, d in ipairs(ns.DUNGEONS) do
        if d.faction == "Both" or d.faction == faction then
            if level >= d.min - 1 and level <= d.max then
                local span = math.max(d.max - d.min, 1)
                local pos = (level - d.min) / span
                local fit = 1 - math.abs(pos - 0.4) / 0.6
                if d.confidence == "estimate" then fit = fit - 0.08 end
                table.insert(out, { dungeon = d, fit = fit })
            end
        end
    end
    table.sort(out, function(a, b) return a.fit > b.fit end)
    return out
end

function ns.FindDungeon(names)
    for _, n in ipairs(names or {}) do
        local key = ns.ZoneKey(n)
        for _, d in ipairs(ns.DUNGEONS) do
            if d.key == key then return d end
        end
    end
    return nil
end
