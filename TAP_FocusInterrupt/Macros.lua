-- Twisteds Combat Alerts - Macros.lua
-- The "Macro Factory": generates a set-focus (+ mark + announce) macro and a
-- class/spec-aware interrupt-@focus macro. Knows which specs have no interrupt.
local addonName, FTI = ...

----------------------------------------------------------------------
-- Interrupt database
--
-- Per class: `all` = one interrupt for every spec; `bySpec` = spec-id overrides
-- (with an optional `all` default); `none` = a message for specs with no interrupt.
-- Spec-only classes list only the specs that HAVE one; the rest fall through to
-- the `none` message.
----------------------------------------------------------------------
-- Ordered candidate interrupts per class. We return the FIRST one the character
-- actually KNOWS, so talent-gated interrupts (Balance's Solar Beam, a Warlock pet
-- lock, Divine Toll, etc.) are auto-detected without hard-coding spec rules.
--   id     = spell id
--   ground = ground-targeted (cast @focus, no ,harm)  -- e.g. Solar Beam
--   pet    = cast by your pet (may need the right pet out)
--   note   = short caveat shown in the UI
FTI.INTERRUPTS = {
    WARRIOR     = { { id = 6552 } },       -- Pummel
    ROGUE       = { { id = 1766 } },       -- Kick
    DEATHKNIGHT = { { id = 47528 } },      -- Mind Freeze
    SHAMAN      = { { id = 57994 } },      -- Wind Shear
    MAGE        = { { id = 2139 } },       -- Counterspell
    MONK        = { { id = 116705 } },     -- Spear Hand Strike
    DEMONHUNTER = { { id = 183752 } },     -- Disrupt
    EVOKER      = { { id = 351338 } },     -- Quell
    HUNTER      = { { id = 147362 }, { id = 187707 } },  -- Counter Shot / Muzzle (Survival)
    PRIEST      = { { id = 15487 } },      -- Silence (Shadow baseline; a talent for Disc/Holy)
    PALADIN     = { { id = 96231 },                                   -- Rebuke (all specs)
                    { id = 31935, note = "silences on hit" },         -- Avenger's Shield (Prot)
                    { id = 375576, note = "talent" } },               -- Divine Toll (talent)
    DRUID       = { { id = 106839 },                                  -- Skull Bash (Feral/Guardian)
                    { id = 78675, ground = true, note = "talent" } }, -- Solar Beam (Balance talent)
    WARLOCK     = { { id = 19647, pet = true, note = "needs your Felhunter" },   -- Spell Lock
                    { id = 89766, pet = true, note = "needs your Felguard" } },  -- Axe Toss
}

-- Class-specific "nothing found" explanations.
local INTERRUPT_NONE = {
    PRIEST  = "No interrupt detected - only Shadow (Silence) has one by default; Disc/Holy must talent Silence.",
    DRUID   = "No interrupt detected - Feral/Guardian use Skull Bash; Balance can talent Solar Beam; Resto has none.",
    WARLOCK = "No interrupt detected - Warlock interrupts (Spell Lock / Axe Toss) are pet abilities you must talent and have the matching pet out.",
}

-- True if the character can cast this spell (player book or pet book).
local function knowsSpell(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown then
        if IsSpellKnown(id) then return true end
        if IsSpellKnown(id, true) then return true end  -- pet spellbook
    end
    return false
end

-- Resolve the current character's best available interrupt (first one KNOWN).
-- Returns { id, name, icon, ground, pet, note } on success, or nil, reasonString.
function FTI.GetPlayerInterrupt()
    local _, class = UnitClass("player")
    local list = class and FTI.INTERRUPTS[class]
    if not list then return nil, "No interrupt data for your class." end
    for _, c in ipairs(list) do
        if knowsSpell(c.id) then
            local rid, name, icon = FTI.ResolveSpell(c.id)
            return { id = rid or c.id, name = name, icon = icon, ground = c.ground, pet = c.pet, note = c.note }
        end
    end
    return nil, INTERRUPT_NONE[class] or "No interrupt detected for your current spec / talents."
end

----------------------------------------------------------------------
-- Macro text generation
----------------------------------------------------------------------
-- One macro that sets your focus (your mouseover if you have a live one, else your
-- current target) AND places your marker on that focus. Both /focus and /tm are
-- SECURE macro commands, so this works in combat with no taint - this is the proper
-- way to "mark + auto-focus in one press" (see Blizzard's /tm, Midnight 12.0.7).
-- The trailing "~" on /tm is native overwrite-protection (won't clobber a different mark).
-- opts.mark = 1-8 (0 / nil = focus only, no mark). Announcing is event-driven (below).
function FTI.BuildFocusMacro(opts)
    opts = opts or {}
    local mark = tonumber(opts.mark) or 0
    local src = opts.focusTarget or "smart"
    local focusLine
    if src == "target" then
        focusLine = "/focus"                                    -- current target
    elseif src == "mouseover" then
        focusLine = "/focus [@mouseover,exists,nodead]"         -- mouseover only
    else
        focusLine = "/focus [@mouseover,exists,nodead][]"       -- mouseover, else target
    end
    local lines = { "#showtooltip", focusLine }
    if mark >= 1 and mark <= 8 then
        lines[#lines + 1] = "/tm [@focus] ~" .. mark
    end
    return table.concat(lines, "\n")
end

-- Returns macroText, interruptInfo  OR  nil, reasonString.
function FTI.BuildKickMacro()
    local intr, reason = FTI.GetPlayerInterrupt()
    if not intr then return nil, reason end
    local name = intr.name or ("spell:" .. tostring(intr.id))
    -- Ground-targeted interrupts (Solar Beam) drop at the focus's feet; the rest hit @focus.
    local cond = intr.ground and "[@focus]" or "[@focus,harm]"
    local body = "#showtooltip " .. name .. "\n/cast " .. cond .. " " .. name
    return body, intr
end

----------------------------------------------------------------------
-- Targeted single-target stuns. Most are talents, so we list every candidate
-- per class and pick the first one the character actually KNOWS.
----------------------------------------------------------------------
FTI.STUNS = {
    WARRIOR     = { 107570 },        -- Storm Bolt (talent)
    PALADIN     = { 853 },           -- Hammer of Justice
    ROGUE       = { 408 },           -- Kidney Shot (needs combo points)
    HUNTER      = { 19577 },         -- Intimidation (pet stuns your target)
    DRUID       = { 5211, 22570 },   -- Mighty Bash (talent) / Maim (Feral, combo points)
    DEATHKNIGHT = { 108194 },        -- Asphyxiate (talent)
    DEMONHUNTER = { 211881 },        -- Fel Eruption (talent)
    -- No reliable single-target targeted stun: Monk (Leg Sweep is AoE), Warlock
    -- (Shadowfury AoE), Shaman (Cap Totem AoE), Mage, Priest, Evoker.
}

-- Returns { id, name, icon } for the first KNOWN targeted stun, or nil, reason.
function FTI.GetPlayerStun()
    local _, class = UnitClass("player")
    local list = class and FTI.STUNS[class]
    if not list then return nil, "Your class has no single-target targeted stun." end
    local knownFn = IsPlayerSpell or IsSpellKnown
    for _, id in ipairs(list) do
        local rid, name, icon = FTI.ResolveSpell(id)
        if (not knownFn) or knownFn(id) then
            return { id = rid or id, name = name, icon = icon, known = true }
        end
    end
    return nil, "No targeted stun with your current talents (most class stuns are talent-gated)."
end

-- Returns macroText, stunInfo  OR  nil, reasonString.  (@focus, else @target)
function FTI.BuildStunMacro()
    local s, reason = FTI.GetPlayerStun()
    if not s then return nil, reason end
    local name = s.name or ("spell:" .. tostring(s.id))
    local body = "#showtooltip " .. name .. "\n/cast [@focus,harm][@target,harm] " .. name
    return body, s
end

----------------------------------------------------------------------
-- Create / update an actual macro (out of combat only).
-- Returns true, index  OR  false, reasonString.
----------------------------------------------------------------------
function FTI.SaveMacro(name, icon, body, perCharacter)
    if InCombatLockdown and InCombatLockdown() then
        return false, "Can't create or edit macros while in combat."
    end
    -- CreateMacro / EditMacro / GetMacroIndexByName live in Blizzard_MacroUI, which is
    -- load-on-demand - without this they silently fail until the macro window is opened.
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loader then pcall(loader, "Blizzard_MacroUI") end
    if not CreateMacro then return false, "The macro API is unavailable on this client." end
    local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
    if idx and idx > 0 then
        if EditMacro then EditMacro(idx, name, icon, body) end
        FTI.OpenMacroUI()
        return true, idx
    end
    local ok, newIdx = pcall(CreateMacro, name, icon, body, perCharacter and true or false)
    if ok and newIdx and newIdx > 0 then FTI.OpenMacroUI(); return true, newIdx end
    return false, "Couldn't create the macro - your macro list may be full."
end

-- Quietly update the existing "TAP Focus" macro to match the current marker/focus
-- settings, WITHOUT opening the macro pane. Used by the on-the-fly marker palette.
-- No-op if the macro doesn't exist or we're in combat (EditMacro is combat-protected).
function FTI.UpdateFocusMacro()
    if InCombatLockdown and InCombatLockdown() then return false end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loader then pcall(loader, "Blizzard_MacroUI") end
    if not (GetMacroIndexByName and EditMacro) then return false end
    local idx = GetMacroIndexByName("TAP Focus")
    if idx and idx > 0 then
        EditMacro(idx, "TAP Focus", nil, FTI.BuildFocusMacro(FTI.db and FTI.db.macro))
        return true
    end
    return false
end

-- Open Blizzard's macro pane so the newly created/updated macro is right there to
-- drag onto a bar. Out of combat only (SaveMacro already gates on combat).
function FTI.OpenMacroUI()
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loader then pcall(loader, "Blizzard_MacroUI") end
    if MacroFrame and not MacroFrame:IsShown() then
        if ShowUIPanel then ShowUIPanel(MacroFrame) else MacroFrame:Show() end
    end
end

-- Make marker `i` the SAVED focus marker and write it into the "TAP Focus" macro. Editing a macro
-- only actually sticks with Blizzard's macro pane open, and macros can't be edited in combat - so
-- this force-opens the pane and refuses (leaving the marker unchanged) in combat or if the pane
-- can't be opened. Returns true on success, or false + a reason ("combat" / "nomacroui" / "nodb").
function FTI.SetFocusMarker(i)
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    local m = FTI.db and FTI.db.macro
    if not m then return false, "nodb" end
    local wasOpen = MacroFrame and MacroFrame:IsShown()
    FTI.OpenMacroUI()                                        -- required so the edit below persists
    if not (MacroFrame and MacroFrame:IsShown()) then return false, "nomacroui" end
    m.mark = i
    FTI.UpdateFocusMacro()                                   -- writes the new marker into "TAP Focus"
    -- Auto-close the pane if WE opened it (leave it be if the player already had it up). Deferred one
    -- frame so the edit above is fully committed before we hide it.
    if not wasOpen then
        local function shut()
            if HideUIPanel and MacroFrame then HideUIPanel(MacroFrame)
            elseif MacroFrame then MacroFrame:Hide() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, shut) else shut() end
    end
    return true
end

----------------------------------------------------------------------
-- Focus announce + auto-focus (event driven)
--
-- One marker (FTI.db.macro.mark) drives everything. The announce fires on the
-- focus-changed / ready-check events so it works no matter HOW you set focus
-- (macro, click, keybind, auto-focus). Auto-focus sets your focus to whatever
-- currently carries your marker - Blizzard only permits addon focus out of
-- combat, so it's a no-op in combat (you still marked the target via the keybind).
----------------------------------------------------------------------

-- Fill the {rt} marker-icon tag in an announce line.
-- Target-name parsing was removed on purpose: UnitName on the focus is a "secret" value
-- in combat/instances (Midnight), so we no longer read it at all.
local function fmtAnnounce(msg, mark)
    msg = tostring(msg or "")
    msg = msg:gsub("%%target", ""):gsub("%%t", "")   -- drop legacy name tokens, don't leak them
    local rt = (mark and mark >= 1 and mark <= 8) and ("{rt" .. mark .. "}") or ""
    msg = msg:gsub("{rt}", rt)
    -- Tidy any gap left by a removed token (double spaces, a dangling ": " / " -").
    msg = msg:gsub("%s+", " "):gsub("%s*[:%-]%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return msg
end

local function sendAnnounce(msg, m)
    if not (SendChatMessage and m.channel and m.channel ~= "NONE") then return end
    local text = fmtAnnounce(msg, tonumber(m.mark) or 0)
    if text == "" then return end
    local ch = m.channel
    -- In combat the focus is set by a SECURE action; this handler runs inside that
    -- protected call stack, where SendChatMessage (a restricted API) is blocked. Defer to
    -- a fresh frame so it sends as ordinary insecure code (how other addons announce in
    -- combat). Out of combat this is just a harmless 1-frame delay.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() pcall(SendChatMessage, text, ch) end)
    else
        pcall(SendChatMessage, text, ch)
    end
end

-- Is the announce allowed in the current content? (instance-type gate, e.g. M+ but not raids)
local function instanceAllows(setting)
    if not setting or setting == "any" then return true end
    local inInstance, itype = false, "none"
    if IsInInstance then inInstance, itype = IsInInstance() end
    itype = itype or "none"
    if setting == "none" then return not inInstance end
    if setting == "any_instance" then return inInstance and true or false end
    return itype == setting
end

-- Class/spec gate: the announce only fires while YOUR current spec is one of the chosen specs.
-- `m.triggerSpecs` is a set (specID -> true); empty/nil means every character announces.
-- (A focus unit's spec can't be read via API, so this scopes a shared config per character.)
local function specAllows(m)
    local sel = m.triggerSpecs
    if not sel or not next(sel) then return true end
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return false end
    local specID = GetSpecializationInfo and GetSpecializationInfo(idx)
    return specID ~= nil and sel[specID] == true
end

local focusFrame
function FTI.EnsureFocusWatcher()
    if focusFrame then return end
    focusFrame = CreateFrame("Frame")
    focusFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    focusFrame:RegisterEvent("READY_CHECK")
    focusFrame:SetScript("OnEvent", function(_, event)
        if FTI.focusEnabled == false then return end   -- Focus Tools module disabled in the suite
        local m = FTI.db and FTI.db.macro
        if not m then return end
        if event == "PLAYER_FOCUS_CHANGED" then
            if m.announceFocus and UnitExists and UnitExists("focus") and instanceAllows(m.announceInstance) and specAllows(m) then
                sendAnnounce(m.focusMsg, m)
            end
        elseif event == "READY_CHECK" then
            -- No target/focus is expected at a ready check, so this fires regardless.
            if m.announceReady and instanceAllows(m.announceInstance) and specAllows(m) then sendAnnounce(m.readyMsg, m) end
        end
    end)
end

FTI.EnsureFocusWatcher()
