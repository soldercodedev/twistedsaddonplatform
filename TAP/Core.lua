-- UIFoundry - Core.lua
-- A self-skinned, dependency-free UI kit for World of Warcraft addons.
-- Extracted from Twisteds Combat Alerts so a whole suite of tools can share one look:
-- flat dark theme + configurable accent, custom toggles / dropdowns / sliders / inputs /
-- pickers / dialogs, a pooled content builder, and a full application window shell.
--
-- No external textures or libraries: solid-color textures + built-in (or bundled) fonts.
--
-- Usage (from a consuming addon that lists UIFoundry as a dependency):
--     local UIF   = _G.UIFoundry
--     local theme = UIF:NewTheme({ name = "MyAddon", accent = { 0.2, 0.6, 1.0 } })
--     local btn   = theme:Button(parent)
--     btn:Configure("Save", 100, 26, "primary", function() print("saved") end)
--
-- This file establishes the shared namespace and the palette-independent math /
-- Midnight-secret-safety helpers that every other file relies on.

local ADDON, UIF = ...

UIF.MAJOR   = "UIFoundry-1.0"
UIF.version = 1

-- The library table is exposed as a global so any dependent addon can reach it
-- without LibStub. As a standalone dependency there is only ever one copy loaded.
-- It ships as the "TAP" addon (the shared lib for the suite), so it is also
-- exposed under that name - use whichever global you prefer.
_G.UIFoundry = UIF
_G.TAP = UIF

-- Methods added across the widget / picker / window files land on this shared mixin;
-- NewTheme() (Theme.lua) sets it as every theme's metatable __index. Because all files
-- populate the SAME table reference, methods defined in later-loaded files are still
-- available on themes created at runtime.
UIF.ThemeMixin = {}

-- Monotonic counter for auto-generating unique global frame names (Math.random and
-- time-based names are avoided so behavior is deterministic across reloads).
UIF._uid = 0
function UIF.NextId(prefix)
    UIF._uid = UIF._uid + 1
    return (prefix or "UIFoundry") .. UIF._uid
end

----------------------------------------------------------------------
-- Color math (palette-independent; colors are passed in explicitly)
----------------------------------------------------------------------
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
UIF.clamp01 = clamp01

-- Fill a texture with a solid color table { r, g, b }, optional alpha.
function UIF.paint(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or 1) end

-- Lighten / darken toward white / black by fraction f.
function UIF.lighten(c, f) return { clamp01(c[1] + f), clamp01(c[2] + f), clamp01(c[3] + f) } end
function UIF.darken(c, f)  return { c[1] * (1 - f), c[2] * (1 - f), c[3] * (1 - f) } end

-- Linear blend a -> b by t (0..1).
function UIF.mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Hex helpers for the color picker + any hex I/O.
function UIF.hexOf(r, g, b)
    return string.format("%02X%02X%02X",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function UIF.parseHex(s)
    s = (s or ""):gsub("[^0-9a-fA-F]", "")
    if #s >= 6 then
        return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
    end
end

----------------------------------------------------------------------
-- Midnight "secret value" safety
-- In patch 12.0 (Midnight) some APIs return values you cannot compare or do math on --
-- doing so throws "attempt to compare ... a secret value". issecretvalue()/canaccessvalue()
-- let you test first (calling them on a secret is allowed). Pre-12.0 clients have neither
-- global, and nothing is secret there.
----------------------------------------------------------------------
local _canaccessvalue, _issecretvalue = canaccessvalue, issecretvalue
-- UIF.CanRead(v) -> true when it is safe to compare / do math on v right now.
function UIF.CanRead(v)
    if _issecretvalue then
        local ok, res = pcall(_issecretvalue, v)
        if ok then return not res end
    end
    if _canaccessvalue then
        local ok, res = pcall(_canaccessvalue, v)
        if ok then return res and true or false end
    end
    return true
end

----------------------------------------------------------------------
-- ScrollFrame helpers (secret-safe)
----------------------------------------------------------------------
-- Readable vertical scroll max for a ScrollFrame. GetVerticalScrollRange() can return a
-- Midnight "secret" number when the content held secret values; the child / viewport
-- heights stay readable, so derive the range from them instead.
function UIF.scrollMax(sf)
    local child = sf.GetScrollChild and sf:GetScrollChild()
    local ch = child and child:GetHeight()
    local vh = sf:GetHeight()
    if child and UIF.CanRead(ch) and UIF.CanRead(vh) then
        return math.max(0, ch - vh)
    end
    return 0
end

-- Shared mousewheel scroller (30px per notch).
function UIF.scrollWheel(self, delta)
    local cur = self:GetVerticalScroll()
    if not UIF.CanRead(cur) then return end   -- position unreadable (secret) -> can't clamp safely
    self:SetVerticalScroll(math.min(UIF.scrollMax(self), math.max(0, cur - delta * 30)))
end

----------------------------------------------------------------------
-- Font resolution
----------------------------------------------------------------------
-- WoW only indexes font files that existed at launch, so a freshly-added bundled TTF may
-- not be loadable on the very first run. Probe it; fall back to the default font when
-- SetFont returns false.
function UIF.ResolveFontFile(path)
    local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if not path or path == "" then return fallback end
    local probe = UIParent and UIParent:CreateFontString(nil, "OVERLAY")
    if probe then
        local ok = probe:SetFont(path, 12)
        probe:Hide()
        if ok then return path end
        return fallback
    end
    return path
end

-- Default full-bleed icon crop (bundled Tabler-style TGAs are edge-to-edge; Blizzard
-- ICONS want the classic 0.07..0.93 inset to trim their built-in border).
UIF.ICON_INSET = { 0.07, 0.93, 0.07, 0.93 }
