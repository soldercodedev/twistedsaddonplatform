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
-- `abbr` is a short (<=12 char) tag used only to name the SECOND+ macro when a spec has more than one
-- of a kind; the first detected ability always keeps the classic "TAP Interrupt" / "TAP Stun" name so
-- existing macros keep updating. WoW caps macro names at 16 chars, hence "TAP " + a short abbr.
FTI.INTERRUPTS = {
    WARRIOR     = { { id = 6552 } },       -- Pummel
    ROGUE       = { { id = 1766 } },       -- Kick
    DEATHKNIGHT = { { id = 47528 } },      -- Mind Freeze
    SHAMAN      = { { id = 57994 } },      -- Wind Shear
    MAGE        = { { id = 2139 } },       -- Counterspell
    MONK        = { { id = 116705 } },     -- Spear Hand Strike
    DEMONHUNTER = { { id = 183752 } },     -- Disrupt
    EVOKER      = { { id = 351338 } },     -- Quell
    HUNTER      = { { id = 147362, abbr = "CtrShot" }, { id = 187707, abbr = "Muzzle" } },  -- Counter Shot / Muzzle (Survival)
    PRIEST      = { { id = 15487 } },      -- Silence (Shadow baseline; a talent for Disc/Holy)
    PALADIN     = { { id = 96231, abbr = "Rebuke" },                                 -- Rebuke (all specs)
                    { id = 31935, abbr = "AvShield", note = "silences on hit" },     -- Avenger's Shield (Prot)
                    { id = 375576, abbr = "DivToll", note = "talent" } },            -- Divine Toll (talent)
    DRUID       = { { id = 106839, abbr = "SkullBash" },                                          -- Skull Bash (Feral/Guardian)
                    { id = 78675, abbr = "SolarBeam", ground = true, note = "talent" } },         -- Solar Beam (Balance talent)
    WARLOCK     = { { id = 19647, abbr = "SpellLock", pet = true, note = "needs your Felhunter" },  -- Spell Lock
                    { id = 89766, abbr = "AxeToss", pet = true, note = "needs your Felguard" } },   -- Axe Toss
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

-- Every interrupt the character actually KNOWS, in candidate order. Returns a list of
-- { id, name, icon, ground, pet, note, abbr }; empty list + reasonString when none.
function FTI.GetPlayerInterrupts()
    local _, class = UnitClass("player")
    local list = class and FTI.INTERRUPTS[class]
    if not list then return {}, "No interrupt data for your class." end
    local out = {}
    for _, c in ipairs(list) do
        if knowsSpell(c.id) then
            local rid, name, icon = FTI.ResolveSpell(c.id)
            out[#out + 1] = { id = rid or c.id, name = name, icon = icon, ground = c.ground, pet = c.pet, note = c.note, abbr = c.abbr }
        end
    end
    if #out == 0 then return {}, INTERRUPT_NONE[class] or "No interrupt detected for your current spec / talents." end
    return out
end

-- The character's best available interrupt (first one KNOWN). Returns the info table, or nil, reason.
function FTI.GetPlayerInterrupt()
    local list, reason = FTI.GetPlayerInterrupts()
    if list[1] then return list[1] end
    return nil, reason
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

-- Where the interrupt macro aims: ordered unit fallback chains (first usable unit wins).
local KICK_UNITS = {
    focus           = { "focus" },
    focus_target    = { "focus", "target" },
    target          = { "target" },
    mouseover       = { "mouseover" },
    mouseover_focus = { "mouseover", "focus" },
}

-- Build a "cast <ability> at <unit chain>" macro for ONE detected ability (interrupt or stun).
-- `castTarget` is a KICK_UNITS key (focus / focus_target / target / mouseover / mouseover_focus).
-- Ground-targeted abilities (Solar Beam) drop at the unit's feet, so their conditions check
-- exists/nodead instead of harm. Returns the macro text, or nil if no ability was passed.
function FTI.BuildAbilityMacro(ability, castTarget)
    if not ability then return nil end
    local name = ability.name or ("spell:" .. tostring(ability.id))
    local units = KICK_UNITS[castTarget] or KICK_UNITS.focus
    local conds = {}
    for _, u in ipairs(units) do
        conds[#conds + 1] = ability.ground and ("[@" .. u .. ",exists,nodead]") or ("[@" .. u .. ",harm]")
    end
    return "#showtooltip " .. name .. "\n/cast " .. table.concat(conds) .. " " .. name
end

-- The macro-book name for a detected ability. The FIRST of a kind keeps the classic
-- "TAP Interrupt" / "TAP Stun" (so pre-existing macros keep being updated); the 2nd+ get
-- "TAP <abbr>", kept within WoW's 16-char macro-name limit.
function FTI.AbilityMacroName(kind, ability, index)
    if (index or 1) <= 1 then return kind == "stun" and "TAP Stun" or "TAP Interrupt" end
    local abbr = ability.abbr or (tostring(ability.name or ""):gsub("[^%w]", ""))
    local nm = "TAP " .. abbr
    if #nm > 16 then nm = nm:sub(1, 16) end
    return nm
end

-- Returns macroText, interruptInfo  OR  nil, reasonString. opts.kickTarget picks the aim
-- (a KICK_UNITS key; default focus-only). Kept for the first/primary interrupt + any callers.
function FTI.BuildKickMacro(opts)
    opts = opts or {}
    local intr, reason = FTI.GetPlayerInterrupt()
    if not intr then return nil, reason end
    return FTI.BuildAbilityMacro(intr, opts.kickTarget or "focus"), intr
end

----------------------------------------------------------------------
-- Targeted single-target stuns. Most are talents, so we list every candidate
-- per class and pick the first one the character actually KNOWS.
----------------------------------------------------------------------
FTI.STUNS = {
    WARRIOR     = { { id = 107570 } },        -- Storm Bolt (talent)
    PALADIN     = { { id = 853 } },           -- Hammer of Justice
    ROGUE       = { { id = 408 } },           -- Kidney Shot (needs combo points)
    HUNTER      = { { id = 19577 } },         -- Intimidation (pet stuns your target)
    DRUID       = { { id = 5211, abbr = "MightyBash" }, { id = 22570, abbr = "Maim" } },  -- Mighty Bash (talent) / Maim (Feral)
    DEATHKNIGHT = { { id = 108194 } },        -- Asphyxiate (talent)
    DEMONHUNTER = { { id = 211881 } },        -- Fel Eruption (talent)
    -- No reliable single-target targeted stun: Monk (Leg Sweep is AoE), Warlock
    -- (Shadowfury AoE), Shaman (Cap Totem AoE), Mage, Priest, Evoker.
}

-- Every targeted stun the character KNOWS, in candidate order. Returns a list of
-- { id, name, icon, abbr }; empty list + reasonString when none.
function FTI.GetPlayerStuns()
    local _, class = UnitClass("player")
    local list = class and FTI.STUNS[class]
    if not list then return {}, "Your class has no single-target targeted stun." end
    local out = {}
    for _, c in ipairs(list) do
        if knowsSpell(c.id) then
            local rid, name, icon = FTI.ResolveSpell(c.id)
            out[#out + 1] = { id = rid or c.id, name = name, icon = icon, abbr = c.abbr }
        end
    end
    if #out == 0 then return {}, "No targeted stun with your current talents (most class stuns are talent-gated)." end
    return out
end

-- The first KNOWN targeted stun. Returns the info table, or nil, reason.
function FTI.GetPlayerStun()
    local list, reason = FTI.GetPlayerStuns()
    if list[1] then return list[1] end
    return nil, reason
end

-- Returns macroText, stunInfo  OR  nil, reasonString. opts.stunTarget picks the aim
-- (a KICK_UNITS key; default focus, else target). Kept for the first/primary stun + any callers.
function FTI.BuildStunMacro(opts)
    opts = opts or {}
    local s, reason = FTI.GetPlayerStun()
    if not s then return nil, reason end
    return FTI.BuildAbilityMacro(s, opts.stunTarget or "focus_target"), s
end

----------------------------------------------------------------------
-- Create / update an actual macro (out of combat only).
-- Returns true, index  OR  false, reasonString.
----------------------------------------------------------------------
-- True if a macro with this name already exists in the macro book (global or
-- per-character). Loads the load-on-demand macro API first, same as SaveMacro.
function FTI.MacroExists(name)
    local loader = C_AddOns and C_AddOns.LoadAddOn
    if loader then pcall(loader, "Blizzard_MacroUI") end
    local idx = GetMacroIndexByName and GetMacroIndexByName(name)
    return (idx or 0) > 0
end

function FTI.SaveMacro(name, icon, body, perCharacter)
    if InCombatLockdown and InCombatLockdown() then
        return false, "Can't create or edit macros while in combat."
    end
    -- CreateMacro / EditMacro / GetMacroIndexByName live in Blizzard_MacroUI, which is
    -- load-on-demand - without this they silently fail until the macro window is opened.
    local loader = C_AddOns and C_AddOns.LoadAddOn
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
    local loader = C_AddOns and C_AddOns.LoadAddOn
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
    local loader = C_AddOns and C_AddOns.LoadAddOn
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
