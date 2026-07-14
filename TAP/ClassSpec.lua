-- UIFoundry - ClassSpec.lua
-- A reusable class + spec multi-select, promoted from Twisteds Combat Alerts and rebuilt on the
-- library's OWN components (Checkbox, Heading, Button, StylePanel) so ANY suite sidecar can gate
-- features by class/spec with the same class-colored grid, in the addon's theme.
--
-- Data helpers (palette-independent):
--   UIF.GetClassList()              -> { { token, name, id, color = {r,g,b} }, ... }
--   UIF.GetSpecList(token[, all])   -> { { id = specID, name, icon }, ... }  (all=true prepends "all")
--   UIF.ClassColor(token)           -> r, g, b
--
-- UI (theme methods):
--   theme:ClassSpecSummary(selected)          -> "All classes / specs" | "N specs selected"
--   theme:OpenClassSpecPicker(opts)           -> the class-colored grid popup
--   theme:ClassSpecButton(parent, opts)       -> a button that shows the summary + opens the picker
--   b:ClassSpecButton(x, y, opts)             -> the same, via the Builder
--
-- `selected` is a SET: specID -> true. Empty/nil means "all classes / specs".
--   opts (picker):  selected, title, hint, onChange(selected), columns (5), colWidth (160)
--   opts (button):  selected, title, hint, onChange(selected), width (190), height, kind, columns, colWidth

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
function UIF.ClassColor(token)
    local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.95
end

function UIF.GetClassList()
    local list = {}
    local n = (GetNumClasses and GetNumClasses()) or 0
    for i = 1, n do
        local name, token, id = GetClassInfo(i)
        if token then
            local r, g, b = UIF.ClassColor(token)
            list[#list + 1] = { token = token, name = name, id = id, color = { r, g, b } }
        end
    end
    return list
end

local function classIdFromToken(token)
    for _, c in ipairs(UIF.GetClassList()) do if c.token == token then return c.id end end
end

function UIF.GetSpecList(token, includeAll)
    local list = {}
    if includeAll then list[#list + 1] = { id = "all", name = "All Specs" } end
    local classID = token and classIdFromToken(token)
    if classID and GetNumSpecializationsForClassID then
        for s = 1, GetNumSpecializationsForClassID(classID) do
            local specID, specName, _, specIcon, role = GetSpecializationInfoForClassID(classID, s)
            if specID then list[#list + 1] = { id = specID, name = specName, icon = specIcon, role = role } end
        end
    end
    return list
end

-- DAMAGER specs that fight at range (everything else DAMAGER is treated as melee). Spec IDs are
-- stable; add new ones here as expansions ship.
local RANGED_DPS = {
    [62] = true, [63] = true, [64] = true,          -- Mage: Arcane / Fire / Frost
    [265] = true, [266] = true, [267] = true,       -- Warlock: Affliction / Demonology / Destruction
    [253] = true, [254] = true,                     -- Hunter: Beast Mastery / Marksmanship (Survival is melee)
    [258] = true,                                   -- Priest: Shadow
    [102] = true,                                   -- Druid: Balance
    [262] = true,                                   -- Shaman: Elemental
    [1467] = true, [1473] = true,                   -- Evoker: Devastation / Augmentation
}

-- Map a spec to a role group: "TANK" | "HEALER" | "RANGED" | "MELEE".
function UIF.SpecGroup(specID, role)
    if role == "TANK" then return "TANK" end
    if role == "HEALER" then return "HEALER" end
    return RANGED_DPS[specID] and "RANGED" or "MELEE"
end

----------------------------------------------------------------------
-- Summary label
----------------------------------------------------------------------
function Mixin:ClassSpecSummary(selected)
    if not selected or not next(selected) then return "All classes / specs" end
    local n = 0; for _ in pairs(selected) do n = n + 1 end
    return n .. (n == 1 and " spec selected" or " specs selected")
end

----------------------------------------------------------------------
-- The picker popup - assembled entirely from UIFoundry components.
----------------------------------------------------------------------
function Mixin:OpenClassSpecPicker(opts)
    opts = opts or {}
    local theme, C = self, self.C
    local selected = opts.selected or {}
    local COLS = opts.columns or 5
    local COLW = opts.colWidth or 160

    local p = theme._classSpecPicker
    if not p then
        p = CreateFrame("Frame", UIF.NextId(theme.id .. "ClassSpecPicker"), UIParent)
        theme._classSpecPicker = p
        p:SetSize(40 + COLS * COLW, 596); p:SetPoint("CENTER")
        p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
        theme:StylePanel(p, C.panel, C.border); p:EnableMouse(true); p:SetMovable(true)
        tinsert(UISpecialFrames, p:GetName())

        -- Draggable header + centered title (Heading).
        local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(34)
        hd:RegisterForDrag("LeftButton"); hd:SetScript("OnDragStart", function() p:StartMoving() end); hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
        p.title = theme:Heading(hd, { text = "Class / Spec", role = "h4" }); p.title:SetPoint("CENTER"); p.title:SetJustifyH("CENTER")

        -- Close (Button).
        local xb = theme:Button(p); xb:Configure("X", 26, 22, "danger", function() p:Hide() end)
        xb:SetPoint("TOPRIGHT", -4, -4); xb:SetFrameLevel(hd:GetFrameLevel() + 5)

        -- Bulk actions (ghost Buttons) + hint (Heading/caption).
        local ca = theme:Button(p); ca:Configure("Check All", 84, 20, "ghost", function()
            for _, cls in ipairs(UIF.GetClassList()) do for _, sp in ipairs(UIF.GetSpecList(cls.token)) do p._selected[sp.id] = true end end
            p._rebuild(); if p._onChange then p._onChange(p._selected) end
        end); ca:SetPoint("TOPLEFT", 16, -42)
        local ua = theme:Button(p); ua:Configure("Uncheck All", 96, 20, "ghost", function()
            wipe(p._selected); p._rebuild(); if p._onChange then p._onChange(p._selected) end
        end); ua:SetPoint("LEFT", ca, "RIGHT", 4, 0)
        p.hint = theme:Heading(p, { text = "", role = "caption" }); p.hint:SetPoint("LEFT", ua, "RIGHT", 12, 0)

        -- Role quick-select: toggle every spec in a role group on/off. If all are already checked,
        -- the button clears them; otherwise it checks them all.
        local function roleToggle(group)
            local ids = {}
            for _, cls in ipairs(UIF.GetClassList()) do
                for _, sp in ipairs(UIF.GetSpecList(cls.token)) do
                    if UIF.SpecGroup(sp.id, sp.role) == group then ids[#ids + 1] = sp.id end
                end
            end
            local allOn = #ids > 0
            for _, id in ipairs(ids) do if not p._selected[id] then allOn = false; break end end
            for _, id in ipairs(ids) do p._selected[id] = (not allOn) and true or nil end
            p._rebuild(); if p._onChange then p._onChange(p._selected) end
        end
        local roleLbl = theme:Heading(p, { text = "Roles", role = "caption" }); roleLbl:SetPoint("TOPLEFT", 18, -78)
        local prev
        for _, r in ipairs({ { "Tanks", "TANK" }, { "Healers", "HEALER" }, { "Ranged DPS", "RANGED" }, { "Melee DPS", "MELEE" } }) do
            local rb = theme:Button(p); rb:Configure(r[1], #r[1] * 7 + 22, 20, "default", function() roleToggle(r[2]) end)
            if prev then rb:SetPoint("LEFT", prev, "RIGHT", 6, 0) else rb:SetPoint("LEFT", roleLbl, "RIGHT", 10, 0) end
            prev = rb
        end

        -- Body grid + Done (Button).
        p.body = CreateFrame("Frame", nil, p); p.body:SetPoint("TOPLEFT", 20, -106); p.body:SetPoint("BOTTOMRIGHT", -20, 54)
        local done = theme:Button(p); done:Configure("Done", 190, 30, "primary", function() p:Hide() end); done:SetPoint("BOTTOM", 0, 14)

        -- Pooled class Headings + spec Checkboxes, laid out into COLS columns.
        p._headers, p._checks = {}, {}
        p._rebuild = function()
            for _, hh in ipairs(p._headers) do hh:Hide() end
            for _, cc in ipairs(p._checks) do cc:Hide() end
            local classes = UIF.GetClassList()
            table.sort(classes, function(a, b) return a.name < b.name end)
            local cols = {}; for i = 1, COLS do cols[i] = {} end
            for i, cls in ipairs(classes) do table.insert(cols[((i - 1) % COLS) + 1], cls) end
            local nH, nC = 0, 0
            for ci = 1, COLS do
                local colX, yOff = (ci - 1) * COLW, 0
                for _, cls in ipairs(cols[ci]) do
                    nH = nH + 1
                    local hh = p._headers[nH]
                    if not hh then hh = theme:Heading(p.body, { role = "h5" }); p._headers[nH] = hh end
                    hh:ClearAllPoints(); hh:SetPoint("TOPLEFT", p.body, "TOPLEFT", colX, -yOff); hh:Show()
                    hh:SetText(cls.name); hh:SetTextColor(cls.color[1], cls.color[2], cls.color[3])
                    yOff = yOff + 24
                    for _, sp in ipairs(UIF.GetSpecList(cls.token)) do
                        nC = nC + 1
                        local c = p._checks[nC]
                        if not c then c = theme:Checkbox(p.body); p._checks[nC] = c end
                        c:ClearAllPoints(); c:SetPoint("TOPLEFT", p.body, "TOPLEFT", colX + 2, -yOff); c:SetWidth(COLW - 8); c:Show()
                        local sid = sp.id
                        c:Configure(sp.name, p._selected[sid] and true or false, function(v)
                            p._selected[sid] = v and true or nil
                            if p._onChange then p._onChange(p._selected) end
                        end, cls.color)
                        c.fs:SetTextColor(cls.color[1], cls.color[2], cls.color[3])   -- color the label per class too
                        yOff = yOff + 23
                    end
                    yOff = yOff + 14
                end
            end
        end
    end

    p.title:SetText(opts.title or "Class / Spec")
    p.hint:SetText(opts.hint or "none checked = every class / spec")
    p._selected = selected
    p._onChange = opts.onChange
    p._rebuild()
    p:Show()
    return p
end

----------------------------------------------------------------------
-- A Button that shows the current selection summary and opens the picker.
----------------------------------------------------------------------
function Mixin:ClassSpecButton(parent, opts)
    opts = opts or {}
    local theme = self
    local selected = opts.selected or {}
    local btn = theme:Button(parent)
    btn:Configure(theme:ClassSpecSummary(selected), opts.width or 190, opts.height or 26, opts.kind or "default", function()
        theme:OpenClassSpecPicker({
            selected = selected, title = opts.title, hint = opts.hint,
            columns = opts.columns, colWidth = opts.colWidth,
            onChange = function(sel)
                btn.fs:SetText(theme:ClassSpecSummary(sel))
                if opts.onChange then opts.onChange(sel) end
            end,
        })
    end, opts)
    return btn
end
