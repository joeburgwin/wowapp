-- ForeverXP: Direction arrow overlay
-- A gentle arrow that rotates toward the current target (a quest waypoint
-- or a suggestion you clicked) with the distance underneath. Falls back to
-- the quest the advisor thinks is most valuable when nothing is selected.

local _, ns = ...
local API = ns.API
local R = ns.NewModule("Arrow")
ns.Arrow = R

R.target = nil      -- { mapID, x, y, label, manual, setAt }
local MANUAL_TTL = 600
-- WoW's Lua 5.1 has math.atan2; newer Lua folds it into math.atan(y, x).
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Pure math: bearing from player (px,py) to target (tx,ty) in map space,
-- where +y is south. Returns radians counter-clockwise from north.
function R.Bearing(px, py, tx, ty)
    return atan2(-(tx - px), -(ty - py))
end

-- Rotation to apply to an up-pointing texture so it points at the target.
function R.Rotation(bearing, facing)
    local r = bearing - (facing or 0)
    while r > math.pi do r = r - 2 * math.pi end
    while r < -math.pi do r = r + 2 * math.pi end
    return r
end

function R.Distance(px, py, tx, ty, w, h)
    local dx, dy = (tx - px) * (w or 1), (ty - py) * (h or 1)
    return math.sqrt(dx * dx + dy * dy)
end

function R:SetTarget(mapID, x, y, label, manual)
    if not mapID or not x or not y then return end
    self.target = { mapID = mapID, x = x, y = y, label = label or "", manual = manual and true or false, setAt = ns.Now() }
    if self.frame then self.frame:Show() end
end

function R:Clear()
    self.target = nil
    if self.frame then self.frame:Hide() end
end

function R:AutoTarget()
    if self.target and self.target.manual and ns.Now() - self.target.setAt < MANUAL_TTL then return end
    local q = ns.Quests and ns.Quests:Priority()
    if q and q.wp then
        self:SetTarget(q.wp.mapID, q.wp.x, q.wp.y, q.title, false)
    elseif self.target and not self.target.manual then
        self:Clear()
    end
end

function R:Create()
    local f = CreateFrame("Frame", "ForeverXPArrow", UIParent)
    self.frame = f
    f:SetSize(64, 80)
    f:SetFrameStrata("MEDIUM")
    ns.MakeMovable(f)
    ns.RestorePosition(f, "TOP", 0, -200)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetSize(40, 40)
    f.tex:SetPoint("TOP", f, "TOP", 0, 0)
    f.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.tex:SetVertexColor(0.5, 0.83, 1, 1)

    f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.dist:SetPoint("TOP", f.tex, "BOTTOM", 0, -2)
    f.dist:SetTextColor(1, 0.95, 0.6)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("TOP", f.dist, "BOTTOM", 0, -1)
    f.label:SetWidth(180)
    f.label:SetWordWrap(false)
    f.label:SetTextColor(0.8, 0.8, 0.8)

    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then R:Clear(); R:AutoTarget() end
    end)

    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        R:Tick()
    end)
    f:Hide()
end

function R:Tick()
    local f, t = self.frame, self.target
    if not f or not t or not ns.db.showArrow or not ns.db.enabled then if f then f:Hide() end; return end
    local px, py, mapID = API.PlayerMapPosition(t.mapID)
    local facing = API.PlayerFacing()
    if not px or mapID ~= t.mapID or not facing then
        -- different map / instance / position restricted: show label only
        f.tex:SetAlpha(0.25)
        f.dist:SetText("?")
        f.label:SetText(t.label)
        f:SetAlpha(ns.db.alpha or 0.85)
        f:Show()
        return
    end
    local bearing = R.Bearing(px, py, t.x, t.y)
    f.tex:SetRotation(R.Rotation(bearing, facing))
    local w, h = API.MapWorldSize(t.mapID)
    local dist = w and R.Distance(px, py, t.x, t.y, w, h) or nil
    f.tex:SetAlpha(1)
    if dist then
        f.dist:SetText(string.format("%d yd", math.floor(dist)))
        if dist < 12 and not t.manual then self:Clear(); return end
        -- colour: green when close, blue when far
        local k = ns.Clamp(dist / 600, 0, 1)
        f.tex:SetVertexColor(0.5 + 0.2 * (1 - k), 0.83 + 0.1 * (1 - k), 1 - 0.5 * (1 - k), 1)
    else
        f.dist:SetText("")
    end
    f.label:SetText(t.label)
    f:SetScale(ns.db.scale or 1)
    f:SetAlpha(ns.db.alpha or 0.85)
    f:Show()
end

function R:OnLogin()
    self:Create()
    ns.Listen("QUESTS_SCANNED", function() R:AutoTarget() end)
    ns.Listen("SETTINGS_CHANGED", function() R:Tick() end)
end
