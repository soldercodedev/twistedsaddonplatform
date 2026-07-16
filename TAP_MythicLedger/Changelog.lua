-- TAP: Mythic Ledger - Changelog.lua
-- In-game "What's New" text (parsed by the suite: `## version`, `### sub`, `- **[TAG]** text`).
local ADDON, ML = ...

ML.CHANGELOG = [==[
# Mythic Ledger - What's New

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
