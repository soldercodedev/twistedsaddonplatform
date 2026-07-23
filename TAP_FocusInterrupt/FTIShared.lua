-- TAP_FocusInterrupt - FTIShared.lua
-- Bridges the Focus engine (Macros.lua / FocusPalette.lua, split out of Twisteds Combat Alerts) to
-- the Twisteds Addon Platform. Provides the handful of primitives the engine expects (its saved DB,
-- a spell resolver, the message prefix, and the manager-window hooks) so the engine files stay
-- byte-for-byte the same as their Combat Cues originals. Loads FIRST, before the engine.

local addonName, FTI = ...
local Suite = _G.TAP

FTI.PREFIX = "|cff33ff99Focus Target Interrupt:|r "

-- Per-feature gate the module flips (mirrors the Combat Cues bridge). The always-on engine bits
-- (announce watcher, marker palette) respect it.
if FTI.focusEnabled == nil then FTI.focusEnabled = true end

----------------------------------------------------------------------
-- Saved settings. These live in the SUITE's shared DB (per-module), exactly like every other
-- module - so they persist centrally through the suite's SavedVariables and survive /reload. (An
-- addon's own file-scope SavedVariable is unreliable: the global isn't guaranteed populated when
-- this file runs, so a cached reference gets orphaned.) FTI.db is (re)pointed at the module's
-- settings table by FTI.SyncDB(), which callers invoke before touching FTI.db.
----------------------------------------------------------------------
local MACRO_DEFAULTS = {
    mark             = 8,               -- raid-target index (1-8, Star..Skull); 0 = none
    channel          = "NONE",          -- announce channel
    autoFocus        = false,
    announceFocus    = false,
    announceReady    = false,
    announceInstance = "any",
    focusTarget      = "smart",         -- smart (mouseover>target) / target / mouseover
    paletteShown     = false,
    palettePos       = nil,
    paletteScale     = 1.0,
    paletteVisibility = "always",
    paletteRotation  = "horizontal",           -- horizontal (row) or vertical (column)
    paletteBgColor   = { 0.05, 0.05, 0.06 },    -- bar background color
    paletteBorderColor = { 0.25, 0.25, 0.30 },  -- bar border color
    paletteOpacity   = 0.9,                     -- bar background opacity (0-1)
    focusMsg         = "Focus {rt}",
    readyMsg         = "My interrupt target is {rt}",
}

-- Point FTI.db at this module's persistent settings in the suite DB, seeding defaults. Safe to
-- call repeatedly; returns the settings table (or the current FTI.db if the module isn't up yet).
function FTI.SyncDB()
    local mod = Suite and Suite.GetModule and Suite:GetModule("focusInterrupt")
    local s = mod and mod:GetSettings()
    if not s then return FTI.db end
    s.macro = s.macro or {}
    for k, v in pairs(MACRO_DEFAULTS) do if s.macro[k] == nil then s.macro[k] = v end end
    FTI.db = s
    return s
end

local _login = CreateFrame("Frame")
_login:RegisterEvent("PLAYER_LOGIN")
_login:SetScript("OnEvent", function() FTI.SyncDB() end)

----------------------------------------------------------------------
-- Spell resolver (copied from the Combat Cues engine - the only shared primitive the Focus files
-- reached into the alerts engine for). Returns id, name, iconID.
----------------------------------------------------------------------
function FTI.ResolveSpell(input)
    if input == nil or input == "" then return nil, nil, nil end
    local num = tonumber(input)
    local info
    if C_Spell and C_Spell.GetSpellInfo then
        info = C_Spell.GetSpellInfo(num or input)
    end
    if info then
        return info.spellID or num, info.name, info.iconID
    end
    if num then return num, nil, nil end
    return nil, input, nil
end

----------------------------------------------------------------------
-- Manager-window hooks (drive the suite's /tap window).
----------------------------------------------------------------------
function FTI.RefreshManager()
    if Suite and Suite.RefreshWindow then Suite:RefreshWindow() end
end

function FTI.OpenManager()
    if Suite and Suite.OpenWindow then Suite:OpenWindow("mod:focusInterrupt") end
end
