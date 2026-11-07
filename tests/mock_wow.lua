-- Minimal mock of the WoW UI environment, enough to load every addon file
-- headlessly and drive the pure logic. Not a simulation of the game.

unpack = unpack or table.unpack
local M = {}

local METHOD_PREFIXES = { "Set", "Get", "Is", "Create", "Register", "Unregister", "Enable", "Disable", "Show", "Hide", "Clear", "Start", "Stop", "Raise", "Lower", "Add", "Can" }
local function isMethodName(k)
    for _, p in ipairs(METHOD_PREFIXES) do
        if k:sub(1, #p) == p and k:sub(#p + 1, #p + 1):match("%u") then return true end
    end
    return false
end

-- generic frame object: any method call is a no-op returning nil, except a few
local function newFrame(kind, name, parent, template)
    local f = {}
    f.__kind, f.__name, f.__shown, f.__children, f.__scripts = kind, name, true, {}, {}
    local mt = {}
    mt.__index = function(t, k)
        if k == "CreateFontString" or k == "CreateTexture" then
            return function() return newFrame(k) end
        elseif k == "SetScript" then
            return function(self, ev, fn) self.__scripts[ev] = fn end
        elseif k == "GetScript" then
            return function(self, ev) return self.__scripts[ev] end
        elseif k == "Show" then return function(self) self.__shown = true end
        elseif k == "Hide" then return function(self) self.__shown = false end
        elseif k == "IsShown" then return function(self) return self.__shown end
        elseif k == "GetName" then return function(self) return self.__name end
        elseif k == "GetPoint" then return function() return "TOPRIGHT", nil, "TOPRIGHT", -220, -120 end
        elseif k == "GetStringHeight" then return function() return 24 end
        elseif k == "GetChecked" then return function(self) return self.__checked end
        elseif k == "SetChecked" then return function(self, v) self.__checked = v end
        elseif k == "RegisterEvent" then return function(self, ev) M.registered[ev] = true end
        elseif k == "UnregisterEvent" then return function() end
        elseif type(k) == "string" and isMethodName(k) then
            return function() end
        else
            return nil
        end
    end
    setmetatable(f, mt)
    if name then _G[name] = f end
    return f
end

M.registered = {}
M.timers = {}

function CreateFrame(kind, name, parent, template)
    if template == "EXPLODE" then error("bad template") end
    return newFrame(kind, name, parent, template)
end
UIParent = newFrame("Frame", "UIParent")
GameTooltip = newFrame("GameTooltip", "GameTooltip")
M.messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.lastMessage = msg; table.insert(M.messages, msg); if M.echo then print(msg) end end }
function M.Errors()
    local out = {}
    for _, m in ipairs(M.messages) do if m:find("error") then table.insert(out, m) end end
    return out
end
BackdropTemplateMixin = {}
SlashCmdList = {}
C_Timer = {
    After = function(s, fn) table.insert(M.timers, { at = s, fn = fn }) end,
    NewTicker = function(s, fn) table.insert(M.timers, { at = s, fn = fn, ticker = true }); return { Cancel = function() end } end,
}
function M.RunTimers()
    local list = M.timers
    M.timers = {}
    for _, t in ipairs(list) do t.fn() end
end

-- Player state (mutable from tests)
M.player = {
    level = 23, xp = 4000, xpMax = 10000, rested = 0, resting = false, faction = "Alliance", class = "WARRIOR",
    race = "Human", group = 0, inInstance = false, instanceType = "none", facing = 0,
    zone = "Duskwood", subzone = "Darkshire", mapID = 47, pos = { x = 0.5, y = 0.5 },
    inventory = {}, quests = {}, maxQuests = 25, build = { "1.60.1", "70338", "Nov 4 2026", 16001 },
}
local p = M.player
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT = 1, 2, 18
WOW_PROJECT_ID = 18
function GetBuildInfo() return p.build[1], p.build[2], p.build[3], p.build[4] end
function GetMaxPlayerLevel() return 60 end
function UnitLevel() return p.level end
function UnitXP() return p.xp end
function UnitXPMax() return p.xpMax end
function GetXPExhaustion() return p.rested > 0 and p.rested or nil end
function IsResting() return p.resting end
function InCombatLockdown() return false end
function UnitFactionGroup() return p.faction end
function UnitClass() return p.class, p.class end
function UnitRace() return p.race, p.race end
function GetNumGroupMembers() return p.group end
function IsInInstance() return p.inInstance, p.instanceType end
function GetPlayerFacing() return p.facing end
function GetZoneText() return p.zone end
function GetRealZoneText() return p.zone end
function GetSubZoneText() return p.subzone end
function GetTime() return M.now or 1000 end
function time() return 1700000000 end
function GetInventoryItemLink(_, slot) return p.inventory[slot] and p.inventory[slot].link end
function GetQuestLogRewardXP(questID)
    for _, q in ipairs(p.quests) do if q.questID == questID then return q.xp end end
end

C_Map = {
    GetBestMapForUnit = function() return p.mapID end,
    GetMapInfo = function(id)
        if id == p.mapID then return { mapID = id, name = p.zone, mapType = 3, parentMapID = 13 } end
        if id == 13 then return { mapID = 13, name = "Eastern Kingdoms", mapType = 2 } end
    end,
    GetPlayerMapPosition = function(id) if id ~= p.mapID or p.inInstance then return nil end return { x = p.pos.x, y = p.pos.y, GetXY = function(s) return s.x, s.y end } end,
    GetMapWorldSize = function() return 2000, 2000 end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(pt) M.waypoint = pt end,
}
C_SuperTrack = { SetSuperTrackedQuestID = function(id) M.tracked = id end, SetSuperTrackedUserWaypoint = function() end, GetSuperTrackedQuestID = function() return M.tracked end }
C_Item = {
    GetItemInfo = function(link)
        for _, it in pairs(p.inventory) do
            if it.link == link then return it.name, link, it.quality, it.ilvl, it.minLevel, "Armor", "Cloth", 1, "INVTYPE_CHEST" end
        end
    end,
}
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
C_GameRules = { GetForeverExperiencePreset = function() return 1 end }
C_QuestLog = {
    GetNumQuestLogEntries = function() return #p.quests end,
    GetMaxNumQuestsCanAccept = function() return p.maxQuests end,
    GetInfo = function(i)
        local q = p.quests[i]
        if not q then return nil end
        return { questID = q.questID, title = q.title, level = q.level, isHeader = q.isHeader, isOnMap = q.inZone, isHidden = false }
    end,
    ReadyForTurnIn = function(id) for _, q in ipairs(p.quests) do if q.questID == id then return q.complete end end end,
    IsFailed = function() return false end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(p.quests) do if q.questID == id then return q.objectives or {} end end
        return {}
    end,
    GetQuestsOnMap = function() return {} end,
    GetNextWaypointForMap = function(id, mapID)
        for _, q in ipairs(p.quests) do if q.questID == id and q.wp then return q.wp.x, q.wp.y end end
    end,
    GetDistanceSqToQuest = function(id)
        for _, q in ipairs(p.quests) do if q.questID == id then return q.distSq or 0, true end end
    end,
}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) M.openedOptions = id end,
}

-- Load the addon files in TOC order with the (ADDON, ns) vararg the client passes.
function M.LoadAddon(root)
    local ns = {}
    local toc = assert(io.open(root .. "/ForeverXP.toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^##") and line:match("%S") then
            local path = root .. "/" .. line:gsub("\\", "/")
            local chunk, err = loadfile(path)
            assert(chunk, err)
            chunk("ForeverXP", ns)
        end
    end
    return ns
end

-- Fire a WoW event into the addon's event frame.
function M.Event(ns, event, ...)
    local fn = ns.eventFrame.__scripts.OnEvent
    fn(ns.eventFrame, event, ...)
end


-------------------------------------------------------------------------------
-- Optional Questie mock (call M.EnableQuestie() in a test).
-- Shapes mirror Questie's Forever build: AvailableQuests.__availableQuests,
-- QuestieDB.GetQuest / :GetNPC / :GetObject, ZoneDB:GetUiMapIdByAreaId.
-------------------------------------------------------------------------------
function M.EnableQuestie(data)
    data = data or {}
    local modules = {}
    QuestieLoader = { ImportModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end }
    local db = QuestieLoader:ImportModule("QuestieDB")
    local avail = QuestieLoader:ImportModule("AvailableQuests")
    local zone = QuestieLoader:ImportModule("ZoneDB")
    avail.__availableQuests = data.available or {}
    db.quests, db.npcs, db.objects = data.quests or {}, data.npcs or {}, data.objects or {}
    function db.GetQuest(id) return db.quests[id] end
    function db:GetNPC(id) return self.npcs[id] end
    function db:GetObject(id) return self.objects[id] end
    function zone:GetUiMapIdByAreaId(areaId) return (data.areaToMap or {})[areaId] end
    M.questie = { modules = modules, db = db, avail = avail }
    return M.questie
end
function M.DisableQuestie() QuestieLoader = nil; M.questie = nil end

return M
