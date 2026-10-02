# Player history — Android notes

> **What:** the Android score-history page for the selected player. **Read when:** changing `ui/profile/PlayerHistoryScreen.kt`, `PlayerHistoryViewModel` or `core/profile/PlayerHistory.kt`. Behavior: [spec.md](spec.md).

- Route `PlayerHistoryRoute(songId, instrument)`; read `FestivalApi.playerHistory` (`GET /api/player/{accountId}/history?songId=&instrument=`; 202 → Syncing, 404 → Unregistered; rows re-filtered to the song and chart). Debug: `FST_DEBUG_ROUTE=playerHistory:<songId>:<wire>`. The entry point from Song Detail or the song leaderboard belongs to the Songs lane.
- States (`HistoryPhase`): NoPlayer (no request), Loading, Unregistered, Syncing (Retry), Empty, Failed (shared service status with the scrape-freeze countdown), Loaded. A selected-player change re-reads.
- Sort: the top-bar sort action opens the shared `FestivalModalSheet` "Sort Scores" (header Reset `fst.history.sort.reset` and Close `fst.history.sort.close`) with radio modes and an Ascending/Descending segmented button. Changes apply immediately (the Material sort-sheet idiom instead of the web's Apply/Cancel modal). Default Score descending, in memory only (as on the web). The personal-best row (gold border and score) follows the sort.
- Rows (list capped at 840 dp, centered on tablets and unfolded windows): flat two-line cards (score and stars; date · season with accuracy/FC pills), one accessibility node each. Native addition: a "Score Over Time" Canvas line for 2+ dated rows, best point in gold.
- IDs: `fst.history`, `fst.history.{subtitle,rows,chart,message,retry}`, `fst.history.sort[.open|.reset]`, `fst.history.sort.mode.{date,score,accuracy,season}`, `fst.history.sort.direction.{ascending,descending}`.
