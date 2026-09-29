# Solo song leaderboard — Windows notes

> **What:** what the Windows per-song solo leaderboard implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsSongPage*`, `LeaderboardsSongRow` or `SongLeaderboardViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.SongLeaderboard(songId, instrument, page)` (Song Detail's "View Full Leaderboard"). The song resolves from the session catalogue (missing → failure state). `GET /api/leaderboard/{song}/{instrument}?top=25&offset=` with `leeway` (one decimal) only when Settings filters invalid scores. Page count uses `localEntries ?? totalEntries`; an explicit out-of-range page is corrected once totals arrive; superseded responses are dropped.
- Header scrolls with the rows inside the one `ScrollViewer` (operator batch 7.8: it scrolls away under the title bar; no gap above row one); the pinned row and pager stay below it.
- Rows: rank and score columns share the widest rank/score text on the page **including the pinned row** (web `computeRankWidth` / score `ch` width; `SongLeaderboardRowViewModel.RankChars`/`ScoreChars`), so the pinned row lines up with the list (batch 7.9); **Your Page** sits above the pinned row rather than beside it. Accuracy uses the web `AccuracyDisplay` (`ScoreBadge`): tinted pill or skewed gold FC outline, fixed 58 epx (fits "XX.X%"), no "FC" prefix (batches 7.1/7.11).
- Header: 80 epx static cover (the shell background switches to the song cover, `IBackdropPage`), title (heading 1), artist, instrument icon (keys variant for keyboard songs) + label, "N <Instrument> entries" only when `showLeaderboardEntryTotals`.
- Rows (`LeaderboardsSongRow`): rank, name, season and stars (≥520 epx rows only), accuracy pill ("FC 98.5%"), score; below 400 epx the column minimums drop so rank, name, pill and score stay visible. The selected player's row opens Statistics, anyone else their profile; rows without a usable account ID are not interactive.
- Selected player: highlighted in place, and pinned above the pager from `FestivalSession.SelectedScoreIndex` (no extra read), only while `IsSelectedProfileCurrent` (same publication). With invalid-score filtering on, an invalid score uses its valid variant (shown unranked, no jump) or no pinned row. **Your page** jumps to their page when their row is elsewhere; the list scrolls to the highlighted row after a page change. The web footer never re-pages (native addition, as on iPhone).
- Shared pager (`fst.song-leaderboard.page-*`), Back restores the page (kept view model), F5 reloads.

## Evidence

Fixture: `windows/reports/screenshots/song-leaderboard-{medium,compact,selected-medium}.png`.

## IDs

`fst.song-leaderboard.title`, `.instrument`, `.list`, `.row.<accountId>`, `.spotlight-footer`, `.spotlight-jump`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- Paging does not rewrite the back-stack route (the spec's native correction): Back restores from the kept view model, but a copied deep link has no page state.
- Announced page change uses a polite live region on the page text only; Narrator pass pending.
