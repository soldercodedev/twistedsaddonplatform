-- UIFoundry - Widgets.lua
-- Bare, pooled-friendly widget factories. Each is a Theme method that returns a plain
-- frame carrying a :Configure (or :Set*) method. They read their colors from the theme
-- live, so ApplyAccent() recolors them on the next Configure/refresh. Positioning is left
-- to the caller (or to the Builder, which lays them out from a content frame's TOPLEFT).
--
--   local tg = theme:Toggle(parent);  tg:Configure(true, function(v) ... end)
--   local b  = theme:Button(parent);  b:Configure("Save", 100, 26, "primary", cb)
--   local dd = theme:Dropdown(parent):SetChoices(150, choices, getVal, setVal)
--   local e  = theme:EditBox(parent); e:Configure(200, 24, value, onCommit)
--   local s  = theme:Slider(parent);  s:Configure(200, 0, 10, 0.5, getVal, setVal, "%.1f")

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

----------------------------------------------------------------------
-- Toggle (on/off switch)
----------------------------------------------------------------------
function Mixin:Toggle(parent)
    local theme = self
    local f = CreateFrame("Button", nil, parent); f:SetSize(38, 18)
    f.track = f:CreateTexture(nil, "ARTWORK"); f.track:SetAllPoints()
    f.knob = f:CreateTexture(nil, "OVERLAY"); f.knob:SetSize(14, 14)
    function f:_render()
        local C = theme.C
        if self.checked then
            UIF.paint(self.track, self._onColor or C.accent)
            self.knob:ClearAllPoints(); self.knob:SetPoint("RIGHT", -2, 0); self.knob:SetColorTexture(0.05, 0.06, 0.08)
        else
            UIF.paint(self.track, self._offColor or C.border)
            self.knob:ClearAllPoints(); self.knob:SetPoint("LEFT", 2, 0); UIF.paint(self.knob, C.text)
        end
    end
    function f:Configure(checked, cb, opts)
        self.checked = checked and true or false; self.cb = cb
        -- Reset style EVERY time (this widget is pooled): otherwise a toggle reused without opts
        -- keeps a prior caller's on/off color or size, so toggles render inconsistent colors.
        self._onColor  = opts and UIF.toColor(opts.color or opts.onColor) or nil
        self._offColor = opts and UIF.toColor(opts.offColor) or nil
        self:SetSize((opts and opts.width) or 38, (opts and opts.height) or 18)
        self:_render()
    end
    function f:ApplyStyle(opts) self:Configure(self.checked, self.cb, opts) end
    f:SetScript("OnClick", function(self)
        self.checked = not self.checked; self:_render()
        if self.cb then self.cb(self.checked) end
    end)
    f:SetScript("OnEnter", theme.showTip)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

----------------------------------------------------------------------
-- Button (kinds: "primary" accent, "danger" red, "default" card)
-- The click callback receives the button itself, so it can be used as a menu anchor.
----------------------------------------------------------------------
function Mixin:Button(parent)
    local theme = self
    local b = CreateFrame("Button", nil, parent)
    b.borderTex = b:CreateTexture(nil, "BACKGROUND", nil, -1); b.borderTex:SetAllPoints(); b.borderTex:Hide()
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.iconTex = b:CreateTexture(nil, "ARTWORK"); b.iconTex:SetSize(14, 14); b.iconTex:SetPoint("LEFT", 8, 0); b.iconTex:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12); b.fs:SetPoint("CENTER")
    -- Paint the background either as a solid color (square) or a 9-sliced rounded-rect texture
    -- tinted with the color (rounded corners that stay crisp at any button size).
    function b:_paintBg(c)
        if self._shapeTex then
            self.bg:SetColorTexture(1, 1, 1)      -- clear any prior solid fill
            self.bg:SetTexture(self._shapeTex)
            if self.bg.SetTextureSliceMargins then
                local m = self._shapeMargin or 8
                pcall(self.bg.SetTextureSliceMargins, self.bg, m, m, m, m)
                if self.bg.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
                    pcall(self.bg.SetTextureSliceMode, self.bg, Enum.UITextureSliceMode.Stretched)
                end
            end
            self.bg:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        else
            self.bg:SetVertexColor(1, 1, 1)
            if self.bg.SetTextureSliceMargins then pcall(self.bg.SetTextureSliceMargins, self.bg, 0, 0, 0, 0) end
            UIF.paint(self.bg, c)
        end
    end
    b:SetScript("OnEnter", function(self) self._hovered = true; if self._hover then self:_paintBg(self._hover) end; theme:_showTip(self) end)
    b:SetScript("OnLeave", function(self) self._hovered = false; if self._normal then self:_paintBg(self._normal) end; GameTooltip_Hide() end)
    -- Recompute colors from the CURRENT accent (accent is mutable via ApplyAccent), then
    -- layer any per-instance style overrides (color / hoverColor / textColor / font / border
    -- / icon) on top.
    function b:_applyColors()
        local C, st = theme.C, self._style
        -- Re-apply the live theme font each configure so a global font swap + refresh propagates.
        self.fs:SetFont(theme.FONT, (st and st.fontSize) or 12, (st and st.fontFlags) or "")
        if self._kind == "primary" then
            self._normal = { C.accent[1], C.accent[2], C.accent[3] }
            self._hover  = UIF.lighten(C.accent, 0.14)
            self.fs:SetTextColor(1, 1, 1)
        elseif self._kind == "danger" then
            self._normal, self._hover = { 0.32, 0.14, 0.15 }, { 0.5, 0.22, 0.23 }
            self.fs:SetTextColor(1, 0.72, 0.72)
        elseif self._kind == "ghost" then
            self._normal, self._hover = { C.bg[1], C.bg[2], C.bg[3] }, UIF.mix(C.bg, C.accent, 0.30)
            self.fs:SetTextColor(unpack(C.text))
        else
            self._normal = { C.card[1], C.card[2], C.card[3] }
            self._hover  = UIF.darken(C.accent, 0.35)
            self.fs:SetTextColor(unpack(C.text))
        end
        if st then
            self._normal = UIF.toColor(st.color, self._normal)
            self._hover  = UIF.toColor(st.hoverColor, st.color and UIF.lighten(self._normal, 0.12) or self._hover)
            local tc = UIF.toColor(st.textColor)
            if tc then self.fs:SetTextColor(tc[1], tc[2], tc[3]) end
            if st.font then self.fs:SetFont(theme:ResolveFont(st.font), st.fontSize or 12, st.fontFlags or "") end
            if st.icon then
                self.iconTex:SetTexture(theme:IconPath(st.icon, st.iconVariant) or st.icon)
                self.iconTex:SetSize(st.iconSize or 14, st.iconSize or 14)
                if st.iconColor then local ic = UIF.toColor(st.iconColor); self.iconTex:SetVertexColor(ic[1], ic[2], ic[3]) else self.iconTex:SetVertexColor(1, 1, 1) end
                self.iconTex:Show()
                self.iconTex:ClearAllPoints()
                local txt = self.fs:GetText()
                if txt == nil or txt == "" then
                    -- Icon-only button: center the glyph (used for compact action buttons).
                    self.iconTex:SetPoint("CENTER")
                    self.fs:ClearAllPoints(); self.fs:SetPoint("CENTER")
                else
                    self.iconTex:SetPoint("LEFT", 8, 0)
                    self.fs:ClearAllPoints(); self.fs:SetPoint("LEFT", self.iconTex, "RIGHT", 6, 0)
                end
            else
                self.iconTex:Hide(); self.fs:ClearAllPoints(); self.fs:SetPoint("CENTER")
            end
        else
            self.iconTex:Hide(); self.fs:ClearAllPoints(); self.fs:SetPoint("CENTER")
        end
        -- Corner style: opts.radius / opts.corner, else the theme/skin default radius.
        local spec = (st and (st.radius or st.corner)) or theme.radius
        if spec and spec ~= 0 then self._shapeTex, self._shapeMargin = theme:ShapeTexture(spec) else self._shapeTex = nil end
        -- Optional border ring (st.border = true or { color, size }); fill insets to reveal it.
        local bd = st and st.border
        if bd then
            if bd == true then bd = {} end
            local bsz = bd.size or theme.borderSize or 1
            theme:PaintShape(self.borderTex, theme:Color(bd.color, C.border), (spec and spec ~= 0) and spec or nil, self:GetWidth(), self:GetHeight())
            self.borderTex:Show()
            self.bg:ClearAllPoints(); self.bg:SetPoint("TOPLEFT", bsz, -bsz); self.bg:SetPoint("BOTTOMRIGHT", -bsz, bsz)
        else
            self.borderTex:Hide(); self.bg:ClearAllPoints(); self.bg:SetAllPoints()
        end
        theme:StyleFrame(self, self._style)   -- shadow (st.shadow), etc.
        self:_paintBg(self._hovered and self._hover or self._normal)
    end
    -- kind: "primary" | "danger" | "default" | "ghost". opts (optional) restyles anything,
    -- incl. corner radius (opts.radius / opts.corner) and icon.
    function b:Configure(text, w, h, kind, cb, opts)
        self._kind = kind; self._style = opts; self:SetSize(w, h or 26); self.fs:SetText(text)
        self:_applyColors()
        self:SetScript("OnClick", function(self) if cb then cb(self) end end)
    end
    function b:ApplyStyle(opts) self._style = opts; self:_applyColors() end
    function b:SetText(text) self.fs:SetText(text) end
    function b:Retheme() self:_applyColors() end
    return b
end

----------------------------------------------------------------------
-- Dropdown (button that opens a themed Menu). Three flavors:
--   :SetChoices(w, { {value,label}, ... }, getVal, setVal)
--   :SetIconChoices(w, { {value,label,icon,coords}, ... }, getVal, setVal)
--   :SetMenu(w, buildItems, getVal, onPick, labelFor)  -- fully custom item list
----------------------------------------------------------------------
function Mixin:Dropdown(parent)
    local theme, C = self, self.C
    local b = CreateFrame("Button", nil, parent); theme:StylePanel(b, C.card)
    b.iconTex = b:CreateTexture(nil, "ARTWORK"); b.iconTex:SetSize(16, 16); b.iconTex:SetPoint("LEFT", 6, 0); b.iconTex:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12)
    b.fs:SetPoint("LEFT", 8, 0); b.fs:SetPoint("RIGHT", -20, 0); b.fs:SetJustifyH("LEFT"); b.fs:SetTextColor(unpack(C.text))
    b.caret = b:CreateFontString(nil, "OVERLAY"); b.caret:SetFont(theme.FONT, 10); b.caret:SetPoint("RIGHT", -7, -1)
    b.caret:SetText("v"); b.caret:SetTextColor(unpack(C.accent))
    b:SetScript("OnEnter", function(self) theme:FillPaint(self, theme.C.hover); theme:_showTip(self) end)
    b:SetScript("OnLeave", function(self) theme:FillPaint(self, theme.C.card); GameTooltip_Hide() end)

    function b:SetChoices(w, choices, getVal, setVal)
        theme:StylePanel(self, C.card)   -- pooled: re-apply shape/color so a live skin swap sticks
        self.fs:SetTextColor(C.text[1], C.text[2], C.text[3])   -- re-apply text color too (light themes)
        self:SetSize(w, 26)
        self.fs:SetFont(theme.FONT, 12)
        self.iconTex:Hide(); self.fs:SetPoint("LEFT", 8, 0)   -- clear any leftover icon from pooled reuse
        self.caret:SetTextColor(theme.C.accent[1], theme.C.accent[2], theme.C.accent[3])
        local function label() for _, c in ipairs(choices) do if c[1] == getVal() then return c[2] end end return "?" end
        self.fs:SetText(label())
        self:SetScript("OnClick", function(self)
            local items = {}
            for _, c in ipairs(choices) do items[#items + 1] = { label = c[2], value = c[1] } end
            theme:OpenMenu(self, items, getVal, function(v) setVal(v); self.fs:SetText(label()) end)
        end)
        return self
    end

    -- Dropdown where each item carries an icon; the button shows the selected item's icon.
    function b:SetIconChoices(w, items, getVal, setVal)
        theme:StylePanel(self, C.card)   -- pooled: re-apply shape/color so a live skin swap sticks
        self.fs:SetTextColor(C.text[1], C.text[2], C.text[3])   -- re-apply text color too (light themes)
        self:SetSize(w, 26)
        self.caret:SetTextColor(theme.C.accent[1], theme.C.accent[2], theme.C.accent[3])
        local function cur() for _, it in ipairs(items) do if it.value == getVal() then return it end end end
        local function refresh()
            local it = cur()
            if it and it.icon then
                self.iconTex:SetTexture(theme:IconPath(it.icon) or it.icon)
                if it.coords then self.iconTex:SetTexCoord(it.coords[1], it.coords[2], it.coords[3], it.coords[4])
                else self.iconTex:SetTexCoord(unpack(theme.iconInset)) end
                self.iconTex:Show(); self.fs:SetPoint("LEFT", 28, 0)
            else
                self.iconTex:Hide(); self.fs:SetPoint("LEFT", 8, 0)
            end
            self.fs:SetText(it and it.label or "?")
        end
        refresh()
        self:SetScript("OnClick", function(self)
            theme:OpenMenu(self, items, getVal, function(v) setVal(v); refresh() end)
        end)
        return self
    end

    -- Fully custom: buildItems() returns a fresh item array each open (for headers /
    -- dynamic lists), labelFor(value) renders the closed-state label.
    function b:SetMenu(w, buildItems, getVal, onPick, labelFor)
        theme:StylePanel(self, C.card)   -- pooled: re-apply shape/color so a live skin swap sticks
        self.fs:SetTextColor(C.text[1], C.text[2], C.text[3])   -- re-apply text color too (light themes)
        self:SetSize(w, 26)
        self.iconTex:Hide(); self.fs:SetPoint("LEFT", 8, 0)
        self.caret:SetTextColor(theme.C.accent[1], theme.C.accent[2], theme.C.accent[3])
        self.fs:SetText(labelFor and labelFor(getVal()) or "")
        self:SetScript("OnClick", function(self)
            theme:OpenMenu(self, buildItems(), getVal, function(v)
                onPick(v); if labelFor then self.fs:SetText(labelFor(v)) end
            end)
        end)
        return self
    end
    return b
end

----------------------------------------------------------------------
-- EditBox (single-line input). onCommit fires on Enter and on focus loss.
----------------------------------------------------------------------
function Mixin:EditBox(parent)
    local theme, C = self, self.C
    local e = CreateFrame("EditBox", nil, parent); theme:StylePanel(e, C.bg)
    e:SetFont(theme.FONT, 12, ""); e:SetTextColor(unpack(C.text)); e:SetTextInsets(7, 7, 0, 0); e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnter", theme.showTip)
    e:SetScript("OnLeave", GameTooltip_Hide)
    function e:Configure(w, h, value, onCommit)
        theme:StylePanel(self, C.bg)           -- pooled: re-apply shape/color so a live skin swap sticks
        self:SetTextColor(C.text[1], C.text[2], C.text[3])   -- re-apply text color too (light themes)
        self:SetSize(w, h or 24)
        self:SetFont(theme.FONT, 12, "")       -- re-apply live theme font (global font swap)
        self:SetScript("OnTextChanged", nil)   -- pooled: avoid a stale handler firing on SetText
        self:SetText(value ~= nil and tostring(value) or ""); self:SetCursorPosition(0)
        self:SetScript("OnEnterPressed", function(self) if onCommit then onCommit(self:GetText()) end self:ClearFocus() end)
        self:SetScript("OnEditFocusLost", function(self) if onCommit then onCommit(self:GetText()) end end)
    end
    -- Override border / bg / font / textColor per instance.
    function e:ApplyStyle(opts)
        if not opts then return end
        theme:StyleFrame(self, opts)
        if opts.font or opts.fontSize or opts.fontFlags then
            self:SetFont(opts.font and theme:ResolveFont(opts.font) or theme.FONT, opts.fontSize or 12, opts.fontFlags or "")
        end
        local tc = UIF.toColor(opts.textColor); if tc then self:SetTextColor(tc[1], tc[2], tc[3]) end
    end
    return e
end

----------------------------------------------------------------------
-- Slider (horizontal). The value readout above the track is an editable field: click it to
-- type an exact number (handy when the drag step is too coarse / the track too sensitive).
-- The typed value is parsed, clamped to [min,max], and snapped to the step before applying.
----------------------------------------------------------------------
-- Decimal places implied by a step (so the edit field shows a clean, parseable number).
local function stepDecimals(step)
    if not step or step <= 0 or math.floor(step) == step then return 0 end
    local d, s = 0, step
    while d < 6 and math.floor(s) ~= s do s, d = s * 10, d + 1 end
    return d
end

function Mixin:Slider(parent)
    local theme, C = self, self.C
    local s = CreateFrame("Slider", nil, parent); s:SetOrientation("HORIZONTAL")
    s.track = s:CreateTexture(nil, "ARTWORK"); UIF.paint(s.track, C.border)
    s.track:SetHeight(3); s.track:SetPoint("LEFT"); s.track:SetPoint("RIGHT")
    s.thumb = s:CreateTexture(nil, "OVERLAY"); UIF.paint(s.thumb, C.accent); s.thumb:SetSize(12, 12)
    s:SetThumbTexture(s.thumb)
    -- Value readout is an EditBox (not a FontString) so it doubles as a manual-entry field.
    s.val = CreateFrame("EditBox", nil, s); s.val:SetFont(theme.FONT, 11, "")
    s.val:SetSize(60, 14); s.val:SetPoint("BOTTOM", s, "TOP", 0, 1)
    s.val:SetJustifyH("CENTER"); s.val:SetAutoFocus(false)
    s.val:SetTextColor(unpack(C.subtext)); s.val._base = { C.subtext[1], C.subtext[2], C.subtext[3] }
    s.val._tipTitle, s.val._tipBody = "Set value", "Click to type an exact number."
    s:SetScript("OnEnter", theme.showTip)
    s:SetScript("OnLeave", GameTooltip_Hide)

    -- Parse the field, clamp + snap, apply. SetValue() fires OnValueChanged (updates the readout
    -- + calls setVal); reformat afterward so an unchanged value still redraws cleanly.
    local function commit(e)
        local txt = e:GetText() or ""
        local num = tonumber(txt) or tonumber(txt:match("%-?%d*%.?%d+") or "")
        if num and s._min then
            if num < s._min then num = s._min elseif num > s._max then num = s._max end
            if s._step and s._step > 0 then
                num = s._min + math.floor((num - s._min) / s._step + 0.5) * s._step
                if num > s._max then num = s._max end
            end
            s:SetValue(num)
        end
        e:SetText(string.format(s._fmt or "%.1f", s:GetValue()))
        e:HighlightText(0, 0); e:ClearFocus()
    end
    s.val:SetScript("OnEnterPressed", commit)
    s.val:SetScript("OnEditFocusLost", commit)
    s.val:SetScript("OnEditFocusGained", function(e)
        e:SetText(string.format("%." .. (s._dec or 0) .. "f", s:GetValue())); e:HighlightText()
    end)
    s.val:SetScript("OnEscapePressed", function(e)
        e:SetText(string.format(s._fmt or "%.1f", s:GetValue())); e:ClearFocus()
    end)
    s.val:SetScript("OnEnter", function(e)
        local r, g, b = theme:AccentHeader(); e:SetTextColor(r, g, b); theme:_showTip(e)
    end)
    s.val:SetScript("OnLeave", function(e)
        e:SetTextColor(e._base[1], e._base[2], e._base[3]); GameTooltip_Hide()
    end)

    function s:Configure(w, minv, maxv, step, getVal, setVal, fmt)
        fmt = fmt or "%.1f"
        UIF.paint(self.thumb, theme.C.accent)
        self._min, self._max, self._step, self._fmt, self._dec = minv, maxv, step, fmt, stepDecimals(step)
        -- Clear any previous setter FIRST: this slider may be pooled, and SetValue() fires
        -- OnValueChanged. Without this, reuse would run the OLD setter with the new value.
        self:SetScript("OnValueChanged", nil)
        self:SetSize(w, 16); self:SetMinMaxValues(minv, maxv); self:SetValueStep(step); self:SetObeyStepOnDrag(true)
        self:SetValue(getVal()); self.val:SetText(string.format(fmt, getVal()))
        self:SetScript("OnValueChanged", function(_, v) self.val:SetText(string.format(fmt, v)); setVal(v) end)
        if self._style then self:ApplyStyle(self._style) end
    end
    -- Override track / thumb / value-text colors per instance.
    function s:ApplyStyle(opts)
        self._style = opts; if not opts then return end
        if opts.trackColor then UIF.paint(self.track, UIF.toColor(opts.trackColor)) end
        if opts.color or opts.thumbColor then UIF.paint(self.thumb, UIF.toColor(opts.thumbColor or opts.color)) end
        local tc = UIF.toColor(opts.textColor)
        if tc then self.val:SetTextColor(tc[1], tc[2], tc[3]); self.val._base = { tc[1], tc[2], tc[3] } end
        if opts.hideValue then self.val:Hide() else self.val:Show() end
    end
    return s
end

----------------------------------------------------------------------
-- Icon button (small framed texture). Default 20x20; set .tex texture after creation.
----------------------------------------------------------------------
function Mixin:Icon(parent)
    local theme = self
    local b = CreateFrame("Button", nil, parent); b:SetSize(20, 20)
    theme:StylePanel(b, theme.C.bg)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(unpack(theme.iconInset))
    -- Override size / border / bg / icon tint; texture (opts.icon) and crop optional.
    function b:ApplyStyle(opts)
        if not opts then return end
        if opts.width or opts.height or opts.size then self:SetSize(opts.size or opts.width or 20, opts.size or opts.height or 20) end
        theme:StyleFrame(self, opts)
        if opts.icon then self.tex:SetTexture(theme:IconPath(opts.icon, opts.iconVariant) or opts.icon) end
        if opts.iconInset == false then self.tex:SetTexCoord(0, 1, 0, 1) elseif opts.iconCoords then self.tex:SetTexCoord(unpack(opts.iconCoords)) end
        local ic = UIF.toColor(opts.iconColor); if ic then self.tex:SetVertexColor(ic[1], ic[2], ic[3]) end
    end
    return b
end

----------------------------------------------------------------------
-- Color swatch (opens the color picker on click). colorTbl is mutated in place.
----------------------------------------------------------------------
function Mixin:Swatch(parent)
    local theme = self
    local b = CreateFrame("Button", nil, parent); b:SetSize(20, 20); theme:StylePanel(b, theme.C.bg)
    b.color = b:CreateTexture(nil, "ARTWORK")
    b.color:SetPoint("TOPLEFT", 2, -2); b.color:SetPoint("BOTTOMRIGHT", -2, 2)
    -- colorTbl = { r, g, b } (mutated on pick); onChange() fires live while dragging.
    function b:Configure(colorTbl, onChange, tipTitle, tipBody)
        theme:StylePanel(self, theme.C.bg)   -- pooled: re-apply shape so a live skin swap sticks
        local col = colorTbl
        self.color:SetColorTexture(col[1] or 1, col[2] or 0.1, col[3] or 0.1)
        self._tipTitle, self._tipBody = tipTitle or "Choose a color", tipBody
        self:SetScript("OnEnter", theme.showTip)
        self:SetScript("OnLeave", GameTooltip_Hide)
        self:SetScript("OnClick", function()
            theme:OpenColorPicker(col[1] or 1, col[2] or 0.1, col[3] or 0.1, function(r, g, b)
                col[1], col[2], col[3] = r, g, b
                self.color:SetColorTexture(r, g, b)
                if onChange then onChange(r, g, b) end
            end)
        end)
    end
    return b
end

----------------------------------------------------------------------
-- Logo tile: an image inside a 2px accent border on a dark panel, so it never clashes
-- with the background regardless of the logo's own edges.
----------------------------------------------------------------------
function Mixin:Logo(parent)
    local theme = self
    local f = CreateFrame("Frame", nil, parent)
    f.brd = f:CreateTexture(nil, "BACKGROUND", nil, 0); f.brd:SetAllPoints(); UIF.paint(f.brd, theme.C.accent)
    f.inner = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.inner:SetPoint("TOPLEFT", 2, -2); f.inner:SetPoint("BOTTOMRIGHT", -2, 2); UIF.paint(f.inner, theme.C.bg)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 6, -6); f.tex:SetPoint("BOTTOMRIGHT", -6, 6)
    function f:SetLogo(texture, size)
        if size then self:SetSize(size, size) end
        UIF.paint(self.brd, theme.C.accent)   -- track theme accent on rebuild
        self.tex:SetTexture(texture)
    end
    return f
end

----------------------------------------------------------------------
-- Checkbox row: a labeled box + check. Handy for multi-select grids.
----------------------------------------------------------------------
function Mixin:Checkbox(parent)
    local theme, C = self, self.C
    local b = CreateFrame("Button", nil, parent); b:SetHeight(22)
    b.brd = b:CreateTexture(nil, "BACKGROUND"); b.brd:SetSize(16, 16); b.brd:SetPoint("LEFT", 2, 0); UIF.paint(b.brd, C.border)
    b.box = b:CreateTexture(nil, "ARTWORK"); b.box:SetPoint("TOPLEFT", b.brd, "TOPLEFT", 1, -1); b.box:SetPoint("BOTTOMRIGHT", b.brd, "BOTTOMRIGHT", -1, 1); UIF.paint(b.box, C.bg)
    b.check = b:CreateTexture(nil, "OVERLAY"); b.check:SetPoint("TOPLEFT", b.box, "TOPLEFT", 2, -2); b.check:SetPoint("BOTTOMRIGHT", b.box, "BOTTOMRIGHT", -2, 2); b.check:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12); b.fs:SetPoint("LEFT", b.brd, "RIGHT", 8, 0); b.fs:SetPoint("RIGHT", 0, 0); b.fs:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) UIF.paint(self.box, theme.C.hover) end)
    b:SetScript("OnLeave", function(self) UIF.paint(self.box, theme.C.bg) end)
    -- label, checked, cb(newChecked); optional checkColor { r,g,b } (defaults to accent).
    function b:Configure(label, checked, cb, checkColor)
        local C = theme.C
        self.fs:SetText(label)
        local cc = checkColor or C.accent
        self.check:SetColorTexture(cc[1], cc[2], cc[3], 1)
        self.check:SetShown(checked and true or false)
        self:SetScript("OnClick", function(self)
            local nv = not self.check:IsShown()
            self.check:SetShown(nv)
            if cb then cb(nv) end
        end)
    end
    return b
end

----------------------------------------------------------------------
-- Preview: a framed box showing large text with an optional icon that can be dragged to
-- reposition it. Useful for "on-screen alert" style authoring. The icon offset is written
-- back into a bound data table (a.iconX / a.iconY) as you drag.
----------------------------------------------------------------------
function Mixin:Preview(parent)
    local theme = self
    local f = CreateFrame("Frame", nil, parent); theme:StylePanel(f, { 0.05, 0.05, 0.06 }, theme.C.border)
    f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetPoint("CENTER")
    local ag = f.fs:CreateAnimationGroup()
    local p1 = ag:CreateAnimation("Alpha"); p1:SetFromAlpha(1); p1:SetToAlpha(0.3); p1:SetDuration(0.5); p1:SetOrder(1)
    local p2 = ag:CreateAnimation("Alpha"); p2:SetFromAlpha(0.3); p2:SetToAlpha(1); p2:SetDuration(0.5); p2:SetOrder(2)
    ag:SetLooping("REPEAT"); f.pulse = ag

    local ib = CreateFrame("Button", nil, f); ib:SetSize(24, 24); ib:EnableMouse(true); ib:RegisterForDrag("LeftButton"); ib:Hide()
    ib.tex = ib:CreateTexture(nil, "ARTWORK"); ib.tex:SetAllPoints(); ib.tex:SetTexCoord(unpack(theme.iconInset))
    ib:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Drag to position the icon", theme:AccentHeader()); GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", GameTooltip_Hide)
    ib:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local pf = self:GetParent(); local a, ps = pf._action, pf._pscale or 1
            if not a then return end
            local s = pf:GetEffectiveScale(); local cx, cy = GetCursorPosition()
            local fcx, fcy = pf.fs:GetCenter()
            if fcx and s and s > 0 then
                a.iconX = ((cx / s) - fcx) / ps; a.iconY = ((cy / s) - fcy) / ps
                self:ClearAllPoints(); self:SetPoint("CENTER", pf.fs, "CENTER", a.iconX * ps, a.iconY * ps)
            end
        end)
    end)
    ib:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local pf = self:GetParent(); if pf._onMove then pf._onMove() end
    end)
    f.iconBtn = ib

    -- Bind the data table that drag writes into (fields iconX/iconY) and an onMove hook.
    function f:Bind(action, pscale, onMove) self._action = action; self._pscale = pscale or 1; self._onMove = onMove end
    return f
end

----------------------------------------------------------------------
-- NavRow: a sidebar navigation row - left accent bar + selectable bg + icon + label
-- (+ optional toggle). Used by the Window shell, but exposed for custom sidebars too.
----------------------------------------------------------------------
function Mixin:NavRow(parent, width)
    local theme, C = self, self.C
    local b = CreateFrame("Button", nil, parent); b:SetSize(width or 194, 30)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); UIF.paint(b.bg, C.sidebar)
    b.sel = b:CreateTexture(nil, "ARTWORK"); UIF.paint(b.sel, C.accent)
    b.sel:SetPoint("TOPLEFT"); b.sel:SetPoint("BOTTOMLEFT"); b.sel:SetWidth(3); b.sel:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 12, 0)
    b.tg = theme:Toggle(b); b.tg:SetPoint("RIGHT", -8, 0); b.tg:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(theme.FONT, 12)
    b.fs:SetPoint("LEFT", b.icon, "RIGHT", 8, 0); b.fs:SetPoint("RIGHT", -8, 0); b.fs:SetJustifyH("LEFT")

    -- Attention pulse: a slow accent wash that fades in and out to draw the eye to an important
    -- row. Sits just above the row background (below icon/text) so it reads as a glow, not a mask.
    b.pulse = b:CreateTexture(nil, "BACKGROUND", nil, 1); b.pulse:SetAllPoints()
    UIF.paint(b.pulse, C.accent); b.pulse:SetAlpha(0); b.pulse:Hide()
    b._pulseAG = b.pulse:CreateAnimationGroup(); b._pulseAG:SetLooping("REPEAT")
    local pIn  = b._pulseAG:CreateAnimation("Alpha"); pIn:SetOrder(1);  pIn:SetDuration(0.85)
    pIn:SetFromAlpha(0);    pIn:SetToAlpha(0.30); pIn:SetSmoothing("IN_OUT")
    local pOut = b._pulseAG:CreateAnimation("Alpha"); pOut:SetOrder(2); pOut:SetDuration(0.95)
    pOut:SetFromAlpha(0.30); pOut:SetToAlpha(0);   pOut:SetSmoothing("IN_OUT")
    function b:StartPulse()
        self._wantPulse = true
        if self._sel or self._pulsing then return end   -- selected rows don't pulse
        self._pulsing = true
        UIF.paint(self.pulse, theme.C.accent)           -- re-tint if the theme accent changed
        self.pulse:SetAlpha(0); self.pulse:Show(); self._pulseAG:Play()
    end
    function b:StopPulse(permanent)
        if permanent then self._wantPulse = false end
        self._pulsing = false
        self._pulseAG:Stop(); self.pulse:SetAlpha(0); self.pulse:Hide()
    end

    b:SetScript("OnEnter", function(self) if not self._sel then UIF.paint(self.bg, UIF.mix(theme.C.sidebar, theme.C.accent, 0.28)) end end)
    b:SetScript("OnLeave", function(self) if not self._sel then UIF.paint(self.bg, theme.C.sidebar) end end)
    -- Apply/clear the selected look.
    function b:Select(sel)
        local C = theme.C
        self._sel = sel
        self.sel:SetShown(sel); UIF.paint(self.sel, C.accent)
        UIF.paint(self.bg, sel and UIF.mix(C.sidebar, C.accent, 0.45) or C.sidebar)
        self.fs:SetTextColor(unpack(sel and { 0.98, 0.99, 1 } or C.text))
        -- Pause the attention pulse while selected; resume on deselect if still wanted.
        if sel then self:StopPulse() elseif self._wantPulse then self:StartPulse() end
    end

    -- Compact (icon-only) mode for a collapsed sidebar: hide the label and center the icon.
    function b:SetCompact(compact)
        self._compact = compact and true or false
        self.icon:ClearAllPoints()
        if self._compact then
            self.icon:SetPoint("CENTER", 0, 0); self.fs:Hide()
        else
            self.icon:SetPoint("LEFT", 12, 0); self.fs:Show()
        end
    end
    return b
end
