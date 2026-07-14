# Twisteds Addon Platform — Changelog

Platform-level release notes. Each module also keeps its own in-game **What's New** (open `/tap` →
any module → *What's New*), and a `README.md` in its folder.

## 1.0.0

First public release of the platform. Everything ships as one download.

- **[NEW]** **Twisteds Addon Platform** — a single hub (`/tap`) that hosts every tool under one
  shared look, with live on/off toggles per module and a built-in "What's New" for each.
- **[NEW]** **Combat Alerts** — build your own rule-based audible & visual cues (no target, out of
  range, aggro, pet down, item ready). Includes a spell/item search backed by an optional bundled
  database. *(Grew out of the standalone "Twisteds Combat Cues".)*
- **[NEW]** **Focus Target Interrupt** — one-key focus + mark macro, an on-screen raid-marker bar
  (movable, resizable, recolourable, row or column), and auto-detected interrupt/stun macros for
  your spec and talents.
- **[NEW]** **Rotation Assistant** — draws the keybind of Blizzard's suggested next ability on
  screen (show-only), with cast-vs-instant, GCD sweep, out-of-range, and out-of-resource indicators.
- **[NEW]** **TAP&#95;GameDB** — an optional, load-on-demand spell/item name database, loaded
  centrally by the platform only when a search needs it.

### Notes

- **[CHANGE]** The old standalone *Twisteds Combat Cues* has been split into two focused modules —
  **Combat Alerts** and **Focus Target Interrupt** — and rebuilt on the shared platform UI.
- **[CHANGE]** Alert **group-range** checks are hidden: Blizzard's API changes make them unreliable
  across all content, so alerts prefer a spell-range check to your target instead.
- **[KNOWN]** Exported alert strings from the old add-on still import (the `TCCX1!` format is
  accepted).
