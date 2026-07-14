-- UIFoundry - Style.lua
-- The per-call override system. Almost everything you draw can be restyled at draw time
-- via an `opts` table, so a component call reads like "draw this, but bigger / in this
-- color / with this border". These helpers are the backbone every widget and component
-- routes its styling through.
--
-- STANDARD STYLE KEYS (all optional; a component ignores keys that don't apply):
--   Text:   font (key or path) · fontSize · fontFlags ("OUTLINE"/"THICKOUTLINE"/"") ·
--           textColor · justify ("LEFT"/"CENTER"/"RIGHT") · wrap (bool)
--   Fill:   color (main/fill) · hoverColor · activeColor · bg (panel background)
--   Border: border = { color =, size =, inset = } | false to remove
--   Box:    width · height · alpha
--   Icon:   icon (texture/key) · iconSize · iconColor · iconCoords · iconInset (bool)
--   Misc:   padding · tip = { title, body }
--
-- Colors may be given as { r, g, b } OR a "RRGGBB" hex string anywhere below.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- Normalize a color value ({r,g,b} table or "RRGGBB"/"#RRGGBB" hex) to { r, g, b }.
-- The fallback is normalized the same way, so it may itself be a hex string.
function UIF.toColor(v, fallback)
    if v == nil then v = fallback end
    if type(v) == "table" then return v end
    if type(v) == "string" then
        local r, g, b = UIF.parseHex(v)
        if r then return { r, g, b } end
    end
    return type(fallback) == "table" and fallback or nil
end
local toColor = UIF.toColor

-- Resolve a color spec: a palette key name ("accent"/"success"/...), a hex string, an
-- { r,g,b } table, else the fallback.
function UIF.ThemeMixin:Color(spec, fallback)
    if type(spec) == "string" and self.C[spec] then return self.C[spec] end
    return UIF.toColor(spec, fallback)
end

-- Pull a color from opts[key] (or a list of alias keys), else return the default.
function UIF.optColor(opts, key, default)
    if not opts then return default end
    return toColor(opts[key], default)
end

----------------------------------------------------------------------
-- Font styling for a FontString.
----------------------------------------------------------------------
function Mixin:StyleFont(fs, opts, defaults)
    opts, defaults = opts or {}, defaults or {}
    local font  = opts.font or defaults.font
    local size  = opts.fontSize or defaults.fontSize or 12
    local flags = opts.fontFlags or defaults.fontFlags or ""
    fs:SetFont(font and self:ResolveFont(font) or self.FONT, size, flags)
    local col = toColor(opts.textColor, defaults.textColor or self.C.text)
    fs:SetTextColor(col[1], col[2], col[3], col[4])
    if opts.justify or defaults.justify then fs:SetJustifyH(opts.justify or defaults.justify) end
    if opts.wrap ~= nil then fs:SetWordWrap(opts.wrap and true or false) end
    return fs
end

----------------------------------------------------------------------
-- Border + background overrides for a StylePanel'd frame (uses f._brd / f._fill).
-- opts.border = false removes the border; a table sets its color / thickness / inset.
-- opts.bg sets the fill color.
----------------------------------------------------------------------
function Mixin:StyleFrame(f, opts)
    if not opts then return f end
    if opts.shadow ~= nil then self:AttachShadow(f, opts.shadow) end
    if opts.bg then self:FillPaint(f, opts.bg) end
    if opts.border ~= nil and f._brd then
        if opts.border == false then
            f._brd:Hide()
        else
            f._brd:Show()
            local bd = opts.border
            UIF.paint(f._brd, toColor(bd.color, self.C.border))
            local inset = bd.size or 1
            if f._fill then
                f._fill:ClearAllPoints()
                f._fill:SetPoint("TOPLEFT", inset, -inset); f._fill:SetPoint("BOTTOMRIGHT", -inset, inset)
            end
        end
    end
    return f
end

-- Paint a texture as a solid fill OR a 9-sliced rounded-rect (tinted), so any element can
-- have square / rounded / pill corners. `spec` is a radius number, "pill", a corner name,
-- or nil (solid). When w/h are given, the slice margin is fitted so short elements (badges)
-- round correctly instead of over-slicing.
function Mixin:PaintShape(tex, color, spec, w, h, alpha)
    local col = UIF.toColor(color, self.C.accent)
    local shapeTex, margin = self:ShapeTexture(spec)
    if shapeTex then
        if w and h then margin = math.max(2, math.min(margin, math.floor(math.min(w, h) / 2))) end
        tex:SetTexture(shapeTex)
        if tex.SetTextureSliceMargins then
            pcall(tex.SetTextureSliceMargins, tex, margin, margin, margin, margin)
            if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
                pcall(tex.SetTextureSliceMode, tex, Enum.UITextureSliceMode.Stretched)
            end
        end
        tex:SetVertexColor(col[1], col[2], col[3], alpha or 1)
    else
        tex:SetVertexColor(1, 1, 1)
        if tex.SetTextureSliceMargins then pcall(tex.SetTextureSliceMargins, tex, 0, 0, 0, 0) end
        tex:SetColorTexture(col[1], col[2], col[3], alpha or 1)
    end
end

-- Attach (or update / remove) a soft drop shadow behind a frame, so it pops off the page.
--   spec: true, or { spread, offsetX, offsetY, alpha, color }.  false / nil removes it.
local SHADOW_MARGIN = 24
function Mixin:AttachShadow(frame, spec)
    local sh = frame._uifShadow
    if not spec then if sh then sh:Hide() end return end
    if spec == true then spec = {} end
    local spread = spec.spread or 6
    local ox, oy = spec.offsetX or 0, spec.offsetY or -3
    local col = UIF.toColor(spec.color, { 0, 0, 0 })
    local alpha = spec.alpha or 0.38
    if not sh then sh = frame:CreateTexture(nil, "BACKGROUND", nil, -8); frame._uifShadow = sh end
    if self.shapeDir then
        sh:SetTexture(self.shapeDir .. "shadow.tga")
        if sh.SetTextureSliceMargins then
            pcall(sh.SetTextureSliceMargins, sh, SHADOW_MARGIN, SHADOW_MARGIN, SHADOW_MARGIN, SHADOW_MARGIN)
            if sh.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(sh.SetTextureSliceMode, sh, Enum.UITextureSliceMode.Stretched) end
        end
        sh:SetVertexColor(col[1], col[2], col[3], alpha)
    else
        sh:SetColorTexture(col[1], col[2], col[3], alpha * 0.5)
    end
    sh:ClearAllPoints()
    sh:SetPoint("TOPLEFT", frame, "TOPLEFT", -spread + ox, spread + oy)
    sh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spread + ox, -spread + oy)
    sh:Show()
    return sh
end

-- Convenience: build a bordered + filled panel in one call with full style control.
--   theme:Panel(parent, { bg = "1A1D24", border = { color = "2E3440", size = 1 }, width=, height= })
function Mixin:Panel(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    self:StylePanel(f, UIF.toColor(opts.bg, self.C.panel), UIF.toColor(opts.borderColor, self.C.border))
    if opts.width or opts.height then f:SetSize(opts.width or 100, opts.height or 100) end
    self:StyleFrame(f, opts)
    return f
end
