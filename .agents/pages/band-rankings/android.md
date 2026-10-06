# Band rankings — Android notes

> **What:** what the Android paginated band rankings page implements and its open gaps. **Read when:** changing `ui/leaderboards/BandRankingsScreen.kt` or `BandRankingsViewModel`. Behavior: [spec.md](spec.md); shared layout and pager: [full-rankings/android.md](../full-rankings/android.md).

## Implemented

- `BandRankingsRoute(bandType)` (unknown → Duos). 25-row pages of `GET /api/rankings/bands/{bandType}?rankBy=&page=&pageSize=25`; page count from `totalTeams`; out-of-range pages corrected; superseded responses dropped. Uses the Bands lane's `core/bands` `BandType`, `BandRankingMetric` and `BandMember` (roster joined with ` + `, web `formatBandTeamName`).
- Title "<Size> Leaderboards"; band-size and band Rank By pickers (no Max Score). The metric starts from the persisted Leaderboards Rank By narrowed like `coerceBandRankingMetric` and is then local to the page. Switching either returns to page 1; switching or paging runs the shared load swap (issue #71; spinner `fst.band-rankings.loading`).
- Rows open `BandRoute(bandId, bandType, teamKey)` so Band Detail resolves via the safe `?teamKey=` read, never `/api/bands/{bandId}` or the bare `/{bandType}/{teamKey}` route ([service safety](../../platforms/service-safety.md)). Rows without a path-safe `bandId`/`teamKey` are shown but not interactive. Rows containing the selected player are highlighted.
- **Footer fade** (issue #116): `RankingsBoardScaffold(fadeAboveFooter = true)`. Rows fade out above the floating pager, and the list ends at the pager's top (`clipAboveFooter`). Rows no longer pass visibly between and under the page buttons, and hidden rows leave touch and TalkBack ([song-leaderboard/android.md](../song-leaderboard/android.md)). Under Increase Contrast or Reduce Transparency the list keeps the hard edge at the same height.
- **Narrow panes stack rows** (issue #116): the half-open book fold's list pane is about 261 dp wide. One-line columns (rank ≥ 44, songs, 9–10-digit score, chevron) used to collapse the roster column to 0 dp, so rows showed only rank, songs and score. The page measures its row width and passes `rememberBandColumns(stackBelow = rowWidth)`. When `LeaderboardColumnLayout.rankingNameRoom` leaves the name less than `MIN_NAME_WIDTH` (72 dp), the plan is `stacked` and rows use the large-text `StackedRankingRow`: rank, then the full roster, the score and songs. Stacking is opt-in (`LeaderboardSection.stackNarrowNames`), so Full Rankings, Compete and the Leaderboards overview are unchanged. Before the first layout (unknown width), rows stay on one line. Live phone rows (about 77 dp for the name) stay on one line and truncate names. The full roster is in the row's TalkBack label. Tests: `LeaderboardColumnLayoutTest.bandRows*`, `BandRankingsRowLayoutUiTest`.
- **Large-text roster budget** (issue #188): at large text the roster reserves one line per member (`stackedBandNameLines`: Duos 2, Trios 3, Quads 4), the same budget the Leaderboards band cards' skeleton reserves, so rows of one band size share a height; a longer roster still wraps. Narrow stacked rows at normal text keep the roster at its own length ([leaderboard-row](../../patterns/leaderboard-row.md) agent decision).

## Validation (issue #116, live service)

Live Duos, Trios and Quads (1,816,766 ranked Duos), with SFentonX selected. Captures are in the issue.

| Configuration | Result |
|---|---|
| FST_Phone portrait / landscape, font 1.0 / 2.0 | **Bug, fixed:** rows passed visibly between and under the floating pager and stayed in touch and TalkBack. Fixed with the footer fade. Font 2.0 stacks rows (rank, roster, score, songs) without clipping. The title ellipsizes at 2.0 (`Duos Leader…`): this is the standard single-line M3 top app bar, accepted as in #103. Paging 1 → 2 and Rank By (FC Rate) work. |
| FST_Tablet landscape / portrait, font 2.0 | OK: drawer in landscape, rail in portrait, full names on one line, pager centered under the fade. At 2.0 the rows stack. |
| FST_Resizable phone · foldable · tablet · desktop, desktop font 2.0 | OK: bottom bar → rail → drawer, fade at every width. |
| FST_Book_Fold folded / half / unfolded, half font 2.0 | **Half-open bug, fixed:** in the 261 dp list pane, names disappeared. Rows now stack with full rosters, and the population and pager sit in the trailing pane. Folded and unfolded rows are unchanged. Half-open at font 2.0 stays one column with stacked rows: `rememberHingeSplit` drops the split under large text and TalkBack by design (`rememberSingleColumn`). |
| FST_Passport_Fold folded / half / unfolded, unfolded font 2.0 | OK: half-open splits and stacks, unfolded shows full names on one line, and 2.0 stacks. |
| FST_TriFold folded / partial / unfolded, font 2.0 | OK. On the folded cover screen (about 360 dp), rows stack with full rosters, and the compact pager drops first/last. Partial and unfolded are a flat fold, single column with one-line rows. Rail labels hide at 2.0 per the shell. |
| Light theme | No effect: the app is dark-only by design ([design/android.md](../../design/android.md)). |
| Reduced motion (animator 0) / animations on | Captures ran at animator 0: the paging swap and backdrop snap (`LoadSwapPolicy`). With animations on, a page change fades, spins and staggers rows in (recording in the issue). |
| Robolectric `BandRankingsUiTest` (phone, row layout, large text) | Covers loading → rows, paging and band-size/Rank By switches, initial failure with Retry, inline failure after a page change, empty page, one-line versus stacked rows by pane width, and large text. |
| Connected `BandRankingsJourneyTest` (ATF) | Passes on FST_Phone and FST_Book_Fold (half) with no ATF errors. It covers reading order (title → population → rows → pager), the band-size and Rank By menus, paging, and opening a band. Coverage gate: logic 98.0%, UI 94.1%. |

**Deliberate deviations from the web or M3:** the pager always shows (web hides it on a single page; the pinned footer keeps page context). Rank By is always offered. There is no band-combo filter or selected-band footer, because Android has no selected-band identity. Population text uses the primary text role. The empty copy is "No ranked bands yet.". The app is dark-only.

## IDs

`fst.band-rankings.list`, `.population`, `.band-type-menu` (items `.band-type-menu.<n>`), `.rank-by-menu` (items `.<n>`), `.pager`, `.page-*`, `.supporting-pane`, `.bottom-bar`, `fst.band-rankings.row.<teamKey>`.

## Open

- No selected-band pinned row (Android has no selected-band identity) and no band-combo filter.
- Full Rankings likely has the same half-open name squeeze. It could opt into `stackNarrowNames` after its own validation.
