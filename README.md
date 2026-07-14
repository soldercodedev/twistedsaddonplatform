# Twisteds Addon Platform (TAP)

A collection of small, focused World of Warcraft add-ons that live under **one clean UI** and
**one command**. Instead of juggling several add-ons that all look and behave differently, you get a
single hub — open it with **`/tap`**, flip the tools you want on, and leave the rest switched off.

Everything ships in a **single download**. Each feature is its own *module*: turn on only what you
use, and the ones you don't just sit quietly and do nothing.

---

## What's inside

| Module | What it does |
|---|---|
| **Combat Alerts** | Rule-based audible & visual cues — no target, out of range, pulled aggro, pet down, item/trinket ready — from alerts you build yourself. |
| **Focus Target Interrupt** | One-key focus + mark macro, an on-screen raid-marker bar, and auto-detected interrupt/stun macros for your exact spec. |
| **Rotation Assistant** | Shows the **keybind** of Blizzard's suggested next ability on screen (show-only — it never presses anything), with cast/instant, GCD, range and resource indicators. |
| **TAP** (hub) | The shared UI kit + module manager. Always present; this is what `/tap` opens. |
| **TAP&#95;GameDB** | An optional, load-on-demand spell/item name database used by Combat Alerts' search. |

Each module has its own README in its folder for the details.

---

## Install

1. Download and extract into `Interface/AddOns/`. You'll get the folders `TAP`, `TAP_CombatAlerts`,
   `TAP_FocusInterrupt`, `TAP_RotationAssistant`, and `TAP_GameDB`.
2. Launch the game and log in.
3. Type **`/tap`** to open the manager.

You don't have to run everything — open **Installed** (or **Overview**) in the `/tap` window and
toggle any module on or off. A disabled module unloads its code and does nothing until you turn it
back on.

---

## Highlights

- **One look, one window.** A shared, self-skinned theme (accent colour, skin and font are all
  configurable in **Settings**). No external UI libraries.
- **Live on/off.** Toggle modules without a reload; each cleanly stands itself up and down.
- **"What's New" built in.** Every module lists its changelog in plain language — look for the
  *What's New* buttons on Overview, Installed, and About.
- **Combat-safe.** The alert engine avoids Midnight's "secret value" pitfalls; Rotation Assistant is
  purely show-only and never performs a protected action.

---

## Community & support

Questions, bug reports, or ideas? Join the Discord: **https://discord.com/invite/pN5vYDrQ5j**
(there's a one-click "Join our Discord" button on the **About** page in `/tap`).

## License

Original source code and artwork are licensed under the **GNU General Public License, version 2** —
see [`LICENSE`](LICENSE). Bundled third-party fonts, icons, sounds, and game data remain under their
own licenses — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). World of Warcraft and all
Blizzard assets are the property of Blizzard Entertainment, Inc.; this project is not affiliated with
or endorsed by Blizzard.
