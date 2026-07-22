# Mythic Ledger - Manual Test Checklist

`[LOCAL]` = testable without a real key (mock data / UI / disable-enable).
`[M+]` = requires a real Mythic+ group/run to verify end-to-end.

## Providers
1. `[M+]` Details! present & loaded → run stats attributed to each party member by GUID.
2. `[M+]` Details! absent → falls back to Blizzard meter, `provider = "BLIZZARD"`.
3. `[M+]` Details! extraction throws → falls back to Blizzard automatically (check Debug log).
4. `[M+]` Blizzard `C_DamageMeter` supplies party totals when Details! is off.
5. `[M+]` Blizzard meter window hidden → stats still captured (if API supports it).
6. `[M+]` Neither provider usable → metadata-only; deaths/interrupts/dispels still counted from CLEU.

## Run lifecycle
7. `[M+]` Timed key → saved once, `status = TIMED`, `timeRemaining ≥ 0`.
8. `[M+]` Depleted key → `status = DEPLETED`, over-timer shown.
9. `[M+]` Abandoned/reset key → saved as `ABANDONED` (if tracking on), excluded from timed %.
10. `[M+]` `/reload` mid-key → run restored, not duplicated (recovery record consumed).
11. `[M+]` Disconnect/reconnect mid-key → same as reload.
12. `[M+]` Party replacement mid-key → roster snapshot updates; final roster saved.
13. `[M+]` Boss wipe then kill → attempts/wipes/kill split recorded on the boss.
14. `[M+]` Duplicate `CHALLENGE_MODE_COMPLETED` → still saved exactly once (composite fingerprint).
15. `[M+]` Secret-value safety → no Lua errors on any protected keystone/roster value.
16. `[M+]` Party roles stored for every member; all available stats stored.

## Module / platform
17. `[LOCAL]` Module appears in Overview / Installed / About / sidebar automatically.
18. `[LOCAL]` Disable module → tracking/recap events unregister, timers cancel; re-enable resumes.
19. `[LOCAL]` `/tap ledger`, `/ledger`, `/tap ledger history|players|current|debug|export` all work.
20. `[LOCAL]` What's New button shows the changelog.

## History / UI
21. `[LOCAL]` Empty history → friendly empty states on every page (no errors).
22. `[LOCAL]` Import a large mock history → Runs/Players sort & filter correctly; scrolls smoothly.
23. `[LOCAL]` Delete a run / delete all history / retention cap → caches rebuild correctly.
24. `[LOCAL]` Old/corrupt DB (hand-edit SavedVariables) → loads without wiping; migration logged.
25. `[LOCAL]` Same name on different realms → kept as two separate players (GUID/Name-Realm keyed).
26. `[LOCAL]` Player aggregation separates roles (no healer HPS blended with DPS damage).
27. `[LOCAL]` Unavailable metrics render as "-" everywhere (never a fake 0).

## Recap
28. `[M+]` Group with a returning player → recap appears once, in local chat only.
29. `[M+]` Repeated `GROUP_ROSTER_UPDATE` → no recap spam (once per person per group session).
30. `[LOCAL]` Recap "Preview for current group" button in Settings prints a sample.
31. `[LOCAL]` Recap respects season scope (current vs all) and min-shared-runs.
32. `[LOCAL]` Notes stay private - never in a recap unless "Include personal notes" is enabled.

## Packaging
33. `[LOCAL]` `deploy.ps1` mirrors `TAP_MythicLedger`; `/reload` loads it with no errors.
34. `[LOCAL]` Release ZIP includes `TAP_MythicLedger` and contains **no** Python/PS1 tooling.

## How to generate mock data (dev only)
Run this once in-game (not shipped) to exercise the UI without real keys:
```lua
/run for i=1,40 do local ML=select(2,...) end   -- (use TAP_MythicLedger's own dev generator if added)
```
A developer-only mock generator may be added under `TAP_MythicLedger/tools/` - that folder is
pruned from the release ZIP by the build action.
