# Song Detail — Android notes

> **What:** Android implementation state and decisions for Song Detail and the full song leaderboard. **Read when:** changing Song Detail on Android (`ui/songdetail/`). Behavior: [spec.md](spec.md).

## Implemented

- `SongDetailRouteScreen` wires the view model with shared Shop, selected-profile and Settings state; the shell calls it for both the pushed route and the two-pane detail.
- Song resolved by ID (debug: or exact title) against the current catalogue; the shared backdrop shows the song's static cover.
- **Load gate** (batch 6.41): `SongDetailViewModel.startPreviews` / `startBandPreviews` start every visible chart's and band size's ten-row preview together, plus the selected player's song history; `FestivalLoadGate` (`ui/common/LoadGate.kt`) shows only the spinner until all settle (loaded or failed, `core/songs/SongDetailLayout.ready`), fades it, then staggers header → Intensity → Score History → card rows → band rows.
- **Item order** (`SongDetailLayout.items`, web `SongDetailPage`): header, actions, Intensity, Score History, instrument rows, band previews last. Each item carries its Quick Links section IDs (web `registerSectionRef` IDs: `intensity`, `score-history`, `instrument-<wireId>`, `band-<wireId>`).
- **Hinge** (book half-open, any separating vertical fold): nothing straddles it. Intensity and Score History share one `HingeSummary` row either side of the fold (`CardGridRow`); without history the Intensity grid itself is split (`splitIntensity`, leading half rounded up, trailing half's header space kept blank and hidden from TalkBack); band previews pair up (Duos | Trios, Quads). Device evidence: `android/reports/screenshots/song-detail-hinge-book-half.png`, `song-detail-bands-book-half.png`. Cached data returning shows at once.
- **Header** (6.40): 88 dp album art, title and `artist · year · length` in the list; it scrolls away and the top bar shows the title only once it has (`firstVisibleItemIndex > 0`), like iOS.
- Header actions: **Paths** (only when a visible, charted, non-Karaoke chart exists) and, for a same-publication Shop offer, the **Item Shop** official-link pill (validated host only), which breathes in the status colour (web `shopBreathe*`, static under reduced motion). A failed Shop read shows `fst.song-detail.shop-error`.
- **Intensity** (6.31): every charted instrument, two columns everywhere; compact cards show icon + meter (left-aligned, web cell), cards ≥ 480 dp add the label.
- **Score History** (6.39, `SongHistoryCard.kt`, web `ScoreHistoryChart` in a `GraphCard`): `GET /api/player/{id}/history?songId=` (no instrument; `data/songs/FestivalApiSongHistory.kt`), invalid scores dropped while Filter Invalid Scores is on (`SongHistoryChart.valid`). Instrument Selector (required) over visible charts with history (auto: current → Lead → first); one canvas draws accuracy bars (red→green, gold for a 100% FC, ≤ 72 dp wide) and the blue score line; tapping a bar selects it (purple stroke) and shows its detail row; « ‹ › » paging (`SongHistoryPaging`, web `useChartPagination`); the five best scores (best purple and bold); **View All Scores** → `PlayerHistoryRoute` when there are more than five. Hidden when the player has no history on visible charts.
- **Season pill (issue #62, web `QUERY_SHOW_SEASON`/`renderDetailCard`):** `core/songs/ScoreRowSeasonPolicy` (520 dp, = `LeaderboardColumnLayout.SEASON_BREAKPOINT`). The top-five rows measure their own width (`BoxWithConstraints`) and show the `S<n>` pill and the TalkBack "Season N" only from 520 dp. The web gates on the viewport; Android uses the rows' width so a hinge half or split pane stays narrow. The tapped bar's detail row always shows a known season. Phones show none in the list; instrument-card rows already followed the 520 dp rule. Tests: `ScoreRowSeasonPolicyTest`, `SongHistoryCardUiTest` (411 dp and 700 dp, the 519/520 dp boundary, font 2.0), `SongDetailScoreRowSeasonUiTest` (instrument-card rows; issue #170).
- **Instrument switch** (issue #61, iOS #31): the selector updates at once while `SongHistorySwap.plan` swaps the drawn chart: fade the graph, top rows and View All out (150 ms), swap, fade in (250 ms); instant under app Reduce Motion or animator scale 0; a newer pick cancels the running swap (`LaunchedEffect` restart) and returning to the drawn chart just fades back in. The card (`fst.song-detail.history.card`) keeps its height: its min height is pinned for the swap and eased back to the new natural height afterwards, and while any selectable chart pages (`SongHistoryChart.reservesPager`) a non-paging chart keeps an empty 48 dp pager slot (`fst.song-detail.history.pager-slot`, no semantics). Tests: `SongDetailCoreTest.historySwap*`, `SongHistoryCardUiTest` switching/rapid/reduced-motion journeys (the emulator was unavailable on the low-disk host, so evidence is Robolectric).
- **Instrument cards** (6.4/6.5/6.29/6.31/6.38/6.42): instrument header (icon, name, "N total entries") above a card of rows separated by hairlines (`RowSeparator`), columns from the shared section fitter (issue #37: `core/rankings/LeaderboardColumnLayout.fit` via `ui/leaderboards/rememberScoreColumns`, measured from every row plus the appended player row: rank, name, season from a 520 dp row, score, the reserved `AccuracyPill` slot, stars from a 700 dp row, in-card chevron on navigable rows; stars drop before the season when large text would squeeze the name); the selected player's row has the web purple highlight and bold texts, every row shares the same 4 dp inset so columns align; when outside the top ten the player's row follows after a separator (`fst.song-detail.your-rank.<chart>`, opens the page containing it). No "Your score" line. Cards end with the shared purple **View Full Leaderboard** (`ui/design/ViewFullLeaderboardButton`). Two columns when the content is ≥ 600 dp, and either side of a separating vertical hinge (book half-open) via `rememberHingeSplit` + `CardGridRow`.
- An empty chart shows the web `InstrumentEmptyState` text; a failed chart shows an inline retry.
- **Preview row actions** (issue #63, iOS #33): each row with a valid account is one TalkBack stop with the Button role and opens `RankingNavigation.playerRoute` (Statistics for the selected player, otherwise their profile). The click label names the destination (`RankingNavigation.actionLabel`, iOS `SongPreviewSpotlightPolicy.hint`): "Open profile", "Open your statistics", or "Open your page of the full leaderboard" for the appended row eleven. Rows without an account aren't clickable and read "Profile unavailable". Verified on FST_Phone against the fixture (tap → profile → Back) and by `SongDetailPreviewRowsUiTest`.
- **Band previews** (web `SongBandLeaderboardPreview`): a section per size (Duos, Trios, Quads) with its ten-row preview from `GET /api/leaderboard/{songId}/bands/{bandType}?top=10&offset=0[&accountId=]` (pure `SELECT`s, including `GetSongBandLeaderboardEntryForAccount` for `accountId`). Rows reuse `BandScoreRow` (shared with the full board; below 400 dp the team score, accuracy pill and stars move to a footer row so member names keep their width; in-card chevron) and open Band Detail. With a selected player the service returns their best band row as `selectedPlayerEntry`: highlighted purple in place, or appended after the top ten (`fst.song-detail.band-selected.<type>`). Empty → the web `InstrumentEmptyState` with the band text; failure → inline retry; **View Full Leaderboard** → `SongBandLeaderboardRoute`. *Promoting* the selected band's size above the instrument cards needs a selected-band identity (deferred with the other band-identity features).
- **Quick Links** (web `usePageQuickLinks`, pushed page only): Intensity, Score History (when shown), each chart, each band size, in the top bar or phone floating toolbar via the shared `QuickLinksAction`; jumps are instant.
- **`?instrument=`** (`SongDetailRoute(songId, instrument)`; profile Best Rank / top-song rows and single-instrument notifications pass it, web `autoScroll`): preselects that chart in Score History and, once the page reveals, scrolls its card to the top unless the user already scrolled; hidden or unknown charts are ignored (`SongDetailLayout.focus`). Debug: `FST_DEBUG_ROUTE=song:<id> FST_DEBUG_INSTRUMENT=<wireId>`.
- With Filter Invalid Scores on, previews read with `leeway=` and show the service's rows and raw Epic ranks exactly like the web (production Winterfest Wish Lead: 7 valid entries of 12,438; verified live 2026-09-28, test `filterInvalidScoresUsesTheLeewayBoardAndDropsInvalidHistory`).
- Full board (`SongLeaderboardScreen`): the song header (64 dp art, title, artist) and instrument switcher scroll with the rows; the top bar takes the title once they're gone (7.8). Rows use the same `ScoreRow`; the selected player's pinned footer is just their row (opens Statistics, no page-jump button, 7.9). Rows and footer are one section (`LeaderboardSectionMember` "rows"/"footer"): fitted to the narrower member, and the rows card has the footer card's 8 dp side inset so the columns line up (`LeaderboardsUiTest.songLeaderboardPinsTheSelectedScoreRowLikeTheWeb` asserts equal score-column bounds).
- Paths sheet: see [chopt-paths/android.md](../../controls/chopt-paths/android.md).
- **Large-text history rows (issue #102):** at font scale ≥ 1.3 (`isLargeText`), each top-five Score History row stacks the date above a `FlowRow` of season pill, score and accuracy. Before this, the one-line row clipped the date ("Jul 24,") and wrapped the pill to "100 / %". `AccuracyText` keeps a 64 dp minimum width and one line. Tests: `SongHistoryCardUiTest.largeTextStacks…`, `defaultTextKeepsTheTopRowsOnOneLine`.

## Validation (issue #102, live public service, 2026-10)

Ran with SFentonX selected (`FST_DEBUG_PROFILE`) on Everlong, using `device.py drive` with one emulator at a time.

| Configuration | Result |
|---|---|
| FST_Phone portrait/landscape, font 1.0/2.0 | Compact layout: bottom bar plus floating toolbar, actions move to the top bar in landscape. Fixed: hidden toolbar ghosting through the 0.96-alpha bottom bar after scrolling (#1), and clipped history rows at 2.0 (#2). |
| FST_Tablet landscape/portrait, 1.0/2.0 | Permanent drawer in landscape (rail in portrait at 2.0) and two-column Intensity. Fixed: #2, plus the 280 dp drawer breaking words at 2.0 ("Leaderboard / s", #3 → `AdaptiveLayoutPolicy.permanentDrawerWidth`, 360 dp at ≥ 1.3×). |
| FST_Resizable phone/foldable/tablet/desktop | Bottom bar → rail → drawer by width class. Desktop at 2.0 shows the #3 fix. |
| FST_Book_Fold folded/half/unfolded (+landscape, 2.0) | Folded is like the phone; half-open splits Intensity and Score History across the hinge; unfolded uses the rail in one column. |
| FST_Passport_Fold folded (portrait/landscape)/half/unfolded (2.0) | Good. |
| FST_TriFold folded/partial/unfolded (2.0) | Good. |

- **Light theme:** the app stays dark on purpose ([design/android.md](../../design/android.md), "Dark scheme only for now").
- **Reduced motion:** with animator scale 0, content appears without animation (as on cold emulator boots), and the Robolectric reduced-motion swap test covers it.
- **TalkBack** (`talkback_walk.py`, FST_Phone): actions → header → Intensity ("Lead, Difficulty 4 of 7") → Score History selector/chart/pager/rows → each instrument heading, rows, the player's appended row, View Full Leaderboard. `SongsAccessibilityJourneyTest` (ATF: touch targets, contrast, labels) passed on FST_Phone and FST_Book_Fold half-open.
- **Deliberate deviations:**
  - Intensity labels hide below a 480 dp card (web icon grid), but TalkBack still reads them.
  - The bottom bar is icon-only at large text.
  - The top-bar notification badge slightly overlaps the avatar at 2.0 (shell chrome; noted here, not changed).

## Validation (issue #170, season pill, live public service, 2026-10)

The #62 rule (season only on rows at least 520 dp wide; the tapped-bar detail row always shows it) was re-checked on SFentonX / Everlong with a UI-tree probe that measured each row's width in dp and recorded whether it showed `S<n>` plus the TalkBack "Season N". No configuration broke the rule, so the code was not changed.

Row widths are in dp; "shown" or "hidden" refers to the season.

| Configuration | Score History rows | Tapped-bar detail | Instrument-card rows |
|---|---|---|---|
| FST_Phone portrait, font 1.0 / 2.0 / light setting | 379, hidden | 355, shown ("Season 13") | 371, hidden |
| FST_Phone landscape, 1.0 / 2.0 | 837, shown | not tapped (logic as portrait) | 1.0: two columns, 402–411, hidden. 2.0: one column, 573–829, shown |
| FST_Tablet landscape 1.0 / 2.0 | 968 / 888, shown | 944, shown | 1.0: two columns, 468, hidden. 2.0: one column, 880, shown |
| FST_Tablet portrait 1.0 | 672, shown | shown | 320, hidden |
| FST_Resizable phone / foldable / tablet | 379 hidden / 713 shown / 968 shown | 355 / 689 / 944, shown | 371 / 340 / 468, hidden |
| FST_Resizable desktop 1.0 / 2.0 | 1608 / 1528, shown | 1584, shown | 788 / 748, shown |
| FST_Book_Fold folded / half-open / unfolded | 411 hidden / 402 hidden (hinge side) / 724 shown | 387 / 378 / 700, shown | 403 / 298–402 / 354, hidden |
| FST_Book_Fold half-open 2.0 | 724, shown (no hinge split at large text) | not tapped | 715–724, shown |
| FST_Passport_Fold folded / half-open / unfolded | 379 hidden / 397 hidden / 713 shown | 355 / 372, shown | 371 / 292–397 / 349, hidden |
| FST_TriFold folded 1.0 / 2.0 | 328, hidden | not tapped | 320–328, hidden |
| FST_TriFold partial | 592, shown | not tapped | 584–592 shown; 328 (stacked) hidden |
| FST_TriFold unfolded 1.0 / 2.0 | 952, shown | not tapped | 1.0: 460 (two columns), hidden. 2.0: 688–952, shown |

The detail row was tapped on the phone and on each fold and Resizable posture; it showed the season at every width (355–1584 dp). In the other runs, the chart sat under the floating toolbar, so the run was not tapped. The detail row has no width condition; Robolectric covers it at 519 dp and at 411 dp with font 2.0. The TriFold AVD launches on its secondary display, so runs there use `am start --display 0`; there is no crash.

- **Why the row width, not the window class:** Material 3 recommends window size classes over hand-rolled `BoxWithConstraints` checks. The season rule is a deliberate exception (`leaderboard-row` R1, web `SEASON_BREAKPOINT`): the hinge half on a half-open Book Fold and the two-column cards on Medium/Expanded windows must stay narrow even when the window is wide.
- **Large text (deliberate deviation):** at a font scale of 1.3 or more, the history rows and the cards both stack (`FlowRow` / `StackedScoreRow`), and both keep the 520 dp rule. The section fitter (`LeaderboardColumnLayout.fit`, issue #37) can still drop the card season on a card just over 520 dp when the stacked columns don't fit. This still meets "only when ≥ 520 dp", and it is the shared fitter's rule for every leaderboard, so this check left it as it was.
- **Light theme:** the app stays dark (dark scheme only).
- **Reduced motion:** animator scale 0 is the `device.py` default for all runs.
- **Accessibility:** the season is read only when it is shown. `SongsAccessibilityJourneyTest#songDetailBoardAndPaths` (ATF touch targets, contrast and labels, plus reading order) passed on FST_Phone.
- **Tests:**
  - `SongHistoryCardUiTest.theRowsOwnWidthDecidesTheSeasonAtTheBreakpoint` covers 519 vs 520 dp in a 900 dp window.
  - `SongHistoryCardUiTest.largeTextKeepsTheWidthRuleInTheStackedRows` covers font 2.0 at 411 and 600 dp.
  - `SongDetailScoreRowSeasonUiTest` covers instrument-card rows at 411, 519 and 520 dp, then back to 519, and at font 2.0 at 411 and 900 dp.

## Open

Promoted (selected-band) band previews need a selected-band identity.
