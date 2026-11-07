-- ForeverXP: Compat
-- WoW: Forever runs the modern (Mainline-style) UI API with Midnight's
-- combat restrictions. The exact surface still moves between builds, so every
-- game call the addon makes goes through this shim which:
--   * prefers the C_* namespaced API,
--   * falls back to the older globals where they still exist,
--   * never raises - callers get nil when a feature isn't available.

local _, ns = ...
local API = {}
ns.API = API

local Try = ns.Try

-------------------------------------------------------------------------------
-- Client / project detection
-------------------------------------------------------------------------------
function API.GetBuild()
    local version, build, date, toc = nil, nil, nil, nil
    if GetBuildInfo then version, build, date, toc = GetBuildInfo() end
    return version or "?", build or "?", toc or 0
end

function API.IsForever()
    -- Project constant observed on live Forever builds; feature probes are
    -- more reliable than the ID, so we accept either signal.
    if WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then return true end
    if C_GameRules and C_GameRules.GetForeverExperiencePreset then return true end
    local version = API.GetBuild()
    return tostring(version):match("^1%.6%d") ~= nil
end

function API.MaxLevel()
    local lvl = Try(GetMaxPlayerLevel)
    if type(lvl) == "number" and lvl > 0 then return lvl end
    if MAX_PLAYER_LEVEL and MAX_PLAYER_LEVEL > 0 then return MAX_PLAYER_LEVEL end
    return 60
end

-------------------------------------------------------------------------------
-- Player
-------------------------------------------------------------------------------
function API.PlayerLevel() return Try(UnitLevel, "player") or 1 end
function API.PlayerXP() return Try(UnitXP, "player") or 0 end
function API.PlayerXPMax() return Try(UnitXPMax, "player") or 1 end
function API.RestedXP() return Try(GetXPExhaustion) or 0 end
function API.IsResting() return Try(IsResting) and true or false end
function API.InCombat() return Try(InCombatLockdown) and true or false end
function API.PlayerFaction()
    local f = Try(UnitFactionGroup, "player")
    return f or "Neutral"
end
function API.PlayerClass()
    local _, class = nil, nil
    if UnitClass then _, class = UnitClass("player") end
    return class or "UNKNOWN"
end
function API.PlayerRace()
    local _, race = nil, nil
    if UnitRace then _, race = UnitRace("player") end
    return race or "UNKNOWN"
end
function API.GroupSize()
    local n = Try(GetNumGroupMembers)
    if type(n) == "number" then return n end
    return 0
end
function API.InInstance()
    local inInst, instType = nil, nil
    if IsInInstance then inInst, instType = IsInInstance() end
    return inInst and true or false, instType or "none"
end
function API.PlayerFacing()
    local f = Try(GetPlayerFacing)
    if type(f) == "number" then return f end
    return nil
end

-------------------------------------------------------------------------------
-- Map / position
-------------------------------------------------------------------------------
function API.CurrentMapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local id = Try(C_Map.GetBestMapForUnit, "player")
        if type(id) == "number" then return id end
    end
    return nil
end

function API.MapInfo(mapID)
    if not mapID or not (C_Map and C_Map.GetMapInfo) then return nil end
    local info = Try(C_Map.GetMapInfo, mapID)
    if type(info) == "table" then return info end
    return nil
end

-- Returns the name of the current zone and the chain of map names up to the
-- continent, e.g. { "Goldshire", "Elwynn Forest", "Eastern Kingdoms" }.
function API.ZoneNames()
    local names = {}
    local zone = Try(GetZoneText)
    local real = Try(GetRealZoneText)
    local sub = Try(GetSubZoneText)
    if sub and sub ~= "" then table.insert(names, sub) end
    if zone and zone ~= "" then table.insert(names, zone) end
    if real and real ~= "" and real ~= zone then table.insert(names, real) end
    local mapID = API.CurrentMapID()
    local depth = 0
    while mapID and depth < 6 do
        local info = API.MapInfo(mapID)
        if not info then break end
        if info.name and info.name ~= "" then table.insert(names, info.name) end
        mapID = info.parentMapID
        depth = depth + 1
    end
    return names
end

-- Player position on map (0..1 each) or nil when unavailable (instances).
function API.PlayerMapPosition(mapID)
    mapID = mapID or API.CurrentMapID()
    if not mapID or not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local pos = Try(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(pos) ~= "table" then return nil end
    local x, y
    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, mapID
end

-- Yards per map unit for a map (width, height).
local worldSizeCache = {}
function API.MapWorldSize(mapID)
    if not mapID then return nil end
    if worldSizeCache[mapID] then return unpack(worldSizeCache[mapID]) end
    local w, h
    if C_Map and C_Map.GetMapWorldSize then w, h = Try(C_Map.GetMapWorldSize, mapID) end
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 then return nil end
    worldSizeCache[mapID] = { w, h }
    return w, h
end

function API.SetUserWaypoint(mapID, x, y)
    if not (C_Map and C_Map.SetUserWaypoint and C_Map.CanSetUserWaypointOnMap) then return false end
    if not Try(C_Map.CanSetUserWaypointOnMap, mapID) then return false end
    local point
    if UiMapPoint and UiMapPoint.CreateFromCoordinates then
        point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    else
        point = { uiMapID = mapID, position = { x = x, y = y } }
    end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return ok
end

function API.SuperTrackQuest(questID)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        return pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
    end
    if SetSuperTrackedQuestID then return pcall(SetSuperTrackedQuestID, questID) end
    return false
end

-------------------------------------------------------------------------------
-- Quests
-------------------------------------------------------------------------------
function API.NumQuestLogEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local n = Try(C_QuestLog.GetNumQuestLogEntries)
        if type(n) == "number" then return n end
    end
    if GetNumQuestLogEntries then
        local n = Try(GetNumQuestLogEntries)
        if type(n) == "number" then return n end
    end
    return 0
end

function API.MaxQuests()
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
        local n = Try(C_QuestLog.GetMaxNumQuestsCanAccept)
        if type(n) == "number" and n > 0 then return n end
    end
    if MAX_QUESTS and MAX_QUESTS > 0 then return MAX_QUESTS end
    return 25
end

-- Normalised quest log entry: { questID, title, level, isHeader, isComplete, isOnMap, index }
function API.QuestLogEntry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = Try(C_QuestLog.GetInfo, index)
        if type(info) == "table" then
            return {
                index = index,
                questID = info.questID,
                title = info.title,
                level = info.level or info.difficultyLevel,
                isHeader = info.isHeader and true or false,
                isHidden = info.isHidden and true or false,
                isOnMap = info.isOnMap and true or false,
                hasLocalPOI = info.hasLocalPOI and true or false,
                headerName = info.isHeader and info.title or nil,
            }
        end
        return nil
    end
    if GetQuestLogTitle then
        local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
        if not title then return nil end
        return {
            index = index, questID = questID, title = title, level = level,
            isHeader = isHeader and true or false, isComplete = isComplete,
        }
    end
    return nil
end

function API.QuestIsComplete(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then
        local r = Try(C_QuestLog.ReadyForTurnIn, questID)
        if r ~= nil then return r and true or false end
    end
    if C_QuestLog and C_QuestLog.IsComplete then
        local r = Try(C_QuestLog.IsComplete, questID)
        if r ~= nil then return r and true or false end
    end
    return false
end

function API.QuestIsFailed(questID)
    if C_QuestLog and C_QuestLog.IsFailed then return Try(C_QuestLog.IsFailed, questID) and true or false end
    return false
end

function API.QuestRewardXP(questID)
    if not questID then return nil end
    local xp
    if GetQuestLogRewardXP then xp = Try(GetQuestLogRewardXP, questID) end
    if type(xp) == "number" and xp > 0 then return xp end
    if C_QuestLog and C_QuestLog.GetQuestRewardXP then
        xp = Try(C_QuestLog.GetQuestRewardXP, questID)
        if type(xp) == "number" and xp > 0 then return xp end
    end
    return nil
end

-- Returns { {text=, finished=, fulfilled=, required=}, ... }
function API.QuestObjectives(questID)
    local out = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local list = Try(C_QuestLog.GetQuestObjectives, questID)
        if type(list) == "table" then
            for _, o in ipairs(list) do
                table.insert(out, {
                    text = o.text or "",
                    finished = o.finished and true or false,
                    fulfilled = tonumber(o.numFulfilled) or 0,
                    required = tonumber(o.numRequired) or 0,
                })
            end
        end
    end
    return out
end

function API.QuestsOnMap(mapID)
    if not mapID or not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return {} end
    local list = Try(C_QuestLog.GetQuestsOnMap, mapID)
    if type(list) ~= "table" then return {} end
    return list
end

-- Next waypoint for a quest on the given map: x, y (0..1) or nil
function API.QuestWaypoint(questID, mapID)
    if not questID or not mapID or not (C_QuestLog and C_QuestLog.GetNextWaypointForMap) then return nil end
    local x, y = Try(C_QuestLog.GetNextWaypointForMap, questID, mapID)
    if type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end

function API.QuestDistanceSq(questID)
    if not questID or not (C_QuestLog and C_QuestLog.GetDistanceSqToQuest) then return nil end
    local d, onContinent = Try(C_QuestLog.GetDistanceSqToQuest, questID)
    if type(d) == "number" then return d, onContinent end
    return nil
end

function API.SuperTrackedQuest()
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        return Try(C_SuperTrack.GetSuperTrackedQuestID)
    end
    if GetSuperTrackedQuestID then return Try(GetSuperTrackedQuestID) end
    return nil
end

-------------------------------------------------------------------------------
-- Items / gear
-------------------------------------------------------------------------------
function API.InventoryItemLink(slot)
    return Try(GetInventoryItemLink, "player", slot)
end

-- Returns itemLevel, quality, equipSlot, name for a link (any may be nil).
function API.ItemInfo(link)
    if not link then return nil end
    local name, quality, ilvl, equipLoc
    if C_Item and C_Item.GetItemInfo then
        local n, _, q, lvl, _, _, _, _, loc = Try(C_Item.GetItemInfo, link)
        name, quality, ilvl, equipLoc = n, q, lvl, loc
    elseif GetItemInfo then
        local n, _, q, lvl, _, _, _, _, loc = Try(GetItemInfo, link)
        name, quality, ilvl, equipLoc = n, q, lvl, loc
    end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local real = Try(C_Item.GetDetailedItemLevelInfo, link)
        if type(real) == "number" and real > 0 then ilvl = real end
    elseif GetDetailedItemLevelInfo then
        local real = Try(GetDetailedItemLevelInfo, link)
        if type(real) == "number" and real > 0 then ilvl = real end
    end
    return ilvl, quality, equipLoc, name
end

function API.ItemMinLevel(link)
    if not link then return nil end
    local minLevel
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, _, ml = Try(C_Item.GetItemInfo, link)
        minLevel = ml
    elseif GetItemInfo then
        local _, _, _, _, ml = Try(GetItemInfo, link)
        minLevel = ml
    end
    return tonumber(minLevel)
end

-------------------------------------------------------------------------------
-- Misc
-------------------------------------------------------------------------------
function API.AddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return Try(C_AddOns.GetAddOnMetadata, ns.ADDON, "Version") or ns.VERSION
    end
    if GetAddOnMetadata then return Try(GetAddOnMetadata, ns.ADDON, "Version") or ns.VERSION end
    return ns.VERSION
end
