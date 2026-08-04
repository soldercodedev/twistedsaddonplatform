# Mythic Ledger - Changelog

## 1.3.0

A Live Coach that nudges you between fights, plus some week-over-week stats: trend cards and trouble spots on the Overview, a Great Vault tracker on the Characters page, and a new Progression page. Scoring is untouched.

- **[NEW]** **Live Coach** - an on-screen nudge between fights. After a boss (or big pulls too, your call) it checks how the run is going and tells you the one thing to fix: "Kick more", "Cut avoidable damage", "Push your DPS". It grades with the same engine as your end-of-run score, so the advice matches your final grade - the real score still comes at the end. Off by default; turn it on in Settings > Live Coach, where you pick how often it speaks, how much it says, and how it looks. `/tap ml coach` tests it.
- **[NEW]** The Overview has a **This Week** row - runs, timed %, average score, and deaths, each compared to last week. Shows up once you have two weeks of history.
- **[NEW]** **Trouble Spots**, also on the Overview: the dungeons that keep beating you, ranked by fail rate and deaths.
- **[NEW]** The Characters page now starts with a **Weekly Vault** panel - every character's top 8 keys this week, with the three vault slots marked and the reset timer. Depleted keys count too, same as the vault itself.
- **[NEW]** A new **Progression** page charts a character's trajectory across their runs. Pick a metric - Ledger Score, Key Level, Time vs timer, Deaths, DPS or HPS - and read it as a line with an average line and an Improving / Steady / Regressing call, with Latest / Min / Max / Average cards above it. Switch between a per-run and a weekly view, and narrow to a date range and/or a key-level range.

## 1.2.0

Throughput scoring goes back to "meeting your share is 100," the Death Causes breakdown now names what killed you, and the saved run history is leaner with lower memory use.

- **[NEW]** The Death Causes breakdown now names what actually killed you - the mechanic behind each avoidable death, the un-kicked cast behind a missed kick, and the biggest single source behind an unavoidable one. Works on your existing runs too.
- **[CHANGE]** Throughput: hitting your expected group share is a full 100 again. Doing your fair share is a top mark, beating it caps at 100 (you can't score above 100% for work that wasn't asked of you), and falling short is still graded down. This reverts last version's stricter bar, which scored meeting your share only a 94. Your existing runs re-score on login.
- **[CHANGE]** The saved run history is much smaller. Several per-ability breakdowns that were stored but never shown are no longer kept, along with a leftover stat nothing fills in; your existing runs are trimmed automatically on login, keeping everything the score, the run review, and the boss splits actually use.
- **[CHANGE]** Per-boss splits store less - the top DPS and HPS are worked out from the per-player numbers instead of saved a second time, and empty death lists aren't kept.
- **[CHANGE]** Uses less memory when you browse a lot of run reviews in one session: a viewed run's full score detail is now cached briefly instead of held for the whole session.

## 1.1.2

A scoring calibration pass - fairer tank grading and a firmer throughput bar - plus the Hunter Feign Death fix and housekeeping.

- **[CHANGE]** Tanks are now graded on threat control: every teammate death from a mob you lost or never grabbed docks your Survival. Tanks used to score near-perfect regardless; now holding the group together shows in the score. Your existing runs re-score on login.
- **[CHANGE]** Tanks are held to a much tighter avoidable-damage standard than other roles. A tank eats the brunt of every pull, so even a small share of avoidable damage taken now costs real Survival points, where the shared grace band used to park every tank at 100.
- **[CHANGE]** Throughput no longer maxes out just for pulling your fair share. Meeting your expected share is a strong score and beating it a little tops out, so the DPS/HPS bar tells good from average better.
- **[CHANGE]** Kick expectations for Seat of the Triumvirate and Nexus-Point Xenas were recalibrated to what real runs actually kick.
- **[CHANGE]** Several often-kicked casts (Arcane Bolt, Shadow Bolt, Holy Bolt, Umbra Bolt, Shadowfrost Blast) now show as Should Kick instead of Spare in the Dungeon Guide.
- **[CHANGE]** The group-utility tiles in the run review use the same color per dispel school as the Dungeon Guide.
- **[CHANGE]** The post-run summary options (whether it pops, waiting until you loot the end chest, and the popup delay) moved from the Tracking tab to the Scoreboard tab, where they belong.
- **[BUG FIX]** A Hunter's Feign Death no longer counts as a real death, so hunters aren't penalized for feigning. Your existing runs are corrected on login.
- **[BUG FIX]** The run lists on the Characters and Dungeons pages were missing their column headers. They're back, and now sortable by date, key, time, deaths or DPS/HPS.
- **[BUG FIX]** The Dungeon Guide's caster preview shows on the first click instead of staying blank until you click away and back.
- **[BUG FIX]** The scoreboard and browsing lots of runs no longer slowly use more memory over a long session.
- **[BUG FIX]** Sliders on the Settings pages show their current number again instead of a blank readout.

## 1.1.1

A quiet maintenance release - no changes to scoring or to how anything looks. Under the hood, add-on presence checks (Details!, the Encounter Journal) now use the current `C_AddOns` API directly instead of a legacy fallback.

- **[CHANGE]** Uses the modern `C_AddOns` API directly for add-on checks. No functional change.

## 1.1.0

The platform's new **two-tier navigation** plus a big **scoring pass**: item level now factors into throughput, healers get full credit on a clean key, death causes are smarter, and a new **Scoring Guide** explains the whole model. Every scoring change below **re-scores your existing runs automatically** on login.

### Scoring

- **[NEW]** **Scoring Guide - how every run is graded.** A new read-only **Scoring Guide** page (under Mythic Ledger) lays out the whole model in plain language: the 5 metrics and their weights, the real-world factors (your gear, spec, the dungeon, and your group), the guardrails that stop a teammate over-performing from hurting your score, and the grade ladder - all pulled live from the engine, so it always matches your real scores.
- **[CHANGE]** **Item level now shapes your damage bar.** Throughput is the one place gear genuinely changes output, so your expected damage is nudged by your item level versus the group average (bounded, about 1% per item level). The **lowest-geared player isn't punished** for output their gear can't reach, and out-gearing the group no longer reads as skill. Applies only when most of the party's item level is known.
- **[CHANGE]** **Healers get full credit on a clean key.** Time the key with no deaths and your healing was enough by definition, so the **healing half** of your throughput is lifted to full marks instead of being marked down when the group self-covered its own damage. It scales with deaths (a messy run earns less of the lift) and **never lowers** a score.
- **[NEW]** **New S+ grade.** A flawless run - every metric that applied to you a perfect 100 - now earns an **S+**, one tier above S.
- **[CHANGE]** **Smarter death causes.** The **killing blow** now decides why you died: a fatal hit that was avoidable, **environmental** (fall / lava / fire - now counted as your own fault), a **melee** hit taken as a non-tank (lost threat), or an **un-kicked cast** (missed kick) is labeled by that hit, even when earlier chip damage was something else.
- **[CHANGE]** **Fairer dispels.** When the group already handled the one or two dispels a fight offered, a spec with only a tiny fair share is no longer scored a zero for it. Skyreach no longer expects a healer to cleanse a debuff that isn't there (its dispellable content is enemy buffs), and **Restoration Druids** are now credited for **Soothe**.
- **[CHANGE]** **Long-cooldown interrupts get a pass.** A spec with a long-cooldown kick (Solar Beam, Quell, Shadow's Silence...) is no longer docked when the group already covered the run's kicks and nobody died to a missed one - with a note that it's still worth pressing when you can.
- **[NEW]** **Tanks see loose-mob deaths.** A tank's review now flags teammate deaths that came from a mob it lost or never had threat on - shown for awareness, **not** part of the score.

### Navigation & pages

- **[NEW]** **Every page is now a sidebar row.** Summary, Runs, Dungeons, Characters, Players, Bests, Settings and Debug live in the left sidebar under the **Mythic Ledger** category (with the Dungeon Guide and Scoring Guide) instead of an in-body tab strip. Opening a run, player, dungeon or the player review still happens in place, and Back returns where you came from.
- **[CHANGE]** **"Overview" is now "Summary."** The Mythic Ledger landing page is renamed so it no longer clashes with the platform's own Overview.
- **[NEW]** **Filter and sort the Runs list.** New filter toolbar - **Season, Result, Character, Dungeon, Key level** and **Role** - plus **DPS and HPS in their own sortable columns**, with the result shown inline with the season.
- **[NEW]** **Filter Players by class and spec.** The Players page adds **Class** and **Spec** dropdowns beside the Role and Favorites filters.
- **[CHANGE]** **Settings, reorganized into sub-tabs.** The two-column Settings grid is replaced by in-body sub-tabs - **Appearance, Tooltips, Scoreboard, Death Report, Tracking, Regroup** and **Misc** - each full-width with its own heading. Tooltips gets a **Hover Me** preview, Scoreboard column pickers expand to fit, and Death Report / Regroup use two columns with proper section headers.
- **[CHANGE]** **"Recap" is now "Regroup."** The returning-player tab is renamed (it's about grouping up again, not a run summary); its unused **Detail** dropdown is gone, and the death report's on switch is now **Enable Death Report** under **Behavior**.
- **[BUG FIX]** **Run-history date column.** Widened the date column on the run-history tables so the date/time stamp no longer runs under the dungeon icon.

## 1.0.0-beta.8

**Missed Kick** deaths, a new on-screen **death report**, and an **avoidable-damage breakdown** with clearer, personalized coaching - building on beta.7's attribution. The scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Missed Kick is now its own death cause.** Death attribution adds a fourth cause alongside Avoidable, Threat, and Other: a **Missed Kick** - a cast that should have been interrupted landed and helped kill you - and it names the exact cast. It reads the death recap and weighs the *whole* sequence, so a kickable cast that dropped you gets the blame even when a normal hit lands the killing blow. Recomputed from each run's stored recaps, so it appears on runs you already have.
- **[CHANGE]** **Missed-kick deaths are scored like an "Other" death.** A death from a missed interrupt carries the same penalty as an unavoidable one - carved out of the old "Other" bucket, so the death count and its total weight are unchanged, only how each death is labeled.
- **[NEW]** **On-screen death report.** After a pull (or at the run's end), a customizable overlay flashes **who died since the last report and why** - the time in the key, the killing blow, and the cause (including a missed kick's cast). Turn it on in **Settings > Death Report**, where you can style the font, size, colors, an optional background panel, and position (drag-to-move with Save/Cancel), pick how it dismisses (auto-fade or **click to dismiss**), and choose whether it fires each pull or once at the finish. **/ledger deathreport** reposts the last one to party chat.
- **[NEW]** **Avoidable-damage breakdown on the score card.** The player review now lists the exact mechanics behind your Survival score - biggest first, each a real **spell icon** with the game's own hover tooltip, plus the damage taken, a share bar, and its share of your avoidable total. Reference only; it never changes the score.
- **[CHANGE]** **Clearer, personalized score explanations.** The "How your targets were set" box now sits **below** the coaching (What went well / Focus on), and every category is explained in plain language using **your own numbers** with a worked example. Survival and Deaths in particular now show your actual avoidable share and what each death cost, instead of a generic rule.
- **[BUG FIX]** **Scoreboard "Least Avoidable" leader fixed.** A player who took **no** avoidable damage (shown as "-") was skipped, so the crown went to someone who actually stood in something; a clean player is now correctly read as zero and credited.
- **[CHANGE]** **Settings page redesigned.** Settings now use a **two-column layout**, and the scoreboard **Scale** slider shows its numeric value again.
- **[BUG FIX]** **Interrupt cooldown-class labels corrected.** Several kicks were labeled in the wrong CD band: 15-second melee kicks (Kick, Pummel, Mind Freeze, Disrupt, Skull Bash, Spear Hand Strike, Rebuke) now read **Short-CD**, and 24-second ranged kicks (Counter Shot, Counterspell, Spell Lock) read **Standard**. Labels only - expected kick rates and grades are unchanged.

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
  organized by character.
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
