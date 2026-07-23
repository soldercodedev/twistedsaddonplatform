-- UIFoundry - Headings.lua
-- Typographic "classes": a Heading with named roles (display / h1..h6 / title / subtitle /
-- overline / caption / label / body). Each role is a preset of size + weight + color that
-- you can override per call. This is the type scale the rest of the kit reuses.
--
--   theme:Heading(parent, { text = "Settings", role = "h1" })
--   theme:Heading(parent, { text = "SECTION", role = "overline", textColor = "20C997" })
--   b:Heading("Welcome", x, y, "display")            -- via the Builder

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- Roles (all overridable via the standard style keys - fontSize, textColor, font, ...).
-- `color` names a palette key; `upper` uppercases the text unless opts.upper says otherwise.
UIF.HEADING_ROLES = {
    display  = { fontSize = 28, fontFlags = "", color = "text",    upper = false },
    h1       = { fontSize = 22, fontFlags = "", color = "text",    upper = false },
    h2       = { fontSize = 18, fontFlags = "", color = "text",    upper = false },
    h3       = { fontSize = 16, fontFlags = "", color = "text",    upper = false },
    h4       = { fontSize = 14, fontFlags = "", color = "text",    upper = false },
    h5       = { fontSize = 13, fontFlags = "", color = "accent",  upper = false },
    h6       = { fontSize = 12, fontFlags = "", color = "accent",  upper = false },
    title    = { fontSize = 16, fontFlags = "", color = "text",    upper = false },
    subtitle = { fontSize = 12, fontFlags = "", color = "subtext", upper = false },
    overline = { fontSize = 10, fontFlags = "", color = "subtext", upper = true  },
    caption  = { fontSize = 11, fontFlags = "", color = "subtext", upper = false },
    label    = { fontSize = 12, fontFlags = "", color = "subtext", upper = false },
    body     = { fontSize = 12, fontFlags = "", color = "text",    upper = false },
}

-- Create a heading fontstring. opts.role picks the preset (default "h3"); any style key
-- overrides it. opts.text sets the string; opts.wrapWidth makes it word-wrap.
function Mixin:Heading(parent, opts)
    opts = opts or {}
    local role = UIF.HEADING_ROLES[opts.role or "h3"] or UIF.HEADING_ROLES.h3
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local roleColor = self.C[role.color] or self.C.text
    self:StyleFont(fs, opts, { fontSize = role.fontSize, fontFlags = role.fontFlags, textColor = roleColor, justify = "LEFT" })
    local text = opts.text or ""
    if (opts.upper == nil and role.upper) or opts.upper then text = text:upper() end
    fs:SetText(self:HL(text))
    if opts.wrapWidth then fs:SetWordWrap(true); fs:SetWidth(opts.wrapWidth) else fs:SetWordWrap(false) end
    return fs
end
