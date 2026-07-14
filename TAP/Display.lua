-- UIFoundry - Display.lua
-- Presentational components: Badge, Card, StatTile, Separator, Avatar. All styleable.

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
    local variant = opts.variant and (UIF.BADGE_VARIANTS[opts.variant] or nil)
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
        if opts.accentBar ~= false then
            -- Inset the accent bar by the border + corner radius so it stays inside a rounded
            -- card instead of poking out of the corners.
            local bs = theme.borderSize or 1
            local rInset = (theme.radius and theme.radius > 0) and theme.radius or 0
            local bar = f:CreateTexture(nil, "ARTWORK"); bar:SetWidth(3)
            bar:SetPoint("TOPLEFT", bs, -rInset); bar:SetPoint("BOTTOMLEFT", bs, rInset)
            UIF.paint(bar, accentCol); f.accentBar = bar
        end
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
----------------------------------------------------------------------
function Mixin:StatTile(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local f = theme:Card(parent, { width = opts.width or 150, height = opts.height or 72,
        bg = opts.bg, borderColor = opts.borderColor, padding = opts.padding or 12 })
    local label = theme:Heading(f.body, { text = opts.label or "", role = "overline" })
    label:SetPoint("TOPLEFT", 0, 0)
    local value = theme:Heading(f.body, { text = opts.value or "", role = opts.valueRole or "h2", textColor = opts.valueColor })
    value:SetPoint("TOPLEFT", 0, -16)
    f.labelFS, f.valueFS = label, value
    if opts.delta then
        local trendCol = opts.trend == "up" and UIF.BADGE_VARIANTS.success
            or opts.trend == "down" and UIF.BADGE_VARIANTS.danger or C.subtext
        local d = theme:Heading(f.body, { text = opts.delta, role = "caption", textColor = trendCol })
        d:SetPoint("BOTTOMLEFT", 0, 0); f.deltaFS = d
    end
    function f:SetValue(v) self.valueFS:SetText(v) end
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

----------------------------------------------------------------------
-- Avatar: a circular icon/texture tile with an optional ring.
--   theme:Avatar(parent, { texture="Interface\\ICONS\\...", size=48, ring=true })
----------------------------------------------------------------------
function Mixin:Avatar(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local size = opts.size or 40
    local f = CreateFrame("Frame", nil, parent); f:SetSize(size, size)
    if opts.ring ~= false then
        local ring = f:CreateTexture(nil, "BACKGROUND"); ring:SetAllPoints(); UIF.paint(ring, UIF.toColor(opts.ringColor, C.accent))
    end
    local inset = opts.ring == false and 0 or 2
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", inset, -inset); tex:SetPoint("BOTTOMRIGHT", -inset, inset)
    if opts.texture then tex:SetTexture(theme:ResolveIcon(opts.texture) or opts.texture) end
    if tex.SetMask then pcall(tex.SetMask, tex, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    else tex:SetTexCoord(unpack(theme.iconInset)) end
    f.tex = tex
    function f:SetTexture(t) self.tex:SetTexture(theme:ResolveIcon(t) or t) end
    return f
end
