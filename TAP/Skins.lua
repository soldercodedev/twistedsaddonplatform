-- TAP - Skins.lua
-- A skin is a named preset that changes COLOR (palette + accent) and SHAPE (corner radius + border
-- weight). Selected at theme creation via `skin =`; the appearance UI drives palette and shape as two
-- independent axes (see ApplyPalette / ApplyShape below).
--
-- Each skin: { palette = { key = {r,g,b}, ... }, accent = {r,g,b}, radius, borderSize, winRadius }.
-- Skins DELIBERATELY carry NO font: the UI font is a single global choice (TAP.SetGlobalFont, driven
-- by the appearance page's font selector) that always wins and is shared by every theme, so a skin
-- swap can never fight the user's chosen font. Anything omitted falls back to the base defaults.

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

TAP.SKINS = {
    -- Flat / clean: the default dark look, square corners, thin border.
    flat = {
        accent = { 0.04, 0.34, 0.79 }, radius = 0, borderSize = 1,
    },
    -- Rounded: same palette, soft 8px corners.
    rounded = {
        accent = { 0.04, 0.34, 0.79 }, radius = 8, borderSize = 1,
    },
    -- Modern: cooler deep-space palette, teal accent, big 12px corners.
    modern = {
        palette = {
            bg = { 0.07, 0.08, 0.11 }, sidebar = { 0.09, 0.10, 0.14 }, panel = { 0.11, 0.12, 0.16 },
            card = { 0.15, 0.16, 0.22 }, hover = { 0.20, 0.22, 0.30 }, border = { 0.22, 0.24, 0.32 },
            text = { 0.92, 0.94, 0.97 }, subtext = { 0.55, 0.60, 0.70 },
        },
        accent = { 0.13, 0.79, 0.59 }, radius = 12, borderSize = 1,
    },
    -- Blizzard-inspired: dark parchment tones, muted gold accent, square + a heavier border.
    -- (An evocative palette, not the literal gold DialogBox texture.)
    blizzard = {
        palette = {
            bg = { 0.045, 0.045, 0.06 }, sidebar = { 0.065, 0.058, 0.045 }, panel = { 0.085, 0.075, 0.055 },
            card = { 0.115, 0.10, 0.07 }, hover = { 0.165, 0.135, 0.085 }, border = { 0.28, 0.22, 0.12 },
            text = { 0.88, 0.83, 0.71 }, subtext = { 0.56, 0.50, 0.39 },
        },
        accent = { 0.82, 0.65, 0.27 }, radius = 0, borderSize = 2,
    },
    -- Neon: near-black with a vivid magenta accent and 10px corners.
    neon = {
        palette = {
            bg = { 0.04, 0.04, 0.06 }, sidebar = { 0.05, 0.05, 0.08 }, panel = { 0.07, 0.07, 0.10 },
            card = { 0.10, 0.10, 0.15 }, hover = { 0.17, 0.14, 0.25 }, border = { 0.26, 0.19, 0.38 },
            text = { 0.95, 0.95, 0.98 }, subtext = { 0.62, 0.58, 0.72 },
        },
        accent = { 0.86, 0.20, 0.76 }, radius = 10, borderSize = 1,
    },
}
-- Per-expansion presets: each is the base dark palette with borders / hover / bg subtly
-- tinted toward the expansion's signature accent, plus a soft radius. Built from an accent.
local function expac(accent, opts)
    opts = opts or {}
    local base = TAP.DEFAULT_PALETTE
    return {
        accent = accent,
        palette = {
            bg      = TAP.mix(base.bg, accent, 0.05),
            sidebar = TAP.mix(base.sidebar, accent, 0.06),
            panel   = TAP.mix(base.panel, accent, 0.06),
            card    = TAP.mix(base.card, accent, 0.07),
            hover   = TAP.mix(base.hover, accent, 0.22),
            border  = TAP.mix(base.border, accent, 0.30),
        },
        radius = opts.radius or 6, borderSize = opts.borderSize or 1,
    }
end

-- Signature accents per WoW expansion. Tuned so each hue is distinct on the wheel:
-- red -> orange -> bronze -> gold on the warm side; emerald -> jade -> teal -> cyan ->
-- blue -> indigo -> void-violet on the cool side. The two fel greens (tbc/legion) are
-- split by lightness (deep Dark Portal vs bright acid), and the two ex-teals (bfa/warwithin)
-- are split by moving War Within to its true "radiant earthen" gold.
TAP.SKINS.classic      = expac({ 0.80, 0.24, 0.22 })   -- vanilla red
TAP.SKINS.tbc          = expac({ 0.30, 0.62, 0.20 })   -- Dark Portal fel (deep emerald)
TAP.SKINS.wrath        = expac({ 0.42, 0.78, 0.95 })   -- icy frost blue
TAP.SKINS.cataclysm    = expac({ 0.86, 0.28, 0.09 })   -- Deathwing molten crimson
TAP.SKINS.mop          = expac({ 0.20, 0.72, 0.47 })   -- pandaren jade
TAP.SKINS.wod          = expac({ 0.72, 0.46, 0.16 })   -- Iron Horde bronze
TAP.SKINS.legion       = expac({ 0.62, 0.95, 0.24 })   -- demonic acid fel (bright)
TAP.SKINS.bfa          = expac({ 0.13, 0.66, 0.72 })   -- azerite teal
TAP.SKINS.shadowlands  = expac({ 0.52, 0.60, 0.96 })   -- anima blue
TAP.SKINS.dragonflight = expac({ 0.96, 0.52, 0.16 })   -- dragon fire (golden orange)
TAP.SKINS.warwithin    = expac({ 0.88, 0.66, 0.20 })   -- radiant earthen gold
TAP.SKINS.midnight     = expac({ 0.54, 0.22, 0.72 })   -- void eclipse violet

-- Friendly display labels.
TAP.SKIN_LABELS = {
    flat = "Flat", rounded = "Rounded", modern = "Modern", blizzard = "Blizzard", neon = "Neon",
    classic = "Classic", tbc = "Burning Crusade", wrath = "Wrath of the Lich King",
    cataclysm = "Cataclysm", mop = "Mists of Pandaria", wod = "Warlords of Draenor",
    legion = "Legion", bfa = "Battle for Azeroth", shadowlands = "Shadowlands",
    dragonflight = "Dragonflight", warwithin = "The War Within", midnight = "Midnight",
}
----------------------------------------------------------------------
-- Decoupled shape + palette selection.
-- A skin bundles SHAPE (corner radius + border weight) and COLOR (palette + accent) together.
-- The suite's appearance UI splits those into two independent axes so you can pick, say, a
-- rounded shape with the Neon palette - a consumer drives each axis on its own, or supplies a
-- fully custom palette.
----------------------------------------------------------------------

-- SHAPE presets (the "buttons"): square/sharp vs rounded corners + borders.
TAP.SHAPES = {
    square  = { radius = 0, borderSize = 1 },
    rounded = { radius = 8, borderSize = 1 },
}
TAP.SHAPE_ORDER  = { "square", "rounded" }
TAP.SHAPE_LABELS = { square = "Sharp / Square", rounded = "Rounded" }
function Mixin:ShapeLabel(name) return TAP.SHAPE_LABELS[name] or name end
function Mixin:ShapeList() return TAP.SHAPE_ORDER end

-- Extra full palettes beyond the WoW-expansion set: a neutral greyscale ramp (blacks -> greys) and a
-- couple of LIGHT templates (light background, dark text). Each sets every color key, so switching is
-- a clean swap; the accent stays tasteful but you can override it or go Custom. radius/borderSize only
-- matter if applied as a full skin - the appearance page drives shape on its own axis.
TAP.SKINS.obsidian = {   -- near-black, cool neutral
    palette = {
        bg = { 0.030, 0.032, 0.038 }, sidebar = { 0.050, 0.052, 0.060 }, panel = { 0.070, 0.073, 0.083 },
        card = { 0.100, 0.104, 0.118 }, hover = { 0.150, 0.156, 0.176 }, border = { 0.200, 0.208, 0.232 },
        text = { 0.920, 0.930, 0.945 }, subtext = { 0.540, 0.560, 0.600 },
    },
    accent = { 0.40, 0.52, 0.70 }, radius = 8, borderSize = 1,
}
TAP.SKINS.graphite = {   -- dark neutral grey
    palette = {
        bg = { 0.085, 0.088, 0.095 }, sidebar = { 0.110, 0.113, 0.122 }, panel = { 0.130, 0.134, 0.144 },
        card = { 0.175, 0.180, 0.193 }, hover = { 0.235, 0.242, 0.258 }, border = { 0.300, 0.310, 0.330 },
        text = { 0.905, 0.910, 0.922 }, subtext = { 0.560, 0.570, 0.600 },
    },
    accent = { 0.55, 0.60, 0.68 }, radius = 8, borderSize = 1,
}
TAP.SKINS.nickel = {   -- medium grey, softer contrast
    palette = {
        bg = { 0.150, 0.155, 0.165 }, sidebar = { 0.180, 0.186, 0.198 }, panel = { 0.205, 0.212, 0.226 },
        card = { 0.255, 0.263, 0.280 }, hover = { 0.320, 0.330, 0.350 }, border = { 0.390, 0.402, 0.425 },
        text = { 0.930, 0.935, 0.945 }, subtext = { 0.640, 0.652, 0.680 },
    },
    accent = { 0.60, 0.66, 0.78 }, radius = 8, borderSize = 1,
}
TAP.SKINS.daylight = {   -- clean light: light-grey background, dark text
    palette = {
        bg = { 0.950, 0.960, 0.972 }, sidebar = { 0.900, 0.912, 0.930 }, panel = { 0.875, 0.888, 0.908 },
        card = { 0.822, 0.840, 0.866 }, hover = { 0.760, 0.792, 0.850 }, border = { 0.680, 0.706, 0.748 },
        text = { 0.120, 0.140, 0.180 }, subtext = { 0.380, 0.410, 0.470 },
    },
    accent = { 0.10, 0.42, 0.82 }, radius = 8, borderSize = 1,
}
TAP.SKINS.parchment = {   -- warm light / cream
    palette = {
        bg = { 0.960, 0.945, 0.905 }, sidebar = { 0.918, 0.898, 0.848 }, panel = { 0.895, 0.872, 0.815 },
        card = { 0.852, 0.822, 0.752 }, hover = { 0.800, 0.760, 0.668 }, border = { 0.700, 0.652, 0.548 },
        text = { 0.175, 0.150, 0.105 }, subtext = { 0.430, 0.390, 0.310 },
    },
    accent = { 0.72, 0.46, 0.14 }, radius = 8, borderSize = 1,
}

-- Palette dropdown, GROUPED. Each entry is a full DISTINCT palette (shape is its own axis, so the
-- shape-only "rounded" skin is excluded). Neutral = greyscale ramp; Light = light templates;
-- Styled = the characterful ones; Expansion = the WoW-signature accent palettes.
TAP.PALETTE_GROUPS = {
    { header = "Neutral",   names = { "flat", "obsidian", "graphite", "nickel" } },
    { header = "Light",     names = { "daylight", "parchment" } },
    { header = "Styled",    names = { "modern", "blizzard", "neon" } },
    { header = "Expansion", names = { "classic", "tbc", "wrath", "cataclysm", "mop", "wod",
                                      "legion", "bfa", "shadowlands", "dragonflight", "warwithin", "midnight" } },
}

-- Flattened order (backward-compatible with callers that just want a simple list).
TAP.PALETTE_ORDER = {}
for _, g in ipairs(TAP.PALETTE_GROUPS) do
    for _, n in ipairs(g.names) do TAP.PALETTE_ORDER[#TAP.PALETTE_ORDER + 1] = n end
end

TAP.PALETTE_LABELS = {
    flat = "Default (Dark)", obsidian = "Obsidian", graphite = "Graphite", nickel = "Nickel",
    daylight = "Daylight (Light)", parchment = "Parchment (Light)",
}   -- Styled + Expansion fall back to TAP.SKIN_LABELS
function Mixin:PaletteLabel(name) return TAP.PALETTE_LABELS[name] or TAP.SKIN_LABELS[name] or name end
function Mixin:PaletteList() return TAP.PALETTE_ORDER end
function Mixin:PaletteGroups() return TAP.PALETTE_GROUPS end

-- The palette color variables, in editor display order (the Custom editor edits each of these).
TAP.PALETTE_KEYS = { "bg", "sidebar", "panel", "card", "hover", "border", "accent", "text", "subtext" }

-- Apply ONLY the shape tokens (corner radius + border weight); color + font are untouched.
function Mixin:ApplyShape(name)
    local s = TAP.SHAPES[name]; if not s then return self end
    self.radius     = s.radius or 0
    self.borderSize = s.borderSize or 1
    self.winRadius  = s.winRadius or s.radius or 0
    return self
end

-- Apply ONLY the color (palette + accent) of a named scheme; shape + font are untouched.
-- Resets to the base palette first so switching schemes never leaves stale entries behind.
function Mixin:ApplyPalette(name)
    local skin = TAP.SKINS[name]; if not skin then return self end
    for k, v in pairs(TAP.DEFAULT_PALETTE) do self.C[k] = { v[1], v[2], v[3] } end
    if skin.palette then for k, v in pairs(skin.palette) do self.C[k] = { v[1], v[2], v[3] } end end
    if skin.accent then self.C.accent = { skin.accent[1], skin.accent[2], skin.accent[3] } end
    self:_updateAccentCode()
    if self._onAccent then self._onAccent(self) end
    return self
end

-- Apply a fully custom palette: a table of { key = {r,g,b} } layered over the base defaults.
-- Any key in TAP.PALETTE_KEYS is honoured; missing keys keep the default. Shape + font stay.
function Mixin:ApplyCustomPalette(pal)
    for k, v in pairs(TAP.DEFAULT_PALETTE) do self.C[k] = { v[1], v[2], v[3] } end
    if pal then for k, v in pairs(pal) do if self.C[k] then self.C[k] = { v[1], v[2], v[3] } end end end
    self:_updateAccentCode()
    if self._onAccent then self._onAccent(self) end
    return self
end
