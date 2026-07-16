# Mythic Ledger

A module of the [Twisteds Addon Platform](../README.md). Open it with **`/tap`** (or **`/ledger`**),
or `/tap ledger`.

Mythic Ledger is a **private, account-wide Mythic+ journal**. It records every run automatically,
organises history by character, remembers the people you've run keys with, and reminds you about
them the next time you group up — all stored locally, all private to you.

## What it does

- **Records every Mythic+ run automatically** — dungeon, keystone level, affixes, season, timer and
  result (timed / depleted / abandoned), duration, keystone upgrade, and the exact character that ran
  it. Only real Mythic+ challenge runs are recorded — never Normal/Heroic/M0, Delves, raids, or PvP.
- **Party & performance history** — every party member's role and combat stats are saved with the
  run: damage/DPS, healing/HPS, damage taken, interrupts, dispels, and deaths (whatever the active
  stat provider can supply).
- **Combat-stat providers** — uses **Details!** when it's loaded and compatible, Blizzard's built-in
  damage meter otherwise, and a metadata-only mode when neither can help. Deaths, interrupts, and
  dispels are counted from the combat log regardless, so those are always available.
- **"Who have I run with?"** — a searchable, sortable **Players** browser plus per-player detail
  pages (runs together, timed %, highest key, per-role averages, notes, tags, favourite).
- **Returning-player recap** — when you join a group with someone you've keyed with before, a short
  reminder prints **to your own chat only**. It is never sent to party/raid/instance/guild chat, is
  shown once per person per group, respects a minimum-shared-runs threshold, and only shows metrics
  that are actually available.
- **Pages** — Overview, Runs (filter/sort), Run Details, Dungeons, Characters, Players, Personal
  Bests, Settings, and Debug — plus an optional post-run summary.
- **Boss splits**, **reload/disconnect recovery**, **versioned export/import**, and a **schema
  migration framework**.

## Slash commands

- `/tap ledger` (or `/ledger`) — open the journal
- `/tap ledger history` — jump to Run History
- `/tap ledger players` — jump to the party-member browser
- `/tap ledger current` — print the in-progress run's status
- `/tap ledger debug` — open the diagnostics page
- `/tap ledger export` — copy the whole ledger as a share string

## Notes

- **Everything is local and private.** No data is uploaded, and recaps are never posted to a shared
  chat channel. There is no rating, blacklist, or automatic judgement of other players — it's a
  personal history.
- Metrics a provider can't supply are shown as **—**, never a fake **0**.
- Details! is optional and is never modified — all integration is isolated behind a provider.

## Requires

The **TAP** hub (bundled). **Details!** is an optional enhancement (`## OptionalDeps: Details`).

## License

GPL v2 — see the platform [`LICENSE`](../LICENSE) and [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
