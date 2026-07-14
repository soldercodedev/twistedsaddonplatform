-- UIFoundry - Social.lua
-- Real social buttons: brand icon + official brand color, wired to open a link (via the
-- copy dialog, since WoW can't launch a browser) or a custom onClick.
--
-- Brand icons come from Tabler's `brand-*` outline set (MIT). Convert the ones you use to
-- TGA (see tools/convert_icons.py + ICONS.md) and point the theme at that folder:
--     local theme = UIF:NewTheme({ name="MyAddon", iconDir = "Interface\\AddOns\\MyAddon\\icons\\" })
-- Every brand below except Ko-fi maps to a Tabler slug (Ko-fi isn't in Tabler, so it falls
-- back to the `coffee` glyph). If no iconDir/icon is available, the button shows its label
-- text in the brand color instead, so it always renders.
--
--   theme:SocialButton(parent, { brand = "discord", url = "https://discord.gg/xxxx" })
--   theme:SocialButton(parent, { brand = "github", label = "Star on GitHub", url = "..." })
--   theme:SocialBar(parent, { { brand="discord", url=... }, { brand="github", url=... } })

local ADDON, UIF = ...
local Mixin = UIF.ThemeMixin

-- brand -> { slug (bundled social icon name), color (hex), label, on = icon/text-on-brand color }
-- The default set matches the icons bundled in tools/socials (converted by convert_icons.py).
-- Add your own with:  UIFoundry.BRANDS.mybrand = { slug = "mybrand", color = "AABBCC", label = "…" }
UIF.BRANDS = {
    discord = { slug = "discord", color = "5865F2", label = "Discord" },
    github  = { slug = "github",  color = "24292E", label = "GitHub",  on = "FFFFFF" },
    patreon = { slug = "patreon", color = "F96854", label = "Patreon" },
    twitch  = { slug = "twitch",  color = "9146FF", label = "Twitch" },
    youtube = { slug = "youtube", color = "FF0000", label = "YouTube" },
}

-- Resolve a brand's icon texture path (bundled social icon, or an explicit override).
local function brandIcon(theme, brand, override)
    if override then return theme:IconPath(override, "social") or override end
    if brand.slug then return theme:GetIcon(brand.slug, "social") end
    return nil
end

----------------------------------------------------------------------
-- A single social button. opts:
--   brand    = key into UIF.BRANDS (or omit and pass icon/color/label directly)
--   url      = link to copy on click (opens the copy dialog)
--   onClick  = custom handler (overrides url)
--   label    = text; omit for an icon-only square button
--   color / icon / textColor  = per-instance overrides
--   size / width / height     = icon-only uses `size`; labeled uses width/height
----------------------------------------------------------------------
function Mixin:SocialButton(parent, opts)
    opts = opts or {}
    local theme, C = self, self.C
    local brand = (opts.brand and UIF.BRANDS[opts.brand]) or {}
    local fill = UIF.toColor(opts.color, brand.color) or C.card
    local iconTex = brandIcon(theme, brand, opts.icon)
    local iconTint = UIF.toColor(opts.iconColor or brand.on, { 1, 1, 1 })
    local label = opts.label
    local iconOnly = (label == nil)

    local b = CreateFrame("Button", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    local normal, hover = fill, UIF.lighten(fill, 0.10)
    UIF.paint(b.bg, normal)

    if iconTex then
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(iconTex)
        b.icon:SetVertexColor(iconTint[1], iconTint[2], iconTint[3])
    end
    if iconOnly then
        local s = opts.size or 28
        b:SetSize(s, s)
        if b.icon then b.icon:SetSize(s * 0.6, s * 0.6); b.icon:SetPoint("CENTER") end
    else
        -- Labeled: brand-colored background with a readable (white / brand.on) label, and the
        -- brand icon at left if we have one. Text is always on-brand contrast, never the brand
        -- color itself (which would be invisible on the matching background).
        local fs = b:CreateFontString(nil, "OVERLAY")
        theme:StyleFont(fs, opts, { fontSize = 12, textColor = brand.on or "FFFFFF" })
        fs:SetText(label); b.fs = fs
        if b.icon then
            b.icon:SetSize(15, 15); b.icon:SetPoint("LEFT", 10, 0)
            fs:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
        else
            fs:SetPoint("CENTER")
        end
        local w = opts.width or ((b.icon and 34 or 16) + fs:GetStringWidth() + 16)
        b:SetSize(w, opts.height or 28)
    end
    -- If we have neither icon nor label (misconfigured), show the brand initial.
    if iconOnly and not b.icon then
        local fs = b:CreateFontString(nil, "OVERLAY"); theme:StyleFont(fs, {}, { fontSize = 13, textColor = "FFFFFF" })
        fs:SetPoint("CENTER"); fs:SetText((brand.label or "?"):sub(1, 1))
    end

    b:SetScript("OnEnter", function(self)
        UIF.paint(self.bg, hover)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(opts.tip or brand.label or label or "Link", theme:AccentHeader())
        if opts.url then GameTooltip:AddLine("Click to copy the link.", 0.82, 0.86, 0.92, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) UIF.paint(self.bg, normal); GameTooltip_Hide() end)
    b:SetScript("OnClick", function(self)
        if opts.onClick then opts.onClick(self)
        elseif opts.url then theme:ShowLinkDialog((brand.label or "Link") .. " - copy this link (Ctrl+C)", opts.url) end
    end)
    b._brand = brand
    return b
end

----------------------------------------------------------------------
-- SocialBar: a horizontal row of social buttons.
--   theme:SocialBar(parent, { { brand="discord", url=... }, { brand="github", url=... } },
--       { gap = 6, iconOnly = true, size = 28 })
----------------------------------------------------------------------
function Mixin:SocialBar(parent, list, opts)
    opts = opts or {}
    local gap = opts.gap or 6
    local bar = CreateFrame("Frame", nil, parent)
    bar.buttons = {}
    local x, hMax = 0, 0
    for _, entry in ipairs(list or {}) do
        local e = {}
        for k, v in pairs(entry) do e[k] = v end
        if opts.iconOnly and e.label == nil then e.label = nil else if opts.labeled then e.label = e.label or (UIF.BRANDS[e.brand] and UIF.BRANDS[e.brand].label) end end
        if opts.size then e.size = opts.size end
        local b = self:SocialButton(bar, e)
        b:SetPoint("LEFT", x, 0)
        x = x + b:GetWidth() + gap
        hMax = math.max(hMax, b:GetHeight())
        bar.buttons[#bar.buttons + 1] = b
    end
    bar:SetSize(math.max(1, x - gap), hMax)
    return bar
end
