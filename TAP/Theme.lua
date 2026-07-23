-- TAP - Theme.lua
-- A Theme is the central object: it owns a palette (with a live-mutable accent), the UI
-- font, and every widget / picker / window factory (added as ThemeMixin methods across
-- the other files). Create one per addon so each tool can carry its own accent while
-- sharing all the component code.

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

-- Flat dark base palette with a Bootstrap-primary accent (a few shades darker).
TAP.DEFAULT_PALETTE = {
    bg      = { 0.09, 0.10, 0.12 },
    sidebar = { 0.11, 0.12, 0.15 },
    panel   = { 0.13, 0.14, 0.17 },
    card    = { 0.17, 0.19, 0.23 },
    hover   = { 0.22, 0.25, 0.30 },
    border  = { 0.26, 0.29, 0.35 },
    accent  = { 0.04, 0.34, 0.79 },
    text    = { 0.90, 0.92, 0.95 },
    subtext = { 0.56, 0.60, 0.68 },
}

----------------------------------------------------------------------
-- NewTheme
----------------------------------------------------------------------
-- opts = {
--   name        = "MyAddon"      -- prefixes the library's global frame names; give a
--                                   unique value per addon so pickers/dialogs don't clash.
--   accent      = { r, g, b }    -- accent color (overrides the palette accent)
--   palette     = { key = {r,g,b}, ... }  -- override any base palette entries
--   font        = "path\\to.ttf" -- UI font (probed; falls back to STANDARD_TEXT_FONT)
--   fonts       = { { key=, label=, path= }, ... }  -- optional registry for Preview/font dropdowns
--   iconInset   = { l, r, t, b } -- default TexCoord crop for game icons
--   onAccent    = function(theme) end  -- called after ApplyAccent (rethemes live widgets)
-- }
function TAP:NewTheme(opts)
    opts = opts or {}
    local theme = setmetatable({}, { __index = TAP.ThemeMixin })

    -- A skin (TAP.SKINS[name]) supplies palette + shape tokens; opts override it.
    local skin = opts.skin and TAP.SKINS and TAP.SKINS[opts.skin] or nil
    local C = {}
    for k, v in pairs(TAP.DEFAULT_PALETTE) do C[k] = { v[1], v[2], v[3] } end
    if skin and skin.palette then for k, v in pairs(skin.palette) do C[k] = { v[1], v[2], v[3] } end end
    if opts.palette then for k, v in pairs(opts.palette) do C[k] = { v[1], v[2], v[3] } end end
    if skin and skin.accent then C.accent = { skin.accent[1], skin.accent[2], skin.accent[3] } end
    if opts.accent then C.accent = { opts.accent[1], opts.accent[2], opts.accent[3] } end
    theme.C = C

    -- Shape tokens (default corner radius + border weight for panels/buttons/inputs).
    theme.radius     = opts.radius or (skin and skin.radius) or 0
    theme.borderSize = opts.borderSize or (skin and skin.borderSize) or 1
    theme.winRadius  = opts.winRadius or (skin and skin.winRadius) or theme.radius

    theme.id        = opts.name or TAP.NextId("TAPTheme")
    theme.fonts     = opts.fonts or TAP.DEFAULT_FONTS   -- font registry (bundled set by default)
    -- Default asset dirs point at TAP's own bundled art, so icons / shapes / fonts work
    -- out of the box. A consumer that copies the assets into its own addon overrides these.
    theme.iconDir   = opts.iconDir  or "Interface\\AddOns\\TAP\\assets\\icons\\"
    theme.shapeDir  = opts.shapeDir or "Interface\\AddOns\\TAP\\assets\\shapes\\"
    theme.soundDir  = opts.soundDir or "Interface\\AddOns\\TAP\\Sounds\\"
    theme.sceneDir  = opts.sceneDir or "Interface\\AddOns\\TAP\\assets\\scenes\\"
    theme.sounds    = opts.sounds   -- optional sound catalog override (defaults to TAP.SOUNDS)
    theme.iconInset = opts.iconInset or TAP.ICON_INSET
    -- UI font: there is NO per-theme / per-skin font. Every theme uses the ONE global font choice
    -- (TAP._globalFontSpec, driven by the appearance page via TAP.SetGlobalFont); until that's set we
    -- use the framework default. Storing _fontSpec lets :ApplyFont() re-resolve after login - a
    -- first-launch fallback (before WoW indexes the bundled TTF) then corrects itself. `opts.font` /
    -- `skin.font` are intentionally ignored so a theme/skin can never fight the selected font.
    theme._fontSpec = TAP._globalFontSpec or TAP.DEFAULT_FONT_KEY or "UBUNTU"
    theme.FONT      = TAP.ResolveFontFile(theme:ResolveFont(theme._fontSpec))
    theme._onAccent = opts.onAccent
    theme._onFont   = opts.onFont
    theme:_updateAccentCode()

    -- Register every theme so a global font re-resolution can reach it (module addons each make
    -- their own theme; without this only the hub's font would correct after login).
    TAP._themes = TAP._themes or {}
    TAP._themes[#TAP._themes + 1] = theme

    -- Bound closure so widgets can wire OnEnter directly to the theme's tooltip.
    theme.showTip = function(f) theme:_showTip(f) end

    return theme
end

----------------------------------------------------------------------
-- Accent-derived helpers
----------------------------------------------------------------------
-- A brightened accent so tooltip headers / highlights stay readable on the dark tooltip
-- background even when the user's accent is a dark shade.
function Mixin:AccentHeader()
    local a = self.C.accent
    return math.min(1, a[1] * 1.3 + 0.30), math.min(1, a[2] * 1.3 + 0.30), math.min(1, a[3] * 1.3 + 0.30)
end

-- Inline accent color code (lightened). Author highlights in text as the |cffffffff
-- placeholder and call HL() to swap it for the live theme accent when rendering, so key
-- words pop in accent instead of white-on-white.
function Mixin:_updateAccentCode()
    local r, g, b = self:AccentHeader()
    self._accentCode = string.format("|cff%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function Mixin:HL(s)
    if not s then return s end
    return (s:gsub("|cffffffff", self._accentCode))
end

-- Recolor the accent live (mutates C.accent in place so later widget rebuilds pick it up),
-- refresh the highlight code, and fire the consumer's onAccent hook to retheme live frames.
function Mixin:ApplyAccent(rgb)
    if rgb then
        self.C.accent[1], self.C.accent[2], self.C.accent[3] = rgb[1], rgb[2], rgb[3]
    end
    self:_updateAccentCode()
    if self._onAccent then self._onAccent(self) end
end

-- Re-resolve this theme's UI font (from a new spec, or the stored one) and fire the onFont hook so
-- live frames can re-apply it. Safe to call repeatedly - the point is that a bundled TTF may not be
-- loadable until after login, so a first-launch fallback (Friz) corrects itself when this re-runs.
function Mixin:ApplyFont(spec)
    if spec ~= nil then self._fontSpec = spec end
    local resolved = TAP.ResolveFontFile(self:ResolveFont(self._fontSpec or "UBUNTU"))
    local changed = (resolved ~= self.FONT)
    self.FONT = resolved
    if self._onFont then pcall(self._onFont, self, changed) end
    return resolved, changed
end

-- Set the global UI (chrome) font for EVERY registered theme, re-resolve, and fire each onFont hook.
-- The hub owns this choice; module addons each build their own theme, and their config panels create
-- fontstrings from their own theme.FONT - so without this a non-default global font would leave module
-- chrome on the bundled default (the "mixed / fell-back font" bug). Per-widget fonts (a specific
-- alert's font, the rotation keybind font) are set explicitly elsewhere and are NOT touched.
--   spec = a font key/path to push to all themes; nil = just re-resolve each from its stored spec
--   (used on login, once WoW has finished indexing bundled TTFs, to correct a first-launch fallback).
function TAP.SetGlobalFont(spec)
    if spec ~= nil then TAP._globalFontSpec = spec end   -- remember it so themes created LATER adopt it
    for _, t in ipairs(TAP._themes or {}) do pcall(t.ApplyFont, t, spec) end
end

----------------------------------------------------------------------
-- Tooltip system: any frame with ._tipTitle set shows help on hover.
----------------------------------------------------------------------
function Mixin:_showTip(f)
    if not f._tipTitle then return end
    GameTooltip:SetOwner(f, f._tipAnchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(f._tipTitle, self:AccentHeader())   -- accent-colored header
    if f._tipBody then GameTooltip:AddLine(self:HL(f._tipBody), 0.82, 0.86, 0.92, true) end
    GameTooltip:Show()
end

-- Attach a hover tooltip to any frame (returns the frame for call chaining).
-- The widget factories already wire OnEnter/OnLeave to the theme tooltip, so this only
-- needs to set the strings.
function Mixin:SetTip(frame, title, body, anchor)
    if frame then frame._tipTitle, frame._tipBody, frame._tipAnchor = title, body, anchor end
    return frame
end

----------------------------------------------------------------------
-- Panel skin: a 1px border texture + inset fill on any frame.
-- Stores the two textures as frame._brd / frame._fill so widgets can recolor the fill on
-- hover (the Dropdown, cards, etc. all rely on these field names).
----------------------------------------------------------------------
-- 9-slice helpers (shared; defined as TAP.applySlice / TAP.clearSlice in Core.lua).
local applySlice, clearSlice = TAP.applySlice, TAP.clearSlice

-- Skin a frame as a bordered, filled panel. When the theme (or the `radius` arg) requests
-- rounded corners AND a shape texture is available, the border + fill are drawn as 9-sliced
-- rounded-rect textures (tinted); otherwise the classic square 1px-border + inset-fill.
-- Stores f._rounded so hover recolors know whether to SetVertexColor (rounded) or
-- SetColorTexture (square) - use theme:FillPaint / theme:EdgePaint for that.
function Mixin:StylePanel(f, fill, edge, radius)
    local C = self.C
    fill, edge = TAP.toColor(fill, C.panel), TAP.toColor(edge, C.border)
    radius = radius or self.radius or 0
    local bs = self.borderSize or 1
    local b = f._brd or f:CreateTexture(nil, "BACKGROUND", nil, 0); f._brd = b
    local g = f._fill or f:CreateTexture(nil, "BACKGROUND", nil, 1); f._fill = g
    b:SetAllPoints()
    g:ClearAllPoints(); g:SetPoint("TOPLEFT", bs, -bs); g:SetPoint("BOTTOMRIGHT", -bs, bs)
    f._fillColor, f._edgeColor = fill, edge

    local shapeTex, margin
    if radius and radius > 0 then shapeTex, margin = self:ShapeTexture(radius) end
    if shapeTex then
        f._rounded = true
        b:SetTexture(shapeTex); applySlice(b, margin); b:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1)
        g:SetTexture(shapeTex); applySlice(g, math.max(1, margin - bs)); g:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
    else
        f._rounded = false
        b:SetVertexColor(1, 1, 1); clearSlice(b); TAP.paint(b, edge)
        g:SetVertexColor(1, 1, 1); clearSlice(g); TAP.paint(g, fill)
    end
    return f
end

-- Recolor a panel's fill / border, respecting whether it's rounded (SetVertexColor) or square
-- (SetColorTexture). Widgets use these for hover states so rounding survives the recolor.
function Mixin:FillPaint(f, color)
    if not f._fill then return end
    if f._rounded then local c = TAP.toColor(color, self.C.panel); f._fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    else TAP.paint(f._fill, TAP.toColor(color, self.C.panel)) end
end
function Mixin:EdgePaint(f, color)
    if not f._brd then return end
    if f._rounded then local c = TAP.toColor(color, self.C.border); f._brd:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    else TAP.paint(f._brd, TAP.toColor(color, self.C.border)) end
end

-- Resolve a font key against this theme's font registry -> a usable font path. A value that
-- already looks like a path (contains a backslash or a font extension) passes straight through.
function Mixin:ResolveFont(key)
    if type(key) == "string" and (key:find("\\") or key:lower():find("%.[to]t[fc]$") or key:lower():find("%.otf$")) then
        return key
    end
    if self.fonts then
        for _, fd in ipairs(self.fonts) do if fd.key == key then return fd.path end end
    end
    return self.FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Shape (rounded-rect) texture for a corner radius -> path, sliceMargin (nil for square).
-- spec: a number radius, "pill", or a named corner ("square"/"sm"/"md"/"lg"/"pill").
TAP.SHAPE_RADII = { 4, 6, 8, 10, 12, 16 }
local CORNER_NAMES = { square = 0, none = 0, sm = 6, small = 6, md = 10, medium = 10, lg = 16, large = 16, pill = "pill" }
function Mixin:ShapeTexture(spec)
    if spec == nil or not self.shapeDir then return nil end
    if CORNER_NAMES[spec] ~= nil then spec = CORNER_NAMES[spec] end
    if spec == "pill" then return self.shapeDir .. "roundrect-pill.tga", 31 end
    local r = tonumber(spec)
    if not r or r <= 0 then return nil end
    local best = TAP.SHAPE_RADII[1]
    for _, v in ipairs(TAP.SHAPE_RADII) do if math.abs(v - r) < math.abs(best - r) then best = v end end
    return self.shapeDir .. "roundrect-" .. best .. ".tga", best
end
