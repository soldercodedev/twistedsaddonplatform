# Twisteds Addon Platform

**One hub. One command. Pick the tools you want.**

Twisteds Addon Platform (TAP) bundles a set of small, focused combat helpers and trackers under a
single clean UI. No pile of mismatched add-ons, no ten separate config panels - just type **`/tap`**,
switch on the tools you use, and leave the rest off. Everything shares one theme (set your accent
color, skin, and font once and it all matches), and it all arrives in **one download**.

![The /tap hub - every module in one window, each with a live on/off switch](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/01-platform-overview.png)

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

![A Combat Alert firing on-screen mid-pull](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/05-combat-alerts-ingame-no-target.png)

### 🎯 Focus Target Interrupt
Interrupt like a pro. A **one-key Focus + Mark** macro (fully combat-safe), an **on-screen
raid-marker palette** you can click to focus + mark a target live (movable, resizable, row or column,
your colors), and **auto-detected Interrupt & Stun macros** built for your *exact* spec and talents -
just click **Create Macro** and drag it to a bar. Optional **party call-outs** announce your focus or
interrupt target when a ready check starts, so the whole group knows who's got the kick.

![Auto-detected interrupt & stun macros, generated for your spec](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/06-focus-interrupt-macros.png)

### ⌨️ Rotation Assistant
Learning a rotation, or a new spec? TAP reads Blizzard's built-in one-button assistant and draws the
**keybind of your next suggested ability** right on screen. It's **show-only** - it never presses
anything for you, so it's completely allowed. Shape the cue to your UI (size, border, font, position),
and switch on optional extras: a **cast-vs-instant** tint, a **GCD sweep**, an **out-of-range** tint,
and an **out-of-resource** tint.

![The next-ability keybind cue, live in the world](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/13-rotation-assistant-ingame-cue.png)

### 🗝️ Mythic Ledger
Your own **private, account-wide Mythic+ journal**. Every key is recorded automatically - dungeon,
level, affixes, timer result and the **keystone upgrade** you earned (+1 / +2 / +3) - organized by
character. At the end of a run it pops a full **scoreboard**: party DPS/HPS, damage taken, interrupts,
dispels, deaths, boss splits, an in-combat **timeline**, and how your time stacks up **against your
best for that exact key**. An at-a-glance **Group Utility** panel breaks the party's interrupts,
enemy buffs purged, and debuffs cleansed down as landed vs expected.

![End-of-run scoreboard with MVP, party stats, boss splits and timeline](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/20-mythic-ledger-scoreboard.png)

Each player also gets a deterministic **performance grade** - a transparent, group-relative rating
across **Throughput, Interrupts, Dispels, Survival, and Death Impact** (talent-aware, so a spec is
never docked for a tool it doesn't have). Healers and tanks are graded on the **damage the group
actually took**, not a raw HPS number, and a new **Dungeon Guide** lists every dungeon's interrupt and
dispel priorities - which casts to kick, which auras to remove - with the caster shown as a live 3D
model. Every grade shows exactly *how* it was built and what to work on next - no black box, no uploads.

![Per-player grade breakdown - see exactly how the score was built](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/19-mythic-ledger-player-grade.png)

And it remembers **who you've run keys with**: a searchable Players browser, per-player pages (runs
together, timed %, highest key, averages, notes, tags, favorites), and a quiet **returning-player
recap** - printed to *your* chat only - when you regroup with someone. Your shared history rides on
their **Blizzard tooltip** too - hover anyone you've keyed with (unit frames, group finder, /who,
guild, friends) to see keys together, timed %, and their average grade, right alongside RaiderIO.
Everything stays **local and private**: no data is uploaded, and there are no ratings, blacklists, or
judgements of other players.

![Account-wide Overview - your season at a glance](https://raw.githubusercontent.com/soldercodedev/twistedsaddonplatform/beta/media/14-mythic-ledger-overview.png)

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
