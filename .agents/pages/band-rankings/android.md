# Band rankings — Android notes

> **What:** what the Android paginated band rankings page implements and its open gaps. **Read when:** changing `ui/leaderboards/BandRankingsScreen.kt` or `BandRankingsViewModel`. Behavior: [spec.md](spec.md); shared layout and pager: [full-rankings/android.md](../full-rankings/android.md).

## Implemented

- `BandRankingsRoute(bandType)` (unknown → Duos). 25-row pages of `GET /api/rankings/bands/{bandType}?rankBy=&page=&pageSize=25`; page count from `totalTeams`; out-of-range pages corrected; superseded responses dropped. Uses the Bands lane's `core/bands` `BandType`, `BandRankingMetric` and `BandMember` (roster joined with ` + `, web `formatBandTeamName`).
- Title "<Size> Rankings"; band-size and band Rank By pickers (no Max Score). The metric starts from the persisted Leaderboards Rank By narrowed like `coerceBandRankingMetric` and is then local to the page. Switching either returns to page 1; switching or paging runs the shared load swap (issue #71; spinner `fst.band-rankings.loading`).
- Rows open `BandRoute(bandId, bandType, teamKey)` so Band Detail resolves via the safe `?teamKey=` read, never `/api/bands/{bandId}` or the bare `/{bandType}/{teamKey}` route ([service safety](../../platforms/service-safety.md)). Rows without a path-safe `bandId`/`teamKey` are shown but not interactive. Rows containing the selected player are highlighted.

## IDs

`fst.band-rankings.list`, `.population`, `.band-type-menu` (items `.band-type-menu.<n>`), `.rank-by-menu` (items `.<n>`), `.pager`, `.page-*`, `.supporting-pane`, `.bottom-bar`, `fst.band-rankings.row.<teamKey>`.

## Open

- No selected-band pinned row (Android has no selected-band identity) and no band-combo filter.
