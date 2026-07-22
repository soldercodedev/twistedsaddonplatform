# Mythic Ledger - Changelog

## 1.0.0-beta.9

Part of the platform's new **two-tier navigation** (TAP 1.5.0-beta.1).

- **[NEW]** **Every page is now a sidebar row.** Overview, Runs, Dungeons, Characters, Players, Bests, Settings and Debug live in the left sidebar under the **Mythic Ledger** category (with the Dungeon Guide) instead of an in-body tab strip. Opening a run, player, dungeon or the player review still happens in place, and Back returns where you came from.
- **[NEW]** **Filter and sort the Runs list.** The Runs page gains a filter toolbar - **Season, Result, Character, Dungeon, Key level** and **Role** (Tank / Healer / DPS) - and now shows **DPS and HPS in their own columns**, each sortable, alongside the result shown inline with the season.
- **[NEW]** **Filter Players by class and spec.** The Players page adds **Class** and **Spec** dropdowns next to the existing Role and Favorites filters.
- **[CHANGE]** **Settings, reorganized into sub-tabs.** The two-column Settings grid is replaced by in-body sub-tabs - **Appearance, Tooltips, Scoreboard, Death Report, Tracking, Regroup** and **Misc** - each with its own page heading (title + description) below the tab bar and shown full-width, with more description on what each setting does. Highlights: Tooltips has a **Hover Me** live preview, the Scoreboard column dropdowns now expand to fit, Death Report and Regroup use a two-column layout with proper section headers (Death Report: **Behavior / Appearance / Preview**; Regroup: **Triggers / Include**), Regroup adds a **test toast** button, and the minimap-button toggle moved onto **Misc** (formerly Debug).
- **[CHANGE]** **"Recap" is now "Regroup."** The returning-player recap tab is renamed - "Recap" read like a run summary; "Regroup" is about grouping up again with someone you've keyed with. Its redundant **Detail** dropdown is gone (it never changed the output - use the *Include* toggles), and the on-screen death report's enable switch moved under **Behavior** as **Enable Death Report**.

## 1.0.0-beta.8

**Missed Kick** deaths, a new on-screen **death report**, and an **avoidable-damage breakdown** with clearer, personalized coaching - building on beta.7's attribution. The scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Missed Kick is now its own death cause.** Death attribution adds a fourth cause alongside Avoidable, Threat, and Other: a **Missed Kick** - a cast that should have been interrupted landed and helped kill you - and it names the exact cast. It reads the death recap and weighs the *whole* sequence, so a kickable cast that dropped you gets the blame even when a normal hit lands the killing blow. Recomputed from each run's stored recaps, so it appears on runs you already have.
- **[CHANGE]** **Missed-kick deaths are scored like an "Other" death.** A death from a missed interrupt carries the same penalty as an unavoidable one - carved out of the old "Other" bucket, so the death count and its total weight are unchanged, only how each death is labelled.
- **[NEW]** **On-screen death report.** After a pull (or at the run's end), a customizable overlay flashes **who died since the last report and why** - the time in the key, the killing blow, and the cause (including a missed kick's cast). Turn it on in **Settings > Death Report**, where you can style the font, size, colors, an optional background panel, and position (drag-to-move with Save/Cancel), pick how it dismisses (auto-fade or **click to dismiss**), and choose whether it fires each pull or once at the finish. **/ledger deathreport** reposts the last one to party chat.
- **[NEW]** **Avoidable-damage breakdown on the score card.** The player review now lists the exact mechanics behind your Survival score - biggest first, each a real **spell icon** with the game's own hover tooltip, plus the damage taken, a share bar, and its share of your avoidable total. Reference only; it never changes the score.
- **[CHANGE]** **Clearer, personalized score explanations.** The "How your targets were set" box now sits **below** the coaching (What went well / Focus on), and every category is explained in plain language using **your own numbers** with a worked example. Survival and Deaths in particular now show your actual avoidable share and what each death cost, instead of a generic rule.
- **[BUG FIX]** **Scoreboard "Least Avoidable" leader fixed.** A player who took **no** avoidable damage (shown as "-") was skipped, so the crown went to someone who actually stood in something; a clean player is now correctly read as zero and credited.
- **[CHANGE]** **Settings page redesigned.** Settings now use a **two-column layout**, and the scoreboard **Scale** slider shows its numeric value again.
- **[BUG FIX]** **Interrupt cooldown-class labels corrected.** Several kicks were labelled in the wrong CD band: 15-second melee kicks (Kick, Pummel, Mind Freeze, Disrupt, Skull Bash, Spear Hand Strike, Rebuke) now read **Short-CD**, and 24-second ranged kicks (Counter Shot, Counterspell, Spell Lock) read **Standard**. Labels only - expected kick rates and grades are unchanged.

## 1.0.0-beta.7

Death **attribution** and per-spell **interrupt & dispel breakdowns**. Every death is now sorted into **why** it happened, which drives a smarter death penalty, and the run review shows **exactly what you kicked and dispelled** versus what the dungeon demanded. The scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Death Causes.** Every death is classified as **Avoidable** (you stood in something), **Threat** (unmitigated melee while you weren't tanking - you pulled aggro, or the tank never picked it up), or **Other** (unavoidable). It reads the game's **death recap** and weighs the *whole* sequence, not just the final hit - so a mechanic that dropped you to 10% gets the blame even when a normal hit lands the killing blow. Shown as a breakdown card on the player review.
- **[CHANGE]** **Deaths are scored by cause.** The Death penalty is no longer flat: an **avoidable** death costs the most; an **unavoidable** one less; a **threat/aggro** death the least (it's largely not on you). The death count and its weight are unchanged - only how much each death costs. Runs recorded before this update keep the old flat penalty.
- **[NEW]** **Interrupt breakdown - did you kick the right casts?** The player review now shows **what you actually interrupted**, grouped by the dungeon's priority tiers (Critical / Must / Should kick), plus the priority casts you didn't personally cover. **Click any spell to jump straight to it in the Dungeon Guide.**
- **[NEW]** **Dispel breakdown, with your tool shown.** The same for dispels - your clearing ability on the left, what you cleared by priority on the right, and the casts your kit could have handled but didn't, **filtered to what your spec can actually dispel**. (Folds the old dispel coaching into one clearer block.)
- **[NEW]** **Item level & hero talent on the details page.** Each player's **item level** now has its own tile, and their chosen **hero talent** shows as an icon in the header.
- **[NOTE]** **Full per-spell run log.** Every run now records the complete per-spell breakdown for the whole party - damage and healing done, damage taken, avoidable, interrupts, dispels, and the death recaps - so future scoring and analysis have the raw detail to build on. *(Captured now; most of it isn't shown yet.)*

## 1.0.0-beta.6

The deepest scoring pass yet - **healing is now graded against the damage your group actually took**, **dispels only count the real priorities**, and there's a brand-new **Dungeon Guide**. Every scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Dungeon Guide.** A read-only journal of the season's **interrupt & dispel priorities**, dungeon by dungeon: which enemy casts to kick and which auras to dispel, ranked by tier, with the dispel type and the caster shown as a **live 3D model** when you click a spell. It's its own entry in the **/tap** menu under Modules - a reference, it doesn't affect scoring.
- **[CHANGE]** **Tanks & healers are graded on the damage the group actually took.** Instead of a share of the group's total HPS, tank and healer **Throughput** now measures healing **plus absorbs** against a target built from **unavoidable damage taken**: the tank is expected to self-cover a spec-based portion, the healer covers the rest of the group. Standing in **avoidable** damage now hits **that player's own Survival**, not the healer's target - so a healer isn't punished for a group that stands in the bad. Absorbs count toward output, so shield-heavy healers (Disc, Preservation) aren't shortchanged.
- **[CHANGE]** **Healing expectations tuned per tank spec, from 32 logged runs.** Guardian Druid and Prot Paladin self-cover **more** (Frenzied Regen / Word of Glory out-heal the old bar); Brewmaster covers **less** (Stagger's mitigation isn't visible to the meter, so Brew genuinely leans on the healer); the healer target was re-centered so both land where they should.
- **[CHANGE]** **Dispels only count what's actually a priority.** Each dungeon's dispel requirement now counts **only High/Must** dispels, so you're no longer docked for skipping low-value cleanses. We added the dungeon dispels the guides never named (Transference, Permeating Cold, Energy Bomb...), **gated out enemy buffs the group rarely removes** (trash enrages), and stacking DoTs (Rotting Strikes, Vilebranch Sting) now count **once per threshold**, not per stack.
- **[CHANGE]** **Long-cooldown interrupts expect fewer kicks.** A 45-60s interrupt is reasonably banked when the group already covers the casts, so long-CD specs (Shadow Priest, Balance Druid, Mage...) are no longer docked for holding it.
- **[NEW]** **Groundwork for gear- & build-aware scoring.** The start-of-run inspection now records each party member's **hero tree, talents, and item level** (shown on the details page) - the foundation for expectations that adjust to a player's class, spec, item level and build. *(Collected now; not yet driving scores.)*

## 1.0.0-beta.5

A scoring accuracy pass, two new features - a **Group Utility** panel and **shared-history player tooltips** - and a couple of capture fixes. Scoring changes below **re-score your existing runs automatically** on login.

- **[NEW]** **At-a-glance Group Utility.** Run details and the scoreboard now show a **Group Utility** panel: party totals for **interrupts**, **buffs purged/soothed**, and **debuffs cleansed**, each landed vs expected. Hover the dispel tiles for what was dispellable, with icons.
- **[NEW]** **Your shared history, right on their tooltip.** Mouse over anyone you've keyed with - frames, group finder, /who, guild, communities, friends - and their tooltip shows your shared history: keys together, timed %, best key, **average score**, and your notes. Sits **under** RaiderIO without replacing it; toggle each surface in **Settings > Tooltips**.
- **[CHANGE]** **Interrupt & dispel expectations are built from real runs.** Each dungeon's expected kicks and dispels are now calibrated from logged data instead of estimates - and higher, since the old model under-counted a coordinated group. The last untuned dungeons (Skyreach, Windrunner Spire, Nexus-Point Xenas) are dialed in too.
- **[CHANGE]** **Time in combat shapes interrupt & dispel expectations.** They now scale with time in combat - trash with run length, each **boss** with how long it was up. A 19-minute key and a 26-minute key are no longer held to the same number.
- **[CHANGE]** **Carrying a slacker no longer hands them a free pass.** A teammate covering interrupts/dispels for you now only helps **halfway** - the old system forgave the shortfall completely, so a lazy player could ride the group to a perfect Utility score.
- **[CHANGE]** **Tank damage counts for more.** Tanks contribute more of the group's damage than we credited, so tank Throughput scored too easily. Rebalanced to match; DPS off-healing counts for a little more too.
- **[CHANGE]** **Augmentation Evokers are scored as the support spec they are.** An Aug's Throughput bar now drops to about **half** a normal DPS's, with that share handed to the teammates it buffs - most to damage-dealers, a little to tank and healer. It shouldn't be graded on personal damage when its job is pumping everyone else's.
- **[CHANGE]** **Party members are scored on their real spec when we can see it.** We now use the start-of-run talent inspection when it lands instead of a class guess - so a Beast Mastery Hunter isn't credited with a kick it doesn't have. Un-inspected Hunter DPS defaults to Counter Shot (long cooldown).
- **[CHANGE]** **Survival is a bit more forgiving.** A wider avoidable-damage grace band, and it now bottoms out at **50%** of your damage taken being avoidable (was 40%).
- **[BUG FIX]** **Runs that finish on trash now record their stats.** A key that completed on **trash** instead of the last boss saved while still in combat, so the Midnight meter (out-of-combat only) returned empty totals. Finalizing now waits for combat to drop; boss splits were unaffected.

## 1.0.0-beta.4

- **[BUG FIX]** **Warlock interrupts now count.** Spell Lock fires from the Felhunter, so the meter
  files those kicks under the **pet** - not the Warlock - and a pet that dies and resummons gets a
  brand-new source id, so they were being dropped entirely (a Warlock's interrupts could read 0). The
  ledger now maps each pet to its owner live during the run and folds pet interrupts / dispels (Spell
  Lock, Devour Magic) back onto the player; a pet/talent-gated interrupt a player couldn't use (and
  didn't land) is scored **N/A**, never a zero. *(Fix is in but not yet confirmed in a live key -
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
  Impact always carry exactly equal weight** - averaged as a final step in `Weights.Resolve`, so they
  stay equal even after interrupt/dispel weight is redistributed; a **tracked run with no avoidable-
  damage rows** now scores a true 0% avoidable share (Survival 100), not a neutral "no data" estimate;
  and the confidence blend is one-directional - low group-sample only ever lifts a weak score toward
  neutral, never docks an interrupt/dispel target you actually met.
- **[NEW]** Scoreboard shows a delta vs your best for the exact dungeon + character + spec + key-level
  combo (new best / time off your best / first timed clear). The party table also renders per-stat
  deltas (DPS / HPS / damage taken / deaths / interrupts / dispels / avoidable) for you and any teammate
  you've logged this key with - each driven from that `(guid + spec)`'s fastest timed run of the key in
  your saved history (single-pass `memberBest` index, matched on character + spec).
- **[NEW]** `/tap changekey` - arms a one-shot "change your keystone" reminder that pops over the
  post-run scoreboard, then clears (persists across a reload).
- **[NEW]** Debug page: "Inspect group (dispels)" button - a copyable report of each member's dispel
  capability (also `/mldev inspect`).
- **[BUG FIX]** Returning-player recap no longer re-toasts the just-played group when a run saves - the
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
- **[NEW]** Returning-player recap - local-only, once per person per group, role-aware, season-scoped.
- **[NEW]** Overview / Runs / Run Details / Dungeons / Characters / Players / Personal Bests /
  Settings / Debug pages, plus a post-run summary.
- **[NEW]** Boss split tracking, reload/disconnect recovery, versioned export/import, schema
  migrations.

### Notes

- **[KNOWN]** Combat-stat coverage depends on the provider; unavailable metrics show as "-", never 0.
- **[KNOWN]** All history is local and private; recaps are never posted to group chat.
