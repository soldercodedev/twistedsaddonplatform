-- TAP: Mythic Ledger - Changelog.lua
-- In-game "What's New" text (parsed by the suite: `## version`, `### sub`, `- **[TAG]** text`).
local ADDON, ML = ...

ML.CHANGELOG = [==[
# Mythic Ledger - What's New

## 1.0.0-beta.5

A big accuracy pass on the scoring engine, a new at-a-glance **Group Utility** panel, and a couple of
capture fixes. We pulled a batch of real logged keys and used the actual numbers to bring interrupts,
dispels, throughput and survival in line with what really happens in a dungeon. Everything below
**re-scores your existing runs automatically**, so your history updates to the new math on login.

- **[NEW]** **At-a-glance Group Utility.** The run details page and the end-of-run scoreboard now show a
  **Group Utility** panel - your party's total **interrupts**, **target buffs** purged/soothed, and
  **debuffs** cleansed, each as landed vs expected. Hover the dispel tiles to see exactly which enemy
  buffs and player debuffs were dispellable in that dungeon, with spell icons. (The meter only reports one
  combined dispel count, so the purge-vs-cleanse split is attributed by each player's capability - single-
  axis dispellers are exact, dual-axis ones split by their expected share.)
- **[CHANGE]** **Interrupt & dispel expectations are now built from real runs.** Each dungeon's expected
  kicks and dispels used to be a rough estimate; they're now calibrated to logged data, per dungeon -
  some dungeons simply throw more interruptible casts than others, and your target reflects that. The
  old model badly under-counted how much a coordinated group actually kicks, so expectations are higher
  and more realistic across the board. These will keep getting refined as more runs come in.
- **[CHANGE]** **Time in combat now shapes interrupt & dispel expectations.** If you blast a pack - or a
  boss - down before its casts come around, there was simply less to interrupt, and the score knows that
  now. Trash expectations scale with how long the run took; each **boss** scales with how long that boss
  was actually up, since its mechanics recycle the longer the fight runs - a slow kill offers more kicks
  and dispels than a burst, and a boss dropped before its cast comes around offers almost none. Same
  dungeon, a 19-minute key and a 26-minute key are no longer held to the same number.
- **[CHANGE]** **Carrying a slacker no longer hands them a free pass.** If a teammate over-performs and
  covers interrupts/dispels you never got a chance at, you're still not punished for a cast that was
  gone before you reached it. But the old system forgave that shortfall **completely** - so a player who
  just wasn't pressing their button could ride their group to a perfect Utility score. There's now a
  middle ground: teammates covering for you helps, but only **halfway**. Plainly under-use your kit and
  it will show up.
- **[CHANGE]** **Tank damage counts for more.** Measuring logged runs against the model, tanks were
  contributing a lot more of the group's damage than we were crediting them for - so tank Throughput was
  scoring a touch too easily. The role split was rebalanced to match reality (and DPS off-healing now
  counts for a little more, too).
- **[CHANGE]** **Party members are scored on their real spec when we can see it.** A pug's spec isn't
  broadcast to addons, so interrupts/throughput ran off a generic class guess - which could credit, say,
  a Beast Mastery Hunter with a 15-second kick it doesn't have. We now use the spec from the start-of-run
  talent inspection when it lands (and store it), and for an un-inspected Hunter DPS default to the far-
  more-common Counter Shot (long cooldown) rather than assuming a short kick.
- **[CHANGE]** **Survival is a bit more forgiving.** The grace band for avoidable damage widened
  slightly (nobody plays perfectly clean), and the point where Survival bottoms out moved from **40% to
  50%** of your total damage taken being avoidable. Same steep "don't stand in it" curve - just a little
  more breathing room before it bites.
- **[BUG FIX]** **Runs that finish on trash now record their stats.** When a key completed on **trash**
  instead of the last boss (short on enemy forces, went back to clear), the run was saved while you were
  still in combat - and the Midnight meter only reads out of combat, so DPS/HPS/interrupt/dispel numbers
  came back empty. Finalizing now waits for combat to drop first. Boss splits were always fine; this
  fixes the run totals.

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
