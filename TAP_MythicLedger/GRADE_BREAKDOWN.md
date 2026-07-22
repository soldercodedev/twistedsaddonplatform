# Mythic Ledger - Grade Breakdown, element by element

A plain-language map of every piece that goes into a player's grade, so you can reason about where to
tune it. Each item is 1-2 sentences plus a pointer to the knob that controls it. Everything is
**deterministic and group-relative** - no self-learning that would make scores differ between installs,
and no player is ever compared directly to a teammate (only to a spec-aware expectation).

Source of truth: `Scoring/Config.lua` (the engine constants), `Scoring/Seasons/*.lua` (the per-dungeon
interrupt/dispel content for the active season), `Scoring/Distribute.lua` (the group workload split),
`Scoring/Categories.lua` (the per-category math), `Scoring/Weights.lua` (weighting), `Scoring/Score.lua`
(assembly + explanation text). Current scoring version: **23**.

---

## The one-paragraph model

Each player gets five category scores (0-100), each is the player's result vs an **expected** value put
through a **curve**, and the grade is their **weighted average**. Missing data never scores 0 - it sits
at a neutral estimate. A category that doesn't apply to a spec is marked **N/A** and its weight moves to
categories the player *can* affect. The final 0-100 maps to a letter grade.

---

## The five categories (and their weights)

Weights are currently **identical for every role** (`Config.roleWeights`):

| Category | Weight | Measures |
|---|---|---|
| Throughput | **35%** | Damage and/or healing vs your expected group share |
| Interrupts | **12.5%** | Kicks landed vs expected for your spec's kit |
| Dispels | **12.5%** | Dispels/purges vs expected for your spec + the dungeon |
| Survival | **20%** | How much of the damage you took was *avoidable* |
| Death Impact | **20%** | A flat, escalating penalty per death |
| ~~Role Contribution~~ | **0%** | Retired - a small survival+utility composite, currently unweighted |

Interrupts + Dispels together form a **25% "utility" bucket**; if one doesn't apply, the whole 25% goes
to the other.

---

### 1. Throughput - 35%
- **What:** a group-relative blend of a DPS component and an HPS component. Your **expected** value for a
  metric = `groupTotal(metric) × yourShare ÷ sum(shares)` - i.e. your fair slice of what the group
  actually produced (`Config.throughput.groupShare`, `Baselines.lua`).
- **Role shares:** DPS share `DAMAGER 1.0 / TANK 0.35 / HEALER 0.08`; HPS share `HEALER 1.0 / TANK 0.62 /
  DAMAGER 0.04`. How the two blend per role is `metricMix` (`DAMAGER` all DPS, `HEALER` 85% HPS, `TANK`
  60/40), and tanks are further scaled by a per-spec **healiness** table (Blood DK 1.35 → Prot Warr 0.60).
- **Curve:** ratio (yours/expected) → score, hitting **100 at 1.0×** and plateauing above it (`Config.throughput.curve`), so meeting your share is full marks.
- **Two anti-padding guards:** (a) doing more than your share is removed from the group total everyone
  else is measured against (`Baselines.EffectiveGroupTotals`), so out-DPSing never drags teammates -
  or you - down; (b) healer/tank **HPS is soft-capped** above `healerSoftCapRatio = 1.15×` (excess
  healing usually means avoidable damage, which is Survival's job to penalize, not Throughput's to reward).
- **Fallback:** if the group produced no total (metadata-only run), a static role reference is used
  (`staticReference`: DPS 900k / tank 500k / healer 450k HPS). No data at all → neutral **70**.

### 2. Interrupts - 12.5%
- **What (group-distributed):** expected is your **fair share of the run's kick supply**, not a solo
  estimate (`Scoring/Distribute.lua`). Supply = `min(season kick supply, group cooldown capacity)`. Your
  **share** = your kick capacity (`InterruptRatePerMinute × runMinutes`) ÷ the group's total - so more
  capable teammates shrink your share. **Sniping redistribution:** a teammate over their share has that
  excess pulled from the under-performers' expected (sniped players aren't docked); the over-performer is
  curve-capped at 100 (no reward). A share redistributed to ~0 → **N/A** (teammates covered it).
- **Season kick supply (implicit boss-time):** the pool is summed from the **season utility profile**
  (`Scoring/Seasons/*.lua`) as `trash.interruptFrequency × trashKick + Σ(killed boss.interruptFrequency ×
  bossKick)` - one block for all trash, one per boss, keyed by `dungeonEncounterID`. Because only the
  **bosses actually killed** contribute, a boss with nothing to kick (`interruptFrequency = 0`) simply adds
  nothing - no separate "dead boss time" subtraction is needed. The per-source scales live in
  `Config.supplyScale` (`trashKick` / `bossKick`); the frequencies are the per-dungeon tuning knobs.
- **Curve & cap:** the shared **contribution curve** (`0→0 … 1.0→100`), capped at 100.
- **Talent/pet gate:** a talent-/pet-gated interrupt (Warlock Spell Lock) is scored **N/A** unless we
  confirmed the tool or you landed ≥1 kick. Baseline interrupts are always expected.
- **No benefit of the doubt:** on a **tracked** run, no recorded kicks = a real **0** (not neutral). The
  **confidence blend is removed** for interrupts - a genuine 0 stays a 0. Only a fully **untracked** run
  (no combat data at all) falls back to neutral, so a data outage isn't punished. A dungeon with **no
  season profile** yields no fair target → **N/A** (never a zero for a missing model).

### 3. Dispels - 12.5% (dual-axis, group-distributed)
- **What:** same supply→share→redistribution engine as interrupts, but the supply is **per school × axis**
  and each school's supply is split **only among the members who can address it** - so a school only one
  player can touch (e.g. the sole decurser) lands entirely on them, and three Magic-cleansers split the
  Magic load. Dispel is **two jobs**, and the per-school split is where that fairness now lives, so a spec
  is only ever measured on what it can do:
  - **Defensive** - cleanse **friendly debuffs** (Magic/Curse/Poison/Disease), from the season profile's
    `partyDebuffFrequencies` per school.
  - **Offensive** - **purge** enemy buffs (`targetBuffFrequencies.purge` → the Magic offensive school) /
    **soothe** enrages (`targetBuffFrequencies.enrage`).
  A purge-only spec only ever draws from purge/soothe supply, a cleanse-only spec only from debuff supply -
  neither is penalised for work it structurally cannot do, with no explicit demand/axis knob to maintain.
- **Season dispel supply (implicit boss-time):** like interrupts, each (axis, school) supply is summed over
  the **trash block + the blocks of the bosses actually killed** (`× trashDispel` / `× bossDispel` from
  `Config.supplyScale`). A boss with no cleansable debuff contributes nothing, so boss-time is handled
  implicitly - no per-axis dead-time subtraction.
- **Gates:** **talent gate** (talented cleanses → N/A unless confirmed or you dispelled ≥1); and if the
  distribution allocates you **~0** (the dungeon has nothing your kit can touch, or teammates covered it),
  the category is **N/A** (weight redistributed), not a zero. Healers' baseline cures always count.
- **No benefit of the doubt:** like interrupts, a tracked run with a real share and no dispels scores a
  real 0; the ~0-share N/A fires first, so a 0 only bites when there *was* something the spec could
  dispel/purge here. The **confidence blend is removed** for dispels too - the per-school target is
  accurate, so a genuine 0 stays a 0. **Coaching callout** (`Config.DungeonDispelTargets` →
  `dungeonDispelDebuffs`) still lists the exact effects your kit could have cleared.

### 4. Survival - 20%
- **What:** a single, scale-free ratio - **avoidable damage ÷ total damage taken** - so it's fair across
  roles and gear. A confirmed **0% avoidable = a perfect 100** at full confidence.
- **Curve:** flat 100 through a **2.5% grace band**, then a steep, front-loaded drop to **0 at a 40%
  avoidable share** (`Config.survival.avoidableShareCurve`: 5%→87, 12%→55, 25%→22).
- **No data** (missing avoidable or taken) → neutral **80**.

### 5. Death Impact - 20%
- **What:** a flat, escalating penalty, **not** a judgement of whose fault a death was. `score = 100 -
  penalty`, with **-25 per death** → 1 death = 75, 2 = 50, 3 = 25, **4+ = 0** (`Config.deaths`).
- Combined with the heavy 20% weight, dying is the single most expensive thing on the grade.
- **No data** → neutral (base **100**).

### Role Contribution - 0% (retired)
- A small composite of Survival + utility execution, currently carried at **0 weight** for all roles.
  It still computes (for possible future use) but contributes nothing to the grade today.

---

## Cross-cutting mechanics (why a number ends up where it does)

### Expected → actual → curve
Every utility/throughput category turns a **ratio** (your value ÷ expected) into a score through a
lookup curve that tops out at **100 when you meet expectation** and never rewards overshoot. Tune the
shape in `Config.contributionCurve` (interrupts/dispels) and `Config.throughput.curve`.

### Group-relative baselines
Throughput expectations come from the group's own totals split by role share - deterministic, no
learning - with each player's contribution to that total **capped at their own share** so padding can't
move the bar (`Baselines.EffectiveGroupTotals`).

### Composition - via capability share (was a bounded ±15% nudge)
Teammates who can do the same job **lower your expected utility** - structural, via the
**capability-share distribution** (your share of the supply = your capacity ÷ the group's total), not a
bounded modifier. More/stronger interrupters or same-school dispellers → smaller share → lower expected.
Over-performing a teammate **reduces the rest of the group's workload** (sniping redistribution) and never
raises anyone's target. Interrupts/dispels are graded **only** through this run-level group pass; a
standalone scoring call with no run context marks them **N/A** rather than inventing a solo estimate.

### Confidence blend - no longer applied to utility
The interrupt/dispel **confidence blend is removed**: now that expected is a group-distributed fair share
of an accurate season supply (boss-time implicit), no group-total forgiveness is applied - a real 0 stays
a 0. The group total is still surfaced as **sample context** on the result, just not blended in. (The
throughput low-sample handling via baselines is unchanged.)

### Weight redistribution (N/A categories)
An N/A category's weight is **moved, never dropped** (`Weights.Resolve` + `Config.redistribution`):
interrupts N/A → dispels takes the 25%; dispels N/A → interrupts takes it; **both** N/A → the 25% splits
50/50 to throughput and survival. Separately, **Survival and Death Impact are always equalized** to the
exact same weight, whatever else moved.

### Grade letters
The 0-100 overall maps to `Config.grades`: **S ≥ 97, A+ ≥ 93, A ≥ 89, A- ≥ 85, B+ ≥ 80, B ≥ 75, B- ≥ 70,
C+ ≥ 65, C ≥ 60, D ≥ 50, F** otherwise.

### Static vs learned baselines
Throughput baselines can blend from the static role reference toward a **learned same-spec median** as
comparable runs accumulate (`Config.learned`: needs 3+ runs in a bucket to use it, full trust at 20).
This is the one place history feeds in - still deterministic per your own data, never uploaded.

---

## Quick "where to tune it" index

| Want to change… | Edit |
|---|---|
| Category weights | `Config.roleWeights` |
| What happens when a category is N/A | `Config.redistribution` + `Weights.Resolve` |
| How hard the curve punishes under-performance | `Config.contributionCurve`, `Config.throughput.curve` |
| Per-spec kick/dispel cooldown rates (the SHARE side) | `InterruptRatePerMinute`, `dispelProfiles`, `Capability.lua` |
| Per-dungeon interrupt content (trash + per boss) | `Scoring/Seasons/*.lua` → `interruptFrequency` |
| Per-dungeon defensive dispel content, per school | `Scoring/Seasons/*.lua` → `partyDebuffFrequencies` |
| Per-dungeon offensive purge/soothe content | `Scoring/Seasons/*.lua` → `targetBuffFrequencies` (`purge` / `enrage`) |
| Global frequency→count scale (the SUPPLY floor) | `Config.supplyScale` (`trashKick`/`bossKick`/`trashDispel`/`bossDispel`) |
| Dispel coaching: exact effects a kit could clear | `Config.dungeonDispelDebuffs` (`kind` tags) → `DungeonDispelTargets` |
| Adding a new season | copy `Scoring/Seasons/MidnightS1.lua`, edit numbers, register under its season id(s) |
| Role DPS/HPS shares, tank healiness, HPS soft cap | `Config.throughput` |
| Survival strictness (grace band / zero point) | `Config.survival.avoidableShareCurve` |
| Death penalty severity | `Config.deaths` |
| How teammates affect expectations | `Config.composition` |
| Low-sample forgiveness | `Config.confidence` |
| Grade letter cutoffs | `Config.grades` |
| History blend | `Config.learned` |
