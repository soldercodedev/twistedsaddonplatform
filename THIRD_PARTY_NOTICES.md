# Third-Party Notices

The **Twisteds Addon Platform** ("the addon") is an add-on for **World of Warcraft**. Its own
source code and original artwork are licensed under the **GNU General Public License, version 2**
(see `LICENSE`). This file credits the third-party material bundled with, or used by, the addon.
The addon's license does not extend to any of it, and no ownership is claimed over Blizzard
Entertainment assets or any third-party file.

The platform ships as one download containing several add-on folders (`TAP`, `TAP_CombatAlerts`,
`TAP_FocusInterrupt`, `TAP_RotationAssistant`, `TAP_GameDB`). Shared assets - the icon set, fonts,
and sounds - live in the parent `TAP` folder; the search databases live in `TAP_GameDB`.

---

## Blizzard Entertainment, Inc.

World of Warcraft, its game client and APIs, and all in-game names, icons, spell and item artwork,
textures, built-in fonts (`FRIZQT__`, `SKURRI`, `MORPHEUS`), sound kits, and the raid-target
("target marker") icon textures are the property of **Blizzard Entertainment, Inc.** The addon
references these through the game client and does not bundle or redistribute them. Spell/item
**names and IDs** in the bundled search databases are Blizzard game data. This project is not
affiliated with or endorsed by Blizzard Entertainment.

## Tabler Icons

The interface icons in `TAP/assets/icons/*.tga` are converted from **Tabler Icons**
(<https://tabler.io/icons>), licensed under the **MIT License**:

> Copyright (c) 2020-2024 Paweł Kuna
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software
> and associated documentation files (the "Software"), to deal in the Software without restriction
> ... (standard MIT terms).

## Fonts (`TAP/assets/fonts/`)

Bundled for the on-screen-text font picker.

- **Open Font License / Ubuntu Font Licence** (full license texts included in
  `TAP/assets/fonts/LICENSES/`, one per family): Fira Sans, Poppins, Barlow Condensed, Changa,
  Cinzel Decorative, Exo, and Russo One (SIL OFL 1.1); Ubuntu (Ubuntu Font Licence 1.0).
- Other bundled fonts (`Expressway`, `Future X Black`, `Homespun`, `KMT`) are from various
  community font sources and remain under their respective authors' terms.

## Sounds (`TAP/Sounds/`)

Community-sourced cue sounds. Several are by **Piffz**, a well-known World of Warcraft community
sound author. `DoubleWhoosh.ogg` is public domain (qubodup / Iwan Gabovitch). The remainder are
from assorted community and free-sound sources. Each file remains under its respective author's
terms.

## wago.tools

The bundled search databases (`TAP_GameDB/SpellDB.lua`, `TAP_GameDB/ItemDB.lua`) are generated
offline from DB2 CSV exports provided by **wago.tools** (<https://wago.tools>); the underlying data
is Blizzard game data.

## WeakAuras

Credited as **inspiration only**. This addon is not derived from WeakAuras source code and includes
no WeakAuras code.

---

*If you are a rights holder for any bundled material and believe it is included in error, please
contact the addon author and it will be removed.*
