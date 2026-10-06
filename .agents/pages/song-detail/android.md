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
- **Season pill (issue #62, web `QUERY_SHOW_SEASON`/`renderDetailCard`):** `core/songs/ScoreRowSeasonPolicy` (520 dp, = `LeaderboardColumnLayout.SEASON_BREAKPOINT`). The top-five rows measure their own width (`BoxWithConstraints`) and show the `S<n>` pill and the TalkBack "Season N" only from 520 dp. The web gates on the viewport; Android uses the rows' width so a hinge half or split pane stays narrow. The tapped bar's detail row always shows a known season. Phones show none in the list; instrument-card rows already followed the 520 dp rule. Tests: `ScoreRowSeasonPolicyTest`, `SongHistoryCardUiTest` (411 dp and 700 dp).
- **Instrument switch** (issue #61, iOS #31): the selector updates at once while `SongHistorySwap.plan` swaps the drawn chart: fade the graph out (150 ms), swap, fade in (250 ms); instant under app Reduce Motion or animator scale 0; a newer pick cancels the running swap (`LaunchedEffect` restart) and returning to the drawn chart just fades back in. The card (`fst.song-detail.history.card`) keeps its height: its min height is pinned for the swap and eased back to the new natural height afterwards, and while any selectable chart pages (`SongHistoryChart.reservesPager`) a non-paging chart keeps an empty 48 dp pager slot (`fst.song-detail.history.pager-slot`, no semantics).
- **Best scores and View All on a switch** (issue #169, [load-transition](../../patterns/load-transition.md) R7, web `GraphCard` + `useListAnimation`): the list (`fst.song-detail.history.top`, shared `ui/common/GraphCardList`) follows the selection at once, not the graph fade. The old rows fade out and drift up (150 ms ease-in, 40 ms stagger, phase 200 + 40 × (rows − 1) ms). The list then eases to the new height over 300 ms with the rows hidden, and the new rows fade in from 12 dp below (300 ms ease-out, 60 ms stagger). The instrument cards below therefore glide instead of jumping. View All sits outside the list and toggles with the selection, as on the web; it opens the selected chart. Reduced motion swaps at once. Tests: `GraphListPolicyTest`, `SongDetailCoreTest.historySwap*`, `SongHistoryCardUiTest` (switching, rapid, reduced-motion, the `GraphListPhase` sequence and View All journeys), and the connected `SongsAccessibilityJourneyTest.songDetailScoreHistorySwitch…` (card size, selection and ATF on the device).
- **Instrument cards** (6.4/6.5/6.29/6.31/6.38/6.42): instrument header (icon, name, "N total entries") above a card of rows separated by hairlines (`RowSeparator`), columns from the shared section fitter (issue #37: `core/rankings/LeaderboardColumnLayout.fit` via `ui/leaderboards/rememberScoreColumns`, measured from every row plus the appended player row: rank, name, season from a 520 dp row, score, the reserved `AccuracyPill` slot, stars from a 700 dp row, in-card chevron on navigable rows; stars drop before the season when large text would squeeze the name); the selected player's row has the web purple highlight and bold texts, every row shares the same 4 dp inset so columns align; when outside the top ten the player's row follows after a separator (`fst.song-detail.your-rank.<chart>`, opens the page containing it). No "Your score" line. Cards end with the shared purple **View Full Leaderboard** (`ui/design/ViewFullLeaderboardButton`). Two columns when the content is ≥ 600 dp, and either side of a separating vertical hinge (book half-open) via `rememberHingeSplit` + `CardGridRow`.
- An empty chart shows the web `InstrumentEmptyState` text; a failed chart shows an inline retry.
- **Preview row actions** (issue #63, iOS #33): each row with a valid account is one TalkBack stop with the Button role and opens `RankingNavigation.playerRoute` (Statistics for the selected player, otherwise their profile). The click label names the destination (`RankingNavigation.actionLabel`, iOS `SongPreviewSpotlightPolicy.hint`): "Open profile", "Open your statistics", or "Jump to your position" for the appended row eleven, which opens the full board on the page holding its rank and reveals the row (`SongLeaderboardRoute(page, navToPlayer = true)`, [leaderboard-row](../../patterns/leaderboard-row.md) R7, issue #307). Rows without an account aren't clickable and read "Profile unavailable". Verified on FST_Phone against the fixture (tap → profile → Back) and by `SongDetailPreviewRowsUiTest`.
- **Band previews** (web `SongBandLeaderboardPreview`): a section per size (Duos, Trios, Quads) with its ten-row preview from `GET /api/leaderboard/{songId}/bands/{bandType}?top=10&offset=0[&accountId=]` (pure `SELECT`s, including `GetSongBandLeaderboardEntryForAccount` for `accountId`). Rows reuse `BandScoreRow` (shared with the full board; below 400 dp the team score, accuracy pill and stars move to a footer row so member names keep their width; in-card chevron) and open Band Detail. With a selected player the service returns their best band row as `selectedPlayerEntry`: highlighted purple in place (opens Band Detail), or appended after the top ten (`fst.song-detail.band-selected.<type>`), where, like the solo row eleven, it jumps to the full band board on the page holding its rank and reveals it ("Jump to your band's position", `SelectedRowAction.preview`, `SongBandLeaderboardRoute(page, navToBand = true)`; issue #307, before it opened the Band page). Empty → the web `InstrumentEmptyState` with the band text; failure → inline retry (`fst.song-detail.band-retry.<type>`); loading → a spinner TalkBack reads as "Loading <size> scores" (`fst.song-detail.band-loading.<type>`; instrument cards likewise "Loading <instrument> scores"); **View Full Leaderboard** → `SongBandLeaderboardRoute`. *Promoting* the selected band's size above the instrument cards needs a selected-band identity (deferred with the other band-identity features).
- **Band row rules (issue #172):**
  - One rank column per section: `rememberBandRankWidth` measures every drawn rank, including the appended selected band, so an appended "#9,968" doesn't push its members right of the top ten's (`leaderboard-row` R1). The full band board uses the same column for its page.
  - The selected band's row starts its TalkBack description with "Your band, " (`bandScoreAnnouncement(entry, selected = true)`, iOS `SongBandPreviewText`, Windows), because the purple highlight is otherwise visual only.
  - Tests: `SongsParityUiTest.songDetailBandPreviewsSpotlightTheSelectedPlayersBand` (descriptions, Button role, "Open band" in place, "Jump to your band's position" when appended), `songDetailBandPreviewRetryShowsALabelledSpinnerThenRows` (failure → retry → labelled spinner → rows), `SongBandLeaderboardLayoutUiTest.sectionRankColumnFitsAnAppendedFourDigitRankAtAnyTextSize`.
- **Quick Links** (web `usePageQuickLinks`, pushed page only): Intensity, Score History (when shown), each chart, each band size, in the top bar or phone floating toolbar via the shared `QuickLinksAction`; jumps are instant.
- **`?instrument=`** (`SongDetailRoute(songId, instrument)`; profile Best Rank / top-song rows and single-instrument notifications pass it, web `autoScroll`): preselects that chart in Score History and, once the page reveals, scrolls its card to the top unless the user already scrolled; hidden or unknown charts are ignored (`SongDetailLayout.focus`). Debug: `FST_DEBUG_ROUTE=song:<id> FST_DEBUG_INSTRUMENT=<wireId>`.
- With Filter Invalid Scores on, previews read with `leeway=` and show the service's rows and raw Epic ranks exactly like the web (production Winterfest Wish Lead: 7 valid entries of 12,438; verified live 2026-09-28, test `filterInvalidScoresUsesTheLeewayBoardAndDropsInvalidHistory`).
- Full board (`SongLeaderboardScreen`): the song header (64 dp art, title, artist) and instrument switcher scroll with the rows; the top bar takes the title once they're gone (7.8). Rows use the same `ScoreRow`; the selected player's pinned footer is just their row (no page-jump button, 7.9; it jumps to its page or opens Statistics per [leaderboard-row](../../patterns/leaderboard-row.md) R7). Rows and footer are one section (`LeaderboardSectionMember` "rows"/"footer"): fitted to the narrower member, and the rows card has the footer card's 8 dp side inset so the columns line up (`LeaderboardsUiTest.songLeaderboardPinsTheSelectedScoreRowLikeTheWeb` asserts equal score-column bounds).
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

## Validation: band previews (issue #172, live public service, 2026-10)

SFentonX on Everlong (Quads band appended at #9,968, Trios at #9,920, no Duos band), `device.py drive`, one emulator at a time.

| Configuration | Result |
|---|---|
| FST_Phone portrait/landscape, 1.0/2.0 | Three sections with ten rows each, the selected band appended in purple, then View Full. Narrow cards stack the team score under the members; at 2.0 names wrap and nothing clips. |
| FST_Tablet, 1.0/2.0 | **Fixed:** the appended "#9,920" row pushed its members right of the top ten (clearest at 2.0), against `leaderboard-row` R1. The section now shares one rank column (`rememberBandRankWidth`). |
| FST_Resizable phone/foldable/tablet/desktop (1.0), desktop/phone (2.0) | Aligned at every width class. |
| FST_Book_Fold folded/half/unfolded, 2.0 | Half-open pairs Duos \| Trios either side of the hinge with Quads below. At 2.0 the page goes single column (`rememberSingleColumn`), the same as unfolded. |
| FST_Passport_Fold folded/half/unfolded, 2.0 | Same as Book_Fold. |
| FST_TriFold folded/partial/unfolded, 2.0 | Good. On the folded cover at 2.0 (about 360 dp), the shared "#9,968" column leaves the top-ten rows a wide rank gutter, and long names wrap, sometimes mid-word. This is accepted: R1 shares one column, and R3 lets accessibility text wrap. Instrument `StackedScoreRow` keeps the section rank width too. |

- **TalkBack** (`talkback_walk.py`, FST_Phone): rows read in order ("Rank 2, ‹member›, Drums, ‹score›, …, band score …, accuracy, 5 gold stars. Button"), then "Your band, Rank 9968, …. Button" and "View Full Leaderboard. Button". Each row is one stop with the "Open band" action; since #307 the appended band instead offers "Jump to your band's position" and opens its page of the full band board. `SongsAccessibilityJourneyTest` (ATF) passed on FST_Phone and FST_Book_Fold half-open, and `BandsSettingsJourneyTest` passed on FST_Phone.
- **Material 3:** rows are whole-card click targets taller than 48 dp. View Full is the shared purple `ViewFullLeaderboardButton`, the section titles use the shared `SectionHeader`, and the loading state is a labelled `FestivalLoading` spinner.
- **Deliberate deviations:**
  - Android reads each size (`/bands/{type}?top=10`) where iOS and Windows read `/bands/all`. Both are allowlisted pure reads.
  - View Full shows no entry count, and sections have no "N bands" subtitle.
  - Instrument icons inside band rows keep 18 dp at large text.

## Validation (issue #169, Score History instrument switch, live public service, 2026-10)

Each configuration ran SFentonX on Everlong (`device.py drive`, one emulator at a time). The steps: open Quick Links → Score History, dump the tree on Lead (4 best scores; 2 at large text or on narrow windows), switch to Bass (1 score), then dump again. The card (`fst.song-detail.history.card`) had **identical bounds before and after** in every row. Bass was selected and its graph showed.

| Configuration | Selector | Card bounds (px) | Notes |
|---|---|---|---|
| FST_Phone portrait 1.0 | compact | `[42,520][1038,1624]` | Also recorded with animator scale 1 (fade out → swap → fade in; rapid ›››‹ ends on the last pick). |
| FST_Phone portrait 2.0 | compact | `[42,568][1038,1840]` | Prompt wraps, legend fits, and the stacked best-score row doesn't clip. |
| FST_Phone landscape | full (6 chips) | `[184,305][2382,849]` (scrolled, clipped by viewport) | The card is taller than the viewport and its bounds match after the same scroll. |
| FST_Phone light (`dark:off`) | compact | `[42,520][1038,1624]` | Stays dark by design. |
| FST_Tablet landscape / portrait / 2.0 | full | `[592,336][2528,1064]` / `[224,336][1568,1176]` / `[752,372][2528,1276]` | In portrait and at 2.0 the empty pager slot holds the size, because another chart pages at that width. |
| FST_Resizable phone / foldable / tablet / desktop | compact / full / full / full | `[42,452][1038,1556]` / `[294,452][2166,1556]` / `[444,258][1896,804]` / `[296,172][1904,536]` | — |
| FST_Book_Fold folded / half / unfolded / unfolded 2.0 | compact / compact / full / full | `[39,504][1041,1529]` / `[1058,488][2037,1513]` / `[273,488][2037,1513]` / `[273,532][2037,1635]` | When half-open, the card sits on the right of the hinge. |
| FST_Passport_Fold folded / half / unfolded | compact / compact / full | `[42,488][1038,1592]` / `[1125,452][2166,1556]` / `[294,452][2166,1556]` | — |
| FST_TriFold folded / partial / unfolded | compact / full / full | `[32,336][688,1176]` / `[224,336][1408,1176]` / `[224,336][2128,1064]` | — |

- **Found and fixed:** the card held its size, but the best-score list below it snapped instantly to its new height (4 → 1 rows). That made the instrument cards jump up mid-fade. The list now runs the web GraphCard list sequence, including the 300 ms height step (see "Best scores and View All on a switch" above).
- **Reduced motion:** the emulators run at animator scale 0, so the matrix exercises the instant swap. The size still holds and Bass is selected. The Robolectric reduced-motion tests (`reducedMotion…`) cover the app setting.
- **Material 3 alignment** (`material-3` skill, `references/typography-and-shape.md` § Motion, "Easing and Duration (Transitions)"): the graph fade out uses 150 ms FastOutLinearIn (exit, Short 3), and its fade in uses 250 ms LinearOutSlowIn (enter, Medium 1). The card's height release uses 250 ms FastOutSlowIn (standard). The best-score list keeps the web `useListAnimation` timings instead (load-transition R7: web behavior beats the native token choice). Its ease-in exit, ease-out entrance and standard `ease` resize are the same accelerate, decelerate and standard roles. Under reduced motion every swap is instant.
- **Accessibility:** the connected `SongsAccessibilityJourneyTest.songDetailScoreHistorySwitchKeepsTheCardAndSelectsTheNewChart` ran ATF (touch targets, labels, contrast) on FST_Phone and on FST_Book_Fold half-open. Selector arrows and pager buttons are 48 dp and chips are 64 dp. The selected chip reads its instrument name and the empty pager slot has no semantics.
- **Deliberate deviations:** the card is the brand `GlassCard` rather than an M3 `Card`, and the scheme is dark only ([design/android.md](../../design/android.md)).

## Validation (issue #168: load-only fade from #60, live public service, 2026-10)

The #60 rule held everywhere, so nothing changed in the product. Song Detail loads every section behind `SongDetailGate`. Only what is visible when the gate opens fades in; a card scrolled into view later, or scrolled back to, appears at once.

**Method.** SFentonX selected (`FST_DEBUG_PROFILE`), Cake By The Ocean (`song:009f0d51-…`), animator scales set to 1, still backdrop. Each run recorded three drags (five `MOVE`s each) and counted the frames that changed. A fade would add changed frames after each drag's last `MOVE` (400 ms ≈ 12 frames). Every configuration changed only on `MOVE` frames:

| Configuration | Changed frames / `MOVE`s |
|---|---|
| FST_Phone portrait, landscape, font 2.0 + system light | 15/15 each |
| FST_Tablet landscape, two-pane (auto-selected song) | 15/15 |
| FST_Resizable phone / foldable / tablet | 15/15 each |
| FST_Book_Fold folded / unfolded | 15/15 (+3 pre-touch frames from the breathing Item Shop pill) / 14/15 |
| FST_Passport_Fold folded / unfolded | 15/15 each |
| FST_TriFold folded / partial / unfolded | 16/15 (one 0.7% touch-down frame) / 15/15 / 15/15 |

TriFold runs used `am start --display 0` (see [android.md](../../platforms/android.md); the AVD otherwise launches on display 2).

- **Load reveal:** backdrop, then the spinner fades, then content staggers in (recorded on FST_Phone).
- **Reduced motion:** with animator scale 0, content appears without any fade.
- **Other pages (FST_Phone, live):** Leaderboards (the Bass card scrolled in without a fade) and Item Shop rows don't fade. Shop changes of 0.2–0.8% up to 150 ms after a drag are thumbnails decoding. Suggestions' existing cards don't re-fade.
- **Code and Robolectric only:**
  - Global Search fades only when results settle (`rememberRevealed(settled == signature)`). The emulator keyboard swallowed the drags.
  - Player Profile and Player Bands use `/api/player/{id}/bands`, which isn't on the [service-safety](../../platforms/service-safety.md) allowlist. Covered by `FadeInWindowTest` and fixture journeys.
- **Tests:**
  - `SongDetailFadeUiTest`: a band card scrolled into view and the header scrolled back are fully drawn in their first frame.
  - `SuggestionsBatchFadeUiTest`: shown cards stay drawn while a new batch fades in.
  - Both fail when a fade is forced (mutation-checked).
- **Material 3 deviation:** M3 suggests Emphasized Decelerate (400 ms) for elements entering the screen. The fade keeps the web `fadeInUp` instead (400 ms CSS ease-out, 12 dp rise) for cross-platform parity. Reduced motion (app setting or animator scale 0) shows content at once.

## Open

Promoted (selected-band) band previews need a selected-band identity.
