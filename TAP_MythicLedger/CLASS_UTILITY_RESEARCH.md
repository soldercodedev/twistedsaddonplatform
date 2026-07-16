# Class Utility Research — TAP: Mythic Ledger scoring

| | |
|---|---|
| **Date researched** | 2026-07-15 |
| **Game version** | Midnight, patch 12.1 (client interface 120007 = 12.0.7 base) |
| **Expansion / Season** | Midnight, Mythic+ Season 2 |
| **Last verified** | 2026-07-15 |

## Sources

- Warcraft Wiki — *Interrupt* — <https://warcraft.wiki.gg/wiki/Interrupt> (cooldowns, ranges, which
  specs lack an interrupt)
- Warcraft Wiki — *Dispel* / *Dispel type* — <https://warcraft.wiki.gg/wiki/Dispel> (dispel access,
  types, defensive vs offensive)
- Wowpedia — *List of interrupts by class specializations* — <https://wowpedia.fandom.com/wiki/List_of_interrupts_by_class_specializations>
- Midnight 12.1 Season-2 notes (Icy Veins, Conquest Capped): interrupts retained across classes; PvE
  interrupt **lockouts lengthened** this season (cooldowns essentially unchanged).

## Confidence & verification notes

- **Interrupt/dispel access, cooldowns, and ranges: HIGH confidence** — confirmed against the two wikis
  above for the current live game, and these are among the most stable elements of class design.
- **Spell IDs: HIGH confidence** — long-standing live IDs; still flagged `verify` in
  `Scoring/Capability.lua` in case Midnight re-issued any ID. A mismatch changes nothing in scoring
  (we score on the profile/rate, not the ID) but should be corrected for the audit trail.
- **Talent dependency** noted where an interrupt/dispel requires a pet or talent (Warlock Spell Lock,
  Shaman Purify Spirit/Cleanse Spirit, Evoker Expunge, Warlock Singe Magic).
- Uncertain/edge items are marked ⚠ in the notes column.

Legend — Interrupt profile: `NONE / LONG_CD / STANDARD / SHORT_CD / HIGH_CONTROL`. Dispel profile:
`NONE / LIMITED / STANDARD / HIGH_UTILITY`. Range: M = melee, R = ranged.

## Interrupts

| Class | Spec | Role | Interrupt | ID | CD | Rng | Talent? | Profile | Additional stops / notes |
|---|---|---|---|---:|---:|:--:|:--:|---|---|
| Death Knight | Blood | Tank | Mind Freeze | 47528 | 15 | R(15y) | no | STANDARD | Asphyxiate (stun) situational |
| Death Knight | Frost | DPS | Mind Freeze | 47528 | 15 | R | no | STANDARD | |
| Death Knight | Unholy | DPS | Mind Freeze | 47528 | 15 | R | no | STANDARD | |
| Demon Hunter | Havoc | DPS | Disrupt | 183752 | 15 | M | no | STANDARD | Consume Magic can stop a cast ⚠ |
| Demon Hunter | Vengeance | Tank | Disrupt | 183752 | 15 | M | no | **HIGH_CONTROL** | + Sigil of Silence (202137, AoE silence) |
| Druid | Balance | DPS | Solar Beam | 78675 | 60 | R | no | LONG_CD | AoE silence; only Balance's stop |
| Druid | Feral | DPS | Skull Bash | 106839 | 15 | M | no | STANDARD | requires Cat form |
| Druid | Guardian | Tank | Skull Bash | 106839 | 15 | M | no | STANDARD | requires Bear form; Incapacitating Roar |
| Druid | Restoration | Healer | — | — | — | — | — | **NONE** | no Skull Bash out of form, no Solar Beam |
| Evoker | Devastation | DPS | Quell | 351338 | 40 | R | no | LONG_CD | |
| Evoker | Preservation | Healer | — | — | — | — | — | **NONE** | lost Quell in Midnight (healer interrupt removal) |
| Evoker | Augmentation | DPS | Quell | 351338 | 40 | R | no | LONG_CD | |
| Hunter | Beast Mastery | DPS | Counter Shot | 147362 | 24 | R | no | LONG_CD | |
| Hunter | Marksmanship | DPS | Counter Shot | 147362 | 24 | R | no | LONG_CD | |
| Hunter | Survival | DPS | Muzzle | 187707 | 15 | M | no | STANDARD | melee-range interrupt |
| Mage | Arcane | DPS | Counterspell | 2139 | 24 | R | no | LONG_CD | also silences |
| Mage | Fire | DPS | Counterspell | 2139 | 24 | R | no | LONG_CD | |
| Mage | Frost | DPS | Counterspell | 2139 | 24 | R | no | LONG_CD | Ring of Frost (incap) |
| Monk | Brewmaster | Tank | Spear Hand Strike | 116705 | 15 | M | no | STANDARD | Leg Sweep / Ring of Peace |
| Monk | Windwalker | DPS | Spear Hand Strike | 116705 | 15 | M | no | STANDARD | Leg Sweep |
| Monk | Mistweaver | Healer | — | — | — | — | — | **NONE** | lost Spear Hand Strike in Midnight (healer interrupt removal) |
| Paladin | Holy | Healer | — | — | — | — | — | **NONE** | lost Rebuke in Midnight (healer interrupt removal); Hammer of Justice (stun) remains |
| Paladin | Protection | Tank | Rebuke | 96231 | 15 | M | no | **HIGH_CONTROL** | + Avenger's Shield (31935, ranged silence, ~15s, rotational) |
| Paladin | Retribution | DPS | Rebuke | 96231 | 15 | M | no | STANDARD | |
| Priest | Discipline | Healer | — | — | — | — | — | **NONE** | no conventional interrupt |
| Priest | Holy | Healer | — | — | — | — | — | **NONE** | no conventional interrupt |
| Priest | Shadow | DPS | Silence | 15487 | 45 | R | no | LONG_CD | non-player targets; Psychic Horror ⚠ |
| Rogue | Assassination | DPS | Kick | 1766 | 15 | M | no | STANDARD | Kidney/Cheap Shot situational |
| Rogue | Outlaw | DPS | Kick | 1766 | 15 | M | no | STANDARD | |
| Rogue | Subtlety | DPS | Kick | 1766 | 15 | M | no | STANDARD | |
| Shaman | Elemental | DPS | Wind Shear | 57994 | 12 | R(30y) | no | **SHORT_CD** | |
| Shaman | Enhancement | DPS | Wind Shear | 57994 | 12 | R | no | **SHORT_CD** | |
| Shaman | Restoration | Healer | Wind Shear | 57994 | 30 | R | no | **LONG_CD** | ONLY healer that kept an interrupt in Midnight, but CD slowed 12s→30s |
| Warlock | Affliction | DPS | Spell Lock | 19647 | 24 | R | **pet** | LONG_CD | Felhunter; Axe Toss via Felguard ⚠ |
| Warlock | Demonology | DPS | Spell Lock | 19647 | 24 | R | **pet** | LONG_CD | Felguard → Axe Toss (stun) alt |
| Warlock | Destruction | DPS | Spell Lock | 19647 | 24 | R | **pet** | LONG_CD | |
| Warrior | Arms | DPS | Pummel | 6552 | 14 | M | no | STANDARD | 14s w/ Honed Reflexes (15s base); Storm Bolt (talent) |
| Warrior | Fury | DPS | Pummel | 6552 | 14 | M | no | STANDARD | 14s w/ Honed Reflexes (15s base) |
| Warrior | Protection | Tank | Pummel | 6552 | 14 | M | no | STANDARD | + Disrupting Shout (386071, 90s AoE **interrupt**); Shockwave (46968, AoE **stun**, not an interrupt) |

## Dispels

| Class | Spec | Defensive dispel (types) | ID | Offensive / purge | Soothe? | Profile | Talent? |
|---|---|---|---:|---|:--:|---|:--:|
| Death Knight | all | — | — | — | no | NONE | — |
| Demon Hunter | all | — | — | Consume Magic (Magic) | no | LIMITED | no |
| Druid | Balance/Feral/Guardian | Remove Corruption (Curse, Poison) | 2782 | — | Soothe (2908) | LIMITED | no |
| Druid | Restoration | Nature's Cure (Magic, Curse, Poison) | 88423 | — | Soothe | STANDARD | no |
| Evoker | Devastation/Augmentation | Cauterizing Flame (Curse, Disease, Poison) | 374251 | — | Oppressing Roar (Overawe) ⚠ | LIMITED | Expunge=talent |
| Evoker | Preservation | Naturalize (Magic, Poison) | 360823 | — | — | STANDARD | no |
| Hunter | all | — | — | Tranquilizing Shot (Magic, Enrage) | yes | LIMITED | no |
| Mage | all | Remove Curse (Curse) | 475 | Spellsteal (Magic) | no | LIMITED | no |
| Monk | Brewmaster/Windwalker | Detox (Disease, Poison) | 218164 | — | — | LIMITED | no |
| Monk | Mistweaver | Detox (Disease, **Magic**, Poison) | 218164 | — | — | STANDARD | no |
| Paladin | Holy | Cleanse (Magic, Disease, Poison) | 4987 | — | no | STANDARD | no |
| Paladin | Protection/Retribution | Cleanse Toxins (Disease, Poison) | 213644 | — (Prot: Shield Slam purge) | no | LIMITED | no |
| Priest | Discipline/Holy | Purify (Magic, Disease) + Mass Dispel (32375) | 527 | Dispel Magic (Magic) | no | HIGH_UTILITY | no |
| Priest | Shadow | Purify Disease (Disease) | 213634 | Dispel Magic; Mass Dispel | no | LIMITED | no |
| Rogue | all | — | — | Shiv (5938, Enrage) | via Shiv | LIMITED | no |
| Shaman | Elemental/Enhancement | Cleanse Spirit (Curse) | 51886 | Purge (Magic) | no | LIMITED | Cleanse Spirit=talent |
| Shaman | Restoration | Purify Spirit (Magic, Curse) | 77130 | Purge | no | STANDARD | no |
| Warlock | all | Singe Magic (Magic, Imp) | 89808 | Devour Magic (Magic, Felhunter) | no | LIMITED | **pet/talent** |
| Warrior | Arms/Fury | — | — | — | no | NONE | — |
| Warrior | Protection | — | — | — (Warriors cannot dispel/purge) | no | NONE | no |

## Open items to re-verify for 12.x

- Confirm every **spell ID** against the live 12.1 spell database (flagged `verify = true` in code).
- **Applied (Midnight):** interrupts REMOVED from all healers except Restoration Shaman (whose Wind
  Shear went 12s→30s → LONG_CD). Preservation Evoker / Mistweaver Monk / Holy Paladin now `NONE`.
  Non-healer cooldowns held (lockouts lengthened, e.g. Pummel 5s). Pummel listed at 14s (Honed
  Reflexes; 15s base). Prot Warrior gains Disrupting Shout (90s AoE interrupt) alongside Shockwave.
- Decide whether **Brewmaster Monk / Prot Warrior** should be promoted to `HIGH_CONTROL` given their
  rotational AoE stops (Leg Sweep / Shockwave) — currently `STANDARD` (conservative). Prot Warrior's
  Disrupting Shout is a 90s AoE interrupt (LOW rotational likelihood), so it stays `STANDARD`.
- Warlock interrupt is **pet-dependent** (Felhunter Spell Lock vs Felguard Axe Toss); treated as one
  `LONG_CD` profile with `talentDependent = true`.
