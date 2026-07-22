# Twisteds Addon Platform - Changelog

Platform-level release notes. Each module also keeps its own in-game **What's New** (open `/tap` →
any module → *What's New*), and a `README.md` in its folder.

## 1.5.0-beta.1

A ground-up **navigation overhaul**. Each installed add-on now gets its own **category in the left sidebar**, and its pages live there as sub-items - so a feature-rich module's pages are discoverable at a glance instead of crammed into an in-body tab strip. Freeing that in-body top-nav lets a page carry its **own sub-tabs** (the Mythic Ledger Settings page is the first to use them). *(Beta: please report any navigation or rendering quirks.)*

**Platform**

- **[NEW]** **Two-tier sidebar navigation.** The old single "Modules" list is replaced by one **collapsible category per add-on** (Mythic Ledger, Combat Alerts, Focus Target Interrupt, Rotation Assistant), with each module's pages as sub-rows. Only the add-on you're in stays expanded (accordion), so the list stays tidy. The **Dungeon Guide** now sits inside the Mythic Ledger category, directly under **Overview**.
- **[NEW]** **Page-level sub-tabs.** With top-level nav in the sidebar, the in-body top-nav is free for a page's own tabs.
- **[CHANGE]** **Every module's tabs moved to the sidebar.** Combat Alerts (Alerts / Profiles / Settings), Focus Target Interrupt (Macros / Marker Palette / Announce / Settings), and Rotation Assistant (Behavior / Indicators / Appearance / Settings) now list their pages in the sidebar. Drill-downs (a run's details, a rule's editor) still open in-body over the page they came from. Deep links, minimap buttons and slash commands are unchanged.
- **[CHANGE]** **Overview is now one row per add-on** with its version as a **badge** (green for a stable release, blue for a beta), a colored **What's New** button, and a red **Disable** button. The old **Installed** page is gone - **enable/disable (live toggle) and Unload** now live on Overview, and the redundant enable toggle was removed from each module's own Settings.
- **[CHANGE]** **Consistent page headings everywhere.** Every page now carries the same title/description **Page Heading** style; the Platform *Appearance* page is renamed **Settings** and rebuilt on the **two-column grid**.

### Mythic Ledger (1.0.0-beta.9)

- **[NEW]** **All eight pages in the sidebar.** Overview, Runs, Dungeons, Characters, Players, Bests, Settings and Debug are now sidebar sub-rows under the **Mythic Ledger** category. Clicking a run/player/dungeon still opens its detail view in place, with Back returning where you came from.
- **[NEW]** **Runs list filters & sortable DPS/HPS columns.** Filter by **Season, Result, Character, Dungeon, Key level** and **Role**, with **DPS and HPS in their own sortable columns** and the result shown inline with the season.
- **[NEW]** **Players filters for Class and Spec**, beside the existing Role and Favorites filters.
- **[CHANGE]** **Settings, reorganized into sub-tabs.** The cramped two-column Settings grid is replaced by in-body sub-tabs - **Appearance, Tooltips, Scoreboard, Death Report, Tracking, Regroup** and **Misc** - each with its own heading below the tab bar and full-width, better described (Tooltips **Hover Me** preview, expanding Scoreboard pickers, two-column Death Report/Regroup with proper section headers, minimap toggle moved to Misc). The **Recap** tab is renamed **Regroup** (its unused Detail dropdown removed), and the death report's on switch is now **Enable Death Report** under Behavior.

### Focus Target Interrupt (1.1.0-beta.1)

- **[NEW]** **Announce by class/spec.** The Announce page adds a **Class / Spec** picker so focus and ready-check call-outs fire only while you're playing one of the chosen specs - leave it empty to announce on every character.

## 1.4.0

Death attribution grows a **Missed Kick** cause and an on-screen **death report**, the player review gains an **avoidable-damage breakdown** and plain-language target explanations, and the platform window is now **collapsible and resizable**. Each module's full notes also live in its in-game **What's New** (`/tap` > module > *What's New*).

**Platform**

- **[NEW]** **Collapsible sidebar.** A toggle at the bottom of the `/tap` sidebar shrinks the navigation to an icon-only strip (hover an icon for its name); the content area reflows to fill the freed space, and the collapsed state is remembered.
- **[NEW]** **Resizable window.** **Settings** gains **width** and **height** sliders, so you can size the `/tap` window to taste - alongside the existing menu-scale and maximize controls.

### Mythic Ledger (1.0.0-beta.8)

**Missed Kick** deaths, an on-screen **death report**, and a new **avoidable-damage breakdown** with clearer, personalized coaching. The scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Missed Kick is now its own death cause.** Death attribution adds a fourth cause: a **Missed Kick** - a cast that should have been interrupted landed and helped kill you - shown alongside Avoidable, Threat, and Other, naming the exact cast. It reads the death recap and weighs the whole sequence, so a kickable cast that dropped you gets the blame even when a normal hit lands the killing blow.
- **[CHANGE]** **Missed-kick deaths are scored like an "Other" death.** A death from a missed interrupt now carries the same penalty as an unavoidable one - carved out of the old "Other" bucket, so the death count and total weight are unchanged. Existing runs recompute this cause from their stored recaps on login.
- **[NEW]** **On-screen death report.** After a pull (or at the run's end), a customizable overlay flashes who died since the last report and why - time in the key, the killing blow, and the cause (including a missed kick's cast). Styleable font/size/colors/background/position (drag-to-move), **auto- or click-dismiss**, per-pull or once at the finish. **/ledger deathreport** reposts the last one to party chat.
- **[NEW]** **Avoidable-damage breakdown on the score card.** The player review now lists the exact mechanics behind your Survival score - biggest first, each a real **spell icon** (hover for the game's tooltip) with the damage taken, a share bar, and its share of your avoidable total. Reference only; it never changes the score.
- **[CHANGE]** **Clearer, personalized score explanations.** "How your targets were set" now sits **below** the coaching (What went well / Focus on), and every category is explained in plain language using **your own numbers** with a worked example - Survival and Deaths included, which now show your actual avoidable share and what each death cost.
- **[BUG FIX]** **Scoreboard "Least Avoidable" leader fixed.** A player who took **no** avoidable damage (logged as "-") was skipped, so the crown went to someone who actually stood in something; a clean player is now correctly read as zero and credited.
- **[CHANGE]** **Settings page redesigned.** The module's settings now use a **two-column layout**, and the scoreboard **Scale** slider shows its numeric value again.
- **[BUG FIX]** **Interrupt cooldown-class labels corrected.** Several kicks sat in the wrong CD band - 15-second melee kicks (Kick, Pummel, Mind Freeze, Disrupt, Skull Bash, Spear Hand Strike, Rebuke) now read **Short-CD**, and 24-second ranged kicks (Counter Shot, Counterspell, Spell Lock) read **Standard**. Labels only; expected kick rates and grades are unchanged.

## 1.3.0

Headlined by **Mythic Ledger beta.7** - death **attribution** (every death sorted into *why* it happened, driving a smarter death penalty) and per-spell **interrupt & dispel breakdowns** that show exactly what you kicked and cleared versus what the dungeon demanded. The platform window also links straight to the **website** now. Each module's full notes also live in its in-game **What's New** (`/tap` > module > *What's New*).

**Platform**

- **[NEW]** **Website link in the footer.** The `/tap` window footer now has a **Website** button next to Discord - it copies **https://tap.soldercode.dev/** (WoW can't open a browser directly).

### Mythic Ledger (1.0.0-beta.7)

Death **attribution** and per-spell **utility breakdowns**. The scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Death Causes.** Every death is now classified as **Avoidable** (you stood in something), **Threat** (unmitigated melee while you weren't tanking - pulled aggro, or the tank never picked it up), or **Other** (unavoidable). It reads the game's **death recap** and weighs the *whole* sequence, not just the killing blow - so a mechanic that dropped you to 10% is blamed even when a normal hit finishes you. Shown as a breakdown card on the player review.
- **[CHANGE]** **Deaths are scored by cause.** The Death penalty is no longer flat - an **avoidable** death costs the most, an **unavoidable** one less, and a **threat/aggro** death the least. The death count and its weight are unchanged; only how much each death costs. Runs recorded before this update keep the old flat penalty.
- **[NEW]** **Interrupt & dispel breakdowns.** The player review now shows **what you actually kicked and dispelled** grouped by the dungeon's priority tiers, plus the priority casts you didn't personally cover - dispels filtered to what your spec can really clear, with your clearing tool shown. **Click any spell to jump to it in the Dungeon Guide.**
- **[NEW]** **Item level & hero talent on the details page.** Each player's item level gets its own tile and their hero talent shows as an icon in the header.
- **[NOTE]** **Full per-spell run log.** Every run now records the complete per-spell breakdown for the whole party (damage/healing done, damage taken, avoidable, interrupts, dispels) plus death recaps - raw detail for future scoring and analysis. *(Captured now; most of it isn't shown yet.)*

## 1.2.0

A platform release headlined by **Mythic Ledger's** deepest scoring pass yet - healing is now graded against the damage your group actually took, dispels only count the real priorities - plus a brand-new **Dungeon Guide**. Each module's full notes also live in its in-game **What's New** (`/tap` > module > *What's New*).

### Mythic Ledger (1.0.0-beta.6)

The deepest scoring pass yet - **healing is now graded against the damage your group actually took**, **dispels only count the real priorities**, and there's a brand-new **Dungeon Guide**. Every scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Dungeon Guide.** A read-only journal of the season's **interrupt & dispel priorities**, dungeon by dungeon: which enemy casts to kick and which auras to dispel, ranked by tier, with the dispel type and the caster shown as a **live 3D model** when you click a spell. It's its own entry in the **/tap** menu under Modules - a reference, it doesn't affect scoring.
- **[CHANGE]** **Tanks & healers are graded on the damage the group actually took.** Instead of a share of the group's total HPS, tank and healer **Throughput** now measures healing **plus absorbs** against a target built from **unavoidable damage taken**: the tank is expected to self-cover a spec-based portion, the healer covers the rest of the group. Standing in **avoidable** damage now hits **that player's own Survival**, not the healer's target - so a healer isn't punished for a group that stands in the bad. Absorbs count toward output, so shield-heavy healers (Disc, Preservation) aren't shortchanged.
- **[CHANGE]** **Healing expectations tuned per tank spec, from 32 logged runs.** Guardian Druid and Prot Paladin self-cover **more** (Frenzied Regen / Word of Glory out-heal the old bar); Brewmaster covers **less** (Stagger's mitigation isn't visible to the meter, so Brew genuinely leans on the healer); the healer target was re-centered so both land where they should.
- **[CHANGE]** **Dispels only count what's actually a priority.** Each dungeon's dispel requirement now counts **only High/Must** dispels, so you're no longer docked for skipping low-value cleanses. We added the dungeon dispels the guides never named (Transference, Permeating Cold, Energy Bomb...), **gated out enemy buffs the group rarely removes** (trash enrages), and stacking DoTs (Rotting Strikes, Vilebranch Sting) now count **once per threshold**, not per stack.
- **[CHANGE]** **Long-cooldown interrupts expect fewer kicks.** A 45-60s interrupt is reasonably banked when the group already covers the casts, so long-CD specs (Shadow Priest, Balance Druid, Mage...) are no longer docked for holding it.
- **[NEW]** **Groundwork for gear- & build-aware scoring.** The start-of-run inspection now records each party member's **hero tree, talents, and item level** (shown on the details page) - the foundation for expectations that adjust to a player's class, spec, item level and build. *(Collected now; not yet driving scores.)*

## 1.1.1

A platform release rolling up the latest from every module. **Mythic Ledger** lands a major scoring accuracy pass plus two new features, and the other modules graduate to a stable **1.0**. Each module's full notes also live in its in-game **What's New** (`/tap` > module > *What's New*).

### Mythic Ledger (1.0.0-beta.5)

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

### Combat Alerts (1.0.0)

- **[CHANGE]** Out of beta - Twisteds Combat Alerts is now a stable 1.0 release.

### Focus Target Interrupt (1.0.0)

- **[CHANGE]** Out of beta - Focus Target Interrupt is now a stable 1.0 release.

### Rotation Assistant (1.0.0)

- **[CHANGE]** Out of beta - Rotation Assistant is now a stable 1.0 release.
- **[NOTE]** The on-screen cue reads keybinds from **Action Bars 1-5** only - the bars listed under
  Action Bars in the keybinding editor. Keys bound solely on third-party action-bar addons may not
  be picked up.

## 1.0.1

A big **Mythic Ledger** visual + scoring pass (module version 1.0.0-beta.4), plus a platform-wide
**per-module on/off** you can reach from any module's own Settings tab, and settings tidy-ups across
the other modules.

- **[BUG FIX]** **Mythic Ledger - Warlock interrupts now count.** Spell Lock fires from the Felhunter,
  so the meter filed those kicks under the **pet** (and a resummoned pet gets a new source id), dropping
  them - a Warlock's interrupts could read 0. Pet interrupts/dispels are now mapped back to the owner
  live during the run, and a pet/talent-gated interrupt a player couldn't use is scored **N/A**, not a
  zero. *(Fix is in but not yet confirmed in a live key.)*
- **[NEW]** **Enable/disable any module from its own page.** Every module's **Settings** tab now has a
  master on/off switch, and a module you switch off shows a clear **MODULE DISABLED** overlay on its
  other tabs (with a jump straight back to Settings) instead of a dead page. **Rotation Assistant** and
  **Focus Target Interrupt** gained a dedicated **Settings** tab for this - their minimap toggle moved
  there too.
- **[NEW]** **Mythic Ledger - run details, rebuilt.** A run's party and boss splits are now **hero
  cards** (spec portraits with the performance grade; boss cards fronted by their portrait), with a
  **run timeline** - in-combat vs downtime, each boss kill, deaths, and the **+1 / +2 / +3** timer
  targets - matching the end-of-run scoreboard.
- **[NEW]** **Mythic Ledger - "Timed +2".** Run results now show the **keystone upgrade** you earned
  on the Runs list, the run tooltip, and the run header, not just "Timed".
- **[CHANGE]** **Mythic Ledger - player pages** now match the character page: **Specs Played** and
  **Dungeons Together** are the same hero cards, with the same reflowing headline tiles.
- **[CHANGE]** **Mythic Ledger - interrupt scoring** reweighted so the tiers (long-CD / standard /
  short-CD / high-control) split the expected kick volume **10 / 20 / 30 / 40** - higher-control kits
  are expected to carry more.
- **[CHANGE]** **Mythic Ledger - scoring weights are now static and uniform across roles.** Every role
  is graded **Throughput 35% · Interrupts + Dispels 25% · Survival 20% · Death Impact 20%**. The two
  utility categories share the 25% evenly when both apply; if a spec only has one (or the dungeon has
  nothing for it), the whole 25% stays on the one it can affect. **Role Contribution is retired to 0%**
  for now (its targets can be tuned later). Your saved runs are automatically rescored.
- **[CHANGE]** **Mythic Ledger - Survival and Death Impact always weigh the same.** Each role's
  Survival and Death Impact category carries exactly equal weight - and stays equal even when a utility
  category (interrupts / dispels) doesn't apply and its weight is redistributed - so avoiding damage and
  not dying always count equally toward your grade.
- **[NEW]** **Mythic Ledger - timestamps show the time of day.** Every run date now shows the local
  time next to it, with a new **Date & Time** setting to choose the date format (NA `mm/dd/yy`, ISO, or
  EU) and a 12- or 24-hour clock.
- **[CHANGE]** **Mythic Ledger - a clean run scores full Survival.** If you took **no avoidable damage**
  on a tracked run, that now counts as a true 0% avoidable share (a perfect Survival score) rather than
  a neutral "no data" estimate.
- **[NEW]** **Mythic Ledger - fairer dispel scoring.** Researched against Midnight's talent trees:
  almost every DPS/tank dispel is a **talent**, not baseline - Consume Magic, Remove Corruption,
  Cauterizing Flame, Tranquilizing Shot, Remove Curse, Detox, Cleanse Toxins, Purify Disease, Cleanse
  Spirit, Singe Magic (only Rogue's Shiv is baseline). The ledger talent-inspects the party at the start
  of a run; a member who never specced their dispel (and cast none) is scored **N/A**, not penalized,
  and their review names the ability they could talent.
- **[NEW]** **Mythic Ledger - scoreboard "vs your best".** The end-of-run scoreboard shows your time
  against your best for that exact **dungeon + character + spec + key level** - a new best, how far off
  you were, or your first timed clear. The party table also shows **per-stat deltas** (DPS, HPS, damage
  taken, deaths, interrupts, dispels, avoidable) next to your row **and next to any teammate you've run
  this key with before** - each compared to that player's OWN best run of this key (matched by character
  + spec, from your saved history).
- **[NEW]** **Mythic Ledger - `/tap changekey`.** Arms a one-shot reminder that pops over your next
  run's scoreboard to change your keystone.
- **[BUG FIX]** **Mythic Ledger - recap spam.** The returning-player recap no longer toasts your whole
  group at the end of a run.
- **[BUG FIX]** **Mythic Ledger - scoreboard timeline labels** (0:00 / total time) no longer tuck
  under the footer buttons.
- **[BUG FIX]** **Mythic Ledger - utility scoring.** Meeting your **interrupt / dispel target** now
  scores full even on a low-sample ("Limited") run - a met target was being dragged toward the neutral
  score (e.g. **93** instead of 100). Low confidence now only lifts a weak showing toward neutral; it
  never docks a target you actually hit.
- **[BUG FIX]** **Mythic Ledger - runs that finish on trash now capture stats.** When the **last boss
  didn't complete the key** (you were short on enemy forces and went back to clear trash), the run was
  saved while you were still in combat - and the Midnight meter only reads out of combat, so the final
  DPS/HPS/interrupt/dispel numbers came back empty. Finalization now waits for combat to actually drop
  before reading the meter. Boss splits were always captured correctly; this fixes the run totals.

### Modules

- **[CHANGE]** **Combat Alerts - Settings reorganized** into **Sound**, **Performance**, **Backup &
  Data**, and **Minimap** sections, and the **Alerts** tab now names the **active profile** (shared
  account-wide vs private to this character) and how many alerts it holds.

## 1.0.0-beta.3

Third beta. A big visual + accuracy pass on **Mythic Ledger**, plus a round of platform appearance
fixes that every module inherits. Each module also lists its own changes in its in-game **What's
New** (`/tap` → module → *What's New*).

- **[CHANGE]** **Mythic Ledger - hero-card pages.** The character overview's **By Spec** and **By
  Dungeon** breakdowns are now rich hero cards (class-colored spec cards with spec icons; dungeon
  is a hero-card grid with a **type-to-filter** box (3+ letters) beside the season selector.
- **[BUG FIX]** **Mythic Ledger - boss icons** now load on the post-run scoreboard and on
  previously-recorded runs (they were blank until the Encounter Journal was queried correctly), and
  the dungeon background art now covers the whole scoreboard.
- **[BUG FIX]** **Mythic Ledger - average deaths** now count only **your** deaths per run (it was
  averaging the entire party). The Runs page still reports total party deaths.
- **[CHANGE]** **Mythic Ledger - scoring.** Interrupts and dispels were rescored for Midnight:
  per-spec interrupt cooldowns corrected, and DPS/tanks are now credited for the dispels they bring
  (healers aren't the only ones expected to dispel).
- **[BUG FIX]** **Appearance.** Custom theme colors now save correctly from the color picker; the
  **Menu scale** slider is smoother to drag (it applies when you release it); table tooltips render at
  the cursor; there's more room under the per-page dropdown; and check-box labels no longer wrap.
- **[BUG FIX]** Fixed a Lua error when opening a run's player scores, and fixed party cards
  overlapping their section header.

### Modules

- **[CHANGE]** **Tabbed layouts.** **Combat Alerts**, **Focus Target Interrupt**, and **Rotation
  Assistant** each moved from one long scrolling page to a docked **tab strip** under the title bar
  (e.g. Combat Alerts → Alerts / Profiles / Settings), matching Mythic Ledger. Same options, faster to
  navigate. All three also pick up the shared appearance fixes above.

## 1.0.0-beta.2

Second beta. A brand-new module (Mythic Ledger), a platform look & feel overhaul, and a round of
updates to the modules that already shipped in beta.1. Each module also lists its own changes in its
in-game **What's New** (`/tap` → module → *What's New*).

- **[NEW]** **Mythic Ledger** - a new, private, account-wide Mythic+ journal. It records every timed,
  depleted, or abandoned key automatically (sorted by character), remembers who you've run keys with,
  and can give a short, **private** heads-up when you group with them again. Every run is **graded** -
  an easy-to-read, fair score for each player covering damage & healing, interrupts, dispels, staying
  out of the bad stuff, and deaths - and clicking a player opens a full **review**: their key stats, a
  breakdown of how the grade was earned, and plain-language tips on what they did well and what to
  work on. Plus run/dungeon/character/player pages, personal bests, per-boss stats, a post-run
  scoreboard, and easy backup & sharing. Stats come from the game's own damage meter (with the basics
  still tracked if it isn't available).
- **[NEW]** **Appearance, reworked.** In `/tap` → Settings the look is now two independent choices:
  a **shape** (sharp / rounded) and a **color scheme** - a neutral greyscale ramp (Obsidian,
  Graphite, Nickel…), **light** themes (Daylight, Parchment), the styled set (Modern/Blizzard/Neon),
  or a WoW-**expansion** palette - plus a full **Custom** editor for every color. Add a **Menu
  scale** slider to size the whole window.
- **[CHANGE]** **Cleaner module pages** - a selected module's name now shows in the window title
  instead of a repeated in-page header, leaving more room for its settings.
- **[BUG FIX]** Dropdown/menu backgrounds and text now follow the theme on a live swap (fixes stale
  colors on the light themes); shape changes apply to every widget.
- **[CHANGE]** Consistent branding: every add-on shows the shared platform logo and a `Twisteds …`
  name in the AddOns list.
- **[KNOWN]** Mythic Ledger targets Retail Midnight; some live meter/API details are still being
  verified in game. Metrics the meter can't supply show as "-", never a fake zero.

### Updates to existing modules

- **Combat Alerts** - **per-character alert profiles** (switch a character between Account-wide and
  This character in the Profile section, so alerts are no longer shared across all your toons);
  spell/item **Find** search (spellbook, auras, gear, bags, and the game database) with a live icon;
  fixed slider spacing in the alert editor.
- **Rotation Assistant** - `/tap rotation` and `/rcue` slash commands; the cue now follows your
  chosen Platform font.
- **Focus Target Interrupt** - the marker bar now remembers your **saved focus marker** (set it out
  of combat with a chat confirmation; in combat it just marks your target).

## 1.0.0-beta.1

First public release of the platform. Everything ships as one download.

- **[NEW]** **Twisteds Addon Platform** - a single hub (`/tap`) that hosts every tool under one
  shared look, with live on/off toggles per module and a built-in "What's New" for each.
- **[NEW]** **Combat Alerts** - build your own rule-based audible & visual cues (no target, out of
  range, aggro, pet down, item ready). Includes a spell/item search backed by an optional bundled
  database. *(Grew out of the standalone "Twisteds Combat Cues".)*
- **[NEW]** **Focus Target Interrupt** - one-key focus + mark macro, an on-screen raid-marker bar
  (movable, resizable, recolorable, row or column), and auto-detected interrupt/stun macros for
  your spec and talents.
- **[NEW]** **Rotation Assistant** - draws the keybind of Blizzard's suggested next ability on
  screen (show-only), with cast-vs-instant, GCD sweep, out-of-range, and out-of-resource indicators.
- **[NEW]** **TAP&#95;GameDB** - an optional, load-on-demand spell/item name database, loaded
  centrally by the platform only when a search needs it.

### Notes

- **[CHANGE]** The old standalone *Twisteds Combat Cues* has been split into two focused modules -
  **Combat Alerts** and **Focus Target Interrupt** - and rebuilt on the shared platform UI.
- **[CHANGE]** Alert **group-range** checks are hidden: Blizzard's API changes make them unreliable
  across all content, so alerts prefer a spell-range check to your target instead.
- **[KNOWN]** Exported alert strings from the old add-on still import (the `TCCX1!` format is
  accepted).
