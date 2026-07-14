-- UIFoundry - Forms.lua
-- Form controls beyond the basic widgets: RadioGroup, SegmentedControl, Stepper,
-- SearchBox, and TextArea. All accept the standard style keys.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

----------------------------------------------------------------------
-- RadioGroup: single-select list of options.
--   theme:RadioGroup(parent, {
--     options = { { value="a", label="Option A" }, { value="b", label="Option B" } },
--     value = "a", horizontal = false, spacing = 24, onChange = function(v) end })
----------------------------------------------------------------------
function Mixin:RadioGroup(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local g = CreateFrame("Frame", nil, parent)
    g.value = opts.value
    g.buttons = {}
    local horiz = opts.horizontal
    local spacing = opts.spacing or (horiz and 120 or 24)
    local off = 0
    for _, o in ipairs(opts.options or {}) do
        local b = CreateFrame("Button", nil, g); b:SetSize(horiz and (spacing - 8) or 200, 20)
        if horiz then b:SetPoint("LEFT", off, 0) else b:SetPoint("TOPLEFT", 0, -off) end
        b.ring = b:CreateTexture(nil, "ARTWORK"); b.ring:SetSize(14, 14); b.ring:SetPoint("LEFT", 0, 0)
        UIF.paint(b.ring, C.border)
        b.inner = b:CreateTexture(nil, "ARTWORK"); b.inner:SetSize(12, 12); b.inner:SetPoint("CENTER", b.ring, "CENTER"); UIF.paint(b.inner, C.bg)
        b.dot = b:CreateTexture(nil, "OVERLAY"); b.dot:SetSize(6, 6); b.dot:SetPoint("CENTER", b.ring, "CENTER"); UIF.paint(b.dot, C.accent); b.dot:Hide()
        b.fs = b:CreateFontString(nil, "OVERLAY"); theme:StyleFont(b.fs, opts, { textColor = C.text }); b.fs:SetPoint("LEFT", b.ring, "RIGHT", 8, 0); b.fs:SetText(o.label)
        b._value = o.value
        b:SetScript("OnClick", function() g:SetValue(o.value); if opts.onChange then opts.onChange(o.value) end end)
        b:SetScript("OnEnter", function(self) UIF.paint(self.ring, theme.C.accent) end)
        b:SetScript("OnLeave", function(self) UIF.paint(self.ring, self._value == g.value and theme.C.accent or theme.C.border) end)
        g.buttons[#g.buttons + 1] = b
        off = off + spacing
    end
    function g:SetValue(v)
        self.value = v
        for _, b in ipairs(self.buttons) do
            local on = b._value == v
            b.dot:SetShown(on); UIF.paint(b.ring, on and theme.C.accent or theme.C.border)
        end
    end
    if horiz then g:SetSize(off, 20) else g:SetSize(200, math.max(20, off)) end
    g:SetValue(g.value)
    return g
end

----------------------------------------------------------------------
-- SegmentedControl: connected buttons, single-select (iOS-style tab switch).
--   theme:SegmentedControl(parent, { segments = { {value="d",label="Day"}, ... },
--       value="d", width=300, height=26, onChange=function(v) end })
----------------------------------------------------------------------
function Mixin:SegmentedControl(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local segs = opts.segments or {}
    local w, h = opts.width or 300, opts.height or 26
    local f = CreateFrame("Frame", nil, parent); f:SetSize(w, h)
    theme:StylePanel(f, UIF.toColor(opts.bg, C.card), UIF.toColor(opts.borderColor, C.border))
    theme:StyleFrame(f, opts)
    f.value = opts.value
    f.buttons = {}
    local n = math.max(1, #segs)
    local segW = (w - 2) / n
    for i, s in ipairs(segs) do
        local b = CreateFrame("Button", nil, f); b:SetSize(segW, h - 2)
        b:SetPoint("LEFT", 1 + (i - 1) * segW, 0)
        b.hl = b:CreateTexture(nil, "ARTWORK"); b.hl:SetAllPoints(); b.hl:Hide()
        b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetPoint("CENTER"); theme:StyleFont(b.fs, opts, { textColor = C.subtext }); b.fs:SetText(s.label)
        b._value = s.value
        b:SetScript("OnClick", function() f:SetValue(s.value); if opts.onChange then opts.onChange(s.value) end end)
        b:SetScript("OnEnter", function(self) if self._value ~= f.value then UIF.paint(self.hl, UIF.mix(theme.C.card, theme.C.accent, 0.2)); self.hl:Show() end end)
        b:SetScript("OnLeave", function(self) if self._value ~= f.value then self.hl:Hide() end end)
        f.buttons[#f.buttons + 1] = b
    end
    function f:SetValue(v)
        self.value = v
        for _, b in ipairs(self.buttons) do
            local on = b._value == v
            b.hl:SetShown(on)
            if on then UIF.paint(b.hl, theme.C.accent); b.fs:SetTextColor(1, 1, 1)
            else b.fs:SetTextColor(unpack(theme.C.subtext)) end
        end
    end
    f:SetValue(f.value)
    return f
end

----------------------------------------------------------------------
-- Stepper: number field with - / + buttons.
--   theme:Stepper(parent, { value=5, min=0, max=10, step=1, width=120, onChange=fn })
----------------------------------------------------------------------
function Mixin:Stepper(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w, h = opts.width or 120, opts.height or 24
    local f = CreateFrame("Frame", nil, parent); f:SetSize(w, h)
    f.value = opts.value or 0; f.min = opts.min; f.max = opts.max; f.step = opts.step or 1

    local minus = theme:Button(f); minus:Configure("-", h, h, "default", nil, opts.buttonStyle); minus:SetPoint("LEFT")
    local plus  = theme:Button(f); plus:Configure("+", h, h, "default", nil, opts.buttonStyle); plus:SetPoint("RIGHT")
    local box = theme:EditBox(f); box:Configure(w - 2 * h - 4, h, f.value); box:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    box:SetJustifyH("CENTER"); box:ApplyStyle(opts)
    f.box = box

    function f:_clamp(v)
        if self.min and v < self.min then v = self.min end
        if self.max and v > self.max then v = self.max end
        return v
    end
    function f:SetValue(v, fire)
        v = self:_clamp(tonumber(v) or self.value)
        self.value = v; self.box:SetText(tostring(v)); self.box:SetCursorPosition(0)
        if fire and opts.onChange then opts.onChange(v) end
    end
    minus:SetScript("OnClick", function() f:SetValue(f.value - f.step, true) end)
    plus:SetScript("OnClick", function() f:SetValue(f.value + f.step, true) end)
    box:SetScript("OnEnterPressed", function(self) f:SetValue(self:GetText(), true); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self) f:SetValue(self:GetText(), true) end)
    f:SetValue(f.value)
    return f
end

----------------------------------------------------------------------
-- SearchBox: an input with a search glyph, placeholder, and a clear (x) button. onChange
-- fires live per keystroke. Great for filtering lists.
--   theme:SearchBox(parent, { width=240, placeholder="Search...", onChange=function(t) end })
----------------------------------------------------------------------
function Mixin:SearchBox(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w, h = opts.width or 240, opts.height or 24
    local e = theme:EditBox(parent); e:Configure(w, h, opts.value or "", nil)
    e:SetTextInsets(opts.icon and 26 or 8, 22, 0, 0)
    e:ApplyStyle(opts)
    if opts.icon then
        e.searchIcon = e:CreateTexture(nil, "ARTWORK"); e.searchIcon:SetSize(14, 14); e.searchIcon:SetPoint("LEFT", 7, 0)
        e.searchIcon:SetTexture(theme:ResolveIcon(opts.icon) or opts.icon)
        local ic = UIF.toColor(opts.iconColor, C.subtext); e.searchIcon:SetVertexColor(ic[1], ic[2], ic[3])
    end
    e._ph = e:CreateFontString(nil, "OVERLAY"); theme:StyleFont(e._ph, opts, { fontSize = 11, textColor = C.subtext })
    e._ph:SetPoint("LEFT", opts.icon and 26 or 8, 0); e._ph:SetText(opts.placeholder or "Search...")

    local clr = CreateFrame("Button", nil, e); clr:SetSize(16, 16); clr:SetPoint("RIGHT", -4, 0); clr:Hide()
    clr.fs = clr:CreateFontString(nil, "OVERLAY"); theme:StyleFont(clr.fs, {}, { fontSize = 13, textColor = C.subtext }); clr.fs:SetPoint("CENTER"); clr.fs:SetText("x")
    clr:SetScript("OnEnter", function(self) self.fs:SetTextColor(unpack(theme.C.text)) end)
    clr:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(theme.C.subtext)) end)
    clr:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
    e.clear = clr

    e:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        self._ph:SetShown(t == ""); self.clear:SetShown(t ~= "")
        if opts.onChange then opts.onChange(t) end
    end)
    e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    return e
end

----------------------------------------------------------------------
-- TextArea: a multi-line, scroll-clipped input inside a styled panel.
--   theme:TextArea(parent, { width=400, height=120, value="", onChange=fn })
----------------------------------------------------------------------
function Mixin:TextArea(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local box = CreateFrame("Frame", nil, parent); box:SetSize(opts.width or 400, opts.height or 120)
    theme:StylePanel(box, UIF.toColor(opts.bg, C.bg), UIF.toColor(opts.borderColor, C.border))
    theme:StyleFrame(box, opts)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", UIF.scrollWheel)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true); eb:SetAutoFocus(false)
    eb:SetFont(opts.font and theme:ResolveFont(opts.font) or theme.FONT, opts.fontSize or 12, opts.fontFlags or "")
    local tc = UIF.toColor(opts.textColor, C.text); eb:SetTextColor(tc[1], tc[2], tc[3])
    eb:SetTextInsets(2, 2, 2, 2); eb:SetWidth((opts.width or 400) - 20)
    eb:SetText(opts.value or ""); eb:SetCursorPosition(0)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then eb:SetWidth(w) end end)
    eb:SetScript("OnCursorChanged", function(_, _, cy, _, ch)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        if -cy < top then scroll:SetVerticalScroll(-cy)
        elseif (-cy + ch) > (top + view) then scroll:SetVerticalScroll(-cy + ch - view) end
    end)
    if opts.onChange then eb:SetScript("OnTextChanged", function(self) opts.onChange(self:GetText()) end) end
    scroll:SetScript("OnMouseDown", function() eb:SetFocus() end)
    scroll:SetScrollChild(eb)
    box.editBox = eb
    function box:GetText() return self.editBox:GetText() end
    function box:SetText(t) self.editBox:SetText(t or ""); self.editBox:SetCursorPosition(0) end
    return box
end
