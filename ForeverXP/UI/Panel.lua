-- ForeverXP: Advisor panel overlay
-- A small, translucent, movable panel showing the top suggestions and a
-- one-line status (level, XP/h, time to level, rested, gear, activity).

local _, ns = ...
local API = ns.API
local P = ns.NewModule("Panel")
ns.Panel = P

local WIDTH = 300
local PAD = 8

local function savePosition(frame)
    if not ns.db then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.db.positions[frame:GetName()] = { point = point, relPoint = relPoint, x = x, y = y }
end

function ns.RestorePosition(frame, defaultPoint, defaultX, defaultY)
    frame:ClearAllPoints()
    local pos = ns.db and ns.db.positions[frame:GetName()]
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultPoint, defaultX, defaultY)
    end
end

function ns.MakeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(f)
        if ns.db and not ns.db.locked then f:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        savePosition(f)
    end)
end

function ns.ApplyBackdrop(frame, alpha)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.05, 0.07, 0.1, alpha or 0.75)
        frame:SetBackdropBorderColor(0.5, 0.83, 1, 0.35)
    end
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(34)
    row.icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.icon:SetWidth(18)
    row.icon:SetJustifyH("CENTER")
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 22, 0)
    row.title:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetJustifyV("TOP")
    row.detail:SetWordWrap(true)
    row.detail:SetTextColor(0.78, 0.78, 0.78)
    if row.detail.SetMaxLines then row.detail:SetMaxLines(index == 1 and 3 or 2) end
    row:SetScript("OnEnter", function(self)
        if not self.suggestion or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.suggestion.title, 1, 1, 1, true)
        GameTooltip:AddLine(self.suggestion.detail or "", 0.8, 0.8, 0.8, true)
        if self.suggestion.action then GameTooltip:AddLine("Click: track / set waypoint", 0.5, 0.83, 1) end
        if self.suggestion.zone and self.suggestion.zone.notes then GameTooltip:AddLine(self.suggestion.zone.notes, 0.6, 0.6, 0.6, true) end
        if self.suggestion.zone and self.suggestion.zone.confidence == "estimate" then
            GameTooltip:AddLine("* level range is an estimate; fix with /fxp zone <min> <max> while standing in it", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self)
        if self.suggestion then P.Act(self.suggestion) end
    end)
    return row
end

function P.Act(s)
    local a = s.action
    if not a then
        if s.zone then ns.Print("%s: %s", s.zone.name, s.zone.travel or ("quest hub " .. (s.zone.hub or "?"))) end
        return
    end
    if a.questID then API.SuperTrackQuest(a.questID) end
    if a.mapID and a.x then
        if API.SetUserWaypoint(a.mapID, a.x, a.y) then
            ns.Print("Waypoint set for %s.", s.title)
        end
        if ns.Arrow then ns.Arrow:SetTarget(a.mapID, a.x, a.y, s.title, true) end
    end
end

function P:Create()
    local f = CreateFrame("Frame", "ForeverXPPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.frame = f
    f:SetWidth(WIDTH)
    f:SetHeight(120)
    f:SetFrameStrata("MEDIUM")
    ns.ApplyBackdrop(f, 0.75)
    ns.MakeMovable(f)
    ns.RestorePosition(f, "TOPRIGHT", -220, -120)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -6)
    f.title:SetText("|cff7fd4ffForeverXP|r route advisor")

    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(16, 16)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.close.text = f.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.close.text:SetPoint("CENTER")
    f.close.text:SetText("×")
    f.close:SetScript("OnClick", function() ns.db.showPanel = false; P:Update() end)

    f.min = CreateFrame("Button", nil, f)
    f.min:SetSize(16, 16)
    f.min:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.min.text = f.min:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.min.text:SetPoint("CENTER")
    f.min.text:SetText("–")
    f.min:SetScript("OnClick", function() ns.db.minimized = not ns.db.minimized; P:Update() end)

    f.rows = {}
    for i = 1, 5 do
        local row = createRow(f, i)
        row:SetPoint("LEFT", f, "LEFT", PAD, 0)
        row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
        f.rows[i] = row
    end

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 6)
    f.status:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(0.7, 0.7, 0.7)

    -- toast: floating text when the top suggestion changes
    local toast = CreateFrame("Frame", "ForeverXPToast", UIParent)
    toast:SetSize(500, 40)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toast:SetFrameStrata("HIGH")
    toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.text:SetPoint("CENTER")
    toast.text:SetTextColor(0.5, 0.83, 1)
    toast:Hide()
    toast:SetScript("OnUpdate", function(t, elapsed)
        t.timer = (t.timer or 0) + elapsed
        if t.timer < 0.5 then t:SetAlpha(t.timer / 0.5)
        elseif t.timer < 4 then t:SetAlpha(1)
        elseif t.timer < 5 then t:SetAlpha(5 - t.timer)
        else t:Hide() end
    end)
    self.toast = toast
end

function P:Toast(text)
    if not ns.db.toasts or not self.toast then return end
    self.toast.text:SetText(text)
    self.toast.timer = 0
    self.toast:SetAlpha(0)
    self.toast:Show()
end

local ACTIVITY_LABEL = { questing = "Questing", grinding = "Grinding", dungeon = "Dungeon", traveling = "Traveling", resting = "Resting", idle = "Idle" }

function P.StatusLine(ctx)
    if not ctx then return "" end
    local parts = {}
    table.insert(parts, string.format("Lv %d · %.0f%%", ctx.level, (ctx.xp or 0) / math.max(ctx.xpMax or 1, 1) * 100))
    if ctx.xpPerHour and ctx.xpPerHour > 0 then
        table.insert(parts, ns.FormatCompact(ctx.xpPerHour) .. " XP/h")
        table.insert(parts, ns.FormatDuration(ctx.timeToLevel) .. " to level")
    end
    if ctx.rested and ctx.rested > 0 then
        table.insert(parts, string.format("Rested %.0f%%", ctx.rested / math.max(ctx.xpMax or 1, 1) * 100))
    end
    if ctx.gear and ctx.gear.rating ~= "unknown" then table.insert(parts, "Gear " .. ctx.gear.rating) end
    table.insert(parts, ACTIVITY_LABEL[ctx.activity or "idle"] or "Idle")
    return table.concat(parts, " · ")
end

function P:Update()
    local f = self.frame
    if not f then return end
    local db = ns.db
    if not db.enabled or not db.showPanel or (db.hideInCombat and API.InCombat()) then f:Hide(); return end
    f:Show()
    f:SetScale(db.scale or 1)
    f:SetAlpha(db.alpha or 0.85)

    local list = ns.Advisor.suggestions or {}
    local ctx = ns.Advisor.ctx
    local maxRows = db.minimized and 1 or ns.Clamp(db.maxSuggestions or 3, 1, 5)
    local y = -22
    for i, row in ipairs(f.rows) do
        local s = list[i]
        if s and i <= maxRows then
            row.suggestion = s
            row.icon:SetText(s.icon or "•")
            row.title:SetText(s.title)
            row.detail:SetText(db.minimized and "" or (s.detail or ""))
            if i == 1 then
                row.title:SetTextColor(1, 0.95, 0.6)
                row.icon:SetTextColor(0.5, 0.83, 1)
            else
                row.title:SetTextColor(0.9, 0.9, 0.9)
                row.icon:SetTextColor(0.6, 0.6, 0.6)
            end
            local h = db.minimized and 16 or (16 + (row.detail:GetStringHeight() or 24) + 4)
            if h < 18 then h = 18 end
            if not db.minimized and h < 30 then h = 30 end
            row:SetHeight(h)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
            row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
            row:Show()
            y = y - h - 4
        else
            row.suggestion = nil
            row:Hide()
        end
    end
    if #list == 0 then
        f.rows[1].suggestion = nil
        f.rows[1].icon:SetText("…")
        f.rows[1].title:SetText("Gathering data")
        f.rows[1].detail:SetText("Suggestions appear once your quest log and zone are scanned.")
        f.rows[1]:SetHeight(40)
        f.rows[1]:ClearAllPoints()
        f.rows[1]:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        f.rows[1]:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
        f.rows[1]:Show()
        y = y - 44
    end
    f.status:SetText(P.StatusLine(ctx))
    f:SetHeight(-y + 22)
end

function P:OnLogin()
    self:Create()
    ns.Listen("SUGGESTIONS", function(list, ctx, changed)
        P:Update()
        if changed and list[1] and list[1].kind ~= "rested" then P:Toast(list[1].title) end
    end)
    ns.Listen("COMBAT", function() P:Update() end)
    ns.Listen("SETTINGS_CHANGED", function() P:Update() end)
    ns.Ticker(10, function() P:Update() end)
    self:Update()
end
