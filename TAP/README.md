# UIFoundry

A self-skinned, **dependency-free** UI kit for World of Warcraft addons - extracted from
*Twisteds Combat Cues* so a whole suite of tools can share one look.

Flat dark theme with a configurable accent. No external textures or libraries: solid-color
textures + built-in (or your own bundled) fonts. Careful about Midnight's "secret value"
API (safe scroll math, no comparing protected values).

Add it as a **dependency addon** and each of your tools gets a full component library - from
typography and buttons to progress bars, form controls, cards, tabs, social buttons, toasts,
pickers, dialogs, a pooled content builder, and a complete application window shell.

The component gallery (`Showcase.lua`) has no slash command; open it with
`UIFoundry._demoWindow:Toggle()` for local testing.

---

## Install / depend on it

Ships as the addon folder **`TwistedsAddonSuite`** (the shared lib for the suite).

1. The folder lives at `Interface/AddOns/TwistedsAddonSuite/`.
2. In each consuming addon's `.toc`: `## Dependencies: TwistedsAddonSuite` (the folder name)
3. Reach it through the global (either works): `local UIF = _G.UIFoundry` (or `_G.TwistedsAddonSuite`)

## Quick start

```lua
local UIF   = _G.UIFoundry
local theme = UIF:NewTheme({ name = "MyAddon", accent = { 0.13, 0.79, 0.59 } })

local btn = theme:Button(parent)
btn:Configure("Save", 100, 26, "primary", function() print("saved") end)
```

Each addon creates **its own theme** so it can carry its own accent while sharing all the
component code.

### `UIF:NewTheme(opts)` → `theme`

| option | meaning |
|--------|---------|
| `name` | prefixes the library's global frame names - give a **unique** value per addon |
| `accent` | `{ r, g, b }` accent color |
| `palette` | override base palette entries (`bg`,`sidebar`,`panel`,`card`,`hover`,`border`,`text`,`subtext`,`accent`) |
| `font` | UI font path (probed; falls back to the game font) |
| `fonts` | `{ { key=, label=, path= }, ... }` registry for font dropdowns / Preview |
| `iconDir` | folder of bundled TGA icons (brand + UI glyphs) - see **ICONS.md** |
| `iconInset` | default `SetTexCoord` crop for game icons |
| `onAccent` | `function(theme)` after `ApplyAccent` - retheme any live widgets you keep |

---

## Skins (color + shape)

A **skin** is a named preset that changes both the palette/accent **and the shape** - corner
radius, border weight, and font. Pick one at creation or swap it live.

```lua
local theme = UIFoundry:NewTheme({ name = "MyAddon", skin = "rounded" })
theme:ApplySkin("blizzard");  win:Refresh()      -- swap live, then re-render
```

Built-in skins (`UIFoundry.SKIN_ORDER`): **flat** (default, square) · **rounded** (soft 8px) ·
**modern** (teal, deep palette, 12px) · **blizzard** (dark gold, square, heavy border) ·
**neon** (magenta, 10px), plus a preset per **WoW expansion** (`classic`, `tbc`, `wrath`,
`cataclysm`, `mop`, `wod`, `legion`, `bfa`, `shadowlands`, `dragonflight`, `warwithin`,
`midnight`) - each
its signature accent over a subtly tinted palette. `theme:SkinLabel(name)` gives a display
label. Add your own to `UIFoundry.SKINS`.

The skin's `radius` becomes the default corner for buttons, inputs, dropdowns, cards, badges,
and every `StylePanel` panel; `borderSize` sets border weight. Override per-widget any time
with `radius` / `corner`. A `Window` re-skins its whole chrome on `Refresh`, so a live skin
swap restyles the entire window. The showcase's **Appearance → Skins** page swaps them live.

## Restyle anything at draw time

Almost every component accepts an **`opts` table** so you can override how it looks *when you
draw it* - no theme edits needed. Colors may be `{ r, g, b }` **or** a `"RRGGBB"` hex string
anywhere.

Standard style keys (a component ignores keys that don't apply):

```
Text:   font · fontSize · fontFlags ("OUTLINE"/"THICKOUTLINE"/"") · textColor · justify · wrap
Fill:   color · hoverColor · activeColor · bg
Border: border = { color =, size = }   (Button/Badge draw a ring; color takes a palette key or hex)
Corner: radius (number / "pill") · corner ("square"/"sm"/"md"/"lg"/"pill")
Shadow: shadow = true  or  { spread =, offsetX =, offsetY =, alpha =, color = }
Box:    width · height · alpha
Icon:   icon · iconSize · iconColor · iconCoords · iconInset · iconVariant ("filled")
```

**Shadows & borders** make elements pop. `shadow` works on **Button**, **Badge**/pills, and any
`StylePanel` component (**Card**, inputs, modals); `border` draws a ring on **Button** and
**Badge**. `theme:AttachShadow(frame, spec)` adds one to any frame, and `theme:Color(spec)`
resolves a palette key / hex / `{r,g,b}`.

```lua
theme:Button(p):Configure("Go", 100, 28, "primary", cb, { corner = 8, shadow = true, border = { color = "FFFFFF" } })
theme:Badge(p, { text = "NEW", variant = "success", pill = true, shadow = true })
theme:Card(p, { title = "Stats", shadow = { spread = 8, alpha = 0.5 } })
```

`font` can be a bundled key (`"UBUNTU"`, `"POPPINS"`, …) or a path - the ~17 fonts packed
in `assets/fonts` are registered by default, and **Ubuntu is the default UI font** (falls
back to the game font if it isn't loadable yet).

Examples:

```lua
-- a purple button with a white icon and a hairline border
theme:Button(parent):Configure("Invite", 120, 28, "primary", cb, {
  color = "6610F2", hoverColor = "7A28FF", textColor = "FFFFFF",
  icon = "Interface\\ICONS\\Achievement_GuildPerk_EverybodysFriend", iconSize = 14,
  border = { color = "2E3440", size = 1 }, fontSize = 13,
})

-- a mint toggle, a bordered mint input, a red slider thumb
theme:Toggle(p):Configure(true, cb, { color = "20C997", width = 44 })
theme:EditBox(p):ApplyStyle({ bg = "101216", border = { color = "20C997" }, fontSize = 13 })
theme:Slider(p):ApplyStyle({ trackColor = "2E3440", thumbColor = "FF5E5B", hideValue = true })

-- a heading, recolored and resized per call
theme:Heading(parent, { text = "Overview", role = "h1", textColor = "20C997", fontSize = 24 })
```

Core widgets expose `:ApplyStyle(opts)`; `Button:Configure` and every rich component take
`opts` directly. There are also two style helpers you can use on your own frames:
`theme:StyleFont(fs, opts)`, `theme:StyleFrame(frame, opts)`, and a one-call panel builder
`theme:Panel(parent, { bg =, border =, width =, height = })`.

---

## Component catalog

Everything below is a `theme:` method. Rich components take an `opts` table; the Builder
(see further down) can draw each at an `(x, y)` on a scroll page.

### Typography
| component | what it is |
|-----------|-----------|
| **Heading** | text with a named **role**: `display · h1 · h2 · h3 · h4 · h5 · h6 · title · subtitle · overline · caption · label · body`. Every role's size/weight/color is overridable. |
| **Label / Wrap** | plain + word-wrapped text (via the Builder) |

### Buttons & controls
| component | notes |
|-----------|-------|
| **Button** | kinds `primary` · `danger` · `default` · `ghost`; **square or rounded corners** (`radius`/`corner`, incl. `pill`); optional left icon; full style overrides |
| **Toggle** | on/off switch; custom on/off colors + size |
| **Dropdown** | `:SetChoices` · `:SetIconChoices` (icon per row) · `:SetMenu` (custom/dynamic, **submenus**) |
| **Menu** | the themed popup behind dropdowns (`theme:OpenMenu`); **section headers, per-row icons, per-row fonts, nested submenus** |
| **Slider** | **editable value readout** (click to type an exact number); custom track/thumb colors |
| **RangeSlider** | **single or dual-thumb range** selector; `onChange(lo, hi)` (or one value) |
| **EditBox** | single-line input; commit on Enter + focus loss |
| **Icon** | framed icon button; tint / border / crop overrides |
| **Swatch** | color well that opens the color picker |
| **Checkbox** | labeled check (custom check color) |
| **NavRow** | sidebar row (icon + label + optional toggle) with a `:Select` state |

### Form controls
| component | notes |
|-----------|-------|
| **RadioGroup** | single-select, vertical or horizontal |
| **SegmentedControl** | connected buttons, single-select (iOS-style) |
| **Stepper** | number field with - / + buttons, min/max/step |
| **SearchBox** | input with search glyph, placeholder, live `onChange`, clear (×) |
| **TextArea** | multi-line, scroll-clipped input |
| **ComboBox** | a select that opens a **searchable, icon-capable** list popup |
| **FontSelect** | font picker where **each option is rendered in its own font** (bundled font set) |

### Feedback & progress
| component | notes |
|-----------|-------|
| **ProgressBar** | determinate (`:SetValue`) or **indeterminate** sweep; custom fill/bg/text |
| **Spinner** | rotating loader (bundled loader icon, or art-free fallback) |
| **Toast** | stacking notifications; variants `info · success · warning · danger`; 7 positions (`TOP · TOP-LEFT · TOP-RIGHT · BOTTOM · BOTTOM-LEFT · BOTTOM-RIGHT · CENTER`); `animation` `fade · slide · none`; `dismissible` × button; `duration` (0 = sticky); optional **`sound`** |

### Sound
| API | notes |
|-----|-------|
| **PlaySound** | `theme:PlaySound(key, channel)` - plays a bundled `.ogg`/`.mp3` (Sounds/, ~64 from TCC) or a Blizzard `SOUNDKIT` sound, with fallback |
| **SoundSelect** | dropdown of all sounds (grouped), **previews on pick** |
| **SoundList / SoundLabel / ResolveSound** | catalog access |

Toasts take an optional sound: `sound = "AirHorn"` plays that key, or `sound = true` plays the
variant's default (info→subtle, success→ready-check, warning→alarm, danger→raid-warning).

Toasts spawn against the **viewport by default**, or **within a frame's bounds** via
`parent` (e.g. your window) + `inset`:

```lua
theme:Toast({ text = "In the corner of my window", parent = win.frame, position = "BOTTOM-RIGHT", inset = 10 })
```

```lua
theme:PlaySound("AirHorn")                                   -- Master channel
theme:Toast({ text = "Pull!", variant = "warning", sound = "AirHorn" })
theme:Toast({ text = "Done", variant = "success", sound = true })
theme:SoundSelect(parent, { value = "Focus", onChange = function(key) db.cue = key end })
```

### Display & layout
| component | notes |
|-----------|-------|
| **Badge** | tag/pill; variants `accent · neutral · success · warning · danger · info`; **square, rounded (`radius`), or `pill`**; optional dot |
| **Card** | container with optional **header** (title/subtitle + accent bar), **footer**, and **colored `variant`s**; `.body` / `.header` / `.footer` regions |
| **TooltipPreview** | a static, styled tooltip you drop on a page to design content (title + colored lines) |
| **StatTile** | KPI tile: label + big value + optional trend delta |
| **Separator** | horizontal/vertical rule, with an optional centered label |
| **Avatar** | circular icon/texture tile with optional ring |
| **TabBar** | horizontal tabs with an active underline |
| **Accordion** | collapsible header + body (chevron), `:Toggle` / `:SetExpanded` |
| **Preview** | large text with a **draggable** icon (for on-screen alert authoring) |
| **Logo** | image inside an accent-bordered tile |

### Icons
| component | notes |
|-----------|-------|
| **bundled set** | ~200 Tabler glyphs (outline **and** filled) + socials, as white TGAs you tint any color |
| **GetIcon / IconPath / HasIcon** | resolve a bundled name (or path / fileID) to a texture |
| **Glyph** | a standalone, colorable icon display (`:SetGlyph`, `:SetColor`) |

Set `iconDir` on the theme, then reference icons by bare name anywhere a component takes an
`icon`, add `iconVariant = "filled"` where you want the filled look, and tint with
`iconColor`. See **ICONS.md**.

```lua
theme:GetIcon("sword")             -- "...\icons\sword.tga"
theme:GetIcon("shield", "filled")  -- filled variant (falls back to outline if none)
theme:Glyph(parent, { icon = "flame", size = 24, color = "FF7A00" })
theme:Button(p):Configure("Attack", 100, 26, "primary", cb, { icon = "sword", iconColor = "FFD166" })
```

### Character / live game data
| component | notes |
|-----------|-------|
| **Portrait2D** | a unit's flat 2D portrait (`SetPortraitTexture`), optional circular mask + ring, auto-refreshing |
| **PortraitModel** | a 3D head-and-shoulders portrait (`PlayerModel`, face zoom) |
| **UnitModel** | a full 3D character model, **drag to rotate** |
| **GameIcon** | the icon for any **spell / buff / debuff / item**, with the real game tooltip on hover |

Portraits and models take a **`background`** (scene behind the character): a bundled scene
name (`dusk · ember · arcane · verdant · steel · void`), a `{r,g,b}`/hex color, an
`"atlas:Name"`, a texture path, or - for a truly **animated** backdrop - `"model:<fileID>"`
(a live 3D M2). Named presets exist (`"model:illidan"`, `"model:arthas"` - verified fileIDs
in `UIF.MODEL_BACKDROPS`); pass a raw number for any other (find them on wago.tools DB2
*ModelFileData*). Static scenes also take `animated = true` for a gentle breathing accent
glow. `:SetBackground(spec, animated)` swaps it live.

```lua
theme:Portrait2D(parent, { unit = "player", size = 64, circular = true, background = "dusk" })
theme:PortraitModel(parent, { unit = "player", size = 96, background = "arcane" })
local m = theme:UnitModel(parent, { unit = "target", width = 150, height = 220, background = "ember" })
m:SetBackground("atlas:Some-Scene")   -- or a color / texture path
local ic = theme:GameIcon(parent, { spell = 133, size = 36 })   -- Fireball; also { item = 6948 } / { aura = 1459 }
ic:SetItem(5512);  ic:SetSpell(116);  ic:SetAura(21562)          -- swap live
```

### Social
| component | notes |
|-----------|-------|
| **SocialButton** | brand icon + official brand color, opens a link (copy dialog) or custom handler |
| **SocialBar** | a row of social buttons (icon-only or labeled) |

Built-in brands (in `UIFoundry.BRANDS`, with bundled icons): **Discord, GitHub, Patreon,
Twitch, YouTube**. Add your own with one line (see ICONS.md). Without an `iconDir` a social
button falls back to its label on the brand color.

```lua
theme:SocialButton(parent, { brand = "discord", url = "https://discord.gg/xxxx" })
theme:SocialBar(parent, {
  { brand = "discord", url = "…" }, { brand = "github", url = "…" }, { brand = "youtube", url = "…" },
}, { iconOnly = true, size = 28 })
```

### Pickers & dialogs
| component | notes |
|-----------|-------|
| **OpenColorPicker** | preview + hex + RGB sliders + presets; live callback |
| **OpenIconPicker** | generic icon grid (bundled TGAs / fileIDs), optional "use default" |
| **ShowCopyDialog / ShowLinkDialog** | hand a string/URL to the user (Ctrl+C) |
| **ShowInputDialog** | take a pasted string + accept |
| **CaptureKey** | modifier-aware key-combo prompt (returns e.g. `"CTRL-F"`) |
| **Modal** | centered dialog; variants, icon, custom content, footer buttons, stacking; `dim = false` (no darken), `closeOnClickOutside = false` (non-modal / floating) |
| **Alert / Confirm / Prompt** | ready-made modals (message + OK / Confirm-Cancel / text input) |

Copy/link dialogs take options: `theme:ShowLinkDialog(title, url, { autoClose = true })` - a
**single-line** box that **auto-closes** once you copy and click away / press Escape (WoW can't
detect the copy itself). `ShowCopyDialog(title, text, info, { singleLine =, autoClose = })`.

```lua
theme:Alert({ title = "Saved", message = "Done.", variant = "success" })
theme:Confirm({ title = "Delete?", message = "Can't be undone.", variant = "danger",
                confirmLabel = "Delete", onConfirm = fn })
theme:Prompt({ title = "Rename", value = "Old name", onAccept = function(text) ... end })
local m = theme:Modal({ title = "Settings", width = 460, height = 300,
    content = function(body, modal) ... end,
    buttons = { { label = "Save", kind = "primary", onClick = function(m) m:Close() end } } }):Open()
```

### Tooltips

Any frame: `theme:SetTip(frame, "Title", "Body with a |cffffffffhighlighted|r word")` -
`|cffffffff…|r` becomes the live accent color. For multi-line, colored tooltips:

```lua
theme:SetTipLines(frame, "Title", {
  "A plain line.",
  { text = "Accent line", color = "accent" },   -- palette key or hex
  { text = "Muted", color = "subtext" },
})
```

`theme:TooltipPreview(parent, { title, lines, width })` renders the same model inline so you
can design tooltip content and see it.

---

## Builder (immediate-mode layout)

Lays widgets out by `(x, y)` offsets from a scroll content frame's TOPLEFT (`y` grows
downward as negatives) and **pools** simple widgets, so you can redraw a page every keystroke
cheaply. Rich components are drawn transiently (hidden on `:Reset()`).

```lua
local b = theme:Builder(contentFrame, { contentWidth = 660 })
local function render()
  b:Reset()
  local x, y = 24, -20
  b:Heading("Settings", x, y, "h1");                    y = y - 34
  y = b:Section("GENERAL", x, y);                       y = y - 34   -- Section adds a top margin; use its return
  b:Toggle(x, y, db.enabled, function(v) db.enabled = v end)
  b:Label("Enable addon", x + 46, y - 2, theme.C.text); y = y - 40
  b:ProgressBar(x, y, { width = 300, value = 62, showText = true }); y = y - 28
  b:SocialBar(x, y, { { brand = "discord", url = "…" } }, { iconOnly = true })
  contentFrame:SetHeight(math.max(400, -y + 20))
end
```

Builder methods: `Reset`, `Label`, `Wrap`, `Heading`, `Section`, `Sub`, `Toggle`, `Button`,
`Dropdown`, `EditBox`, `Slider`, `Icon`, `Swatch`, `Logo`, `Preview`, `Box`, `VRule`,
`ProgressBar`, `Spinner`, `Badge`, `Card`, `StatTile`, `Separator`, `Avatar`, `RadioGroup`,
`SegmentedControl`, `Stepper`, `SearchBox`, `TextArea`, `TabBar`, `Accordion`,
`SocialButton`, `SocialBar`, `Glyph`, `RangeSlider`, `ComboBox`, `FontSelect`,
`TooltipPreview`. Chaining widgets return the widget; anything returned works with
`theme:SetTip(...)`.

---

## Window shell

A movable, self-skinned application window: header (drag + logo + title + close), a left
sidebar of icon nav rows, a scroll-clipped content area with a themed scrollbar, and a
footer. Pages render into a pooled Builder.

```lua
local win = theme:Window({
  name = "MyAddonWindow", title = "My Addon", logo = "Interface\\AddOns\\MyAddon\\logo.tga",
  width = 920, height = 600, sidebarWidth = 210, contentWidth = 660,
  savedPos  = db.windowPos, onMovePos = function(p) db.windowPos = p end,
  pages = {
    { header = "General" },                                        -- a sidebar CATEGORY label
    { view = "home", label = "Home", icon = "...\\home.tga",
      render = function(b, win) ...; return finalY end },          -- return last y → sizes scroll child
    { view = "edit", label = "Editor", icon = "...", subViews = { "row" } },
  },
  footer = { left = "My Addon", right = "v1.0",
             link = { label = "Discord", url = "https://...", tipBody = "Copy the invite." } },
  sidebarButton = { label = "Do Thing", kind = "primary", onClick = fn, tip = { "Title", "Body" } },
  defaultView = "home",
})
win:Open(view);  win:Toggle();  win:SelectView(v);  win:Refresh();  win:Hide()
```

**Maximize:** pass `maximizable = true` for a header maximize/restore button, plus
`win:Maximize()` / `win:Restore()` / `win:ToggleMaximize()`. Cap the size with `maxWidth` /
`maxHeight` (window-coord px) or `maxWidthPct` / `maxHeightPct` (fraction of the viewport).

**Footer styles:** `footer.style` = `"none"` · `"minimal"` (default) · `"expanded"` (taller,
larger text, an optional `subtitle`, and a row of `socials`). `footer = false` also means none.

```lua
footer = { style = "expanded", left = "My Addon", subtitle = "v2 build", right = "v2.0",
           socials = { { brand = "discord", url = "…" }, { brand = "github", url = "…" } } },
```

A `pages` entry with `header` (and no `view`) becomes a **sidebar category** grouping the rows
under it. Categories are **collapsible** by default (click the header / chevron); pass
`collapsible = false` to keep a plain label, or `collapsed = true` to start collapsed. The nav
area **scrolls with a scrollbar** when it overflows.

```lua
{ header = "Tools", collapsed = true },   -- starts collapsed
{ view = "macros", label = "Macros", ... },
```

---

## Live theming

```lua
theme:ApplyAccent({ 0.13, 0.79, 0.59 })   -- or a hex via UIF.toColor
win:Refresh()                              -- sidebar, buttons, sliders, scrollbar, tooltips all follow
```

The showcase's *Social & Toasts* and *Pickers & Dialogs* pages demonstrate a live accent
swatch and the toasts.

---

## Files

| file | contents |
|------|----------|
| `Core.lua` | namespace, color math, Midnight secret-safety, font probe |
| `Theme.lua` | `NewTheme`, palette, accent, tooltips, `StylePanel`, icon/font resolve |
| `Style.lua` | per-call override system (`StyleFont`/`StyleFrame`/`Panel`, `toColor`) |
| `Fonts.lua` | bundled font registry (`DEFAULT_FONTS`, `FontList`/`FontLabel`) |
| `Sounds.lua` | sound catalog + `PlaySound`, `SoundSelect` (bundled `Sounds/` from TCC) |
| `Skins.lua` | `SKINS` presets (color + shape) + `ApplySkin` |
| `IconManifest.lua` | generated list of bundled icons (from `convert_icons.py`) |
| `Icons.lua` | icon registry (`GetIcon`/`IconPath`/`HasIcon`) + colorable `Glyph` |
| `Menu.lua` | themed dropdown popup (headers, icons, per-row fonts, submenus) |
| `Widgets.lua` | Button (corner radius), Toggle, Dropdown, EditBox, Slider, Icon, Swatch, Logo, Checkbox, Preview, NavRow |
| `Headings.lua` | Heading roles / type scale |
| `Progress.lua` | ProgressBar, Spinner |
| `Forms.lua` | RadioGroup, SegmentedControl, Stepper, SearchBox, TextArea |
| `Selectors.lua` | RangeSlider, ComboBox, FontSelect |
| `Display.lua` | Badge, Card (header/footer/colored), StatTile, Separator, Avatar |
| `Tabs.lua` | TabBar, Accordion |
| `Social.lua` | SocialButton, SocialBar, brand registry |
| `Tooltip.lua` | TooltipPreview + multi-line `SetTipLines` |
| `Game.lua` | Portrait2D, PortraitModel, UnitModel, GameIcon (live game data) |
| `Selectors.lua` | RangeSlider, ComboBox, FontSelect |
| `ColorPicker.lua` / `IconPicker.lua` / `TextDialog.lua` / `KeyCapture.lua` / `Toast.lua` / `Modal.lua` | pickers, dialogs, key capture, toasts, modals |
| `Builder.lua` | pooled immediate-mode content builder |
| `Window.lua` | the application window shell |
| `Showcase.lua` | component gallery + self-test, no slash command (delete to ship lib-only) |
| `assets/` | bundled `icons/` (Tabler outline+filled + socials), `fonts/` (~17 TTF/OTF), `shapes/` (rounded-rect), `scenes/` (model backdrops) |
| `Sounds/` | ~64 bundled `.ogg`/`.mp3` notification sounds (from TCC) |
| `tools/convert_icons.py` · `gen_shapes.py` · `gen_scenes.py` · `ICONS.md` | icon converter, shape + scene generators, icon docs |

---

## Credits

Components extracted from **Twisteds Combat Cues** by *Twistedfury-Zul'jin*. Icons: Tabler
(MIT). Panel layout inspiration: EllesmereUI. No affiliation implied.
