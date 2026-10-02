# Leaderboards overview — Android notes

> **What:** what the Android Leaderboards overview implements, its adaptive layout per form factor and open gaps. **Read when:** changing `ui/leaderboards/LeaderboardsScreen.kt`, `LeaderboardsViewModel` or the shared rankings rows. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Code map

| Layer | Files (`android/app/src/main/java/com/festivalscoretracker/android/`) |
|---|---|
| Core | `core/rankings/Rankings.kt` (metrics, tolerant rows, paging), `RankingFormatting.kt` (web formatting + spotlight placement), `LeaderboardsPolicy.kt` (row routes, column/pane rules), `RankHistory.kt` (history wire model, gap filling, chart geometry) |
| Data | `data/rankings/FestivalApiRankings.kt` (`ServiceEndpoint.Feature` reads incl. `rankHistory`), `LeaderboardPreferences.kt` (`fst.leaderboards.rankBy`) |
| Presentation | `presentation/leaderboards/LeaderboardsViewModel.kt`, `RankingsBoardViewModels.kt` |
| UI | `ui/leaderboards/*` (registered by `leaderboardsGraph(...)` in the shell's `NavHost`), `RankHistoryCard.kt`, shared `ui/design/StarRating.kt` |

## Implemented

- Tab root (`LeaderboardsTab`) and pushed `LeaderboardsRoute` (from Compete/drawer): with a selected player, a **Rank History** card first (below), then one top-ten card (`GET /api/rankings/{instrument}?rankBy=&page=1&pageSize=10`) per Settings-visible instrument, then a **Bands** section title (`headlineSmall`, one step larger than the Duos · Trios · Quads card headers, operator 6.8) with a **Band Rankings** link (`BandRankingsRoute(Band_Duets)`; `/bands` without a band is "Band not found") and Duos · Trios · Quads cards (`GET /api/rankings/bands/{bandType}`). Every read is keyless and pinned ([service safety](../../platforms/service-safety.md)); at most four reads are in flight.
- **Card headers sit above and outside each card** (web `InstrumentHeader` over the card body; operator 2026-09-28): instrument cards show the 40 dp icon + name only (no metric subtitle), Duos · Trios · Quads the name only. The card holds the rows, the spotlight row and, below them (the eleventh row when the selected player is outside the top ten), the shared purple `ViewFullLeaderboardButton` (operator 6.29) as **View All Rankings (N)** / **View All Band Rankings (N)** (web `viewAllRankingsWithCount`, Title Case per 7.16). Rows grouped in one card have hairline `RowSeparator`s (6.5) and an in-card chevron on navigable rows (7.3); every row of a card, including the selected player's pinned row, shares measured rank/songs/rating columns (`LocalRankingColumns`, 7.9; sized by the shared `LeaderboardColumnLayout.fit`, issue #37: rank ≥ 44 dp, the songs label never drops) and the selected row is bold like the web `RankingEntry` `isPlayer` (6.42).
- **Load gate** (operator 6.41): one centred spinner until the first instrument card has data, then the list fades in; the list stays composed (invisible) underneath so its cards load meanwhile.
- **Rows fade in as they load** (web staggered `fadeInUp`): `Modifier.festivalFadeIn` + `rememberRevealed` from `ui/common/FadeInOnLoad.kt`, 400 ms with a 125 ms stagger per row; cached cards (Back from a pushed page, scrolled back into view) appear at once, and Remove animations / Reduce Motion shows rows immediately. The paginated boards fade each newly loaded page the same way.
- **Quick Links** (web `quickLinkItems`, title "Leaderboards Quick Links"): Rank History Graph (with a selected player), each visible instrument, then Duos · Trios · Quads. Entry is a screen action: floating toolbar → bottom sheet on compact windows, top app bar → anchored menu on medium and wider (no side pane, [quick-links](../../controls/quick-links/android.md)); rows of the card grid are the jump targets.
- **Rank History** (web `RankHistoryChart`): heading + "Your ranking progression over the past 30 days." outside the card; inside, a chart picker (48 dp instrument chips, `Role.Tab`), then the profile chart's interaction (web `GraphCard`): the bars that fit the width, swipe or « ‹ › » to move through the 30 days, tap a bar for its detail; metric value bars coloured by rank (web `rankColor`) under the rank line (#4C7DFF, #1 on top, padded 10 % axis), value and rank axes (the web's Recharts ticks via `ChartScale`, see [player-profile/android.md](../player-profile/android.md): a constant rank sits mid-plot, values from 0 with nice ticks), a legend and the five newest days (newest highlighted); the frosted boards pager (7.4). `RankHistoryChart` maps the metric's rank and value into the profile lane's `RankHistoryWindow` / `RankHistoryPlot` (fractional metrics scaled ×10⁶), so both charts share one tested window/plot model. `GET /api/rankings/{instrument}/{accountId}/history?days=30` is read for one chart at a time on demand (the web prefetches all) and reused across metric changes; sparse days carry forward through today (web `fillRankHistoryGaps`). Loading, failure with Retry, and "No rank history for <chart>" states.
- Rank By: top-bar sort action → Material menu (Total Score first, then Adjusted, Weighted, FC Rate, Max Score, check on the selected item). Persisted in the settings DataStore; band cards narrow Max Score to Total Score (web `coerceBandRankingMetric`). All metrics are offered, as on iPhone/Windows (the web hides four behind its experimental flag).
- Cards reload only when their inputs change: instrument cards on metric or selected-player change, band cards only when the *narrowed* band metric changes. Back from a pushed page keeps them; pull to refresh reloads all, keeping content visible.
- Per card: static skeleton (no shimmer); spinners are the shared white `FestivalLoading` without a caption, empty text, `ServiceStatusInline` failure with Retry (scrape freezes count down and retry automatically), rows, **View All** → `FullRankingsRoute(instrument, rankBy)` / `BandRankingsRoute(bandType)`.
- Selected-player spotlight (`RankingSpotlight.placement`): highlighted in place (purple 18 % fill + 1 dp border) when in the top ten, with no extra read; otherwise their own row from `GET /api/rankings/{instrument}/{accountId}` below the rows, a spinner while loading, "Not yet ranked on <instrument>." (404) or an inline retry. The own row carries every metric's rank, so a metric change reuses it. Band rows containing the selected player are highlighted (web `BandRankingCard`); no selected-band spotlight (Android has no selected-band identity).
- Text is `textPrimary` (white) by default; only true de-emphasis (Bayesian value, "Not yet ranked") uses the secondary token.
- Rows are one line (android-gaps #14, web `RankingEntry`): `#rank`, name ("Unknown User" when blank), "X / Y" (full combos under FC Rate) and the rating in accent blue #4C7DFF ("Top N%" + a small Bayesian value for percentile metrics). The selected player's row opens Statistics, others their profile; anonymous/malformed rows are shown but not interactive. Band rows open `BandRoute(bandId, bandType, teamKey)` — never `/api/bands/{id}`.
- The list composes only after settings arrive: composing band cards first made `LazyColumn` anchor on them once instrument rows were inserted above (opened scrolled to Bands).

## Layout

| Form factor | Result |
|---|---|
| Phone / book folded / passport folded / tri-fold folded | One column |
| Medium and expanded (book/passport unfolded, tri-fold partial/unfolded, tablet) | Grid rows of equal columns ≥ 340 dp, up to four (`LeaderboardsLayoutPolicy.columns`); rows top-aligned so a spotlight or failure never clips a neighbour |
| Separating vertical hinge (book half-open) | Exactly two columns, one per side of the fold, with the hinge width plus 16 dp clear (`rememberHingeSplit` from `WindowPosture.hingeList`); Rank History takes the leading panel and the first instrument card the trailing one (`OverviewLayout.historyPaired`), so no panel is left empty |

## Evidence

Fixture screenshots (mock service, no production data): `android/reports/screenshots/leaderboards-*.png`. Robolectric: `rankings/LeaderboardsUiTest.kt` (phone journeys + expanded grid), `LeaderboardsComponentsUiTest.kt` (card states, hinge row). Unit: `RankingsCoreTest`, `RankingsDataTest`, `RankingsViewModelTest`, `OverviewLayoutTest` (paired hinge rows and Quick Links targets). Device: `androidTest/.../leaderboards/LeaderboardsDeviceJourneyTest` (FST_Phone and FST_Book_Fold `--posture half`: history paired across the fold, spotlight, View All → Full Rankings, pinned row until its page).

## IDs

`fst.leaderboards` (list), `fst.leaderboards.loading`, `fst.leaderboards.rank-history` (`.picker`, `.picker.<instrument>`, `.loading`, `.empty`), `fst.quick-links.open|sheet|menu|item.<id>` (ids `rank-history`, `instrument:<wire>`, `band:<wire>`), `fst.leaderboards.card.<instrument>`, `.view-all`, `.spotlight`, `.spotlight.loading`, `.spotlight.unranked`, `fst.leaderboards.band-card.<bandType>`, `.view-all`, `fst.leaderboards.bands-link`, `fst.rankings.rank-by-menu`, `fst.rankings.rank-by.<metric>`, `fst.rankings.row.<accountId|anonymous-…>`, `fst.band-rankings.row.<teamKey>`. Screens set `testTagsAsResourceId` so `device.py drive` can use `id=`.

## Open

- No band-combo filter; no selected-band spotlight or promoted band card (no selected-band identity on Android).
- Rank history reads one chart at a time on demand (the web prefetches every chart before showing the page).
- TalkBack order and live announcements not yet audited (a later phase); rows expose one merged description ("Rank 1st, Name. 12,345. 190 / 250 songs." / "Your rank, 40th, …").
