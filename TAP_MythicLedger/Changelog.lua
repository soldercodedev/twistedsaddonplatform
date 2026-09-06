-- TAP: Mythic Ledger - Changelog.lua
-- In-game "What's New" text (parsed by the suite: `## version`, `### sub`, `- **[TAG]** text`).
local ADDON, ML = ...

ML.CHANGELOG = [==[
# Mythic Ledger - What's New

## 1.4.0

Season 2 utility expectations re-measured, and settings are now per profile.

- **[CHANGE]** Season 2 utility expectations were re-measured against logged runs. Every dungeon's trash interrupt rate came down, by 10% to 40%: a median group was landing only 61-85% of the modelled kick supply, so a completely ordinary run was being marked down for it.
- **[BUG FIX]** That over-statement was being hidden, unevenly. Interrupt supply is capped at your group's own kick capacity, and at the old rates that cap was doing the work in 85% of runs - so how harshly you were graded depended on your group's composition rather than on the dungeon. A group with plenty of kickers was measured against a number no group reaches; a group with few was quietly capped back to something fair. Kings' Rest, Voidscar Arena and Temple of Sethraliss are where it bit hardest, and their interrupt scores rise 11 to 13 points.
- **[CHANGE]** Dispel rates moved both ways and by less, since they were already close: Voidscar Arena +36%, Murder Row +32% and Altar of Fangs +22%, everything else in single digits.
- **[BUG FIX]** Voidscar Arena's biggest cleanse, Corrosive Essence, was missing from the dungeon data altogether, so the dungeon looked as though it had almost no poison to remove: healers were graded against a nearly empty requirement and dispel-capable damage dealers were not graded on dispels there at all. It counts now, and Voidscar Arena is the only dungeon this moves.
- **[BUG FIX]** Four dispels that groups clear constantly were graded as optional, and now count: Cold Claws and Rolling Thunder (Ruby Life Pools), Serpent Strike (Kings' Rest) and Insatiable Hunger (Den of Nalorakk). Den of Nalorakk carried no curse requirement at all, so anyone whose only dispel was a decurse went ungraded on dispels there.
- **[NEW]** Three more dispels are named in the Dungeon Guide without counting toward your score, because groups clear them too rarely to be expected to: Mind-Numbing Poison and Mother's Wrath, plus Murder Row's Fel Crazed.
- **[NEW]** Five casts that groups routinely kick were missing from the Dungeon Guide and are now listed: Shadowbolt Volley (Voidscar Arena), Storm Bolt (Ruby Life Pools), Shadow Bolt (Kings' Rest), Doom Bolt (Murder Row), and the Uncoiled Writhe's copy of Toxic Atrophy in Altar of Fangs. Listing them does not change any score.
- **[CHANGE]** Death Report and Live Coach settings are per profile now, and both overlays are placed through the platform's Movers page. Your run history, player notes and personal bests are account-wide and are never part of a profile.
- **[NOTE]** Existing runs re-score on login. The average overall score moves by well under a point, and about one player in ten shifts by a single letter grade, almost always upward.

## 1.3.0

Midnight Season 2 is fully supported - the Dungeon Guide, kick/dispel expectations, and the review's dispel coaching all know the new pool, and every guide entry now explains why it matters. Saved data is much smaller, with one control for how long runs keep their full detail and Keep flags for the ones you want left alone. Plus a Live Coach that nudges you between fights, week-over-week stats, a Great Vault tracker, and a new Progression page. Scoring picks up one fix too: a run is graded against its own season's data again. Your existing runs re-score on login.

- **[CHANGE]** Saved data is about **35% smaller**. Every run stored the full talent list of all five players twice over, and nothing read it. Those lists are gone and are no longer recorded - roughly 4 MB back on a large history.
- **[NEW]** **Run History** (Settings > Tracking) is one control for how long a run keeps full detail - all runs, the current season, the current expansion, or a number of days - and what happens after that: **trim** it or **delete** it. Trimming keeps the run, so its date, key, result, party, your numbers, score and grade all stay and it still appears in every list and chart. It drops only the deep review detail: death recaps, per-spell breakdowns and the combat timeline, about 87% of a run's size. Nothing changes until you press Apply. A per-season table shows what each season costs, with its own Trim button.
- **[NEW]** A trimmed run's score is **frozen**, so a later change to the scoring engine cannot rewrite grades already in your history.
- **[NEW]** **Keep** flags. Lock a run to hold its full detail, or lock a **player** to protect their record and every run they appear in. A locked run is never trimmed or deleted, whatever the policy says.
- **[BUG FIX]** A run is scored against **its own season's** dungeon data again. When Season 2 began, every Season 1 run started resolving against the Season 2 profile, which does not list Season 1's dungeons - so those runs were graded as if their dungeons had no interrupts or dispels to handle at all, and their expectations collapsed. Season 1 runs use Season 1 data, Season 2 uses Season 2, and a run recorded before seasons were tagged falls back to the profile that actually lists its dungeon. Your existing runs re-score on login.
- **[NEW]** **Midnight Season 2**: Altar of Fangs, Den of Nalorakk, Kings' Rest, Murder Row, Ruby Life Pools, Temple of Sethraliss, The Blinding Vale, and Voidscar Arena all have a full kick/dispel catalog in the Dungeon Guide and interrupt/dispel scoring expectations calibrated from real Season 2 runs. Season 1 keeps its own profile for your history.
- **[NEW]** The Dungeon Guide explains **why** - each spell's tooltip carries its justification: the mechanic plus the observed evidence ("killing blow on the healer at +8", "removed 67% of applications"), with key numbers highlighted, hard warnings in orange, a skull on death evidence, per-school colors on dispel types, and a green check on dispels that count toward your score.
- **[NEW]** The run review's "what you could have dispelled" coaching covers the Season 2 dungeons.
- **[NEW]** **Live Coach** - an on-screen nudge between fights. After a boss (or big pulls too, your call) it checks how the run is going and tells you the one thing to fix: "Kick more", "Cut avoidable damage", "Push your DPS". It grades with the same engine as your end-of-run score, so the advice matches your final grade - the real score still comes at the end. Off by default; turn it on in Settings > Live Coach, where you pick how often it speaks, how much it says, and how it looks. /tap ml coach tests it.
- **[NEW]** The Overview has a **This Week** row - runs, timed %, average score, and deaths, each compared to last week. Shows up once you have two weeks of history.
- **[NEW]** **Trouble Spots**, also on the Overview: the dungeons that keep beating you, ranked by fail rate and deaths.
- **[NEW]** The Characters page now starts with a **Weekly Vault** panel - every character's top 8 keys this week, with the three vault slots marked and the reset timer. Depleted keys count too, same as the vault itself.
- **[NEW]** A new **Progression** page charts a character's trajectory across their runs. Pick a metric - Ledger Score, Key Level, Time vs timer, Deaths, DPS or HPS - and read it as a line with an average line and an Improving / Steady / Regressing call, with Latest / Min / Max / Average cards above it. Switch between a per-run and a weekly view, and narrow to a date range and/or a key-level range.
- **[CHANGE]** The season filter names seasons by expansion ("Midnight Season 2" instead of "Season 18"), labels the current one, and derives the names so future seasons title themselves correctly.

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
