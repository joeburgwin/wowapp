-- ForeverXP: Tracker
-- Tracks XP gains, XP/hour, rested state, and classifies what the player is
-- currently doing (questing, grinding, dungeon, traveling, resting, idle).
-- Uses only XP / quest / chat events - no combat log, which Forever restricts.

local _, ns = ...
local API = ns.API
local T = ns.NewModule("Tracker")
ns.Tracker = T

T.samples = {}        -- ring of { t = time, xp = gained, kind = "kill"|"quest"|"other" }
T.events = {}         -- recent activity markers { t=, kind= }
T.lastXP = nil
T.lastMax = nil
T.lastLevel = nil
T.positions = {}      -- recent { t, x, y, mapID } for movement detection
T.activity = "idle"
T.activityReason = ""
T.sessionStart = 0

local ACTIVITY_WINDOW = 180  -- seconds considered "recent"
local SAMPLE_KEEP = 3600     -- keep an hour of samples

local function prune(list, maxAge)
    local now = ns.Now()
    local i = 1
    while i <= #list do
        if now - list[i].t > maxAge then table.remove(list, i) else i = i + 1 end
    end
end

function T:Mark(kind, data)
    table.insert(self.events, { t = ns.Now(), kind = kind, data = data })
    prune(self.events, ACTIVITY_WINDOW * 2)
end

function T:AddXP(amount, kind)
    if not amount or amount <= 0 then return end
    table.insert(self.samples, { t = ns.Now(), xp = amount, kind = kind or "other" })
    prune(self.samples, SAMPLE_KEEP)
    local s = ns.cdb and ns.cdb.session
    if s then
        if kind == "kill" then s.killXP = (s.killXP or 0) + amount
        elseif kind == "quest" then s.questXP = (s.questXP or 0) + amount
        else s.otherXP = (s.otherXP or 0) + amount end
    end
    self:Mark(kind == "quest" and "questxp" or (kind == "kill" and "killxp" or "xp"), amount)
    ns.Fire("XP_GAINED", amount, kind)
end

-- XP per hour over the configured window, plus split by kind.
function T:XPPerHour(window)
    window = window or (ns.db and ns.db.xpWindow) or 900
    local now = ns.Now()
    local total, kill, quest = 0, 0, 0
    local oldest = now
    for _, s in ipairs(self.samples) do
        if now - s.t <= window then
            total = total + s.xp
            if s.kind == "kill" then kill = kill + s.xp elseif s.kind == "quest" then quest = quest + s.xp end
            if s.t < oldest then oldest = s.t end
        end
    end
    -- Use elapsed time since the session started if that is shorter than the window
    local elapsed = math.min(window, now - (self.sessionStart > 0 and self.sessionStart or now))
    if elapsed < 60 then elapsed = 60 end
    local perHour = total / elapsed * 3600
    return perHour, kill / elapsed * 3600, quest / elapsed * 3600, total, elapsed
end

function T:TimeToLevel()
    local rate = self:XPPerHour()
    if rate <= 0 then return nil end
    local remaining = API.PlayerXPMax() - API.PlayerXP()
    return remaining / rate * 3600
end

-- Count of recent markers of a kind.
function T:Recent(kind, window)
    window = window or ACTIVITY_WINDOW
    local now, n = ns.Now(), 0
    for _, e in ipairs(self.events) do
        if e.kind == kind and now - e.t <= window then n = n + 1 end
    end
    return n
end

function T:RecentDistance(window)
    window = window or ACTIVITY_WINDOW
    local now, dist = ns.Now(), 0
    local prev
    for _, p in ipairs(self.positions) do
        if now - p.t <= window then
            if prev and prev.mapID == p.mapID then
                local w, h = API.MapWorldSize(p.mapID)
                w, h = w or 1000, h or 1000
                local dx, dy = (p.x - prev.x) * w, (p.y - prev.y) * h
                dist = dist + math.sqrt(dx * dx + dy * dy)
            end
            prev = p
        end
    end
    return dist
end

-- Pure classifier so it can be unit tested.
-- facts: { inInstance, instanceType, resting, killXP, questXP, questProgress, distance, inCity, groupSize }
function T.Classify(facts)
    if facts.inInstance and (facts.instanceType == "party" or facts.instanceType == "raid") then
        return "dungeon", "inside an instance"
    end
    if facts.questXP > 0 or facts.questProgress > 0 then
        if facts.killXP >= 6 and facts.questProgress == 0 then
            return "grinding", "lots of kills, no quest progress"
        end
        return "questing", "quest progress in the last few minutes"
    end
    if facts.killXP >= 3 then
        return "grinding", "kill XP with no quest progress"
    end
    if facts.distance > 400 then
        return "traveling", "moving a lot with no XP"
    end
    if facts.resting or facts.inCity then
        return "resting", "in an inn or city"
    end
    return "idle", "no XP or movement recently"
end

function T:UpdateActivity()
    local inInst, instType = API.InInstance()
    local facts = {
        inInstance = inInst,
        instanceType = instType,
        resting = API.IsResting(),
        killXP = self:Recent("killxp"),
        questXP = self:Recent("questxp"),
        questProgress = self:Recent("questprogress"),
        distance = self:RecentDistance(),
        inCity = ns.IsCity(API.ZoneNames()),
        groupSize = API.GroupSize(),
    }
    local act, reason = T.Classify(facts)
    if act ~= self.activity then
        self.activity = act
        self.activityReason = reason
        ns.Fire("ACTIVITY_CHANGED", act, reason)
    end
    return act
end

function T:SamplePosition()
    local x, y, mapID = API.PlayerMapPosition()
    if not x then return end
    table.insert(self.positions, { t = ns.Now(), x = x, y = y, mapID = mapID })
    prune(self.positions, ACTIVITY_WINDOW * 2)
end

-- Handle XP bar change; figures out the delta even across a level-up.
function T:OnXPUpdate()
    local xp, max, level = API.PlayerXP(), API.PlayerXPMax(), API.PlayerLevel()
    if self.lastXP ~= nil then
        local gained
        if level > (self.lastLevel or level) then
            gained = (self.lastMax - self.lastXP) + xp
        else
            gained = xp - self.lastXP
        end
        if gained > 0 and not self.pendingKind then
            -- XP that didn't come through a chat/quest event (exploration, etc.)
            self:AddXP(gained, "other")
        end
        self.pendingKind = nil
    end
    self.lastXP, self.lastMax, self.lastLevel = xp, max, level
    ns.Fire("XP_CHANGED", xp, max, level)
end

-- CHAT_MSG_COMBAT_XP_GAIN text parsing (locale tolerant: looks for "dies" / "experience")
local function parseXPMessage(msg)
    if not msg then return nil end
    local raw = msg:match("(%d[%d,%.]*)%s+experience") or msg:match("(%d[%d,%.]*)%s+Erfahrung")
        or msg:match("(%d[%d,%.]*)%s+exp") or msg:match("(%d[%d,]*)")
    local amount = raw and tonumber((raw:gsub("[,%.]", "")))
    if not amount or amount <= 0 then return nil end
    local kind = "kill"
    if msg:find("^You gain") or msg:find("[Qq]uest") then kind = "quest" end
    if msg:find("dies") or msg:find("Rested bonus") or msg:find("Group bonus") then kind = "kill" end
    if msg:find("[Ee]xplor") or msg:find("[Dd]iscover") then kind = "other" end
    return amount, kind
end
T.ParseXPMessage = parseXPMessage

function T:OnInit()
    self.sessionStart = ns.Now()
    if ns.cdb and ns.cdb.session then
        ns.cdb.session = { killXP = 0, questXP = 0, otherXP = 0, started = time and time() or 0 }
    end
end

function T:OnLogin()
    self.lastXP, self.lastMax, self.lastLevel = API.PlayerXP(), API.PlayerXPMax(), API.PlayerLevel()

    ns.RegisterEvent("PLAYER_XP_UPDATE", function() T:OnXPUpdate() end)
    ns.RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
        ns.cdb.levelTimes[tostring(level)] = time and time() or 0
        ns.After(0.5, function() T:OnXPUpdate(); ns.Fire("LEVEL_UP", level) end)
    end)
    ns.RegisterEvent("UPDATE_EXHAUSTION", function() ns.Fire("RESTED_CHANGED", API.RestedXP()) end)
    ns.RegisterEvent("PLAYER_UPDATE_RESTING", function() T:UpdateActivity() end)

    ns.RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg)
        local amount, kind = parseXPMessage(msg)
        if amount then
            T.pendingKind = kind
            T:AddXP(amount, kind)
        end
    end)

    -- QUEST_TURNED_IN carries the XP reward directly on modern clients.
    ns.RegisterEvent("QUEST_TURNED_IN", function(_, questID, xpReward)
        if type(xpReward) == "number" and xpReward > 0 then
            T.pendingKind = "quest"
            T:AddXP(xpReward, "quest")
        end
        T:Mark("questturnin", questID)
        ns.Fire("QUEST_TURNED_IN", questID, xpReward)
    end)
    ns.RegisterEvent("QUEST_ACCEPTED", function(_, questID) T:Mark("questaccept", questID); ns.Fire("QUESTS_CHANGED") end)
    ns.RegisterEvent("QUEST_REMOVED", function() ns.Fire("QUESTS_CHANGED") end)
    ns.RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(_, unit)
        if unit == "player" then T:Mark("questprogress"); ns.Fire("QUESTS_CHANGED") end
    end)
    ns.RegisterEvent("QUEST_WATCH_UPDATE", function() T:Mark("questprogress") end)
    ns.RegisterEvent("QUEST_LOG_UPDATE", ns.Debounce(1, function() ns.Fire("QUESTS_CHANGED") end))

    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() ns.Fire("ZONE_CHANGED") end)
    ns.RegisterEvent("ZONE_CHANGED", function() ns.Fire("ZONE_CHANGED") end)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.After(2, function() ns.Fire("ZONE_CHANGED") end) end)
    ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() ns.Fire("GROUP_CHANGED") end)
    ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", ns.Debounce(2, function() ns.Fire("GEAR_CHANGED") end))
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() ns.Fire("COMBAT", true) end)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() ns.Fire("COMBAT", false) end)

    ns.Ticker(5, function()
        T:SamplePosition()
        T:UpdateActivity()
    end)
end
