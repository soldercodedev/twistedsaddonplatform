-- TAP: Mythic Ledger - Changelog.lua
-- In-game "What's New" text (parsed by the suite: `## version`, `### sub`, `- **[TAG]** text`).
local ADDON, ML = ...

ML.CHANGELOG = [==[
# Mythic Ledger - What's New

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
