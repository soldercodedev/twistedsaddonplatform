-- UIFoundry - Selectors.lua
-- RangeSlider (single or dual/range), ComboBox (searchable select with icons), and
-- FontSelect (each option rendered in its own font).

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

----------------------------------------------------------------------
-- RangeSlider: a single-value or dual-thumb range selector.
--   theme:RangeSlider(parent, { width=240, min=0, max=100, step=1, low=20, high=80,
--       range=true, format="%d", onChange=function(lo, hi) end })
--   range=false -> a single thumb; onChange(value) gets one number.
----------------------------------------------------------------------
function Mixin:RangeSlider(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w = opts.width or 220
    local minv, maxv = opts.min or 0, opts.max or 100
    local step = opts.step or 1
    local range = opts.range ~= false
    local fmt = opts.format or "%d"

    local f = CreateFrame("Frame", nil, parent); f:SetSize(w, 22)
    local track = f:CreateTexture(nil, "ARTWORK"); track:SetHeight(3); track:SetPoint("LEFT", 0, -4); track:SetPoint("RIGHT", 0, -4)
    UIF.paint(track, UIF.toColor(opts.trackColor, C.border))
    local fill = f:CreateTexture(nil, "OVERLAY"); fill:SetHeight(3); fill:SetPoint("TOP", track, "TOP")
    UIF.paint(fill, UIF.toColor(opts.color, C.accent))
    local val = f:CreateFontString(nil, "OVERLAY"); theme:StyleFont(val, opts, { fontSize = 11, textColor = C.subtext })
    val:SetPoint("BOTTOM", f, "TOP", 0, -2)

    f.low  = math.max(minv, math.min(maxv, opts.low or minv))
    f.high = math.max(minv, math.min(maxv, opts.high or maxv))
    if not range then f.low = minv end

    local function snap(v) local s = math.floor((v - minv) / step + 0.5) * step + minv; return math.max(minv, math.min(maxv, s)) end
    local function frac(v) return (maxv > minv) and (v - minv) / (maxv - minv) or 0 end

    local function mkThumb()
        local t = CreateFrame("Button", nil, f); t:SetSize(13, 13); t:RegisterForDrag("LeftButton")
        local tx = t:CreateTexture(nil, "OVERLAY"); tx:SetAllPoints(); UIF.paint(tx, UIF.toColor(opts.thumbColor or opts.color, C.accent))
        t.tx = tx
        return t
    end
    local loThumb = range and mkThumb() or nil
    local hiThumb = mkThumb()

    function f:_render()
        local hiX = frac(self.high) * w
        hiThumb:ClearAllPoints(); hiThumb:SetPoint("CENTER", track, "LEFT", hiX, 0)
        if range then
            local loX = frac(self.low) * w
            loThumb:ClearAllPoints(); loThumb:SetPoint("CENTER", track, "LEFT", loX, 0)
            fill:ClearAllPoints(); fill:SetPoint("TOP", track, "TOP"); fill:SetPoint("LEFT", track, "LEFT", loX, 0); fill:SetPoint("RIGHT", track, "LEFT", hiX, 0)
            val:SetText(string.format(fmt .. "  -  " .. fmt, self.low, self.high))
        else
            fill:ClearAllPoints(); fill:SetPoint("TOPLEFT", track, "TOPLEFT"); fill:SetPoint("RIGHT", track, "LEFT", hiX, 0)
            val:SetText(string.format(fmt, self.high))
        end
    end
    local function fire() if opts.onChange then if range then opts.onChange(f.low, f.high) else opts.onChange(f.high) end end end

    local function drag(thumb, isLow)
        thumb:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local s = track:GetEffectiveScale(); local cx = GetCursorPosition()
                local left = track:GetLeft()
                if not (left and s and s > 0) then return end
                local v = snap(minv + ((cx / s) - left) / w * (maxv - minv))
                if isLow then f.low = math.min(v, f.high) else f.high = range and math.max(v, f.low) or v end
                f:_render(); fire()
            end)
        end)
        thumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        -- click-to-set on the track region is handled by dragging the nearest thumb
    end
    if range then drag(loThumb, true) end
    drag(hiThumb, false)

    function f:SetValues(lo, hi)
        if range then f.low, f.high = snap(lo), snap(hi) else f.high = snap(lo) end
        f:_render()
    end
    f:_render()
    return f
end

----------------------------------------------------------------------
-- ComboBox: a select that opens a searchable, icon-capable list popup.
--   theme:ComboBox(parent, { width=220, value="a", placeholder="Choose...",
--       items = { { value="a", label="Apple", icon="apple" }, ... },
--       searchable=true, onChange=function(value) end })
----------------------------------------------------------------------
local function ensureComboPopup(theme)
    if theme._combo then return theme._combo end
    local C = theme.C
    local p = CreateFrame("Frame", UIF.NextId(theme.id .. "Combo"), UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true); p:Hide()
    theme:StylePanel(p, C.panel, C.accent)
    local closer = CreateFrame("Button", nil, UIParent); closer:SetAllPoints(UIParent); closer:SetFrameStrata("FULLSCREEN_DIALOG"); closer:Hide()
    closer:SetScript("OnClick", function() p:Hide() end)
    p:SetScript("OnHide", function() closer:Hide() end); p.closer = closer
    p.search = theme:SearchBox(p, { width = 10, placeholder = "Search...", icon = "search",
        onChange = function(t) p._filter = (t or ""):lower(); p:_rebuild() end })
    p.search:ClearAllPoints(); p.search:SetPoint("TOPLEFT", 6, -6); p.search:SetPoint("TOPRIGHT", -6, -6)
    p.scroll = CreateFrame("ScrollFrame", nil, p); p.scroll:SetPoint("TOPLEFT", 6, -36); p.scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    p.child = CreateFrame("Frame", nil, p.scroll); p.child:SetSize(10, 10); p.scroll:SetScrollChild(p.child)
    p.scroll:EnableMouseWheel(true); p.scroll:SetScript("OnMouseWheel", UIF.scrollWheel)
    p.rows = {}
    function p:_rebuild()
        for _, r in ipairs(self.rows) do r:Hide() end
        local n, y = 0, -2
        local sel = self._getVal and self._getVal()
        for _, it in ipairs(self._items or {}) do
            if self._filter == "" or (it.label or ""):lower():find(self._filter, 1, true) then
                n = n + 1
                local r = self.rows[n]
                if not r then
                    r = CreateFrame("Button", nil, self.child); r:SetHeight(22)
                    r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:Hide()
                    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 6, 0)
                    r.fs = r:CreateFontString(nil, "OVERLAY"); r.fs:SetFont(theme.FONT, 12); r.fs:SetPoint("LEFT", 28, 0); r.fs:SetPoint("RIGHT", -6, 0); r.fs:SetJustifyH("LEFT")
                    r:SetScript("OnEnter", function(s) UIF.paint(s.hl, UIF.mix(theme.C.card, theme.C.accent, 0.4)); s.hl:Show() end)
                    r:SetScript("OnLeave", function(s) s.hl:Hide() end)
                    self.rows[n] = r
                end
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", self.child, "RIGHT", 0, 0)
                if it.icon then r.icon:SetTexture(theme:IconPath(it.icon) or it.icon); r.icon:SetTexCoord(unpack(theme.iconInset)); r.icon:Show(); r.fs:SetPoint("LEFT", 28, 0)
                else r.icon:Hide(); r.fs:SetPoint("LEFT", 8, 0) end
                r.fs:SetText(it.label); r.fs:SetTextColor(unpack(it.value == sel and theme.C.accent or theme.C.text))
                local v = it.value
                r:SetScript("OnClick", function() if self._onPick then self._onPick(v) end self:Hide() end)
                r:Show(); y = y - 22
            end
        end
        self.child:SetWidth(self:GetWidth() - 12); self.child:SetHeight(math.max(1, -y + 2))
    end
    theme._combo = p
    return p
end

function Mixin:ComboBox(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w = opts.width or 220
    local b = CreateFrame("Button", nil, parent); theme:StylePanel(b, C.card); b:SetSize(w, 26)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 6, 0); b.icon:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12); b.fs:SetPoint("LEFT", 8, 0); b.fs:SetPoint("RIGHT", -20, 0); b.fs:SetJustifyH("LEFT")
    b.caret = b:CreateFontString(nil, "OVERLAY"); b.caret:SetFont(theme.FONT, 10); b.caret:SetPoint("RIGHT", -7, -1); b.caret:SetText("v"); b.caret:SetTextColor(unpack(C.accent))
    b._value = opts.value
    b:SetScript("OnEnter", function(self) theme:FillPaint(self, theme.C.hover) end)
    b:SetScript("OnLeave", function(self) theme:FillPaint(self, theme.C.card) end)

    local function itemFor(v) for _, it in ipairs(opts.items or {}) do if it.value == v then return it end end end
    function b:Refresh()
        local it = itemFor(self._value)
        if it and it.icon then self.icon:SetTexture(theme:IconPath(it.icon) or it.icon); self.icon:SetTexCoord(unpack(theme.iconInset)); self.icon:Show(); self.fs:SetPoint("LEFT", 28, 0)
        else self.icon:Hide(); self.fs:SetPoint("LEFT", 8, 0) end
        self.fs:SetText(it and it.label or (opts.placeholder or "Select..."))
        self.fs:SetTextColor(unpack(it and theme.C.text or theme.C.subtext))
    end
    b:SetScript("OnClick", function(self)
        local p = ensureComboPopup(theme)
        p._items, p._filter = opts.items or {}, ""
        p._getVal = function() return self._value end
        p._onPick = function(v) self._value = v; self:Refresh(); if opts.onChange then opts.onChange(v) end end
        p:ClearAllPoints(); p:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        p:SetSize(math.max(w, 180), math.min(280, 44 + #(opts.items or {}) * 22))
        p.search:SetText("")
        p.closer:Show(); p:Show(); p:SetFrameLevel(500)
        p:_rebuild()
    end)
    b:Refresh()
    return b
end

----------------------------------------------------------------------
-- FontSelect: a dropdown where each option's label is rendered in that font, so you can see
-- what you're picking. Uses the theme's font registry (bundled set by default).
--   theme:FontSelect(parent, { width=200, value="UBUNTU", onChange=function(key) end })
----------------------------------------------------------------------
function Mixin:FontSelect(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local fonts = opts.fonts or theme:FontList()
    local w = opts.width or 200
    local b = CreateFrame("Button", nil, parent); theme:StylePanel(b, C.card); b:SetSize(w, 26)
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetPoint("LEFT", 8, 0); b.fs:SetPoint("RIGHT", -20, 0); b.fs:SetJustifyH("LEFT"); b.fs:SetTextColor(unpack(C.text))
    b.caret = b:CreateFontString(nil, "OVERLAY"); b.caret:SetFont(theme.FONT, 10); b.caret:SetPoint("RIGHT", -7, -1); b.caret:SetText("v"); b.caret:SetTextColor(unpack(C.accent))
    b._value = opts.value or (fonts[1] and fonts[1].key)
    b:SetScript("OnEnter", function(self) theme:FillPaint(self, theme.C.hover) end)
    b:SetScript("OnLeave", function(self) theme:FillPaint(self, theme.C.card) end)
    local function labelFor(key)
        for _, fd in ipairs(fonts) do if fd.key == key then return fd end end
        return fonts[1]
    end
    function b:Refresh()
        local fd = labelFor(self._value)
        if fd then self.fs:SetFont(theme:ResolveFont(fd.path or fd.key), 13); self.fs:SetText(fd.label) end
    end
    b:SetScript("OnClick", function(self)
        local items = {}
        for _, fd in ipairs(fonts) do items[#items + 1] = { label = fd.label, value = fd.key, font = fd.path or fd.key, fontSize = 13 } end
        theme:OpenMenu(self, items, function() return self._value end, function(v)
            self._value = v; self:Refresh(); if opts.onChange then opts.onChange(v) end
        end)
    end)
    b:Refresh()
    return b
end
