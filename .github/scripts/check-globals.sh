#!/usr/bin/env bash
# Global-namespace pollution gate.
#
# Compiles every shipped Lua file and reads the actual SETGLOBAL opcodes the Lua compiler
# emits (authoritative - no regex heuristics). Any global WRITE that is not an intentional,
# whitelisted export fails the check. This is what a WoWInterface / Ketho-style audit cares
# about most, so we enforce it on every push.
#
# Intentional writable globals:
#   SLASH_*        - required by WoW's slash-command API (SLASH_<NAME>N)
#   *DB            - declared ## SavedVariables (the client populates these as globals)
#   TAP_GameDB_*   - load-on-demand data exports, consumed via _G in TAP/Suite.lua
# Everything else must be `local`, or an explicit `_G.<name> = ...` intentional export
# (an explicit _G write compiles to SETTABLE, not SETGLOBAL, so it is never flagged here).
#
# Local use (Windows/dev with luac 5.1 on PATH):  LUAC=luac bash .github/scripts/check-globals.sh
set -uo pipefail

LUAC="${LUAC:-luac5.1}"
FOLDERS="TAP TAP_CombatAlerts TAP_FocusInterrupt TAP_RotationAssistant TAP_GameDB TAP_MythicLedger"

is_allowed() {
  case "$1" in
    SLASH_*)                                              return 0 ;;
    TAPDB|TAP_CombatAlertsDB|TAP_CombatAlertsCharDB|TAP_MythicLedgerDB) return 0 ;;
    TAP_GameDB_Spells|TAP_GameDB_Items)                   return 0 ;;
    *)                                                    return 1 ;;
  esac
}

fail=0
count=0
while IFS= read -r -d '' f; do
  count=$((count + 1))
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if ! is_allowed "$name"; then
      echo "::error file=${f}::global-namespace pollution: '${name}' is written as a global. Use 'local ${name}', or an explicit '_G.${name} = ...' if it is a deliberate export."
      fail=1
    fi
  done < <("$LUAC" -l -p "$f" 2>/dev/null | grep -E 'SETGLOBAL' | sed -E 's/.*; //')
done < <(find $FOLDERS -name '*.lua' -not -path '*/tools/*' -print0)

if [ "$fail" -eq 0 ]; then
  echo "OK: no global-namespace pollution across ${count} Lua file(s)."
fi
exit $fail
