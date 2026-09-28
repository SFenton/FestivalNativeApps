# Full rankings — Android notes

> **What:** what the Android paginated instrument rankings page implements and its open gaps. **Read when:** changing `ui/leaderboards/FullRankingsScreen.kt`, `RankingsBoardScaffold.kt` or `FullRankingsViewModel`. Behavior: [spec.md](spec.md); overview and code map: [leaderboards/android.md](../leaderboards/android.md).

## Implemented

- `FullRankingsRoute(instrument, rankBy)` (default `totalscore`, the web default; unknown values fall back to it). 25-row pages of `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=25`; page count `ceil(totalAccounts / 25)` (≥ 1); an out-of-range page is corrected once totals arrive; a newer request cancels an older one so a superseded page never lands.
- Title "<Instrument> Rankings"; instrument picker (Settings-visible charts plus the current one, with icons) and Rank By picker as outlined dropdown buttons; "N ranked players". Switching either returns to page 1 and shows the skeleton; paging keeps the previous page visible under a progress bar (`FullRankingsViewModel.displayed`).
- Selected player: highlighted in place and scrolled into view (`BringIntoViewRequester`) when on the page; otherwise a pinned row above the pager from the per-instrument own-row read (independent of page and metric) with **Your Page** (`LeaderboardPaging.pageForRank`) — a native addition, the web footer only links to the profile. Loading, "Not yet ranked" and inline-failure states as on the overview.
- Shared pager (`RankingsPager`): First · Previous · "page / total" (polite live region, spoken "Page 2 of 34,760") · Next · Last, 48 dp targets; First/Last drop below 360 dp.
- Anonymous rows: "Unknown User", not interactive ([spec live quirk](spec.md#live-data-quirk-2026-09-28)).

## Layout (`RankingsBoardScaffold`, shared with Band Rankings and the song leaderboard)

| Width / posture | Result |
|---|---|
| Compact and medium (< 840 dp) | Pickers scroll with the rows; the "your rank" row and pager stay pinned above the bottom bar |
| Expanded (≥ 840 dp: book/passport unfolded with rail, tablet, tri-fold unfolded) | Rows in the list pane; pickers, population, your-rank row and pager in a 360 dp supporting pane |
| Separating vertical hinge (book half-open) | Rows on the leading side of the fold, the supporting pane on the other side |

## IDs

`fst.full-rankings.list`, `.population`, `.instrument-menu` (items `.instrument-menu.<n>`), `.supporting-pane`, `.bottom-bar`, `.pager`, `.page-first|page-previous|page-info|page-next|page-last`, `.spotlight-footer`, `.spotlight-footer.loading`, `.spotlight-footer.unranked`, `.spotlight-jump`, shared `fst.rankings.rank-by-menu` (items `.<n>`), `fst.rankings.row.<accountId>`.

## Open

- Paging and picker changes do not rewrite the back-stack route (the spec's native correction); the view model keeps the state across Back and configuration changes, but not across process death.
- No band-combo filter; no percentile/rank-history extras.
