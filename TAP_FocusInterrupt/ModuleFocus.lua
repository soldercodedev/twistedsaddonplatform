-- TAP_FocusInterrupt - ModuleFocus.lua
-- Registers the "Focus Tools" suite module and rebuilds its settings page on the suite's Builder
-- (replacing the old buildMacros UI). Drives the kept engine: FTI.BuildFocusMacro / BuildKickMacro
-- / BuildStunMacro / SaveMacro (Macros.lua) and the marker palette (FocusPalette.lua).

local addonName, FTI = ...
local Suite = _G.TAP
if not Suite then return end

local CHANGELOG = [==[
# Focus Target Interrupt - What's New

## 1.3.0

- **[NEW]** **Cast at now covers every detected interrupt and stun.** The Macros page lists every interrupt and targeted stun your spec and talents actually give you (not just the first) - so a Prot Paladin sees Rebuke, Avenger's Shield and Divine Toll, a Feral sees Skull Bash plus Mighty Bash and Maim, and so on. Each ability gets its own **Cast at** dropdown (focus, target, mouseover, or a fallback combo) and its own macro. Stuns had no Cast at before; now they do (default: focus, else target).
- **[CHANGE]** The first interrupt keeps the name **TAP Interrupt** and the first stun **TAP Stun**, so your existing macros keep updating. Extra abilities get their own short names (e.g. TAP AvShield, TAP Maim).

## 1.2.0

- **[NEW]** The Interrupt macro has a **Cast at** option, just like the Focus macro's focus source: interrupt your focus, your current target, or your mouseover, with fallback combos (focus, else target / mouseover, else focus). The default is still focus-only; save the macro again after changing it.
- **[NEW]** The Macros page shows the detected interrupt and stun as a proper spell icon - hover it for the real Blizzard spell tooltip.
- **[CHANGE]** The macro buttons now read **Update Macro** when that macro already exists in your macro book, so it's clear you're rewriting it rather than adding another.

## 1.1.1

- **[CHANGE]** Loading Blizzard's macro UI now uses the current **C_AddOns** API directly. No functional change.

## 1.1.0

- **[CHANGE]** The Macros, Marker Palette, Announce and Settings pages moved into the sidebar under Focus Target Interrupt, and the on/off toggle is now on the platform Overview.
- **[NEW]** You can limit focus and ready-check call-outs to certain specs - the Announce page has a Class/Spec picker. Leave it empty to announce on every character.

## 1.0.0

- **[CHANGE]** Out of beta - Focus Target Interrupt is now a stable 1.0 release.

## 1.0.0-beta.3

- **[CHANGE]** **Tabbed layout.** The page is now split into tabs - **Macros**, **Marker Palette**,
  **Announce**, and **Settings** - docked under the title bar, instead of one long scrolling page.
  Everything's in the same place, just quicker to get to.
- **[BUG FIX]** Picks up the latest shared appearance fixes - custom theme colors now save correctly
  from the color picker, and the **Menu scale** slider is smoother to drag.

## 1.0.0-beta.2

- **[NEW]** The marker bar now **remembers your focus marker**. Click a marker on the bar out of
  combat and it becomes your **saved** Focus macro marker (the "TAP Focus" macro updates and you get
  a chat confirmation). In combat it still just marks your current target, with no change or spam.
- **[NEW]** Fresh platform look in Settings: pick a **shape** and a **color scheme** (neutrals,
  light themes, or a WoW-expansion palette) or full custom colors, and scale the menu with
  **Menu scale**.

## 1.0.0-beta.1

- **[NEW]** Focus Target Interrupt is here - the focus & interrupt tools split out into their own
  add-on so you can run just the bits you want.
- **[NEW]** One-key Focus + Mark macro: press once to set your focus (your mouseover, or your
  target) and slap your chosen raid marker on it. Both are combat-safe, so it works mid-fight.
- **[NEW]** An on-screen marker bar: click any of the 8 raid markers to focus + mark whoever
  you're looking at, live. Move it, resize it, lay it out as a row or a column, and pick its
  background/border colors and opacity.
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
local KICK_SOURCE = {
    { "focus", "Focus only" }, { "focus_target", "Focus, else target" }, { "target", "Current target" },
    { "mouseover", "Mouseover only" }, { "mouseover_focus", "Mouseover, else focus" },
}
local PALETTE_WHERE = {
    { "always", "Always" }, { "any_instance", "In any instance" },
    { "party", "In dungeons" }, { "raid", "In raids" }, { "group", "In a group" },
}
local PALETTE_ROTATE = { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }

----------------------------------------------------------------------
-- Settings page (rebuilt on the Builder).
----------------------------------------------------------------------
-- Renders ONE of the module's pages (its tabs now live in the sidebar as sub-rows). Keeps all the
-- per-tab render closures; only the top-nav dispatch is replaced by a pageId dispatch.
local function RenderPage(pageId, mod, b, x, y, w, win)
    local C = b.theme.C
    local d = (FTI.SyncDB and FTI.SyncDB()) or FTI.db   -- ensure FTI.db points at persisted settings
    if not d then b:Wrap("Loading...", x, y, w, C.subtext, 12); return y - 20 end
    local mac = d.macro   -- SyncDB() above already seeded every macro default

    -- Re-apply the bar's look (rotation / size / colors / opacity) live from a control.
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

    -- MACROS page: Focus + Mark, then one macro per detected interrupt and per detected stun.
    local function renderMacros(y)
        -- Create/Update button for one ready-made macro: the label and tooltip flip to "Update"
        -- when the macro already exists in the macro book, and the page re-renders after a save
        -- so the label stays true. buildFn returns the macro body at click time.
        local function macroButton(cx, cy, bw, name, icon, buildFn, tipNote)
            local exists = FTI.MacroExists(name)
            local verb = exists and "Update" or "Create"
            return tip(b:Button(cx, cy, bw, verb .. " Macro", "primary", function()
                local ok, res = FTI.SaveMacro(name, icon, buildFn(), true)
                print(FTI.PREFIX .. (ok and ((exists and "Updated macro |cffffff00" or "Saved character macro |cffffff00") .. name .. "|r.")
                    or ("Not saved: " .. tostring(res))))
                FTI.RefreshManager()
            end), verb .. " macro",
                exists and ("Overwrite the existing '" .. name .. "' macro with the text shown above" .. (tipNote or "") .. ".")
                    or ("Save this as a per-character macro named '" .. name .. "'" .. (tipNote or "") .. "."))
        end
        local _, ih = b:Wrap("Generate ready-made macros. |cffffffffCreate Macro|r saves it to your macro "
            .. "list, or |cffffffffUpdate Macro|r rewrites it once it exists (out of combat only); "
            .. "|cffffffffCopy text|r opens it so you can paste it into a macro yourself.",
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
        macroButton(x, y, 140, "TAP Focus", "INV_Misc_QuestionMark", function() return FTI.BuildFocusMacro(mac) end)
        tip(b:Button(x + 150, y, 110, "Copy text", "default", function() copy("TAP Focus macro", FTI.BuildFocusMacro(mac)) end),
            "Copy text", "Open the macro text so you can copy it.")
        y = y - 44

        -- Render ONE detected ability (icon + Cast at + macro text + Create/Copy). Shared by interrupts
        -- and stuns. The per-ability Cast at is stored in mac.castTargets keyed by spell id, falling
        -- back to `defaultTarget`. The FIRST of each kind keeps its classic macro name (see AbilityMacroName).
        local function renderAbility(cy, kind, ability, index, defaultTarget, castTip, macroNote)
            local id = ability.id
            local getT = function() return (mac.castTargets and mac.castTargets[id]) or defaultTarget end
            local mname = FTI.AbilityMacroName(kind, ability, index)
            b:GameIcon(x, cy, { spell = id, size = 48 })   -- hover = the real Blizzard spell tooltip
            local line = "Detected: |cff33ff33" .. tostring(ability.name or "?") .. "|r"
            if ability.note then line = line .. "   |cffffcc00(" .. ability.note .. ")|r" end
            b:Label(line, x + 58, cy - 4, C.text)
            b:Label("Cast at", x + 58, cy - 30, C.subtext)
            dropdown(x + 112, cy - 28, 200, KICK_SOURCE, getT,
                function(v) mac.castTargets = mac.castTargets or {}; mac.castTargets[id] = v; FTI.RefreshManager() end,
                (kind == "stun") and "Stun target" or "Interrupt target", castTip)
            cy = cy - 62
            cy = macroBox(FTI.BuildAbilityMacro(ability, getT()), x, cy)
            macroButton(x, cy, 130, mname, ability.icon or "INV_Misc_QuestionMark",
                function() return FTI.BuildAbilityMacro(ability, getT()) end, macroNote)
            tip(b:Button(x + 140, cy, 110, "Copy text", "default", function() copy(mname .. " macro", FTI.BuildAbilityMacro(ability, getT())) end),
                "Copy text", "Open the macro text so you can copy it.")
            return cy - 48
        end

        -- INTERRUPTS (every one your spec/talents give you; each gets its own Cast at + macro)
        b:Sub("INTERRUPTS  (auto-detected for your spec)", x, y); y = y - 30
        local interrupts, ireason = FTI.GetPlayerInterrupts()
        if interrupts[1] then
            for i, intr in ipairs(interrupts) do
                y = renderAbility(y, "interrupt", intr, i, mac.kickTarget or "focus",
                    "Who this interrupt hits: your focus, current target, or mouseover - with a fallback if the first isn't there. Save the macro again after changing this.",
                    " (spec-specific)")
            end
        else
            local _, nh = b:Wrap("|cffffcc00No interrupt macro for your spec.|r  " .. tostring(ireason), x, y - 2, w - 48, C.subtext, 12)
            y = y - (nh + 14)
        end

        -- STUNS (every targeted stun your talents give you; each gets its own Cast at + macro)
        b:Sub("STUNS  (auto-detected for your talents)", x, y); y = y - 30
        local stuns, sreason = FTI.GetPlayerStuns()
        if stuns[1] then
            for i, stun in ipairs(stuns) do
                y = renderAbility(y, "stun", stun, i, "focus_target",
                    "Who this stun hits: your focus, current target, or mouseover - with a fallback if the first isn't there. Save the macro again after changing this.")
            end
        else
            local _, sh = b:Wrap("|cffffcc00No stun macro:|r  " .. tostring(sreason), x, y - 2, w - 48, C.subtext, 12)
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
            -- Colors row.
            b:Label("Background", x + 46, y - 2, C.subtext)
            tip(b:Swatch(x + 150, y - 2, mac.paletteBgColor, function() refreshPalette() end, "Background color"),
                "Background color", "The bar's fill color (pair with Opacity 0 for outline-only).")
            b:Label("Border", x + 240, y - 2, C.subtext)
            tip(b:Swatch(x + 300, y - 2, mac.paletteBorderColor, function() refreshPalette() end, "Border color"),
                "Border color", "The bar's outline color.")
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
        b:Label("only on", x + 4, y - 2, C.subtext)
        tip(b:ClassSpecButton(x + 96, y, {
            selected = mac.triggerSpecs or {},
            title = "Announce on these specs",
            hint = "none checked = announce on every character",
            width = 220,
            onChange = function(sel)
                mac.triggerSpecs = (sel and next(sel)) and sel or nil
                FTI.RefreshManager()
            end,
        }), "Trigger specs", "Only send call-outs while you're playing one of the chosen classes / specs. Leave empty to announce on every character.")
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
        -- (enable/disable lives on the Platform Overview page, not repeated here)
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

    -- Top-level nav now lives in the sidebar (one row per page). Disabled: overlay every page except
    -- Settings (where the enable toggle lives), so the module can always be switched back on.
    if mod and mod.IsEnabled and not mod:IsEnabled() and pageId ~= "settings" then
        return b:DisabledOverlay(x, y, w, { subtitle = "Enable Focus Target Interrupt from the Platform Overview.",
            onSettings = function() if win then win:SelectView("overview") end end })
    end

    -- Standard page heading (matches the platform + other modules).
    local HEAD = {
        macros   = { "Macros",         "Ready-made focus + mark, interrupt, and stun macros for your spec - copy them or save them straight to your macro list." },
        palette  = { "Marker Palette", "An on-screen raid-marker palette to tag your focus / interrupt target with a click." },
        announce = { "Announce",       "Call out your focus / interrupt target to the group when you set it." },
        settings = { "Settings",       "Master options for Focus Target Interrupt and its minimap button." },
    }
    if HEAD[pageId] then y = b:PageHeading(x, y, HEAD[pageId][1], HEAD[pageId][2]) end

    if pageId == "palette" then
        y = renderPalette(y)
    elseif pageId == "announce" then
        y = renderAnnounce(y)
    elseif pageId == "settings" then
        y = renderSettings(y)
    else
        y = renderMacros(y)
    end
    return y
end

-- Page render closures for the sidebar (each delegates to RenderPage with its page id).
local function ftiPages()
    local function pg(id) return function(m, b, x, y, w, win) return RenderPage(id, m, b, x, y, w, win) end end
    return {
        { id = "macros",   label = "Macros",         icon = "keyboard", default = true, disabledSafe = true, render = pg("macros") },
        { id = "palette",  label = "Marker Palette", icon = "target",   disabledSafe = true, render = pg("palette") },
        { id = "announce", label = "Announce",       icon = "message",  disabledSafe = true, render = pg("announce") },
        { id = "settings", label = "Settings",       icon = "settings", disabledSafe = true, render = pg("settings") },
    }
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
    group   = "Focus Target Interrupt",   -- single-module addon: its own sidebar category
    groupColor = "5f8dff",                -- signature tint for this add-on's sidebar category
    rendersWhenDisabled = true,   -- keep our pages (and the Settings page) reachable while disabled
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
    pages = ftiPages(),
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

-- List a shortcut to this module's page on Help > Commands.
if Suite and Suite.RegisterCommand then
    Suite:RegisterCommand({
        cmd = "/tap focus", desc = "Open the Focus Target Interrupt page", owner = "Focus Target Interrupt",
        sub = "focus", handler = function() if Suite.OpenWindow then Suite:OpenWindow("mod:focusInterrupt") end end,
    })
end
