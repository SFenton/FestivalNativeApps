# Solo song leaderboard — Windows notes

> **What:** what the Windows per-song solo leaderboard implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsSongPage*`, `Controls/LeaderboardEntryRow` or `SongLeaderboardViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.SongLeaderboard(songId, instrument, page)` (Song Detail's "View Full Leaderboard"). The song resolves from the session catalogue (missing → failure state). `GET /api/leaderboard/{song}/{instrument}?top=25&offset=` with `leeway` (one decimal) only when Settings filters invalid scores. Page count uses `localEntries ?? totalEntries`; an explicit out-of-range page is corrected once totals arrive; superseded responses are dropped.
- Header scrolls with the rows inside the one `ScrollViewer` (operator batch 7.8: it scrolls away under the title bar; no gap above row one); the pinned row and pager float over the bottom of the rows (`Controls/BoardFooter`, web fixed footer).
- Footer edge (issue #93, web `useScrollMask` over a viewport that ends at the footer): rows fade out over 40 epx just above the footer's top (the **Your Page** button when shown) and are hidden beneath it; the band eases out over the last 40 epx of scroll so the last row is clear at the end (`Controls/BoardFooterFade` on `BoardFadeSource`/`BoardFadeHost`, `Festival.Core/Domain/BoardFooterEdgeFade`). Contrast themes, Windows transparency effects off, Increase Contrast and Less Transparency keep the plain list under the footer's solid surfaces. Composition-only: hit testing, focus and UIA still use the real rows.
- Rows: rank and score columns share the widest rank/score text on the page **including the pinned row** (web `computeRankWidth` / score `ch` width; `SongLeaderboardRowViewModel.RankChars`/`ScoreChars`), so the pinned row lines up with the list (batch 7.9); **Your Page** sits above the pinned row rather than beside it. Accuracy uses the web `AccuracyDisplay` (`ScoreBadge`): tinted pill or skewed gold FC outline, fixed 58 epx (fits "XX.X%"), no "FC" prefix (batches 7.1/7.11).
- Header: 80 epx static cover (the shell background switches to the song cover, `IBackdropPage`), title (heading 1), artist, instrument icon (keys variant for keyboard songs) + label, "N <Instrument> entries" only when `showLeaderboardEntryTotals`.
- Rows (shared `LeaderboardEntryRow`, operator batch 7.7; web `LeaderboardEntry` column order): rank, name, season (rows from 520 epx), score, accuracy badge (gold skewed outline for FC), stars (rows from 700 epx), chevron; separate frosted rows 4 epx apart; below 420 epx the column gaps tighten. The selected player's row opens Statistics, anyone else their profile; rows without a usable account ID are not interactive.
- Selected player: highlighted in place, and pinned above the pager from `FestivalSession.SelectedScoreIndex` (no extra read), only while `IsSelectedProfileCurrent` (same publication). With invalid-score filtering on, an invalid score uses its valid variant (shown unranked, no jump) or no pinned row. **Your page** jumps to their page when their row is elsewhere; the list scrolls to the highlighted row after a page change. The web footer never re-pages (native addition, as on iPhone).
- Shared pager (`fst.song-leaderboard.page-*`; batch 7.4: keyboard paging, hidden for one page; journey `tools/windows/journeys/boards-ui.json`), Back restores the page (kept view model), F5 reloads.
- Load-swap gate (issue #71): first load, F5, invalid-score leeway reloads and paging run the shared web sequence (300 ms content-out, centered ring, 500 ms ring-out, row stagger). The new rows/empty/error state commits while hidden and rapid selections are latest-wins; Reduce Motion swaps immediately. Only the rows (or "No scores yet.") take the content role: the song header, pinned row and pager stay in place while another page loads (issue #93, web `PaginatedLeaderboard` keeps its pagination mounted; `ShowContent` follows the committed state only). A failed reload still replaces the page with the failure state.

## Evidence

Fixture: `windows/reports/screenshots/song-leaderboard-{medium,compact,selected-medium}.png`.

## IDs

`fst.song-leaderboard.title`, `.instrument`, `.list`, `.row.<accountId>`, `.spotlight-footer`, `.spotlight-jump`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- Paging does not rewrite the back-stack route (the spec's native correction): Back restores from the kept view model, but a copied deep link has no page state.
- Announced page change uses a polite live region on the page text only; Narrator pass pending.
