# Band rankings — Windows notes

> **What:** what the Windows paginated band rankings page implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsBandRankingsPage*` or `BandRankingsViewModel`. Behavior: [spec.md](spec.md); account variant: [full-rankings/windows.md](../full-rankings/windows.md).

## Implemented

- Route `AppRoute.BandRankings(bandType)` (unknown type → Duos). 25-row pages of `GET /api/rankings/bands/{bandType}?rankBy=&page=&pageSize=25` (publication-pinned pure read); page count from `totalTeams`; out-of-range pages clamped; superseded responses dropped.
- Header: "<Size> Rankings" (heading 1), "N ranked bands"; band-size switcher (Duos · Trios · Quads) and band Rank By (no Max Score; starts from the persisted Leaderboards metric narrowed like `coerceBandRankingMetric`). Switching returns to page 1.
- Rows: rank, roster ("Unknown User" for blank member names), songs, rating; a row opens `AppRoute.Band(bandId, bandType, teamKey)` so Band Detail uses the safe rankings read, never `/api/bands/{bandId}` ([service-safety](../../platforms/service-safety.md)). Rows without `bandId`/`teamKey` are shown but not interactive.
- Shared pager and Back-state behavior as Full Rankings; compact collapses the band-size label to its icon.

## Evidence

Fixture: `windows/reports/screenshots/band-rankings-wide.png`; journey steps in `tools/windows/journeys/leaderboards.steps`.

## IDs

`fst.band-rankings.title`, `.list`, `.band-type-menu`, `.band-type.<bandType>`, `.rank-by-menu`, `.rank-by.<metric>`, `.page-first|page-previous|page-info|page-next|page-last`, `.row.<teamKey>`.

## Open

- No selected-band pinned row (no selected-band identity on Windows) and no band-combo filter.

## Two columns

From a 1100 epx page the rankings keep a 560 epx column and the chosen band's Band Detail (`BandsDetailPage` in `DetailFrame`, `fst.band-rankings.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). It starts on the first openable row, follows row clicks (`IRouteHost`) and survives paging while that band is listed; its row gets `LeaderboardsRankingRow.IsCurrent`. Below 1100 epx, or without openable rows, the page is one 1100 epx column. Journey: `tools/windows/journeys/split-panes.json`.
