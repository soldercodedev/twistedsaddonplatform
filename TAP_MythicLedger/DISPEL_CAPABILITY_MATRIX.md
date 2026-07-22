# Dispel Capability Matrix - by TYPE/SCHOOL and AXIS

**Purpose.** A due-diligence check that whenever the scoring engine *expects* a spec to dispel
something, that spec can actually remove that **type/school** on that **axis**. This is a
capability reference (spec → school), **not** a spell-by-spell list. Nothing here changes scoring;
it is the ground truth the engine's `Scoring/Capability.lua` records are audited against.

| | |
|---|---|
| **Researched** | 2026-07-21 |
| **Game version** | Midnight 12.x (client interface `120007`) |
| **Code audited** | `TAP_MythicLedger/Scoring/Capability.lua` (`dp(...)` records) |

## Sources (external community references)

- Warcraft Wiki - *Dispel* - <https://warcraft.wiki.gg/wiki/Dispel> (per-class defensive/offensive
  ability list; explicitly states **Paladins cannot remove buffs from enemies**).
- Warcraft Wiki - *Dispel type* - <https://warcraft.wiki.gg/wiki/Dispel_type> (which classes remove
  each school; offensive Magic = Hunter/Shaman/Warlock/Mage/Priest/DH; no Paladin).
- Wowpedia - *Dispel* / *Dispel type* (corroborating type→class mapping).
- Companion internal doc: [CLASS_UTILITY_RESEARCH.md](CLASS_UTILITY_RESEARCH.md) (interrupt + dispel
  table, spell IDs).

**Axes.** *Defensive cleanse* = remove a **debuff from a friendly**. *Offensive* = **purge** a buff
off an enemy (Magic) or **soothe** an **Enrage**. A spec is only fairly expected to address a school
on an axis it actually has a tool for.

---

## Defensive cleanse - which SCHOOL each spec can remove from a friendly

✓ = capable · - = cannot · (t) = talent-gated (only expected when the engine confirms the talent or
the player actually dispelled). Matches `dispel.defensive` in `Capability.lua`.

| Class | Spec | Magic | Curse | Poison | Disease | Ability | Code ✓? |
|---|---|:--:|:--:|:--:|:--:|---|:--:|
| Death Knight | all | - | - | - | - | none | ✓ |
| Demon Hunter | all | - | - | - | - | none (Consume Magic is offensive) | ✓ |
| Druid | Balance/Feral/Guardian | - | ✓(t) | ✓(t) | - | Remove Corruption | ✓ |
| Druid | Restoration | ✓ | ✓ | ✓ | - | Nature's Cure | ✓ |
| Evoker | Devastation/Aug | - | ✓(t) | ✓ | ✓(t) | Cauterizing Flame (+Expunge=Poison) | ⚠ see note E1/E2 |
| Evoker | Preservation | ✓ | - | ✓ | - | Naturalize | ✓ |
| Hunter | all | - | - | - | - | none (Tranq is offensive) | ✓ |
| Mage | all | - | ✓(t) | - | - | Remove Curse | ✓ |
| Monk | Brewmaster/Windwalker | - | - | ✓(t) | ✓(t) | Detox | ✓ |
| Monk | Mistweaver | ✓ | - | ✓ | ✓ | Detox | ✓ |
| **Paladin** | **Holy** | ✓ | - | ✓ | ✓ | Cleanse | ✓ |
| Paladin | Prot/Ret | - | - | ✓(t) | ✓(t) | Cleanse Toxins | ✓ |
| Priest | Disc/Holy | ✓ | - | - | ✓ | Purify (+Mass Dispel) | ✓ |
| Priest | Shadow | - | - | - | ✓(t) | Purify Disease | ✓ |
| Rogue | all | - | - | - | - | none | ✓ |
| Shaman | Ele/Enh | - | ✓(t) | - | - | Cleanse Spirit | ✓ |
| Shaman | Restoration | ✓ | ✓ | - | - | Purify Spirit | ✓ |
| Warlock | all | ✓(t) | - | - | - | Singe Magic (Imp) | ✓ |
| Warrior | all | - | - | - | - | none | ✓ |

## Offensive - Magic PURGE and Enrage SOOTHE (remove from an ENEMY)

| Class | Magic purge | Enrage soothe | Ability | Code ✓? |
|---|:--:|:--:|---|:--:|
| Death Knight | - | - | none | ✓ |
| Demon Hunter | ✓ | - | Consume Magic | ✓ |
| Druid | - | ✓ | Soothe (all specs, baseline) | ✓ (Resto added v39 - see D1) |
| Evoker | - | ✓(t) | Oppressing Roar + Overawe | ⚠ E3 - not modeled (niche) |
| Hunter | ✓ | ✓ | Tranquilizing Shot | ✓ |
| Mage | ✓ | - | Spellsteal | ✓ |
| **Paladin** | **-** | **-** | **none - cannot purge or soothe** | ✓ |
| Priest | ✓ | - | Dispel Magic (+Mass Dispel) | ✓ |
| Rogue | - | ✓ | Shiv | ✓ |
| Shaman | ✓ | - | Purge | ✓ |
| Warlock | ✓ | - | Devour Magic (Felhunter) | ✓ |
| Warrior | - | - | none (Shattering Throw ≠ purge) | ✓ |

> **Headline (the Skyreach question):** No Paladin - Holy included - has an offensive Magic purge or
> an Enrage soothe. Confirmed by all three external sources. The engine already encodes Holy Paladin
> `offensive = {}`, so it is **never** expected to purge Skyreach's enemy Magic buffs
> (Solar Barrier) or soothe its Enrages (Rushing Winds). The capability table is correct here.

---

## Discrepancies found (code vs. sources) - candidates, no change made yet

- **D1 - Restoration Druid missing Soothe (offensive Enrage). [FIXED v39]** All druids have Soothe
  (baseline), and [CLASS_UTILITY_RESEARCH.md](CLASS_UTILITY_RESEARCH.md) lists it, but `Capability.lua`
  gave Balance/Feral/Guardian `offensive = { enrage }` while Restoration was `offensive = {}`. Now set
  to `{ enrage }` so a Resto druid is credited for soothing Skyreach-type enrages.
- **E1 - Evoker Poison cleanse is partly baseline (Expunge), coded as fully talent-gated.**
  Cauterizing Flame (the talent) covers Curse/Disease/Poison; Expunge (Poison) is baseline. Coding
  the whole record `talentDependent` can under-expect an evoker's Poison cleanse. Minor.
- **E2 - Cauterizing Flame also clears Bleed** (per Warcraft Wiki); the code omits Bleed. Bleeds are
  rarely a tracked dispel school, so negligible.
- **E3 - Evoker Oppressing Roar (Overawe) enrage soothe** not modeled. Niche talent; leave.
- **P1 - Doc note "Prot Paladin: Shield Slam purge" is spurious.** Shield Slam is a *Warrior*
  ability, and even the Prot-Warrior purge is legacy/situational. The **code is correct** (all
  Paladins and Warriors have no purge); only the note in the companion doc is misleading.

**Net:** the capability table is accurate for scoring purposes. The only worth-considering code edit
is **D1 (Resto Druid Soothe)**; the rest err safely toward N/A.

## How scoring consumes this (for context)

`Scoring/Distribute.lua` builds a **per-(axis, school) supply** from the season profile -
`partyDebuffFrequencies` feeds the *defensive* schools, `targetBuffFrequencies` feeds *offensive*
(`purge` → Magic, `enrage` → Soothe) - and splits each school's supply **only among members whose
`defensive`/`offensive` table covers that school**. So a correct matrix here is what keeps a
purge-less Holy Paladin out of an offensive-Magic expectation. See the run-log finding that the
**Skyreach healer dispel-0 problem is a season-data (defensive/offensive split) issue, not a
capability error** - recorded in [SCORING_TUNING_IDEAS.md](SCORING_TUNING_IDEAS.md).
