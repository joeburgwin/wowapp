-- ForeverXP: Route planner
-- Orders every stop that matters in the current zone (quest pickups from
-- Questie, objectives, turn-ins) into one efficient path from where you stand,
-- then walks you through it: the arrow follows the next stop and the quest
-- list shows the numbered steps.
--
-- Route.Plan is pure (nearest-neighbour + 2-opt) so it is unit tested.

local _, ns = ...
local API = ns.API
local R = ns.NewModule("Route")
ns.Route = R

R.steps = {}
R.totalYards = 0
R.skipped = {}        -- stepKey -> time skipped/arrived (suppressed for a while)
local SKIP_SECONDS = 180
local ARRIVE_YARDS = 15

local function stepKey(s) return s.kind .. ":" .. tostring(s.questID) end
R.StepKey = stepKey

-------------------------------------------------------------------------------
-- Pure planner
-------------------------------------------------------------------------------
-- stops: list of { x, y, ... } in map units; start: { x, y }; w, h: yards per map unit.
-- Returns ordered copy of stops with .leg (yards from previous) and .cum, plus total yards.
function R.Plan(stops, start, w, h)
    w, h = w or 1, h or 1
    local n = #stops
    if n == 0 then return {}, 0 end
    local function dist(a, b)
        local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
        return math.sqrt(dx * dx + dy * dy)
    end
    -- nearest neighbour
    local remaining, order = {}, {}
    for i = 1, n do remaining[i] = stops[i] end
    local cur = start
    while #remaining > 0 do
        local bi, bd
        for i, s in ipairs(remaining) do
            local d = dist(cur, s) * (s.weight or 1)
            if not bd or d < bd then bi, bd = i, d end
        end
        cur = table.remove(remaining, bi)
        table.insert(order, cur)
    end
    -- 2-opt improvement on an open path from start
    if n >= 3 and n <= 25 then
        local improved = true
        local function pathLen()
            local t, prev = 0, start
            for _, s in ipairs(order) do t = t + dist(prev, s); prev = s end
            return t
        end
        local best = pathLen()
        local guard = 0
        while improved and guard < 50 do
            improved = false
            guard = guard + 1
            for i = 1, n - 1 do
                for j = i + 1, n do
                    -- reverse segment i..j
                    local a, b = i, j
                    while a < b do order[a], order[b] = order[b], order[a]; a = a + 1; b = b - 1 end
                    local len = pathLen()
                    if len < best - 0.5 then best = len; improved = true
                    else
                        a, b = i, j
                        while a < b do order[a], order[b] = order[b], order[a]; a = a + 1; b = b - 1 end
                    end
                end
            end
        end
    end
    local out, prev, cum = {}, start, 0
    for i, s in ipairs(order) do
        local copy = {}
        for k, v in pairs(s) do copy[k] = v end
        copy.leg = dist(prev, s)
        cum = cum + copy.leg
        copy.cum = cum
        copy.index = i
        out[i] = copy
        prev = s
    end
    return out, cum
end

-------------------------------------------------------------------------------
-- Live route
-------------------------------------------------------------------------------
function R:Stops(mapID, px, py)
    local stops = {}
    local db = ns.db
    local now = ns.Now()
    local function active(key) return not R.skipped[key] or now - R.skipped[key] > SKIP_SECONDS end

    for _, q in ipairs(ns.Quests.list or {}) do
        if q.inZone and not q.failed then
            local wp = q.wp
            if q.complete and not wp and ns.QuestieBridge then
                local x, y, name = ns.QuestieBridge.TurnInLocation(q.questID, mapID, px, py)
                if x then wp = { mapID = mapID, x = x, y = y, who = name } end
            end
            if wp and wp.mapID == mapID then
                local s = { kind = q.complete and "turnin" or "objective", questID = q.questID, title = q.title,
                    x = wp.x, y = wp.y, mapID = mapID, xp = q.xp, quest = q, who = wp.who }
                -- turn-ins and nearly done objectives are slightly "closer" so they get picked up on the way
                if q.complete then s.weight = 0.85 elseif q.objTotal > 0 and q.objDone > 0 then s.weight = 0.95 end
                if active(stepKey(s)) then table.insert(stops, s) end
            end
        end
    end

    if db.questiePickups ~= false and ns.QuestieBridge and ns.QuestieBridge.IsAvailable() then
        local exclude = {}
        for id in pairs(ns.Quests.byID or {}) do exclude[id] = true end
        local pickups = ns.QuestieBridge.Pickups(mapID, px, py, {
            level = API.PlayerLevel(), slack = db.pickupLevelSlack or 2, maxCount = db.routeMaxPickups or 6, exclude = exclude,
        })
        for _, p in ipairs(pickups) do
            local s = { kind = "pickup", questID = p.questID, title = p.title, x = p.x, y = p.y, mapID = mapID,
                xp = p.xp, who = p.giver, level = p.level, weight = 1.05 }
            if active(stepKey(s)) then table.insert(stops, s) end
        end
    end
    return stops
end

function R:Rebuild()
    if not ns.db or not ns.db.enabled or ns.db.routeMode == false then
        self.steps, self.totalYards = {}, 0
        ns.Fire("ROUTE_CHANGED", self.steps)
        return
    end
    local px, py, mapID = API.PlayerMapPosition()
    if not px then
        self.steps, self.totalYards = {}, 0
        ns.Fire("ROUTE_CHANGED", self.steps)
        return
    end
    local w, h = API.MapWorldSize(mapID)
    local stops = self:Stops(mapID, px, py)
    self.steps, self.totalYards = R.Plan(stops, { x = px, y = py }, w or 1000, h or 1000)
    self.mapID = mapID
    ns.Fire("ROUTE_CHANGED", self.steps)
end

function R:Next() return self.steps[1] end

-- Mark the current step as done/skipped so the route moves on.
function R:Skip(step)
    step = step or self.steps[1]
    if not step then return end
    self.skipped[stepKey(step)] = ns.Now()
    self:Rebuild()
end

function R:CheckArrival()
    local s = self.steps[1]
    if not s then return end
    local px, py, mapID = API.PlayerMapPosition(s.mapID)
    if not px or mapID ~= s.mapID then return end
    local w, h = API.MapWorldSize(mapID)
    if not w then return end
    local d = ns.Arrow.Distance(px, py, s.x, s.y, w, h)
    if d < ARRIVE_YARDS and s.kind == "pickup" then
        -- reached the quest giver: give the player a moment, then stop pointing here
        self.skipped[stepKey(s)] = ns.Now()
        self:Rebuild()
    end
end

function R.Summary(steps, total)
    local n = #steps
    if n == 0 then return nil end
    local pick, obj, turn = 0, 0, 0
    for _, s in ipairs(steps) do
        if s.kind == "pickup" then pick = pick + 1 elseif s.kind == "turnin" then turn = turn + 1 else obj = obj + 1 end
    end
    local bits = {}
    if pick > 0 then table.insert(bits, pick .. " pickup" .. (pick == 1 and "" or "s")) end
    if obj > 0 then table.insert(bits, obj .. " objective" .. (obj == 1 and "" or "s")) end
    if turn > 0 then table.insert(bits, turn .. " turn-in" .. (turn == 1 and "" or "s")) end
    return string.format("Route: %s, ~%s yd", table.concat(bits, ", "), ns.FormatCompact(total or 0))
end

function R:OnLogin()
    local rebuild = ns.Debounce(1, function() R:Rebuild() end)
    ns.Listen("QUESTS_SCANNED", rebuild)
    ns.Listen("ZONE_CHANGED", rebuild)
    ns.Listen("SETTINGS_CHANGED", rebuild)
    ns.Ticker(5, function() R:CheckArrival() end)
    ns.Ticker(45, function() R:Rebuild() end)
end
