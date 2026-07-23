# Combat Alerts

A module of the **[Twisteds Addon Platform](../README.md)**. Configure it with **`/tap`** →
*Combat Alerts*.

Build your own **combat-safe cues** - sounds, big on-screen text, and icons - that fire on the
situations you care about.

## What it does

- **Typed alerts** for the common cases, one click each: Range, Target, Threat, Pet, Item.
- **Advanced alerts** with an **AND / OR** condition builder for anything custom.
- Per-alert **actions**: play a sound, flash on-screen text (font, size, color, position, pulse),
  show and place an **icon**, and/or print a chat message.
- **Load rules** so an alert only runs where it should - by class/spec, in/out of combat, group
  state, or content type.
- A **spell/item search** (the **Find** button) that looks through your spellbook, auras, gear and
  bags by name; paste a numeric spell or item ID to add anything outside those.
- **Export / Import** your alert set as a text string to back up or share.

## Notes

- **Group-range** checks are hidden: Blizzard's API changes make them unreliable across all content,
  so alerts prefer a **spell-range check to your target** instead. Existing group-range alerts still
  run.
- Import accepts strings from the old standalone *Twisteds Combat Cues* (`TCCX1!` format).

## Requires

The **`TAP`** hub (bundled with the platform download).

## License

GPL v2 - see the platform [`LICENSE`](../LICENSE) and [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
