# All Rivals — Windows notes

> **What:** Windows state of `/rivals/all`. **Read when:** changing `windows/Festival.App/Pages/AllRivalsPage*` or `AllRivalsViewModel`. Full Rivals notes (data, scope, IDs, tests): [../rivals/windows.md](../rivals/windows.md).

- `AppRoute.AllRivals(RivalScope)` parses web queries (`category`, `mode=leaderboard`, `rankBy`, optional `instruments`); `category=common`/`combo` without instruments resolve against Settings at load, and an unresolvable scope shows "This rivals list could not be identified."
- Virtualized `ListView` of `RivalRowView` rows (above, then below), centred to 960 epx; rows push Rival Detail with the same scope.
- States: loading ring, shared `ServiceStatusView` (scrape freeze countdown), empty, no player.
