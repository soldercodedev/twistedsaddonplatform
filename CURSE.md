# Twisteds Addon Platform

**Website:** https://tap.soldercode.dev/

**One hub. One command. Pick the tools you want.**

Twisteds Addon Platform (TAP) bundles a set of small, focused combat helpers and trackers under a
single clean UI. No pile of mismatched add-ons, no ten separate config panels - just type **`/tap`**,
switch on the tools you use, and leave the rest off. Everything shares one theme (set your accent
color, skin, and font once and it all matches), and it all arrives in **one download**.

![The /tap hub - every module in one window, color-coded in the sidebar, each with a live on/off switch and its own version badge](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/platform-overview.png)

> Type **`/tap`** to open the manager. Every module has a live on/off switch - flip one off and it
> unloads and gets out of the way. No reload needed.

---

## ✨ Modules

### 🔔 Combat Alerts
Never miss the moment that matters. Build your own **audible & visual cues** for *no target, out of
range, pulled aggro, pet down, low health, trinket/ability ready* - and anything else - with sounds,
big on-screen text, and icons you place yourself. Start from simple **"typed" alerts** for the common
cases, or open the **advanced AND/OR builder** for fully custom conditions, and point any alert at a
specific ability or item with the built-in **spell/item search**. Alerts can be **scoped to just the
specs that need them**, and saved per-character or shared account-wide.

![The Combat Alerts list - each alert has a live toggle, its own icon, and the active profile is scoped to the current character](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/combat-alerts-alerts.png)

Every alert has a full editor split into **Load, Trigger, Sound, Visual, and Chat** tabs. Drag the
on-screen text or icon in a live preview, pick the font, size, and color, toggle a **pulse/fade**,
and hit **Test cue** to see exactly what it will look like mid-fight before you ever pull.

![The alert editor - a live on-screen preview with draggable text and icon, plus font, color, pulse, and Test cue controls](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/combat-alerts-editor.png)

### 🎯 Focus Target Interrupt
Interrupt like a pro. A **one-key Focus + Mark** macro (fully combat-safe), an **on-screen
raid-marker palette** you can click to focus + mark a target live (movable, resizable, row or column,
your colors), and **auto-detected Interrupt & Stun macros** built for your *exact* spec and talents -
just click **Create Macro** and drag it to a bar. Optional **party call-outs** announce your focus or
interrupt target when a ready check starts, so the whole group knows who's got the kick.

![Ready-made macros generated for your spec - a combat-safe Focus + Mark, plus Interrupt and Stun macros with your actual kick and stun auto-detected (Pummel, Storm Bolt)](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/focus-interrupt-macros.png)

### ⌨️ Rotation Assistant
Learning a rotation, or a new spec? TAP reads Blizzard's built-in one-button assistant and draws the
**keybind of your next suggested ability** right on screen. It's **show-only** - it never presses
anything for you, so it's completely allowed. Switch on optional extras: a **cast-vs-instant** tint,
a **GCD sweep**, an **out-of-range** tint, and an **out-of-resource** tint - each with a live preview
so you can see the state at a glance.

![Optional indicators around the cue - cast-vs-instant border tint, GCD sweep, out-of-range tint, and can't-afford desaturation, each shown in a live preview](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/rotation-assistant-indicators.png)

Shape the cue to your UI down to the pixel: **icon shape, size, zoom, scale, and opacity**, border
thickness and color, and keybind-text font, size, position, and color - all previewed live as you
drag the sliders.

![Appearance controls - icon shape, size, zoom, border, and keybind-text styling, with a live preview of your next-cast cue](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/rotation-assistant-appearance.png)

### 🗝️ Mythic Ledger
Your own **private, account-wide Mythic+ journal**. Every key is recorded automatically - dungeon,
level, affixes, timer result and the **keystone upgrade** you earned (+1 / +2 / +3) - organized by
character. At the end of a run it pops a full **scoreboard**: party DPS/HPS, damage taken, interrupts,
dispels, deaths, boss splits, an in-combat **timeline**, and how your time stacks up **against your
best for that exact key**. An at-a-glance **Group Utility** panel breaks the party's interrupts,
enemy buffs purged, and debuffs cleansed down as landed vs expected.

![End-of-run scoreboard - MVP, top DPS/HPS/interrupts, Group Utility landed-vs-expected, a full party table with grades and item level, boss splits, and a pull-and-death timeline](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-scoreboard.png)

An account-wide **Summary** rolls your whole season into one glance: total runs, timed %, highest
timed key, average key/time/deaths, unique teammates met, most-played dungeon and character, and your
timed / depleted / abandoned split.

![The Summary page - season stats at a glance: runs, timed %, highest key, averages, players met, and run outcomes](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-summary.png)

Drill into everything you've logged. The **Runs** list is a filterable, sortable history of every
timed, depleted, or abandoned key (by season, result, character, dungeon, key level, and role), and
the **Dungeons** view rolls each dungeon up into a card - best time, timed %, average deaths, and your
highest key - so you can see at a glance where you're sharp and where you're leaking time.

![The Runs list - every key you've recorded, filterable by season, result, character, dungeon, key level, and role, with DPS and HPS per run](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-runs.png)

![The Dungeons view - each dungeon as a card with best time, timed %, average deaths, and your highest key over its own artwork](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-dungeons.png)

A **Personal Bests** board ranks your top runs of the season and assigns each a letter grade, from a
perfect **S+** on down, so your cleanest keys rise to the top.

![Personal Bests - your top 10 runs of the season, each with its keystone level, time, DPS, and a letter grade from S+ down](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-bests.png)

Each player also gets a deterministic **performance grade** - a transparent, group-relative rating
across **Throughput, Survival, Deaths, Interrupts, and Dispels** (talent-aware, so a spec is never
docked for a tool it doesn't have). Healers and tanks are graded on the **damage the group actually
took**, not a raw HPS number. Nothing about it is a black box: a built-in **Scoring Guide** lays out
exactly how every metric is weighted and the guardrails that keep you from being penalized for a
teammate going above and beyond.

![The Scoring Guide - a plain-language breakdown of all five metrics, their weights, and the guardrails that protect your grade](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-scoring-guide.png)

A new **Dungeon Guide** lists every dungeon's interrupt and dispel priorities - which casts to kick,
which auras to remove, and how urgent each one is - with the caster shown as a live 3D model so you
know exactly who to watch for.

![The Dungeon Guide - per-dungeon interrupt and dispel priorities, color-coded by urgency, with the caster rendered as a live 3D model](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-dungeon-guide.png)

When someone falls, Mythic Ledger tells you **why** - a concise death report that classifies each
death as a **missed kick, avoidable, threat, or unavoidable** hit, so the group learns from the wipe
instead of guessing.

![The in-game death report - each death timestamped and classified as missed kick, avoidable, threat, or unavoidable](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/mythic-ledger-death-report.png)

And it remembers **who you've run keys with**: a searchable Players browser, per-player pages (runs
together, timed %, highest key, averages, notes, tags, favorites), and a quiet **returning-player
recap** - printed to *your* chat only - when you regroup with someone. Your shared history rides on
their **Blizzard tooltip** too - hover anyone you've keyed with (unit frames, group finder, /who,
guild, friends) to see keys together, timed %, and their average grade, right alongside RaiderIO.
Everything stays **local and private**: no data is uploaded, and there are no ratings, blacklists, or
judgements of other players.

---

## Why a platform?

- **One look, one window.** A shared, self-skinned theme - set the accent color, skin, and font
  once and everything matches.
- **Only what you want.** Toggle any module on or off, live - right from its own page. Off means
  unloaded and out of the way.
- **"What's New" built in.** Every module explains its updates in plain language, right in the
  window.
- **Combat-safe & lightweight.** No external UI libraries; careful around the game's new protected
  values, and nothing that presses your buttons for you.

---

## 📥 Getting started

1. Install and log in.
2. Type **`/tap`**.
3. Flip on the modules you want in **Overview** or **Installed**, then open each one to set it up.

---

## 💬 Community

**Come help shape it.** Twisteds Addon Platform is actively in development, and the best ideas come
from the people actually running keys. Right now we're especially looking for hands to help **dial in
the Mythic Ledger scoring** - real runs, real feedback on where a grade feels right or wrong - plus
**feature suggestions, bug reports, and testing** to push the whole platform forward.

Whether you're here to fine-tune the numbers, pitch an idea, squash a bug, or just say hi - you're
welcome. **[Join the Discord »](https://discord.com/invite/pN5vYDrQ5j)** and jump in.

---

## ⚖️ License & credits

Source and original art are **GPL v2**. Bundled fonts, icons, sounds, and game data remain under
their own licenses (see the in-package `THIRD_PARTY_NOTICES.md`). World of Warcraft and all Blizzard
assets belong to Blizzard Entertainment, Inc. - this project is not affiliated with or endorsed by
Blizzard.
