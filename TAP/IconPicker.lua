-- UIFoundry - IconPicker.lua
-- A generic grid picker for a curated set of icons (bundled TGAs, atlas coords, or
-- fileIDs). Each theme builds one picker; the icon set is supplied per open, so the same
-- picker serves any list.
--
--   theme:OpenIconPicker({
--     title       = "Choose Icon",
--     icons       = { { value = "bell.tga", texture = "path\\bell.tga", label = "bell",
--                       coords = { l, r, t, b } }, ... },   -- coords optional
--     columns     = 8, cell = 36,
--     current     = "bell.tga",              -- value to highlight
--     allowDefault= true, defaultLabel = "Use default",  -- shows a button -> onPick(nil)
--     customInput = true,                    -- shows a text row -> onPick(typed string)
--     customLabel = "Spell / item / path",   -- placeholder-ish hint for that row
--     customValue = "Frostbolt",             -- prefill for the text row
--     onPick      = function(value) end,     -- value is nil for default, a texture for a grid
--                                            -- pick, or the raw typed string for custom input.
--   })

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

function Mixin:OpenIconPicker(opts)
    opts = opts or {}
    local theme, C = self, self.C
    local icons  = opts.icons or {}
    local COLS   = opts.columns or 8
    local CELL   = opts.cell or 36
    local rows   = math.max(1, math.ceil(#icons / COLS))
    local hasCustom  = opts.customInput and true or false
    local extra      = hasCustom and 54 or 0   -- vertical room for the text row (+ gap below it)

    -- The picker frame is rebuilt whenever the icon set / grid dimensions / row set change (so it
    -- can serve differently-sized lists); otherwise it is reused.
    local p = theme._iconPicker
    local sig = string.format("%d|%d|%d|%d", #icons, COLS, CELL, hasCustom and 1 or 0)
    if p and p._sig ~= sig then p:Hide(); p:SetParent(nil); theme._iconPicker = nil; p = nil end

    if not p then
        local name = UIF.NextId(theme.id .. "IconPicker")
        p = CreateFrame("Frame", name, UIParent)
        theme._iconPicker = p
        p._sig = sig
        local frameW = 40 + COLS * CELL
        p:SetSize(frameW, 118 + extra + rows * CELL)
        p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
        theme:StylePanel(p, C.panel, C.border); p:EnableMouse(true); p:SetMovable(true)
        tinsert(UISpecialFrames, name)

        local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(34)
        hd:RegisterForDrag("LeftButton"); hd:SetScript("OnDragStart", function() p:StartMoving() end); hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
        p._title = hd:CreateFontString(nil, "OVERLAY"); p._title:SetFont(theme.FONT, 15); p._title:SetPoint("CENTER"); p._title:SetTextColor(unpack(C.text))
        local xb = theme:Button(p); xb:Configure("X", 26, 22, "danger", function() p:Hide() end); xb:SetPoint("TOPRIGHT", -4, -4); xb:SetFrameLevel(hd:GetFrameLevel() + 5)

        -- Optional custom text row (spell / item / path). Submitting it fires onPick(text).
        if hasCustom then
            local commit = function(text)
                text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
                p:Hide(); if p._onPick and text ~= "" then p._onPick(text) end
            end
            p._customHint = p:CreateFontString(nil, "OVERLAY"); p._customHint:SetFont(theme.FONT, 11)
            p._customHint:SetPoint("TOPLEFT", 20, -40); p._customHint:SetTextColor(unpack(C.subtext))
            local eb = theme:EditBox(p); eb:Configure(frameW - 40 - 76, 24, "", function() end)
            eb:SetPoint("TOPLEFT", 20, -54)
            eb:SetScript("OnEnterPressed", function(self) commit(self:GetText()); self:ClearFocus() end)
            p._custom = eb
            local ub = theme:Button(p); ub:Configure("Use", 58, 24, "primary", function() commit(eb:GetText()) end)
            ub:SetPoint("TOPLEFT", eb, "TOPRIGHT", 12, 0)
        end

        p._def = theme:Button(p); p._def:SetPoint("TOP", 0, -(40 + extra))

        -- Cells parented directly to the panel: a zero-size intermediate frame would stop
        -- them rendering (WoW needs a sized parent for child layout).
        local GX, GY = 20, -(74 + extra)
        p._cells = {}
        for i = 1, #icons do
            local cell = CreateFrame("Button", nil, p); cell:SetSize(CELL - 6, CELL - 6)
            local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
            cell:SetPoint("TOPLEFT", p, "TOPLEFT", GX + col * CELL, GY - row * CELL)
            theme:StylePanel(cell, C.bg)
            cell.tex = cell:CreateTexture(nil, "ARTWORK"); cell.tex:SetPoint("TOPLEFT", 3, -3); cell.tex:SetPoint("BOTTOMRIGHT", -3, 3)
            cell.sel = cell:CreateTexture(nil, "OVERLAY"); cell.sel:SetAllPoints(); cell.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35); cell.sel:Hide()
            cell:SetScript("OnEnter", function(self)
                self.tex:SetVertexColor(0.6, 0.85, 1)
                if self._label then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self._label, theme:AccentHeader()); GameTooltip:Show() end
            end)
            cell:SetScript("OnLeave", function(self) self.tex:SetVertexColor(1, 1, 1); GameTooltip_Hide() end)
            cell:SetScript("OnClick", function(self)
                p:Hide(); if p._onPick then p._onPick(self._value) end
            end)
            p._cells[i] = cell
        end
    end

    -- (Re)bind this open's data onto the (possibly reused) picker.
    p._onPick = opts.onPick
    p._title:SetText(opts.title or "Choose Icon")
    if hasCustom and p._custom then
        p._customHint:SetText(opts.customLabel or "Type a spell name, item, icon ID, or texture path:")
        p._custom:SetText(opts.customValue and tostring(opts.customValue) or "")
        p._custom:SetCursorPosition(0)
    end
    if opts.allowDefault then
        p._def:Configure(opts.defaultLabel or "Use default", 220, 24, "default", function()
            p:Hide(); if p._onPick then p._onPick(nil) end
        end)
        p._def:Show()
    else
        p._def:Hide()
    end
    for i, cell in ipairs(p._cells) do
        local it = icons[i]
        cell._value = it.value
        cell._label = it.label
        cell.tex:SetTexture(it.texture)
        if it.coords then cell.tex:SetTexCoord(it.coords[1], it.coords[2], it.coords[3], it.coords[4])
        else cell.tex:SetTexCoord(0, 1, 0, 1) end
        cell.sel:SetShown(opts.current ~= nil and opts.current == it.value)
    end
    p:Show()
    return p
end
