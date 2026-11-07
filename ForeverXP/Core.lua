-- ForeverXP: Core
-- Namespace, saved variables, event bus, timers and small utilities.
-- Everything else in the addon hangs off the shared `ns` table.

local ADDON, ns = ...
ForeverXP = ns -- exposed for /dump and other addons
ns.ADDON = ADDON
ns.VERSION = "0.2.0"
ns.PREFIX = "|cff7fd4ffForeverXP|r"

-------------------------------------------------------------------------------
-- Defaults
-------------------------------------------------------------------------------
ns.defaults = {
    enabled = true,
    locked = false,
    scale = 1.0,
    alpha = 0.85,
    showPanel = true,
    showArrow = true,
    showQuestList = true,
    toasts = true,
    maxSuggestions = 3,
    questListRows = 8,
    hideInCombat = false,
    minimized = false,
    -- route planning
    routeMode = true,          -- order zone stops into a path and step the arrow through it
    questiePickups = true,     -- include quests you can pick up (needs Questie)
    pickupLevelSlack = 2,      -- include pickups up to this many levels above you
    routeMaxPickups = 6,       -- most pickups to fold into one route
    -- window length (seconds) used for XP/hour
    xpWindow = 900,
    positions = {}, -- frameName -> {point, x, y}
    -- zoneKey -> uiMapID learned via /fxp learn or automatically
    mapOverrides = {},
}

ns.charDefaults = {
    session = { killXP = 0, questXP = 0, otherXP = 0, started = 0 },
    levelTimes = {}, -- level -> seconds played when reached (best effort)
}

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------
local function copyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.copyDefaults = copyDefaults

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. ": " .. msg)
    else
        print(ns.PREFIX .. ": " .. msg)
    end
end

function ns.Debug(fmt, ...)
    if ns.db and ns.db.debug then ns.Print("|cff888888[debug]|r " .. fmt, ...) end
end

function ns.Round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end

function ns.Clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

function ns.FormatNumber(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    local s = tostring(n)
    -- thousands separator
    local left, num, right = s:match("^([^%d]*%d)(%d*)(.-)$")
    return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

-- "8.2k" style, for the one-line status
function ns.FormatCompact(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

function ns.FormatDuration(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge or seconds < 0 then return "--" end
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 48 then return "2d+" end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm", m) end
    return "<1m"
end

-- Safe call: returns ok, results... without ever raising.
function ns.Safe(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- Returns the result of fn(...) or nil if it errors / doesn't exist.
function ns.Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
    return nil
end

function ns.Now()
    if GetTime then return GetTime() end
    return os.clock()
end

function ns.TrimLower(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

-- normalise zone names for matching ("Shen'dralas", "Shen’dralas" -> "shendralas")
function ns.ZoneKey(name)
    if not name then return nil end
    local s = tostring(name):lower()
    s = s:gsub("[’'`%-%s%.]", "")
    return s
end

-------------------------------------------------------------------------------
-- Event bus
-------------------------------------------------------------------------------
local handlers = {}
local frame = CreateFrame("Frame", "ForeverXPEventFrame")
ns.eventFrame = frame

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            ns.Print("|cffff5555error in %s handler:|r %s", event, tostring(err))
        end
    end
end)

function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then ns.Debug("event %s not available in this client", event) end
    end
    table.insert(handlers[event], fn)
end

function ns.UnregisterEvent(event)
    handlers[event] = nil
    pcall(frame.UnregisterEvent, frame, event)
end

-- In-addon message bus (not WoW events): ns.Fire("XP_CHANGED", ...)
local listeners = {}
function ns.Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.Print("|cffff5555error in %s listener:|r %s", msg, tostring(err)) end
    end
end

-------------------------------------------------------------------------------
-- Timers
-------------------------------------------------------------------------------
function ns.After(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

function ns.Ticker(seconds, fn)
    if C_Timer and C_Timer.NewTicker then
        return C_Timer.NewTicker(seconds, fn)
    end
end

-- Debounce: coalesces bursts of calls into one call `delay` seconds later.
function ns.Debounce(delay, fn)
    local pending = false
    return function(...)
        if pending then return end
        pending = true
        local args = { ... }
        local n = select("#", ...)
        ns.After(delay, function()
            pending = false
            fn(unpack(args, 1, n))
        end)
    end
end

-------------------------------------------------------------------------------
-- Saved variables / lifecycle
-------------------------------------------------------------------------------
ns.modules = {}
function ns.NewModule(name)
    local m = { name = name }
    ns.modules[name] = m
    table.insert(ns.modules, m)
    return m
end

local function InitDB()
    ForeverXPDB = copyDefaults(ForeverXPDB, ns.defaults)
    ForeverXPCharDB = copyDefaults(ForeverXPCharDB, ns.charDefaults)
    ns.db = ForeverXPDB
    ns.cdb = ForeverXPCharDB
end

ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    InitDB()
    for _, m in ipairs(ns.modules) do
        if m.OnInit then
            local ok, err = pcall(m.OnInit, m)
            if not ok then ns.Print("|cffff5555init error in %s:|r %s", m.name, tostring(err)) end
        end
    end
    ns.Fire("INIT")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    for _, m in ipairs(ns.modules) do
        if m.OnLogin then
            local ok, err = pcall(m.OnLogin, m)
            if not ok then ns.Print("|cffff5555login error in %s:|r %s", m.name, tostring(err)) end
        end
    end
    ns.Fire("LOGIN")
    if ns.db and ns.db.enabled and not ns.db.quietLogin then
        ns.Print("v%s loaded. Type |cffffff00/fxp|r for options.", ns.VERSION)
    end
end)
