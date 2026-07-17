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
-- NavBar: a horizontal navigation strip of segmented buttons - one per item, one marked active -
-- meant to dock across the top of a body/content frame. Each item is an optional ICON plus a label.
-- By default the buttons fill the given width evenly (pass tabWidth to fix their size). Pooled +
-- reconfigurable, so redrawing it every frame is cheap.
--   local nav = theme:NavBar(parent)
--   nav:Configure({ items = { {key="overview", label="Overview", icon="layout-grid"}, ... },
--       active = "overview", width = 700, onSelect = function(key) ... end,
--       tip = function(key) return TIPS[key] end })
--   local h = nav:GetHeight()   -- for laying out content below it
----------------------------------------------------------------------
function Mixin:NavBar(parent)
    local theme = self
    local f = CreateFrame("Frame", nil, parent)
    f.buttons = {}
    f.line = f:CreateTexture(nil, "ARTWORK"); f.line:SetHeight(2)

    function f:Configure(opts)
        opts = opts or {}
        local items = opts.items or {}
        local n = #items
        local gap = opts.gap or 4
        local h = opts.height or 28
        local width = opts.width or (parent.GetWidth and parent:GetWidth()) or 600
        local tw = opts.tabWidth or math.max(40, math.floor((width - math.max(0, n - 1) * gap) / math.max(1, n)))
        -- Hide any pooled buttons beyond the current item count.
        for i = n + 1, #self.buttons do self.buttons[i]:Hide() end
        for i, it in ipairs(items) do
            local btn = self.buttons[i]
            if not btn then btn = theme:Button(self); self.buttons[i] = btn end
            local active = (it.key == opts.active)
            btn:Configure(it.label, tw, h, active and "primary" or "default",
                function() if opts.onSelect then opts.onSelect(it.key) end end,
                it.icon and { icon = it.icon, iconSize = it.iconSize or 14 } or nil)
            btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", (i - 1) * (tw + gap), 0); btn:Show()
            if theme.SetTip then theme:SetTip(btn, it.label, (opts.tip and opts.tip(it.key)) or it.label) end
        end
        f:SetSize(math.max(1, width), h + 8)
        -- Accent baseline across the whole bar (the "docked header" underline).
        f.line:ClearAllPoints(); f.line:SetPoint("TOPLEFT", 0, -h - 2); f.line:SetWidth(math.max(1, width))
        UIF.paint(f.line, theme.C.accent); f.line:SetAlpha(0.5); f.line:Show()
    end
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
