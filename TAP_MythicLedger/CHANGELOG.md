# Mythic Ledger — Changelog

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
