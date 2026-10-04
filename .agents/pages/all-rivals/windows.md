# All Rivals — Windows notes

> **What:** Windows state of `/rivals/all`. **Read when:** changing `windows/Festival.App/Pages/AllRivalsPage*` or `AllRivalsViewModel`. Full Rivals notes (data, scope, IDs, tests): [../rivals/windows.md](../rivals/windows.md).

- `AppRoute.AllRivals(RivalScope)` parses web queries (`category`, `mode=leaderboard`, `rankBy`, optional `instruments`); `category=common`/`combo` without instruments resolve against Settings at load, and an unresolvable scope shows "This rivals list could not be identified."
- Virtualized `ListView` of `RivalRowView` rows (above, then below), centred to 960 epx; rows push Rival Detail with the same scope.
- States: loading ring, shared `ServiceStatusView` (scrape freeze countdown), empty, no player.
- Header: an instrument icon or none, the title, then a subtitle (metric and rank, or the chart list) that collapses when empty (`HasSubtitle`) and wraps. The web has no subtitle; it's a native addition. Accessibility matrix pages: `all-rivals`, `all-rivals-lead`, `-board`, `-empty` and `-freeze` in `journeys/a11y.json`. Validation: [windows-accessibility.md](../../testing/windows-accessibility.md#all-rivals-validation-issue-201-2026-10-03).
- Design review (issue #201, `winui-design`/`winui-code-review`): the row container uses `OverlayCornerRadius`. Deliberate deviations:
  - The app is dark-only, so the theme dictionaries are Default plus HighContrast.
  - Strings are inline because the repo has no `.resw`.
  - Field-style `[ObservableProperty]` follows the repo convention.

## Two columns

From a 1100 epx page the list keeps a 520 epx column and the chosen rival's Rival Detail (`RivalDetailPage` in `DetailFrame`, `fst.all-rivals.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). The list switches to single selection: the first rival is selected on load, clicks and arrow keys move the detail, and the choice survives a reload while that rival is listed. Below 1100 epx, or while loading/empty, it is the single centred column and clicks push Rival Detail. The Rivals hub itself already fills wide windows with two to four masonry columns of section cards, so it has no detail pane. Journeys: `tools/windows/journeys/split-panes.json`, and `journeys/all-rivals-split.json` (UIA Select and Invoke move the detail; needs a 100% or 150% scale mode on a 300% host: `a11y_matrix.py --pages tools/windows/journeys/all-rivals-split.json --mode scale-150 --sizes wide,maximized`).
