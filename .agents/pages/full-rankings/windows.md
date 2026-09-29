# Full rankings — Windows notes

> **What:** what the Windows paginated global rankings page implements, its live findings and open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsFullRankingsPage*` or `FullRankingsViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md); band variant: [band-rankings/windows.md](../band-rankings/windows.md).

## Implemented

- Route `AppRoute.FullRankings(instrument, rankBy)` (unknown or missing `rankBy`, including a bare `/leaderboards/all` deep link, → Total Score, web `DEFAULT_METRIC`). 25-row pages of `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=25`; page count `ceil(totalAccounts / 25)` (≥1); an out-of-range page is clamped once totals arrive; a superseded response (older instrument/metric/page) is dropped.
- Header: instrument icon, "<Instrument> Rankings" (heading 1), "N ranked players"; instrument switcher (Settings-visible charts plus the current one) and Rank By, both radio `MenuFlyout`s; switching either returns to page 1. The picker's instrument icon and the Rank By glyph render at the same 18 epx height (operator 2026-09-28; the icon is never shrunk). Rows read "X / Y" (web `getSongsLabel`). The selected player's spotlight loads behind a white ring with no subtitle.
- Rows in a card (`ItemsRepeater` in a `ScrollViewer`); the selected player's row is highlighted. A page change scrolls to the top, or to the selected row when it is on the new page.
- Pinned "your rank" row above the pager when the selected player is not on the page (own-row read is per instrument, independent of the page), with **Your page** (`LeaderboardPaging.PageForRank`): a native addition — the web footer only links to the profile. Loading / unranked / inline-failure states as on the overview.
- Shared pager (`LeaderboardsPager`): First · Previous · "page / total" (polite live region, "Page 2 of 34,760") · Next · Last; First/Last collapse below 380 epx.
- Back restores the page, switcher and metric: pushed pages keep their view model per back-stack entry (`LeaderboardsPageState`, keyed by the route object Frame hands back).
- Indeterminate progress bar over the current rows while another page loads; full-page `ServiceStatusView` on failure.

## Live findings (2026-09-28)

- Production serves ranking rows with an **empty `accountId` and no `displayName`** (Lead, Total Score, rank 15). Validating every row's ID rejected the whole page; such rows are now accepted, shown as "Unknown User" and not interactive (`AccountRankingEntry.HasProfile`). The same tolerance applies to band rows without `bandId`/`teamKey` and solo chart rows.
- Lead Total Score: 869,000 ranked players (34,760 pages); a rank-40 selected player's pinned row and Your page → page 2 verified live.

## Layout

| Window | Result |
|---|---|
| Wide / medium | Switchers beside the title; list max width 1100 epx |
| Compact | Switchers below the title, instrument switcher icon-only, 12 epx padding, pager without First/Last |

## Evidence

Fixture: `windows/reports/screenshots/full-rankings-{medium,compact,selected-wide}.png`. Live captures (not committed): `C:\Users\sfent\workspace\showcase\win-leaderboards\live-full-rankings-*.png`, `live-spotlight-full-*.png`.

## IDs

`fst.full-rankings.title`, `.list`, `.instrument-menu`, `.instrument.<instrument>`, `.page-first|page-previous|page-info|page-next|page-last`, `.spotlight-footer`, `.spotlight-footer.loading`, `.spotlight-footer.unranked`, `.spotlight-jump`, shared `fst.rankings.rank-by-menu`, `fst.rankings.rank-by.<metric>`, `fst.rankings.row.<accountId>`.

## Open

- Paging does not update the back-stack route (a restored page comes from the kept view model, not the route).
- No band-combo filter; no percentile/rank-history extras.

## Pager (operator batch 6.30)

`Controls/LeaderboardsPager` follows the web `Paginator` + `LeaderboardPaginationFooter`: round 40 epx card-surface buttons (double chevrons for first/last, single for previous/next) either side of a small "page / total" badge, no plate behind them. The selected player's row sits in its own rows card directly above it. Shared by Full Rankings, Band Rankings and song leaderboards.

## Two columns (wide)

From a 1100 epx page the rankings keep a 560 epx column and the chosen player's profile (`PlayerProfilePage` in `DetailFrame`, `fst.full-rankings.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). The profile starts on the selected player's row when it is on the page, else the first row; it follows row clicks (rows ask an `IRouteHost` ancestor before pushing) and survives paging while that player is still listed. The shown player's row gets a subtle fill (`LeaderboardsRankingRow.IsCurrent`). Below 1100 epx, or without rows, the page is the single 1100 epx column again. Band Rankings and All Rivals use the same split ([band-rankings](../band-rankings/windows.md#two-columns), [all-rivals](../all-rivals/windows.md#two-columns)).
