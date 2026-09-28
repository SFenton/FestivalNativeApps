# Full rankings — Android notes

> **What:** what the Android paginated instrument rankings page implements, where its controls live and why, and its open gaps. **Read when:** changing `ui/leaderboards/FullRankingsScreen.kt`, `RankingsBoardScaffold.kt` or `FullRankingsViewModel`. Behavior: [spec.md](spec.md); overview and code map: [leaderboards/android.md](../leaderboards/android.md).

## Implemented

- `FullRankingsRoute(instrument, rankBy, page)` (defaults `totalscore`, page 1; unknown values fall back). 25-row pages of `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=25`; page count `ceil(totalAccounts / 25)` (≥ 1); an out-of-range page is corrected once totals arrive; a newer request cancels an older one so a superseded page never lands.
- **Route follows the board** (spec native correction): `SyncRouteArguments` writes the current instrument, metric and page back into the back-stack entry's `SavedStateHandle`, and the entry is decoded with `savedStateHandle.toRoute()`, so Back to the board and a recreated entry (process death) restore the same page. Debug deep link: `fullRankings:<instrument>[:<page>]`.
- Title "<Instrument> Rankings"; the instrument (current chart icon → menu of Settings-visible charts plus the current one) and Rank By (sort icon → metric menu) are **screen actions** (`TopBarChoiceAction`). Above the rows: "N ranked players · <metric>". Switching either returns to page 1 and shows the skeleton; paging keeps the previous page visible under a progress bar.
- Selected player: highlighted in place and scrolled into view when on the page; otherwise an anchored "your rank" card above the pager from the per-instrument own-row read, with **Your Page** (`LeaderboardPaging.pageForRank`) — a native addition, the web footer only links to the profile. Loading, "Not yet ranked" and inline-failure states in the same card.
- Shared pager (`RankingsPager`): a floating pill (First · Previous · "page / total" · Next · Last, 48 dp targets, polite live region "Page 2 of 34,760"); First/Last drop below 360 dp.
- Anonymous rows: "Unknown User", not interactive ([spec live quirk](spec.md#live-data-quirk-2026-09-28)).

## Control placement (decision, 2026-09-28)

| Control | Where | Why |
|---|---|---|
| Instrument, Rank By | Screen actions: the shell's floating toolbar on compact windows (< 600 dp, with global search), top app bar next to search on medium and wider | They change *what* the whole page shows (scope and sort), which Material 3 puts in top app bar actions and Fluent 2 in the page's command bar; the M3 Expressive floating toolbar is the compact home for page-contextual actions ([app-navigation](../../controls/app-navigation/android.md)). Anchoring them above the pager instead would stack pickers, the "your rank" card and the pager at the bottom — about a third of a phone viewport — and separate the scope from the title it changes |
| Pager, "your rank" card | Bottom-anchored over the rows, above the bottom bar / floating toolbar, on every width | Page-to-page navigation is repeated while reading, so it stays within thumb reach (M3 bottom-anchored controls; the web's floating paginator). The list reserves the anchored height as bottom padding, so the last row scrolls clear |

## Layout (`RankingsBoardScaffold`, shared with Band Rankings and the song leaderboard)

| Width / posture | Result |
|---|---|
| Every width without a separating hinge (phone, folded, unfolded, tablet, tri-fold) | Rows fill the pane; "your rank" card and floating pager anchored bottom-centre (at most 720 dp wide) |
| Separating vertical hinge (book half-open) | Rows on the leading side of the fold; page information at the top and the anchored "your rank" card + pager at the bottom of the other side |

## IDs

`fst.full-rankings.list`, `.population`, `.instrument-menu` (items `.instrument-menu.<n>`), `.bottom-bar` (anchored footer + pager), `.supporting-pane` (hinge only), `.pager`, `.page-first|page-previous|page-info|page-next|page-last`, `.spotlight-footer`, `.spotlight-footer.loading`, `.spotlight-footer.unranked`, `.spotlight-jump`, shared `fst.rankings.rank-by-menu` (items `fst.rankings.rank-by.<metric>`), `fst.rankings.row.<accountId>`.

## Open

- No band-combo filter; no percentile/rank-history extras on this page (the overview has the rank-history card).
