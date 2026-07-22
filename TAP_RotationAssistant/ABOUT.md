# Twisteds Rotation Assistant

## What is it, in one sentence?

It watches the game's built‑in "what should I press next?" helper and shows you the
**keyboard key** for that ability, as a big icon on your screen - so you can just glance at it
and press the key, instead of hunting across your action bars.

---

## The problem it solves

Modern World of Warcraft has a built‑in **Assisted Combat** feature (the "one‑button rotation"
Blizzard added). It's smart about what your class should cast next - but by default it only
highlights the ability on your action bar. If you don't have that bar memorized, you still have
to look down, find the glowing button, and figure out which key it's bound to.

This addon skips all of that. It asks the game the same question ("what's next?"), finds that
ability on your bars, and puts the **keybind** front‑and‑center where you're already looking.
See the ability, see the key, press the key. That's the whole idea.

**It only ever *shows* you the suggestion. It never presses anything for you.** There's no
automation and nothing that plays the game for you - it's just a heads‑up display.

---

## What you actually see

A single icon somewhere on your screen (you choose where) showing:

- **The ability's icon** - the picture of the spell/attack the game suggests next.
- **The keybind** - the actual key you have that ability bound to, shown as text (e.g. `4`,
  `S-4` for Shift+4, `M4` for a mouse button). It reads your *real* bindings, so it's correct
  even if you hide keybind text on your bars.
- **An optional glow** - if the suggested ability is currently "procced" (lit up on your bars),
  the cue can light up too, so you know it's an extra‑good moment to press it.

As you play, the icon and key update to follow the rotation.

---

## Works with your bars (whatever you use)

A lot of people don't use the default Blizzard action bars. This addon figures out your keybind
no matter which bar addon you run:

- **Default Blizzard UI**
- **EllesmereUI** (and other overhauls that restyle the Blizzard bars)
- **ElvUI**
- **Bartender4**
- **Dominos**

It reads the key straight off whichever button actually holds the ability, and falls back to
your raw key binding if needed - so you get the right key even if you've turned off the little
keybind numbers on your bars.

---

## Features and options

Everything below is adjustable in the addon's settings page.

### Where and when it shows

- **Set Placement** - hides the settings window, unlocks the cue, and lets you **drag it
  anywhere** on screen. Click **Done** (or press Escape) when you like where it is. Outside of
  this placement mode the cue is locked, so you can't knock it out of place by accident.
- **Only show in combat** - keep it hidden until a fight starts (on by default). This also
  means it uses **zero resources while you're not fighting**.
- **Class / Spec filter** - only show the cue for the classes/specs you pick. Leave it empty to
  show for everything. There are handy quick‑select buttons for **Tanks, Healers, Ranged DPS,
  and Melee DPS**, so you can, say, turn it on for all your healing specs in one click.
- **Only suggest abilities on a visible button** - a stricter mode that only shows a suggestion
  if it's on a bar you can actually see.

### The icon's look

- **Shape** - Square, Rounded, Circle, or Hexagon frame around the icon (like the fancy shaped
  buttons in some UI packs).
- **Size** - how big the icon is.
- **Zoom** - crop in on the ability art (handy for shaped frames).
- **Scale** - grow or shrink the whole cue; it grows around its center so it stays put.
- **Icon opacity** - fade the icon. Because there's no solid backdrop behind it, fading the icon
  actually lets you **see the game world through it**.
- **Overall opacity** - fade the entire cue at once.

### The border

- **Thickness** - a real, hollow ring around the icon (set to 0 for no border).
- **Color** - any color you like.
- **Opacity** - fade just the border.

### The keybind text

- **Position** - put the key text Below, Above, Left, Right, in the four corners, dead‑center
  over the icon, or a fully **Custom** spot with X/Y sliders.
- **Font** - pick from the bundled fonts.
- **Size** - how big the key text is.
- **Color** - any color.
- **Opacity** - fade just the text.

### The proc glow

- **Proc glow** - light the cue up when the suggested ability is proc‑highlighted (the game's
  "spell activation overlay") on your bars, so you know it's primed to use.

### Live preview

The settings page has a **live preview** that shows a real cue - using your *actual* next
ability while you're fighting - that updates instantly as you drag the sliders. What you set is
exactly what you'll get.

### Performance

- **Scan interval** - how often it re‑checks your next ability, in seconds. Lower = more
  responsive, higher = a little lighter on your computer. It only ever checks **while you're in
  combat** (unless you've turned off "Only show in combat"), and does **nothing** the rest of
  the time - so it's very light on resources.

---

## How it fits into the suite

The Rotation Assistant is a **plug‑in module** of the **Twisteds Addon Suite**. The Suite is a
shared framework that provides the look, the settings window, and a manager where you can turn
individual features on and off.

- Open the manager with **`/tas`**.
- The Rotation Cue appears there as its own entry - toggle it on/off, and all of its settings
  live on its page.
- If you don't want this feature, just switch the module off; if you don't want it *at all*, you
  can fully unload it from the manager's "Installed" page.

There's also a diagnostic command, **`/rcue`**, that prints what the addon currently "sees" -
useful if a keybind ever shows as `?` and you want to report it.

---

## Quick start

1. Make sure both **Twisteds Addon Suite** and **Twisteds Rotation Cue** are installed and
   enabled.
2. Type **`/tas`** and open the **Rotation Assistant** page.
3. Click **Set Placement**, drag the cue where you want it, and click **Done**.
4. Tweak the shape/size/colors to taste - watch the live preview.
5. Jump into combat (a training dummy works great) and it'll start showing your next ability's
   keybind.

That's it. Look at the key, press the key. 🎯
