-- UIFoundry - Display.lua
-- Presentational components: Badge, Card, StatTile, Separator. All styleable.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- Named badge variants map to a fill; text color is chosen for contrast (or overridden).
UIF.BADGE_VARIANTS = {
    accent  = "accent",
    neutral = { 0.30, 0.33, 0.40 },
    success = { 0.13, 0.53, 0.33 },
    warning = { 0.72, 0.53, 0.20 },
    danger  = { 0.55, 0.20, 0.22 },
    info    = { 0.05, 0.55, 0.75 },
}

-- A 3px left accent bar, inset by the border + corner radius so it stays inside a rounded card
-- instead of poking out of the corners. Shared by Card and StatTile (stored as frame.accentBar).
function Mixin:_accentBar(frame, color, width)
    local bs = self.borderSize or 1
    local rInset = (self.radius and self.radius > 0) and self.radius or 0
    local bar = frame:CreateTexture(nil, "ARTWORK"); bar:SetWidth(width or 3)
    bar:SetPoint("TOPLEFT", bs, -rInset); bar:SetPoint("BOTTOMLEFT", bs, rInset)
    UIF.paint(bar, color); frame.accentBar = bar
    return bar
end

-- Wire a hover tooltip onto a frame from opts.tipData (rich) or opts.tip = { title, body, anchor }.
-- Card-based components aren't mouse-enabled by default, so this enables the mouse too.
function Mixin:_wireTip(frame, opts)
    if not (opts.tipData or opts.tip) then return end
    frame:EnableMouse(true)
    if opts.tipData then self:SetTipData(frame, opts.tipData)
    else self:SetTip(frame, opts.tip.title, opts.tip.body, opts.tip.anchor) end
    frame:SetScript("OnEnter", function(s) self:_showTip(s) end)
    frame:SetScript("OnLeave", function() GameTooltip_Hide() end)
end

----------------------------------------------------------------------
-- Badge / pill / tag. opts.variant picks a preset fill; opts.color overrides it.
--   theme:Badge(parent, { text = "NEW", variant = "success", dot = true })
--   theme:Badge(parent, { text = "12", color = "6610F2", textColor = "FFFFFF", pill = true })
----------------------------------------------------------------------
-- opts: text · variant · color · textColor · dot/dotColor · padding · width · height · alpha ·
--       pill (bool, fully rounded) · radius (number) · corner ("sm"/"md"/"lg"/"pill"/"square")
function Mixin:Badge(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local variant = UIF.BADGE_VARIANTS[opts.variant or "accent"] or C.accent
    local fill = UIF.toColor(opts.color, type(variant) == "string" and C[variant] or variant)
    local f = CreateFrame("Frame", nil, parent)
    local borderTex = f:CreateTexture(nil, "BACKGROUND", nil, -1); borderTex:SetAllPoints(); borderTex:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); f.bg = bg
    local pad = opts.padding or 8
    local dot
    if opts.dot then
        dot = f:CreateTexture(nil, "ARTWORK"); dot:SetSize(5, 5); dot:SetPoint("LEFT", pad, 0)
        UIF.paint(dot, UIF.toColor(opts.dotColor, { 1, 1, 1 }))
    end
    local fs = f:CreateFontString(nil, "OVERLAY")
    theme:StyleFont(fs, opts, { fontSize = 10, textColor = { 1, 1, 1 } })
    fs:SetText(opts.text or "")
    fs:SetPoint("LEFT", dot and (pad + 9) or pad, 0)
    local w = opts.width or (fs:GetStringWidth() + pad * 2 + (dot and 9 or 0))
    local h = opts.height or 16
    f:SetSize(w, h)
    -- Solid, rounded, or pill corners (default to the theme/skin radius).
    local spec = opts.pill and "pill" or opts.radius or opts.corner or theme.radius
    if opts.border then
        local bd = opts.border == true and {} or opts.border
        local bsz = bd.size or theme.borderSize or 1
        theme:PaintShape(borderTex, theme:Color(bd.color, C.border), spec, w, h)
        borderTex:Show()
        bg:ClearAllPoints(); bg:SetPoint("TOPLEFT", bsz, -bsz); bg:SetPoint("BOTTOMRIGHT", -bsz, bsz)
    end
    theme:PaintShape(bg, fill, spec, w, h, opts.alpha)
    if opts.shadow ~= nil then theme:AttachShadow(f, opts.shadow) end
    f.fs = fs
    function f:SetText(t) self.fs:SetText(t) end
    return f
end

----------------------------------------------------------------------
-- Card: a bordered container with optional header title/subtitle and a body region you
-- parent your own content to (card.body). Everything styleable.
--   local card = theme:Card(parent, { width=300, height=160, title="Stats", subtitle="today" })
--   local btn = theme:Button(card.body); btn:SetPoint("TOPLEFT", 0, 0)
----------------------------------------------------------------------
-- opts: width · height · padding · bg · borderColor · title · subtitle · titleRole ·
--       variant (accent/success/warning/danger/info/neutral) · color/accentColor ·
--       accentBar (default true when titled) · footer (bool) · footerHeight
-- Regions: card.body (fill), card.header (when titled), card.footer (when footer set).
function Mixin:Card(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    -- Colored variants tint the background and color the accent bar / title.
    local variant = opts.variant and UIF.BADGE_VARIANTS[opts.variant]
    local accentCol = UIF.toColor(opts.color or opts.accentColor,
        variant and (type(variant) == "string" and C[variant] or variant) or C.accent)
    local bgCol = UIF.toColor(opts.bg, opts.variant and UIF.mix(C.card, accentCol, 0.12) or C.card)

    local f = CreateFrame("Frame", nil, parent); f:SetSize(opts.width or 300, opts.height or 160)
    theme:StylePanel(f, bgCol, UIF.toColor(opts.borderColor, C.border))
    theme:StyleFrame(f, opts)
    local pad = opts.padding or 14
    local topPad, botPad = pad, pad

    if opts.title then
        local hdr = CreateFrame("Frame", nil, f); hdr:SetPoint("TOPLEFT", 0, 0); hdr:SetPoint("TOPRIGHT", 0, 0); f.header = hdr
        -- On a colored (tinted) card, brighten the title toward white so it pops against the
        -- tint instead of blending in; the accent bar keeps the true variant color.
        local titleCol = opts.variant and UIF.mix(accentCol, { 1, 1, 1 }, 0.45) or opts.titleColor
        local t = theme:Heading(hdr, { text = opts.title, role = opts.titleRole or "h4", textColor = titleCol })
        t:SetPoint("TOPLEFT", pad, -pad); f.title = t
        topPad = pad + 22
        if opts.subtitle then
            local s = theme:Heading(hdr, { text = opts.subtitle, role = "caption" })
            s:SetPoint("TOPLEFT", pad, -pad - 20); f.subtitle = s
            topPad = pad + 38
        end
        hdr:SetHeight(topPad)
        if opts.accentBar ~= false then theme:_accentBar(f, accentCol) end
    end

    if opts.footer then
        -- Footer content strip, inset by `pad` on left / right / bottom, with a divider above it.
        local fContent = opts.footerHeight or 26
        local foot = CreateFrame("Frame", nil, f)
        foot:SetPoint("BOTTOMLEFT", pad, pad); foot:SetPoint("BOTTOMRIGHT", -pad, pad); foot:SetHeight(fContent)
        local div = f:CreateTexture(nil, "ARTWORK"); div:SetHeight(1)
        div:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 8); div:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 8)
        div:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.7)
        f.footer = foot; botPad = pad + fContent + 12
    end

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", pad, -topPad); body:SetPoint("BOTTOMRIGHT", -pad, botPad)
    f.body = body
    return f
end

----------------------------------------------------------------------
-- StatTile: a small KPI tile - big value, label, optional trend/delta.
--   theme:StatTile(parent, { label="DPS", value="128.4k", delta="+12%", trend="up",
--       width=150, height=72 })
--
-- Metric coloring (opt-in): pass `accent` = a color (hex/{r,g,b}) to draw a subtle 3px
-- left accent bar, tint the 1px border toward it, and (unless overridden) color the value
-- and icon with it - the pattern the Mythic Ledger hero tiles use.
--   opts: icon (bundled icon name) · iconVariant · iconColor (defaults to accent/value) ·
--         iconSize · accent · valueColor · valueRole · hero (bold/flashy treatment) ·
--         tip = { title, body } · tipData = { icon, title, lines } (rich, see Tooltip.lua)
--
-- `hero = true` (used with `accent`) gives the bold look: the icon sits in a SOLID metric
-- badge with a knocked-out glyph, the value is large with a soft metric glow, the card carries
-- a faint metric wash + tinted border, and (when `meter` is a 0..1 fraction) a colored rank
-- meter bar runs along the bottom showing where the value sits on its scale.
----------------------------------------------------------------------
-- Three opt-in card styles (opts.style) sharing one formula - label / big value / supporting
-- subtext / icon - with distinct treatments. Used by the Mythic Ledger Overview (chosen in its
-- Settings); any caller that omits opts.style gets the original behavior below untouched.
--   "clean"   - flat card, thin accent-tinted border, minimal corner glyph, one subtext line
--   "panel"   - darker "stone" card, framed accent icon badge, value glow, accent gem + rank meter
--   "compact" - flat card, big value, a two-line data footer (Best / range / last-N / this week)
local function styledStatTile(theme, parent, opts)
    local C = theme.C
    local accent = opts.accent and UIF.toColor(opts.accent) or UIF.toColor(C.accent) or { 0.6, 0.62, 0.7 }
    local style = opts.style
    local w = opts.width or 150
    local pad = opts.padding or 12
    local h = opts.height or ((style == "panel" and 100) or (style == "compact" and 104) or 96)

    -- Card ground + border per style.
    local bg, borderCol
    if style == "panel" then
        bg = UIF.mix(C.card, { 0, 0, 0 }, 0.22)             -- darker stone/metal
        borderCol = UIF.mix(C.border, accent, 0.55)
    elseif style == "compact" then
        bg = C.card
        borderCol = UIF.mix(C.border, accent, 0.30)
    else -- clean
        bg = C.card
        borderCol = UIF.mix(C.border, accent, 0.42)         -- thin accent-tinted border
    end
    local f = theme:Card(parent, { width = w, height = h, bg = bg, borderColor = borderCol, padding = pad })
    local body, bodyW = f.body, w - 2 * pad

    -- Header: icon (framed badge for panel, minimal corner glyph otherwise) + label.
    local labelX = 0
    if opts.icon then
        if style == "panel" then
            local badge = 26
            local frame = body:CreateTexture(nil, "ARTWORK", nil, 1)
            frame:SetSize(badge, badge); frame:SetPoint("TOPLEFT", 0, 0)
            theme:PaintShape(frame, UIF.mix(C.card, accent, 0.40), opts.badgeShape or "md", badge, badge, 1)
            local g = theme:Glyph(body, { icon = opts.icon, variant = opts.iconVariant, size = 15,
                color = UIF.mix(accent, { 1, 1, 1 }, 0.15) })
            g:SetPoint("CENTER", frame, "CENTER", 0, 0); f.iconGlyph = g
            labelX = badge + 8
        else
            local isz = opts.iconSize or 14
            local g = theme:Glyph(body, { icon = opts.icon, variant = opts.iconVariant, size = isz,
                color = opts.iconColor or UIF.mix(C.subtext, accent, 0.5) })
            -- A large icon fills the right side of the card (hero style); a small one tucks top-right.
            if isz >= 30 then g:SetPoint("RIGHT", 4, 0) else g:SetPoint("TOPRIGHT", 0, -1) end
            f.iconGlyph = g
        end
    end
    local label = theme:Heading(body, { text = opts.label or "", role = "overline" })
    label:SetPoint("TOPLEFT", labelX, (style == "panel") and -2 or 0)

    -- Big value.
    local value = theme:Heading(body, { text = opts.value or "", role = "h1", textColor = opts.valueColor or accent })
    value:SetPoint("TOPLEFT", labelX, (style == "panel") and -20 or -19)
    if style == "panel" and value.SetShadowColor then
        value:SetShadowColor(accent[1], accent[2], accent[3], 0.55); value:SetShadowOffset(0, 0)
    end
    f.valueFS = value

    -- Supporting subtext: compact stacks up to two footer lines; clean/panel show one sub line.
    if style == "compact" then
        local fy, foot = 1, opts.footer or {}
        for i = math.min(#foot, 2), 1, -1 do
            local ln = foot[i]
            if ln and ln ~= "" then
                local fs = theme:Heading(body, { text = ln, role = "caption", textColor = C.subtext })
                fs:SetPoint("BOTTOMLEFT", 0, fy); fs:SetWidth(bodyW); fs:SetJustifyH("LEFT")
                fy = fy + 14
            end
        end
    elseif opts.sub then
        local fs = theme:Heading(body, { text = opts.sub, role = "caption", textColor = C.subtext })
        fs:SetPoint("BOTTOMLEFT", 0, 1); fs:SetWidth(bodyW); fs:SetJustifyH("LEFT")
    end

    -- Panel extra: a small accent "gem" (rotated square) in the top-right corner.
    if style == "panel" then
        local gem = body:CreateTexture(nil, "OVERLAY")
        gem:SetSize(9, 9); gem:SetPoint("TOPRIGHT", -1, -2)
        UIF.paint(gem, accent); gem:SetRotation(0.7854); f.gem = gem   -- 45deg -> diamond
    end

    theme:_wireTip(f, opts)   -- rich tipData wins over simple tip; Card frames aren't mouse-enabled
    f.labelFS = label
    return f
end

function Mixin:StatTile(parent, opts)
    opts = opts or {}
    if opts.style then return styledStatTile(self, parent, opts) end
    local theme, C = self, self.C
    -- The accent color drives the border tint, the badge/meter, and (by default) the value.
    local accent = opts.accent and UIF.toColor(opts.accent) or nil
    local hero = opts.hero and accent or nil
    local borderCol = opts.borderColor
    if accent and borderCol == nil then borderCol = UIF.mix(C.border, accent, hero and 0.55 or 0.35) end
    local valueCol = opts.valueColor
    if valueCol == nil and accent then valueCol = accent end
    -- Hero cards get a faint metric wash so they read as "colored" without a solid fill.
    local bgCol = opts.bg
    if bgCol == nil and hero then bgCol = UIF.mix(C.card, accent, 0.10) end

    local pad = opts.padding or 12
    local f = theme:Card(parent, { width = opts.width or 150, height = opts.height or 72,
        bg = bgCol, borderColor = borderCol, padding = pad })

    -- Non-hero: subtle left accent bar. Hero uses the solid badge instead (below).
    if accent and not hero then theme:_accentBar(f, accent, opts.accentWidth or 3) end

    -- Header: optional icon (a SOLID metric badge with a knockout glyph in hero mode) + label.
    local labelX, labelDY = 0, 0
    if opts.icon then
        local isz = opts.iconSize or (hero and 18 or 14)
        if hero then
            local badge = isz + 16
            local bTex = f.body:CreateTexture(nil, "ARTWORK", nil, 1)
            bTex:SetSize(badge, badge); bTex:SetPoint("TOPLEFT", 0, -1)
            theme:PaintShape(bTex, accent, opts.badgeShape or "md", badge, badge, 1); f.iconChip = bTex
            local g = theme:Glyph(f.body, { icon = opts.icon, variant = opts.iconVariant,
                size = isz, color = opts.iconColor or UIF.mix(C.card, { 0, 0, 0 }, 0.35) })
            g:SetPoint("CENTER", bTex, "CENTER", 0, 0); f.iconGlyph = g
            labelX = badge + 10; labelDY = -3
        else
            local g = theme:Glyph(f.body, { icon = opts.icon, variant = opts.iconVariant,
                size = isz, color = opts.iconColor or valueCol or C.subtext })
            g:SetPoint("TOPLEFT", 0, -1); f.iconGlyph = g
            labelX = isz + 6
        end
    end
    local label = theme:Heading(f.body, { text = opts.label or "", role = "overline" })
    label:SetPoint("TOPLEFT", labelX, labelDY)

    local value = theme:Heading(f.body, { text = opts.value or "",
        role = opts.valueRole or (hero and "h1" or "h2"), textColor = valueCol })
    if hero then value:SetPoint("TOPLEFT", labelX, -18) else value:SetPoint("BOTTOMLEFT", 0, 0) end
    -- Soft metric glow behind the value (a colored text shadow), only on hero cards.
    if hero and value.SetShadowColor then
        value:SetShadowColor(accent[1], accent[2], accent[3], 0.6)
        value:SetShadowOffset(0, 0)
    end
    f.labelFS, f.valueFS = label, value

    -- Rank meter along the bottom (hero + a 0..1 fraction): a dark track with a metric-filled
    -- portion showing where the value sits on its scale. Bold, and it reads at a glance.
    if hero and type(opts.meter) == "number" then
        local frac = opts.meter; if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        local mh = opts.meterHeight or 6
        local bodyW = (opts.width or 150) - 2 * pad
        local track = f.body:CreateTexture(nil, "ARTWORK", nil, 1)
        track:SetHeight(mh); track:SetPoint("BOTTOMLEFT", 0, 0); track:SetPoint("BOTTOMRIGHT", 0, 0)
        theme:PaintShape(track, UIF.mix(C.card, { 0, 0, 0 }, 0.35), "pill", bodyW, mh, 0.9)
        local fill = f.body:CreateTexture(nil, "ARTWORK", nil, 2)
        fill:SetHeight(mh); fill:SetPoint("BOTTOMLEFT", 0, 0); fill:SetWidth(math.max(mh, frac * bodyW))
        theme:PaintShape(fill, accent, "pill", bodyW, mh, 1)
        f.meterTrack, f.meterFill = track, fill
    end

    if opts.delta then
        local trendCol = opts.trend == "up" and UIF.BADGE_VARIANTS.success
            or opts.trend == "down" and UIF.BADGE_VARIANTS.danger or C.subtext
        local d = theme:Heading(f.body, { text = opts.delta, role = "caption", textColor = trendCol })
        d:SetPoint("BOTTOMRIGHT", 0, hero and 10 or 2); f.deltaFS = d
    end

    theme:_wireTip(f, opts)   -- rich tipData wins over simple tip; Card frames aren't mouse-enabled

    return f
end

----------------------------------------------------------------------
-- Separator: a line, horizontal (default) or vertical, with an optional centered label.
--   theme:Separator(parent, { width=400, label="OR", color="2E3440" })
--   theme:Separator(parent, { vertical=true, height=40 })
----------------------------------------------------------------------
function Mixin:Separator(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local col = UIF.toColor(opts.color, C.border)
    local thick = opts.thickness or 1
    local f = CreateFrame("Frame", nil, parent)
    if opts.vertical then
        f:SetSize(thick, opts.height or 40)
        local line = f:CreateTexture(nil, "ARTWORK"); line:SetAllPoints(); UIF.paint(line, col, opts.alpha or 0.8)
    else
        local w = opts.width or 400
        f:SetSize(w, math.max(thick, opts.label and 14 or thick))
        if opts.label then
            local fs = theme:Heading(f, { text = opts.label, role = "overline", textColor = opts.textColor })
            fs:SetPoint("CENTER"); fs:SetJustifyH("CENTER")
            local lw = fs:GetStringWidth() + 16
            local l = f:CreateTexture(nil, "ARTWORK"); l:SetHeight(thick); l:SetPoint("LEFT"); l:SetPoint("RIGHT", f, "CENTER", -lw / 2, 0); UIF.paint(l, col, opts.alpha or 0.8)
            local r = f:CreateTexture(nil, "ARTWORK"); r:SetHeight(thick); r:SetPoint("RIGHT"); r:SetPoint("LEFT", f, "CENTER", lw / 2, 0); UIF.paint(r, col, opts.alpha or 0.8)
        else
            local line = f:CreateTexture(nil, "ARTWORK"); line:SetHeight(thick); line:SetPoint("LEFT"); line:SetPoint("RIGHT"); UIF.paint(line, col, opts.alpha or 0.8)
        end
    end
    return f
end

