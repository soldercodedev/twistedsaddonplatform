-- UIFoundry - Tabs.lua
-- TabBar (a row of tab buttons with an active underline) and Accordion (a collapsible
-- header + body). Both styleable.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

----------------------------------------------------------------------
-- TabBar: horizontal tabs. onChange(value) fires on selection.
--   theme:TabBar(parent, { tabs = { {value="a",label="Alpha"}, {value="b",label="Beta"} },
--       value="a", tabWidth=100, height=30, onChange=function(v) end })
----------------------------------------------------------------------
function Mixin:TabBar(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local tw, h = opts.tabWidth or 104, opts.height or 30
    local gap = opts.gap or 4
    local f = CreateFrame("Frame", nil, parent)
    f.value = opts.value
    f.buttons = {}
    for i, t in ipairs(opts.tabs or {}) do
        local b = CreateFrame("Button", nil, f); b:SetSize(tw, h); b:SetPoint("LEFT", (i - 1) * (tw + gap), 0)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        b.underline = b:CreateTexture(nil, "ARTWORK"); b.underline:SetHeight(2); b.underline:SetPoint("BOTTOMLEFT"); b.underline:SetPoint("BOTTOMRIGHT"); b.underline:Hide()
        b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetPoint("CENTER"); theme:StyleFont(b.fs, opts, { textColor = C.subtext }); b.fs:SetText(t.label)
        b._value = t.value
        b:SetScript("OnClick", function() f:SetValue(t.value); if opts.onChange then opts.onChange(t.value) end end)
        b:SetScript("OnEnter", function(self) if self._value ~= f.value then UIF.paint(self.bg, UIF.mix(theme.C.bg, theme.C.accent, 0.12)) end end)
        b:SetScript("OnLeave", function(self) if self._value ~= f.value then UIF.paint(self.bg, theme.C.bg) end end)
        f.buttons[#f.buttons + 1] = b
    end
    f:SetSize(math.max(1, #f.buttons) * (tw + gap) - gap, h)
    function f:SetValue(v)
        self.value = v
        for _, b in ipairs(self.buttons) do
            local on = b._value == v
            b.underline:SetShown(on); UIF.paint(b.underline, theme.C.accent)
            UIF.paint(b.bg, on and UIF.mix(theme.C.bg, theme.C.accent, 0.18) or theme.C.bg)
            b.fs:SetTextColor(unpack(on and { 0.98, 0.99, 1 } or theme.C.subtext))
        end
    end
    f:SetValue(f.value)
    return f
end

----------------------------------------------------------------------
-- Accordion: a clickable header row with a chevron that expands/collapses a body frame you
-- fill (accordion.body). Call :SetExpanded / :Toggle; onToggle(expanded) fires.
--   local ac = theme:Accordion(parent, { title="Advanced", width=560, bodyHeight=120,
--       expanded=false, chevron="...chevron-right.tga", onToggle=fn })
--   theme:Toggle(ac.body):SetPoint("TOPLEFT")
----------------------------------------------------------------------
function Mixin:Accordion(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local w = opts.width or 560
    local headerH = opts.headerHeight or 30
    local f = CreateFrame("Frame", nil, parent); f:SetSize(w, headerH)

    local header = CreateFrame("Button", nil, f); header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(headerH)
    theme:StylePanel(header, UIF.toColor(opts.bg, C.card), UIF.toColor(opts.borderColor, C.border))
    theme:StyleFrame(header, opts)
    local chev = header:CreateFontString(nil, "OVERLAY"); theme:StyleFont(chev, {}, { fontSize = 12, textColor = C.accent }); chev:SetPoint("LEFT", 10, 0)
    if opts.chevron then
        chev:Hide()
        header.chevTex = header:CreateTexture(nil, "ARTWORK"); header.chevTex:SetSize(14, 14); header.chevTex:SetPoint("LEFT", 8, 0)
        header.chevTex:SetTexture(theme:ResolveIcon(opts.chevron) or opts.chevron)
        local ic = C.accent; header.chevTex:SetVertexColor(ic[1], ic[2], ic[3])
    end
    local titleFS = theme:Heading(header, { text = opts.title or "", role = opts.titleRole or "h4" })
    titleFS:SetPoint("LEFT", opts.chevron and 28 or 22, 0)
    f.header, f.chev, f.chevText = header, header.chevTex, chev

    local body = CreateFrame("Frame", nil, f); body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4); body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    body:SetHeight(opts.bodyHeight or 100)
    f.body = body
    f.bodyHeight = opts.bodyHeight or 100

    -- Set the expanded state + visuals. Does NOT fire onToggle (so the initial state and
    -- programmatic changes don't recurse); Toggle() / clicking the header fire it.
    function f:SetExpanded(on)
        self.expanded = on and true or false
        self.body:SetShown(self.expanded)
        if self.chev then self.chev:SetRotation(self.expanded and -math.rad(90) or 0)
        elseif self.chevText then self.chevText:SetText(self.expanded and "v" or ">") end
        self:SetHeight(headerH + (self.expanded and (self.bodyHeight + 4) or 0))
    end
    function f:Toggle()
        self:SetExpanded(not self.expanded)
        if opts.onToggle then opts.onToggle(self.expanded) end
    end
    header:SetScript("OnClick", function() f:Toggle() end)
    header:SetScript("OnEnter", function() theme:FillPaint(header, UIF.mix(theme.C.card, theme.C.accent, 0.10)) end)
    header:SetScript("OnLeave", function() theme:FillPaint(header, UIF.toColor(opts.bg, theme.C.card)) end)
    f:SetExpanded(opts.expanded)
    return f
end
