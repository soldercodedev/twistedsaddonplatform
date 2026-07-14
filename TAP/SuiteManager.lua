-- TAP - SuiteManager.lua
-- The control panel for the suite. `/tap` opens a UIFoundry window.
--
-- Navigation:
--   Suite     -> Overview (dashboard), Settings (appearance), Installed (hard load control)
--   Modules   -> ONE sidebar entry per registered sidecar, each its own page with a live
--                on/off switch and that module's inline settings
--   Help      -> About
--
-- The sidebar is built from the live module registry, so installing a plugin adds its own
-- navigation entry automatically. The window is (re)built lazily whenever the set of
-- registered modules changes.
--
-- This lives in the parent hub so `/tap` always works, even with zero sidecars installed.

local ADDON, UIF = ...
local Suite = _G.TAP

local ICON_DIR = "Interface\\AddOns\\TAP\\assets\\icons\\"

-- Default suite look, out of the box (overridden by any saved appearance).
local DEFAULT_SKIN = "dragonflight"

local theme = UIF:NewTheme({
    name    = "TAPManager",
    skin    = DEFAULT_SKIN,   -- dragon-fire palette + accent (overridden by saved appearance)
    iconDir = ICON_DIR,
})

-- Expose the manager theme so sidecars can match the suite's selected look for their own chrome
-- (e.g. transient dialogs). It's the same object the appearance page mutates, so it stays live.
Suite.uiTheme = theme

----------------------------------------------------------------------
-- SavedVariables slots (under the shared suite DB).
----------------------------------------------------------------------
local function managerDB()
    local db = Suite:DB()
    db.manager = db.manager or {}
    return db.manager
end

-- Persisted appearance { skin, accent = {r,g,b}, font = key }. Seeded from the live theme.
local function appearanceDB()
    local m = managerDB()
    m.theme = m.theme or {}
    m.theme.skin   = m.theme.skin or theme.skin or DEFAULT_SKIN
    m.theme.accent = m.theme.accent or { theme.C.accent[1], theme.C.accent[2], theme.C.accent[3] }
    return m.theme
end

-- The font is governed SOLELY by the font selector (a.font), defaulting to the suite's bundled
-- Ubuntu. SKINS NEVER DICTATE THE FONT. Re-resolved on each call because a bundled TTF may not be
-- loadable until after login (WoW indexes font files only at client launch).
local function applyFont()
    local a = appearanceDB()
    theme.FONT = UIF.ResolveFontFile(theme:ResolveFont(a.font or "UBUNTU"))
end

-- Apply the saved appearance: skin (palette/shape - also resets the accent), then the accent
-- override, then the font LAST so a skin's font can never override the user's chosen font.
local function applySavedAppearance()
    local a = appearanceDB()
    if a.skin then pcall(theme.ApplySkin, theme, a.skin) end
    if a.accent then theme:ApplyAccent(a.accent) end
    applyFont()
end
applySavedAppearance()

----------------------------------------------------------------------
-- Shared helpers.
----------------------------------------------------------------------
local C_AddOns = _G.C_AddOns   -- 11.0+ namespaced addon API

-- An addon folder's Version metadata (nil if unavailable, e.g. no ## Version in its .toc).
local function addonVersion(addonName)
    if not (addonName and C_AddOns and C_AddOns.GetAddOnMetadata) then return nil end
    return C_AddOns.GetAddOnMetadata(addonName, "Version")
end

-- The suite's own version, with a sane fallback if the .toc metadata isn't ready yet.
local function suiteVersion() return addonVersion("TAP") or "1.1.0" end

local function moduleNavIcon(spec)
    if spec.icon then return theme:ResolveIcon(spec.icon) end
    return theme:GetIcon("hexagon")
end

local function statusBadge(b, mod, x, y)
    local variant = mod:IsActive() and "success" or (mod:IsEnabled() and "warning" or "neutral")
    local text = mod:IsActive() and "ACTIVE" or (mod:IsEnabled() and "PENDING" or "OFF")
    b:Badge(x, y, { text = text, variant = variant })
end

----------------------------------------------------------------------
-- "What's New" viewer. Each module exposes a plain-language changelog via spec.changelog (a small
-- markdown-lite string: "## version", "- **[NEW]** ...", etc.). We parse it and show it in a
-- scrollable modal - a friendly "what changed" list, no tech-speak required.
----------------------------------------------------------------------
local TAG_COLOR = {
    ["NEW"] = { 0.45, 0.85, 0.5 }, ["BUG FIX"] = { 0.4, 0.8, 1 }, ["FIX"] = { 0.4, 0.8, 1 },
    ["CHANGE"] = { 1, 0.72, 0.35 }, ["KNOWN"] = { 0.72, 0.72, 0.75 },
}

local function parseChangelog(text)
    local blocks, last = {}, nil
    for raw in (text or ""):gmatch("[^\n]+") do
        local indented = raw:match("^%s") ~= nil
        local t = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" then
            last = nil
        elseif t:match("^###%s") then
            blocks[#blocks + 1] = { kind = "sub", text = t:gsub("^###%s*", "") }; last = nil
        elseif t:match("^##%s") then
            blocks[#blocks + 1] = { kind = "version", text = t:gsub("^##%s*", "") }; last = nil
        elseif t:match("^#%s") then
            last = nil   -- top title: the modal title already says which module this is
        elseif t:match("^%-%s") then
            local body = t:gsub("^%-%s*", "")
            local tag, rest = body:match("^%*%*%[([^%]]+)%]%*%*%s*(.*)$")
            local blk = { kind = "bullet", tag = tag, text = rest or body }
            blocks[#blocks + 1] = blk; last = blk
        elseif indented and last then
            last.text = last.text .. " " .. t   -- wrapped continuation of the previous item
        else
            local blk = { kind = "para", text = t }; blocks[#blocks + 1] = blk; last = blk
        end
    end
    return blocks
end

local function renderChangelog(content, wrapW, blocks)
    local C = theme.C
    local y = -4
    local function line(size, color, w2, xoff, s)
        local fs = content:CreateFontString(nil, "OVERLAY")
        fs:SetFont(theme.FONT, size); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetWidth(w2)
        fs:SetText(s); fs:SetTextColor(color[1], color[2], color[3])
        fs:SetPoint("TOPLEFT", xoff, y)
        y = y - (fs:GetStringHeight() or size) - 5
    end
    for _, blk in ipairs(blocks) do
        local txt = (blk.text or ""):gsub("%*%*", "")   -- strip any leftover bold markers
        if blk.kind == "version" then
            y = y - 10; line(15, C.accent, wrapW, 2, "Version " .. txt)
        elseif blk.kind == "sub" then
            y = y - 4; line(11, C.subtext, wrapW, 4, txt:upper())
        elseif blk.kind == "bullet" then
            local tag = blk.tag and blk.tag:upper()
            local prefix = ""
            if tag then
                local c = TAG_COLOR[tag] or C.subtext
                prefix = string.format("|cff%02x%02x%02x[%s]|r  ",
                    math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), tag)
            end
            line(12, C.text, wrapW - 14, 14, "|cff888888-|r  " .. prefix .. txt)
        else
            line(12, C.text, wrapW, 4, txt)
        end
    end
    content:SetHeight(math.max(10, -y + 8))
end

local function openWhatsNew(title, text)
    local blocks = parseChangelog(text)
    theme:Modal({
        title = "What's New - " .. (title or ""),
        icon = "sparkles", width = 560, bodyHeight = 460, dismissable = true,
        content = function(body, modal)
            local sw = body:GetWidth()
            local scroll = CreateFrame("ScrollFrame", nil, body)
            scroll:SetPoint("TOPLEFT"); scroll:SetPoint("BOTTOMRIGHT")
            local inner = CreateFrame("Frame", nil, scroll); inner:SetSize(sw, 10)
            scroll:SetScrollChild(inner); scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(self, delta)
                local maxv = self:GetVerticalScrollRange()
                self:SetVerticalScroll(math.max(0, math.min(maxv, self:GetVerticalScroll() - delta * 42)))
            end)
            renderChangelog(inner, sw - 8, blocks)
        end,
    }):Open()
end

-- A small "What's New" link-button. Returns the new y (only draws when there's a changelog).
local function whatsNewLink(b, spec, x, y)
    if not (spec and spec.changelog) then return y end
    b:Button(x, y - 2, 116, "What's New", "default",
        function() openWhatsNew(spec.title or spec.id, spec.changelog) end,
        { icon = "sparkles", iconSize = 12, height = 22 })
    return y - 28
end

-- The module (and its changelog) that a given plug-in addon folder provides, if any.
local function moduleForAddon(name)
    for _, mod in ipairs(Suite.modules) do
        if mod.spec.addon == name then return mod end
    end
end

----------------------------------------------------------------------
-- Page: Overview (dashboard - stats + a quick list that links to each module's page)
----------------------------------------------------------------------
local function pageOverview(b, win)
    local C = theme.C
    local w = b.contentWidth
    local x, y = 24, -18

    b:Heading("Platform Overview", x, y, "h1"); y = y - 34
    local total, active = Suite:Stats()
    local _, hh = b:Wrap("Each installed plugin has its own entry in the sidebar. Toggle a module "
        .. "on or off live - no reload needed. Pick a module on the left to configure it.",
        x, y, w - 44, C.subtext, 11)
    y = y - (hh + 14)

    b:StatTile(x, y, { label = "Modules", value = tostring(total), width = 150, height = 64 })
    b:StatTile(x + 162, y, { label = "Active", value = tostring(active), width = 150, height = 64,
        valueColor = active > 0 and "accent" or nil })
    y = y - 80

    if total == 0 then
        b:Section("NO PLUGINS INSTALLED", x, y); y = y - 34
        b:Wrap("No sidecar modules are registered yet. Install a platform plugin addon (one that "
            .. "lists TAP as a dependency) and it will appear here automatically.",
            x, y, w - 44, C.subtext, 12)
        return y - 60
    end

    b:Section("MODULES", x, y); y = y - 30
    local rowW = w - 48
    local rpad = 14   -- inset for the right-aligned controls, so they don't sit flush to the row edge
    for _, mod in ipairs(Suite.modules) do
        local spec = mod.spec
        local yTop = y
        y = y - 12
        -- Header band: every control vertically centered within a 26px-tall band (Button 26,
        -- Glyph 20, Toggle 18, Badge 16 -> offset each by (26 - h)/2).
        local hy = y
        b:Glyph(x + 12, hy - 3, { icon = spec.icon, size = 20, color = mod:IsEnabled() and C.accent or C.subtext })
        local titleFs = b:Label(spec.title or spec.id, x + 42, hy - 5, mod:IsEnabled() and C.text or C.subtext, 13)
        local mver = addonVersion(spec.addon)
        if mver then b:Label("v" .. mver, x + 42 + (titleFs:GetStringWidth() or 60) + 8, hy - 4, C.subtext, 11) end
        statusBadge(b, mod, x + rowW - 200 - rpad, hy - 5)
        b:Toggle(x + rowW - 112 - rpad, hy - 4, mod:IsEnabled(), function(v) mod:SetEnabled(v) end, { color = C.accent })
        b:Button(x + rowW - 66 - rpad, hy, 66, "Open", "default", function() win:SelectView("mod:" .. spec.id) end)
        y = y - 34   -- clear gap below the header band so the description doesn't hug the controls
        if spec.desc then
            local _, dh = b:Wrap(spec.desc, x + 42, y, rowW - 70, C.subtext, 10)
            y = y - (dh + 8)
        end
        y = whatsNewLink(b, spec, x + 42, y)
        y = y - 10
        b:Box(x, yTop, rowW, yTop - y, mod:IsEnabled() and 0.05 or 0.03, 0, mod:IsEnabled() and C.accent or C.card)
        if mod:IsEnabled() then b:VRule(x, yTop - 1, y + 1, 0, C.accent) end
        y = y - 16
    end
    return y - 8
end

----------------------------------------------------------------------
-- Page: one per module (the module's own dashboard + inline settings)
----------------------------------------------------------------------
local function pageModule(b, win, mod)
    local C = theme.C
    local w = b.contentWidth
    local spec = mod.spec
    local x, y = 24, -18

    if spec.icon then b:Glyph(x, y - 2, { icon = spec.icon, size = 26, color = C.accent }) end
    b:Heading(spec.title or spec.id, x + (spec.icon and 36 or 0), y, "h1"); y = y - 36

    -- Enable switch + status.
    b:Toggle(x, y, mod:IsEnabled(), function(v) mod:SetEnabled(v) end, { color = C.accent })
    b:Label(mod:IsEnabled() and "Enabled" or "Disabled", x + 46, y - 2, C.text, 13)
    statusBadge(b, mod, x + w - 120, y - 1)
    y = y - 30

    if spec.desc then
        local _, hh = b:Wrap(spec.desc, x, y, w - 44, C.subtext, 11)
        y = y - (hh + 14)
    else
        y = y - 6
    end

    b:Section("SETTINGS", x, y); y = y - 32

    if not mod:IsEnabled() then
        b:Wrap("Enable this module to configure it.", x, y, w - 44, C.subtext, 12)
        return y - 40
    end
    if not spec.Settings then
        b:Wrap("This module has no configurable settings.", x, y, w - 44, C.subtext, 12)
        return y - 40
    end

    local ok, newY = pcall(spec.Settings, mod, b, x + 4, y, w - 40, win)
    if not ok then
        b:Label("|cffff6666settings error:|r " .. tostring(newY), x + 4, y, C.subtext, 10)
        return y - 24
    end
    return (type(newY) == "number" and newY or y) - 12
end

----------------------------------------------------------------------
-- Page: Settings (suite appearance - skin, accent, font)
----------------------------------------------------------------------
local function pageSettings(b, win)
    local C = theme.C
    local w = b.contentWidth
    local a = appearanceDB()
    local x, y = 24, -18

    b:Heading("Appearance", x, y, "h1"); y = y - 34
    local _, hh = b:Wrap("Customize the look of the Platform Manager. A skin changes the palette and "
        .. "shape; the accent and font can be tuned on top. Saved across sessions.",
        x, y, w - 44, C.subtext, 11)
    y = y - (hh + 16)

    -- Skins (quick buttons for the base set + a dropdown for everything, incl. expansions).
    b:Section("SKIN", x, y); y = y - 30
    local sx = x
    for _, name in ipairs({ "flat", "rounded", "modern", "blizzard", "neon" }) do
        local activeSkin = (a.skin or DEFAULT_SKIN) == name
        b:Button(sx, y, 88, theme:SkinLabel(name), activeSkin and "primary" or "default", function()
            theme:ApplySkin(name)
            a.skin = name
            a.accent = { theme.C.accent[1], theme.C.accent[2], theme.C.accent[3] }
            applyFont()   -- re-assert the user's font (ApplySkin may have set the skin's font)
            win:Refresh()
        end)
        sx = sx + 94
    end
    y = y - 38
    b:Label("All skins", x, y - 2, C.subtext)
    local choices = {}
    for _, name in ipairs(theme:SkinList()) do choices[#choices + 1] = { name, theme:SkinLabel(name) } end
    b:Dropdown(x + 90, y):SetChoices(230, choices, function() return a.skin or DEFAULT_SKIN end, function(v)
        theme:ApplySkin(v)
        a.skin = v
        a.accent = { theme.C.accent[1], theme.C.accent[2], theme.C.accent[3] }
        applyFont()   -- re-assert the user's font
        win:Refresh()
    end)
    y = y - 44

    -- Accent color.
    b:Section("ACCENT", x, y); y = y - 30
    b:Swatch(x, y - 2, a.accent, function(r, g, b2)
        theme:ApplyAccent({ r, g, b2 })
        win:Refresh()
    end, "Accent color", "The platform's highlight color.")
    b:Label("Accent color  ·  #" .. UIF.hexOf(a.accent[1], a.accent[2], a.accent[3]), x + 30, y - 4, C.text)
    y = y - 34

    -- Font.
    b:Section("FONT", x, y); y = y - 30
    b:FontSelect(x, y, { width = 220, value = a.font or "UBUNTU", onChange = function(key)
        a.font = key
        applyFont()
        win:Refresh()
    end })
    y = y - 40

    -- Live preview + reset.
    b:Section("PREVIEW", x, y); y = y - 30
    b:Button(x, y, 96, "Primary", "primary", function() end)
    b:Button(x + 104, y, 96, "Default", "default", function() end)
    b:Badge(x + 208, y + 4, { text = "ACCENT", variant = "accent", pill = true })
    y = y - 34
    b:ProgressBar(x, y, { width = 300, height = 12, value = 66, color = "accent" })
    y = y - 30
    b:Button(x, y, 150, "Reset Appearance", "danger", function()
        managerDB().theme = nil
        theme:ApplySkin(DEFAULT_SKIN)   -- restores dragon-fire palette + accent
        applyFont()                     -- back to the default Ubuntu font
        win:Refresh()
    end)
    return y - 40
end

----------------------------------------------------------------------
-- Page: Installed (hard load control - scan addons that depend on the suite)
----------------------------------------------------------------------
local function scanSidecars()
    local out = {}
    if not (C_AddOns and C_AddOns.GetNumAddOns) then return out end
    local n = C_AddOns.GetNumAddOns() or 0
    for i = 1, n do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= "TAP" then
            local deps = { C_AddOns.GetAddOnDependencies(i) }
            local dependsOnSuite = false
            for _, d in ipairs(deps) do if d == "TAP" then dependsOnSuite = true break end end
            if dependsOnSuite then
                local title = C_AddOns.GetAddOnMetadata(i, "Title") or name
                local version = C_AddOns.GetAddOnMetadata(i, "Version")
                local loaded = C_AddOns.IsAddOnLoaded(name)
                local enabled = true
                if C_AddOns.GetAddOnEnableState then
                    local ok, state = pcall(C_AddOns.GetAddOnEnableState, name)
                    if not ok then ok, state = pcall(C_AddOns.GetAddOnEnableState, nil, i) end
                    if ok then enabled = (state or 0) > 0 end
                end
                out[#out + 1] = { name = name, title = title, version = version, loaded = loaded, enabled = enabled }
            end
        end
    end
    return out
end

local function setAddonEnabled(name, on)
    if not C_AddOns then return end
    local fn = on and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn
    if fn then pcall(fn, name) end
end

local function pageInstalled(b, win)
    local C = theme.C
    local w = b.contentWidth
    local x, y = 24, -18

    b:Heading("Installed Plugins", x, y, "h1"); y = y - 34
    local _, hh = b:Wrap("These add-ons plug into the platform. Disabling one here unloads its code "
        .. "completely (Blizzard addon disable + reload). Use a module's own page for the "
        .. "reload-free on/off switch instead.", x, y, w - 44, C.subtext, 11)
    y = y - (hh + 16)

    local list = scanSidecars()
    b:Section("PLATFORM ADD-ONS", x, y); y = y - 30

    if #list == 0 then
        b:Wrap("No platform plugin add-ons found in your AddOns folder yet.", x, y, w - 44, C.subtext, 12)
        return y - 40
    end

    local rowW = w - 48
    for _, ad in ipairs(list) do
        local yTop = y
        y = y - 12
        -- Header band: controls centered within a 26px band (see pageOverview for the offsets).
        local hy = y
        b:Glyph(x + 12, hy - 3, { icon = "power", size = 20, color = ad.enabled and C.accent or C.subtext })
        b:Label((ad.title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), x + 42, hy - 5, ad.enabled and C.text or C.subtext, 13)
        b:Badge(x + rowW - 210, hy - 5,
            { text = ad.loaded and "LOADED" or (ad.enabled and "ENABLED" or "DISABLED"),
              variant = ad.loaded and "success" or (ad.enabled and "info" or "neutral") })
        b:Button(x + rowW - 100, hy, 100, ad.enabled and "Disable" or "Enable",
            ad.enabled and "danger" or "primary", function()
                local turnOn = not ad.enabled
                theme:Confirm({
                    title = (turnOn and "Enable " or "Disable ") .. ad.name .. "?",
                    message = (turnOn and "Enable this plugin and reload the UI to load it?"
                        or "Disable this plugin and reload the UI to unload it completely?"),
                    variant = turnOn and "info" or "warning",
                    confirmLabel = "Reload UI",
                    onConfirm = function() setAddonEnabled(ad.name, turnOn); C_UI.Reload() end,
                })
            end)
        y = y - 26
        local meta = ad.version and (ad.name .. "  ·  v" .. ad.version) or ad.name
        b:Label(meta, x + 42, y, C.subtext, 10); y = y - 16
        local amod = moduleForAddon(ad.name)
        if amod then y = whatsNewLink(b, amod.spec, x + 42, y - 2) - 2 end
        b:Box(x, yTop, rowW, yTop - y, 0.03, 0, C.card)
        y = y - 14
    end
    return y - 8
end

----------------------------------------------------------------------
-- Page: About
----------------------------------------------------------------------
local function pageAbout(b, win)
    local C = theme.C
    local w = b.contentWidth
    local x, y = 24, -18
    b:Heading("Twisteds Addon Platform", x, y, "h1"); y = y - 34
    b:Label("Version " .. suiteVersion(), x, y, C.accent, 12); y = y - 26

    local _, hh = b:Wrap("This is the home base for Twisted's collection of add-ons. Rather than a pile "
        .. "of separate add-ons that all look and behave differently, they live here together - sharing "
        .. "one clean look and this single window to turn them on or off and set them up.\n\n"
        .. "Each feature is its own \"module\". Switch on only the ones you want; the rest sit quietly and "
        .. "do nothing. Every module you have installed shows up in the list on the left.",
        x, y, w - 44, C.subtext, 12)
    y = y - (hh + 16)

    -- Getting around (what the sidebar pages do)
    b:Section("GETTING AROUND", x, y); y = y - 30
    for _, line in ipairs({
        { "Overview",    "See all your modules at a glance and jump to any one." },
        { "Settings",    "Change the platform's look - theme, accent colour and font." },
        { "Installed",   "Fully load or unload the add-ons that plug in here." },
        { "The sidebar", "Every module has its own page - click it to configure it." },
    }) do
        b:Label(line[1], x, y - 2, C.accent, 12)
        local _, lh = b:Wrap(line[2], x + 120, y, w - 44 - 120, C.subtext, 11)
        y = y - math.max(22, lh + 8)
    end
    y = y - 8

    -- Your modules (details for everything currently loaded)
    b:Section("YOUR MODULES", x, y); y = y - 30
    if #Suite.modules == 0 then
        b:Wrap("No modules installed yet. Add one of Twisted's plug-in add-ons and it'll appear here "
            .. "(and in the sidebar) automatically.", x, y, w - 44, C.subtext, 11)
        y = y - 40
    else
        for _, mod in ipairs(Suite.modules) do
            local spec = mod.spec
            if spec.icon then b:Glyph(x, y - 3, { icon = spec.icon, size = 18, color = mod:IsActive() and C.accent or C.subtext }) end
            local titleFs = b:Label(spec.title or spec.id, x + 26, y - 2, C.text, 13)
            local sx = x + 26 + (titleFs:GetStringWidth() or 60) + 8
            local ver = addonVersion(spec.addon)
            if ver then
                local verFs = b:Label("v" .. ver, sx, y - 1, C.subtext, 11)
                sx = sx + (verFs:GetStringWidth() or 30) + 10
            end
            b:Badge(sx, y - 1, { text = mod:IsActive() and "ON" or "OFF", variant = mod:IsActive() and "success" or "neutral" })
            y = y - 20
            if spec.desc then
                local _, dh = b:Wrap(spec.desc, x + 26, y, w - 44 - 26, C.subtext, 11)
                y = y - (dh + 6)
            else
                y = y - 6
            end
            y = whatsNewLink(b, spec, x + 26, y) - 6
        end
    end
    y = y - 6

    -- Commands
    b:Section("COMMANDS", x, y); y = y - 30
    b:Label("/tap", x, y, C.accent, 12)
    b:Label("Open this window", x + 170, y, C.subtext, 12)
    y = y - 26

    -- Community
    b:Section("COMMUNITY", x, y); y = y - 30
    local _, ch = b:Wrap("Questions, bug reports, or ideas? Come hang out - click to copy the invite.",
        x, y, w - 44, C.subtext, 11)
    y = y - (ch + 8)
    b:Button(x, y, 170, "Join our Discord", "default", function()
        theme:ShowLinkDialog("Discord - copy this link (Ctrl+C)", "https://discord.com/invite/pN5vYDrQ5j")
    end, { color = "5865F2", textColor = "FFFFFF", icon = theme:GetIcon("discord", "social"), iconSize = 15 })
    y = y - 36
    return y - 16
end

----------------------------------------------------------------------
-- Window construction (dynamic - one nav entry per module).
----------------------------------------------------------------------
local win
local builtSig

-- A signature of the current module set; when it changes we rebuild the window so the sidebar
-- reflects newly installed / removed plugins.
local function moduleSig()
    local ids = {}
    for _, m in ipairs(Suite.modules) do ids[#ids + 1] = m.spec.id end
    return table.concat(ids, ",")
end

local function buildPages()
    local pages = {
        { header = "Platform" },
        { view = "overview",  label = "Overview",  icon = theme:GetIcon("layout-grid"),            render = pageOverview },
        { view = "settings",  label = "Settings",  icon = theme:GetIcon("adjustments-horizontal"), render = pageSettings },
        { view = "installed", label = "Installed", icon = theme:GetIcon("database"),               render = pageInstalled },
    }
    if #Suite.modules > 0 then
        pages[#pages + 1] = { header = "Modules" }
        for _, mod in ipairs(Suite.modules) do
            local m = mod
            pages[#pages + 1] = {
                view   = "mod:" .. m.spec.id,
                label  = m.spec.title or m.spec.id,
                icon   = moduleNavIcon(m.spec),
                render = function(b, w) return pageModule(b, w, m) end,
                -- Let a module reset its page state when its nav entry is (re)clicked.
                onSelect = function() if m.spec.OnSelect then m.spec.OnSelect(m) end end,
            }
        end
    end
    pages[#pages + 1] = { header = "Help" }
    pages[#pages + 1] = { view = "about", label = "About", icon = theme:GetIcon("sparkles"), render = pageAbout }
    return pages
end

local function createWindow()
    builtSig = moduleSig()
    win = theme:Window({
        name = UIF.NextId("TAPManagerWindow"),
        title = "Twisteds Addon Platform",
        logo = theme:GetIcon("adjustments-horizontal"),
        width = 1000, height = 680, sidebarWidth = 220, contentWidth = 740,
        maximizable = true, maxWidthPct = 0.95, maxHeightPct = 0.95,
        contentFluid = true,   -- content stretches to the window width (and grows when maximized)
        savedPos = managerDB().pos,
        onMovePos = function(p) managerDB().pos = p end,
        pages = buildPages(),
        footer = {
            style    = "expanded",
            left     = "Twisteds Addon Platform",
            subtitle = "/tap",
            right    = "v" .. suiteVersion(),
            socials  = { { brand = "discord", url = "https://discord.com/invite/pN5vYDrQ5j" } },
        },
        defaultView = "overview",
    })
    return win
end

-- Does the given view still exist in the current window's pages?
local function viewExists(view)
    if not view then return false end
    for _, p in ipairs(win.opts.pages) do if p.view == view then return true end end
    return false
end

local function ensureWindow()
    if win and builtSig ~= moduleSig() then
        -- Module set changed since the window was built: rebuild it (keep view if still valid).
        local view, shown = win.view, win:IsShown()
        if win.frame then win.frame:Hide() end
        win = nil
        createWindow()
        if not viewExists(view) then view = "overview" end
        if shown then win:Open(view) end
    elseif not win then
        createWindow()
    end
    return win
end

-- Re-render (or rebuild) whenever a module registers or toggles, so the list/pages stay live.
Suite:OnChanged(function()
    if not win then return end
    if builtSig ~= moduleSig() then
        ensureWindow()
    elseif win:IsShown() then
        win:Refresh()
    end
end)

----------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------
SLASH_TAP1 = "/tap"
SlashCmdList["TAP"] = function()
    ensureWindow()
    win:Toggle()
end

-- Hooks a sidecar's engine can use to drive the manager window (e.g. an addon whose engine wants
-- to refresh its live settings page, or open the manager to its own module).
function Suite:RefreshWindow() if win and win:IsShown() then win:Refresh() end end
function Suite:OpenWindow(view)
    ensureWindow()
    if view and viewExists(view) then win:Open(view) else win:Open() end
end
function Suite:CloseWindow() if win and win.frame then win.frame:Hide() end end
function Suite:IsWindowOpen() return win and win:IsShown() and true or false end

-- First-run hint + a font re-apply. Bundled TTFs often aren't loadable yet during the initial
-- addon load (WoW only indexes font files at client launch), so applySavedAppearance() at file
-- scope can fall back to the default font. Re-applying once we're logged in (and again a moment
-- later, since indexing can lag) makes a saved custom font actually stick after a /reload.
local hint = CreateFrame("Frame"); hint:RegisterEvent("PLAYER_LOGIN")
hint:SetScript("OnEvent", function()
    local total = Suite:Stats()
    print(("|cffa06cf0Twisteds Addon Platform|r loaded - |cffffffff/tap|r to manage %d module%s.")
        :format(total, total == 1 and "" or "s"))

    -- Re-assert the full saved appearance now that bundled fonts are loadable (and again a moment
    -- later, since indexing can lag), then refresh the window if it's open.
    local function reassert()
        applySavedAppearance()
        if win and win:IsShown() then win:Refresh() end
    end
    reassert()
    C_Timer.After(1, reassert)
end)
