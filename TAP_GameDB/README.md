# TAP&#95;GameDB

A small, **optional** support add-on for the **[Twisteds Addon Platform](../README.md)**. You don't
open or configure it - it just makes searches better.

## What it does

Ships the platform's **spell & item name databases** (`SpellDB.lua`, `ItemDB.lua`) as a
**load-on-demand** add-on. The platform pulls it in **only the first time a search needs it** (e.g.
Combat Alerts' *Find* button), so its ~5 MB of names isn't loaded or parsed until you actually use
it.

Any module can reach it centrally through the hub (`TAP:GetSpellDB()` / `TAP:GetItemDB()`); no module
touches the addon directly.

Without it, searches still work - they just fall back to your **spellbook, auras, gear and bags**.

## Data source

The name/ID tables are generated offline from **wago.tools** DB2 exports; the underlying data is
Blizzard game data. See the platform [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

## License

GPL v2 - see the platform [`LICENSE`](../LICENSE).
