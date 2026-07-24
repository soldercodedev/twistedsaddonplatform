-- TAP: Mythic Ledger - Changelog.lua
-- In-game "What's New" text (parsed by the suite: `## version`, `### sub`, `- **[TAG]** text`).
local ADDON, ML = ...

ML.CHANGELOG = [==[
# Mythic Ledger - What's New

## 1.1.2

Hunter Feign Death is no longer miscounted as a death, plus display and housekeeping fixes.

- **[BUG FIX]** A Hunter's Feign Death no longer counts as a real death, so hunters aren't penalized for feigning. Your existing runs are corrected on login.
- **[BUG FIX]** The run lists on the Characters and Dungeons pages were missing their column headers. They're back, and now sortable by date, key, time, deaths or DPS/HPS.
- **[BUG FIX]** The Dungeon Guide's caster preview shows on the first click instead of staying blank until you click away and back.
- **[BUG FIX]** The scoreboard and browsing lots of runs no longer slowly use more memory over a long session.
- **[CHANGE]** The group-utility tiles in the run review use the same color per dispel school as the Dungeon Guide.

## 1.1.1

A quiet maintenance release - no changes to scoring or to how anything looks. Under the hood, add-on presence checks (Details!, the Encounter Journal) now use the current C_AddOns API directly instead of a legacy fallback.

- **[CHANGE]** Uses the modern C_AddOns API directly for add-on checks. No functional change.

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

- **[NEW]** **Missed Kick is now its own death cause.** Death attribution adds a fourth cause alongside Avoidable, Threat, and Other: a **Missed Kick** - a cast that should have been interrupted landed and helped kill you - and it names the exact cast. It reads the **death recap** and weighs the *whole* sequence, so a kickable cast that dropped you gets the blame even when a normal hit lands the killing blow. Recomputed from each run's stored recaps, so it appears on runs you already have.
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

- **[NEW]** **Run details, rebuilt.** Opening a run now shows the party and boss splits as **hero
  cards** - spec portraits with the performance grade, and boss cards fronted by their Encounter
  Journal portrait - plus a **run timeline** (in-combat vs downtime, each boss kill, deaths, and the
  **+1 / +2 / +3** timer targets), the same one the end-of-run scoreboard uses.
- **[NEW]** **Key timing at a glance.** Results now read **"Timed +2"** - the keystone upgrade you
  earned - on the Runs list, the run tooltip, and the run header, not just "Timed".
- **[NEW]** **Player pages match character pages.** A party member's page now shows **Specs Played**
  and **Dungeons Together** as the same hero cards as your own character page, with the same reflowing
  headline tiles.
- **[CHANGE]** **Interrupt expectations reweighted.** The interrupt tiers (long-CD / standard /
  short-CD / high-control) now split the expected kick volume **10 / 20 / 30 / 40**, so higher-control
  kits are expected to carry more of the group's interrupts.
- **[CHANGE]** **Scoring weights are now static and the same for every role.** Every player is graded
  **Throughput 35% · Interrupts + Dispels 25% · Survival 20% · Death Impact 20%**. Interrupts and
  dispels share the 25% evenly when both apply; if you only have one (or the dungeon has nothing for
  the other), the whole 25% stays on the one you can affect. **Role Contribution is retired to 0%** for
  now. Your saved runs are rescored automatically.
- **[CHANGE]** **Survival and Death Impact always weigh the same.** Each role's Survival and Death
  Impact category carries exactly equal weight - and stays equal even when a utility category
  (interrupts / dispels) doesn't apply and its weight is redistributed - so avoiding damage and not
  dying always count equally toward your grade.
- **[CHANGE]** **A clean run scores full Survival.** If you took **no avoidable damage** on a tracked
  run, that now counts as a true 0% avoidable share (a perfect Survival score) instead of a neutral
  "no data" estimate.
- **[NEW]** **Run times show the time of day.** Every run date now shows the local time next to it. A
  new **Date & Time** setting picks the date format (NA `mm/dd/yy`, ISO, or EU) and a 12- or 24-hour
  clock.
- **[NEW]** **Turn the ledger off from its own page.** The **Settings** tab has a master on/off; a
  disabled ledger shows a clear **MODULE DISABLED** notice on the other tabs and keeps all your saved
  history.
- **[BUG FIX]** Scoreboard **timeline labels** (0:00 / total time) no longer tuck under the footer
  buttons.
- **[BUG FIX]** **Meeting your interrupt / dispel target now scores full marks** even on a low-sample
  ("Limited") run. A met target was being pulled down toward the neutral score - e.g. hitting your
  expected dispels read **93** instead of 100. Low confidence now only ever helps (it lifts a weak
  showing toward neutral), never docks a target you actually met.
- **[NEW]** **Fairer dispel scoring.** In Midnight almost every DPS/tank dispel is a **talent**, not
  baseline - Consume Magic, Remove Corruption, Cauterizing Flame, Tranquilizing Shot, Remove Curse,
  Detox, Cleanse Toxins, Purify Disease, Cleanse Spirit, Singe Magic (only Rogue's Shiv is baseline).
  The ledger now checks each teammate's talents at the start of your run: if they never specced their
  dispel (and cast none), their **Dispels** score is marked **N/A** instead of docking them for a tool
  they don't have - and their review names the ability they could have talented.
- **[NEW]** **Scoreboard: how this run compares.** The end-of-run scoreboard now shows your time versus
  your **best for this exact key** (same dungeon, character, spec and key level) - a new best, how far
  off you were, or your first timed clear. The party table also shows **per-stat deltas** (DPS, HPS,
  damage taken, deaths, interrupts, dispels, avoidable) next to your name - and next to any **teammate
  you've run this key with before** - each compared to that player's own best run of it.
- **[NEW]** **Change-key reminder.** Type **/tap changekey** and, after your next run's scoreboard, a
  reminder pops up over it to slot your next keystone. One-shot, and it survives a reload.
- **[BUG FIX]** Fixed the returning-player recap toasting your **whole group** at the end of a run
  (saving the run briefly made everyone look like a returning player).
- **[BUG FIX]** The **Dungeons filter box** could linger on top of another module's page after you
  left the ledger while on the Dungeons tab. It now hides as soon as you navigate away.
- **[CHANGE]** Removed the **Inspect group (dispels)** button from the Debug page - talent-gated
  dispels are already confirmed automatically at the start of each run, so the manual diagnostic
  isn't needed.

## 1.0.0-beta.2

- **[NEW]** **Hero-card pages.** The character overview's **By Spec** and **By Dungeon** breakdowns
  are now rich hero cards - class-colored spec cards with spec icons, and dungeon cards fronted by
  their own art - and the headline stats are large-icon tiles.
- **[NEW]** The **Dungeons** tab is a hero-card grid with a **type-to-filter** box (start typing 3+
  letters) next to the season selector.
- **[BUG FIX]** **Boss icons** now load on the post-run scoreboard and on runs you recorded earlier
  (they stayed blank until the Encounter Journal was queried correctly), and the dungeon background
  art now covers the whole scoreboard.
- **[BUG FIX]** **Average deaths** now count only **your** deaths per run - it was averaging the
  whole party. The Runs page still shows total party deaths.
- **[CHANGE]** **Interrupts & dispels rescored for Midnight:** per-spec interrupt cooldowns were
  corrected, and DPS/tanks now get credit for the dispels they bring (healers aren't the only ones
  expected to dispel).
- **[CHANGE]** The performance tooltip's score breakdown is easier to read.
- **[BUG FIX]** Fixed a Lua error when opening a run's player scores, and fixed party cards
  overlapping their section header.
- **[NEW]** Data retention is now a policy: keep **All seasons**, the **current season**, or the
  **current expansion**, with an optional cap on the newest N runs (0-10000). "**Never remove a top
  run**" protects your best key per dungeon, your top 10, and your crowned runs. Nothing is deleted
  until you click **Apply**, and Settings shows how many runs you currently have stored.
- **[NEW]** Settings previews: a live **stat-tile** preview in your chosen style, an in-window
  **recap preview**, and a **Launch test scoreboard** button so you can see your scale, font, tile
  style and sound without waiting for a real run.
- **[NEW]** Pick the **sound channel** (Master / Sound FX / Music / Ambience / Dialog) separately for
  the scoreboard sound and the recap sound.
- **[CHANGED]** Export / Import were removed from Settings - the dataset is large enough that pasting
  export strings around risked instability. Use Data Retention and Delete All History to manage data.

## 1.0.0-beta.1

- **[NEW]** First beta of Mythic Ledger - a private, account-wide Mythic+ journal. Every timed,
  depleted, or abandoned key you run is saved automatically, sorted by character.
- **[NEW]** It remembers everyone you've run keys with and can give you a short, private heads-up
  when you group with one of them again.
- **[NEW]** Every run is graded - an easy-to-read, fair score for each player covering damage &
  healing, interrupts, dispels, staying out of the bad stuff, and deaths. What's expected of you
  fits your spec (a short-cooldown kicker is expected to interrupt more than a long-cooldown one),
  missing info counts as neutral instead of a zero, and a teammate doing more never lowers your score.
- **[NEW]** Click any player (on a run or the scoreboard) to open a full review: their key stats, a
  breakdown of how the grade was earned and what they were measured against, and plain-language tips
  on what they did well and what to work on.
- **[NEW]** Per-boss stats (top damage/healing and your own damage on the kill), a post-run
  scoreboard, and pages for Runs, Dungeons, Characters, Players, and Personal Bests.
- **[NEW]** Picks up where it left off after a reload or disconnect, and you can back up or share
  your history with export & import.

### Notes

- **[KNOWN]** Some stats depend on the game's damage meter. Anything it can't supply shows as "-"
  instead of a fake zero.
- **[KNOWN]** All history is stored on your computer and is private to you. The heads-up about
  returning players is never posted to party, raid, instance, or guild chat.
]==]
