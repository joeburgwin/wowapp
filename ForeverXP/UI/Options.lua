-- ForeverXP: Options panel (Settings / Interface Options)

local _, ns = ...
local O = ns.NewModule("Options")
ns.Options = O

local function checkbox(parent, label, key, x, y, tooltip)
    local ok, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok or not cb then
        cb = CreateFrame("CheckButton", nil, parent)
        cb:SetSize(24, 24)
    end
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local text = (type(cb.Text) == "table" and cb.Text) or (type(cb.text) == "table" and cb.text)
        or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:ClearAllPoints()
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb.tooltipText = tooltip
    cb:SetScript("OnShow", function(self) self:SetChecked(ns.db[key]) end)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        ns.Fire("SETTINGS_CHANGED")
    end)
    return cb
end

local function slider(parent, label, key, x, y, lo, hi, step, fmt)
    local ok, s = pcall(CreateFrame, "Slider", nil, parent, "OptionsSliderTemplate")
    if not ok or not s then
        s = CreateFrame("Slider", nil, parent)
        s:SetSize(180, 16)
        s:SetOrientation("HORIZONTAL")
    end
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetWidth(180)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local title = (type(s.Text) == "table" and s.Text) or s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:ClearAllPoints()
    title:SetPoint("BOTTOM", s, "TOP", 0, 2)
    if type(s.Low) == "table" then s.Low:SetText(tostring(lo)) end
    if type(s.High) == "table" then s.High:SetText(tostring(hi)) end
    local function refresh() title:SetText(string.format(fmt, label, ns.db[key] or lo)) end
    s:SetScript("OnShow", function(self) self:SetValue(ns.db[key] or lo); refresh() end)
    s:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        if ns.db[key] ~= value then
            ns.db[key] = value
            refresh()
            ns.Fire("SETTINGS_CHANGED")
        end
    end)
    return s
end

function O:Create()
    local panel = CreateFrame("Frame", "ForeverXPOptions", UIParent)
    panel.name = "ForeverXP"
    self.panel = panel

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ForeverXP - XP route advisor")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Suggests where to level next based on your level, zone, gear, quests and activity. Overlays are drag-to-move when unlocked.")

    local y = -70
    checkbox(panel, "Enable ForeverXP", "enabled", 16, y)
    checkbox(panel, "Lock overlay positions", "locked", 16, y - 28)
    checkbox(panel, "Show advisor panel", "showPanel", 16, y - 56)
    checkbox(panel, "Show direction arrow", "showArrow", 16, y - 84)
    checkbox(panel, "Show zone quest list", "showQuestList", 16, y - 112)
    checkbox(panel, "Toast when the top suggestion changes", "toasts", 16, y - 140)
    checkbox(panel, "Hide overlays in combat", "hideInCombat", 16, y - 168)
    checkbox(panel, "Route mode: order zone stops into one path", "routeMode", 16, y - 196)
    checkbox(panel, "Include quest pickups from Questie", "questiePickups", 16, y - 224, "Needs the Questie addon (Forever build).")

    slider(panel, "Overlay scale", "scale", 320, y - 10, 0.6, 1.6, 0.05, "%s: %.2f")
    slider(panel, "Overlay opacity", "alpha", 320, y - 60, 0.3, 1, 0.05, "%s: %.2f")
    slider(panel, "Suggestions shown", "maxSuggestions", 320, y - 110, 1, 5, 1, "%s: %d")
    slider(panel, "Quest rows", "questListRows", 320, y - 160, 3, 12, 1, "%s: %d")
    slider(panel, "Pickups per route", "routeMaxPickups", 320, y - 210, 0, 12, 1, "%s: %d")
    slider(panel, "Pickup levels above you", "pickupLevelSlack", 320, y - 260, 0, 5, 1, "%s: %d")

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, y - 300)
    help:SetWidth(560)
    help:SetJustifyH("LEFT")
    help:SetText("|cff7fd4ff/fxp|r options  ·  |cff7fd4ff/fxp lock|r  ·  |cff7fd4ff/fxp reset|r positions  ·  |cff7fd4ff/fxp status|r print what the advisor sees\n"
        .. "|cff7fd4ff/fxp zone <min> <max>|r override the level range of the zone you stand in (new Forever zones are estimates)\n"
        .. "|cff7fd4ff/fxp learn|r bind the current map to the zone you name: /fxp learn Riverglades\n"
        .. "|cff7fd4ff/fxp route|r toggle route mode  ·  |cff7fd4ff/fxp skip|r skip the current stop  ·  |cff7fd4ff/fxp questie|r check Questie")

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and category then
            pcall(Settings.RegisterAddOnCategory, category)
            self.category = category
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end
end

function O:Open()
    if self.category and Settings and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category
        pcall(Settings.OpenToCategory, id)
    elseif InterfaceOptionsFrame_OpenToCategory and self.panel then
        pcall(InterfaceOptionsFrame_OpenToCategory, self.panel)
        pcall(InterfaceOptionsFrame_OpenToCategory, self.panel)
    else
        ns.Print("Options panel unavailable on this client; use /fxp commands.")
    end
end

function O:OnLogin()
    self:Create()
end
