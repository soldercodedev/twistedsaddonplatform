# Twisteds Addon Platform - Changelog

Platform-level release notes. Each module also keeps its own in-game **What's New** (open `/tap` →
any module → *What's New*), and a `README.md` in its folder.

## 1.9.0

A platform release: **profiles**, one **frame-placement system** for every add-on, a long-standing **font bug** fixed, and Season 2 scoring re-measured.

### Platform (1.9.0)

**Profiles**

- **[NOTE]** **Give your settings a once-over after updating.** Nothing is deleted - everything you had is carried into the profile named **Default** - but a character can end up pointed at a different profile, and then its add-ons read from there instead. That happens if you had a per-character Combat Alerts profile: the character is now bound to a platform profile of that same name, which starts out holding only those alerts, so your other add-ons will look reset on it while the real settings sit safely in Default.
- **[NOTE]** If something looks missing it is on another profile, not gone. `/tap` > Platform > Profiles shows which profile this character is using - switch it to **Default**, or use **Copy current into it** to pull Default's settings across. Combat Alerts also keeps its own **Copy alerts** tool for moving individual alerts between profiles.
- **[NEW]** **Profiles** (`/tap` > Platform > Profiles, or `/tap profile`). A profile is every add-on's settings in one named bundle - frame positions, sizes, colours, fonts and behaviour toggles - and each character is bound to one, so alts can share a setup or keep their own. Create, copy, rename, delete, and reset from one page.
- **[CHANGE]** What stays shared across every character: which add-ons are switched on, the platform's theme and font, minimap icons, the manager window, and every bit of recorded data - Mythic Ledger's run history, player notes and personal bests, and the WoW Token price history. A profile can never take those with it.
- **[NOTE]** Per-spec behaviour is unchanged and stays where it was: Rotation Assistant's spec filter and Focus Interrupt's trigger specs. Profiles are for "this character is set up differently", not "this spec behaves differently".
- **[BUG FIX]** Copying a profile did not bring Combat Alerts' rules or Mythic Ledger's settings with it - the copy came up with a default rule set instead. Both add-ons keep those in their own saved variables keyed by the profile name, and the platform was only duplicating its own table. Renaming had the same hole (the old rows were orphaned and the renamed profile silently started from defaults), as did deleting (the rows leaked) and resetting (they survived a reset that claimed to wipe everything). Profile copy, rename, delete and reset are now broadcast to every add-on that keeps its own store.
- **[BUG FIX]** On the Profiles page, typing a name and clicking **Create empty** or **Copy current into it** straight away did nothing. The name was only read when the text box lost focus, and clicking a button does not take focus off a text box - so the name was still empty and the create was silently refused. The name is now read live at the moment you click.

**Frame placement**

- **[NEW]** **Movers page** (`/tap` > Platform > Movers, or `/tap move`). Every movable element on the platform is listed in one place, grouped by add-on, with its anchor point and exact X / Y offsets, a Place button, and a Reset. Add-ons register their frames with the platform, so anything added later shows up here automatically.
- **[NEW]** **Placement mode.** Hides the config window, drops a labelled coloured box over every element, and shows one Done / Cancel / Reset bar. The real element follows the box live as you drag, so you position the thing itself rather than a stand-in. Done or Escape keeps the new positions; Cancel restores every one of them. You can place a single frame, one add-on's frames, or the whole platform at once.
- **[CHANGE]** Every add-on's own mover has been retired into this system. Rotation Assistant's placement mode, Combat Alerts' per-rule drag ghosts, Mythic Ledger's Death Report and Live Coach move modes, and Focus Interrupt's marker-bar panel were five implementations of the same idea, each with its own Save/Cancel bar and its own bugs. The buttons are all still where they were - they now open the shared placement mode. Your saved positions are untouched: each add-on still stores its own.
- **[CHANGE]** On-screen elements are no longer draggable in place, so there is no lock state to forget and nothing to accidentally shove out of position mid-fight. Dragging happens on the placement box.
- **[NEW]** Elements that only appear in combat (the rotation cue, an alert, the Death Report, the Live Coach) show a preview of themselves for the duration of a placement session, so you are never dragging an invisible box.
- **[NEW]** Placement mode draws a translucent box per element, sized to that element's real bounds, and the **live preview is a separate toggle** - per element from the eye button above its box (or a right-click on it), and for everything at once from Preview all / Boxes only on the bar. Previews start on; dropping to plain boxes makes a crowded screen readable. Boxes keep the element's real size either way, and re-measure as elements resize.
- **[NEW]** An optional alignment grid while placing: 8 / 16 / 32 / 64 / 128px, drawn outward from screen centre so an element parked at 0,0 sits on the highlighted centre cross. Snapping follows whichever grid you can see.
- **[CHANGE]** The placement controls moved from a panel in the middle of the screen to a slim single-line bar across the top, out of the way of the layout you are working on.
- **[NEW]** Click a box in placement mode to select it, then nudge it with the arrow keys: by the grid pitch when a grid is on, shift for single pixels, ctrl for bigger strides, tab to cycle between boxes. Dragging is fine for roughing a layout out and hopeless for the last few pixels.
- **[NEW]** An optional dim layer while placing, so the world behind your UI drops away and the boxes read clearly. Toggled from the bar.
- **[BUG FIX]** Snapping now happens continuously as you drag rather than only on release, and boxes land exactly on the grid lines. It was snapping the element's stored offset, which is measured in that element's own scaled space and from its own anchor point - so a scaled element, or one anchored anywhere but centre, settled a few pixels off the line. Snapping now happens in screen space, measured from the same centre the grid is drawn from.
- **[CHANGE]** The Movers page is now a hero and a button rather than a per-element table of anchor dropdowns and X / Y boxes. Placement mode does that job better by showing you the real screen, and every add-on still has its own Place button.
- **[BUG FIX]** The first time placement mode was opened after a reload it errored and bounced you straight back to the config window. The control bar is created shown, as every WoW frame is, so hiding it during setup fired its own OnHide handler - which tore down the placement session that was still being built. The bar is hidden before that handler is wired now, and ending a session is guarded so nothing can unwind one mid-build.

**Fonts**

- **[BUG FIX]** **Selected fonts were ignored.** Every font in the platform, and every per-element font picker in every add-on, silently fell back to Friz Quadrata - which is why the setting looked like it reset itself. Before using a font the platform probes whether the client will accept it, and that probe called `SetFont` without the flags argument and trusted its return value. With the argument missing the call never reports success, so *every* font failed the probe and every caller got the fallback. The probe now passes flags and confirms by reading the font back, which is true whatever the API returns. This has been wrong for the life of the add-on.
- **[NEW]** Every per-element font picker now offers **TAP Global Font** as its first option: pick it and that element follows Platform > Settings instead of pinning a font of its own. Anything previously set to "use the UI font" already behaves this way and now says so. The platform's own font picker does not offer it, since that one *is* the global.

### Mythic Ledger (1.4.0)

- **[CHANGE]** Season 2 utility expectations were re-measured against logged runs. Every dungeon's trash interrupt rate came down, by 10% to 40%: a median group was landing only 61-85% of the modelled kick supply, so a completely ordinary run was being marked down for it.
- **[BUG FIX]** That over-statement was being hidden, unevenly. Interrupt supply is capped at your group's own kick capacity, and at the old rates that cap was doing the work in 85% of runs - so how harshly you were graded depended on your group's composition rather than on the dungeon. A group with plenty of kickers was measured against a number no group reaches; a group with few was quietly capped back to something fair. Kings' Rest, Voidscar Arena and Temple of Sethraliss are where it bit hardest, and their interrupt scores rise 11 to 13 points.
- **[CHANGE]** Dispel rates moved both ways and by less, since they were already close: Voidscar Arena +36%, Murder Row +32% and Altar of Fangs +22%, everything else in single digits.
- **[BUG FIX]** Voidscar Arena's biggest cleanse, Corrosive Essence, was missing from the dungeon data altogether, so the dungeon looked as though it had almost no poison to remove: healers were graded against a nearly empty requirement and dispel-capable damage dealers were not graded on dispels there at all. It counts now, and Voidscar Arena is the only dungeon this moves.
- **[BUG FIX]** Four dispels that groups clear constantly were graded as optional, and now count: Cold Claws and Rolling Thunder (Ruby Life Pools), Serpent Strike (Kings' Rest) and Insatiable Hunger (Den of Nalorakk). Den of Nalorakk carried no curse requirement at all, so anyone whose only dispel was a decurse went ungraded on dispels there.
- **[NEW]** Three more dispels are named in the Dungeon Guide without counting toward your score, because groups clear them too rarely to be expected to: Mind-Numbing Poison and Mother's Wrath, plus Murder Row's Fel Crazed.
- **[NEW]** Five casts that groups routinely kick were missing from the Dungeon Guide and are now listed: Shadowbolt Volley (Voidscar Arena), Storm Bolt (Ruby Life Pools), Shadow Bolt (Kings' Rest), Doom Bolt (Murder Row), and the Uncoiled Writhe's copy of Toxic Atrophy in Altar of Fangs. Listing them does not change any score.
- **[CHANGE]** Death Report and Live Coach settings are per profile now, and both overlays are placed through the platform's Movers page. Your run history, player notes and personal bests are account-wide and are never part of a profile.
- **[NOTE]** Existing runs re-score on login. The average overall score moves by well under a point, and about one player in ten shifts by a single letter grade, almost always upward.

### Combat Alerts (1.2.0)

- **[CHANGE]** It had its own profiles; they are now the platform's, so one switch moves every add-on together instead of leaving one on a different setup. Your existing alert profiles and per-character choices are carried over.
- **[BUG FIX]** Its own **Rename** and **Delete** profile buttons only touched its own saved variables and never told the platform. A rename left the platform pointing at the old name, a fresh empty rule set was created under it, and your alerts looked like they had been wiped; a delete left the profile listed everywhere else. Both now go through the platform, which moves every add-on together.
- **[BUG FIX]** The **Copy alerts** tool defaulted its destination to your character key rather than the profile you are actually on - a leftover from when profiles were per-character. On an account where a profile happens to share a character's name, the copy then went silently into the wrong profile, reported success, and left the profile you were looking at empty. The destination now defaults to the active profile, it is spelled out next to the Copy button, and switching profile no longer leaves a stale source and destination behind.
- **[CHANGE]** Each alert's on-screen position is placed through the platform's Movers page; the add-on's own drag ghosts and Save/Cancel bar are gone.

### Focus Target Interrupt (1.4.0)

- **[CHANGE]** The raid-marker palette is positioned through the platform's Movers page. The inline drag panel that used to sit above the bar is gone - the size slider it carried was already on the settings page.
- **[CHANGE]** Its settings are per profile, so alts can keep different marker setups.

### Rotation Assistant (1.1.0)

- **[CHANGE]** The cue is positioned through the platform's Movers page; the add-on's own placement mode is gone and the cue is no longer draggable in place.
- **[CHANGE]** Its settings are per profile.

## 1.8.0

Updated for patch 12.1. A first-launch **Setup Tour** for the platform; Mythic Ledger adds **Midnight Season 2** support, a new **Live Coach**, week-over-week stats, a Weekly Vault panel and a **Progression** page; Focus Target Interrupt now builds a macro for every interrupt and stun you know. Mythic Ledger also stores much less, with one control for how long run history is kept in full.

**Platform**

- **[NEW]** A first-launch **Setup Tour**. On first login the platform offers a short guided walkthrough of the `/tap` Overview, pointing out how to enable, disable, configure and preview each add-on. Reopen it any time from Help > Setup Tour, or `/tap tour`.
- **[CHANGE]** Every dropdown in the suite was rebuilt. Long lists (sounds, fonts, dungeons) now open with a **search box** - start typing to filter them; lists scroll smoothly with a slim scrollbar; arrow keys walk the options with Enter to pick and Escape to back out; options can be grouped under headings; and an option you cannot pick now tells you why when you hover it. Selects can also offer tick-box **multi-select** now, which the add-ons will start using where picking several things makes sense.
- **[CHANGE]** Spell/item icons drawn on settings pages (the ones with the real Blizzard tooltip on hover) are now pooled and reused across page redraws instead of a fresh element per redraw, trimming memory growth over a session.
- **[CHANGE]** Updated for WoW patch 12.1 across every add-on.

### Mythic Ledger (1.3.0)

- **[CHANGE]** Saved data is about **35% smaller**. Every run stored the full talent list of all five players twice over, and nothing read it.
- **[NEW]** **Run History** (Mythic Ledger > Settings > Tracking) is one control for how long a run keeps full detail and what happens after that: trim it or delete it. A trimmed run keeps its date, key, result, party, your numbers, score and grade, and still appears in every list and chart; it drops only the deep review detail, about 87% of its size. Nothing changes until you press Apply. A trimmed run's score is frozen, so a later scoring change cannot rewrite your history.
- **[NEW]** **Keep** flags: lock a run to hold its full detail, or lock a player to protect their record and every run they appear in. A locked run is never trimmed or deleted.
- **[BUG FIX]** Mythic Ledger scores a run against **its own season's** dungeon data again. When Season 2 began, Season 1 runs started resolving against the Season 2 profile, which does not list Season 1's dungeons, so they were graded as if there had been nothing to interrupt or dispel. Existing runs re-score on login.
- **[NEW]** **Midnight Season 2** support: all eight dungeons have a full Dungeon Guide catalog - what to kick, what to dispel, who casts it, with the 3D caster preview - and kick/dispel scoring expectations calibrated from real Season 2 runs. Season 1 keeps its own profile for your history.
- **[NEW]** Dungeon Guide entries now explain **why** each kick and dispel earned its tier - hover a spell for the mechanic and the observed evidence ("killing blow on the healer at +8", "removed 67% of applications"), with key numbers highlighted, dispel schools colored, and death evidence marked with a skull.
- **[NEW]** **Live Coach** - an on-screen nudge between fights. After a boss (or big pulls too, your call) it checks how the run is going and tells you the one thing to fix: "Kick more", "Cut avoidable damage", "Push your DPS". It grades with the same engine as your end-of-run score, so the advice matches your final grade - the real score still comes at the end. Off by default; turn it on in Settings > Live Coach, where you pick how often it speaks, how much it says, and how it looks. `/tap ml coach` tests it.
- **[NEW]** The Overview has a **This Week** row - runs, timed %, average score, and deaths, each compared to last week. Shows up once you have two weeks of history.
- **[NEW]** **Trouble Spots**, also on the Overview: the dungeons that keep beating you, ranked by fail rate and deaths.
- **[NEW]** The Characters page now starts with a **Weekly Vault** panel - every character's top 8 keys this week, with the three vault slots marked and the reset timer. Depleted keys count too, same as the vault itself.
- **[NEW]** A new **Progression** page charts a character's trajectory across their runs. Pick a metric - Ledger Score, Key Level, Time vs timer, Deaths, DPS or HPS - and read it as a line with an average line and an Improving / Steady / Regressing call, with Latest / Min / Max / Average cards above it. Switch between a per-run and a weekly view, and narrow to a date range and/or a key-level range.
- **[CHANGE]** The season filter names seasons properly ("Midnight Season 2" instead of "Season 18") and labels the current one.

### Focus Target Interrupt (1.3.0)

- **[NEW]** A macro for **every** interrupt and targeted stun you know, not just your main one (pet abilities included). Your first of each kind keeps the classic "TAP Interrupt" / "TAP Stun" name so existing bindings keep updating; extras get short "TAP <ability>" names.
- **[NEW]** Every macro has its own **Cast at** option: your focus, current target, or mouseover, with fallback combos (focus, else target / mouseover, else focus). The default is still focus-only; save a macro again after changing it.
- **[NEW]** The Macros page shows each detected ability as a proper spell icon - hover it for the real Blizzard spell tooltip.
- **[CHANGE]** The macro buttons now read **Update Macro** when that macro already exists in your macro book, so it's clear you're rewriting it rather than adding another.

## 1.7.1

Hotfix for 1.7.0: checkboxes and toggles are clickable again.

**Platform**

- **[BUG FIX]** After 1.7.0, some checkboxes and toggles in the settings couldn't be clicked, and a few buttons lost their hover highlight. Fixed.

## 1.7.0

A leaner Mythic Ledger: throughput scoring returns to "meeting your share is 100," a much smaller saved run history, and lower memory use on data-heavy pages.

**Platform**

- **[CHANGE]** Pooled interface elements release what they were holding (click handlers, tooltip data) when they're reused, so paging through data-heavy screens uses less memory over a session.

### Mythic Ledger (1.2.0)

- **[NEW]** The Death Causes breakdown now names what actually killed you - the mechanic behind each avoidable death, the un-kicked cast behind a missed kick, and the biggest single source behind an unavoidable one. Works on existing runs too.
- **[CHANGE]** Throughput: hitting your expected group share is a full 100 again. Doing your fair share is a top mark, beating it caps at 100, and falling short is still graded down. Reverts last version's stricter bar that scored meeting your share only a 94. Your existing runs re-score on login.
- **[CHANGE]** The saved run history is much smaller - several per-ability breakdowns that were stored but never shown are no longer kept (plus a leftover stat nothing fills in); existing runs are trimmed automatically on login, keeping everything the score, the review, and the boss splits use.
- **[CHANGE]** Per-boss splits store less: top DPS and HPS are derived from the per-player numbers instead of saved twice, and empty death lists aren't kept.
- **[CHANGE]** Lower memory when browsing many run reviews in one session - a viewed run's full score detail is cached briefly instead of held all session.

## 1.6.0

Uses less memory over long sessions, Combat Alerts is a smaller download, and you can re-enable a fully-disabled add-on from the Overview.

**Platform**

- **[BUG FIX]** Fixed a slow memory build-up while the `/tap` window stays open for a long session.
- **[CHANGE]** A broken add-on now shows an error instead of quietly doing nothing.
- **[NEW]** You can re-enable a fully-disabled add-on straight from the Overview, instead of hunting for it in Blizzard's AddOns list.

### Mythic Ledger (1.1.2)

- **[CHANGE]** Tanks are now graded on threat control: every teammate death from a mob you lost or never grabbed docks your Survival. Tanks used to score near-perfect regardless; now holding the group together shows in the score. Your existing runs re-score on login.
- **[CHANGE]** Tanks are held to a much tighter avoidable-damage standard than other roles. A tank eats the brunt of every pull, so even a small share of avoidable damage taken now costs real Survival points, where the shared grace band used to park every tank at 100.
- **[CHANGE]** Throughput no longer maxes out just for pulling your fair share. Meeting your expected share is a strong score and beating it a little tops out, so the DPS/HPS bar tells good from average better.
- **[CHANGE]** Kick expectations for Seat of the Triumvirate and Nexus-Point Xenas were recalibrated to what real runs actually kick.
- **[CHANGE]** Several often-kicked casts (Arcane Bolt, Shadow Bolt, Holy Bolt, Umbra Bolt, Shadowfrost Blast) now show as Should Kick instead of Spare in the Dungeon Guide.
- **[CHANGE]** The group-utility tiles in the run review use the same color per dispel school as the Dungeon Guide.
- **[BUG FIX]** A Hunter's Feign Death no longer counts as a real death, so hunters aren't penalized for feigning. Your existing runs are corrected on login.
- **[BUG FIX]** The run lists on the Characters and Dungeons pages were missing their column headers. They're back, and now sortable by date, key, time, deaths or DPS/HPS.
- **[BUG FIX]** The Dungeon Guide's caster preview shows on the first click instead of staying blank until you click away and back.
- **[BUG FIX]** The scoreboard and browsing lots of runs no longer slowly use more memory over a long session.

### Combat Alerts (1.1.0)

- **[BUG FIX]** Deleting an alert no longer leaves its on-screen warning behind.
- **[BUG FIX]** `/tap alerts` opens the manager again.
- **[BUG FIX]** You can stop a running test alert again (the Stop Test bar is back).
- **[CHANGE]** Dropped the bundled spell/item name database - the Find search reads from your spellbook, gear and bags instead, so it's a smaller download. Paste an ID for anything not in those.
- **[CHANGE]** Moved the test button into the alert editor and renamed it Test Alert.

## 1.5.1

A quiet maintenance release. Every module now talks to the game through the **current WoW APIs** directly - the old compatibility shims kept around for pre-Midnight clients are gone - and the project gained automated **code-quality gates** that keep it free of accidental globals and deprecated calls. Nothing changes in how anything looks or plays.

**Platform**

- **[CHANGE]** **Modern APIs only.** Load-on-demand data handling now uses the current `C_AddOns` API directly; the legacy `IsAddOnLoaded` / `LoadAddOn` fallbacks were removed. No functional change.
- **[CHANGE]** **Code-quality gates in CI.** Every push is now checked for global-namespace pollution (compiler-verified, so an accidental global can't slip in) and linted with luacheck.

### Mythic Ledger (1.1.1)

- **[CHANGE]** Add-on presence checks (Details!, the Encounter Journal) now use the current `C_AddOns` API directly. No functional change.

### Combat Alerts (1.0.1)

- **[CHANGE]** Item and add-on lookups now use the current `C_Item` / `C_AddOns` APIs directly; the deprecated `GetItemInfo` / `GetAddOnMetadata` fallbacks were removed. No functional change.

### Focus Target Interrupt (1.1.1)

- **[CHANGE]** Loading Blizzard's macro UI now uses the current `C_AddOns` API directly. No functional change.

### Rotation Assistant (1.0.1)

- **[CHANGE]** Spell cooldown, cast, and icon lookups now use the current `C_Spell` API directly; the legacy global fallbacks were removed. No functional change.

## 1.5.0

A ground-up **navigation overhaul**. Each installed add-on now gets its own **category in the left sidebar**, and its pages live there as sub-items - so a feature-rich module's pages are discoverable at a glance instead of crammed into an in-body tab strip. Freeing that in-body top-nav lets a page carry its **own sub-tabs** (the Mythic Ledger Settings page is the first to use them).

**Platform**

- **[NEW]** **Two-tier sidebar navigation.** The old single "Modules" list is replaced by one **collapsible category per add-on** (Mythic Ledger, Combat Alerts, Focus Target Interrupt, Rotation Assistant), with each module's pages as sub-rows. Only the add-on you're in stays expanded (accordion), so the list stays tidy. The **Dungeon Guide** now sits inside the Mythic Ledger category, directly under **Summary**.
- **[NEW]** **Color-coded sidebar.** Each add-on's category carries its own **signature color**, so you can spot Mythic Ledger, Combat Alerts, Focus Target Interrupt and Rotation Assistant at a glance.
- **[NEW]** **Page-level sub-tabs.** With top-level nav in the sidebar, the in-body top-nav is free for a page's own tabs.
- **[CHANGE]** **Every module's tabs moved to the sidebar.** Combat Alerts (Alerts / Profiles / Settings), Focus Target Interrupt (Macros / Marker Palette / Announce / Settings), and Rotation Assistant (Behavior / Indicators / Appearance / Settings) now list their pages in the sidebar. Drill-downs (a run's details, a rule's editor) still open in-body over the page they came from. Deep links, minimap buttons and slash commands are unchanged.
- **[CHANGE]** **Overview is now one row per add-on** with its version as a **badge** (green for a stable release, blue for a beta), a colored **What's New** button, and a red **Disable** button. The old **Installed** page is gone - **enable/disable (live toggle) and Unload** now live on Overview, and the redundant enable toggle was removed from each module's own Settings.
- **[CHANGE]** **Consistent page headings everywhere.** Every page now carries the same title/description **Page Heading** style; the Platform *Appearance* page is renamed **Settings** and rebuilt on the **two-column grid**.
- **[NEW]** **Changelog page.** The platform's release notes now live in-game under **Help → Changelog** - the global counterpart to each module's *What's New*.

### Mythic Ledger (1.1.0)

A big **scoring pass** alongside the navigation move. Every scoring change below **re-scores your existing runs automatically** on login.

- **[NEW]** **Scoring Guide - how every run is graded.** A new read-only **Scoring Guide** page lays out the whole model in plain language: the 5 metrics and their weights, the real-world factors (your gear, spec, the dungeon, and your group), the guardrails that stop a teammate over-performing from hurting your score, and the grade ladder - all pulled live from the engine.
- **[CHANGE]** **Item level now shapes your damage bar.** Your expected damage is nudged by your item level versus the group average (bounded, about 1% per item level), so the **lowest-geared player isn't punished** for output their gear can't reach, and out-gearing the group no longer reads as skill. Applies only when most of the party's item level is known.
- **[CHANGE]** **Healers get full credit on a clean key.** Time the key with no deaths and the **healing half** of your throughput is lifted to full marks instead of being marked down when the group self-covered. Death-gated, and it **never lowers** a score.
- **[NEW]** **New S+ grade** for a flawless run (every applicable metric a perfect 100).
- **[CHANGE]** **Smarter death causes.** The **killing blow** decides the cause: avoidable, **environmental** (fall / lava / fire - now your own fault), a non-tank **melee** hit (lost threat), or an **un-kicked cast** (missed kick), even when earlier chip damage was something else.
- **[CHANGE]** **Fairer dispels.** A tiny fair share the group already covered no longer scores a zero; Skyreach stops expecting a healer to cleanse a debuff that isn't there, and Restoration Druids are credited for Soothe.
- **[CHANGE]** **Long-cooldown interrupts get a pass** when the group covered the kicks and nobody died to a missed one (still worth pressing).
- **[NEW]** **Tanks see loose-mob deaths** - teammate deaths from a mob the tank lost or never had threat on, shown for awareness (not scored).
- **[NEW]** **All eight pages in the sidebar** (**Summary**, Runs, Dungeons, Characters, Players, Bests, Settings, Debug) with the Dungeon Guide and Scoring Guide, plus **Runs filters + sortable DPS/HPS columns** and **Players filters for Class and Spec**. Clicking a run/player/dungeon still opens in place.
- **[CHANGE]** **"Overview" is now "Summary"** (so it doesn't clash with the platform Overview), and **Settings** is reorganized into sub-tabs (Appearance, Tooltips, Scoreboard, Death Report, Tracking, **Regroup** - formerly Recap - and Misc).
- **[BUG FIX]** **Run-history date column** widened so the date/time stamp no longer runs under the dungeon icon.

### Focus Target Interrupt (1.1.0)

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
