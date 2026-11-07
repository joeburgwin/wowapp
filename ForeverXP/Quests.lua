-- ForeverXP: Quests
-- Scans the quest log and enriches each quest with: estimated XP, difficulty
-- colour, completion, objective progress, whether it is in the current zone,
-- and a waypoint if the client exposes one.

local _, ns = ...
local API = ns.API
local Q = ns.NewModule("Quests")
ns.Quests = Q

Q.list = {}
Q.byID = {}

-- Classic quest XP falloff: full XP while playerLevel <= questLevel + 5,
-- then 80/60/40/20/10 %.
function Q.XPMultiplier(playerLevel, questLevel)
    if not questLevel or questLevel <= 0 then return 1 end
    local diff = playerLevel - questLevel
    if diff <= 5 then return 1.0 end
    if diff == 6 then return 0.8 end
    if diff == 7 then return 0.6 end
    if diff == 8 then return 0.4 end
    if diff == 9 then return 0.2 end
    return 0.1
end

-- Difficulty colour name in classic terms.
function Q.Difficulty(playerLevel, questLevel)
    if not questLevel or questLevel <= 0 then return "normal" end
    local diff = questLevel - playerLevel
    if diff >= 5 then return "red" end
    if diff >= 3 then return "orange" end
    if diff >= -2 then return "yellow" end
    local grayAt = 5 + math.floor(playerLevel / 10)
    if playerLevel >= 60 then grayAt = 9 end
    if -diff >= grayAt then return "gray" end
    return "green"
end

local COLORS = { red = "|cffff2020", orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040", gray = "|cff808080", normal = "|cffffffff" }
function Q.Color(diff) return COLORS[diff] or COLORS.normal end

-- Rough vanilla quest XP curve when the API gives nothing:
-- ~ (questLevel * 45 + 100) scaled by level.
function Q.EstimateXP(questLevel, playerLevel)
    questLevel = questLevel or playerLevel
    local base = questLevel * 45 + 100
    if questLevel >= 50 then base = base * 1.3 elseif questLevel >= 30 then base = base * 1.15 end
    return math.floor(base * Q.XPMultiplier(playerLevel, questLevel))
end

function Q:Scan()
    local level = API.PlayerLevel()
    local mapID = API.CurrentMapID()
    local onMap = {}
    for _, q in ipairs(API.QuestsOnMap(mapID)) do
        if q.questID then onMap[q.questID] = q end
    end
    local list, byID = {}, {}
    local header
    local n = API.NumQuestLogEntries()
    for i = 1, n do
        local e = API.QuestLogEntry(i)
        if e then
            if e.isHeader then
                header = e.title
            elseif e.questID and not e.isHidden then
                local q = e
                q.header = header
                q.complete = (e.isComplete == true) or (e.isComplete == 1) or API.QuestIsComplete(e.questID)
                q.failed = API.QuestIsFailed(e.questID)
                q.objectives = API.QuestObjectives(e.questID)
                local done, total = 0, 0
                for _, o in ipairs(q.objectives) do
                    total = total + 1
                    if o.finished then done = done + 1 end
                end
                q.objDone, q.objTotal = done, total
                local apiXP = API.QuestRewardXP(e.questID)
                q.xp = apiXP or Q.EstimateXP(e.level, level)
                q.xpIsEstimate = apiXP == nil
                q.mult = Q.XPMultiplier(level, e.level)
                q.difficulty = Q.Difficulty(level, e.level)
                q.inZone = e.isOnMap or onMap[e.questID] ~= nil or e.hasLocalPOI
                    or (header ~= nil and ns.ZoneKey(header) == ns.ZoneKey(select(2, Q.CurrentZoneName())))
                if mapID then
                    local wx, wy = API.QuestWaypoint(e.questID, mapID)
                    if wx then q.wp = { mapID = mapID, x = wx, y = wy } end
                    if not q.wp and onMap[e.questID] and onMap[e.questID].x then
                        q.wp = { mapID = mapID, x = onMap[e.questID].x, y = onMap[e.questID].y }
                    end
                end
                -- completed quest with no client waypoint: ask Questie where it is turned in
                if q.complete and not q.wp and mapID and ns.QuestieBridge and ns.QuestieBridge.IsAvailable() then
                    local px, py = API.PlayerMapPosition(mapID)
                    local x, y, who = ns.QuestieBridge.TurnInLocation(e.questID, mapID, px, py)
                    if x then q.wp = { mapID = mapID, x = x, y = y, who = who } end
                end
                q.distSq = API.QuestDistanceSq(e.questID)
                table.insert(list, q)
                byID[e.questID] = q
            end
        end
    end
    self.list, self.byID = list, byID
    self.lastScan = ns.Now()
    ns.Fire("QUESTS_SCANNED", list)
    return list
end

function Q.CurrentZoneName()
    local names = API.ZoneNames()
    return names, names[2] or names[1]
end

-- Summary used by the advisor.
function Q:Summary()
    local s = { total = #self.list, ready = {}, inZone = {}, inZoneReady = {}, gray = {}, xpReady = 0, xpInZone = 0, active = {} }
    for _, q in ipairs(self.list) do
        if q.complete and not q.failed then
            table.insert(s.ready, q); s.xpReady = s.xpReady + q.xp
            if q.inZone then table.insert(s.inZoneReady, q) end
        elseif not q.failed then
            table.insert(s.active, q)
            if q.inZone then table.insert(s.inZone, q); s.xpInZone = s.xpInZone + q.xp end
        end
        if q.difficulty == "gray" then table.insert(s.gray, q) end
    end
    s.max = API.MaxQuests()
    s.full = s.total >= s.max - 1
    return s
end

-- Pick the most valuable quest to point the arrow at:
-- complete quests first (sorted by XP), then closest in-zone active quest.
function Q:Priority()
    local best, bestScore
    for _, q in ipairs(self.list) do
        if not q.failed then
            local score = q.xp * q.mult
            if q.complete then score = score * 3 end
            if q.inZone then score = score * 1.5 end
            if q.distSq and q.distSq > 0 then score = score / (1 + math.sqrt(q.distSq) / 500) end
            if q.objTotal > 0 then score = score * (1 + q.objDone / q.objTotal) end
            if not bestScore or score > bestScore then best, bestScore = q, score end
        end
    end
    return best
end

function Q:OnLogin()
    local rescan = ns.Debounce(1.5, function() Q:Scan() end)
    ns.Listen("QUESTS_CHANGED", rescan)
    ns.Listen("ZONE_CHANGED", rescan)
    ns.Listen("LEVEL_UP", rescan)
    ns.After(4, function() Q:Scan() end)
    ns.Ticker(30, function() Q:Scan() end)
end
