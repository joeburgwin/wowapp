-- ForeverXP: Advisor
-- Turns everything the other modules know (level, zone, gear, quests,
-- rested XP, activity, XP/hour) into a short ranked list of suggestions.
--
-- Advisor.Build(ctx) is pure: it takes a context table and returns
-- suggestions, so it is unit tested without the game client.

local _, ns = ...
local API = ns.API
local A = ns.NewModule("Advisor")
ns.Advisor = A

A.suggestions = {}
A.ctx = nil

local function pct(part, whole)
    if not whole or whole <= 0 then return 0 end
    return part / whole * 100
end

local function zoneLabel(z, lo, hi)
    local s = string.format("%s (%d-%d)", z.name, lo or z.min, hi or z.max)
    if z.confidence == "estimate" then s = s .. "*" end
    return s
end

local function questNames(list, max)
    local names = {}
    for i = 1, math.min(max or 3, #list) do table.insert(names, list[i].title or "?") end
    local s = table.concat(names, ", ")
    if #list > (max or 3) then s = s .. string.format(" +%d more", #list - (max or 3)) end
    return s
end

local function questAction(q)
    if not q then return nil end
    local a = { questID = q.questID }
    if q.wp then a.mapID, a.x, a.y = q.wp.mapID, q.wp.x, q.wp.y end
    return a
end

-- Expected questing XP/hour at a level: a steady 6 quests/hour of level-appropriate quests.
function A.ExpectedQuestRate(level)
    return ns.Quests.EstimateXP(level, level) * 6
end

-------------------------------------------------------------------------------
-- Pure suggestion builder
-------------------------------------------------------------------------------
-- ctx fields (all optional except level):
--   level, maxLevel, xp, xpMax, rested, faction,
--   zone (zone record), zoneLo, zoneHi, zoneNames, inCity, inInstance, instanceType, dungeon,
--   groupSize, activity, xpPerHour, killPerHour, questPerHour,
--   gear (Gear.Score result), quests (Quests:Summary result), priorityQuest
function A.Build(ctx)
    local out = {}
    local function add(s) table.insert(out, s) end
    local level = ctx.level or 1
    local maxLevel = ctx.maxLevel or 60
    local qs = ctx.quests or { total = 0, ready = {}, inZone = {}, inZoneReady = {}, gray = {}, xpReady = 0, xpInZone = 0, active = {}, max = 25, full = false }
    local gear = ctx.gear
    local xpMax = ctx.xpMax or 1
    local faction = ctx.faction or "Alliance"

    if level >= maxLevel then
        add({ kind = "max", score = 100, icon = "★",
            title = "Max level reached",
            detail = "XP routing is done. Chase Legacy progression, dungeon loot and attunements." })
        return out
    end

    --------------------------------------------------------------- Turn-ins
    if #qs.ready > 0 then
        local score = 65 + math.min(30, pct(qs.xpReady, xpMax))
        local pool = (#qs.inZoneReady > 0) and qs.inZoneReady or qs.ready
        table.sort(pool, function(a, b)
            local da, db = a.distSq or math.huge, b.distSq or math.huge
            if da ~= db then return da < db end
            return (a.xp or 0) > (b.xp or 0)
        end)
        -- a turn-in within ~300 yards is nearly free XP
        if pool[1].distSq and pool[1].distSq < 300 * 300 then score = score + 8 end
        local detail = string.format("~%s XP waiting (%.0f%% of a level). %s",
            ns.FormatNumber(qs.xpReady), pct(qs.xpReady, xpMax), questNames(pool))
        if qs.full then
            score = score + 10
            detail = detail .. " Your quest log is nearly full."
        end
        add({ kind = "turnin", score = score, icon = "✔",
            title = string.format("Turn in %d completed quest%s", #qs.ready, #qs.ready == 1 and "" or "s"),
            detail = detail, action = questAction(pool[1]) })
    end

    --------------------------------------------------------------- Zone fit
    local zone = ctx.zone
    local lo, hi = ctx.zoneLo, ctx.zoneHi
    local zoneState = "unknown"
    if zone then
        lo, hi = lo or zone.min, hi or zone.max
        if level > hi then zoneState = "outleveled"
        elseif level < lo - 1 then zoneState = "toohigh"
        else zoneState = "ok" end
    end
    if ctx.inCity then zoneState = "city" end
    if ctx.inInstance then zoneState = "instance" end

    local route = ctx.route or {}
    local routeSummary = ns.Route and ns.Route.Summary(route, ctx.routeYards) or nil
    local pickups = ctx.pickups or {}

    local nextZones = ns.ZonesForLevel(level, faction)
    local function bestOtherZone()
        for _, c in ipairs(nextZones) do
            if not zone or c.zone.key ~= zone.key then return c end
        end
        return nextZones[1]
    end

    if zoneState == "outleveled" then
        local c = bestOtherZone()
        if c then
            add({ kind = "move", score = 70, icon = "➜",
                title = "Move on to " .. zoneLabel(c.zone, c.min, c.max),
                detail = string.format("%s is %d-%d; your quests here are going gray. %sQuest hub: %s.",
                    zone.name, lo, hi, c.zone.travel and (c.zone.travel .. " ") or "", c.zone.hub or "?"),
                zone = c.zone })
        end
    elseif zoneState == "toohigh" then
        local c = bestOtherZone()
        if c then
            add({ kind = "move", score = 65, icon = "⚠",
                title = zone.name .. " is above your level",
                detail = string.format("It is tuned for %d-%d. Try %s instead (hub: %s).", lo, hi,
                    zoneLabel(c.zone, c.min, c.max), c.zone.hub or "?"),
                zone = c.zone })
        end
    elseif zoneState == "ok" then
        local inZone = #qs.inZone
        if inZone >= 2 then
            local score = 45 + math.min(25, pct(qs.xpInZone, xpMax))
            local pq = ctx.priorityQuest
            if pq and pq.complete then pq = nil end
            local nextStep = route[1]
            local detail = string.format("%d active quest%s here worth ~%s XP (%.0f%% of a level). ",
                inZone, inZone == 1 and "" or "s", ns.FormatNumber(qs.xpInZone), pct(qs.xpInZone, xpMax))
            if routeSummary then
                detail = detail .. routeSummary .. ". Next stop: " .. (nextStep.title or "?") .. "."
            else
                detail = detail .. "Next: " .. (pq and pq.title or questNames(qs.inZone, 2)) .. "."
            end
            add({ kind = "quest", score = score, icon = "●",
                title = string.format("Keep questing in %s", zone.name),
                detail = detail,
                action = nextStep and { questID = nextStep.questID, mapID = nextStep.mapID, x = nextStep.x, y = nextStep.y } or questAction(pq or qs.inZone[1]) })
        elseif not qs.full and #pickups == 0 then
            add({ kind = "pickup", score = 55, icon = "?",
                title = string.format("Pick up quests at %s", zone.hub or zone.name),
                detail = string.format("You only have %d quest%s for %s (%d-%d). Fill your log before you grind.%s",
                    inZone, inZone == 1 and "" or "s", zone.name, lo, hi,
                    ctx.questie and "" or " Install Questie and the route will show exactly which quest givers to visit.") })
        end
        -- heading toward the end of the zone's range: queue up the next one
        local span = math.max(hi - lo, 1)
        if (level - lo) / span >= 0.8 and #qs.inZone <= 3 then
            local c = bestOtherZone()
            if c then
                add({ kind = "move", score = 38, icon = "➜",
                    title = "Next zone: " .. zoneLabel(c.zone, c.min, c.max),
                    detail = string.format("You are near the top of %s's range. Hub: %s.", zone.name, c.zone.hub or "?"),
                    zone = c.zone })
            end
        end
    elseif zoneState == "unknown" and not ctx.inInstance then
        local c = nextZones[1]
        if c then
            add({ kind = "move", score = 45, icon = "➜",
                title = "Head to " .. zoneLabel(c.zone, c.min, c.max),
                detail = string.format("No route data for where you are. %s is the best-fit zone for level %d (hub: %s).",
                    c.zone.name, level, c.zone.hub or "?"),
                zone = c.zone })
        end
    elseif zoneState == "city" then
        local c = nextZones[1]
        if c and #qs.ready == 0 then
            add({ kind = "move", score = 40, icon = "➜",
                title = "Back out to " .. zoneLabel(c.zone, c.min, c.max),
                detail = string.format("Cities give no XP. Hub: %s.", c.zone.hub or "?"), zone = c.zone })
        end
    end

    --------------------------------------------------------------- Questie pickups
    if #pickups > 0 and not ctx.inInstance and not qs.full then
        local p = pickups[1]
        local xp = 0
        for _, s in ipairs(pickups) do xp = xp + (s.xp or 0) end
        local score = 50 + math.min(20, pct(xp, xpMax))
        if #qs.inZone < 3 then score = score + 8 end
        add({ kind = "pickup", score = score, icon = "?",
            title = string.format("Pick up %d quest%s on your route (~%s XP)", #pickups, #pickups == 1 and "" or "s", ns.FormatNumber(xp)),
            detail = string.format("Nearest: %s%s. The route folds them in with your objectives and turn-ins.",
                p.title or "?", p.who and (" from " .. p.who) or ""),
            action = { questID = p.questID, mapID = p.mapID, x = p.x, y = p.y } })
    end

    --------------------------------------------------------------- Dungeons
    local dungeons = ns.DungeonsForLevel(level, faction)
    local group = ctx.groupSize or 0
    if ctx.inInstance and (ctx.instanceType == "party") then
        local d = ctx.dungeon
        add({ kind = "dungeon", score = 60, icon = "⚔",
            title = d and ("Finish the quests in " .. d.name) or "Finish the dungeon quests",
            detail = "In Forever, trash XP is reduced but dungeon quest XP and rewards are increased. Complete every quest objective before leaving." })
    elseif #dungeons > 0 then
        local d = dungeons[1].dungeon
        if group >= 3 then
            add({ kind = "dungeon", score = 66, icon = "⚔",
                title = string.format("Run %s with your group (%d-%d)", d.name, d.min, d.max),
                detail = string.format("Grab its quests first (%s): Forever boosted dungeon quest XP and loot.", d.questHub or "?") })
        elseif ctx.activity == "grinding" or (gear and (gear.rating == "poor" or gear.rating == "weak")) then
            add({ kind = "dungeon", score = 36, icon = "⚔",
                title = string.format("Dungeon option: %s (%d-%d)", d.name, d.min, d.max),
                detail = string.format("Find a group and collect its quests at %s first; quest XP and gear there outpace grinding.", d.questHub or "?") })
        end
    end

    --------------------------------------------------------------- Gear
    if gear and (gear.rating == "poor" or gear.rating == "weak") then
        local score = gear.rating == "poor" and 58 or 44
        local bits = {}
        if gear.weaponOutdated then
            table.insert(bits, gear.weaponIlvl and string.format("your weapon (ilvl %d) is outdated", math.floor(gear.weaponIlvl)) or "you have no weapon equipped")
        end
        if #gear.empties > 0 then table.insert(bits, "empty: " .. table.concat(gear.empties, ", ")) end
        if #gear.weakSlots > 0 and #bits < 2 then table.insert(bits, "low: " .. table.concat(gear.weakSlots, ", ")) end
        local fix
        if #dungeons > 0 then
            fix = string.format("Quest rewards here and %s loot will fix it fast.", dungeons[1].dungeon.name)
        else
            fix = "Prioritise quests with gear rewards."
        end
        if zone and zoneState == "ok" then
            local span = math.max(hi - lo, 1)
            if (level - lo) / span > 0.6 and gear.rating == "poor" then
                fix = fix .. " Stay in the lower half of your zone range until it improves."
            end
        end
        add({ kind = "gear", score = score, icon = "⛨",
            title = string.format("Gear is %s (avg ilvl %.0f, ~%d expected)", gear.rating, gear.avg, gear.expected),
            detail = (#bits > 0 and (table.concat(bits, "; ") .. ". ") or "") .. fix })
    end

    --------------------------------------------------------------- Activity / rested
    local rested = ctx.rested or 0
    local restedPct = pct(rested, xpMax)
    local expectedRate = A.ExpectedQuestRate(level)
    local rate = ctx.xpPerHour or 0

    if ctx.activity == "grinding" then
        if rested <= 0 then
            add({ kind = "activity", score = 57, icon = "↻",
                title = "Grinding without rested XP is slow",
                detail = string.format("You are making ~%s XP/h; level-appropriate questing is worth ~%s XP/h. Switch to quests%s.",
                    ns.FormatNumber(rate), ns.FormatNumber(expectedRate),
                    #qs.inZone > 0 and string.format(" (%d in this zone)", #qs.inZone) or "") })
        elseif #qs.inZone > 0 then
            add({ kind = "activity", score = 48, icon = "↻",
                title = "Grind on quest mobs instead",
                detail = string.format("Rested XP (%.0f%% of a level) doubles kill XP, so pair it with the %d quest%s you hold here.",
                    restedPct, #qs.inZone, #qs.inZone == 1 and "" or "s"),
                action = questAction(ctx.priorityQuest) })
        end
    elseif rested > 0 and ctx.activity ~= "dungeon" then
        add({ kind = "rested", score = 30 + math.min(10, restedPct / 10), icon = "☾",
            title = string.format("Rested: %.0f%% of a level banked", restedPct),
            detail = "Rested XP doubles mob-kill XP (not quest XP). Kill-heavy quests and dungeon runs are extra valuable right now." })
    elseif rested <= 0 and ctx.activity == "questing" and rate > 0 and rate < expectedRate * 0.5 and ctx.sessionSeconds and ctx.sessionSeconds > 900 then
        add({ kind = "activity", score = 35, icon = "↻",
            title = "XP rate is low for your level",
            detail = string.format("~%s XP/h vs ~%s expected. Chain quests in one area and turn in in batches.",
                ns.FormatNumber(rate), ns.FormatNumber(expectedRate)) })
    end

    --------------------------------------------------------------- Gray quests
    if #qs.gray > 0 then
        add({ kind = "gray", score = 24, icon = "○",
            title = string.format("%d gray quest%s in your log", #qs.gray, #qs.gray == 1 and "" or "s"),
            detail = "Gray quests give 10% XP. Turn them in if you are passing by, otherwise abandon to free slots: " .. questNames(qs.gray, 2) })
    end

    --------------------------------------------------------------- Traveling
    if ctx.activity == "traveling" and ctx.priorityQuest and ctx.priorityQuest.wp then
        add({ kind = "travel", score = 33, icon = "➜",
            title = "Heading somewhere? Track " .. (ctx.priorityQuest.title or "your best quest"),
            detail = "Click to set a waypoint and the arrow will guide you.", action = questAction(ctx.priorityQuest) })
    end

    table.sort(out, function(a, b) return a.score > b.score end)
    return out
end

-------------------------------------------------------------------------------
-- Context gathering from live modules
-------------------------------------------------------------------------------
function A:Context()
    local names = API.ZoneNames()
    local mapID = API.CurrentMapID()
    local zone = ns.FindZone(names, mapID)
    -- auto-learn the real map ID of a zone (helps the new Forever zones)
    if zone and mapID and ns.db and ns.db.mapOverrides and ns.db.mapOverrides[zone.key] == nil then
        local info = API.MapInfo(mapID)
        -- only learn zone-level maps (mapType 3) when the API says what the map is
        if not info or info.mapType == nil or info.mapType == 3 then ns.db.mapOverrides[zone.key] = mapID end
    end
    local inInst, instType = API.InInstance()
    local lo, hi
    if zone then lo, hi = ns.ZoneRange(zone) end
    local xpPerHour, killPerHour, questPerHour = ns.Tracker:XPPerHour()
    local ctx = {
        level = API.PlayerLevel(), maxLevel = API.MaxLevel(),
        xp = API.PlayerXP(), xpMax = API.PlayerXPMax(), rested = API.RestedXP(),
        faction = API.PlayerFaction(), class = API.PlayerClass(),
        zone = zone, zoneLo = lo, zoneHi = hi, zoneNames = names, mapID = mapID,
        inCity = ns.IsCity(names), inInstance = inInst, instanceType = instType,
        dungeon = inInst and ns.FindDungeon(names) or nil,
        groupSize = API.GroupSize(), activity = ns.Tracker.activity,
        xpPerHour = xpPerHour, killPerHour = killPerHour, questPerHour = questPerHour,
        sessionSeconds = ns.Now() - (ns.Tracker.sessionStart or ns.Now()),
        gear = ns.Gear:Get(), quests = ns.Quests:Summary(), priorityQuest = ns.Quests:Priority(),
        timeToLevel = ns.Tracker:TimeToLevel(),
        route = ns.Route and ns.Route.steps or {}, routeYards = ns.Route and ns.Route.totalYards or 0,
        questie = ns.QuestieBridge and ns.QuestieBridge.IsAvailable() or false,
    }
    ctx.pickups = {}
    for _, s in ipairs(ctx.route) do if s.kind == "pickup" then table.insert(ctx.pickups, s) end end
    return ctx
end

function A:Refresh()
    if not ns.db or not ns.db.enabled then return end
    local ok, ctx = pcall(self.Context, self)
    if not ok then ns.Debug("context error: %s", tostring(ctx)); return end
    local ok2, list = pcall(A.Build, ctx)
    if not ok2 then ns.Debug("build error: %s", tostring(list)); return end
    local changed = (not self.suggestions[1] and list[1]) or (self.suggestions[1] and list[1] and self.suggestions[1].title ~= list[1].title)
    self.ctx, self.suggestions = ctx, list
    ns.Fire("SUGGESTIONS", list, ctx, changed)
end

function A:OnLogin()
    local refresh = ns.Debounce(1, function() A:Refresh() end)
    for _, msg in ipairs({ "QUESTS_SCANNED", "ROUTE_CHANGED", "ZONE_CHANGED", "LEVEL_UP", "GEAR_SCORED", "ACTIVITY_CHANGED", "GROUP_CHANGED", "RESTED_CHANGED", "XP_CHANGED" }) do
        ns.Listen(msg, refresh)
    end
    ns.Ticker(20, function() A:Refresh() end)
    ns.After(6, function() A:Refresh() end)
end
