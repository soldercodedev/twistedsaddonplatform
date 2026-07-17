# TAP: Mythic Ledger — Player Scoring System

*Scoring engine version 1. Source of truth for all constants: `Scoring/Config.lua`. This document
explains the system in plain language; every formula and default below is mirrored in code.*

---

## 1. Purpose of the score

Give each player in a Mythic+ group a single, **explainable** 0–100 score (plus a letter grade) that
reflects **throughput, utility contribution, survival, death impact, and role-specific performance** —
*not* raw DPS — so runs can be compared fairly over time. Every number is auditable: the UI can show
exactly what produced it.

## 2. Data used (what the addon actually has)

In **Midnight (12.x)** the combat log is forbidden to addons; all stats come from **`C_DamageMeter`**
(Overall session) — see `Providers.lua`. Per player, each of these may be present or `nil`
(unavailable — **never** treated as 0): `damageDone, dps, damageTaken, avoidableDamageTaken, absorbs,
healing, hps, overhealing, interrupts, dispels, deaths`, plus `role / classId / specId` and run
`duration / level / mapId / seasonId`.

## 3. Data NOT available

No interruptible-cast counts, priority casts, missed/assigned/overlapped interrupts, interrupt
availability at cast time, stop intent, whether a rotational ability incidentally interrupted, death
cause, required vs avoidable healing, effective vs overhealing detail, or defensive usage. `activeSeconds`
is not stored (we estimate it as `damageDone / dps` where needed, flagged as an estimate).
`crowdControls` is declared but not populated by the meter reader.

## 4. Why raw interrupt totals are unfair

Interrupt cooldowns and kits differ enormously (DPS Wind Shear 12 s vs Counterspell/Counter Shot 24 s
vs Solar Beam 60 s; and in **Midnight all healers lost their interrupt except Resto Shaman**, whose Wind
Shear was raised to 30 s). Raw counts also
depend on how many interruptible casts a dungeon offered and how the group divided them — none of which
we can measure. So we score **Interrupt _Contribution_** against a **spec-specific expectation**, never
accuracy, skill, or missed-kick responsibility, and **never** as a share of the group's total (a
Protection Paladin's 14 kicks must not inflate anyone else's expectation).

## 5. How class/spec capabilities are researched

`Scoring/Capability.lua` holds a profile per specialization: the conventional interrupt (spell, ID, CD,
range), extra silences/stops, and dispel access (types, defensive/offensive). Sourced from
`warcraft.wiki.gg` Interrupt & Dispel pages, cross-checked against Midnight 12.1 Season-2 notes (see
`CLASS_UTILITY_RESEARCH.md`). Each record carries a `confidence` and a `verify` flag so a 12.x spell-ID
audit is a one-line data edit. Profiles are **spec-level**, not class-level, so BM/MM Hunter (Counter
Shot, 24 s) differs from Survival (Muzzle, 15 s), Balance Druid (Solar Beam) from Resto (none), etc.

## 6. Interrupt profile definitions

| Profile | Meaning | rate/min |
|---|---|---:|
| `NONE` | No conventional interrupt (not scored) | 0.00 |
| `LONG_CD` | ~24–60 s ranged (Counterspell, Counter Shot, Quell, Solar Beam) | 0.18 |
| `STANDARD` | ~15 s single interrupt (Kick, Pummel, Rebuke, Mind Freeze, Muzzle, Spear Hand) | 0.30 |
| `SHORT_CD` | ≤12 s (Wind Shear) | 0.40 |
| `HIGH_CONTROL` | 15 s interrupt **plus** a strong ranged stop/silence used rotationally (Prot Paladin, Vengeance DH) | 0.48 |

Dispel profiles (`NONE` 0.00, `LIMITED` 0.10, `STANDARD` 0.22, `HIGH_UTILITY` 0.30) work the same way,
but are **applied to healers only** — see §12.

## 7. Expected interrupt calculation

```
expected_interrupts = duration_minutes × spec_rate_per_minute × composition_modifier
```

Rates are **contribution** rates (a run rarely offers a kick every cooldown), deliberately conservative.

## 8. Group composition modifier

A small, bounded nudge (clamped **0.85–1.15**). Each **other** interrupt-capable player lowers your
expectation slightly (−0.03), each other short-CD/high-control kicker a bit more (−0.02), each **other**
high-control teammate −0.05 (they soak casts). If you're the **only** interrupter, +0.10. It can only
lower or hold your expectation vs a teammate's tools — never raise it, and it never touches another
player's score directly.

## 9. Confidence calculation

If a run didn't record enough total activity to grade confidently, blend toward a **neutral** score:

```
confidence            = clamp(group_total_interrupts / min_sample, 0, 1)     [min_sample = 15]
final_interrupt_score = neutral + (calculated − neutral) × confidence         [neutral = 75]
```

Neutral is **75** (a low-B): absence of evidence should read as "unremarkable," not "bad." Dispels use
neutral 70, min_sample 8.

## 10. Diminishing returns

Contribution uses a concave curve (interpolated), so reaching expectation is rewarded and overshoot
barely moves the needle — an outlier interrupt total can't dominate:

| ratio (actual/expected) | 0.00 | 0.25 | 0.50 | 0.75 | 1.00 | 1.25 | 2.00 |
|---|---:|---:|---:|---:|---:|---:|---:|
| score | 0 | 35 | 60 | 80 | 95 | 100 | 110* |

*Internal ceiling 110; the **category** handed to the weighted sum is always capped at **100**.

## 11. Specs without interrupts

`NONE` specs are marked **N/A** (never 0). The interrupt weight is **redistributed deterministically**
(`Scoring/Weights.lua` + `Config.redistribution`): since interrupts + dispels are one 25% budget, an
interrupt N/A moves its full share to **dispels** (the bucket stays 25%); only if the spec also can't
dispel does the 25% leave the bucket. The UI shows `Interrupt Contribution: N/A` and states where the
weight went.

## 12. Dispel scoring

Same model as interrupts (spec dispel rate → expected → curve → confidence), labelled **Dispel
Contribution**, and scored for **any spec that actually has a dispel tool** — DPS and tanks included.
Research (warcraft.wiki.gg/Dispel; Wowhead "Important Dispels in Midnight Season 1 Mythic+") confirms
non-healers dispel in M+ all the time: Hunter Tranquilizing Shot, Druid/Rogue enrage soothes, Mage
Spellsteal, Shaman Purge, DH Consume Magic, Warlock Devour Magic, plus narrow single-type cures. The
**profile encodes the expectation gap**: healers carry the full defensive party cleanse — Priest
(Disc/Holy) = `HIGH_UTILITY`, Resto Druid / Preservation Evoker / Mistweaver / Holy Paladin / Resto
Shaman = `STANDARD` — while dispel-capable DPS & tanks get the low-expectation `LIMITED`. Only **Warrior
and Death Knight** (no dispel of any kind) are `NONE`, and their weight is redistributed.

Fairness comes from the **confidence blend + composition modifier**, not from denying credit: in a run
with little/no dispellable content the group total is low, so a spec that dispelled nothing is pulled
toward the neutral score (70) rather than punished, and a healer / extra dispeller present lowers
everyone else's expected count. Because we only have aggregate `C_DamageMeter` dispel **counts** (no
combat log in Midnight), this is a **volume** contribution, never a "you missed the priority dispel"
judgement.

## 13. Throughput scoring by role

Scored as `value / baseline` through a gentle curve (`1.00× ≈ 86`, strong overshoot capped at 100 so
DPS can't dominate). **DPS/Tank** use `dps`, **Healers** use `hps` with a **soft cap** above 1.10×
baseline (excess healing usually means the group ate avoidable damage — penalized under survival, not
rewarded here). Baselines blend **static role references → learned same-spec historical medians** as
data accumulates — now **wired** to your own run history (`Scoring/Learned.lua`, §18).

## 14. Survival and avoidable damage

The **scale-invariant avoidable share** (`avoidableDamageTaken / damageTaken`) is the primary signal —
it's independent of key level, health pools, and dungeon, so it's the only survival metric calibratable
without data. An absolute avoidable-per-minute curve is a secondary, deliberately forgiving sanity
signal (its thresholds await learned percentiles). Weights favour share (DPS/Healer 65/35, Tank 70/30);
tanks are normalized separately and high total damage taken is **not** treated as bad.

## 15. Death penalties

**Death Impact** (not responsibility). Escalating and capped: 1st −8, 2nd −12, 3rd −16, 4th −20, 5th+
−20 each, **max −40**. Score = 100 − penalty. Missing death data → neutral 100 (never a fabricated
penalty). We never claim the dead player *caused* the death.

**On the avoidable-damage ↔ death overlap:** these two categories can penalise the *same* moment (you
stood in something bad, took big avoidable damage, and died from it). That double-hit is **intentional,
not a bug** — standing in avoidable damage and dying to it *should* cost you on both survival and death
impact; they measure different things (how much bad stuff you ate vs the run-cost of the death) and both
are legitimately worse. We can't link a specific avoidable hit to a specific death without a combat log,
and we wouldn't want to cancel the overlap even if we could.

## 16. Weight redistribution

Interrupts and dispels share one **25% utility budget**. When **one** utility category is N/A its whole
weight moves to the **other** utility category, so the bucket stays 25% on whichever applies. When
**both** are N/A the combined 25% uses the `utilityBoth` split (evenly to throughput + survival). The
result **always sums to 1.0** (validated + unit-tested), and nothing is silently renormalized.

> The worked examples in §22 below predate v20 (they use the old per-role weights and redistribution);
> the mechanics they illustrate still hold, but the specific weight numbers do not.

## 17. Category weights (static, uniform across roles — v20)

| Role | Throughput | Interrupts | Dispels | Survival | Deaths | Role Contribution |
|---|---:|---:|---:|---:|---:|---:|
| DPS | 35% | 12.5% | 12.5% | 20% | 20% | 0% |
| Tank | 35% | 12.5% | 12.5% | 20% | 20% | 0% |
| Healer | 35% | 12.5% | 12.5% | 20% | 20% | 0% |

Interrupts + Dispels form a single **25% utility budget**, split evenly when both apply. When only one
applies, the other's share moves to it (the bucket stays 25%); when neither applies, the 25% goes to
throughput + survival (§16). Survival and Death Impact are always **exactly equal**. Role Contribution is
retired to **0 weight** — its inputs can be reintroduced via target knobs later without changing these
weights. Configurable in `Config.roleWeights`.

## 18. Historical calibration / 19. Static vs learned baselines

**Mode 1 (static):** rough role references from `Config.throughput.staticReference`. **Mode 2 (learned,
now implemented in `Scoring/Learned.lua`):** the median of your saved runs for the same spec, bucketed
**most-specific-first** — `spec + metric + season + key-bracket` → `spec + metric + season` →
`spec + metric` (all seasons). We use the most specific bucket with ≥ `minBucketSamples` (3) samples;
the blend then scales trust by that bucket's count. Transition is **blended**, never abrupt:

```
learned_confidence = clamp(sample_count / 20)
final_baseline     = static × (1 − learned_confidence) + learned_median × learned_confidence
```

Medians (not averages) reduce outlier distortion; p25/p75 are stored per bucket for future percentile
bands. The learned median is served through the `Scoring.GetLearnedMedian` hook (so the engine stays
DB-agnostic); the cache rebuilds lazily and is invalidated when the run set changes (new run / rebuild).
`dungeon (mapId)` and `duration-bracket` dimensions are collected in the query and can be folded into the
bucket key as data density grows.

## 20. Score versioning & retroactive recalculation

Every score stores `version = Config.version`; raw run stats are preserved, so scores are always
recomputable. Scores are served through **`Scoring/Store.lua`**, which memoises the full result per run,
persists a **compact per-run summary** (`{guid → overall, grade}`) in the derived `summaryCache`, and
exposes **`Scoring.RescoreAll()`** — the migration path that recomputes every saved run with the current
logic. On login, `Store.EnsureCurrent()` auto-runs `RescoreAll` **only if** the stored score version is
stale (a no-op otherwise); there's also a **Debug → "Rescore all runs"** button. So a scoring-logic
change (bump `Config.version`) applies retroactively to your whole history without ever touching raw
data. A single new run only invalidates the learned-median cache (cheap); it doesn't force a full
rescore until a version bump or an explicit `RescoreAll`.

## 21. Grade calculation

`S 97 · A+ 93 · A 89 · A- 85 · B+ 80 · B 75 · B- 70 · C+ 65 · C 60 · D 50 · F <50` (configurable).
The grade never replaces the category breakdown.

## 22. Worked examples

All numbers below are produced by the actual engine (`Scoring/Tests.lua` worked run: ~31.4 min, +12;
group = Fury, Prot Paladin, BM Hunter, Holy Priest, Resto Druid; group interrupt total = 25).

### Fury Warrior (STANDARD interrupt, no dispel)
```
duration = 1884 s = 31.4 min
Interrupt: rate 0.30/min. Composition: 2 other interrupters (−0.06), 1 other high-control kicker (−0.02),
           1 high-control tank (−0.05) → modifier 1.00 − 0.13 = 0.87
  expected = 31.4 × 0.30 × 0.87 = 8.20
  actual   = 8   → ratio = 8 / 8.20 = 0.976
  curve(0.976): between 0.75→80 and 1.00→95 → 80 + 15×((0.976−0.75)/0.25) = 93.6
  confidence = clamp(25/15) = 1.0 → final = 75 + (93.6−75)×1.0 = 93.6 ≈ 94
Dispel: NONE → N/A (Warriors can't dispel). Dispel weight (0.12) redistributed (DPS: 40% throughput,
        30% survival, 30% interrupts) → throughput 0.318, interrupts 0.216, survival 0.286, deaths 0.18
Throughput: 980K / 900K = 1.09× → 91.   Survival: 6M avoidable / 41M taken = 14.6% share → 76.
Deaths: 1 → −8 → 92
Overall = 0.318×91 + 0.216×94 + 0.286×76 + 0.18×92 = 88  → A−
```

### Protection Paladin (HIGH_CONTROL, LIMITED dispel)
```
Interrupt: rate 0.48/min. Comp: 2 other interrupters (−0.06); it IS the high-control kicker/tank so
           those factors exclude itself → modifier 0.94
  expected = 31.4 × 0.48 × 0.94 = 14.2 ;  actual 14 → ratio 0.987 → curve 94 ; confidence 1 → 94
Dispel: LIMITED (Cleanse Toxins, 0.10/min). expected 31.4×0.10×0.89 = 2.8 ; actual 2 → ratio 0.71
        curve(0.71) = 60 + 20×((0.71−0.50)/0.25) = 77 ; confidence 1 → 77  (scored, no redistribution)
Throughput 520K/500K = 1.04 → 88.  Survival: 9M/130M = 6.9% share → 88 (clean).  Deaths 0 → 100.
Role Contribution = mean(survival 88, interrupt 94) ≈ 91
Overall (tank) = 0.16×88 + 0.18×94 + 0.12×77 + 0.30×88 + 0.18×100 + 0.06×91 = 90 → A
```
Note: the 14 interrupts **capped** in-category and, via composition, slightly **lowered** Fury's expected
interrupts — they never raised anyone's expectation or touched anyone's score. The Prot Paladin now gets
modest credit for its two Cleanse Toxins dispels, scored (LIMITED) against a low expectation.

### Hunter (BM — LONG_CD interrupt + LIMITED dispel via Tranquilizing Shot)
```
Interrupt rate 0.18/min (Counter Shot 24 s). expected = 31.4×0.18×0.87 = 4.9 ; actual 3 → ratio 0.61
  curve(0.61): 60 + 20×((0.61−0.50)/0.25) = 68.9 ≈ 69 ; confidence 1 → 69
Dispel rate 0.10/min (LIMITED). expected = 31.4×0.10×1.0 = 3.1 ; actual 2 (Tranq Shots) → ratio 0.65
  curve(0.65): 60 + 20×((0.65−0.50)/0.25) = 72 ; confidence 1 → 72
Throughput 860K/900K = 0.96 → 82.  Survival 12M/34M = 35% share → 51 (sloppy).  Deaths 2 → −20 → 80.
Overall = 0.27×82 + 0.18×69 + 0.12×72 + 0.25×51 + 0.18×80 = 70 → B−  (DPS weights per §17)
```
No redistribution — the Hunter is expected to land a few Tranq Shot dispels, and does.

### Holy Priest (NO interrupt, HIGH_UTILITY dispel)
```
Interrupt: NONE → N/A. Weight 0.15 redistributed (healer rule: 50% dispels, 25% survival, 25% role):
  dispels 0.15+0.075=0.225, survival 0.30+0.0375=0.3375, roleContribution 0.05+0.0375=0.0875
Dispel: expected 31.4×0.30×comp ≈ 9.1 ; actual 7 → ratio 0.77 → ~81 ; confidence 1
Throughput 470K/450K = 1.04 → 88.  Survival 4M/29M = 13.8% share → 80.  Deaths 0 → 100.
Overall = 0.17×88 + 0.225×81 + 0.3375×80 + 0.18×100 + 0.0875×80 = 85 → A−
```
The Priest is **not** penalized for lacking a kick.

### A healer WITH an interrupt (Restoration Shaman)
In Midnight, healers lost their interrupts **except Resto Shaman** (Wind Shear, cooldown raised
12→30 s → `LONG_CD`). So Resto Shaman is the one healer whose interrupt category **applies**: expected
interrupts use the `LONG_CD` rate 0.18/min; if it lands few kicks in a low-interrupt run, confidence
blends the result toward 75 rather than punishing it. Every other healer (Mistweaver, Holy Paladin,
Preservation, Disc/Holy Priest, Resto Druid) is `Interrupt Contribution: N/A` → redistributed.

### A player with no applicable dispel (Frost DK / Fury Warrior)
Warrior and Death Knight are the only classes with no dispel of any kind. Dispel `NONE` →
`Dispel Contribution: N/A`, weight redistributed (DPS: 40% throughput, 30% survival, 30% interrupts).
No zero is ever assigned. (Rogue, by contrast, now scores `LIMITED` — Shiv removes Enrage.)

### A low-confidence run (few total interrupts)
Group interrupt total = 6, min_sample = 15 → confidence = 0.40. A computed interrupt score of 50 becomes
`75 + (50 − 75) × 0.40 = 65` — pulled toward neutral because the run didn't offer enough evidence.

## 23. Known limitations

- Interrupt/dispel scores are **contribution vs expectation**, not correctness — we can't see casts.
- Throughput baselines start static and only become truly fair as your history fills the learned
  buckets (§18); very early on, the static reference dominates.
- Avoidable-damage and death penalties can **overlap on the same moment** — this is **intended**, not a
  flaw (§15): standing in bad stuff and dying to it should cost both.
- Dispels are scored for **any dispel-capable spec** (§12), DPS/tanks included, at a low `LIMITED`
  expectation; only Warrior & Death Knight (no dispel at all) get N/A. It's a volume contribution, so
  in content with nothing to dispel the confidence blend keeps it neutral rather than a penalty.
- `crowdControls` and true `activeSeconds` aren't captured; `activeSeconds` is estimated.
- Spec spell IDs are current-live and flagged `verify` for a 12.x audit.
- Role Contribution is a low-weight composite (no unique data source yet).

## 24. Future improvements

Spell-level interrupt/dispel tracking, interruptible-cast counts, priority/assignment/overlap detection,
CC diminishing returns, defensive/external/battle-res usage, boss-vs-trash damage, effective vs
overhealing, damage prevented, death-cause analysis, route/affix/dungeon-specific benchmarks. The
capability profiles and normalized-input layer are already shaped to accept these.

## 25. All formulas

See §7–§16 and `Scoring/*.lua`. Core:
`overall = Σ (weight_c × min(score_c, 100)) over applicable categories`, weights per §17 (redistributed
when N/A), each category score computed as above.

## 26. Default configuration values

All live in `Scoring/Config.lua`: `roleWeights`, `redistribution`, `interruptProfiles`, `dispelProfiles`,
`contributionCurve`, `confidence` (neutral 75/70, minSample 15/8), `composition` (0.85–1.15 + deltas),
`throughput` (curve + staticReference + healerSoftCapRatio 1.10), `survival` (weights + curves),
`deaths` (8/12/16/20, max 40), `grades`, `learned` (minSamples 20 + brackets), `version`.

## 27. Research sources

- Warcraft Wiki — *Interrupt*: <https://warcraft.wiki.gg/wiki/Interrupt>
- Warcraft Wiki — *Dispel*: <https://warcraft.wiki.gg/wiki/Dispel>
- Wowpedia — *List of interrupts by class specializations*: <https://wowpedia.fandom.com/wiki/List_of_interrupts_by_class_specializations>
- Midnight 12.1 Season-2 class/interrupt notes (Icy Veins, Conquest Capped) — interrupts retained, PvE
  lockouts lengthened.

See `CLASS_UTILITY_RESEARCH.md` for the full per-spec table, dates, and confidence.

## 28. Spec capability profile table (summary)

*Dispel column = the **scored** profile. Every spec with a real dispel/purge/soothe is now scored:
**LIMITED** for the narrow / situational DPS & tank tools (offensive purge, enrage soothe, single-type
cure), **STANDARD / HIGH_UTILITY** for healers' full cleanse. Only **Warrior** and **Death Knight** —
no dispel of any kind — are **NONE**. Fairness comes from the confidence blend + composition modifier,
not from denying credit (see §12). Dispel tool shown in parentheses.*

| Class | Spec | Role | Interrupt (CD) | Interrupt profile | Dispel (scored) |
|---|---|---|---|---|---|
| Death Knight | Blood/Frost/Unholy | T/D/D | Mind Freeze (15) | STANDARD | NONE |
| Demon Hunter | Havoc | DPS | Disrupt (15) | STANDARD | LIMITED (Consume Magic) |
| Demon Hunter | Vengeance | Tank | Disrupt + Sigil of Silence | HIGH_CONTROL | LIMITED (Consume Magic) |
| Druid | Balance | DPS | Solar Beam (60) | LONG_CD | LIMITED (Remove Corruption, Soothe) |
| Druid | Feral/Guardian | D/T | Skull Bash (15) | STANDARD | LIMITED (Remove Corruption, Soothe) |
| Druid | Restoration | Healer | — none — | NONE | STANDARD |
| Evoker | Devastation/Augmentation | DPS | Quell (40) | LONG_CD | LIMITED (Cauterizing Flame) |
| Evoker | Preservation | Healer | — none (Midnight) — | NONE | STANDARD |
| Hunter | Beast Mastery/Marksmanship | DPS | Counter Shot (24) | LONG_CD | LIMITED (Tranquilizing Shot) |
| Hunter | Survival | DPS | Muzzle (15) | STANDARD | LIMITED (Tranquilizing Shot) |
| Mage | Arcane/Fire/Frost | DPS | Counterspell (24) | LONG_CD | LIMITED (Remove Curse, Spellsteal) |
| Monk | Brewmaster/Windwalker | T/D | Spear Hand Strike (15) | STANDARD | LIMITED (Detox) |
| Monk | Mistweaver | Healer | — none (Midnight) — | NONE | STANDARD |
| Paladin | Holy | Healer | — none (Midnight) — | NONE | STANDARD |
| Paladin | Protection | Tank | Rebuke + Avenger's Shield | HIGH_CONTROL | LIMITED (Cleanse Toxins) |
| Paladin | Retribution | DPS | Rebuke (15) | STANDARD | LIMITED (Cleanse Toxins) |
| Priest | Discipline/Holy | Healer | — none — | NONE | HIGH_UTILITY |
| Priest | Shadow | DPS | Silence (45) | LONG_CD | LIMITED (Purify Disease, Dispel Magic) |
| Rogue | Assassination/Outlaw/Subtlety | DPS | Kick (15) | STANDARD | LIMITED (Shiv, enrage) |
| Shaman | Elemental/Enhancement | DPS | Wind Shear (12) | SHORT_CD | LIMITED (Cleanse Spirit, Purge) |
| Shaman | Restoration | Healer | Wind Shear (30) | LONG_CD | STANDARD |
| Warlock | Affliction/Demonology/Destruction | DPS | Spell Lock (24, pet) | LONG_CD | LIMITED (Singe/Devour Magic) |
| Warrior | Arms/Fury | DPS | Pummel (14) | STANDARD | NONE |
| Warrior | Protection | Tank | Pummel + Disrupting Shout (90 AoE interrupt) + Shockwave (stun) | STANDARD | NONE |
