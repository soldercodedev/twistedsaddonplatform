-- UIFoundry - Skins.lua
-- A skin is a named preset that changes both COLOR (palette + accent) and SHAPE (corner
-- radius + border weight + font). Pick one at creation, or swap it live.
--
--   local theme = UIFoundry:NewTheme({ name = "MyAddon", skin = "rounded" })
--   theme:ApplySkin("blizzard");  win:Refresh()          -- swap live, then re-render
--
-- Each skin: { palette = { key = {r,g,b}, ... }, accent = {r,g,b}, radius, borderSize,
--              winRadius, font = "KEY" }.  Anything omitted falls back to the base defaults.

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

UIF.SKINS = {
    -- Flat / clean: the default dark look, square corners, thin border.
    flat = {
        accent = { 0.04, 0.34, 0.79 }, radius = 0, borderSize = 1, font = "UBUNTU",
    },
    -- Rounded: same palette, soft 8px corners.
    rounded = {
        accent = { 0.04, 0.34, 0.79 }, radius = 8, borderSize = 1, font = "UBUNTU",
    },
    -- Modern: cooler deep-space palette, teal accent, big 12px corners.
    modern = {
        palette = {
            bg = { 0.07, 0.08, 0.11 }, sidebar = { 0.09, 0.10, 0.14 }, panel = { 0.11, 0.12, 0.16 },
            card = { 0.15, 0.16, 0.22 }, hover = { 0.20, 0.22, 0.30 }, border = { 0.22, 0.24, 0.32 },
            text = { 0.92, 0.94, 0.97 }, subtext = { 0.55, 0.60, 0.70 },
        },
        accent = { 0.13, 0.79, 0.59 }, radius = 12, borderSize = 1, font = "POPPINS",
    },
    -- Blizzard-inspired: dark parchment tones, muted gold accent, square + a heavier border.
    -- (An evocative palette, not the literal gold DialogBox texture.)
    blizzard = {
        palette = {
            bg = { 0.045, 0.045, 0.06 }, sidebar = { 0.065, 0.058, 0.045 }, panel = { 0.085, 0.075, 0.055 },
            card = { 0.115, 0.10, 0.07 }, hover = { 0.165, 0.135, 0.085 }, border = { 0.28, 0.22, 0.12 },
            text = { 0.88, 0.83, 0.71 }, subtext = { 0.56, 0.50, 0.39 },
        },
        accent = { 0.82, 0.65, 0.27 }, radius = 0, borderSize = 2, font = "FRIZQT",
    },
    -- Neon: near-black with a vivid magenta accent and 10px corners.
    neon = {
        palette = {
            bg = { 0.04, 0.04, 0.06 }, sidebar = { 0.05, 0.05, 0.08 }, panel = { 0.07, 0.07, 0.10 },
            card = { 0.10, 0.10, 0.15 }, hover = { 0.17, 0.14, 0.25 }, border = { 0.26, 0.19, 0.38 },
            text = { 0.95, 0.95, 0.98 }, subtext = { 0.62, 0.58, 0.72 },
        },
        accent = { 0.86, 0.20, 0.76 }, radius = 10, borderSize = 1, font = "RUSSO",
    },
}
-- Per-expansion presets: each is the base dark palette with borders / hover / bg subtly
-- tinted toward the expansion's signature accent, plus a soft radius. Built from an accent.
local function expac(accent, opts)
    opts = opts or {}
    local base = UIF.DEFAULT_PALETTE
    return {
        accent = accent,
        palette = {
            bg      = UIF.mix(base.bg, accent, 0.05),
            sidebar = UIF.mix(base.sidebar, accent, 0.06),
            panel   = UIF.mix(base.panel, accent, 0.06),
            card    = UIF.mix(base.card, accent, 0.07),
            hover   = UIF.mix(base.hover, accent, 0.22),
            border  = UIF.mix(base.border, accent, 0.30),
        },
        radius = opts.radius or 6, borderSize = opts.borderSize or 1, font = opts.font or "UBUNTU",
    }
end

-- Signature accents per WoW expansion. Tuned so each hue is distinct on the wheel:
-- red -> orange -> bronze -> gold on the warm side; emerald -> jade -> teal -> cyan ->
-- blue -> indigo -> void-violet on the cool side. The two fel greens (tbc/legion) are
-- split by lightness (deep Dark Portal vs bright acid), and the two ex-teals (bfa/warwithin)
-- are split by moving War Within to its true "radiant earthen" gold.
UIF.SKINS.classic      = expac({ 0.80, 0.24, 0.22 })   -- vanilla red
UIF.SKINS.tbc          = expac({ 0.30, 0.62, 0.20 })   -- Dark Portal fel (deep emerald)
UIF.SKINS.wrath        = expac({ 0.42, 0.78, 0.95 })   -- icy frost blue
UIF.SKINS.cataclysm    = expac({ 0.86, 0.28, 0.09 })   -- Deathwing molten crimson
UIF.SKINS.mop          = expac({ 0.20, 0.72, 0.47 })   -- pandaren jade
UIF.SKINS.wod          = expac({ 0.72, 0.46, 0.16 })   -- Iron Horde bronze
UIF.SKINS.legion       = expac({ 0.62, 0.95, 0.24 })   -- demonic acid fel (bright)
UIF.SKINS.bfa          = expac({ 0.13, 0.66, 0.72 })   -- azerite teal
UIF.SKINS.shadowlands  = expac({ 0.52, 0.60, 0.96 })   -- anima blue
UIF.SKINS.dragonflight = expac({ 0.96, 0.52, 0.16 })   -- dragon fire (golden orange)
UIF.SKINS.warwithin    = expac({ 0.88, 0.66, 0.20 })   -- radiant earthen gold
UIF.SKINS.midnight     = expac({ 0.54, 0.22, 0.72 })   -- void eclipse violet

UIF.SKIN_ORDER = {
    "flat", "rounded", "modern", "blizzard", "neon",
    "classic", "tbc", "wrath", "cataclysm", "mop", "wod",
    "legion", "bfa", "shadowlands", "dragonflight", "warwithin", "midnight",
}

-- Friendly display labels.
UIF.SKIN_LABELS = {
    flat = "Flat", rounded = "Rounded", modern = "Modern", blizzard = "Blizzard", neon = "Neon",
    classic = "Classic", tbc = "Burning Crusade", wrath = "Wrath of the Lich King",
    cataclysm = "Cataclysm", mop = "Mists of Pandaria", wod = "Warlords of Draenor",
    legion = "Legion", bfa = "Battle for Azeroth", shadowlands = "Shadowlands",
    dragonflight = "Dragonflight", warwithin = "The War Within", midnight = "Midnight",
}
function Mixin:SkinLabel(name) return UIF.SKIN_LABELS[name] or name end

-- Apply a skin to a live theme: reset the palette to defaults, layer the skin's palette /
-- accent / shape tokens / font, then fire onAccent so the consumer re-renders. Call
-- win:Refresh() (or rebuild your UI) afterward to see it.
function Mixin:ApplySkin(name)
    local skin = UIF.SKINS[name]; if not skin then return self end
    self.skin = name
    for k, v in pairs(UIF.DEFAULT_PALETTE) do self.C[k] = { v[1], v[2], v[3] } end
    if skin.palette then for k, v in pairs(skin.palette) do self.C[k] = { v[1], v[2], v[3] } end end
    if skin.accent then self.C.accent = { skin.accent[1], skin.accent[2], skin.accent[3] } end
    self.radius     = skin.radius or 0
    self.borderSize = skin.borderSize or 1
    self.winRadius  = skin.winRadius or self.radius
    if skin.font then self.FONT = UIF.ResolveFontFile(self:ResolveFont(skin.font)) end
    self:_updateAccentCode()
    if self._onAccent then self._onAccent(self) end
    return self
end

function Mixin:SkinList() return UIF.SKIN_ORDER end
