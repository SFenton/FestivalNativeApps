# All Rivals — Windows notes

> **What:** Windows state of `/rivals/all`. **Read when:** changing `windows/Festival.App/Pages/AllRivalsPage*` or `AllRivalsViewModel`. Full Rivals notes (data, scope, IDs, tests): [../rivals/windows.md](../rivals/windows.md).

- `AppRoute.AllRivals(RivalScope)` parses web queries (`category`, `mode=leaderboard`, `rankBy`, optional `instruments`); `category=common`/`combo` without instruments resolve against Settings at load, and an unresolvable scope shows "This rivals list could not be identified."
- Virtualized `ListView` of `RivalRowView` rows (above, then below), centred to 960 epx; rows push Rival Detail with the same scope.
- States: loading ring, shared `ServiceStatusView` (scrape freeze countdown), empty, no player.

## Two columns

From a 1100 epx page the list keeps a 520 epx column and the chosen rival's Rival Detail (`RivalDetailPage` in `DetailFrame`, `fst.all-rivals.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). The list switches to single selection: the first rival is selected on load, clicks and arrow keys move the detail, and the choice survives a reload while that rival is listed. Below 1100 epx, or while loading/empty, it is the single centred column and clicks push Rival Detail. The Rivals hub itself already fills wide windows with two to four masonry columns of section cards, so it has no detail pane. Journey: `tools/windows/journeys/split-panes.json`.
