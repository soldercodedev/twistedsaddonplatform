-- TAP - Changelog.lua
-- The platform's in-game "What's New" text, shown on the Help > Changelog page. Mirrors the root
-- CHANGELOG.md (kept in sync by hand, same as each module's Changelog.lua mirrors its CHANGELOG.md).
-- Parsed by the Suite Manager: `## version`, `### sub`, `**Platform**`, `- **[TAG]** text`.
local ADDON, UIF = ...
local Suite = _G.TAP

Suite.CHANGELOG = [==[
# Twisteds Addon Platform - Changelog

## 1.5.0-beta.1

A ground-up navigation overhaul. Each installed add-on now gets its own category in the left sidebar, and its pages live there as sub-items - so a feature-rich module's pages are discoverable at a glance instead of crammed into an in-body tab strip. Freeing that in-body top-nav lets a page carry its own sub-tabs (the Mythic Ledger Settings page is the first to use them). (Beta: please report any navigation or rendering quirks.)

**Platform**

- **[NEW]** **Two-tier sidebar navigation.** The old single "Modules" list is replaced by one collapsible category per add-on (Mythic Ledger, Combat Alerts, Focus Target Interrupt, Rotation Assistant), with each module's pages as sub-rows. Only the add-on you're in stays expanded (accordion), so the list stays tidy. The Dungeon Guide now sits inside the Mythic Ledger category, directly under Overview.
- **[NEW]** **Page-level sub-tabs.** With top-level nav in the sidebar, the in-body top-nav is free for a page's own tabs.
- **[CHANGE]** **Every module's tabs moved to the sidebar.** Combat Alerts (Alerts / Profiles / Settings), Focus Target Interrupt (Macros / Marker Palette / Announce / Settings), and Rotation Assistant (Behavior / Indicators / Appearance / Settings) now list their pages in the sidebar. Drill-downs (a run's details, a rule's editor) still open in-body over the page they came from. Deep links, minimap buttons and slash commands are unchanged.
- **[CHANGE]** **Overview is now one row per add-on** with its version as a badge (green for a stable release, blue for a beta), a colored What's New button, and a red Disable button. The old Installed page is gone - enable/disable (live toggle) and Unload now live on Overview, and the redundant enable toggle was removed from each module's own Settings.
- **[CHANGE]** **Consistent page headings everywhere.** Every page now carries the same title/description Page Heading style; the Platform Appearance page is renamed Settings and rebuilt on the two-column grid.
- **[NEW]** **This Changelog page.** The platform's release notes now live under Help, right here.

### Mythic Ledger (1.0.0-beta.9)

- **[NEW]** **All eight pages in the sidebar.** Overview, Runs, Dungeons, Characters, Players, Bests, Settings and Debug are now sidebar sub-rows under the Mythic Ledger category. Clicking a run/player/dungeon still opens its detail view in place, with Back returning where you came from.
- **[NEW]** **Runs list filters & sortable DPS/HPS columns.** Filter by Season, Result, Character, Dungeon, Key level and Role, with DPS and HPS in their own sortable columns and the result shown inline with the season.
- **[NEW]** **Players filters for Class and Spec**, beside the existing Role and Favorites filters.
- **[CHANGE]** **Settings, reorganized into sub-tabs.** The cramped two-column Settings grid is replaced by in-body sub-tabs - Appearance, Tooltips, Scoreboard, Death Report, Tracking, Regroup and Misc - each with its own heading below the tab bar and full-width, better described. The Recap tab is renamed Regroup (its unused Detail dropdown removed), and the death report's on switch is now Enable Death Report under Behavior.

### Focus Target Interrupt (1.1.0-beta.1)

- **[NEW]** **Announce by class/spec.** The Announce page adds a Class / Spec picker so focus and ready-check call-outs fire only while you're playing one of the chosen specs - leave it empty to announce on every character.

## 1.4.0

Death attribution grows a Missed Kick cause and an on-screen death report, the player review gains an avoidable-damage breakdown and plain-language target explanations, and the platform window is now collapsible and resizable. Each module's full notes also live in its in-game What's New.

**Platform**

- **[NEW]** **Collapsible sidebar.** A toggle at the bottom of the /tap sidebar shrinks the navigation to an icon-only strip (hover an icon for its name); the content area reflows to fill the freed space, and the collapsed state is remembered.
- **[NEW]** **Resizable window.** Settings gains width and height sliders, so you can size the /tap window to taste - alongside the existing menu-scale and maximize controls.

### Mythic Ledger (1.0.0-beta.8)

- **[NEW]** **Missed Kick is now its own death cause.** Death attribution adds a fourth cause: a Missed Kick - a cast that should have been interrupted landed and helped kill you - shown alongside Avoidable, Threat, and Other, naming the exact cast.
- **[CHANGE]** **Missed-kick deaths are scored like an "Other" death.** A death from a missed interrupt now carries the same penalty as an unavoidable one. Existing runs recompute this cause from their stored recaps on login.
- **[NEW]** **On-screen death report.** After a pull (or at the run's end), a customizable overlay flashes who died since the last report and why. Styleable font/size/colors/background/position, auto- or click-dismiss, per-pull or once at the finish. /ledger deathreport reposts the last one to party chat.
- **[NEW]** **Avoidable-damage breakdown on the score card.** The player review now lists the exact mechanics behind your Survival score - biggest first, each a real spell icon with the damage taken, a share bar, and its share of your avoidable total. Reference only.
- **[CHANGE]** **Clearer, personalized score explanations.** "How your targets were set" now sits below the coaching, and every category is explained in plain language using your own numbers with a worked example.
- **[BUG FIX]** **Scoreboard "Least Avoidable" leader fixed.** A player who took no avoidable damage (logged as "-") was skipped; a clean player is now correctly read as zero and credited.
- **[CHANGE]** **Settings page redesigned** into a two-column layout, and the scoreboard Scale slider shows its numeric value again.
- **[BUG FIX]** **Interrupt cooldown-class labels corrected.** Several kicks sat in the wrong CD band. Labels only; expected kick rates and grades are unchanged.

## 1.3.0

Headlined by Mythic Ledger beta.7 - death attribution (every death sorted into why it happened, driving a smarter death penalty) and per-spell interrupt & dispel breakdowns. The platform window also links straight to the website now.

**Platform**

- **[NEW]** **Website link in the footer.** The /tap window footer now has a Website button next to Discord - it copies https://tap.soldercode.dev/ (WoW can't open a browser directly).

### Mythic Ledger (1.0.0-beta.7)

- **[NEW]** **Death Causes.** Every death is now classified as Avoidable, Threat, or Other. It reads the game's death recap and weighs the whole sequence, not just the killing blow. Shown as a breakdown card on the player review.
- **[CHANGE]** **Deaths are scored by cause.** The Death penalty is no longer flat - an avoidable death costs the most, an unavoidable one less, and a threat/aggro death the least. Runs recorded before this update keep the old flat penalty.
- **[NEW]** **Interrupt & dispel breakdowns.** The player review now shows what you actually kicked and dispelled grouped by the dungeon's priority tiers, plus the priority casts you didn't personally cover. Click any spell to jump to it in the Dungeon Guide.
- **[NEW]** **Item level & hero talent on the details page.**
- **[NOTE]** **Full per-spell run log.** Every run now records the complete per-spell breakdown for the whole party plus death recaps - raw detail for future scoring and analysis. (Captured now; most of it isn't shown yet.)

## 1.2.0

A platform release headlined by Mythic Ledger's deepest scoring pass yet - healing is now graded against the damage your group actually took, dispels only count the real priorities - plus a brand-new Dungeon Guide.

### Mythic Ledger (1.0.0-beta.6)

- **[NEW]** **Dungeon Guide.** A read-only journal of the season's interrupt & dispel priorities, dungeon by dungeon, with the caster shown as a live 3D model. Reference only; it doesn't affect scoring.
- **[CHANGE]** **Tanks & healers are graded on the damage the group actually took.** Tank and healer Throughput now measures healing plus absorbs against a target built from unavoidable damage taken. Standing in avoidable damage now hits that player's own Survival, not the healer's target.
- **[CHANGE]** **Healing expectations tuned per tank spec, from 32 logged runs.**
- **[CHANGE]** **Dispels only count what's actually a priority.** Each dungeon's dispel requirement now counts only High/Must dispels.
- **[CHANGE]** **Long-cooldown interrupts expect fewer kicks.**
- **[NEW]** **Groundwork for gear- & build-aware scoring.** The start-of-run inspection records each party member's hero tree, talents, and item level. (Collected now; not yet driving scores.)

## 1.1.1

A platform release rolling up the latest from every module. Mythic Ledger lands a major scoring accuracy pass plus two new features, and the other modules graduate to a stable 1.0.

### Mythic Ledger (1.0.0-beta.5)

- **[NEW]** **At-a-glance Group Utility.** Run details and the scoreboard now show party totals for interrupts, buffs purged/soothed, and debuffs cleansed, each landed vs expected.
- **[NEW]** **Your shared history, right on their tooltip.** Mouse over anyone you've keyed with and their tooltip shows your shared history: keys together, timed %, best key, average score, and your notes. Toggle each surface in Settings > Tooltips.
- **[CHANGE]** **Interrupt & dispel expectations are built from real runs.**
- **[CHANGE]** **Time in combat shapes interrupt & dispel expectations.**
- **[CHANGE]** **Carrying a slacker no longer hands them a free pass.** A teammate covering for you now only helps halfway.
- **[CHANGE]** **Tank damage counts for more.**
- **[CHANGE]** **Augmentation Evokers are scored as the support spec they are.**
- **[CHANGE]** **Party members are scored on their real spec when we can see it.**
- **[CHANGE]** **Survival is a bit more forgiving.**
- **[BUG FIX]** **Runs that finish on trash now record their stats.**

### Combat Alerts (1.0.0)

- **[CHANGE]** Out of beta - Twisteds Combat Alerts is now a stable 1.0 release.

### Focus Target Interrupt (1.0.0)

- **[CHANGE]** Out of beta - Focus Target Interrupt is now a stable 1.0 release.

### Rotation Assistant (1.0.0)

- **[CHANGE]** Out of beta - Rotation Assistant is now a stable 1.0 release.
- **[NOTE]** The on-screen cue reads keybinds from Action Bars 1-5 only. Keys bound solely on third-party action-bar addons may not be picked up.

## 1.0.1

A big Mythic Ledger visual + scoring pass (module version 1.0.0-beta.4), plus a platform-wide per-module on/off you can reach from any module's own Settings tab, and settings tidy-ups across the other modules.

- **[BUG FIX]** **Mythic Ledger - Warlock interrupts now count.** Spell Lock fires from the Felhunter, so the meter filed those kicks under the pet. Pet interrupts/dispels are now mapped back to the owner live during the run.
- **[NEW]** **Enable/disable any module from its own page.** Every module's Settings tab now has a master on/off switch, and a disabled module shows a clear MODULE DISABLED overlay on its other tabs.
- **[NEW]** **Mythic Ledger - run details, rebuilt** into hero cards with a run timeline matching the end-of-run scoreboard.
- **[NEW]** **Mythic Ledger - "Timed +2".** Run results now show the keystone upgrade you earned.
- **[CHANGE]** **Mythic Ledger - player pages** now match the character page.
- **[CHANGE]** **Mythic Ledger - interrupt scoring** reweighted so the tiers split the expected kick volume 10 / 20 / 30 / 40.
- **[CHANGE]** **Mythic Ledger - scoring weights are now static and uniform across roles** (Throughput 35% / Interrupts + Dispels 25% / Survival 20% / Death Impact 20%). Your saved runs are automatically rescored.
- **[CHANGE]** **Mythic Ledger - Survival and Death Impact always weigh the same.**
- **[NEW]** **Mythic Ledger - timestamps show the time of day**, with a new Date & Time setting.
- **[CHANGE]** **Mythic Ledger - a clean run scores full Survival.**
- **[NEW]** **Mythic Ledger - fairer dispel scoring.** The ledger talent-inspects the party at the start of a run; a member who never specced their dispel is scored N/A, not penalized.
- **[NEW]** **Mythic Ledger - scoreboard "vs your best".**
- **[NEW]** **Mythic Ledger - /tap changekey.** Arms a one-shot reminder to change your keystone.
- **[BUG FIX]** **Mythic Ledger - recap spam** no longer toasts your whole group at the end of a run.
- **[BUG FIX]** **Mythic Ledger - scoreboard timeline labels** no longer tuck under the footer buttons.
- **[BUG FIX]** **Mythic Ledger - utility scoring.** Meeting your interrupt / dispel target now scores full even on a low-sample run.
- **[BUG FIX]** **Mythic Ledger - runs that finish on trash now capture stats.**

### Modules

- **[CHANGE]** **Combat Alerts - Settings reorganized** into Sound, Performance, Backup & Data, and Minimap sections, and the Alerts tab now names the active profile.

## 1.0.0-beta.3

Third beta. A big visual + accuracy pass on Mythic Ledger, plus a round of platform appearance fixes that every module inherits.

- **[CHANGE]** **Mythic Ledger - hero-card pages.** The character overview's By Spec and By Dungeon breakdowns are now rich hero cards with a type-to-filter box beside the season selector.
- **[BUG FIX]** **Mythic Ledger - boss icons** now load on the post-run scoreboard and on previously-recorded runs, and the dungeon background art covers the whole scoreboard.
- **[BUG FIX]** **Mythic Ledger - average deaths** now count only your deaths per run.
- **[CHANGE]** **Mythic Ledger - scoring.** Interrupts and dispels were rescored for Midnight.
- **[BUG FIX]** **Appearance.** Custom theme colors now save correctly from the color picker; the Menu scale slider is smoother to drag; table tooltips render at the cursor; check-box labels no longer wrap.
- **[BUG FIX]** Fixed a Lua error when opening a run's player scores, and party cards overlapping their section header.

### Modules

- **[CHANGE]** **Tabbed layouts.** Combat Alerts, Focus Target Interrupt, and Rotation Assistant each moved from one long scrolling page to a docked tab strip under the title bar, matching Mythic Ledger.

## 1.0.0-beta.2

Second beta. A brand-new module (Mythic Ledger), a platform look & feel overhaul, and a round of updates to the modules that already shipped in beta.1.

- **[NEW]** **Mythic Ledger** - a new, private, account-wide Mythic+ journal. It records every timed, depleted, or abandoned key automatically, remembers who you've run keys with, and grades every run with a full player review. Plus run/dungeon/character/player pages, personal bests, per-boss stats, a post-run scoreboard, and easy backup & sharing.
- **[NEW]** **Appearance, reworked.** The look is now two independent choices: a shape (sharp / rounded) and a color scheme, plus a full Custom editor for every color. Add a Menu scale slider to size the whole window.
- **[CHANGE]** **Cleaner module pages** - a selected module's name now shows in the window title instead of a repeated in-page header.
- **[BUG FIX]** Dropdown/menu backgrounds and text now follow the theme on a live swap.
- **[CHANGE]** Consistent branding: every add-on shows the shared platform logo and a Twisteds name in the AddOns list.
- **[KNOWN]** Mythic Ledger targets Retail Midnight; some live meter/API details are still being verified in game. Metrics the meter can't supply show as "-", never a fake zero.

### Updates to existing modules

- **Combat Alerts** - per-character alert profiles; spell/item Find search with a live icon; fixed slider spacing in the alert editor.
- **Rotation Assistant** - /tap rotation and /rcue slash commands; the cue now follows your chosen Platform font.
- **Focus Target Interrupt** - the marker bar now remembers your saved focus marker.

## 1.0.0-beta.1

First public release of the platform. Everything ships as one download.

- **[NEW]** **Twisteds Addon Platform** - a single hub (/tap) that hosts every tool under one shared look, with live on/off toggles per module and a built-in "What's New" for each.
- **[NEW]** **Combat Alerts** - build your own rule-based audible & visual cues. Includes a spell/item search backed by an optional bundled database.
- **[NEW]** **Focus Target Interrupt** - one-key focus + mark macro, an on-screen raid-marker bar, and auto-detected interrupt/stun macros for your spec and talents.
- **[NEW]** **Rotation Assistant** - draws the keybind of Blizzard's suggested next ability on screen, with cast-vs-instant, GCD sweep, out-of-range, and out-of-resource indicators.
- **[NEW]** **TAP_GameDB** - an optional, load-on-demand spell/item name database.

### Notes

- **[CHANGE]** The old standalone Twisteds Combat Cues has been split into two focused modules - Combat Alerts and Focus Target Interrupt - and rebuilt on the shared platform UI.
- **[CHANGE]** Alert group-range checks are hidden; alerts prefer a spell-range check to your target instead.
- **[KNOWN]** Exported alert strings from the old add-on still import (the TCCX1! format is accepted).
]==]
