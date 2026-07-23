-- TAP - Headings.lua
-- Typographic "classes": a Heading with named roles (display / h1..h6 / title / subtitle /
-- overline / caption / label / body). Each role is a preset of size + weight + color that
-- you can override per call. This is the type scale the rest of the kit reuses.
--
--   theme:Heading(parent, { text = "Settings", role = "h1" })
--   theme:Heading(parent, { text = "SECTION", role = "overline", textColor = "20C997" })
--   b:Heading("Welcome", x, y, "display")            -- via the Builder

local ADDON, TAP = ...
local Mixin = TAP.ThemeMixin

-- Roles (all overridable via the standard style keys - fontSize, textColor, font, ...).
-- `color` names a palette key; `upper` uppercases the text unless opts.upper says otherwise.
TAP.HEADING_ROLES = {
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

-- Apply a role's styling (size / weight / color / upper / wrap) + text to an EXISTING fontstring.
-- Shared by theme:Heading (a fresh fontstring) and the Builder's pooled Heading so the two can't drift.
function Mixin:_applyHeading(fs, text, role, opts)
    opts = opts or {}
    local r = TAP.HEADING_ROLES[role or opts.role or "h3"] or TAP.HEADING_ROLES.h3
    self:StyleFont(fs, opts, { fontSize = r.fontSize, fontFlags = r.fontFlags, textColor = self.C[r.color] or self.C.text, justify = "LEFT" })
    local t = text or ""
    if (opts.upper == nil and r.upper) or opts.upper then t = t:upper() end
    -- Reset any width a prior (pooled) caller left, else a leaked width would wrap/clip this heading;
    -- only constrain when wrapWidth is given.
    fs:SetWordWrap(opts.wrapWidth ~= nil); fs:SetWidth(opts.wrapWidth or 0)
    fs:SetText(self:HL(t))
    return fs
end

-- Create a heading fontstring. opts.role picks the preset (default "h3"); any style key
-- overrides it. opts.text sets the string; opts.wrapWidth makes it word-wrap.
function Mixin:Heading(parent, opts)
    opts = opts or {}
    return self:_applyHeading(parent:CreateFontString(nil, "OVERLAY"), opts.text, opts.role, opts)
end
