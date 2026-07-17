# Rotation Assistant

A module of the **[Twisteds Addon Platform](../README.md)**. Configure it with **`/tap`** →
*Rotation Assistant*.

Reads Blizzard's built-in one-button assistant and shows the **keybind of your next suggested
ability** on screen. It's **show-only** — it never presses anything for you, so there's no
automation and nothing protected.

## What it does

- Draws the next ability's **keybind** (resolved from your action bars) as an on-screen cue.
- **Make it yours:** icon shape (square, rounded, circle, hexagon), size, zoom, border, opacity, and
  where the keybind text sits — with a **live preview** and a **Set Placement** button to drag it
  into position.
- **Optional indicators:**
  - **Cast vs instant** — a colored corner dot (or border tint) for hard casts vs instants.
  - **GCD sweep** — a radial "wipe" on the icon that empties with your global cooldown, shaped to
    your icon.
  - **Out of range** — grey out or red-tint the icon when the suggestion can't reach your target.
  - **Can't afford** — tint the icon when you're short on resource (mana, energy, rage, combo
    points, …).
- **Proc glow** — light up the cue when the suggested ability is proc-highlighted on your bars.

Diagnostics: `/rcue` prints what the assistant is suggesting and how the cue resolves it.

## Requires

The **`TAP`** hub (bundled with the platform download). Blizzard's assistant API (present on modern
clients) is needed for suggestions; without it the cue simply stays hidden.

## License

GPL v2 — see the platform [`LICENSE`](../LICENSE) and [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
