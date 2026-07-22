-- UIFoundry - Showcase.lua
-- A component gallery + self-test that exercises every widget, form control, picker, dialog,
-- icon, and toast. It has no slash command; open it via UIF._demoWindow:Toggle() (tests /
-- external triggering). It's also the
-- reference for how a consuming addon wires UIFoundry up. Delete this file (and its TOC
-- line) to ship the library alone. It points iconDir at the bundled assets/icons folder.

local ADDON, _P = ...
local UIF = _G.UIFoundry

-- One theme for the demo. A real addon would pass its own name + accent (and optionally a
-- bundled font / a fonts registry for the Preview font dropdown). iconDir points at the
-- bundled Tabler + social TGAs so icons render everywhere.
local theme = UIF:NewTheme({
    name    = "UIFoundryShowcase",
    accent  = { 0.04, 0.34, 0.79 },
    iconDir = "Interface\\AddOns\\TAP\\assets\\icons\\",
})

-- Scratch state the demo widgets bind to (stands in for a real addon's saved variables).
local state = {
    enabled = true, loop = false, pulse = true,
    channel = "Master", zone = "any",
    name = "My Alert", volume = 6, scale = 1.0,
    color = { 1, 0.35, 0.2 },
    accent = { 0.04, 0.34, 0.79 },
    action = { iconX = 0, iconY = 40 },
    picked = "spell_holy_flashheal",
    iconVariant = "outline", iconColor = { 0.55, 0.85, 1 },
    toastPos = "TOP", toastAnim = "fade",
    dd = "a", ddIcon = "flame", spell = nil, combo = "coffee",
    fontKey = "UBUNTU", rlo = 20, rhi = 80, single = 50,
    toastSoundOn = true, toastSound = "AirHorn",
    scene = "dusk", sceneAnimated = false, toastInWindow = false,
    skin = "flat",
}

-- Demo data for the menu / select page.
local ICON_ITEMS = {
    { value = "flame", label = "Fire", icon = "flame" }, { value = "snowflake", label = "Frost", icon = "snowflake" },
    { value = "bolt", label = "Nature", icon = "bolt" }, { value = "skull", label = "Shadow", icon = "skull" },
}
local FRUIT = {
    { value = "apple", label = "Apple", icon = "apple" }, { value = "coffee", label = "Coffee", icon = "coffee" },
    { value = "gift", label = "Gift", icon = "gift" }, { value = "star", label = "Star", icon = "star" },
    { value = "heart", label = "Heart", icon = "heart" }, { value = "flask", label = "Flask", icon = "flask" },
    { value = "sword", label = "Sword", icon = "sword" }, { value = "shield", label = "Shield", icon = "shield" },
    { value = "crown", label = "Crown", icon = "crown" }, { value = "diamond", label = "Diamond", icon = "diamond" },
}
local SPELL_MENU = {
    { label = "Recent", header = true },
    { label = "Fireball", value = "fireball", icon = "flame" },
    { label = "Frost", icon = "snowflake", submenu = { { label = "Frostbolt", value = "frostbolt", icon = "snowflake" }, { label = "Ice Lance", value = "icelance", icon = "snowflake" } } },
    { label = "Nature", icon = "leaf", submenu = { { label = "Lightning", value = "lightning", icon = "bolt" }, { label = "Healing Touch", value = "heal", icon = "heart" } } },
    { label = "Physical", icon = "sword", submenu = { { label = "Slam", value = "slam", icon = "sword" }, { label = "Cleave", value = "cleave", icon = "swords" }, { label = "Shield Bash", value = "bash", icon = "shield" } } },
}
local function spellLabel(v)
    local function scan(items) for _, it in ipairs(items) do if it.value == v then return it.label end if it.submenu then local r = scan(it.submenu); if r then return r end end end end
    return scan(SPELL_MENU) or "Choose a spell..."
end

local ICON = "Interface\\ICONS\\"
local CHANNELS = { { "Master", "Master (recommended)" }, { "SFX", "Sound Effects" }, { "Music", "Music" }, { "Ambience", "Ambience" } }
local ZONES = { { "any", "Anywhere" }, { "none", "Open world" }, { "party", "Dungeon" }, { "raid", "Raid" } }

-- A curated icon set for the OpenIconPicker demo (built-in spell icons).
local ICON_SET = {}
for _, n in ipairs({
    "spell_holy_flashheal", "spell_fire_flamebolt", "ability_hunter_killcommand", "spell_frost_frostbolt02",
    "ability_warrior_savageblow", "spell_shadow_shadowbolt", "spell_nature_lightning", "inv_potion_54",
    "ability_rogue_sprint", "spell_holy_powerwordshield", "spell_arcane_blast", "ability_druid_maul",
}) do
    ICON_SET[#ICON_SET + 1] = { value = n, texture = ICON .. n, label = n, coords = UIF.ICON_INSET }
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------
local function pageSkins(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("SKINS  (color + shape)", x, y); y = y - 30
    local _, h = b:Wrap("A skin changes the |cffffffffpalette|r AND the |cffffffffshape|r - corner radius, border weight, and font. "
        .. "Click one to restyle the entire window live.", x, y, win.opts.contentWidth - 44, C.subtext, 11)
    y = y - (h + 14)

    -- Base skins as quick buttons, plus a dropdown with every skin (incl. all expansions).
    local sx = x
    for _, name in ipairs({ "flat", "rounded", "modern", "blizzard", "neon" }) do
        local active = state.skin == name
        b:Button(sx, y, 88, theme:SkinLabel(name), active and "primary" or "default", function()
            state.skin = name; theme:ApplySkin(name); win:Refresh()
        end)
        sx = sx + 94
    end
    y = y - 38
    b:Label("Expansion themes", x, y - 2, C.subtext)
    local choices = {}
    for _, name in ipairs(theme:SkinList()) do choices[#choices + 1] = { name, theme:SkinLabel(name) } end
    b:Dropdown(x + 130, y):SetChoices(240, choices, function() return state.skin end, function(v)
        state.skin = v; theme:ApplySkin(v); win:Refresh()
    end)
    y = y - 42

    y = b:Section("PREVIEW", x, y); y = y - 30
    b:Button(x, y, 100, "Primary", "primary", function() end)
    b:Button(x + 108, y, 100, "Default", "default", function() end)
    b:Button(x + 216, y, 100, "Danger", "danger", function() end)
    b:Toggle(x + 330, y + 3, true, function() end)
    b:Label("Toggle", x + 372, y + 1, C.text)
    y = y - 38
    b:EditBox(x, y, 200, "Input field")
    b:Dropdown(x + 216, y):SetChoices(160, { { "a", "Dropdown" }, { "b", "Other" } }, function() return "a" end, function() end)
    y = y - 42
    local c = b:Card(x, y, { width = 210, height = 84, title = "Card", variant = "accent" })
    theme:Heading(c.body, { text = "Panels + cards adopt the skin's corner radius and border.", role = "caption", wrapWidth = 178 }):SetPoint("TOPLEFT", 0, 0)
    b:Badge(x + 226, y, { text = "SUCCESS", variant = "success" })
    b:Badge(x + 226, y - 26, { text = "PILL", variant = "accent", pill = true })
    b:ProgressBar(x + 226, y - 54, { width = 150, height = 12, value = 60, color = "accent" })
    y = y - 100
    return y
end

local function pageWidgets(b, win)
    local C = theme.C
    local x, y = 24, -20

    y = b:Section("BASIC CONTROLS", x, y); y = y - 34
    theme:SetTip(b:Toggle(x, y, state.enabled, function(v) state.enabled = v end),
        "Toggle", "A themed on/off switch. Hover me - this is the tooltip system.")
    b:Label("Enable feature", x + 46, y - 2, C.text)
    theme:SetTip(b:Toggle(x + 220, y, state.loop, function(v) state.loop = v end), "Loop", "Another toggle.")
    b:Label("Loop", x + 266, y - 2, C.text)
    y = y - 40

    b:Label("Name", x, y - 2, C.subtext)
    theme:SetTip(b:EditBox(x + 46, y, 220, state.name, function(t) state.name = t end),
        "Text input", "Commits on Enter or focus loss.")
    y = y - 38

    b:Label("Channel", x, y - 2, C.subtext)
    theme:SetTip(b:Dropdown(x + 66, y), "Dropdown", "A self-skinned dropdown menu."):SetChoices(
        180, CHANNELS, function() return state.channel end, function(v) state.channel = v end)
    b:Label("Zone", x + 262, y - 2, C.subtext)
    b:Dropdown(x + 300, y):SetChoices(160, ZONES, function() return state.zone end, function(v) state.zone = v end)
    y = y - 40

    b:Label("Volume", x, y - 2, C.subtext)
    theme:SetTip(b:Slider(x + 66, y - 2), "Slider", "Snaps to the step; shows its value above the thumb."):Configure(
        200, 0, 10, 1, function() return state.volume end, function(v) state.volume = v end, "%d")
    y = y - 42

    y = b:Section("BUTTONS", x, y); y = y - 34
    b:Button(x, y, 110, "Primary", "primary", function() print("UIFoundry: primary click") end)
    b:Button(x + 120, y, 110, "Default", "default", function() print("UIFoundry: default click") end)
    b:Button(x + 240, y, 110, "Danger", "danger", function() print("UIFoundry: danger click") end)
    y = y - 44

    y = b:Section("ICON + COLOR", x, y); y = y - 34
    local ic = b:Icon(x, y - 2); ic:SetSize(28, 28)
    ic.tex:SetTexture(ICON .. state.picked)
    theme:SetTip(ic, "Icon button", "Click to pick from a grid of icons.")
    ic:SetScript("OnEnter", theme.showTip); ic:SetScript("OnLeave", GameTooltip_Hide)
    ic:SetScript("OnClick", function()
        theme:OpenIconPicker({
            title = "Pick an Icon", icons = ICON_SET, current = state.picked, columns = 6, cell = 40,
            onPick = function(v) if v then state.picked = v end win:Refresh() end,
        })
    end)
    b:Label("Icon picker", x + 40, y - 10, C.text)

    b:Label("Text color", x + 200, y - 10, C.subtext)
    b:Swatch(x + 280, y - 8, state.color, function() win:Refresh() end, "Text color", "Opens the color picker.")
    y = y - 48

    y = b:Section("PREVIEW (drag the icon)", x, y); y = y - 30
    local pv = b:Preview(x, y, win.opts.contentWidth - 40, 92)
    pv.fs:SetFont(theme.FONT, 30, "THICKOUTLINE")
    pv.fs:SetText(state.name ~= "" and state.name or "ALERT")
    pv.fs:SetTextColor(state.color[1], state.color[2], state.color[3])
    if state.pulse then if not pv.pulse:IsPlaying() then pv.pulse:Play() end else pv.pulse:Stop() end
    pv.iconBtn:SetSize(28, 28); pv.iconBtn.tex:SetTexture(ICON .. state.picked)
    pv.iconBtn:ClearAllPoints(); pv.iconBtn:SetPoint("CENTER", pv.fs, "CENTER", state.action.iconX, state.action.iconY)
    pv.iconBtn:Show()
    pv:Bind(state.action, 1, function() end)
    y = y - 104

    return y
end

local function pagePickers(b, win)
    local C = theme.C
    local x, y = 24, -20
    y = b:Section("PICKERS & DIALOGS", x, y); y = y - 34
    local _, h = b:Wrap("Every popup is themed and drag-movable. These are the same components a "
        .. "real addon calls: |cffffffffcolor picker|r, |cfffffffficon grid|r, |cffffffffcopy/paste dialog|r, and a "
        .. "|cffffffffkey-capture|r prompt.", x, y, win.opts.contentWidth - 44, C.subtext, 12)
    y = y - (h + 16)

    b:Button(x, y, 180, "Open color picker", "primary", function()
        theme:OpenColorPicker(state.color[1], state.color[2], state.color[3], function(r, g, b2)
            state.color[1], state.color[2], state.color[3] = r, g, b2
        end)
    end)
    b:Button(x + 190, y, 180, "Open icon picker", "default", function()
        theme:OpenIconPicker({ title = "Pick an Icon", icons = ICON_SET, current = state.picked, columns = 6, cell = 40,
            onPick = function(v) if v then state.picked = v end win:Refresh() end })
    end)
    y = y - 40

    b:Button(x, y, 180, "Copy (export) dialog", "default", function()
        theme:ShowCopyDialog("Export - copy this (Ctrl+C)", "UIFOUNDRY-DEMO-STRING-" .. state.name, "Selected for you - Ctrl+C.")
    end)
    b:Button(x + 190, y, 180, "Paste (import) dialog", "default", function()
        theme:ShowInputDialog("Import", "Paste anything, then Accept.", "Accept", function(txt)
            if txt == "" then return "|cffff5555Nothing pasted.|r" end
            print("UIFoundry import got:", txt)
        end)
    end)
    y = y - 40

    b:Button(x, y, 250, "Copy link (single-line, auto-close)", "default", function()
        theme:ShowLinkDialog("Copy this link (Ctrl+C)", "https://example.com/uifoundry", { autoClose = true })
    end)
    y = y - 40

    b:Button(x, y, 180, "Capture a key", "default", function()
        theme:CaptureKey({ title = "Press any key", onDone = function(combo, cancelled)
            print("UIFoundry key capture:", cancelled and "cancelled" or combo)
        end })
    end)
    y = y - 48

    y = b:Section("LIVE THEME ACCENT", x, y); y = y - 34
    b:Label("Accent", x, y - 2, C.subtext)
    b:Swatch(x + 66, y, state.accent, function(r, g, bb)
        theme:ApplyAccent({ r, g, bb }); win:Refresh()   -- recolor the whole window live
    end, "Theme accent", "Recolors every UIFoundry widget in this window live.")
    b:Wrap("Change the accent and watch the sidebar, buttons, sliders, and tooltips all follow.",
        x + 100, y - 2, win.opts.contentWidth - 160, C.subtext, 11)
    y = y - 48

    return y
end

local function pageType(b, win)
    local x, y = 24, -18
    y = b:Section("HEADING ROLES", x, y); y = y - 30
    for _, r in ipairs({ "display", "h1", "h2", "h3", "h4", "h5", "h6", "subtitle", "overline", "caption" }) do
        b:Heading(r:upper() .. "  -  The quick brown fox", x, y, r)
        local sz = UIF.HEADING_ROLES[r].fontSize
        y = y - (sz + 8)
    end
    y = y - 6
    y = b:Section("OVERRIDE ANYTHING AT DRAW TIME", x, y); y = y - 30
    b:Heading("Recolored + resized", x, y, "h3", { textColor = "20C997", fontSize = 20 }); y = y - 30
    b:Heading("Accent, bold outline", x, y, "h4", { textColor = "accent", fontFlags = "OUTLINE" }); y = y - 34
    return y
end

local function pageForms(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("INPUTS", x, y); y = y - 30
    b:Label("Search", x, y - 2, C.subtext)
    b:SearchBox(x + 60, y, { width = 240, placeholder = "Filter things...", onChange = function() end }); y = y - 36
    b:Label("Stepper", x, y - 2, C.subtext)
    b:Stepper(x + 60, y, { value = state.volume, min = 0, max = 20, width = 120, onChange = function(v) state.volume = v end }); y = y - 36
    b:Label("Segmented", x, y - 2, C.subtext)
    b:SegmentedControl(x + 76, y, { segments = { { value = "d", label = "Day" }, { value = "w", label = "Week" }, { value = "m", label = "Month" } }, value = state.seg or "d", width = 260, onChange = function(v) state.seg = v end }); y = y - 40
    b:Label("Radios", x, y - 2, C.subtext)
    b:RadioGroup(x + 76, y + 2, { horizontal = true, spacing = 110, options = { { value = "a", label = "Option A" }, { value = "b", label = "Option B" } }, value = state.radio or "a", onChange = function(v) state.radio = v end }); y = y - 40
    b:Label("Notes", x, y - 2, C.subtext)
    b:TextArea(x + 76, y, { width = 320, height = 72, value = "Multi-line text area...\nType here." })
    y = y - 84   -- leave the full text-area height before the next section

    y = b:Section("PROGRESS", x, y); y = y - 30
    b:ProgressBar(x, y, { width = 300, height = 16, value = state.volume * 5, color = "20C997", showText = true, format = "%d%%" }); y = y - 28
    b:ProgressBar(x, y, { width = 300, height = 8, value = 65, color = "accent" }); y = y - 24
    b:Label("Indeterminate", x + 44, y - 1, C.subtext)
    b:ProgressBar(x, y, { width = 30, height = 14 }):SetIndeterminate(true)
    b:Spinner(x + 170, y - 2, { size = 18 }); y = y - 34
    return y
end

local function pageDisplay(b, win)
    local x, y = 24, -18
    y = b:Section("BADGES  (square, pill, rounded)", x, y); y = y - 30
    local bx = x
    for _, v in ipairs({ "accent", "success", "warning", "danger", "info", "neutral" }) do
        local bd = b:Badge(bx, y, { text = v:upper(), variant = v }); bx = bx + bd:GetWidth() + 8
    end
    b:Badge(bx, y, { text = "DOT", variant = "success", dot = true }); y = y - 28
    local px = x
    for _, v in ipairs({ "accent", "success", "warning", "danger", "info" }) do
        local bd = b:Badge(px, y, { text = v:upper(), variant = v, pill = true }); px = px + bd:GetWidth() + 8
    end
    local nb = b:Badge(px, y, { text = "9", variant = "danger", pill = true }); px = px + nb:GetWidth() + 8
    b:Badge(px, y, { text = "rounded", variant = "info", radius = 6 }); y = y - 30
    -- shadow + border pills
    local zx = x
    local z1 = b:Badge(zx, y, { text = "SHADOW", variant = "accent", pill = true, shadow = true }); zx = zx + z1:GetWidth() + 10
    local z2 = b:Badge(zx, y, { text = "BORDER", variant = "success", pill = true, border = { color = "FFFFFF", size = 1 } }); zx = zx + z2:GetWidth() + 10
    b:Badge(zx, y, { text = "BOTH", variant = "danger", pill = true, border = { color = "FFFFFF" }, shadow = { spread = 5, alpha = 0.5 } }); y = y - 34

    y = b:Section("STAT TILES", x, y); y = y - 30
    b:StatTile(x, y, { label = "DPS", value = "128k", delta = "+12%", trend = "up", width = 150 })
    b:StatTile(x + 162, y, { label = "Deaths", value = "3", delta = "-1", trend = "down", width = 150 })
    b:StatTile(x + 324, y, { label = "Item lvl", value = "489", width = 150 })
    y = y - 84

    b:Separator(x, y, { width = win.opts.contentWidth - 48, label = "TABS & ACCORDION" }); y = y - 26
    b:TabBar(x, y, { tabs = { { value = "a", label = "Overview" }, { value = "b", label = "Details" }, { value = "c", label = "Log" } }, value = state.tab or "a", tabWidth = 110, onChange = function(v) state.tab = v; win:Refresh() end })
    y = y - 40
    local ac = b:Accordion(x, y, { title = "Advanced settings", width = win.opts.contentWidth - 48, bodyHeight = 44,
        expanded = state.acc, onToggle = function(v) state.acc = v; win:Refresh() end,
        chevron = theme:GetIcon("chevron-right") })
    -- Real body content, parented to the accordion body so it hides when collapsed.
    local bodyText = theme:Heading(ac.body, { text = "This content lives inside the accordion body and hides when you collapse it. Click the header to toggle.",
        role = "caption", wrapWidth = win.opts.contentWidth - 80 })
    bodyText:SetPoint("TOPLEFT", 14, -6)
    y = y - ac:GetHeight() - 10
    return y
end

local function pageSocial(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("SOCIAL BUTTONS", x, y); y = y - 30
    local _, h = b:Wrap("Real brand buttons with official colors. Set |cfffffffficonDir|r on your theme to show the "
        .. "Tabler |cffffffffbrand-*|r icons (see ICONS.md); without it they fall back to the label in the brand color, "
        .. "as below. Click copies the link.", x, y, win.opts.contentWidth - 44, C.subtext, 11)
    y = y - (h + 14)

    b:SocialButton(x, y, { brand = "discord", label = "Discord", url = "https://discord.com/invite/xxxx" })
    b:SocialButton(x + 130, y, { brand = "github", label = "GitHub", url = "https://github.com/xxxx" })
    b:SocialButton(x + 250, y, { brand = "patreon", label = "Patreon", url = "https://patreon.com/xxxx" })
    y = y - 38
    b:SocialButton(x, y, { brand = "youtube", label = "YouTube", url = "https://youtube.com/@x" })
    b:SocialButton(x + 130, y, { brand = "twitch", label = "Twitch", url = "https://twitch.tv/x" })
    y = y - 40
    b:Label("Icon-only bar:", x, y - 2, C.subtext)
    b:SocialBar(x + 100, y - 2, {
        { brand = "discord", url = "a" }, { brand = "github", url = "b" }, { brand = "youtube", url = "c" },
        { brand = "twitch", url = "d" }, { brand = "patreon", url = "e" },
    }, { gap = 6, iconOnly = true, size = 28 })
    y = y - 44

    y = b:Section("TOASTS", x, y); y = y - 30
    b:Label("Position", x, y - 2, C.subtext)
    b:SegmentedControl(x + 66, y, { width = 300, value = state.toastPos, onChange = function(v) state.toastPos = v end,
        segments = { { value = "TOP", label = "Top" }, { value = "TOP-RIGHT", label = "Top-R" }, { value = "BOTTOM-RIGHT", label = "Bot-R" }, { value = "CENTER", label = "Center" } } })
    b:Label("Anim", x + 380, y - 2, C.subtext)
    b:SegmentedControl(x + 420, y, { width = 150, value = state.toastAnim, onChange = function(v) state.toastAnim = v end,
        segments = { { value = "fade", label = "Fade" }, { value = "slide", label = "Slide" } } })
    y = y - 36
    -- Optional notification sound.
    b:Toggle(x, y, state.toastSoundOn, function(v) state.toastSoundOn = v end)
    b:Label("Play sound", x + 46, y - 2, C.text)
    b:SoundSelect(x + 130, y, { width = 200, value = state.toastSound, channel = "Master",
        onChange = function(k) state.toastSound = k end })
    b:Button(x + 340, y, 70, "Test", "default", function() theme:PlaySound(state.toastSound) end)
    y = y - 34
    -- Spawn relative to the viewport (whole screen) or within this window's bounds.
    b:Toggle(x, y, state.toastInWindow, function(v) state.toastInWindow = v end)
    b:Label("Spawn inside this window (instead of the whole screen)", x + 46, y - 2, C.text)
    y = y - 34
    local function toastOpts(o)
        o.position, o.animation = state.toastPos, state.toastAnim
        if state.toastSoundOn then o.sound = state.toastSound end
        if state.toastInWindow then o.parent, o.inset = win.frame, 10 end
        return o
    end
    b:Button(x, y, 120, "Info", "default", function() theme:Toast(toastOpts({ text = "Just so you know." })) end)
    b:Button(x + 128, y, 120, "Success", "default", function() theme:Toast(toastOpts({ title = "Done", text = "Saved successfully.", variant = "success" })) end)
    b:Button(x + 256, y, 120, "Warning", "default", function() theme:Toast(toastOpts({ text = "Careful now.", variant = "warning" })) end)
    b:Button(x + 384, y, 120, "Sticky ×", "default", function() theme:Toast(toastOpts({ title = "Sticky", text = "Dismiss me with the ×.", variant = "danger", duration = 0 })) end)
    y = y - 44
    return y
end

local function pageIcons(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("BUNDLED ICONS", x, y); y = y - 30
    local _, h = b:Wrap("The Tabler set converted to white TGAs (outline + filled) plus your social icons. Because "
        .. "they're white, |cffffffffany icon tints to any color|r. Toggle the variant and recolor the whole grid; hover for names.",
        x, y, win.opts.contentWidth - 44, C.subtext, 11)
    y = y - (h + 12)

    b:Label("Variant", x, y - 2, C.subtext)
    b:SegmentedControl(x + 66, y, { segments = { { value = "outline", label = "Outline" }, { value = "filled", label = "Filled" } },
        value = state.iconVariant, width = 200, onChange = function(v) state.iconVariant = v; win:Refresh() end })
    b:Label("Color", x + 286, y - 2, C.subtext)
    b:Swatch(x + 330, y, state.iconColor, function() win:Refresh() end, "Icon color", "Recolors the whole grid live.")
    y = y - 40

    local names = theme:IconNames(state.iconVariant == "filled" and "filled" or "outline")
    local COLS, CELL = 14, 34
    for i, name in ipairs(names) do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local g = b:Glyph(x + col * CELL, y - row * CELL, { icon = name, variant = state.iconVariant, size = 22, color = state.iconColor })
        g:EnableMouse(true); g._tipTitle = name
        g:SetScript("OnEnter", theme.showTip); g:SetScript("OnLeave", GameTooltip_Hide)
    end
    y = y - math.ceil(#names / COLS) * CELL - 16
    b:Label("#" .. #names .. " " .. state.iconVariant .. " icons  ·  theme:GetIcon(name, variant)  ·  theme:Glyph(parent, { icon, color })", x, y, C.subtext, 11)
    y = y - 24
    return y
end

local function pageButtons(b, win)
    local x, y = 24, -18
    local noop = function() end
    y = b:Section("KINDS", x, y); y = y - 32
    b:Button(x, y, 110, "Primary", "primary", noop)
    b:Button(x + 120, y, 110, "Default", "default", noop)
    b:Button(x + 240, y, 110, "Danger", "danger", noop)
    b:Button(x + 360, y, 110, "Ghost", "ghost", noop)
    y = y - 46

    y = b:Section("CORNERS  (square edges or radius)", x, y); y = y - 32
    local corners = { { "Square", { corner = "square" } }, { "4px", { radius = 4 } }, { "8px", { radius = 8 } }, { "12px", { radius = 12 } }, { "Pill", { corner = "pill" } } }
    local cx = x
    for _, c in ipairs(corners) do b:Button(cx, y, 92, c[1], "primary", noop, c[2]); cx = cx + 100 end
    y = y - 46

    y = b:Section("WITH ICONS", x, y); y = y - 32
    b:Button(x, y, 130, "Attack", "primary", noop, { icon = "sword", iconColor = "FFD166", corner = "md" })
    b:Button(x + 140, y, 130, "Settings", "default", noop, { icon = "settings", corner = "md" })
    b:Button(x + 280, y, 130, "Delete", "danger", noop, { icon = "trash", corner = "md" })
    y = y - 46

    y = b:Section("CUSTOM COLORS + FONT SIZE", x, y); y = y - 32
    b:Button(x, y, 120, "Purple", "primary", noop, { color = "6610F2", corner = 8 })
    b:Button(x + 130, y, 120, "Teal", "primary", noop, { color = "20C997", corner = 8 })
    b:Button(x + 260, y, 120, "Amber", "primary", noop, { color = "FFC107", textColor = "000000", corner = 8 })
    b:Button(x + 390, y, 96, "Big", "default", noop, { fontSize = 15, corner = 8 })
    y = y - 46

    y = b:Section("SHADOW + BORDER  (pop)", x, y); y = y - 34
    b:Button(x, y, 110, "Shadow", "primary", noop, { corner = 8, shadow = true })
    b:Button(x + 120, y, 120, "Big shadow", "primary", noop, { corner = 10, shadow = { spread = 9, alpha = 0.5 } })
    b:Button(x + 250, y, 110, "Border", "default", noop, { corner = 8, border = { color = "accent", size = 1 } })
    b:Button(x + 370, y, 120, "Both", "primary", noop, { corner = 8, border = { color = "FFFFFF", size = 1 }, shadow = true })
    y = y - 50
    return y
end

local function pageMenus(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("DROPDOWNS", x, y); y = y - 30
    b:Label("Basic", x, y - 2, C.subtext)
    b:Dropdown(x + 70, y):SetChoices(180, { { "a", "Option A" }, { "b", "Option B" }, { "c", "Option C" } },
        function() return state.dd end, function(v) state.dd = v end)
    y = y - 36
    b:Label("Icons", x, y - 2, C.subtext)
    b:Dropdown(x + 70, y):SetIconChoices(200, ICON_ITEMS, function() return state.ddIcon end, function(v) state.ddIcon = v end)
    y = y - 36
    b:Label("Submenus", x, y - 2, C.subtext)
    b:Dropdown(x + 70, y):SetMenu(220, function() return SPELL_MENU end, function() return state.spell end,
        function(v) state.spell = v end, spellLabel)
    y = y - 44

    y = b:Section("SEARCHABLE COMBO  (with icons)", x, y); y = y - 30
    b:Label("Fruit", x, y - 2, C.subtext)
    b:ComboBox(x + 70, y, { width = 260, value = state.combo, placeholder = "Search...", items = FRUIT, onChange = function(v) state.combo = v end })
    y = y - 44

    y = b:Section("FONT SELECT  (each option in its own font; changes the whole UI)", x, y); y = y - 30
    b:Label("UI font", x, y - 2, C.subtext)
    b:FontSelect(x + 70, y, { width = 220, value = state.fontKey, onChange = function(k)
        state.fontKey = k
        theme.FONT = theme:ResolveFont(k)   -- swap the theme's UI font globally...
        win:Refresh()                        -- ...and re-render so everything picks it up
    end })
    b:Heading("The quick brown fox jumps", x + 306, y - 4, "h4")
    y = y - 44

    y = b:Section("SLIDERS  (single + dual range)", x, y); y = y - 30
    b:Label("Range", x, y - 2, C.subtext)
    b:RangeSlider(x + 70, y, { width = 240, min = 0, max = 100, step = 5, low = state.rlo, high = state.rhi,
        onChange = function(lo, hi) state.rlo, state.rhi = lo, hi end })
    y = y - 40
    b:Label("Single", x, y - 2, C.subtext)
    b:RangeSlider(x + 70, y, { width = 240, range = false, min = 0, max = 100, high = state.single,
        onChange = function(v) state.single = v end })
    y = y - 42
    return y
end

local function pageTooltips(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("TOOLTIP PREVIEW", x, y); y = y - 30
    local _, h = b:Wrap("Design tooltip content and see it rendered inline - the same title + colored-lines model the live "
        .. "hover tooltips use. Lines take a palette key or hex color.", x, y, win.opts.contentWidth - 44, C.subtext, 11)
    y = y - (h + 12)
    local tp = b:TooltipPreview(x, y, { title = "Sword of a Thousand Truths", width = 300, lines = {
        { text = "Epic Two-Hand Sword", color = "6610F2" },
        "Deals |cffffffff412 - 618|r damage.",
        { text = "+45 Strength", color = "success" },
        { text = "Requires Level 60", color = "subtext" },
        { text = "\"For the Alliance.\"", color = "accent" },
    } })
    y = y - (tp:GetHeight() or 110) - 18

    y = b:Section("LIVE HOVER TOOLTIP", x, y); y = y - 30
    b:Label("Hover the button - multi-line tooltip with colored lines:", x, y - 2, C.subtext, 12); y = y - 26
    local hb = b:Button(x, y, 200, "Hover me", "primary", function() end, { corner = "md", icon = "info-circle" })
    theme:SetTipLines(hb, "Multi-line Tooltip", {
        "First line of body text.",
        { text = "Highlighted accent line", color = "accent" },
        { text = "Muted footnote", color = "subtext" },
    })
    y = y - 46
    return y
end

local function pageCards(b, win)
    local x, y = 24, -18
    y = b:Section("CARD VARIANTS", x, y); y = y - 30

    -- plain, header, header+footer
    local c1 = b:Card(x, y, { width = 180, height = 116, title = "Header only", subtitle = "with subtitle" })
    theme:Heading(c1.body, { text = "Body region.", role = "caption" }):SetPoint("TOPLEFT", 0, 0)
    local c2 = b:Card(x + 194, y, { width = 190, height = 116, title = "Header + footer", footer = true })
    theme:Heading(c2.body, { text = "Body content.", role = "caption" }):SetPoint("TOPLEFT", 0, 0)
    local fb = theme:Button(c2.footer); fb:Configure("Action", 72, 24, "primary", function() end, { corner = "sm" }); fb:SetPoint("RIGHT", 0, 0)
    local c3 = b:Card(x + 398, y, { width = 180, height = 116 })
    theme:Heading(c3.body, { text = "No header - just a body container you fill.", role = "caption", wrapWidth = 150 }):SetPoint("TOPLEFT", 0, 0)
    y = y - 130

    y = b:Section("COLORED CARDS", x, y); y = y - 30
    local vx, vlist = x, { "accent", "success", "warning", "danger", "info" }
    for _, v in ipairs(vlist) do
        local cc = b:Card(vx, y, { width = 108, height = 76, title = v:sub(1, 1):upper() .. v:sub(2), variant = v })
        theme:Heading(cc.body, { text = "tinted", role = "caption" }):SetPoint("TOPLEFT", 0, 0)
        vx = vx + 116
    end
    y = y - 90

    y = b:Section("STAT TILE CARDS", x, y); y = y - 30
    b:StatTile(x, y, { label = "Members", value = "1,204", delta = "+18", trend = "up", width = 150 })
    b:StatTile(x + 162, y, { label = "Uptime", value = "99.9%", width = 150 })
    b:StatTile(x + 324, y, { label = "Errors", value = "2", delta = "-5", trend = "down", width = 150 })
    y = y - 88
    return y
end

local function pageModals(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("MODALS", x, y); y = y - 30
    local _, h = b:Wrap("Centered dialogs over a dimmed backdrop. Ready-made |cffffffffAlert / Confirm / Prompt|r helpers "
        .. "plus a fully custom content modal, colored variants, and stacking.", x, y, win.opts.contentWidth - 44, C.subtext, 11)
    y = y - (h + 14)

    y = b:Section("ALERTS", x, y); y = y - 30
    b:Button(x, y, 130, "Info", "primary", function()
        theme:Alert({ title = "Heads up", message = "This is an informational alert.", variant = "info", icon = "info-circle" })
    end, { icon = "info-circle" })
    b:Button(x + 140, y, 130, "Success", "default", function()
        theme:Alert({ title = "Saved", message = "Your changes were saved successfully.", variant = "success", icon = "circle-check" })
    end)
    b:Button(x + 280, y, 130, "Warning", "default", function()
        theme:Alert({ title = "Careful", message = "This action carries some risk.", variant = "warning", icon = "alert-triangle" })
    end)
    y = y - 44

    y = b:Section("CONFIRM  &  PROMPT", x, y); y = y - 30
    b:Button(x, y, 170, "Confirm (danger)", "danger", function()
        theme:Confirm({ title = "Delete alert?", message = "This can't be undone.", variant = "danger",
            icon = "alert-circle", confirmLabel = "Delete", onConfirm = function() theme:Toast({ text = "Deleted.", variant = "danger" }) end })
    end)
    b:Button(x + 180, y, 170, "Prompt (input)", "primary", function()
        theme:Prompt({ title = "Rename alert", message = "Enter a new name:", value = "My Alert",
            onAccept = function(t) theme:Toast({ text = "Renamed to " .. (t ~= "" and t or "?"), variant = "success" }) end })
    end)
    y = y - 44

    y = b:Section("CUSTOM CONTENT  &  STACKING", x, y); y = y - 30
    b:Button(x, y, 170, "Custom content", "default", function()
        theme:Modal({ title = "Quick Settings", width = 420, height = 200, icon = "settings",
            content = function(body, modal)
                local t = theme:Toggle(body); t:Configure(true, function() end); t:SetPoint("TOPLEFT", 0, -4)
                theme:Heading(body, { text = "Enable feature", role = "body" }):SetPoint("LEFT", t, "RIGHT", 8, 0)
                theme:Heading(body, { text = "Volume", role = "label" }):SetPoint("TOPLEFT", 0, -40)
                local s = theme:Slider(body); s:Configure(220, 0, 10, 1, function() return 6 end, function() end); s:SetPoint("TOPLEFT", 60, -40)
            end,
            buttons = { { label = "Cancel", kind = "default" },
                        { label = "Save", kind = "primary", onClick = function(m) m:Close(); theme:Toast({ text = "Saved.", variant = "success" }) end } },
        }):Open()
    end)
    b:Button(x + 180, y, 180, "Stacked modals", "default", function()
        theme:Alert({ title = "First modal", message = "Open a second one stacked over this?", okLabel = "Open second",
            onOk = function() theme:Confirm({ title = "Second (stacked)", message = "This sits above the first, with its own backdrop layer." }) end })
    end)
    y = y - 40
    b:Button(x, y, 260, "Non-modal (no dim, no click-off close)", "default", function()
        theme:Modal({ title = "Non-modal dialog", icon = "info-circle",
            message = "No screen dim, and clicking off won't close it - use the X or a button. Great for a floating tool panel.",
            dim = false, closeOnClickOutside = false,
            buttons = { { label = "Got it", kind = "primary" } } }):Open()
    end)
    y = y - 44
    return y
end

local function pageGame(b, win)
    local C = theme.C
    local x, y = 24, -18
    y = b:Section("PORTRAITS & MODELS  (live from the game)", x, y); y = y - 30
    local _, h = b:Wrap("These pull your character live: a flat |cffffffff2D portrait|r, a |cffffffff3D facial portrait|r, and a full "
        .. "|cffffffff3D model|r you can drag to spin.", x, y, win.opts.contentWidth - 44, C.subtext, 11)
    y = y - (h + 12)

    b:Label("Scene backdrop", x, y - 2, C.subtext)
    local scenes = { { "none", "None" } }
    for _, s in ipairs(UIF.MODEL_SCENES) do scenes[#scenes + 1] = { s, s:gsub("^%l", string.upper) } end
    scenes[#scenes + 1] = { "model:illidan", "3D: Illidan" }
    scenes[#scenes + 1] = { "model:arthas", "3D: Arthas" }
    b:Dropdown(x + 110, y):SetChoices(150, scenes, function() return state.scene end, function(v) state.scene = v; win:Refresh() end)
    b:Toggle(x + 268, y + 2, state.sceneAnimated, function(v) state.sceneAnimated = v; win:Refresh() end)
    b:Label("Animate", x + 314, y, C.text)
    b:Wrap("(also try |cffffffffbackground = \"model:<fileID>\"|r for a live 3D backdrop)", x + 384, y, 180, C.subtext, 10)
    y = y - 32
    local bg = (state.scene ~= "none") and state.scene or nil
    local isModel = type(bg) == "string" and bg:find("^model:")
    local texBg = (not isModel) and bg or nil   -- Portrait2D shows scenes/colors, not 3D models
    local anim = state.sceneAnimated
    b:Heading("2D portrait", x + 10, y, "overline")
    b:Heading("3D portrait", x + 150, y, "overline")
    b:Heading("3D model (drag to rotate)", x + 300, y, "overline")
    y = y - 20
    b:Portrait2D(x + 14, y, { unit = "player", size = 72, circular = true, background = texBg, animated = anim })
    b:PortraitModel(x + 150, y, { unit = "player", size = 100, background = bg, animated = anim })
    b:UnitModel(x + 300, y, { unit = "player", width = 150, height = 210, background = bg, animated = anim })
    y = y - 224

    y = b:Section("SPELL / BUFF / ITEM ICONS  (hover for the real game tooltip)", x, y); y = y - 30
    b:Label("Spells", x, y - 2, C.subtext)
    local sx = x + 60
    for _, id in ipairs({ 133, 116, 172, 348, 585, 686 }) do b:GameIcon(sx, y, { spell = id, size = 34 }); sx = sx + 40 end
    y = y - 44
    b:Label("Buffs", x, y - 2, C.subtext)
    sx = x + 60
    for _, id in ipairs({ 1459, 21562, 6673, 1126 }) do b:GameIcon(sx, y, { aura = id, size = 34 }); sx = sx + 40 end
    y = y - 44
    b:Label("Items", x, y - 2, C.subtext)
    sx = x + 60
    for _, id in ipairs({ 6948, 5512, 858, 40771 }) do b:GameIcon(sx, y, { item = id, size = 34 }); sx = sx + 40 end
    y = y - 44
    return y
end

local function pageAbout(b, win)
    local C = theme.C
    local x, y = 24, -20
    y = b:Section("ABOUT UIFOUNDRY", x, y); y = y - 32
    local _, h = b:Wrap("UIFoundry is a self-skinned, dependency-free UI kit: a theme with a live accent, "
        .. "custom |cfffffffftoggles / dropdowns / sliders / inputs|r, |cffffffffpickers|r and |cffffffffdialogs|r, a pooled "
        .. "content |cffffffffbuilder|r, and this |cffffffffwindow shell|r. Add it as a dependency and each of your tools "
        .. "shares one look while keeping its own accent.", x, y, win.opts.contentWidth - 44, C.text, 12)
    y = y - (h + 16)

    -- Preview of the three window footer styles (this window uses "expanded").
    y = b:Section("WINDOW FOOTER STYLES", x, y); y = y - 28
    local fw = win.opts.contentWidth - 48
    b:Label("none  -  no footer bar at all", x, y - 2, C.subtext, 11); y = y - 24

    b:Label("minimal", x, y - 2, C.subtext, 10); y = y - 16
    local m = b:Card(x, y, { width = fw, height = 24, padding = 7, accentBar = false })
    theme:Heading(m.body, { text = "My Addon  ·  by me", role = "caption" }):SetPoint("LEFT", 0, 0)
    theme:Heading(m.body, { text = "Discord", role = "caption", textColor = "accent" }):SetPoint("CENTER", 0, 0)
    theme:Heading(m.body, { text = "v1.0", role = "caption", textColor = "accent" }):SetPoint("RIGHT", 0, 0)
    y = y - 36

    b:Label("expanded", x, y - 2, C.subtext, 10); y = y - 16
    local e = b:Card(x, y, { width = fw, height = 46, padding = 8, accentBar = false })
    theme:Heading(e.body, { text = "My Addon", role = "body" }):SetPoint("TOPLEFT", 0, 2)
    theme:Heading(e.body, { text = "shared UI kit", role = "caption" }):SetPoint("TOPLEFT", 0, -14)
    theme:Heading(e.body, { text = "v1.0", role = "caption", textColor = "accent" }):SetPoint("RIGHT", 0, 0)
    local sbar = theme:SocialBar(e.body, { { brand = "discord", url = "a" }, { brand = "github", url = "b" }, { brand = "youtube", url = "c" } }, { iconOnly = true, size = 22 })
    sbar:SetPoint("CENTER", 0, 0)
    y = y - 60

    b:Label("Drag the header to move, or the scrollbar to scroll.", x, y, C.subtext, 11)
    y = y - 24
    b:Label("Version " .. (UIF.version or 1) .. "  ·  " .. (UIF.MAJOR or "UIFoundry"), x, y, C.accent, 12)
    y = y - 30
    return y
end

----------------------------------------------------------------------
-- The demo window
----------------------------------------------------------------------
local win = theme:Window({
    name = "UIFoundryShowcaseWindow",
    title = "UIFoundry - Component Gallery",
    logo = theme:GetIcon("sparkles"),
    width = 860, height = 560, contentWidth = 600,
    maximizable = true, maxWidthPct = 0.92, maxHeightPct = 0.92,
    pages = {
        { header = "Appearance" },
        { view = "skins",   label = "Skins",             icon = theme:GetIcon("palette"),      render = pageSkins },
        { header = "Foundations" },
        { view = "widgets", label = "Widgets",           icon = theme:GetIcon("adjustments"),  render = pageWidgets },
        { view = "buttons", label = "Buttons",           icon = theme:GetIcon("hexagon"),      render = pageButtons },
        { view = "type",    label = "Typography",        icon = theme:GetIcon("file-text"),    render = pageType },
        { header = "Forms & Menus" },
        { view = "forms",   label = "Forms & Inputs",    icon = theme:GetIcon("list-check"),   render = pageForms },
        { view = "menus",   label = "Menus & Selects",   icon = theme:GetIcon("caret-down"),   render = pageMenus },
        { header = "Layout" },
        { view = "cards",   label = "Cards",             icon = theme:GetIcon("layout-grid"),  render = pageCards },
        { view = "display", label = "Badges & Tabs",     icon = theme:GetIcon("layout-list"),  render = pageDisplay },
        { header = "Feedback" },
        { view = "tips",    label = "Tooltips",          icon = theme:GetIcon("message"),      render = pageTooltips },
        { view = "modals",  label = "Modals",            icon = theme:GetIcon("layout-navbar"), render = pageModals },
        { view = "social",  label = "Social & Toasts",   icon = theme:GetIcon("share"),        render = pageSocial },
        { header = "Media" },
        { view = "icons",   label = "Icons",             icon = theme:GetIcon("sparkles"),     render = pageIcons },
        { view = "game",    label = "Portraits & Models", icon = theme:GetIcon("user-circle"),  render = pageGame },
        { header = "Help" },
        { view = "pickers", label = "Pickers & Dialogs", icon = theme:GetIcon("palette"),      render = pagePickers },
        { view = "about",   label = "About",             icon = theme:GetIcon("info-circle"),  render = pageAbout },
    },
    footer = {
        style = "expanded",
        left  = "UIFoundry",
        subtitle = "shared UI kit  ·  drag the header to move, □ to maximize",
        right = "v" .. "1.1.0",
        socials = {
            { brand = "discord", url = "https://discord.com/invite/xxxx" },
            { brand = "github",  url = "https://github.com/xxxx" },
            { brand = "youtube", url = "https://youtube.com/@xxxx" },
        },
    },
    defaultView = "widgets",
})

UIF._demoWindow = win   -- exposed for tests / external triggering (no slash command)
