-- ForeverXP: slash commands

local _, ns = ...
local API = ns.API

local function printStatus()
    local ctx = ns.Advisor.ctx or ns.Advisor:Context()
    ns.Print("Level %d (%d/%d XP, rested %s) · %s %s", ctx.level, ctx.xp, ctx.xpMax, ns.FormatNumber(ctx.rested or 0), ctx.faction, ctx.class)
    ns.Print("Zone: %s%s · map %s · activity: %s", ctx.zone and ctx.zone.name or (ctx.zoneNames[2] or ctx.zoneNames[1] or "?"),
        ctx.zone and string.format(" (%d-%d)", ctx.zoneLo, ctx.zoneHi) or " (not in route data)", tostring(ctx.mapID), ctx.activity)
    ns.Print("XP/h: %s (kills %s, quests %s) · to level: %s", ns.FormatNumber(ctx.xpPerHour), ns.FormatNumber(ctx.killPerHour), ns.FormatNumber(ctx.questPerHour), ns.FormatDuration(ctx.timeToLevel))
    ns.Print(ns.Gear.Describe(ctx.gear))
    local qs = ctx.quests
    ns.Print("Quests: %d total, %d ready to turn in (~%s XP), %d active here, %d gray", qs.total, #qs.ready, ns.FormatNumber(qs.xpReady), #qs.inZone, #qs.gray)
    for i, s in ipairs(ns.Advisor.suggestions) do
        ns.Print("%d. [%d] %s", i, math.floor(s.score), s.title)
    end
    local v, b = API.GetBuild()
    ns.Print("Client %s (%s) · Forever: %s · project %s", tostring(v), tostring(b), tostring(API.IsForever()), tostring(WOW_PROJECT_ID))
end

local function help()
    ns.Print("commands:")
    ns.Print("  /fxp               open options")
    ns.Print("  /fxp toggle        enable / disable")
    ns.Print("  /fxp panel|arrow|quests   toggle an overlay")
    ns.Print("  /fxp lock          lock / unlock overlay positions")
    ns.Print("  /fxp scale 1.2     overlay scale (0.6-1.6)")
    ns.Print("  /fxp alpha 0.8     overlay opacity (0.3-1)")
    ns.Print("  /fxp reset         reset overlay positions")
    ns.Print("  /fxp status        print what the advisor sees")
    ns.Print("  /fxp refresh       rescan quests, gear and zone now")
    ns.Print("  /fxp zone 35 45    set the level range of the zone you are in")
    ns.Print("  /fxp learn <zone>  bind the current map to a route zone")
    ns.Print("  /fxp zones         list route zones for your level")
end

local function handle(msg)
    msg = ns.TrimLower(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    local db = ns.db
    if cmd == "" or cmd == "options" or cmd == "config" then
        ns.Options:Open()
    elseif cmd == "help" or cmd == "?" then
        help()
    elseif cmd == "toggle" or cmd == "enable" or cmd == "disable" then
        if cmd == "toggle" then db.enabled = not db.enabled else db.enabled = (cmd == "enable") end
        ns.Print("%s", db.enabled and "enabled" or "disabled")
        ns.Fire("SETTINGS_CHANGED")
        if db.enabled then ns.Advisor:Refresh() end
    elseif cmd == "panel" or cmd == "show" or cmd == "hide" then
        if cmd == "panel" then db.showPanel = not db.showPanel else db.showPanel = (cmd == "show") end
        ns.Fire("SETTINGS_CHANGED")
    elseif cmd == "arrow" then
        db.showArrow = not db.showArrow
        ns.Print("arrow %s", db.showArrow and "on" or "off")
        ns.Fire("SETTINGS_CHANGED")
    elseif cmd == "quests" or cmd == "list" then
        db.showQuestList = not db.showQuestList
        ns.Print("quest list %s", db.showQuestList and "on" or "off")
        ns.Fire("SETTINGS_CHANGED")
    elseif cmd == "lock" or cmd == "unlock" then
        if cmd == "lock" then db.locked = not db.locked else db.locked = false end
        ns.Print("overlays %s", db.locked and "locked" or "unlocked (drag to move)")
    elseif cmd == "scale" then
        local v = tonumber(rest)
        if v then db.scale = ns.Clamp(v, 0.6, 1.6); ns.Fire("SETTINGS_CHANGED") else ns.Print("scale is %.2f", db.scale) end
    elseif cmd == "alpha" then
        local v = tonumber(rest)
        if v then db.alpha = ns.Clamp(v, 0.3, 1); ns.Fire("SETTINGS_CHANGED") else ns.Print("alpha is %.2f", db.alpha) end
    elseif cmd == "reset" then
        db.positions = {}
        for _, name in ipairs({ "ForeverXPPanel", "ForeverXPArrow", "ForeverXPQuestList" }) do
            local f = _G[name]
            if f then
                ns.RestorePosition(f, name == "ForeverXPPanel" and "TOPRIGHT" or (name == "ForeverXPArrow" and "TOP" or "RIGHT"),
                    name == "ForeverXPPanel" and -220 or (name == "ForeverXPArrow" and 0 or -20),
                    name == "ForeverXPPanel" and -120 or (name == "ForeverXPArrow" and -200 or 0))
            end
        end
        ns.Print("positions reset")
    elseif cmd == "status" then
        printStatus()
    elseif cmd == "refresh" then
        ns.Gear:Scan(); ns.Quests:Scan(); ns.Advisor:Refresh()
        ns.Print("refreshed")
    elseif cmd == "zone" then
        local lo, hi = rest:match("^(%d+)%s+(%d+)$")
        local ctx = ns.Advisor.ctx or ns.Advisor:Context()
        if not ctx.zone then ns.Print("You are not in a route zone. Use /fxp learn <zone> first."); return end
        if not lo then ns.Print("%s range is %d-%d. Usage: /fxp zone <min> <max>", ctx.zone.name, ctx.zoneLo, ctx.zoneHi); return end
        db.zoneRanges = db.zoneRanges or {}
        db.zoneRanges[ctx.zone.key] = { min = tonumber(lo), max = tonumber(hi) }
        ns.Print("%s range set to %s-%s", ctx.zone.name, lo, hi)
        ns.Advisor:Refresh()
    elseif cmd == "learn" then
        local mapID = API.CurrentMapID()
        if not mapID then ns.Print("No map ID available here."); return end
        local z = ns.ZONE_BY_KEY[ns.ZoneKey(rest)]
        if not z then
            ns.Print("Unknown zone '%s'. Names: %s", rest, "Zephras Isle, Riverglades, Shen'dralas, Mount Hyjal, or any classic zone")
            return
        end
        db.mapOverrides[z.key] = mapID
        ns.Print("Map %d is now %s (%d-%d)", mapID, z.name, z.min, z.max)
        ns.Advisor:Refresh()
    elseif cmd == "zones" then
        local level = tonumber(rest) or API.PlayerLevel()
        ns.Print("route zones for level %d (%s):", level, API.PlayerFaction())
        for i, c in ipairs(ns.ZonesForLevel(level, API.PlayerFaction())) do
            if i > 6 then break end
            ns.Print("  %s %d-%d%s · hub %s", c.zone.name, c.min, c.max, c.zone.confidence == "estimate" and " (est.)" or "", c.zone.hub or "?")
        end
        for i, c in ipairs(ns.DungeonsForLevel(level, API.PlayerFaction())) do
            if i > 3 then break end
            ns.Print("  dungeon: %s %d-%d · quests at %s", c.dungeon.name, c.dungeon.min, c.dungeon.max, c.dungeon.questHub or "?")
        end
    elseif cmd == "debug" then
        db.debug = not db.debug
        ns.Print("debug %s", db.debug and "on" or "off")
    else
        help()
    end
end

SLASH_FOREVERXP1 = "/fxp"
SLASH_FOREVERXP2 = "/foreverxp"
SlashCmdList["FOREVERXP"] = handle
ns.HandleCommand = handle
