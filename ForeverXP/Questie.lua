-- ForeverXP: Questie bridge
-- Optional. When Questie (Forever build) is installed, this reads its quest
-- database to find quests you can pick up nearby and where completed quests
-- are turned in. Everything is wrapped in pcall; without Questie every
-- function returns an empty result and the rest of the addon works as before.
--
-- Questie internals used (read from Questie's source, Forever TOC):
--   QuestieLoader:ImportModule("AvailableQuests").__availableQuests  questId -> true
--   QuestieDB.GetQuest(id)   -> { name, level, requiredLevel, Starts = { NPC, GameObject, Item }, Finisher = { NPC, GameObject }, IsRepeatable, isHidden }
--   QuestieDB:GetNPC(id)     -> { name, spawns = { [areaId] = { {x, y}, ... } } }  (x, y in 0-100)
--   QuestieDB:GetObject(id)  -> same shape
--   ZoneDB:GetUiMapIdByAreaId(areaId)

local _, ns = ...
local API = ns.API
local B = ns.NewModule("QuestieBridge")
ns.QuestieBridge = B

B.cache = { time = 0, key = nil, mapID = nil, pickups = {} }
local CACHE_SECONDS = 10

local function mod(name)
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then return nil end
    local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    if ok and type(m) == "table" then return m end
    return nil
end

-- Call tbl.fn either as a method or a plain function, whichever works.
local function call(tbl, fnName, ...)
    if type(tbl) ~= "table" or type(tbl[fnName]) ~= "function" then return nil end
    local ok, r = pcall(tbl[fnName], tbl, ...)
    if ok and r ~= nil then return r end
    ok, r = pcall(tbl[fnName], ...)
    if ok then return r end
    return nil
end

function B.IsAvailable()
    local db = mod("QuestieDB")
    return db ~= nil and type(db.GetQuest) == "function"
end

function B.Version()
    if not B.IsAvailable() then return nil end
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return ns.Try(C_AddOns.GetAddOnMetadata, "Questie", "Version")
    end
    return "?"
end

-- Nearest spawn of an entity (npc/object record) on uiMapID. Returns x, y (0..1), dist units or nil.
local function nearestSpawn(entity, mapID, px, py)
    if type(entity) ~= "table" or type(entity.spawns) ~= "table" then return nil end
    local zoneDB = mod("ZoneDB")
    local best, bx, by
    for areaId, spawns in pairs(entity.spawns) do
        local uiMapID = call(zoneDB, "GetUiMapIdByAreaId", areaId)
        if uiMapID == mapID and type(spawns) == "table" then
            for _, c in ipairs(spawns) do
                local x, y = tonumber(c[1]), tonumber(c[2])
                if x and y and x >= 0 and y >= 0 then
                    x, y = x / 100, y / 100
                    local d = (x - px) ^ 2 + (y - py) ^ 2
                    if not best or d < best then best, bx, by = d, x, y end
                end
            end
        end
    end
    if best then return bx, by, best end
    return nil
end

local function starterLocation(db, ids, getter, mapID, px, py)
    if type(ids) ~= "table" then return nil end
    local best, bx, by, bname
    for _, id in ipairs(ids) do
        local ent = call(db, getter, id)
        local x, y, d = nearestSpawn(ent, mapID, px, py)
        if x and (not best or d < best) then best, bx, by, bname = d, x, y, ent and ent.name end
    end
    if best then return bx, by, bname, best end
    return nil
end

-- Quests you can pick up on the current map, nearest first.
-- opts: { level, slack (max quest level above you), maxCount, exclude (questID -> true) }
function B.Pickups(mapID, px, py, opts)
    opts = opts or {}
    if not mapID or not px or not B.IsAvailable() then return {} end
    local now = ns.Now()
    local c = B.cache
    local level = opts.level or API.PlayerLevel()
    local slack = opts.slack or 2
    local key = string.format("%d:%d:%d", mapID, level, slack)
    local out
    if c.key == key and now - c.time < CACHE_SECONDS and not opts.force then
        out = c.pickups
    else
        out = B.Candidates(mapID, px, py, level, slack)
        c.time, c.key, c.mapID, c.pickups = now, key, mapID, out
    end
    -- per-call filtering on top of the cached candidate list
    local filtered = {}
    for _, p in ipairs(out) do
        if not (opts.exclude and opts.exclude[p.questID]) then
            table.insert(filtered, p)
            if opts.maxCount and #filtered >= opts.maxCount then break end
        end
    end
    return filtered
end

-- All level-appropriate available quests with a starter on this map, nearest first (uncached).
function B.Candidates(mapID, px, py, level, slack)
    local db = mod("QuestieDB")
    local avail = mod("AvailableQuests")
    local list = avail and avail.__availableQuests
    local out = {}
    if type(list) == "table" then
        for questID in pairs(list) do
            do
                local q = call(db, "GetQuest", questID)
                if type(q) == "table" and not q.isHidden and not q.IsRepeatable then
                    local qlevel = tonumber(q.level) or level
                    local req = tonumber(q.requiredLevel) or 0
                    local diff = ns.Quests.Difficulty(level, qlevel)
                    if req <= level and qlevel <= level + slack and diff ~= "gray" then
                        local starts = q.Starts or {}
                        local x, y, giver, d = starterLocation(db, starts.NPC, "GetNPC", mapID, px, py)
                        if not x then x, y, giver, d = starterLocation(db, starts.GameObject, "GetObject", mapID, px, py) end
                        if x then
                            table.insert(out, {
                                kind = "pickup", questID = questID, title = q.name or ("Quest " .. questID),
                                level = qlevel, mapID = mapID, x = x, y = y, giver = giver, distSq = d,
                                xp = ns.Quests.EstimateXP(qlevel, level), difficulty = diff,
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.distSq < b.distSq end)
    return out
end

-- Where a quest is turned in on this map (x, y, npcName) or nil.
function B.TurnInLocation(questID, mapID, px, py)
    if not B.IsAvailable() or not mapID then return nil end
    local db = mod("QuestieDB")
    local q = call(db, "GetQuest", questID)
    if type(q) ~= "table" or type(q.Finisher) ~= "table" then return nil end
    local x, y, name = starterLocation(db, q.Finisher.NPC, "GetNPC", mapID, px or 0.5, py or 0.5)
    if not x then x, y, name = starterLocation(db, q.Finisher.GameObject, "GetObject", mapID, px or 0.5, py or 0.5) end
    return x, y, name
end

function B.Invalidate() B.cache.time = 0 end

function B:OnLogin()
    ns.Listen("QUESTS_CHANGED", function() B.Invalidate() end)
    ns.After(8, function()
        if B.IsAvailable() then ns.Debug("Questie %s detected: quest pickups enabled", tostring(B.Version())) end
    end)
end
