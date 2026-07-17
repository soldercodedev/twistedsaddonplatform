-- TAP_FocusInterrupt - ModuleFocus.lua
-- Registers the "Focus Tools" suite module and rebuilds its settings page on the suite's Builder
-- (replacing the old buildMacros UI). Drives the kept engine: FTI.BuildFocusMacro / BuildKickMacro
-- / BuildStunMacro / SaveMacro (Macros.lua) and the marker palette (FocusPalette.lua).

local addonName, FTI = ...
local Suite = _G.TAP
if not Suite then return end

local CHANGELOG = [==[
# Focus Target Interrupt - What's New

## 1.0.0-beta.3

- **[CHANGE]** **Tabbed layout.** The page is now split into tabs - **Macros**, **Marker Palette**,
  **Announce**, and **Settings** - docked under the title bar, instead of one long scrolling page.
  Everything's in the same place, just quicker to get to.
- **[BUG FIX]** Picks up the latest shared appearance fixes - custom theme colours now save correctly
  from the colour picker, and the **Menu scale** slider is smoother to drag.

## 1.0.0-beta.2

- **[NEW]** The marker bar now **remembers your focus marker**. Click a marker on the bar out of
  combat and it becomes your **saved** Focus macro marker (the "TAP Focus" macro updates and you get
  a chat confirmation). In combat it still just marks your current target, with no change or spam.
- **[NEW]** Fresh platform look in Settings: pick a **shape** and a **colour scheme** (neutrals,
  light themes, or a WoW-expansion palette) or full custom colours, and scale the menu with
  **Menu scale**.

## 1.0.0

- **[NEW]** Focus Target Interrupt is here - the focus & interrupt tools split out into their own
  add-on so you can run just the bits you want.
- **[NEW]** One-key Focus + Mark macro: press once to set your focus (your mouseover, or your
  target) and slap your chosen raid marker on it. Both are combat-safe, so it works mid-fight.
- **[NEW]** An on-screen marker bar: click any of the 8 raid markers to focus + mark whoever
  you're looking at, live. Move it, resize it, lay it out as a row or a column, and pick its
  background/border colours and opacity.
- **[NEW]** Auto-detected Interrupt and Stun macros for your exact spec and talents - it finds the
  ability you actually have, so you just hit Create Macro and drag it to a bar.
- **[NEW]** Optional call-outs: announce your focus (or a ready check) to say / party / raid, and
  limit them to the content you care about.
]==]

----------------------------------------------------------------------
-- Choice tables (from the old UI).
----------------------------------------------------------------------
local MARK_NAMES = FTI.MARK_NAMES
local function markTag(n) return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. ":16|t" end
local MARK_CHOICES = { { "0", "No marker" } }
for _, n in ipairs({ 8, 7, 6, 5, 4, 3, 2, 1 }) do
    MARK_CHOICES[#MARK_CHOICES + 1] = { tostring(n), markTag(n) .. "  " .. MARK_NAMES[n] }
end
local ANNOUNCE_CHOICES = {
    { "NONE", "Don't announce" }, { "SAY", "Say" }, { "YELL", "Yell" }, { "PARTY", "Party" },
    { "RAID", "Raid" }, { "INSTANCE_CHAT", "Instance" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" }, { "EMOTE", "Emote" },
}
local ANNOUNCE_WHERE = {
    { "any", "Anywhere" }, { "none", "Open world" }, { "any_instance", "Any instance" },
    { "party", "Dungeon (M+)" }, { "raid", "Raid" }, { "arena", "Arena" }, { "pvp", "Battleground" }, { "scenario", "Scenario" },
}
local FOCUS_SOURCE = {
    { "smart", "Mouseover, else target" }, { "target", "Current target" }, { "mouseover", "Mouseover only" },
}
local PALETTE_WHERE = {
    { "always", "Always" }, { "any_instance", "In any instance" },
    { "party", "In dungeons" }, { "raid", "In raids" }, { "group", "In a group" },
}
local PALETTE_ROTATE = { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }

-- Active settings page (docked top-nav): macros | palette | announce | settings.
local uiTab = "macros"
local TAB_TIPS = {
    macros   = "Ready-made Focus + Mark, Interrupt, and Stun macros for your spec.",
    palette  = "The on-screen marker bar: click a marker to focus + mark, live.",
    announce = "Call out your focus to chat.",
    settings = "Module options, including the minimap button.",
}

----------------------------------------------------------------------
-- Settings page (rebuilt on the Builder).
----------------------------------------------------------------------
local function Settings(mod, b, x, y, w, win)
    local C = b.theme.C
    local d = (FTI.SyncDB and FTI.SyncDB()) or FTI.db   -- ensure FTI.db points at persisted settings
    if not d then b:Wrap("Loading...", x, y, w, C.subtext, 12); return y - 20 end
    d.macro = d.macro or {}
    local mac = d.macro
    mac.mark = tonumber(mac.mark) or 8
    mac.channel = mac.channel or "NONE"
    if mac.focusMsg == nil then mac.focusMsg = "Focus {rt}" end
    if mac.readyMsg == nil then mac.readyMsg = "My interrupt target is {rt}" end
    mac.announceInstance = mac.announceInstance or "any"
    mac.paletteScale = tonumber(mac.paletteScale) or 1
    mac.paletteVisibility = mac.paletteVisibility or "always"
    mac.focusTarget = mac.focusTarget or "smart"
    mac.paletteRotation = mac.paletteRotation or "horizontal"
    mac.paletteBgColor = mac.paletteBgColor or { 0.05, 0.05, 0.06 }
    mac.paletteBorderColor = mac.paletteBorderColor or { 0.25, 0.25, 0.30 }
    if mac.paletteOpacity == nil then mac.paletteOpacity = 0.9 end

    -- Re-apply the bar's look (rotation / size / colours / opacity) live from a control.
    local function refreshPalette() if FTI.ApplyPalettePresentation then FTI.ApplyPalettePresentation() end end

    local function tip(widget, title, body) if widget then b.theme:SetTip(widget, title, body) end return widget end
    local function dropdown(cx, cy, wide, choices, getter, setter, tTitle, tBody)
        local dd = b:Dropdown(cx, cy); dd:SetChoices(wide, choices, getter, setter)
        return tip(dd, tTitle, tBody)
    end
    -- A boxed, read-only macro-text block; returns the new y.
    local function macroBox(text, cx, cy)
        local _, h = b:Wrap(text, cx + 8, cy - 6, w - 64, C.text, 11)
        b:Box(cx, cy + 2, w - 26, h + 14, 0.07, 0, C.accent)
        return cy - (h + 20)
    end
    local function copy(title, text) if b.theme.ShowCopyDialog then b.theme:ShowCopyDialog(title, text) end end

    -- MACROS page: the three ready-made macros (Focus + Mark, Interrupt, Stun).
    local function renderMacros(y)
        local _, ih = b:Wrap("Generate ready-made macros. |cffffffffCreate Macro|r saves it to your macro "
            .. "list (out of combat only); |cffffffffCopy text|r opens it so you can paste it into a macro yourself.",
            x, y, w - 48, C.subtext, 11)
        y = y - (ih + 14)

        -- FOCUS + MARK
        b:Sub("FOCUS + MARK  (one key, works in combat)", x, y); y = y - 30
        b:Label("Marker", x, y - 2, C.subtext)
        dropdown(x + 60, y, 160, MARK_CHOICES, function() return tostring(mac.mark or 0) end,
            function(v) mac.mark = tonumber(v) or 0; FTI.RefreshManager() end,
            "Focus marker", "The raid marker the macro places on your focus (also used in the announce below).")
        b:Label("Focus", x + 246, y - 2, C.subtext)
        dropdown(x + 296, y, 200, FOCUS_SOURCE, function() return mac.focusTarget or "smart" end,
            function(v) mac.focusTarget = v; FTI.RefreshManager() end,
            "Focus source", "What the macro focuses: your mouseover, current target, or mouseover-then-target.")
        y = y - 34
        local mk = tonumber(mac.mark) or 0
        if mk == 8 or mk == 7 or mk == 6 then
            local _, wh = b:Wrap("|cffffcc00Heads up:|r " .. MARK_NAMES[mk] .. " is commonly used for kill order / tank "
                .. "marking - consider Star, Circle, Diamond, Triangle, or Moon for a focus so you don't clash.",
                x, y, w - 48, { 0.85, 0.68, 0.35 }, 11)
            y = y - (wh + 8)
        end
        local _, mh = b:Wrap("Sets your focus and |cffffffffmarks|r it in one press. Both commands are secure, so "
            .. "|cffffffffit works in combat|r. After creating it, bind it under Key Bindings > Macros or drag it to a bar.",
            x, y, w - 48, C.subtext, 11)
        y = y - (mh + 8)
        y = macroBox(FTI.BuildFocusMacro(mac), x, y)
        tip(b:Button(x, y, 140, "Create Macro", "primary", function()
            local ok, res = FTI.SaveMacro("TAP Focus", "INV_Misc_QuestionMark", FTI.BuildFocusMacro(mac), true)
            print(FTI.PREFIX .. (ok and "Saved character macro |cffffff00TAP Focus|r." or ("Not saved: " .. tostring(res))))
        end), "Create macro", "Save this as a per-character macro named 'TAP Focus'.")
        tip(b:Button(x + 150, y, 110, "Copy text", "default", function() copy("TAP Focus macro", FTI.BuildFocusMacro(mac)) end),
            "Copy text", "Open the macro text so you can copy it.")
        y = y - 44

        -- INTERRUPT @focus
        b:Sub("INTERRUPT  @FOCUS  (auto-detected for your spec)", x, y); y = y - 30
        local kickText, intr = FTI.BuildKickMacro()
        if kickText then
            local line = "Detected: |cff33ff33" .. tostring(intr.name or "?") .. "|r"
            if intr.note then line = line .. "   |cffffcc00(" .. intr.note .. ")|r" end
            b:Label(line, x, y - 2, C.text); y = y - 26
            y = macroBox(kickText, x, y)
            tip(b:Button(x, y, 130, "Create Macro", "primary", function()
                local ok, res = FTI.SaveMacro("TAP Interrupt", intr.icon or "INV_Misc_QuestionMark", (FTI.BuildKickMacro()), true)
                print(FTI.PREFIX .. (ok and "Saved character macro |cffffff00TAP Interrupt|r." or ("Not saved: " .. tostring(res))))
            end), "Create macro", "Save this as a per-character macro named 'TAP Interrupt' (spec-specific).")
            tip(b:Button(x + 140, y, 110, "Copy text", "default", function() copy("TAP Interrupt macro", (FTI.BuildKickMacro())) end),
                "Copy text", "Open the macro text so you can copy it.")
            y = y - 48
        else
            local _, nh = b:Wrap("|cffffcc00No interrupt macro for your spec.|r  " .. tostring(intr), x, y - 2, w - 48, C.subtext, 12)
            y = y - (nh + 14)
        end

        -- STUN @focus / @target
        b:Sub("STUN  @FOCUS / @TARGET  (auto-detected for your talents)", x, y); y = y - 30
        local stunText, stun = FTI.BuildStunMacro()
        if stunText then
            b:Label("Detected: |cff33ff33" .. tostring(stun.name or "?") .. "|r", x, y - 2, C.text); y = y - 26
            y = macroBox(stunText, x, y)
            tip(b:Button(x, y, 130, "Create Macro", "primary", function()
                local ok, res = FTI.SaveMacro("TAP Stun", stun.icon or "INV_Misc_QuestionMark", (FTI.BuildStunMacro()), true)
                print(FTI.PREFIX .. (ok and "Saved character macro |cffffff00TAP Stun|r." or ("Not saved: " .. tostring(res))))
            end), "Create macro", "Save this as a per-character macro named 'TAP Stun'.")
            tip(b:Button(x + 140, y, 110, "Copy text", "default", function() copy("TAP Stun macro", (FTI.BuildStunMacro())) end),
                "Copy text", "Open the macro text so you can copy it.")
            y = y - 48
        else
            local _, sh = b:Wrap("|cffffcc00No stun macro:|r  " .. tostring(stun), x, y - 2, w - 48, C.subtext, 12)
            y = y - (sh + 14)
        end
        return y
    end

    -- MARKER PALETTE page: the on-screen marker bar and its appearance.
    local function renderPalette(y)
        b:Sub("MARKER PALETTE", x, y); y = y - 30
        tip(b:Toggle(x, y, mac.paletteShown, function(v) FTI.SetMarkerPaletteEnabled(v); FTI.RefreshManager() end),
            "Marker palette", "Show a small movable bar of the 8 raid markers on screen. Click one to focus + mark your "
            .. "target with it - live, even in combat - and make it your focus marker.")
        b:Label("Show marker palette on screen", x + 46, y - 2, C.text)
        if mac.paletteShown then
            local moverOn = FTI._paletteMoverOn and true or false
            tip(b:Button(x + 300, y - 3, 130, moverOn and "Done moving" or "Move on screen", moverOn and "primary" or "default",
                function() FTI.SetMarkerPaletteMover(not FTI._paletteMoverOn) end),
                "Move on screen", "Drag the bar to reposition it (or set the position with the size slider below).")
            y = y - 34
            -- Layout + visibility row.
            b:Label("Layout", x + 46, y - 2, C.subtext)
            dropdown(x + 96, y, 130, PALETTE_ROTATE, function() return mac.paletteRotation or "horizontal" end,
                function(v) mac.paletteRotation = v; refreshPalette(); FTI.RefreshManager() end,
                "Layout", "Arrange the 8 markers in a row (horizontal) or a column (vertical).")
            b:Label("Show", x + 246, y - 2, C.subtext)
            dropdown(x + 288, y, 160, PALETTE_WHERE, function() return mac.paletteVisibility or "always" end,
                function(v) mac.paletteVisibility = v; FTI.RefreshMarkerPaletteVisibility() end,
                "Show where", "When the marker bar is on screen (re-checked on zone/group change).")
            y = y - 46   -- extra room so the Size slider's value bubble doesn't crowd this row
            -- Size (its own row). Route through ApplyMarkerPaletteScale so the bar scales about its
            -- anchor (fixed focal point) instead of drifting.
            b:Label("Size", x + 46, y - 2, C.subtext)
            tip(b:Slider(x + 120, y), "Size", "Scale of the marker bar (grows from a fixed point)."):Configure(240, 0.6, 2.0, 0.05,
                function() return tonumber(mac.paletteScale) or 1 end,
                function(v) mac.paletteScale = v; if FTI.ApplyMarkerPaletteScale then FTI.ApplyMarkerPaletteScale() end end, "%.2f")
            y = y - 42
            -- Opacity (its own row).
            b:Label("Opacity", x + 46, y - 2, C.subtext)
            tip(b:Slider(x + 120, y), "Opacity", "Background transparency of the bar (0 = see-through, border stays)."):Configure(240, 0, 1, 0.05,
                function() return tonumber(mac.paletteOpacity) or 0.9 end,
                function(v) mac.paletteOpacity = v; refreshPalette() end, "%.2f")
            y = y - 40
            -- Colours row.
            b:Label("Background", x + 46, y - 2, C.subtext)
            tip(b:Swatch(x + 150, y - 2, mac.paletteBgColor, function() refreshPalette() end, "Background colour"),
                "Background colour", "The bar's fill colour (pair with Opacity 0 for outline-only).")
            b:Label("Border", x + 240, y - 2, C.subtext)
            tip(b:Swatch(x + 300, y - 2, mac.paletteBorderColor, function() refreshPalette() end, "Border colour"),
                "Border colour", "The bar's outline colour.")
        end
        y = y - 44
        return y
    end

    -- ANNOUNCE page (+ the minimap button).
    local function renderAnnounce(y)
        b:Sub("ANNOUNCE", x, y); y = y - 30
        b:Label("Announce to", x, y - 2, C.subtext)
        dropdown(x + 96, y, 150, ANNOUNCE_CHOICES, function() return mac.channel or "NONE" end,
            function(v) mac.channel = v; FTI.RefreshManager() end,
            "Announce channel", "Which chat channel your focus call-outs go to (None = off).")
        b:Label("in", x + 258, y - 2, C.subtext)
        dropdown(x + 282, y, 160, ANNOUNCE_WHERE, function() return mac.announceInstance or "any" end,
            function(v) mac.announceInstance = v; FTI.RefreshManager() end,
            "Announce where", "Only send call-outs in this kind of content.")
        y = y - 36
        local canAnnounce = (mac.channel or "NONE") ~= "NONE"
        local txtCol = canAnnounce and C.text or C.subtext
        tip(b:Toggle(x, y, mac.announceFocus, function(v) mac.announceFocus = v; FTI.RefreshManager() end),
            "Announce on focus", "Send this call-out whenever you set your focus target.")
        b:Label("When I set focus", x + 46, y - 2, txtCol)
        y = y - 26
        tip(b:EditBox(x + 46, y, w - 116, mac.focusMsg or "", function(t) mac.focusMsg = t end),
            "Focus message", "Sent when you set focus. {rt} = your marker icon.")
        y = y - 34
        tip(b:Toggle(x, y, mac.announceReady, function(v) mac.announceReady = v; FTI.RefreshManager() end),
            "Announce on ready check", "Re-post your focus call-out when a ready check starts.")
        b:Label("When a ready check starts", x + 46, y - 2, txtCol)
        y = y - 26
        tip(b:EditBox(x + 46, y, w - 116, mac.readyMsg or "", function(t) mac.readyMsg = t end),
            "Ready-check message", "Sent when a ready check starts. Lead with {rt} (your marker).")
        y = y - 30
        local _, hh = b:Wrap("Wildcard: |cffffffff{rt}|r = the marker icon.", x + 46, y, w - 110, C.subtext, 11)
        y = y - (hh + 6)
        if not canAnnounce then
            local _, nh = b:Wrap("|cffffcc00Pick an announce channel above to turn call-outs on.|r", x + 46, y, w - 110, { 0.85, 0.68, 0.35 }, 11)
            y = y - (nh + 6)
        end
        return y
    end

    -- SETTINGS page: the master enable/disable plus module-wide options (the minimap button), on
    -- their own tab so they aren't buried under the Announce controls.
    local function renderSettings(y)
        y = b:ModuleToggle(x, y, w, mod, { onToggle = function() if win then win:Refresh() end end,
            sub = "When off, the marker bar and focus call-outs stand down; your macros and settings are kept." })
        b:Sub("MINIMAP", x, y); y = y - 30
        if Suite and Suite.IsMinimapButtonShown then
            tip(b:Toggle(x, y, Suite:IsMinimapButtonShown("focusInterrupt"),
                function(v) Suite:SetMinimapButtonShown("focusInterrupt", v) end),
                "Minimap icon", "Show a Focus Target Interrupt button on the minimap (left-click opens this page).")
            b:Label("Show a minimap button", x + 46, y - 2, C.text)
            b:Label("Left-click it to open this page.", x + 46, y - 20, C.subtext, 10)
            y = y - 44
        else
            local _, nh = b:Wrap("The minimap button isn't available in this environment.", x, y, w - 48, C.subtext, 11)
            y = y - (nh + 10)
        end
        return y
    end

    -- Dock the tab strip as a fixed top-nav flush under the title bar (matches Mythic Ledger). It must
    -- be re-issued every render - Window:Refresh clears the nav before each render.
    if win and win.SetTopNav then
        win:SetTopNav({
            items = {
                { key = "macros",   label = "Macros",         icon = "keyboard" },
                { key = "palette",  label = "Marker Palette",  icon = "target" },
                { key = "announce", label = "Announce",        icon = "message" },
                { key = "settings", label = "Settings",        icon = "settings" },
            },
            active = uiTab, height = 30,
            onSelect = function(key) uiTab = key; if win then win:Refresh() end end,
            tip = function(key) return TAB_TIPS[key] end,
        })
        y = y - 4   -- small breathing room below the docked nav
    end

    -- Disabled: overlay every tab except Settings (where the enable toggle lives).
    if mod and mod.IsEnabled and not mod:IsEnabled() and uiTab ~= "settings" then
        return b:DisabledOverlay(x, y, w, { subtitle = "Go to the Settings tab to turn Focus Target Interrupt back on.",
            onSettings = function() uiTab = "settings"; if win then win:Refresh() end end })
    end

    if uiTab == "palette" then
        y = renderPalette(y)
    elseif uiTab == "announce" then
        y = renderAnnounce(y)
    elseif uiTab == "settings" then
        y = renderSettings(y)
    else
        y = renderMacros(y)
    end
    return y
end

----------------------------------------------------------------------
-- Register the module.
----------------------------------------------------------------------
Suite:RegisterModule({
    id      = "focusInterrupt",
    title   = "Focus Target Interrupt",
    desc    = "Focus + mark macros, an on-screen raid-marker palette, focus call-outs, and "
           .. "auto-detected interrupt / stun macros for your spec.",
    icon    = "target",
    addon   = "TAP_FocusInterrupt",
    default = true,
    fullPage = true,   -- we render our own tabbed page; suite skips the "SETTINGS" band
    rendersWhenDisabled = true,   -- keep our page (and its Settings tab) reachable while disabled
    changelog = CHANGELOG,
    OnEnable = function()
        if FTI.SyncDB then FTI.SyncDB() end   -- ensure FTI.db is the persisted settings before use
        FTI.focusEnabled = true
        if FTI.EnsureMarkerPaletteWatcher then FTI.EnsureMarkerPaletteWatcher() end
        if FTI.RefreshMarkerPaletteVisibility then FTI.RefreshMarkerPaletteVisibility() end
    end,
    OnDisable = function()
        FTI.focusEnabled = false
        if FTI._paletteMoverOn and FTI.SetMarkerPaletteMover then FTI.SetMarkerPaletteMover(false) end
        if FTI.RefreshMarkerPaletteVisibility then FTI.RefreshMarkerPaletteVisibility() end   -- hides the bar
    end,
    Settings = Settings,
})

-- Optional minimap icon for this module (hidden by default; toggled in this module's settings).
if Suite.RegisterMinimapButton then
    Suite:RegisterMinimapButton("focusInterrupt", {
        icon = "Interface\\AddOns\\TAP_FocusInterrupt\\assets\\images\\tap_focus_interrupt_icon.tga",
        title = "|cffa06cf0Focus Target Interrupt|r", action = "open the settings",
        onClick = function() Suite:OpenWindow("mod:focusInterrupt") end,
        defaultHidden = true,
    })
end

-- List a shortcut to this module's page on Help > Commands. Its macro tools also live under
-- /tcc macros (or /tap alerts macros).
if Suite and Suite.RegisterCommand then
    Suite:RegisterCommand({
        cmd = "/tap focus", desc = "Open the Focus Target Interrupt page", owner = "Focus Target Interrupt",
        sub = "focus", handler = function() if Suite.OpenWindow then Suite:OpenWindow("mod:focusInterrupt") end end,
    })
end
