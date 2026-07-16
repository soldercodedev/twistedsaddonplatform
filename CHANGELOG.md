# Twisteds Addon Platform — Changelog

Platform-level release notes. Each module also keeps its own in-game **What's New** (open `/tap` →
any module → *What's New*), and a `README.md` in its folder.

## 1.0.0-beta.2

Second beta. A brand-new module (Mythic Ledger), a platform look & feel overhaul, and a round of
updates to the modules that already shipped in beta.1. Each module also lists its own changes in its
in-game **What's New** (`/tap` → module → *What's New*).

- **[NEW]** **Mythic Ledger** — a new, private, account-wide Mythic+ journal. It records every timed,
  depleted, or abandoned key automatically (sorted by character), remembers who you've run keys with,
  and can give a short, **private** heads-up when you group with them again. Every run is **graded** —
  an easy-to-read, fair score for each player covering damage & healing, interrupts, dispels, staying
  out of the bad stuff, and deaths — and clicking a player opens a full **review**: their key stats, a
  breakdown of how the grade was earned, and plain-language tips on what they did well and what to
  work on. Plus run/dungeon/character/player pages, personal bests, per-boss stats, a post-run
  scoreboard, and easy backup & sharing. Stats come from the game's own damage meter (with the basics
  still tracked if it isn't available).
- **[NEW]** **Appearance, reworked.** In `/tap` → Settings the look is now two independent choices:
  a **shape** (sharp / rounded) and a **colour scheme** — a neutral greyscale ramp (Obsidian,
  Graphite, Nickel…), **light** themes (Daylight, Parchment), the styled set (Modern/Blizzard/Neon),
  or a WoW-**expansion** palette — plus a full **Custom** editor for every colour. Add a **Menu
  scale** slider to size the whole window.
- **[CHANGE]** **Cleaner module pages** — a selected module's name now shows in the window title
  instead of a repeated in-page header, leaving more room for its settings.
- **[BUG FIX]** Dropdown/menu backgrounds and text now follow the theme on a live swap (fixes stale
  colours on the light themes); shape changes apply to every widget.
- **[CHANGE]** Consistent branding: every add-on shows the shared platform logo and a `Twisteds …`
  name in the AddOns list.
- **[KNOWN]** Mythic Ledger targets Retail Midnight; some live meter/API details are still being
  verified in game. Metrics the meter can't supply show as "—", never a fake zero.

### Updates to existing modules

- **Combat Alerts** — **per-character alert profiles** (switch a character between Account-wide and
  This character in the Profile section, so alerts are no longer shared across all your toons);
  spell/item **Find** search (spellbook, auras, gear, bags, and the game database) with a live icon;
  fixed slider spacing in the alert editor.
- **Rotation Assistant** — `/tap rotation` and `/rcue` slash commands; the cue now follows your
  chosen Platform font.
- **Focus Target Interrupt** — the marker bar now remembers your **saved focus marker** (set it out
  of combat with a chat confirmation; in combat it just marks your target).

## 1.0.0-beta.1

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
