# Mythic Ledger — Changelog

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
