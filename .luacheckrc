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
  -- Shadowing is inherent to this codebase's style and is not a correctness concern (the author's
  -- gates are namespace pollution + dead locals, below): mixin methods nest closures that re-use
  -- `self`, and helpers re-localize `C`/`theme`/`win`/`b`. So the shadow classes are muted wholesale.
  "421",  -- shadowing a local definition (deliberate name reuse in a nested scope, e.g. `cols`)
  "431",  -- shadowing an upvalue (re-localizing `C`/`theme`/`win` inside a closure)
  "432",  -- shadowing an upvalue argument (nested methods reuse `self`/`y` - the mixin pattern)
  -- Unused locals ARE a gate - but a few names are conventional no-ops, not dead code:
  "211/ADDON",     -- the addon vararg tuple `local ADDON, NS = ...`; the addon name is usually unused
  "211/addonName", -- the same convention under a different local name
  "211/UIF",       -- `local ADDON, UIF = ...` where a file only needs the other half of the tuple
  "211/_.*",       -- underscore-prefixed locals are intentional discards (`_id`, `_n`, `_P`, ...)
}

-- Scoring engine: left byte-for-byte untouched (its logic/knobs are change-controlled), so its two
-- benign lint nits are silenced here rather than by editing the source.
files["TAP_MythicLedger/Scoring/Score.lua"] = { ignore = { "211/Cap" } }  -- unused module handle
files["TAP_MythicLedger/Scoring/Tests.lua"] = { ignore = { "411" } }      -- a test fixture reuses `d1`

-- Intentional, writable globals. Anything WRITTEN that is not listed here is namespace
-- pollution (luacheck warning 111), matching the bytecode gate's whitelist.
globals = {
  -- Namespace exports (also written explicitly as _G.<name>)
  "UIFoundry", "TAP",
  -- Load-on-demand data exports, consumed via _G in TAP/Suite.lua
  "TAP_GameDB_Spells", "TAP_GameDB_Items",
  -- SavedVariables (declared in the TOCs; the client populates these as globals)
  "TAPDB", "TAP_CombatAlertsDB", "TAP_CombatAlertsCharDB", "TAP_MythicLedgerDB",
  -- WoW frame we stash private fields on (GameTooltip._tapmlKey/_tapmlOwned); marked writable so the
  -- field writes aren't flagged. Not namespace pollution - it's Blizzard's frame, not a new global -
  -- and the bytecode gate (check-globals.sh) only flags actual global-name writes, not field sets.
  "GameTooltip",
  -- WoW slash-command contract
  "SlashCmdList",
  "SLASH_TAP1",
  "SLASH_TAPMYTHICLEDGER1", "SLASH_TAPMYTHICLEDGER2",
  "SLASH_TWROTCUE1",
}

exclude_files = {
  "**/tools/**",
  "betaportal/**",
}
