-- ForeverXP: Zone route database
--
-- Level ranges are the "sweet spot" for questing XP. WoW: Forever keeps the
-- classic 1-60 curve, so the original zones use their vanilla ranges. The new
-- Forever zones (Zephras Isle, Riverglades, Shen'dralas, Mount Hyjal) are
-- marked confidence = "estimate" because Blizzard has not published official
-- ranges; the addon learns their real map IDs the first time you stand in them
-- and you can correct a range with  /fxp zone <min> <max>.
--
-- faction: "Alliance", "Horde" or "Both"
-- hub:     where to pick up quests
-- travel:  one-line hint on how to get there
-- bonus:   extra fit score for unusually quest-dense zones
-- tags:    "starter", "forever" (new in Forever), "contested"

local _, ns = ...

ns.ZONES = {
    ---------------------------------------------------------------- 1-12
    { name = "Elwynn Forest",      faction = "Alliance", min = 1,  max = 10, hub = "Goldshire",            tags = { "starter" } },
    { name = "Dun Morogh",         faction = "Alliance", min = 1,  max = 10, hub = "Kharanos",             tags = { "starter" } },
    { name = "Teldrassil",         faction = "Alliance", min = 1,  max = 10, hub = "Dolanaar",             tags = { "starter" } },
    { name = "Durotar",            faction = "Horde",    min = 1,  max = 10, hub = "Razor Hill",           tags = { "starter" } },
    { name = "Mulgore",            faction = "Horde",    min = 1,  max = 10, hub = "Bloodhoof Village",    tags = { "starter" } },
    { name = "Tirisfal Glades",    faction = "Horde",    min = 1,  max = 10, hub = "Brill",                tags = { "starter" } },
    { name = "Zephras Isle",       faction = "Both",     min = 1,  max = 12, hub = "Skyborne settlement",  tags = { "starter", "forever" }, confidence = "estimate",
      notes = "Skyborne starting isle. Open to both factions as a 1-12 stop." },

    ---------------------------------------------------------------- 10-20
    { name = "Westfall",           faction = "Alliance", min = 10, max = 20, hub = "Sentinel Hill",        travel = "South of Elwynn via the bridge at the Forest's southwest." },
    { name = "Loch Modan",         faction = "Alliance", min = 10, max = 20, hub = "Thelsamar",            travel = "East of Dun Morogh through the tunnel." },
    { name = "Darkshore",          faction = "Alliance", min = 10, max = 20, hub = "Auberdine",            travel = "Boat from Rut'theran Village (Teldrassil)." },
    { name = "The Barrens",        faction = "Horde",    min = 10, max = 25, hub = "The Crossroads",       travel = "West of Durotar; Crossroads is the main hub.", bonus = 0.15,
      notes = "Huge quest density; the Horde's best 10-25 zone." },
    { name = "Silverpine Forest",  faction = "Horde",    min = 10, max = 20, hub = "The Sepulcher",        travel = "South of Tirisfal Glades." },
    { name = "Redridge Mountains", faction = "Alliance", min = 15, max = 25, hub = "Lakeshire",            travel = "East of Elwynn via the road past Eastvale Logging Camp." },
    { name = "Stonetalon Mountains", faction = "Both",   min = 15, max = 27, hub = "Sun Rock Retreat / Stonetalon Peak", tags = { "contested" } },
    { name = "Ashenvale",          faction = "Both",     min = 18, max = 30, hub = "Astranaar (A) / Splintertree Post (H)", tags = { "contested" } },
    { name = "Duskwood",           faction = "Alliance", min = 18, max = 30, hub = "Darkshire",            travel = "South of Elwynn, east of Westfall." },
    { name = "Wetlands",           faction = "Alliance", min = 20, max = 30, hub = "Menethil Harbor",      travel = "North of Loch Modan via Dun Algaz." },
    { name = "Hillsbrad Foothills", faction = "Both",    min = 20, max = 30, hub = "Southshore (A) / Tarren Mill (H)", tags = { "contested" } },

    ---------------------------------------------------------------- 25-40
    { name = "Thousand Needles",   faction = "Both",     min = 25, max = 35, hub = "Freewind Post (H) / Shimmering Flats (Both)", tags = { "contested" },
      notes = "Shimmering Flats quests are great for both factions." },
    { name = "Desolace",           faction = "Both",     min = 30, max = 40, hub = "Nijel's Point (A) / Shadowprey Village (H)", tags = { "contested" } },
    { name = "Arathi Highlands",   faction = "Both",     min = 30, max = 40, hub = "Refuge Pointe (A) / Hammerfall (H)", tags = { "contested" } },
    { name = "Alterac Mountains",  faction = "Both",     min = 30, max = 40, hub = "Southshore / Tarren Mill (quests from Hillsbrad)", tags = { "contested" } },
    { name = "Stranglethorn Vale", faction = "Both",     min = 30, max = 45, hub = "Nesingwary's Expedition / Booty Bay", tags = { "contested" },
      notes = "Very quest-dense. Expect world PvP on PvP realms.", bonus = 0.1 },
    { name = "Dustwallow Marsh",   faction = "Both",     min = 35, max = 45, hub = "Theramore (A) / Brackenwall Village (H)", tags = { "contested" } },
    { name = "Swamp of Sorrows",   faction = "Both",     min = 36, max = 43, hub = "Stonard (H)",          tags = { "contested" } },
    { name = "Riverglades",        faction = "Both",     min = 35, max = 45, hub = "Riverglades hub",      tags = { "forever", "contested" }, confidence = "estimate",
      notes = "New Forever zone with its own dungeon; fills the classic 35-45 gap." },
    { name = "Badlands",           faction = "Both",     min = 35, max = 45, hub = "Kargath (H)",          tags = { "contested" } },

    ---------------------------------------------------------------- 40-50
    { name = "The Hinterlands",    faction = "Both",     min = 40, max = 50, hub = "Aerie Peak (A) / Revantusk Village (H)", tags = { "contested" } },
    { name = "Feralas",            faction = "Both",     min = 40, max = 50, hub = "Feathermoon Stronghold (A) / Camp Mojache (H)", tags = { "contested" } },
    { name = "Tanaris",            faction = "Both",     min = 40, max = 50, hub = "Gadgetzan",            tags = { "contested" } },
    { name = "Searing Gorge",      faction = "Both",     min = 43, max = 50, hub = "Thorium Point",        tags = { "contested" } },
    { name = "Shen'dralas",        faction = "Both",     min = 45, max = 55, hub = "Shen'dralas hub",      tags = { "forever", "contested" }, confidence = "estimate",
      notes = "New Forever highborne zone. Range is an estimate until Blizzard publishes one." },

    ---------------------------------------------------------------- 45-60
    { name = "Azshara",            faction = "Both",     min = 45, max = 55, hub = "Talrendis Point (A) / Valormok (H)", tags = { "contested" } },
    { name = "Blasted Lands",      faction = "Both",     min = 45, max = 55, hub = "Nethergarde Keep (A)", tags = { "contested" } },
    { name = "Un'Goro Crater",     faction = "Both",     min = 48, max = 55, hub = "Marshal's Refuge",     tags = { "contested" },
      notes = "Quest-dense and neutral: one of the best 48-55 zones for both factions.", bonus = 0.1 },
    { name = "Felwood",            faction = "Both",     min = 48, max = 55, hub = "Emerald Sanctuary / Bloodvenom Post (H)", tags = { "contested" } },
    { name = "Burning Steppes",    faction = "Both",     min = 50, max = 58, hub = "Morgan's Vigil (A) / Flame Crest (H)", tags = { "contested" } },
    { name = "Western Plaguelands", faction = "Both",    min = 51, max = 58, hub = "Chillwind Camp (A) / The Bulwark (H)", tags = { "contested" } },
    { name = "Eastern Plaguelands", faction = "Both",    min = 53, max = 60, hub = "Light's Hope Chapel",  tags = { "contested" } },
    { name = "Winterspring",       faction = "Both",     min = 53, max = 60, hub = "Everlook",             tags = { "contested" } },
    { name = "Mount Hyjal",        faction = "Both",     min = 55, max = 60, hub = "Hyjal hub",            tags = { "forever", "contested" }, confidence = "estimate",
      notes = "New Forever zone. Late-50s to 60; leads into Forever's new 60 content." },
    { name = "Silithus",           faction = "Both",     min = 55, max = 60, hub = "Cenarion Hold",        tags = { "contested" } },
}

-- Cities (no XP, but good for "you're resting / go back out" logic)
ns.CITIES = {
    ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true,
    ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true,
}

-- Build lookup by normalised name once.
ns.ZONE_BY_KEY = {}
for i, z in ipairs(ns.ZONES) do
    z.key = ns.ZoneKey(z.name)
    z.index = i
    z.confidence = z.confidence or "high"
    z.tags = z.tags or {}
    ns.ZONE_BY_KEY[z.key] = z
end

function ns.ZoneHasTag(zone, tag)
    if not zone or not zone.tags then return false end
    for _, t in ipairs(zone.tags) do if t == tag then return true end end
    return false
end

function ns.ZoneForFaction(zone, faction)
    if not zone then return false end
    return zone.faction == "Both" or zone.faction == faction
end

-- Effective range after user overrides (/fxp zone min max)
function ns.ZoneRange(zone)
    local o = ns.db and ns.db.zoneRanges and ns.db.zoneRanges[zone.key]
    if o then return o.min, o.max end
    return zone.min, zone.max
end

-- Resolve the zone record the player is standing in.
-- names: list of candidate names (subzone, zone, map chain). mapID optional.
function ns.FindZone(names, mapID)
    if mapID and ns.db and ns.db.mapOverrides then
        for key, id in pairs(ns.db.mapOverrides) do
            if id == mapID and ns.ZONE_BY_KEY[key] then return ns.ZONE_BY_KEY[key] end
        end
    end
    for _, n in ipairs(names or {}) do
        local z = ns.ZONE_BY_KEY[ns.ZoneKey(n)]
        if z then return z end
    end
    return nil
end

function ns.IsCity(names)
    for _, n in ipairs(names or {}) do
        if ns.CITIES[n] then return true end
    end
    return false
end

-- Zones that fit a level for a faction, best first.
-- fit score: 1.0 when the level sits in the lower-middle of the range (lots of
-- quests ahead of you), tapering to 0 at the edges.
function ns.ZonesForLevel(level, faction, opts)
    opts = opts or {}
    local out = {}
    for _, z in ipairs(ns.ZONES) do
        if ns.ZoneForFaction(z, faction) then
            local lo, hi = ns.ZoneRange(z)
            local slack = opts.slack or 1
            if level >= lo - slack and level <= hi then
                local span = math.max(hi - lo, 1)
                local pos = (level - lo) / span          -- 0 at min, 1 at max
                local ideal = 0.35
                local fit = 1 - math.abs(pos - ideal) / (1 - ideal)
                if z.confidence == "estimate" then fit = fit - 0.08 end
                if level < lo then fit = fit - 0.25 end
                fit = fit + (z.bonus or 0)
                table.insert(out, { zone = z, fit = fit, min = lo, max = hi })
            end
        end
    end
    table.sort(out, function(a, b) return a.fit > b.fit end)
    return out
end
