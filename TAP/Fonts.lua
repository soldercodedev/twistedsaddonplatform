-- TAP - Fonts.lua
-- The bundled font registry: WoW built-ins + the TTF/OTF fonts packed under assets/fonts
-- (shared from Twisteds Combat Alerts). A theme uses this as its default `fonts` list, so
-- font dropdowns / FontSelect / the Preview font picker work out of the box, and any style
-- opts.font can be given as a key (e.g. "UBUNTU") instead of a full path.

local ADDON, TAP = ...

local FDIR = "Interface\\AddOns\\TAP\\assets\\fonts\\"

-- The single global UI-font default. There is no per-theme / per-skin font: the selected font (set
-- via TAP.SetGlobalFont from the appearance page) always wins and is shared by every theme.
TAP.DEFAULT_FONT_KEY = "UBUNTU"

TAP.DEFAULT_FONTS = {
    -- WoW built-ins (always available)
    { key = "FRIZQT",   label = "Friz Quadrata (default)", path = "Fonts\\FRIZQT__.TTF" },
    { key = "ARIALN",   label = "Arial Narrow",           path = "Fonts\\ARIALN.TTF" },
    { key = "SKURRI",   label = "Skurri",                 path = "Fonts\\SKURRI.TTF" },
    { key = "MORPHEUS", label = "Morpheus",               path = "Fonts\\MORPHEUS.TTF" },
    -- Bundled (assets/fonts)
    { key = "UBUNTU",      label = "Ubuntu",             path = FDIR .. "Ubuntu.ttf" },
    { key = "POPPINS",     label = "Poppins",            path = FDIR .. "Poppins.ttf" },
    { key = "BARLOW",      label = "Barlow Condensed",   path = FDIR .. "Barlow Condensed.ttf" },
    { key = "CHANGA",      label = "Changa",             path = FDIR .. "Changa.ttf" },
    { key = "CINZEL",      label = "Cinzel Decorative",  path = FDIR .. "Cinzel Decorative.ttf" },
    { key = "EXO",         label = "Exo",                path = FDIR .. "Exo.otf" },
    { key = "EXPRESSWAY",  label = "Expressway",         path = FDIR .. "Expressway.TTF" },
    { key = "EXPRESSWAYB", label = "Expressway Bold",    path = FDIR .. "Expressway Bold.ttf" },
    { key = "FIRALIGHT",   label = "Fira Sans Light",    path = FDIR .. "FiraSans Light.ttf" },
    { key = "FIRAMED",     label = "Fira Sans Medium",   path = FDIR .. "FiraSans Medium.ttf" },
    { key = "FIRABOLD",    label = "Fira Sans Bold",     path = FDIR .. "FiraSans Bold.ttf" },
    { key = "FUTURE",      label = "Future X Black",     path = FDIR .. "Future X Black.otf" },
    { key = "HOMESPUN",    label = "Homespun",           path = FDIR .. "Homespun.ttf" },
    { key = "KIMBERLEY",   label = "KMT Kimberley",      path = FDIR .. "KMT Kimberley.otf" },
    { key = "NINJA",       label = "KMT Ninja Naruto",   path = FDIR .. "KMT Ninja Naruto.ttf" },
    { key = "RUSSO",       label = "Russo One",          path = FDIR .. "Russo One.ttf" },
}

-- The theme's font registry (defaults to the bundled set) as { key, label, path } rows.
function TAP.ThemeMixin:FontList()
    return self.fonts or TAP.DEFAULT_FONTS
end

-- Label for a font key.
function TAP.ThemeMixin:FontLabel(key)
    for _, f in ipairs(self:FontList()) do if f.key == key then return f.label end end
    return key
end
