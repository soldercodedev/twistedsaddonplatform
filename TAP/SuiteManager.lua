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

-- Default suite look, out of the box (overridden by any saved appearance). The look is split
-- into two independent axes: SHAPE (square vs rounded) and a COLOR scheme (palette + accent).
local DEFAULT_SKIN         = "obsidian"       -- seeds NewTheme's palette/accent at creation
local DEFAULT_SHAPE        = "rounded"        -- soft corners out of the box
local DEFAULT_PALETTE_NAME = "obsidian"       -- near-black, cool neutral (steel-blue accent) out of the box

-- "Get Involved" highlight: the page auto-opens ONCE per account, keyed by this campaign string.
-- Bump it in a future update to re-highlight the page for everyone; `/tap getinvolved reset`
-- re-arms it locally for testing.
local WELCOME_CAMPAIGN = "2026-07-runshare"

local theme = UIF:NewTheme({
    name    = "TAPManager",
    skin    = DEFAULT_SKIN,   -- dragon-fire palette + accent (overridden by saved appearance)
    iconDir = ICON_DIR,
})

-- Expose the manager theme so sidecars can match the suite's selected look for their own chrome
-- (e.g. transient dialogs). It's the same object the appearance page mutates, so it stays live.
Suite.uiTheme = theme

-- Base command, listed on Help > Commands. Modules add their own via Suite:RegisterCommand.
Suite:RegisterCommand({ cmd = "/tap", desc = "Open this Manager window", owner = "Platform" })

----------------------------------------------------------------------
-- SavedVariables slots (under the shared suite DB).
----------------------------------------------------------------------
local function managerDB()
    local db = Suite:DB()
    db.manager = db.manager or {}
    return db.manager
end

-- Persisted appearance:
--   { shape = "square"|"rounded",
--     palette = <scheme name>|"custom",
--     custom = { key = {r,g,b}, ... },   -- full palette, only used when palette == "custom"
--     accent = {r,g,b},                  -- accent override on top of a non-custom scheme
--     font = key,
--     menuScale = 1.0 }                   -- proportional scale of the whole /tap panel (text + chrome)
-- Seeded from the live theme. Legacy saves that stored a single `skin` are migrated in place.
local function appearanceDB()
    local m = managerDB()
    m.theme = m.theme or {}
    local t = m.theme
    -- Migrate a legacy bundled-skin setting into the split shape + palette model.
    if t.skin and not t.palette then
        local sk = UIF.SKINS[t.skin]
        t.shape   = (sk and sk.radius and sk.radius > 0) and "rounded" or "square"
        t.palette = (t.skin == "rounded") and "flat" or t.skin   -- "rounded" was flat's palette
        t.skin = nil
    end
    t.shape     = t.shape   or DEFAULT_SHAPE
    t.palette   = t.palette or DEFAULT_PALETTE_NAME
    t.accent    = t.accent  or { theme.C.accent[1], theme.C.accent[2], theme.C.accent[3] }
    t.menuScale = t.menuScale or t.fontScale or 1   -- fontScale = the old key for this setting
    t.fontScale = nil
    return t
end

-- The font is governed SOLELY by the font selector (a.font), defaulting to the suite's bundled
-- Ubuntu. SKINS NEVER DICTATE THE FONT. Re-resolved on each call because a bundled TTF may not be
-- loadable until after login (WoW indexes font files only at client launch).
local function applyFont()
    local a = appearanceDB()
    -- Push the chosen font to EVERY registered theme (hub + each module's own theme) so module
    -- config panels/chrome follow the global choice and a first-login TTF fallback self-corrects.
    if UIF.SetGlobalFont then UIF.SetGlobalFont(a.font or "UBUNTU")
    else theme:ApplyFont(a.font or "UBUNTU") end
end

-- Apply the saved appearance: the COLOR scheme first (a custom palette, or a named scheme +
-- its accent override), then the SHAPE tokens, then the font LAST so nothing overrides the
-- user's chosen font.
local function applySavedAppearance()
    local a = appearanceDB()
    if a.palette == "custom" then
        theme:ApplyCustomPalette(a.custom or {})
    else
        theme:ApplyPalette(a.palette)
        if a.accent then theme:ApplyAccent(a.accent) end
    end
    theme:ApplyShape(a.shape)
    applyFont()
end
applySavedAppearance()

-- Bundled TTFs may not be loadable at file-load (WoW only indexes font files at client launch), so
-- the probe in applyFont() can fall back to the game font on login/reload - that's the "my font
-- reset" bug. Re-apply the saved font once we're logged in (and shortly after) when the TTFs are
-- ready, then refresh any open window so the choice actually sticks.
do
    local fw = CreateFrame("Frame")
    fw:RegisterEvent("PLAYER_LOGIN")
    fw:RegisterEvent("PLAYER_ENTERING_WORLD")
    local function reapply()
        applyFont()
        if _G.TAP and _G.TAP.RefreshWindow then pcall(_G.TAP.RefreshWindow, _G.TAP) end
    end
    fw:SetScript("OnEvent", function(_, ev)
        reapply()
        if C_Timer and C_Timer.After then C_Timer.After(1.5, reapply) end   -- one more pass once fonts settle
        if ev == "PLAYER_ENTERING_WORLD" then fw:UnregisterEvent("PLAYER_ENTERING_WORLD") end
    end)
end

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
local function suiteVersion() return addonVersion("TAP") or "1.1.1" end

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
    local function line(size, color, w2, xoff, s, flags)
        local fs = content:CreateFontString(nil, "OVERLAY")
        fs:SetFont(theme.FONT, size, flags); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetWidth(w2)
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
            if tag == "NOTE" then
                -- A callout: the whole line in the theme accent, outlined so it reads as bold and pops.
                line(12, C.accent, wrapW - 14, 14, "|cff888888-|r  " .. txt, "OUTLINE")
            else
                local prefix = ""
                if tag then
                    local c = TAG_COLOR[tag] or C.subtext
                    prefix = string.format("|cff%02x%02x%02x[%s]|r  ",
                        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), tag)
                end
                line(12, C.text, wrapW - 14, 14, "|cff888888-|r  " .. prefix .. txt)
            end
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
        y = b:Section("NO PLUGINS INSTALLED", x, y); y = y - 34
        b:Wrap("No sidecar modules are registered yet. Install a platform plugin addon (one that "
            .. "lists TAP as a dependency) and it will appear here automatically.",
            x, y, w - 44, C.subtext, 12)
        return y - 60
    end

    y = b:Section("MODULES", x, y); y = y - 30
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

    -- No in-page header: the module's name is shown as the window-title suffix, and its enable/disable
    -- toggle + status live on the Overview and Installed pages. This page is just the module's settings -
    -- it renders straight into its own sections with no redundant "SETTINGS" band on top.

    -- A disabled module normally shows a short "turned off" note here. Modules that own a full tabbed
    -- page (rendersWhenDisabled) instead render themselves even when off, so their Settings tab stays
    -- reachable to re-enable them and the other tabs show the shared MODULE DISABLED overlay.
    if not mod:IsEnabled() and not spec.rendersWhenDisabled then
        b:Wrap("This module is turned off. Switch it on from the Overview page to configure it.",
            x, y, w - 44, C.subtext, 12)
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
-- Page: Settings (suite appearance - shape, colors, accent, font)
----------------------------------------------------------------------

-- Friendly labels for each editable palette variable (Custom mode).
local PALETTE_KEY_LABELS = {
    bg = "Background", sidebar = "Sidebar", panel = "Panel", card = "Card", hover = "Hover",
    border = "Border", accent = "Accent", text = "Text", subtext = "Subtext",
}

-- Menu-scale slider: apply the saved window scale only once the mouse button is released. The slider
-- lives INSIDE the window it scales, so applying live on every drag tick moves the thumb out from under
-- the cursor (the "slider slides away as you drag it" bug). We poll briefly and set the scale when the
-- left button is no longer held - which also covers a value typed into the readout field.
local menuScaleTimer
local function applyMenuScaleWhenReleased(w)
    if menuScaleTimer then menuScaleTimer:Cancel() end
    menuScaleTimer = C_Timer.NewTimer(0.06, function()
        if IsMouseButtonDown and IsMouseButtonDown("LeftButton") then
            applyMenuScaleWhenReleased(w); return   -- still dragging - check again shortly
        end
        menuScaleTimer = nil
        if w and w.frame then w.frame:SetScale(appearanceDB().menuScale or 1) end
    end)
end

-- Ensure a.custom holds an {r,g,b} for every palette variable, seeded from what's on screen
-- now (so entering Custom starts from the current colors). Idempotent - keeps existing edits.
-- IMPORTANT: reuse the existing per-key table instead of replacing it. The color picker holds
-- a reference to the table it edits and fires live during a drag (which triggers win:Refresh ->
-- this reseed); replacing the table here would orphan the picker's edits so the color never
-- sticks. Mutating in place keeps the picker and the saved value pointing at the same table.
local function seedCustomPalette(a)
    a.custom = a.custom or {}
    for _, k in ipairs(UIF.PALETTE_KEYS) do
        if not a.custom[k] then
            local c = theme.C[k] or { 0.5, 0.5, 0.5 }
            a.custom[k] = { c[1], c[2], c[3] }
        end
    end
    return a.custom
end

local function pageSettings(b, win)
    local C = theme.C
    local w = b.contentWidth
    local a = appearanceDB()
    local x, y = 24, -18

    b:Heading("Appearance", x, y, "h1"); y = y - 34
    local _, hh = b:Wrap("Customize the look of the Platform Manager. Pick a shape for the buttons "
        .. "and borders, choose a color scheme, and set the font. Choose |cffffffffCustom|r to set "
        .. "every color yourself. Saved across sessions.", x, y, w - 44, C.subtext, 11)
    y = y - (hh + 16)

    -- SHAPE - buttons: square/sharp vs rounded corners & borders.
    y = b:Section("SHAPE", x, y); y = y - 30
    local sx = x
    for _, name in ipairs(theme:ShapeList()) do
        local active = a.shape == name
        b:Button(sx, y, 132, theme:ShapeLabel(name), active and "primary" or "default", function()
            theme:ApplyShape(name)
            a.shape = name
            win:Refresh()
        end)
        sx = sx + 140
    end
    y = y - 42

    -- COLORS - a scheme dropdown (all palettes), plus a Custom entry.
    y = b:Section("COLORS", x, y); y = y - 30
    b:Label("Scheme", x, y - 2, C.subtext)
    -- Grouped menu: Neutral / Light / Styled / Expansion sections, plus a Custom entry at the end.
    local function schemeItems()
        local items = {}
        for _, g in ipairs(theme:PaletteGroups()) do
            items[#items + 1] = { label = g.header, header = true }
            for _, name in ipairs(g.names) do items[#items + 1] = { label = theme:PaletteLabel(name), value = name } end
        end
        items[#items + 1] = { label = "Custom…", value = "custom" }
        return items
    end
    b:Dropdown(x + 76, y):SetMenu(230, schemeItems, function() return a.palette or DEFAULT_PALETTE_NAME end,
        function(v)
            if v == "custom" then
                seedCustomPalette(a)               -- start from the currently-shown colors
                a.palette = "custom"
                theme:ApplyCustomPalette(a.custom)
            else
                a.palette = v
                theme:ApplyPalette(v)
                a.accent = { theme.C.accent[1], theme.C.accent[2], theme.C.accent[3] }   -- adopt the scheme's accent
            end
            win:Refresh()
        end,
        function(v) return v == "custom" and "Custom…" or theme:PaletteLabel(v) end)
    y = y - 40

    if a.palette == "custom" then
        -- Full palette editor: a swatch + hex for every color variable, in two columns.
        local cust = seedCustomPalette(a)
        b:Wrap("Click a swatch to set each color. These define the whole palette.",
            x, y, w - 44, C.subtext, 10)
        y = y - 20
        local colW, rowTop = (w - 52) / 2, y
        for i, k in ipairs(UIF.PALETTE_KEYS) do
            local col = (i - 1) % 2
            local ry = rowTop - math.floor((i - 1) / 2) * 30
            local cx = x + col * colW
            local label = PALETTE_KEY_LABELS[k] or k
            b:Swatch(cx, ry - 2, cust[k], function()
                theme:ApplyCustomPalette(cust)   -- cust[k] was mutated in place by the swatch
                win:Refresh()
            end, label, "Set the " .. label:lower() .. " color.")
            b:Label(label .. "  ·  #" .. UIF.hexOf(cust[k][1], cust[k][2], cust[k][3]), cx + 28, ry - 4, C.text, 11)
        end
        y = rowTop - math.ceil(#UIF.PALETTE_KEYS / 2) * 30 - 10
    else
        -- Accent override, layered on top of the chosen scheme.
        y = b:Section("ACCENT", x, y); y = y - 30
        b:Swatch(x, y - 2, a.accent, function(r, g, b2)
            theme:ApplyAccent({ r, g, b2 })
            win:Refresh()
        end, "Accent color", "The platform's highlight color, on top of the color scheme.")
        b:Label("Accent color  ·  #" .. UIF.hexOf(a.accent[1], a.accent[2], a.accent[3]), x + 30, y - 4, C.text)
        y = y - 34
    end

    -- Font.
    y = b:Section("FONT", x, y); y = y - 30
    b:FontSelect(x, y, { width = 220, value = a.font or "UBUNTU", onChange = function(key)
        a.font = key
        applyFont()
        win:Refresh()
    end })
    y = y - 42

    -- Menu scale - its own subsection. Scales the whole /tap panel (text + chrome) proportionally.
    -- Applied on RELEASE (not per drag tick) via applyMenuScaleWhenReleased, because the slider sits
    -- inside the window it scales.
    y = b:Section("MENU SCALE", x, y); y = y - 36
    theme:SetTip(b:Slider(x, y):Configure(300, 0.8, 1.5, 0.05,
        function() return a.menuScale or 1 end,
        function(v) a.menuScale = v; applyMenuScaleWhenReleased(win) end, "%.2fx"),
        "Menu scale", "Scales this platform menu (text and everything in it) up or down.")
    y = y - 24
    local _, mh = b:Wrap("Only affects this /tap window - the scoreboard and on-screen combat cues keep "
        .. "their own size.", x, y, w - 44, C.subtext, 10)
    y = y - (mh + 14)

    -- Minimap button (the platform's own; each module toggles its own icon in the module's settings).
    y = b:Section("MINIMAP", x, y); y = y - 30
    theme:SetTip(b:Toggle(x, y - 8, Suite:IsMinimapButtonShown("TAP"),
        function(v) Suite:SetMinimapButtonShown("TAP", v) end, { color = C.accent }),
        "Minimap button", "Show the Twisteds Addon Platform button on the minimap. Left-click opens /tap, "
        .. "drag to move it around the edge, right-click to hide it.")
    b:Label("Show the platform button on the minimap", x + 42, y - 12, C.text, 12)
    y = y - 36

    -- Reset.
    b:Button(x, y, 150, "Reset Appearance", "danger", function()
        managerDB().theme = nil         -- appearanceDB() re-seeds the defaults on next read
        applySavedAppearance()          -- rounded shape + dragon-fire palette + default font
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
    y = b:Section("PLATFORM ADD-ONS", x, y); y = y - 30

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

    -- Full platform logo, with the name + version alongside it.
    local L = 72
    b:Logo(x, y, L, "Interface\\AddOns\\TAP\\assets\\images\\TAP_LOGO_FULL.tga")
    local tx = x + L + 16
    b:Heading("Twisteds Addon Platform", tx, y - 4, "h1")
    b:Label("Version " .. suiteVersion(), tx, y - 38, C.accent, 12)
    y = y - (L + 14)

    local _, hh = b:Wrap("This is the home base for Twisted's collection of add-ons. Rather than a pile "
        .. "of separate add-ons that all look and behave differently, they live here together - sharing "
        .. "one clean look and this single window to turn them on or off and set them up.\n\n"
        .. "Each feature is its own \"module\". Switch on only the ones you want; the rest sit quietly and "
        .. "do nothing. Every module you have installed shows up in the list on the left.",
        x, y, w - 44, C.subtext, 12)
    y = y - (hh + 16)

    -- Getting around (what the sidebar pages do)
    y = b:Section("GETTING AROUND", x, y); y = y - 30
    for _, line in ipairs({
        { "Overview",    "See all your modules at a glance and jump to any one." },
        { "Settings",    "Change the platform's look - theme, accent color and font." },
        { "Installed",   "Fully load or unload the add-ons that plug in here." },
        { "The sidebar", "Every module has its own page - click it to configure it." },
    }) do
        b:Label(line[1], x, y - 2, C.accent, 12)
        local _, lh = b:Wrap(line[2], x + 120, y, w - 44 - 120, C.subtext, 11)
        y = y - math.max(22, lh + 8)
    end
    y = y - 8

    -- Your modules (details for everything currently loaded)
    y = b:Section("YOUR MODULES", x, y); y = y - 30
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

    -- Community
    y = b:Section("COMMUNITY", x, y); y = y - 30
    local _, ch = b:Wrap("Questions, bug reports, or ideas? Come hang out - click to copy the invite.",
        x, y, w - 44, C.subtext, 11)
    y = y - (ch + 8)
    b:Button(x, y, 170, "Join our Discord", "default", function()
        theme:ShowLinkDialog("Discord - copy this link (Ctrl+C)", "https://discord.gg/pN5vYDrQ5j")
    end, { color = "5865F2", textColor = "FFFFFF", icon = theme:GetIcon("discord", "social"), iconSize = 15 })
    y = y - 36
    return y - 16
end

----------------------------------------------------------------------
-- Page: Get Involved. A community call-to-action - Discord, bug reports, ideas, and (the emphasis)
-- sharing your recorded Mythic+ runs so the scoring model's expectations get more accurate. Auto-
-- opens once per account (WELCOME_CAMPAIGN); resettable via /tap getinvolved reset.
----------------------------------------------------------------------
local function pageGetInvolved(b, win)
    local C = theme.C
    local w = b.contentWidth
    local x, y = 24, -18

    b:Heading("Get Involved", x, y, "h1"); y = y - 34
    local _, hh = b:Wrap("Twisted's Addon Platform is built by one person - and it gets better every "
        .. "time |cffffffffyou|r pitch in. Bug reports, ideas, and (most of all) your real Mythic+ "
        .. "runs make it sharper for everyone.", x, y, w - 44, C.subtext, 12)
    y = y - (hh + 18)

    -- Hero callout: share your runs (drawn on an accent-tinted card).
    local yTop = y
    local ix = x + 16
    b:Glyph(ix, y - 4, { icon = "share", size = 20, color = C.accent })
    b:Heading("Share your Mythic+ runs", ix + 30, y - 2, "h3"); y = y - 32
    local _, sh = b:Wrap("The Mythic Ledger grades every player against what their spec is "
        .. "|cffffffffexpected|r to contribute - damage, interrupts, dispels, survival. Those "
        .. "expectations are calibrated from real runs, so the more people share, the more accurate "
        .. "and fair everyone's scores become.", ix, y, w - 44 - 32, C.text, 12)
    y = y - (sh + 10)
    local _, sh2 = b:Wrap("How to share:  it's a one-tap toggle in the beta client - "
        .. "|cffffffffSettings -> Share run log|r. Not on the beta yet? Join our Discord below to "
        .. "grab the client and the quick instructions for sharing your runs with Twisted.", ix, y, w - 44 - 32, C.subtext, 11)
    y = y - (sh2 + 10)
    local _, sh3 = b:Wrap("|cffffd200Thank-you:|r anyone who shares their data gets a personal "
        .. "shout-out credited right here in the addon for everyone to see - entirely your call. "
        .. "Prefer to stay anonymous? That's totally fine too; your runs help either way.", ix, y, w - 44 - 32, C.subtext, 11)
    y = y - (sh3 + 12)
    b:Box(x, yTop + 8, w - 44, (yTop + 8) - (y - 6), 0.06, 0, C.accent)
    y = y - 16

    -- Community / Discord.
    y = b:Section("IDEAS, BUGS & HANGOUTS", x, y); y = y - 30
    local _, ch = b:Wrap("Got a suggestion or hit a bug? The fastest way to reach me is Discord - "
        .. "come say hi, grab the beta client, or tell me what's broken.", x, y, w - 44, C.subtext, 11)
    y = y - (ch + 10)
    b:Button(x, y, 190, "Join our Discord", "default", function()
        theme:ShowLinkDialog("Discord - copy this link (Ctrl+C)", "https://discord.gg/pN5vYDrQ5j")
    end, { color = "5865F2", textColor = "FFFFFF", icon = theme:GetIcon("discord", "social"), iconSize = 15 })
    y = y - 40
    return y - 16
end

----------------------------------------------------------------------
-- Page: Commands (every slash command across the platform + its modules, grouped by owner).
-- Modules contribute via Suite:RegisterCommand{ cmd, desc, owner, subcommands }.
----------------------------------------------------------------------
local function pageCommands(b, win)
    local C = theme.C
    local w = b.contentWidth
    local x, y = 24, -18

    b:Heading("Commands", x, y, "h1"); y = y - 34
    local _, hh = b:Wrap("Every slash command across the platform and its installed modules. "
        .. "Type |cffffffff/tap|r on its own to open this window.", x, y, w - 44, C.subtext, 11)
    y = y - (hh + 16)

    -- Group by owner, preserving the order owners first appear in the registry.
    local order, byOwner = {}, {}
    for _, c in ipairs(Suite:GetCommands()) do
        local o = c.owner or "Platform"
        if not byOwner[o] then byOwner[o] = {}; order[#order + 1] = o end
        table.insert(byOwner[o], c)
    end
    if #order == 0 then
        b:Wrap("No commands registered.", x, y, w - 44, C.subtext, 12)
        return y - 30
    end

    for _, o in ipairs(order) do
        y = b:Section(o:upper(), x, y); y = y - 30
        for _, c in ipairs(byOwner[o]) do
            b:Label(c.cmd, x, y - 2, C.accent, 12)
            if c.desc then b:Label(c.desc, x + 210, y - 2, C.subtext, 12) end
            y = y - 22
            if c.subcommands then
                for _, sc in ipairs(c.subcommands) do
                    b:Label(c.cmd .. " " .. sc[1], x + 16, y - 2, C.text, 11)
                    if sc[2] then b:Label(sc[2], x + 210, y - 2, C.subtext, 11) end
                    y = y - 20
                end
            end
        end
        y = y - 12
    end
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
                -- Shown after the platform name in the window title while this module is selected.
                titleSuffix = "  ·  " .. (m.spec.title or m.spec.id),
                render = function(b, w) return pageModule(b, w, m) end,
                -- Let a module reset its page state when its nav entry is (re)clicked.
                onSelect = function() if m.spec.OnSelect then m.spec.OnSelect(m) end end,
                -- Let a module tidy up (e.g. hide a persistent frame) when you navigate away from it.
                onDeselect = function() if m.spec.OnDeselect then m.spec.OnDeselect(m) end end,
            }
        end
    end
    pages[#pages + 1] = { header = "Help" }
    pages[#pages + 1] = { view = "getinvolved", label = "Get Involved", icon = theme:GetIcon("heart"), render = pageGetInvolved }
    pages[#pages + 1] = { view = "commands", label = "Commands", icon = theme:GetIcon("chevron-right"), render = pageCommands }
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
        -- "Menu scale": scale the whole /tap panel (text + chrome) proportionally. Per-frame, so it
        -- never touches the scoreboard, combat-alert cues, or any other addon frame. Read live each
        -- Refresh so a saved scale is re-applied on open.
        onScale = function() return appearanceDB().menuScale or 1 end,
        pages = buildPages(),
        footer = {
            style    = "expanded",
            left     = "Twisteds Addon Platform",
            subtitle = "/tap",
            right    = "v" .. suiteVersion(),
            socials  = { { brand = "discord", url = "https://discord.gg/pN5vYDrQ5j" } },
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
SlashCmdList["TAP"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg ~= "" then
        local sub, rest = msg:match("^(%S+)%s*(.*)$")
        if Suite:RunCommand(sub, rest) then return end
        print("|cffa06cf0Twisteds Addon Platform|r: unknown command '" .. sub
            .. "' - type |cffffffff/tap|r for the Manager, or open Help > Commands.")
        return
    end
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

----------------------------------------------------------------------
-- "Get Involved" spotlight: open it (and let the dev re-arm the first-run auto-open).
--   /tap getinvolved        - open the page
--   /tap getinvolved reset  - re-arm the once-per-account auto-open (pops again next login/reload)
----------------------------------------------------------------------
Suite:RegisterCommand({
    cmd = "/tap getinvolved", sub = "getinvolved", owner = "Platform",
    desc = "Open Get Involved (add 'reset' to re-show it on next login)",
    handler = function(rest)
        if (rest or ""):lower():gsub("%s+", "") == "reset" then
            managerDB().welcomeSeen = nil
            print("|cffa06cf0Twisteds Addon Platform|r: Get Involved spotlight re-armed - it'll pop again on next login/reload.")
        else
            Suite:OpenWindow("getinvolved")
        end
    end,
})

-- Auto-open the Get Involved page once per account per campaign, shortly after entering the world.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if managerDB().welcomeSeen == WELCOME_CAMPAIGN then return end
        if not (C_Timer and C_Timer.After) then return end
        C_Timer.After(2.5, function()
            local m = managerDB()
            if m.welcomeSeen == WELCOME_CAMPAIGN then return end   -- opened/reset in the meantime
            m.welcomeSeen = WELCOME_CAMPAIGN
            Suite:OpenWindow("getinvolved")
        end)
    end)
end

----------------------------------------------------------------------
-- Minimap buttons - one for the PLATFORM (shown by default) plus an optional one per MODULE (each
-- registers its own via Suite:RegisterMinimapButton, hidden by default). Every button is draggable
-- around the minimap edge; its angle + hidden state persist in TAPDB.minimap[id].
----------------------------------------------------------------------
local minimapButtons = {}   -- id -> { id, icon, title, action, onClick, defaultHidden, defaultAngle, frame }
local minimapReady = false
local minimapOrder = 0      -- stagger default angles so newly-shown buttons don't stack

local function minimapDB(id)
    local db = Suite:DB()
    db.minimap = db.minimap or {}
    -- Migrate the old single-button format ({ angle, hide }) into the platform's entry.
    if db.minimap.angle ~= nil or db.minimap.hide ~= nil then
        db.minimap.TAP = db.minimap.TAP or { angle = db.minimap.angle, hide = db.minimap.hide }
        db.minimap.angle, db.minimap.hide = nil, nil
    end
    db.minimap[id] = db.minimap[id] or {}
    return db.minimap[id]
end

local function positionMinimapBtn(rec)
    if not (rec.frame and _G.Minimap) then return end
    local a = math.rad(minimapDB(rec.id).angle or rec.defaultAngle or 205)
    rec.frame:SetPoint("CENTER", _G.Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

local function createMinimapFrame(rec)
    if rec.frame or not _G.Minimap then return end
    local d = minimapDB(rec.id)
    if d.hide == nil then d.hide = rec.defaultHidden and true or false end
    local b = CreateFrame("Button", "TAPMinimap_" .. rec.id, _G.Minimap)
    rec.frame = b
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton"); b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(19, 19); icon:SetTexture(rec.icon); icon:SetPoint("CENTER", 0, 1)

    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53); ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); ring:SetPoint("TOPLEFT")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function dragUpdate()
        local mx, my = _G.Minimap:GetCenter()
        local scale = _G.Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        if not (mx and my and cx and cy and scale and scale > 0) then return end
        minimapDB(rec.id).angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
        positionMinimapBtn(rec)
    end
    b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", dragUpdate) end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Suite:SetMinimapButtonShown(rec.id, false)
            print("|cffa06cf0Twisteds Addon Platform|r: minimap button hidden - re-enable it in its settings (Platform: |cffffffff/tap minimap|r).")
        else
            rec.onClick()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(rec.title or "|cffa06cf0Twisted's Addon Platform|r")
        GameTooltip:AddLine("Left-click: " .. (rec.action or "open"), 1, 1, 1)
        GameTooltip:AddLine("Right-click: hide  -  Drag: move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    positionMinimapBtn(rec)
    if d.hide then b:Hide() end
end

-- Register (or update) a minimap button. Records the spec; the frame is built at login (or immediately
-- if we're already past login). spec = { icon, title, action, onClick, defaultHidden, defaultAngle }.
function Suite:RegisterMinimapButton(id, spec)
    if type(id) ~= "string" or type(spec) ~= "table" or not spec.icon or type(spec.onClick) ~= "function" then return end
    local rec = minimapButtons[id]
    if not rec then
        minimapOrder = minimapOrder + 1
        rec = { id = id, defaultAngle = spec.defaultAngle or (225 - minimapOrder * 22) }
        minimapButtons[id] = rec
    end
    rec.icon, rec.title, rec.action, rec.onClick = spec.icon, spec.title, spec.action, spec.onClick
    rec.defaultHidden = spec.defaultHidden and true or false
    if minimapReady then createMinimapFrame(rec) end
    return rec
end

function Suite:SetMinimapButtonShown(id, shown)
    minimapDB(id).hide = not shown
    local rec = minimapButtons[id]
    if rec then
        if not rec.frame then createMinimapFrame(rec) end
        if rec.frame then if shown then rec.frame:Show() else rec.frame:Hide() end end
    end
end
function Suite:IsMinimapButtonShown(id) return not minimapDB(id).hide end

-- Build every registered button (called once at login, when the SavedVariables + Minimap exist).
local function createAllMinimapButtons()
    minimapReady = true
    for _, rec in pairs(minimapButtons) do createMinimapFrame(rec) end
end

-- The platform's own button - shown by default, opens the Manager.
Suite:RegisterMinimapButton("TAP", {
    icon = "Interface\\AddOns\\TAP\\assets\\images\\TAP_icon.tga",
    title = "|cffa06cf0Twisted's Addon Platform|r", action = "open the Manager",
    onClick = function() ensureWindow(); win:Toggle() end,
    defaultHidden = false, defaultAngle = 205,
})

Suite:RegisterCommand({
    cmd = "/tap minimap", desc = "Show or hide the platform minimap button", owner = "Platform", sub = "minimap",
    handler = function() Suite:SetMinimapButtonShown("TAP", not Suite:IsMinimapButtonShown("TAP")) end,
})

-- First-run hint + a font re-apply. Bundled TTFs often aren't loadable yet during the initial
-- addon load (WoW only indexes font files at client launch), so applySavedAppearance() at file
-- scope can fall back to the default font. Re-applying once we're logged in (and again a moment
-- later, since indexing can lag) makes a saved custom font actually stick after a /reload.
local hint = CreateFrame("Frame"); hint:RegisterEvent("PLAYER_LOGIN")
hint:SetScript("OnEvent", function()
    local total = Suite:Stats()
    print(("|cffa06cf0Twisteds Addon Platform|r loaded - |cffffffff/tap|r to manage %d module%s.")
        :format(total, total == 1 and "" or "s"))
    createAllMinimapButtons()

    -- Re-assert the full saved appearance now that bundled fonts are loadable (and again a moment
    -- later, since indexing can lag), then refresh the window if it's open.
    local function reassert()
        applySavedAppearance()
        if win and win:IsShown() then win:Refresh() end
    end
    reassert()
    C_Timer.After(1, reassert)
end)
