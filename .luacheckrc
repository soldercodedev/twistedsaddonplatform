-- Luacheck config for Twisteds Addon Platform (a World of Warcraft retail addon suite).
--
-- WoW runs Lua 5.1, and the ~thousands of WoW API globals are provided by the game client,
-- not visible to luacheck. So reading an undefined global is NOT an error here; the things we
-- do care about are namespace pollution (accidental global WRITES) and dead/unused locals.
--
-- Note: the authoritative pollution gate is .github/scripts/check-globals.sh (compiler bytecode).
-- This config powers the complementary luacheck lint (unused locals, shadowing, redefinition).

std = "lua51"
max_line_length = false

ignore = {
  "113",  -- accessing an undefined global (that's the WoW API, provided by the client)
  "212",  -- unused argument (event handlers/callbacks routinely ignore self/event/... args)
  "231",  -- variable set but never accessed via a later branch is often intentional here
}

-- Intentional, writable globals. Anything WRITTEN that is not listed here is namespace
-- pollution (luacheck warning 111), matching the bytecode gate's whitelist.
globals = {
  -- Namespace exports (also written explicitly as _G.<name>)
  "UIFoundry", "TAP",
  -- Load-on-demand data exports, consumed via _G in TAP/Suite.lua
  "TAP_GameDB_Spells", "TAP_GameDB_Items",
  -- SavedVariables (declared in the TOCs; the client populates these as globals)
  "TAPDB", "TAP_CombatAlertsDB", "TAP_CombatAlertsCharDB", "TAP_MythicLedgerDB",
  -- WoW slash-command contract
  "SlashCmdList",
  "SLASH_TAP1",
  "SLASH_TAPMYTHICLEDGER1", "SLASH_TAPMYTHICLEDGER2",
  "SLASH_TWISTEDSCOMBATCUES1", "SLASH_TWISTEDSCOMBATCUES2",
  "SLASH_TWROTCUE1",
}

exclude_files = {
  "**/tools/**",
  "betaportal/**",
}
