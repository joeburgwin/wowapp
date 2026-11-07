-- ForeverXP: Zone quest list overlay
-- A compact, colour-coded list of the quests that matter where you are:
-- completed ones first, then by estimated XP. Click a row to track it.

local _, ns = ...
local API = ns.API
local L = ns.NewModule("QuestList")
ns.QuestList = L

local WIDTH, PAD, ROW_H = 240, 6, 14

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.mark:SetWidth(12)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.title:SetPoint("LEFT", row.mark, "RIGHT", 2, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWidth(70)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
    row:SetScript("OnClick", function(self, button)
        local s = self.step
        if s then
            if button == "RightButton" then ns.Route:Skip(s); return end
            if s.quest then API.SuperTrackQuest(s.questID) end
            if ns.Arrow then ns.Arrow:SetTarget(s.mapID, s.x, s.y, s.title, true) end
            return
        end
        local q = self.quest
        if not q then return end
        API.SuperTrackQuest(q.questID)
        if q.wp and ns.Arrow then ns.Arrow:SetTarget(q.wp.mapID, q.wp.x, q.wp.y, q.title, true) end
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        local q = self.quest
        if self.step and not q then
            if not GameTooltip then return end
            local s = self.step
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(s.title, 1, 1, 1)
            GameTooltip:AddLine(string.format("Pick up from %s · level %s · ~%s XP", s.who or "?", tostring(s.level or "?"), ns.FormatNumber(s.xp or 0)), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Left-click: point the arrow here · Right-click: skip", 0.5, 0.83, 1)
            GameTooltip:Show()
            return
        end
        if not q or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(q.title, 1, 1, 1)
        GameTooltip:AddLine(string.format("Level %s · %s%s XP", tostring(q.level or "?"), q.xpIsEstimate and "~" or "", ns.FormatNumber(q.xp)), 0.8, 0.8, 0.8)
        for _, o in ipairs(q.objectives or {}) do
            GameTooltip:AddLine((o.finished and "|cff55ff55" or "|cffdddddd") .. o.text .. "|r", 1, 1, 1, true)
        end
        GameTooltip:AddLine("Click to track", 0.5, 0.83, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

function L:Create()
    local f = CreateFrame("Frame", "ForeverXPQuestList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.frame = f
    f:SetWidth(WIDTH)
    f:SetHeight(60)
    f:SetFrameStrata("MEDIUM")
    ns.ApplyBackdrop(f, 0.6)
    ns.MakeMovable(f)
    ns.RestorePosition(f, "RIGHT", -20, 0)
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -5)
    f.header:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.header:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, 12 do
        local row = createRow(f)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -20 - (i - 1) * (ROW_H + 1))
        row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
        row:Hide()
        f.rows[i] = row
    end
end

-- Pure sort so it is testable: completed first, then XP-weighted priority.
function L.Order(list)
    local copy = {}
    for _, q in ipairs(list or {}) do if not q.failed then table.insert(copy, q) end end
    table.sort(copy, function(a, b)
        if a.complete ~= b.complete then return a.complete end
        local sa, sb = (a.xp or 0) * (a.mult or 1), (b.xp or 0) * (b.mult or 1)
        if sa ~= sb then return sa > sb end
        return (a.title or "") < (b.title or "")
    end)
    return copy
end

local KIND_ICON = { pickup = "|cff7fd4ff?|r", objective = "|cffffff00●|r", turnin = "|cff55ff55✔|r" }

-- Route view: numbered steps in walking order.
function L:UpdateRoute(steps)
    local f, db = self.frame, ns.db
    local total = ns.Route.totalYards or 0
    f.header:SetText("|cff7fd4ffRoute|r · " .. (ns.Route.Summary(steps, total) or ""):gsub("^Route: ", ""))
    local maxRows = ns.Clamp(db.questListRows or 8, 1, 12)
    local shown = 0
    for i, row in ipairs(f.rows) do
        local s = steps[i]
        if s and i <= maxRows then
            row.quest = s.quest
            row.step = s
            row.mark:SetText(string.format("|cffaaaaaa%d|r", i))
            local who = s.who and (" |cff888888@ " .. s.who .. "|r") or ""
            row.title:SetText((KIND_ICON[s.kind] or "•") .. " " .. (s.title or "?") .. who)
            row.right:SetText(string.format("|cffaaaaaa%s yd|r", ns.FormatCompact(s.leg or 0)))
            row:Show()
            shown = shown + 1
        else
            row.quest, row.step = nil, nil
            row:Hide()
        end
    end
    f:SetScale(db.scale or 1)
    f:SetAlpha(db.alpha or 0.85)
    f:SetHeight(24 + shown * (ROW_H + 1) + PAD)
    f:Show()
end

function L:Update()
    local f = self.frame
    if not f then return end
    local db = ns.db
    if not db.enabled or not db.showQuestList or (db.hideInCombat and API.InCombat()) then f:Hide(); return end
    if db.routeMode ~= false and ns.Route and #(ns.Route.steps or {}) > 0 then
        self:UpdateRoute(ns.Route.steps)
        return
    end
    local all = ns.Quests.list or {}
    local inZone = {}
    for _, q in ipairs(all) do if q.inZone then table.insert(inZone, q) end end
    local source, label = inZone, "Zone quests"
    if #inZone == 0 then source, label = all, "Quest log" end
    local ordered = L.Order(source)
    local ctx = ns.Advisor.ctx
    local zoneName = ctx and ctx.zone and ctx.zone.name or (ctx and ctx.zoneNames and ctx.zoneNames[2]) or ""
    f.header:SetText(string.format("|cff7fd4ff%s|r %s", label, zoneName ~= "" and ("· " .. zoneName) or ""))
    local maxRows = ns.Clamp(db.questListRows or 8, 1, 12)
    local shown = 0
    for i, row in ipairs(f.rows) do
        local q = ordered[i]
        if q and i <= maxRows then
            row.quest = q
            row.mark:SetText(q.complete and "|cff55ff55✔|r" or (q.objTotal > 0 and q.objDone > 0 and "|cffffff00•|r" or "|cff888888•|r"))
            row.title:SetText(ns.Quests.Color(q.difficulty) .. (q.title or "?") .. "|r")
            local prog = ""
            if not q.complete and q.objTotal > 0 then prog = string.format("%d/%d ", q.objDone, q.objTotal) end
            row.right:SetText(string.format("%s|cffaaaaaa%s%s|r", prog, q.xpIsEstimate and "~" or "", ns.FormatNumber(q.xp)))
            row:Show()
            shown = shown + 1
        else
            row.quest = nil
            row:Hide()
        end
    end
    if shown == 0 then
        f.rows[1].quest = nil
        f.rows[1].mark:SetText("")
        f.rows[1].title:SetText("|cff888888No quests - visit the hub|r")
        f.rows[1].right:SetText("")
        f.rows[1]:Show()
        shown = 1
    end
    f:SetScale(db.scale or 1)
    f:SetAlpha(db.alpha or 0.85)
    f:SetHeight(24 + shown * (ROW_H + 1) + PAD)
    f:Show()
end

function L:OnLogin()
    self:Create()
    ns.Listen("QUESTS_SCANNED", function() L:Update() end)
    ns.Listen("ROUTE_CHANGED", function() L:Update() end)
    ns.Listen("SUGGESTIONS", function() L:Update() end)
    ns.Listen("COMBAT", function() L:Update() end)
    ns.Listen("SETTINGS_CHANGED", function() L:Update() end)
    self:Update()
end
