-- UIFoundry - Icons.lua
-- The bundled-icon registry + a colorable icon display (Glyph). Icons are the Tabler set
-- converted to white TGAs under the theme's iconDir (see tools/convert_icons.py + ICONS.md),
-- listed in the generated IconManifest.lua. Because they're white, any icon can be tinted to
-- any color at runtime.
--
--   theme:GetIcon("sword")            -> "…\\icons\\sword.tga"        (outline)
--   theme:GetIcon("sword", "filled")  -> "…\\icons\\filled\\sword.tga" (or outline if none)
--   theme:IconPath(spec, variant)     -> resolve a name / path / fileID to a texture
--   local g = theme:Glyph(parent, { icon = "flame", size = 24, color = "FF7A00" })
--   g:SetGlyph("shield", "filled");  g:SetColor("20C997")

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- Build fast lookup sets from the manifest once.
local function sets()
    local m = UIF.ICON_MANIFEST
    if not m then return nil end
    if not m._sets then
        local s = { outline = {}, filled = {}, social = {} }
        for _, n in ipairs(m.outline or {}) do s.outline[n] = true end
        for _, n in ipairs(m.filled or {}) do s.filled[n] = true end
        for _, n in ipairs(m.social or {}) do s.social[n] = true end
        m._sets = s
    end
    return m._sets
end

-- Texture path for a bundled icon (nil if there's no iconDir, or the manifest says it's
-- absent). A missing filled variant transparently falls back to the outline path.
function Mixin:GetIcon(name, variant)
    if not self.iconDir then return nil end
    local s = sets()
    if variant == "filled" and (not s or s.filled[name]) then
        return self.iconDir .. "filled\\" .. name .. ".tga"
    end
    if not s or s.outline[name] or s.social[name] then
        return self.iconDir .. name .. ".tga"
    end
    return nil
end

-- Resolve any icon spec to something SetTexture accepts:
--   number         -> fileID as-is
--   "Interface\\…" -> full path as-is
--   "12345"        -> numeric fileID
--   "sword"        -> a bundled icon if we have one, else a WoW ICONS name
function Mixin:IconPath(spec, variant)
    if type(spec) == "number" then return spec end
    if type(spec) ~= "string" or spec == "" then return nil end
    if spec:find("\\") then return spec end
    local n = tonumber(spec); if n then return n end
    return self:GetIcon(spec, variant) or ("Interface\\ICONS\\" .. spec)
end

-- Resolve any icon spec for SetTexture: bare names prefer a bundled icon; full paths / fileIDs
-- pass straight through.
function Mixin:ResolveIcon(v, variant)
    return self:IconPath(v, variant)
end

----------------------------------------------------------------------
-- Glyph: a standalone, colorable icon display (not a button).
--   opts: icon (name/path/fileID) · variant ("outline"/"filled") · size · color ·
--         coords · layer ("ARTWORK" default) · inset (bool -> game-icon crop)
----------------------------------------------------------------------
function Mixin:Glyph(parent, opts)
    opts = opts or {}
    local theme = self
    local size = opts.size or 20
    local f = CreateFrame("Frame", nil, parent); f:SetSize(size, size)
    local tex = f:CreateTexture(nil, opts.layer or "ARTWORK"); tex:SetAllPoints()
    f.tex = tex
    function f:SetGlyph(spec, variant)
        tex:SetTexture(theme:IconPath(spec, variant) or spec)
        if opts.coords then tex:SetTexCoord(unpack(opts.coords))
        elseif opts.inset then tex:SetTexCoord(unpack(theme.iconInset))
        else tex:SetTexCoord(0, 1, 0, 1) end
    end
    function f:SetColor(c) local col = UIF.toColor(c, { 1, 1, 1 }); tex:SetVertexColor(col[1], col[2], col[3], col[4]) end
    if opts.icon then f:SetGlyph(opts.icon, opts.variant) end
    f:SetColor(opts.color or { 1, 1, 1 })
    return f
end
