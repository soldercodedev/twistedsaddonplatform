# Mythic Ledger — Changelog

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
- **[NEW]** Returning-player recap — local-only, once per person per group, role-aware, season-scoped.
- **[NEW]** Overview / Runs / Run Details / Dungeons / Characters / Players / Personal Bests /
  Settings / Debug pages, plus a post-run summary.
- **[NEW]** Boss split tracking, reload/disconnect recovery, versioned export/import, schema
  migrations.

### Notes

- **[KNOWN]** Combat-stat coverage depends on the provider; unavailable metrics show as "—", never 0.
- **[KNOWN]** All history is local and private; recaps are never posted to group chat.
