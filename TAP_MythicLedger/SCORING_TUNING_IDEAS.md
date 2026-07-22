# Scoring Tuning Ideas - backlog

Ideas and findings for improving Mythic Ledger scoring accuracy, gathered from beta run-log analysis.
Per project rule, no scoring logic/knob changes without the maintainer's explicit review + sign-off.

**Status:** Ideas **1 and 2 implemented in scoring v39**; **Idea 3 (item level) and the healer outcome
floor implemented in scoring v40** (maintainer-approved 2026-07-22). See the version history in
`Scoring/Config.lua` for the exact knobs. A plain-English explainer of the whole model is auto-generated
from the live config by `tools/scoring-explainer/build.sh` → `tools/ledger-score/out/scoring-explained.html`.

Verification of v39 on the 91-run beta sample (rescored with `tools/ledger-score`): **20 players'
overall improved, 0 regressed**; dispel metric-<50 instances 44 → 29, and the two targeted LONG_CD
kickers passed. The engine test suite is unchanged by these edits (73 pass / 8 pre-existing stale-test
fails, identical before and after).

Evidence base: 91 beta runs (3 clients) pulled from the beta-portal admin API and scored standalone
with the live engine (`tools/ledger-score`), engine **v38**. Full breakdowns:
`tools/ledger-score/out/runlog-accuracy-report.html`.

---

## Idea 1 - Dispel: verify capability by TYPE/SCHOOL, and fix the season-data axis split

**User intent:** make sure that whenever we expect a class/spec to dispel something, they actually
have the ability to clear that **type/school** on that **axis** (defensive cleanse vs offensive
purge/soothe) - e.g. *Holy Paladin has no Dispel-Magic-style purge, so it shouldn't be expected to
clear Skyreach's enemy Magic buffs.*

**Research result (see [DISPEL_CAPABILITY_MATRIX.md](DISPEL_CAPABILITY_MATRIX.md), sourced to
Warcraft Wiki *Dispel* / *Dispel type*):**
- The capability table in `Scoring/Capability.lua` is **accurate**. Holy Paladin is already
  `offensive = {}` - it is **never** expected to purge/soothe. The user's instinct about the
  *capability* is correct, and the model already honors it. ✓ Confirmed by 3 external sources.
- The only capability edit worth considering is **D1: Restoration Druid is missing Soothe**
  (offensive Enrage) in code, though all druids have it. Low impact; errs toward N/A.

**But the run data shows a real dispel problem that is NOT a capability bug - it's the season
DATA's defensive/offensive split:**
- In **Skyreach**, **7 of ~9 healer instances scored 0 on dispels**. They were handed a *defensive*
  Magic expectation of ~1.3-3.2 (from `partyDebuffFrequencies = { magic = 0.08 }`, an estimate),
  but Skyreach's actual dispellable content is **offensive** enemy buffs - Solar Barrier (Magic
  purge) and Rushing Winds (Enrage soothe) - handled by Hunters' Tranquilizing Shot (Beardshottz did
  3 and 18). The healers *can* cleanse defensive Magic; **there just isn't meaningful defensive Magic
  to cleanse**, so the expectation is phantom and they score 0.
- Skyreach's catalog only lists 2 dispels, **both enemy purges**, yet the defensive `magic` estimate
  is non-zero - the estimate outruns the real content.

**IMPLEMENTED (v39):**
1. **Skyreach**: removed the phantom `partyDebuffFrequencies = { magic = 0.08 }` - its dispellable
   content is all offensive (Solar Barrier purge, Rushing Winds soothe), so healers no longer get a
   phantom cleanse target. *(Windrunner Spire left alone - its catalog has real poison/curse/magic
   party debuffs. Nexus-Point Xenas `curse = 0.2` has no curse in its catalog - **flagged for a
   logparse re-derive**, not guess-edited.)*
2. **Group-covered escape** (`Cat.Dispel` + `Config.dispelCoverage`): when a player dispelled 0, their
   fair share was `< shareMax` (1.25), and the group covered `>= groupMin` (0.90) of the demand **on
   the axes this spec can address**, the category becomes N/A (coveredByTeam), not 0. Axis-restricted
   so a DPS's offensive purge can't "cover" a healer's defensive cleanse.
3. **D1 Resto Druid Soothe** added (`Capability.lua`, `offensive = { enrage }`).
4. Rescore is automatic on login (Config.version 38 → 39).

*Verified:* the matrix still holds - a purge-less spec (Holy Paladin, Prot Warrior, DK) never draws
offensive supply; Skyreach Holy Paladins now read dispels N/A instead of 0.

---

## Idea 2 - Interrupts: a LONG_CD "pass" when the group covered kicks and nobody died

**User intent:** a spec with a **LONG_CD** interrupt (Solar Beam 60s, Quell 40s, Shadow Priest
Silence 45s, Resto Shaman Wind Shear 30s, Hunter Counter Shot) should be able to **pass** the
interrupt metric entirely when **(a)** the group did not miss its kick target *and* **(b)** nobody
died from a missed (kickable) cast. Note *why* they passed, and add a nudge that it's **recommended
to press the button anyway**. Especially **highlight** the case where they landed **0 kicks and
someone died to a kickable cast** - a "you could have saved a life, but chose not to" flag.

**Feasibility (from the data - all computable):**
- LONG_CD interrupt scores <50: **10**. Under the pass rule (group kick coverage ≥100% **and** zero
  kickable party deaths), **6 would convert to a pass** (e.g. Badwater/Shaman in Algeth'ar +10 at
  104% group coverage; Thesmanmeta/Shaman in MagistersTerrace +2 at 101%).
- The remaining 4 correctly do **not** pass: 2 because the group under-covered (Skyreach +9 78%,
  Algeth'ar +14 67%), and the Algeth'ar +10 case is correctly blocked because **2 kickable deaths
  occurred** - exactly the guard the user wants.
- The "0 kicks **and** a kickable death" highlight is the strong-negative case. It needs the **v38
  death-cause breakdown** (`deathCauses.kickable`), which was present on only **13/91** runs here -
  so wiring the highlight depends on that capture landing reliably (see Idea-3-adjacent note: death
  causes captured on just 39/200 death rows).

**IMPLEMENTED (v39)** (`Cat.Interrupt` + `Config.interrupt.longCdPassCoverage = 1.0`):
- When `profile == LONG_CD`, the player **scored below neutral** (under-kicked their share), group
  interrupt coverage ≥ `longCdPassCoverage` (100%), and `party kickable deaths == 0`: interrupts →
  **N/A with `recommendPress`** ("group covered the kicks… still worth pressing it when you can"),
  weight redistributed. Gated to under-performers so a LONG_CD spec that kicked its share still scores.
- Pass **revoked** and `missedLifeSavingKick` flagged (score kept) when the player landed 0 kicks and
  a kickable death occurred; the explanation appends the "could have prevented it" note.
- **LONG_CD only** - short-CD/high-control kickers still carry.
- *Verified:* 2 legitimate passes fired on the sample (Resto Shaman, Shadow Priest, both group-covered);
  the guard correctly blocked the Algeth'ar +10 run (2 kickable deaths) - that LONG_CD kicker kept
  its score. Party kickable-death detection needs the v38 death-cause capture (present on 13/91 here),
  so the guard/flag are only as good as that capture.

---

## Idea 3 - Item level: check for over-performance skew from out-gearing

**User intent:** over-performance (throughput ratio > 1) may partly just reflect players **out-gearing
the content**, inflating the throughput score.

**Research result (from the 91 runs):**
- Weak **positive** correlation between item level and DPS-throughput ratio: **Pearson r ≈ 0.28**.
  By bucket, ~280+ ilvl players averaged ratio ~1.3-1.5 vs ~0.75-0.9 for 230-260.
- **Big caveat - data is thin and the model is group-relative.** Item level is only captured on
  **21% of player-rows** (95/455 - mostly the log owner + inspected members). And throughput is
  scored **group-relative**: expected is derived from the group's own total, so out-gearing the
  *content* is largely normalized away - everyone's bar rises together. The residual signal would
  come from out-gearing your *group*, which we can't isolate without near-complete party ilvl.
- The beta.6 groundwork already **records** party hero tree / talents / item level (not yet driving
  scores), so the data to test this properly is starting to arrive.

**Prototype result (2026-07-22, on the 19 full-party-ilvl runs - read-only, NOT wired in):**
- The signal is clear on complete runs: **corr(ilvl - groupAvg, DPS ratio) = +0.40**, slope
  **≈ 1.18% throughput per ilvl** above/below the group average - close to WoW's real gear scaling.
- Simulated `expected × clamp(1 + k·(ilvl - groupAvg), lo, hi)` then re-scored on the throughput curve:
  it **flattens the correlation toward 0** (±25% clamp → +0.04), **lifts undergeared "did their part"
  players +11 to +24** throughput points, leaves **at-average shortfalls ~+0.5** (not excused), and
  **doesn't touch overgeared players** (curve plateaus at ratio 1.0; excess already removed from the
  group baseline via EffectiveGroupTotals). So it's a fairness fix for the *under*-geared, not a nerf.

**IMPLEMENTED (v40)** - `Config.throughput.ilvlAdjust` = { perIlvl 0.01, clamp ±20%, minCoverage 0.8 }.
Bounded multiplier on the throughput **DPS component only** (HPS uses the damage-taken model), applied
only when ≥80% of party ilvl is known (else no-op - inert on the 72/91 runs without full inspect today,
activating as the capture accumulates). Threaded via `Score.RunContext` (groupAvgIlvl + coverage).
*Verified rescore:* 24 up / 7 down - every "down" is an **over**-geared player now held to a higher bar
(max -4); no low-ilvl player was hurt, which was the goal.

### Healer outcome floor (finding 4 from the accuracy report) - IMPLEMENTED (v40)

Diagnosis (prototyped on the beta runs): the healer throughput tail is **not** an intensity/magnitude
problem (concave `groupSelfHealFactor` didn't move it; global-lower just inflated the median) and **not**
an avoidable-damage problem (avoidable is only 3-15% of the requirement, so forgiving it barely moved
scores). The tail splits into clean 0-1-death timed runs (unfairly dinged - the group self-covered) vs
high-death disasters. Fix = `Config.throughput.outcomeFloor` = { roles HEALER, neutral 75, deathK 3,
strength 1.0 }: on a timed run, a sub-neutral healer throughput is lifted toward neutral in proportion to
`clamp(1 - partyDeaths/3)`. Death-gated (10-/16-death runs untouched), never lowers a score. *Verified:*
6 fired (Zymist 64→75 on 0-death Seat +10; Kaoori 47→66), disasters correctly untouched.

---

## Related (from the earlier run-log accuracy report - same evidence base)

- **Interrupts over-punish attribution:** 77% of interrupt <50s happened when the group covered ≥90%
  of kicks. Idea 2 addresses the LONG_CD slice; short-CD needs the report's `coveredByTeam` /
  `snipeForgiveness` / curve options.
- **Dispels near-binary:** 18% of applicable dispel rows score 0, many "expected ≈1, did 0". Idea 1
  step 2 (curve softening / group-covered escape) addresses this.
- **Deaths:** v38 cause-weighting fired on only 39/200 death rows here (capture gap) - the rest used
  the flat -25/death curve. Worth confirming death-recap capture reliability (also gates Idea 2's
  highlight).
