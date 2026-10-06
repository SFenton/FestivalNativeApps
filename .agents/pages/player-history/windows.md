# Player history — Windows notes

> **What:** the Windows score-history page for the selected player. **Read when:** changing the Player History route, `PlayerHistoryViewModel` or `PlayerHistoryModels`. Behavior: [spec.md](spec.md).

- **Folded into Song Detail (operator 6.39):** `AppRoute.PlayerHistory` now opens Song Detail with the chart selected and scrolled to its Score History section — see [song-detail/windows.md](../song-detail/windows.md). The notes below describe the retired standalone page (`PlayerHistoryPage`, deleted in #315 because it was unrouted and kept a copied song header; its sort menu, row states and `fst.history.*` IDs carried over to Song Detail, and `PlayerHistoryViewModel` stays for its tests).
- Route `AppRoute.PlayerHistory(songId, instrument)` → `PlayerHistoryPage` (before 6.39); read `GET /api/player/{accountId}/history?songId=&instrument=` via `FestivalApiClient.GetPlayerHistoryAsync` (202 → Syncing, 404 → Unregistered; rows re-filtered to the song/chart like the web). Entry point: Song Detail (Songs lane).
- States (`PlayerHistoryPhase`): NoPlayer (no request), Loading, Unregistered ("registered users only"), Syncing (Retry), Empty, Failed (`ServiceStatusView`), Loaded. A selected-player change re-reads (per-entity reset).
- Sort: a `DropDownButton` + `MenuFlyout` with radio items (Date/Score/Accuracy/Season, Ascending/Descending, Reset) that applies immediately. This Fluent command-menu idiom replaces the web modal with Apply/Cancel. Default Score descending; not persisted (matches the web). The personal-best row (gold stroke and score) follows the sort (`HighScoreIndex`).
- Rows: virtualized `ListView` of two-line cards (score + star images (`StarRow`); date · season + accuracy/FC pills) that fit compact widths. Accuracy uses the leaderboard scale (the service stores an int).
- Native addition: "Score Over Time" line (`ScoreHistoryChart`) for 2+ dated rows, personal best in gold, month/day axis labels.
- Song header: the route opens Song Detail scrolled to Score History, so the song title users see there is Song Detail's pinned `SongHeaderText Variant="Bar"` (`fst.song-detail.pinned-title`, `.pinned-artist`; [song-header](../../patterns/song-header.md) R4, #315); `song-header-title.json` `player-history-*` and `a11y-song-header-text.json` `song-header-text-history` check it on that route.
- IDs (Song Detail section): `fst.history`, `fst.history.{subtitle,rows,chart,message}`, `fst.history.sort.open`, `fst.history.sort.mode.{date,score,accuracy,season}`, `fst.history.sort.direction.{ascending,descending}`, `fst.history.sort.reset`.
- Fixture: `tools/mock_service.py` history rows use the production int accuracy scale (`991200`); `fixture-history-multi` has 8 Lead / 2 Bass / 3 Drums points (paging), `fixture-history-fail` returns 500 (failed state).

## Validation (issue #198)

Validated the route (`/songs/<id>/<instrument>/history` → Song Detail Score History) with the `winui-design` / `winui-code-review` skills.

| Configuration | Result |
| --- | --- |
| Compact 500, medium 900, wide 1440, portrait tablet 800, snap-left/right, maximized | Chart pages by width (fewer bars when narrow), card centred, no clipping (live SFentonX "Through the Fire and Flames" Lead; fixtures). |
| Dark (the only app theme; no light theme by design) | Pass. |
| Contrast (Night sky, Desert) | **Fixed:** bars kept brand hues; now `FSTChart*Brush` roles (outlined bars, Highlight line/selection), redraw on theme switch. |
| Text 200% | **Fixed:** rotated axis titles overlapped tick labels and "1000k" clipped; axis/date bands and bar slots now scale with `TextScaleLayout.Factor`. |
| Display scale | Host monitor runs at 300%; layout uses effective pixels. 100%/150% could not be switched on the shared host. |
| Keyboard / Narrator (UIA) | **Fixed:** selecting a bar dropped focus to the pager (redraw) and bars had no selected state; bars are now `ToggleButton`s that keep focus, Left/Right move between them. Plot name was stale after paging; Retry buttons, error and detail lacked IDs (IDs on peer-less elements). |
| Axe (axe-windows) | 0 issues: compact, medium, wide, Night sky, Desert, text 200% (fixtures); live compact, medium, wide, maximized, snap-left, Night sky and text 200%. A focused bar's keyboard tooltip adds WinUI's windowed-popup `BoundingRectangleCompletelyObscuresContainer` (framework `PopupHost` internals, no app element; same as [windows-accessibility.md](../../testing/windows-accessibility.md) item 8). |

Automated: `tools/windows/journeys/profile.py` `history` (sort Date/asc/reset, bar toggle + detail), `history-paging`, `history-syncing` (202 + Retry), `history-failed` (500 + Retry), `history-anonymous` (route redirects to Songs because `AppRouteParser.RequiresPlayer`; the section is hidden on Song Detail), `history-unregistered` (404 hides), `history-no-rows`. The locked console blocks real Tab/mouse input, so focus and toggles go through UIA patterns.
