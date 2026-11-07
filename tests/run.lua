-- Headless test runner: lua5.4 tests/run.lua  (from repo root)
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("  ok   " .. name)
    else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. string.format(" expected %s, got %s", tostring(b), tostring(a)), 2) end
end
local function near(a, b, tol, msg)
    if math.abs(a - b) > (tol or 1e-6) then error((msg or "") .. string.format(" expected ~%s, got %s", tostring(b), tostring(a)), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end
local function has(list, pred)
    for _, v in ipairs(list) do if pred(v) then return v end end
    return nil
end

print("Loading addon through mock client")
local ns = M.LoadAddon("ForeverXP")
local p = M.player

-------------------------------------------------------------------------------
print("Core")
test("FormatNumber", function()
    eq(ns.FormatNumber(950), "950"); eq(ns.FormatNumber(1250), "1,250"); eq(ns.FormatNumber(12500), "12.5k"); eq(ns.FormatNumber(2500000), "2.5m")
end)
test("FormatDuration", function()
    eq(ns.FormatDuration(30), "<1m"); eq(ns.FormatDuration(600), "10m"); eq(ns.FormatDuration(3900), "1h 05m"); eq(ns.FormatDuration(nil), "--")
end)
test("ZoneKey normalises apostrophes and spaces", function()
    eq(ns.ZoneKey("Shen'dralas"), "shendralas"); eq(ns.ZoneKey("Shen’dralas"), "shendralas"); eq(ns.ZoneKey("Un'Goro Crater"), "ungorocrater")
end)

-------------------------------------------------------------------------------
print("Lifecycle")
test("ADDON_LOADED + PLAYER_LOGIN run without errors", function()
    M.lastMessage = nil
    M.Event(ns, "ADDON_LOADED", "ForeverXP")
    truthy(ns.db, "db initialised"); eq(ns.db.enabled, true)
    M.Event(ns, "PLAYER_LOGIN")
    M.RunTimers(); M.RunTimers()
    local errs = M.Errors()
    truthy(#errs == 0, "errors printed: " .. table.concat(errs, " | "))
    truthy(M.registered["PLAYER_XP_UPDATE"], "XP event registered")
    truthy(M.registered["QUEST_TURNED_IN"], "quest event registered")
    truthy(_G.ForeverXPPanel, "panel frame created")
end)
test("Compat detects Forever", function()
    truthy(ns.API.IsForever()); eq(ns.API.MaxLevel(), 60)
end)

-------------------------------------------------------------------------------
print("Zones & dungeons")
test("FindZone by name chain", function()
    eq(ns.FindZone({ "Darkshire", "Duskwood", "Eastern Kingdoms" }).name, "Duskwood")
    eq(ns.FindZone({ "Shen’dralas" }).name, "Shen'dralas")
    eq(ns.FindZone({ "Nowhere" }), nil)
end)
test("FindZone via learned map override", function()
    ns.db.mapOverrides.riverglades = 9001
    eq(ns.FindZone({ "???" }, 9001).name, "Riverglades")
    ns.db.mapOverrides.riverglades = nil
end)
test("ZonesForLevel respects faction and range", function()
    local list = ns.ZonesForLevel(23, "Alliance")
    truthy(#list > 0)
    truthy(not has(list, function(c) return c.zone.faction == "Horde" end), "no Horde zones for Alliance")
    truthy(has(list, function(c) return c.zone.name == "Duskwood" end), "Duskwood listed")
    truthy(not has(list, function(c) return c.zone.name == "Westfall" end), "Westfall (10-20) excluded at 23")
    local horde = ns.ZonesForLevel(12, "Horde")
    eq(horde[1].zone.name, "The Barrens")
end)
test("Zone range override", function()
    ns.db.zoneRanges = { riverglades = { min = 30, max = 40 } }
    local lo, hi = ns.ZoneRange(ns.ZONE_BY_KEY.riverglades)
    eq(lo, 30); eq(hi, 40)
    ns.db.zoneRanges = nil
end)
test("DungeonsForLevel", function()
    local d = ns.DungeonsForLevel(19, "Alliance")
    eq(d[1].dungeon.name, "The Deadmines")
    truthy(not has(d, function(c) return c.dungeon.name == "Ragefire Chasm" end), "Horde-only dungeon excluded")
    local late = ns.DungeonsForLevel(58, "Horde")
    truthy(has(late, function(c) return c.dungeon.name == "Shaper's Terrace" end), "Forever dungeon present")
end)

-------------------------------------------------------------------------------
print("Quests")
test("XP multiplier falloff", function()
    local Q = ns.Quests
    eq(Q.XPMultiplier(30, 27), 1.0); eq(Q.XPMultiplier(30, 24), 0.8); eq(Q.XPMultiplier(30, 22), 0.4); eq(Q.XPMultiplier(30, 15), 0.1)
end)
test("Difficulty colours", function()
    local Q = ns.Quests
    eq(Q.Difficulty(30, 36), "red"); eq(Q.Difficulty(30, 33), "orange"); eq(Q.Difficulty(30, 30), "yellow"); eq(Q.Difficulty(30, 25), "green"); eq(Q.Difficulty(30, 20), "gray")
    eq(Q.Difficulty(5, 1), "green"); eq(Q.Difficulty(12, 6), "gray")
end)
test("EstimateXP grows with level and decays when gray", function()
    local Q = ns.Quests
    truthy(Q.EstimateXP(40, 40) > Q.EstimateXP(20, 20))
    truthy(Q.EstimateXP(20, 40) < Q.EstimateXP(20, 20) / 5)
end)

-------------------------------------------------------------------------------
print("Gear")
test("Gear score: level-appropriate gear is ok", function()
    local items = {}
    for _, s in ipairs(ns.Gear.SLOTS) do table.insert(items, { slot = s.id, ilvl = 33, quality = 2 }) end
    local sc = ns.Gear.Score(30, items)
    eq(sc.rating, "ok"); eq(sc.weaponOutdated, false)
end)
test("Gear score: outdated gear is poor and flags weapon", function()
    local items = {}
    for _, s in ipairs(ns.Gear.SLOTS) do table.insert(items, { slot = s.id, ilvl = 14, quality = 1 }) end
    local sc = ns.Gear.Score(30, items)
    eq(sc.rating, "poor"); eq(sc.weaponOutdated, true)
end)
test("Gear score: empty expected slots pull the average down", function()
    local sc = ns.Gear.Score(40, { { slot = 16, ilvl = 43 }, { slot = 5, ilvl = 43 } })
    truthy(#sc.empties >= 8, "many empties"); truthy(sc.rating == "weak" or sc.rating == "poor")
end)
test("Gear score: low level ignores head/shoulder/ring slots", function()
    local sc = ns.Gear.Score(8, { { slot = 16, ilvl = 10 }, { slot = 5, ilvl = 9 }, { slot = 7, ilvl = 9 }, { slot = 8, ilvl = 8 }, { slot = 6, ilvl = 8 }, { slot = 10, ilvl = 8 }, { slot = 9, ilvl = 8 }, { slot = 15, ilvl = 8 } })
    truthy(not has(sc.empties, function(n) return n == "Head" end))
    eq(sc.rating, "ok")
end)

-------------------------------------------------------------------------------
print("Tracker")
test("Classify activities", function()
    local C = ns.Tracker.Classify
    local base = { inInstance = false, instanceType = "none", resting = false, killXP = 0, questXP = 0, questProgress = 0, distance = 0, inCity = false, groupSize = 0 }
    local function with(t) local c = {}; for k, v in pairs(base) do c[k] = v end; for k, v in pairs(t) do c[k] = v end; return c end
    eq(C(with({ inInstance = true, instanceType = "party" })), "dungeon")
    eq(C(with({ questProgress = 2 })), "questing")
    eq(C(with({ killXP = 5 })), "grinding")
    eq(C(with({ killXP = 8, questXP = 1 })), "grinding")
    eq(C(with({ distance = 900 })), "traveling")
    eq(C(with({ resting = true })), "resting")
    eq(C(with({})), "idle")
end)
test("Parse XP chat messages", function()
    local P = ns.Tracker.ParseXPMessage
    local a, k = P("Young Wolf dies, you gain 45 experience.") eq(a, 45); eq(k, "kill")
    a, k = P("Defias Thug dies, you gain 62 experience. (+31 Rested bonus)") eq(a, 62); eq(k, "kill")
    a, k = P("You gain 1,250 experience.") eq(a, 1250); eq(k, "quest")
    a, k = P("Discovered Lakeshire: 350 experience gained") eq(a, 350); eq(k, "other")
    a, k = P("Experience gained: 2,340.") eq(a, 2340)
    eq(P("Hello there"), nil)
end)
test("XP/hour and time to level from samples", function()
    local T = ns.Tracker
    T.samples = {}; T.sessionStart = 1000; M.now = 1600
    T:AddXP(1000, "kill"); T:AddXP(500, "quest")
    local rate, kill, quest = T:XPPerHour(900)
    eq(rate, 9000); eq(kill, 6000); eq(quest, 3000)
    p.xp, p.xpMax = 1000, 10000
    near(T:TimeToLevel(), 3600, 1)
    M.now = nil
end)
test("OnXPUpdate handles level-up delta", function()
    local T = ns.Tracker
    T.samples = {}; T.pendingKind = nil
    p.level, p.xp, p.xpMax = 23, 9500, 10000
    T:OnXPUpdate()
    p.level, p.xp, p.xpMax = 24, 300, 11000
    T:OnXPUpdate()
    eq(T.samples[#T.samples].xp, 800)
    p.level, p.xp, p.xpMax = 23, 4000, 10000
    T:OnXPUpdate(); T.samples = {}
end)

-------------------------------------------------------------------------------
print("Advisor")
local function ctx(over, nils)
    local c = {
        level = 23, maxLevel = 60, xp = 4000, xpMax = 10000, rested = 0, faction = "Alliance",
        zone = ns.ZONE_BY_KEY.duskwood, zoneLo = 18, zoneHi = 30, zoneNames = { "Duskwood" },
        inCity = false, inInstance = false, instanceType = "none", groupSize = 0, activity = "questing",
        xpPerHour = 6000, gear = ns.Gear.Score(23, (function() local t = {} for _, s in ipairs(ns.Gear.SLOTS) do table.insert(t, { slot = s.id, ilvl = 26 }) end return t end)()),
        quests = { total = 5, ready = {}, inZone = {}, inZoneReady = {}, gray = {}, xpReady = 0, xpInZone = 0, active = {}, max = 25, full = false },
        sessionSeconds = 2000,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    for _, k in ipairs(nils or {}) do c[k] = nil end
    return c
end
local function q(id, title, opts)
    local t = { questID = id, title = title, level = 23, xp = 1200, mult = 1, complete = false, inZone = true, objDone = 0, objTotal = 1, difficulty = "yellow" }
    for k, v in pairs(opts or {}) do t[k] = v end
    return t
end

test("Turn-ins top the list", function()
    local ready = { q(1, "A", { complete = true, wp = { mapID = 47, x = 0.4, y = 0.4 } }), q(2, "B", { complete = true }) }
    local c = ctx({ quests = { total = 5, ready = ready, inZone = {}, inZoneReady = ready, gray = {}, xpReady = 2400, xpInZone = 0, active = {}, max = 25, full = false } })
    local s = ns.Advisor.Build(c)
    eq(s[1].kind, "turnin"); truthy(s[1].title:find("2 completed quests")); eq(s[1].action.mapID, 47)
end)
test("Keep questing when the zone fits and quests are held", function()
    local inZone = { q(1, "A"), q(2, "B"), q(3, "C") }
    local c = ctx({ quests = { total = 5, ready = {}, inZone = inZone, inZoneReady = {}, gray = {}, xpReady = 0, xpInZone = 3600, active = inZone, max = 25, full = false }, priorityQuest = inZone[2] })
    local s = ns.Advisor.Build(c)
    eq(s[1].kind, "quest"); truthy(s[1].title:find("Duskwood")); eq(s[1].action.questID, 2)
end)
test("Pick up quests when the log is empty for the zone", function()
    local s = ns.Advisor.Build(ctx())
    eq(s[1].kind, "pickup"); truthy(s[1].title:find("Darkshire"))
end)
test("Outleveled zone suggests moving on", function()
    local s = ns.Advisor.Build(ctx({ level = 33, zone = ns.ZONE_BY_KEY.duskwood, zoneLo = 18, zoneHi = 30 }))
    eq(s[1].kind, "move"); truthy(s[1].title:find("Move on to"))
    truthy(s[1].zone.faction ~= "Horde")
end)
test("Zone above level warns", function()
    local s = ns.Advisor.Build(ctx({ level = 12, zone = ns.ZONE_BY_KEY.duskwood, zoneLo = 18, zoneHi = 30 }))
    eq(s[1].kind, "move"); truthy(s[1].title:find("above your level"))
end)
test("Grinding with no rested XP pushes quests", function()
    local s = ns.Advisor.Build(ctx({ activity = "grinding", xpPerHour = 3000 }))
    truthy(has(s, function(x) return x.kind == "activity" and x.title:find("rested") end))
    truthy(has(s, function(x) return x.kind == "dungeon" end), "solo dungeon option offered while grinding")
end)
test("Grinding with rested XP and quests pairs them", function()
    local inZone = { q(1, "A") }
    local s = ns.Advisor.Build(ctx({ activity = "grinding", rested = 3000, quests = { total = 1, ready = {}, inZone = inZone, inZoneReady = {}, gray = {}, xpReady = 0, xpInZone = 1200, active = inZone, max = 25, full = false } }))
    truthy(has(s, function(x) return x.title:find("quest mobs") end))
end)
test("Group of five gets a dungeon on top", function()
    local s = ns.Advisor.Build(ctx({ groupSize = 5 }))
    eq(s[1].kind, "dungeon"); truthy(s[1].title:find("with your group"))
end)
test("Inside a dungeon: finish its quests", function()
    local s = ns.Advisor.Build(ctx({ inInstance = true, instanceType = "party", dungeon = ns.DUNGEONS[2], activity = "dungeon" }))
    eq(s[1].kind, "dungeon"); truthy(s[1].title:find("Deadmines"))
end)
test("Poor gear produces a gear suggestion with a fix", function()
    local items = {}
    for _, sl in ipairs(ns.Gear.SLOTS) do table.insert(items, { slot = sl.id, ilvl = 12 }) end
    local s = ns.Advisor.Build(ctx({ gear = ns.Gear.Score(23, items) }))
    local g = has(s, function(x) return x.kind == "gear" end)
    truthy(g); truthy(g.title:find("poor")); truthy(g.detail:find("weapon")); truthy(g.detail:find("loot"))
end)
test("Rested XP note when idle/questing", function()
    local s = ns.Advisor.Build(ctx({ rested = 2500 }))
    truthy(has(s, function(x) return x.kind == "rested" and x.title:find("25%%") end))
end)
test("Gray quests flagged", function()
    local g = { q(9, "Old", { difficulty = "gray", mult = 0.1 }) }
    local s = ns.Advisor.Build(ctx({ quests = { total = 1, ready = {}, inZone = g, inZoneReady = {}, gray = g, xpReady = 0, xpInZone = 120, active = g, max = 25, full = false } }))
    truthy(has(s, function(x) return x.kind == "gray" end))
end)
test("City: go back out", function()
    local s = ns.Advisor.Build(ctx({ inCity = true, activity = "resting" }, { "zone", "zoneLo", "zoneHi" }))
    eq(s[1].kind, "move"); truthy(s[1].title:find("Back out"))
end)
test("Unknown zone: head to best-fit", function()
    local s = ns.Advisor.Build(ctx({}, { "zone", "zoneLo", "zoneHi" }))
    eq(s[1].kind, "move"); truthy(s[1].title:find("Head to"))
end)
test("Max level", function()
    local s = ns.Advisor.Build(ctx({ level = 60 }))
    eq(#s, 1); eq(s[1].kind, "max")
end)
test("Suggestions sorted by score", function()
    local ready = { q(1, "A", { complete = true }) }
    local s = ns.Advisor.Build(ctx({ groupSize = 5, rested = 100, quests = { total = 1, ready = ready, inZone = {}, inZoneReady = {}, gray = {}, xpReady = 1200, xpInZone = 0, active = {}, max = 25, full = false } }))
    for i = 2, #s do truthy(s[i - 1].score >= s[i].score, "sorted") end
end)

-------------------------------------------------------------------------------
print("Arrow math")
test("Bearing: north is 0, west is +pi/2, east is -pi/2, south is pi", function()
    local R = ns.Arrow
    near(R.Bearing(0.5, 0.5, 0.5, 0.4), 0)
    near(R.Bearing(0.5, 0.5, 0.4, 0.5), math.pi / 2)
    near(R.Bearing(0.5, 0.5, 0.6, 0.5), -math.pi / 2)
    near(math.abs(R.Bearing(0.5, 0.5, 0.5, 0.6)), math.pi)
end)
test("Rotation subtracts facing and wraps", function()
    local R = ns.Arrow
    near(R.Rotation(math.pi / 2, math.pi / 2), 0)
    near(R.Rotation(-math.pi * 0.9, math.pi * 0.9), math.pi * 0.2)
end)
test("Distance in yards from map size", function()
    near(ns.Arrow.Distance(0.5, 0.5, 0.5, 0.6, 2000, 2000), 200, 1e-6)
end)

-------------------------------------------------------------------------------
print("UI helpers")
test("StatusLine", function()
    local line = ns.Panel.StatusLine({ level = 23, xp = 4000, xpMax = 10000, xpPerHour = 8200, timeToLevel = 2634, rested = 3000, gear = { rating = "ok" }, activity = "questing" })
    truthy(line:find("Lv 23 · 40%%")); truthy(line:find("8.2k XP/h")); truthy(line:find("Rested 30%%")); truthy(line:find("Gear ok")); truthy(line:find("Questing"))
end)
test("QuestList.Order: complete first then XP", function()
    local o = ns.QuestList.Order({ q(1, "low", { xp = 100 }), q(2, "done", { complete = true, xp = 50 }), q(3, "high", { xp = 900 }), q(4, "failed", { failed = true }) })
    eq(#o, 3); eq(o[1].title, "done"); eq(o[2].title, "high"); eq(o[3].title, "low")
end)

-------------------------------------------------------------------------------
print("Integration through the mock client")
test("Quest scan + advisor with a mocked quest log", function()
    p.level, p.xp, p.xpMax, p.rested = 23, 4000, 10000, 0
    p.quests = {
        { questID = 0, title = "Duskwood", isHeader = true },
        { questID = 101, title = "The Legend of Stalvan", level = 24, xp = 1400, inZone = true, complete = false, objectives = { { text = "Find the chest", finished = false, numFulfilled = 0, numRequired = 1 } }, wp = { x = 0.6, y = 0.4 }, distSq = 40000 },
        { questID = 102, title = "Wolves at Our Heels", level = 22, xp = 1100, inZone = true, complete = true, objectives = { { text = "Dire Wolf slain", finished = true, numFulfilled = 8, numRequired = 8 } }, wp = { x = 0.55, y = 0.5 }, distSq = 2500 },
        { questID = 103, title = "Seasoned Wolf Kabobs", level = 20, xp = 900, inZone = true, complete = false, objectives = { { text = "Wolf Meat", finished = false, numFulfilled = 3, numRequired = 6 } } },
    }
    local list = ns.Quests:Scan()
    eq(#list, 3)
    truthy(ns.Quests.byID[102].complete)
    eq(ns.Quests.byID[101].xp, 1400); eq(ns.Quests.byID[101].xpIsEstimate, false)
    eq(ns.Quests.byID[103].objDone, 0); eq(ns.Quests.byID[103].objTotal, 1)
    ns.Advisor:Refresh()
    local s = ns.Advisor.suggestions
    truthy(#s > 0, "has suggestions")
    eq(s[1].kind, "turnin"); truthy(s[1].title:find("1 completed quest"))
    eq(ns.Advisor.ctx.zone.name, "Duskwood")
    eq(ns.db.mapOverrides.duskwood, 47, "learned map id for the zone")
    local pri = ns.Quests:Priority()
    eq(pri.questID, 102, "completed quest wins priority")
    ns.Arrow:AutoTarget()
    eq(ns.Arrow.target.mapID, 47); eq(ns.Arrow.target.label, "Wolves at Our Heels")
    ns.Arrow:Tick()
    truthy(ns.Arrow.frame.__shown)
    ns.Panel:Update(); ns.QuestList:Update()
    truthy(_G.ForeverXPPanel.__shown); truthy(_G.ForeverXPQuestList.__shown)
end)
test("Clicking a suggestion sets waypoint and tracks", function()
    ns.Panel.Act(ns.Advisor.suggestions[1])
    eq(M.tracked, 102); truthy(M.waypoint); truthy(ns.Arrow.target.manual)
end)
test("Chat XP events feed the tracker", function()
    local before = #ns.Tracker.samples
    M.Event(ns, "CHAT_MSG_COMBAT_XP_GAIN", "Dire Wolf dies, you gain 120 experience.")
    eq(#ns.Tracker.samples, before + 1); eq(ns.Tracker.samples[#ns.Tracker.samples].kind, "kill")
    M.Event(ns, "QUEST_TURNED_IN", 102, 1100, 0)
    eq(ns.Tracker.samples[#ns.Tracker.samples].kind, "quest"); eq(ns.cdb.session.questXP >= 1100, true)
end)
test("Slash commands", function()
    local H = ns.HandleCommand
    H("status"); truthy(M.lastMessage:find("Client 1.60.1"))
    H("zone 20 28"); eq(ns.db.zoneRanges.duskwood.min, 20); eq(ns.db.zoneRanges.duskwood.max, 28)
    H("learn riverglades"); eq(ns.db.mapOverrides.riverglades, 47)
    ns.db.mapOverrides.riverglades = nil; ns.db.zoneRanges = nil
    H("scale 1.2"); eq(ns.db.scale, 1.2)
    H("alpha 5"); eq(ns.db.alpha, 1)
    H("lock"); eq(ns.db.locked, true); H("unlock"); eq(ns.db.locked, false)
    H("arrow"); eq(ns.db.showArrow, false); H("arrow"); eq(ns.db.showArrow, true)
    H("zones 40"); truthy(M.lastMessage:find("dungeon"))
    H(""); eq(M.openedOptions, "ForeverXP")
    H("reset"); truthy(M.lastMessage:find("reset"))
    H("toggle"); eq(ns.db.enabled, false); H("toggle"); eq(ns.db.enabled, true)
end)
test("Hide in combat hides overlays", function()
    ns.db.hideInCombat = true
    InCombatLockdown = function() return true end
    ns.Panel:Update(); eq(_G.ForeverXPPanel.__shown, false)
    InCombatLockdown = function() return false end
    ns.Panel:Update(); eq(_G.ForeverXPPanel.__shown, true)
    ns.db.hideInCombat = false
end)
test("API shim survives missing functions", function()
    local saved = C_QuestLog
    C_QuestLog = nil; GetQuestLogTitle = nil
    eq(ns.API.NumQuestLogEntries(), 0); eq(ns.API.QuestLogEntry(1), nil); eq(ns.API.MaxQuests(), 25)
    C_QuestLog = saved
    local savedMap = C_Map; C_Map = nil
    eq(ns.API.CurrentMapID(), nil); eq(ns.API.PlayerMapPosition(), nil)
    C_Map = savedMap
end)


-------------------------------------------------------------------------------
print("Route planner")
test("Plan: nearest-neighbour + 2-opt yields a sensible order and legs", function()
    local stops = {
        { name = "far", x = 0.9, y = 0.9 }, { name = "near", x = 0.52, y = 0.5 },
        { name = "mid", x = 0.7, y = 0.7 }, { name = "mid2", x = 0.6, y = 0.6 },
    }
    local order, total = ns.Route.Plan(stops, { x = 0.5, y = 0.5 }, 1000, 1000)
    eq(#order, 4); eq(order[1].name, "near"); eq(order[2].name, "mid2"); eq(order[3].name, "mid"); eq(order[4].name, "far")
    near(order[1].leg, 20, 0.01); truthy(total > 500 and total < 600, "total " .. total)
    eq(order[4].cum, total)
end)
test("Plan: 2-opt fixes a greedy crossing", function()
    -- greedy from (0,0) goes A(0.1,0) then C(0.9,0) before B(0.5,0.4)... 2-opt should order A,B,C or A,C,B whichever is shorter
    local stops = { { name = "C", x = 0.9, y = 0.0 }, { name = "A", x = 0.1, y = 0.0 }, { name = "B", x = 0.5, y = 0.05 } }
    local order, total = ns.Route.Plan(stops, { x = 0, y = 0 }, 1000, 1000)
    eq(order[1].name, "A"); eq(order[2].name, "B"); eq(order[3].name, "C")
    truthy(total < 950, "total " .. total)
end)
test("Plan: empty and single", function()
    local o, t = ns.Route.Plan({}, { x = 0, y = 0 }, 1, 1); eq(#o, 0); eq(t, 0)
    o, t = ns.Route.Plan({ { x = 0.5, y = 0.5 } }, { x = 0.5, y = 0.4 }, 1000, 1000); eq(#o, 1); near(t, 100, 0.01)
end)
test("Plan: weight pulls turn-ins earlier", function()
    local stops = { { name = "obj", x = 0.60, y = 0.5 }, { name = "turnin", x = 0.61, y = 0.5, weight = 0.85 } }
    local order = ns.Route.Plan(stops, { x = 0.5, y = 0.5 }, 1000, 1000)
    eq(order[1].name, "turnin")
end)
test("Summary", function()
    eq(ns.Route.Summary({ { kind = "pickup" }, { kind = "objective" }, { kind = "objective" }, { kind = "turnin" } }, 2400), "Route: 1 pickup, 2 objectives, 1 turn-in, ~2.4k yd")
    eq(ns.Route.Summary({}, 0), nil)
end)

-------------------------------------------------------------------------------
print("Questie bridge")
test("Without Questie everything is empty", function()
    M.DisableQuestie()
    eq(ns.QuestieBridge.IsAvailable(), false)
    eq(#ns.QuestieBridge.Pickups(47, 0.5, 0.5, {}), 0)
    eq(ns.QuestieBridge.TurnInLocation(1, 47), nil)
end)
local function questieData()
    return {
        available = { [201] = true, [202] = true, [203] = true, [204] = true, [205] = true },
        quests = {
            [201] = { name = "Near Giver",  level = 23, requiredLevel = 20, Starts = { NPC = { 5001 } }, Finisher = { NPC = { 5001 } } },
            [202] = { name = "Far Giver",   level = 24, requiredLevel = 22, Starts = { NPC = { 5002 } }, Finisher = { NPC = { 5002 } } },
            [203] = { name = "Too High",    level = 29, requiredLevel = 27, Starts = { NPC = { 5001 } } },
            [204] = { name = "Gray One",    level = 10, requiredLevel = 5,  Starts = { NPC = { 5001 } } },
            [205] = { name = "Other Zone",  level = 23, requiredLevel = 20, Starts = { NPC = { 5003 } } },
            [102] = { name = "Wolves at Our Heels", level = 22, requiredLevel = 20, Starts = { NPC = { 5002 } }, Finisher = { NPC = { 5002 } } },
        },
        npcs = {
            [5001] = { name = "Innkeeper", spawns = { [10] = { { 52, 50 } } } },
            [5002] = { name = "Watcher",   spawns = { [10] = { { 70, 70 }, { 20, 20 } } } },
            [5003] = { name = "Elsewhere", spawns = { [11] = { { 50, 50 } } } },
        },
        areaToMap = { [10] = 47, [11] = 48 },
    }
end
test("Pickups: filters by level, map, log and sorts by distance", function()
    M.EnableQuestie(questieData())
    truthy(ns.QuestieBridge.IsAvailable())
    local list = ns.QuestieBridge.Pickups(47, 0.5, 0.5, { level = 23, slack = 2, exclude = { [202] = false }, force = true })
    eq(#list, 2); eq(list[1].questID, 201); eq(list[1].giver, "Innkeeper"); near(list[1].x, 0.52); eq(list[2].questID, 202)
    near(list[2].x, 0.70, 1e-9, "nearest of two spawns")
    local capped = ns.QuestieBridge.Pickups(47, 0.5, 0.5, { level = 23, slack = 2, maxCount = 1, force = true })
    eq(#capped, 1)
    local excl = ns.QuestieBridge.Pickups(47, 0.5, 0.5, { level = 23, slack = 2, exclude = { [201] = true }, force = true })
    eq(#excl, 1); eq(excl[1].questID, 202)
end)
test("TurnInLocation from Questie finisher", function()
    local x, y, who = ns.QuestieBridge.TurnInLocation(102, 47, 0.5, 0.5)
    near(x, 0.70); near(y, 0.70); eq(who, "Watcher")
end)
test("Bridge survives a broken Questie", function()
    QuestieLoader = { ImportModule = function() error("boom") end }
    eq(ns.QuestieBridge.IsAvailable(), false)
    eq(#ns.QuestieBridge.Pickups(47, 0.5, 0.5, { force = true }), 0)
    M.DisableQuestie()
end)

-------------------------------------------------------------------------------
print("Route integration")
test("Route built from quest log + Questie pickups; arrow follows it", function()
    M.EnableQuestie(questieData())
    p.pos = { x = 0.5, y = 0.5 }
    p.quests = {
        { questID = 0, title = "Duskwood", isHeader = true },
        { questID = 101, title = "The Legend of Stalvan", level = 24, xp = 1400, inZone = true, complete = false, objectives = {}, wp = { x = 0.6, y = 0.4 } },
        { questID = 102, title = "Wolves at Our Heels", level = 22, xp = 1100, inZone = true, complete = true, objectives = {} }, -- no client waypoint: Questie finisher
        { questID = 103, title = "Seasoned Wolf Kabobs", level = 20, xp = 900, inZone = true, complete = false, objectives = {}, wp = { x = 0.3, y = 0.3 } },
    }
    ns.Route.skipped = {}
    ns.Quests:Scan()
    ns.Route:Rebuild()
    local steps = ns.Route.steps
    eq(#steps, 5, "2 pickups + 2 objectives + 1 turn-in")
    eq(steps[1].kind, "pickup"); eq(steps[1].questID, 201)
    local turnin = has(steps, function(s) return s.kind == "turnin" end)
    truthy(turnin); eq(turnin.questID, 102); eq(turnin.who, "Watcher")
    truthy(ns.Route.totalYards > 0)
    ns.Arrow:Clear()
    ns.Arrow:AutoTarget()
    truthy(ns.Arrow.target.label:find("^Pick up: Near Giver"))
    ns.Advisor:Refresh()
    local s = ns.Advisor.suggestions
    local pick = has(s, function(x) return x.kind == "pickup" end)
    truthy(pick); truthy(pick.title:find("Pick up 2 quests on your route")); eq(pick.action.questID, 201)
    local keep = has(s, function(x) return x.kind == "quest" end)
    truthy(keep and keep.detail:find("Route: 2 pickups, 2 objectives, 1 turn%-in"), keep and keep.detail)
    ns.QuestList:Update()
    truthy(_G.ForeverXPQuestList.__shown)
end)
test("Skipping a stop advances the route", function()
    local first = ns.Route:Next()
    ns.HandleCommand("skip")
    truthy(ns.Route:Next().questID ~= first.questID)
    truthy(M.lastMessage:find("skipped"))
end)
test("Arrival at a pickup suppresses it", function()
    ns.Route.skipped = {}
    ns.Route:Rebuild()
    p.pos = { x = 0.52, y = 0.5 } -- standing on the Innkeeper
    ns.Route:CheckArrival()
    truthy(ns.Route:Next().questID ~= 201)
    p.pos = { x = 0.5, y = 0.5 }
    ns.Route.skipped = {}
end)
test("Accepting a pickup removes it from the route", function()
    table.insert(p.quests, { questID = 201, title = "Near Giver", level = 23, xp = 1200, inZone = true, complete = false, objectives = {}, wp = { x = 0.55, y = 0.55 } })
    ns.Quests:Scan(); ns.QuestieBridge.Invalidate(); ns.Route:Rebuild()
    local pick = has(ns.Route.steps, function(s) return s.kind == "pickup" and s.questID == 201 end)
    eq(pick, nil)
    truthy(has(ns.Route.steps, function(s) return s.kind == "objective" and s.questID == 201 end))
    table.remove(p.quests)
end)
test("/fxp route and /fxp questie commands", function()
    ns.HandleCommand("route"); truthy(M.lastMessage:find("yd%)"))
    ns.HandleCommand("questie"); truthy(M.lastMessage:find("Questie") and M.lastMessage:find("pickup"))
    ns.HandleCommand("route off"); eq(ns.db.routeMode, false); eq(#ns.Route.steps, 0)
    ns.Arrow:AutoTarget(); truthy(ns.Arrow.target and not ns.Arrow.target.label:find("Pick up"), "falls back to priority quest")
    ns.HandleCommand("route on"); eq(ns.db.routeMode, true); truthy(#ns.Route.steps > 0)
    M.DisableQuestie()
    ns.HandleCommand("questie"); truthy(M.lastMessage:find("not detected"))
end)
test("No Questie: route still orders log quests", function()
    ns.QuestieBridge.Invalidate(); ns.Quests:Scan(); ns.Route:Rebuild()
    local steps = ns.Route.steps
    eq(#steps, 2, "two objectives with client waypoints; the turn-in has no location without Questie")
    truthy(not has(steps, function(s) return s.kind == "pickup" end))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
