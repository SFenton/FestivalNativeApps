# Player history — Windows notes

> **What:** the Windows score-history page for the selected player. **Read when:** changing `windows/Festival.App/Pages/PlayerHistoryPage*`, `PlayerHistoryViewModel` or `PlayerHistoryModels`. Behavior: [spec.md](spec.md).

- Route `AppRoute.PlayerHistory(songId, instrument)` → `PlayerHistoryPage`; read `GET /api/player/{accountId}/history?songId=&instrument=` via `FestivalApiClient.GetPlayerHistoryAsync` (202 → Syncing, 404 → Unregistered; rows re-filtered to the song/chart like the web). Entry point: Song Detail (Songs lane).
- States (`PlayerHistoryPhase`): NoPlayer (no request), Loading, Unregistered ("registered users only"), Syncing (Retry), Empty, Failed (`ServiceStatusView`), Loaded. A selected-player change re-reads (per-entity reset).
- Sort: a `DropDownButton` + `MenuFlyout` with radio items (Date/Score/Accuracy/Season, Ascending/Descending, Reset) that applies immediately. This Fluent command-menu idiom replaces the web modal with Apply/Cancel. Default Score descending; not persisted (matches the web). The personal-best row (gold stroke and score) follows the sort (`HighScoreIndex`).
- Rows: virtualized `ListView` of two-line cards (score + star images (`StarRow`); date · season + accuracy/FC pills) that fit compact widths. Accuracy uses the leaderboard scale (the service stores an int).
- Native addition: "Score Over Time" line (`ScoreHistoryChart`) for 2+ dated rows, personal best in gold, month/day axis labels.
- IDs: `fst.history`, `fst.history.{subtitle,rows,chart,message}`, `fst.history.sort.open`, `fst.history.sort.mode.{date,score,accuracy,season}`, `fst.history.sort.direction.{ascending,descending}`, `fst.history.sort.reset`.
- Fixture gap: `tools/mock_service.py` history rows send `accuracy` as a 0–1 fraction (`0.9912`), which renders as 0%; production sends the int scale. TODO(orchestrator): fix the fixture.
