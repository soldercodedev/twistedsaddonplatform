# Mythic Ledger — Changelog

## 1.0.0-beta.5

A big accuracy pass on the scoring engine, a new at-a-glance **Group Utility** panel, and a couple of
capture fixes. We pulled a batch of real logged keys and used the actual numbers to bring interrupts,
dispels, throughput and survival in line with what really happens in a dungeon. Everything below
**re-scores your existing runs automatically**, so your history updates to the new math on login.

- **[NEW]** **At-a-glance Group Utility.** The run details page and the end-of-run scoreboard now show a
  **Group Utility** panel — your party's total **interrupts**, **target buffs** purged/soothed, and
  **debuffs** cleansed, each as landed vs expected. Hover the dispel tiles to see exactly which enemy
  buffs and player debuffs were dispellable in that dungeon, with spell icons. (The meter only reports one
  combined dispel count, so the purge-vs-cleanse split is attributed by each player's capability — single-
  axis dispellers are exact, dual-axis ones split by their expected share.)
- **[CHANGE]** **Interrupt & dispel expectations are now built from real runs.** Each dungeon's expected
  kicks and dispels used to be a rough estimate; they're now calibrated to logged data, per dungeon —
  some dungeons simply throw more interruptible casts than others, and your target reflects that. The
  old model badly under-counted how much a coordinated group actually kicks, so expectations are higher
  and more realistic across the board. These will keep getting refined as more runs come in.
- **[CHANGE]** **Time in combat now shapes interrupt & dispel expectations.** If you blast a pack — or a
  boss — down before its casts come around, there was simply less to interrupt, and the score knows that
  now. Trash expectations scale with how long the run took; each **boss** scales with how long that boss
  was actually up, since its mechanics recycle the longer the fight runs — a slow kill offers more kicks
  and dispels than a burst, and a boss dropped before its cast comes around offers almost none. Same
  dungeon, a 19-minute key and a 26-minute key are no longer held to the same number.
- **[CHANGE]** **Carrying a slacker no longer hands them a free pass.** If a teammate over-performs and
  covers interrupts/dispels you never got a chance at, you're still not punished for a cast that was
  gone before you reached it. But the old system forgave that shortfall **completely** — so a player who
  just wasn't pressing their button could ride their group to a perfect Utility score. There's now a
  middle ground: teammates covering for you helps, but only **halfway**. Plainly under-use your kit and
  it will show up.
- **[CHANGE]** **Tank damage counts for more.** Measuring logged runs against the model, tanks were
  contributing a lot more of the group's damage than we were crediting them for — so tank Throughput was
  scoring a touch too easily. The role split was rebalanced to match reality (and DPS off-healing now
  counts for a little more, too).
- **[CHANGE]** **Party members are scored on their real spec when we can see it.** A pug's spec isn't
  broadcast to addons, so interrupts/throughput ran off a generic class guess — which could credit, say,
  a Beast Mastery Hunter with a 15-second kick it doesn't have. We now use the spec from the start-of-run
  talent inspection when it lands (and store it), and for an un-inspected Hunter DPS default to the far-
  more-common Counter Shot (long cooldown) rather than assuming a short kick.
- **[CHANGE]** **Survival is a bit more forgiving.** The grace band for avoidable damage widened
  slightly (nobody plays perfectly clean), and the point where Survival bottoms out moved from **40% to
  50%** of your total damage taken being avoidable. Same steep "don't stand in it" curve — just a little
  more breathing room before it bites.
- **[BUG FIX]** **Runs that finish on trash now record their stats.** When a key completed on **trash**
  instead of the last boss (short on enemy forces, went back to clear), the run was saved while you were
  still in combat — and the Midnight meter only reads out of combat, so DPS/HPS/interrupt/dispel numbers
  came back empty. Finalizing now waits for combat to drop first. Boss splits were always fine; this
  fixes the run totals.

## 1.0.0-beta.4

- **[BUG FIX]** **Warlock interrupts now count.** Spell Lock fires from the Felhunter, so the meter
  files those kicks under the **pet** — not the Warlock — and a pet that dies and resummons gets a
  brand-new source id, so they were being dropped entirely (a Warlock's interrupts could read 0). The
  ledger now maps each pet to its owner live during the run and folds pet interrupts / dispels (Spell
  Lock, Devour Magic) back onto the player; a pet/talent-gated interrupt a player couldn't use (and
  didn't land) is scored **N/A**, never a zero. *(Fix is in but not yet confirmed in a live key —
  please report if a Warlock's kicks still read 0.)*

## 1.0.0-beta.3

- **[NEW]** Run timestamps now show the local time of day next to the date everywhere a date appears
  (run lists, cards, detail pages, recaps). New **Date & Time** settings: date format (NA `mm/dd/yy`,
  ISO `yyyy-mm-dd`, or EU `dd/mm/yy`) and 12- vs 24-hour clock, with a live preview. Default is NA +
  24-hour (e.g. `07/14/26 21:33`). Times are in your local timezone.
- **[CHANGE]** Scoring weights are now **static and uniform across every role** (`Config.version` → 20,
  retroactive rescore): **Throughput 35%**, **Interrupts + Dispels 25% combined**, **Survival 20%**,
  **Death Impact 20%**. The two utility categories share the 25% evenly (12.5% each) when both apply; if
  only one applies the other's share moves to it so the utility bucket stays 25%; if neither applies the
  25% goes to throughput + survival. **Role Contribution retired to 0 weight** for all roles (its targets
  can be tuned via knobs later without touching the weights).
- **[NEW]** Talent-aware dispel scoring. Researched vs the Midnight 12.0 talent trees: nearly every
  DPS/tank defensive cleanse is a class-tree talent (Consume Magic, Remove Corruption, Cauterizing
  Flame, Tranquilizing Shot, Remove Curse, Detox, Cleanse Toxins, Purify Disease, Cleanse Spirit, Singe
  Magic; only Rogue Shiv stays baseline). These only create an expectation when confirmed: the tracker
  talent-inspects the party at run start (`Inspect.lua`) and records each member's dispel capability on
  the run, so a player who never specced it (and cast none) scores the Dispels category N/A, never a
  penalty. The player review names the ability they could talent. Scoring `Config.version` → 16
  (retroactive rescore; old runs with no capture treat unknown as N/A too).
- **[CHANGE]** Scoring refinements (`Config.version` → 19, retroactive rescore): **Survival and Death
  Impact always carry exactly equal weight** — averaged as a final step in `Weights.Resolve`, so they
  stay equal even after interrupt/dispel weight is redistributed; a **tracked run with no avoidable-
  damage rows** now scores a true 0% avoidable share (Survival 100), not a neutral "no data" estimate;
  and the confidence blend is one-directional — low group-sample only ever lifts a weak score toward
  neutral, never docks an interrupt/dispel target you actually met.
- **[NEW]** Scoreboard shows a delta vs your best for the exact dungeon + character + spec + key-level
  combo (new best / time off your best / first timed clear). The party table also renders per-stat
  deltas (DPS / HPS / damage taken / deaths / interrupts / dispels / avoidable) for you and any teammate
  you've logged this key with — each driven from that `(guid + spec)`'s fastest timed run of the key in
  your saved history (single-pass `memberBest` index, matched on character + spec).
- **[NEW]** `/tap changekey` — arms a one-shot "change your keystone" reminder that pops over the
  post-run scoreboard, then clears (persists across a reload).
- **[NEW]** Debug page: "Inspect group (dispels)" button — a copyable report of each member's dispel
  capability (also `/mldev inspect`).
- **[BUG FIX]** Returning-player recap no longer re-toasts the just-played group when a run saves — the
  party is marked seen on save, closing the window where a fresh group looked "returning".

## 1.0.0-beta.2

- **[NEW]** Hero-card character overview: **By Spec** (class-colored spec cards) and **By Dungeon**
  (dungeon-art cards) breakdowns, plus large-icon headline stat tiles.
- **[NEW]** Dungeons tab reworked to a hero-card grid with a live type-to-filter (3+ chars).
- **[NEW]** Data-retention policy (All seasons / current season / current expansion, optional newest-N
  cap, "never remove a top run"); Settings previews (stat tile, recap, test scoreboard); per-sound
  channel selection.
- **[BUG FIX]** Boss icons resolve on the scoreboard and historical runs (Encounter Journal is now
  selected before its encounters are queried); scoreboard dungeon art covers the full modal.
- **[BUG FIX]** Average-deaths aggregates now use the player's own deaths, not party totals
  (Runs page still reports party deaths); fixed a nil-call opening run scores and party-card /
  section-header overlap.
- **[CHANGE]** Interrupt/dispel capability profiles corrected for Midnight (per-spec cooldowns; DPS
  and tanks credited for dispels). Scoring `Config.version` bumped to force a rescore.
- **[CHANGE]** Export / Import removed from Settings (dataset size); manage data via Data Retention
  and Delete All History.

## 1.0.0-beta.1

- **[NEW]** First beta. Automatic, account-wide Mythic+ recording (timed / depleted / abandoned),
  organised by character.
- **[NEW]** Party-member history keyed by GUID (never bare name), with a searchable Players browser
  and per-player detail pages.
- **[NEW]** Combat-stat providers: Details! → Blizzard built-in meter → metadata-only, behind one
  normalized interface. Deaths / interrupts / dispels are counted from the combat log in all modes.
- **[NEW]** Returning-player recap — local-only, once per person per group, role-aware, season-scoped.
- **[NEW]** Overview / Runs / Run Details / Dungeons / Characters / Players / Personal Bests /
  Settings / Debug pages, plus a post-run summary.
- **[NEW]** Boss split tracking, reload/disconnect recovery, versioned export/import, schema
  migrations.

### Notes

- **[KNOWN]** Combat-stat coverage depends on the provider; unavailable metrics show as "—", never 0.
- **[KNOWN]** All history is local and private; recaps are never posted to group chat.
