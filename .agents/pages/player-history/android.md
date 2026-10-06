# Player history — Android notes

> **What:** the Android score-history page for the selected player. **Read when:** changing `ui/profile/PlayerHistoryScreen.kt`, `PlayerHistoryViewModel` or `core/profile/PlayerHistory.kt`. Behavior: [spec.md](spec.md).

- Route `PlayerHistoryRoute(songId, instrument)`; read `FestivalApi.playerHistory` (`GET /api/player/{accountId}/history?songId=&instrument=`; 202 → Syncing, 404 → Unregistered; rows re-filtered to the song and chart). Debug: `FST_DEBUG_ROUTE=playerHistory:<songId>:<wire>`. The entry point from Song Detail or the song leaderboard belongs to the Songs lane.
- States (`HistoryPhase`): NoPlayer (no request), Loading, Unregistered, Syncing (Retry), Empty, Failed (shared service status with the scrape-freeze countdown), Loaded. A selected-player change re-reads.
- Sort: the sort action (top app bar; the floating toolbar on compact windows) opens the shared `FestivalModalSheet` "Sort Scores" (header Reset `fst.history.sort.reset` and Close `fst.history.sort.close`) with a "Sort By" heading over radio modes and a "Sort Direction" heading over an Ascending/Descending segmented button (the shared sort-sheet section headers). The sheet opens fully expanded (shared default) and its body `fst.history.sort.form` scrolls under the pinned header, so the direction stays reachable in landscape phones at font scale 2.0 (issue #105: the half-height sheet left it off-screen). Changes apply immediately (the Material sort-sheet idiom instead of the web's Apply/Cancel modal). Default Score descending, in memory only (as on the web). The personal-best row (gold border and score) follows the sort.
- Rows (list capped at 840 dp, centered on tablets and unfolded windows): flat two-line cards `fst.history.row` (score and stars; date · season with accuracy/FC pills), one accessibility node each. Native addition: a "Score Over Time" Canvas line for 2+ dated rows, best point in gold, its start and end dates under the plot's ends (not the score-axis gutter, #314); the chart is one TalkBack stop (its summary names the range and best score; axis labels are not separate stops) read before the rows.
- Half-open book fold (separating vertical hinge, `ui/leaderboards/rememberHingeSplit`): subtitle and chart on the start panel (`fst.history.summary`), rows on the end panel (`fst.history.rows`), in `fst.history.split`; M3 never lays content across a hinge. Under TalkBack or large text the shared single-column rule (`rememberSingleColumn`) keeps one column. Flat folds (unfolded Book/Passport, TriFold) keep the centred column.
- IDs: `fst.history`, `fst.history.{subtitle,rows,row,chart,summary,split,message,retry}`, `fst.history.sort[.open|.reset|.close|.form]`, `fst.history.sort.mode.{date,score,accuracy,season}`, `fst.history.sort.direction.{ascending,descending}`.
- Tests: `PlayerHistoryUiTest.kt` (Robolectric: loaded/sort/announcements, single row without chart, empty chart, no-player redirect and standalone NoPlayer, 202 Syncing + Retry, failed read + Retry, landscape 2.0 sheet scroll, hinge split and single column), `ProfileUiTest` history cases, connected `ProfileDeviceJourneyTest.historySortSheet` (also asserts nothing straddles a half-open hinge).

## Validation (issue #105, live public service)

| Configuration | Result |
|---|---|
| FST_Phone portrait 1.0/2.0, landscape 1.0 | Pass. At 2.0 the shared top bar truncates the title and the bell badge overlaps the avatar (shell, not this page). |
| FST_Phone landscape 2.0 | Fixed: sort sheet now opens fully and scrolls to Sort Direction. |
| FST_Tablet landscape/portrait, 1.0/2.0 | Pass; list centred at 840 dp. |
| FST_Resizable phone/foldable/tablet/desktop | Pass. Desktop 2.0: the shared expanded drawer wraps long labels (shell). |
| FST_Book_Fold unfolded/folded | Pass. Half-open: fixed (content no longer crosses the hinge). |
| FST_Passport_Fold unfolded/half/folded (1.0/2.0) | Pass; half-open uses the hinge split. |
| FST_TriFold unfolded/partial/folded (1.0/2.0) | Pass (flat folds: one column). |
| TalkBack (FST_Phone) | Fixed chart order (one stop before the rows). Page: back, title, actions, subtitle, heading, chart, rows, tabs, sort. Sheet: Sort By heading, radios with n of 4 and state, Sort Direction heading, Ascending/Descending with state, Reset/Close. The floating-toolbar sort action reads after the tabs (shared shell order). |
| Reduced motion (animator scales 0, the device default) | Content and sheet appear without animation; nothing waits on the fade-in. |

Deliberate deviations: the app is dark-only by design (`.agents/design/android.md`), so system light theme renders the same; chart axis labels keep a fixed size (`LargeText.kt`); the sort sheet stays a bottom sheet on expanded windows (shared `FestivalModalSheet`) rather than an M3 side sheet.
