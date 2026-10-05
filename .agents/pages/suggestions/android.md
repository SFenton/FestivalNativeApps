# Suggestions — Android notes

> **What:** Android (Kotlin/Compose) implementation, Apple parity evidence and decisions for the Suggestions section. **Read when:** changing Suggestions on Android or its generator port. Behavior reference: [ios.md](ios.md) (the Apple port is the source of truth until [spec.md](spec.md) is promoted); sibling port: [windows.md](windows.md).

## Implemented (`android/app/src/main/java/com/festivalscoretracker/android/`)

| Piece | File |
|---|---|
| Line-for-line port of Apple `SuggestionGenerator` (Mulberry32 in 32-bit `Int` arithmetic, pipeline list order, emit table + skip streaks, `selectNewFirst`, decade variants, `near_max_*`, all ten `song_rival_*` families, late rival splice) | `core/suggestions/SuggestionGenerator.kt`, `SuggestionRng.kt` |
| Types (Apple raw values as persisted keys), `SuggestionScore` input decoupled from any wire model, items, categories, season fallback | `core/suggestions/SuggestionModels.kt` |
| `RivalDataIndex.build` + `/rivals/all` wire models (precomputed and live-fallback shapes) | `core/suggestions/SuggestionRivalData.kt` |
| Immutable filter (minimal off-sets, web cascade rules, `""` when untouched, corrupt/oversize → defaults) and `SuggestionCategoryFilter` | `core/suggestions/SuggestionFilterSettings.kt` |
| Row metadata by key (web `getRowLayout`: rival, UNFC accuracy, season, percentile tier, stars, instrument chips) and the one TalkBack label per row | `core/suggestions/SuggestionRowPresentation.kt` |
| Reads via the `ServiceEndpoint.Feature` seam: `/api/player/{id}` (pinned, 202 = syncing, compact wire validated like Apple `PlayerProfileResponse.validate`, `acc` ×1000) and `/api/player/{id}/rivals/all` (404 → empty) | `data/suggestions/FestivalApiSuggestions.kt` |
| Filter persistence under `fst.suggestions.filter` in the shared settings DataStore (registered in `SettingsRegistry`, reset with app settings) | `data/suggestions/SuggestionFilterStore.kt` |
| Page model: one generator per (player, catalogue publication, score publication); web batching (10 first, 6 per trigger), endless `resetForEndless` remix, 1,000-category cap + Start a new mix; rivals fetched after the first batch and spliced in (best-effort); filter/chart visibility re-applied without regenerating; generation on `Dispatchers.Default` under a mutex, state published inside the lock | `presentation/suggestions/SuggestionsViewModel.kt` |
| Stateless screen + `SuggestionsActions`; category header above a glass card of rows; `LazyVerticalStaggeredGrid`; live filter `ModalBottomSheet` | `ui/suggestions/SuggestionsScreen.kt`, `SuggestionCardView.kt`, `SuggestionsFilterSheet.kt` |
| Nav registration for `SuggestionsTab` and `SuggestionsRoute` (one call in `FestivalApp`) | `ui/suggestions/SuggestionsDestinations.kt` |

States: no player (Choose Profile opens the profile sheet), loading, syncing (202, Retry), failed (shared `ServiceStatusView`, scrape-freeze countdown), empty (Play some songs first! / filtered → Reset Filters), loaded, loading-more footer, 1,000 cap. Rows push `SongDetailRoute(songId)`.

## Apple parity evidence

- `core/suggestions/SuggestionParityTest` reads the Windows lane's shared fixture **in place** (`windows/Festival.Core.Tests/Fixtures/suggestions-parity{,.expected}.json`, produced from the unmodified Apple sources by `tools/windows/suggestion_parity/run_parity.py`) and matches every page of all six scenarios (228 pages + 27 endless-remix pages), the rival index and raw Mulberry32 draws for four seeds, exactly. Regenerate the fixture there; this test needs no copy.
- Order-sensitive rules the port keeps: `Instrument.entries` = Apple `Instrument.allCases`; stable `sortedBy` wherever Swift's `sorted` sees ties (rival gap/protect/spotlight); ordinal `String` order for keyed groups; every RNG draw at the Apple call site (e.g. `displayCount()` only when an artist has > 5 songs); Swift `.whitespaces` trimming for titles/artist names (`trimSpaces`) vs `.whitespacesAndNewlines` for keys (`trim()`).

## Layout by form factor

| Window | Grid |
|---|---|
| Compact (phone, folded foldables, tri-fold one panel) | One column; row metadata other than icon-only layouts moves under the title line (web `useIsNarrow`) |
| Medium/expanded | `max(1, ⌊(width + 16) / (400 + 16)⌋)` columns (book fold unfolded: 1; tablet/tri-fold unfolded: 2) |
| Separating vertical hinge (book fold half-open) | `HingeSplitCells`: two unequal columns whose gap is the hinge (≥ 16 dp), so no card straddles the fold; computed from `currentWindowAdaptiveInfo().windowPosture.hingeList` and the grid's window position |

Filter sheet (operator 2026-09-28): **applies live** — every switch, cascade and Reset Filters applies and persists at once (`SuggestionsViewModel.applyFilter`), so the grid and the toolbar's "filters on" state update behind the sheet. The shared sheet header is the title plus the standard Close icon button (issue #23; it replaced Done and keeps `fst.suggestions.filter.done`); back, swipe or Close just closes. No Cancel/Apply and no discard prompt.

## Card (web `CategoryCard`, operator 2026-09-28)

- **Header outside the card**: title (16 sp bold, heading), description (12 sp `textTertiary` #9AA6B2) and, for single-chart categories, a 36 dp instrument icon sit above the glass card (`fst.suggestions.header.<id>`), like Leaderboards/Compete; the card holds only the rows (1 dp `borderSubtle` dividers). Cards are 24 dp apart (web `Gap.section`).
- Row: 44 dp artwork, then title (14 sp semibold) and "Artist · Year" (12 sp `textSubtle`), both marquee when they overflow (shared `FestivalMarqueeText`; truncated under Reduce Motion); 10 dp vertical / 16 dp horizontal insets (web 24 px; Material list-item inset keeps metadata beside the text on phones). Narrow cards move metadata to a right-aligned second line.
- Metadata per category (web `RightContent`): instrument chips = 34 dp solid status circles (gold/green/red fill + 2 dp darker stroke, 20 dp icon, 6 dp gap, Settings-visible charts); star-gain rows = web star images at 20 dp (`StarRating`) + 28 dp instrument icon; percentile = `PercentilePill` (subtle white; Top 5% gold outline; Top 1% gold outline italic — Compose has no skew) + 28 dp icon; UNFC = accuracy pill tinted by accuracy; stale = 48 dp `SeasonPill` (16 sp); rival = name badge (blue song rival / yellow leaderboard rival, 11 sp, ≤ 100 dp; mixed-rival cards only, see Decisions) + bold tabular rank delta (green ahead / red behind) + 28 dp icon; unplayed/variety/artist = none.
- Entry motion: each generated batch fades in (web `getCardDelay`: 125 ms stagger from the batch's first card); cards already revealed or scrolled back into view show at once; Reduce Motion shows them immediately.

## Decisions

- Suggestions keeps its own score read rather than the profile lane's `presentation/profile/SelectedProfileStore` (landed mid-lane): the second `GET /api/player/{id}` within one publication is a 304 through `FestivalApi`'s per-URL ETag cache. TODO(orchestrator): consolidate onto `SelectedProfileStore` once its API exposes an awaitable score index, so Retry on Suggestions also refreshes Songs/Statistics.
- The mix persists per back-stack entry (tab switches restore it); a player switch/deselect, a new catalogue or score publication, or Start a new mix rebuilds it; `mixId` is monotonic so the grid returns to the top.
- A filter that disables every type skips generation (nothing could show).
- **Rival name badge, native deviation (2026-10-02, issue #59 check of #29):** single-rival cards (`song_rival_spotlight_`/`gap_`/`protect_`/`slipping_`/`dominate_`) name the rival in their title, so rows drop the web's per-row name badge and show only the signed delta + icon (`SuggestionRowPresentation.showsRivalName`, as Apple). Mixed-rival cards (`song_rival_battleground` and the cross-pollination families) keep the badge. TalkBack still names the rival on badge-less rows: the row label ends "2 ranks behind Rival B1" (`rivalDeltaAccessibilityLabel`); mixed rows keep "rival X, ahead by 1 rank" (singular "rank" fixed at the same time). Verified on `FST_Phone` (fixture mode, seed 1) via the UI tree's `content-desc`.
- Filter stays reachable while the cards scroll (issue #52): `FestivalScreen(pinActions = true)` pins the compact floating toolbar instead of hiding it on scroll; global search is already in the pinned top app bar.
- Filter reads before the feed (issue #112): the shell reads the floating toolbar after page content (traversal index 1), but this feed loads cards as TalkBack scrolls, so linear navigation never reached Filter. `FestivalScreen(actionsReadFirst = true)` makes the top app bar a traversal group at −2 and the toolbar −1: top bar → Filter → cards. Songs reads its toolbar first too (issue #160); other pages keep the default.
- Button copy follows the web strings (`FortniteFestivalWeb/src/i18n/en.json` `suggestions.*`) in the repo's Title Case for buttons ([design](../../design/README.md)): `Start a New Mix` (web "Start a new mix"), `Reset Filters`.

## Debug and fixtures

`FST_DEBUG_SUGGESTIONS_SEED=<0–4294967295>` pins the mix seed. Fixture mode: `python tools/windows/suggestions_fixture_server.py --port 8776` (synthetic parity catalogue, compact scores, rivals, generated art) and launch with `FST_ORIGIN=http://10.0.2.2:8776`, `FST_DEBUG_PROFILE=fixture-suggest:Fixture Player`, `FST_DEBUG_TAB=suggestions`. Screen and sheet set `testTagsAsResourceId`, so `device.py drive` can use `id=fst.suggestions.*`.

## Tests

| Suite | Covers |
|---|---|
| `core/suggestions/SuggestionParityTest`, `SuggestionCoreTest` | Apple parity; helpers, filter cascade/persistence, rival index edge cases, row layouts, skip streak, spotlight |
| `suggestions/SuggestionDataTest` | Wire validation (identity, counts, duplicates, bounds, 202 envelope), instrument bit codes, keyless requests, rivals 404/500, filter store |
| `suggestions/SuggestionsViewModelTest` | Batching, rival splice, remix to the cap + new mix, filter/visibility refilter, syncing/failure retry, player switch, new publication |
| `suggestions/SuggestionsUiTest`, `SuggestionsRenderTest` (Robolectric) | Whole-shell journeys (load, scroll, open Song Detail, live filter/Done/reset, all types off, no player, syncing → failure → loaded), traversal order (top bar → Filter → cards; Song Detail unchanged) and hosted renders of every phase/row layout, phone and expanded |
| `journeys/SuggestionsAccessibilityJourneyTest` (connected, `device.py test`) | ATF on the feed and filter sheet, reading order in logcat `FST_A11Y`, no card across a separating hinge |

Fixtures: `testing/SuggestionFixtures` (shared with `androidTest`).

| Last measured | Logic lines | UI lines |
|---|---|---|
| Suggestions packages (JaCoCo, JVM + Robolectric) | 99.0% | 96.8% |

## Device evidence

| AVD / posture | Result (fixture mode, seed 1) |
|---|---|
| `FST_Phone` | One column, narrow rows, filter sheet, filter apply (`android/reports/screenshots/suggestions-{phone,phone-scrolled,filter-phone}.png`) |
| `FST_Book_Fold` unfolded / half / folded | One wide column / hinge split (WindowManager reported `fold-[1038,0,1038,2152]`, HALF_OPENED): two columns with the gap on the fold / phone layout (`suggestions-book-{unfolded,half,folded}.png`) |
| Every AVD and posture (live service) | See Validation (issue #112) |

## Validation (issue #112, 2026-10-04)

Live public service, SFentonX selected, dark scheme. Material 3 skill guidance checked: cards "Compact: full-width single column; Medium: multi-column; Expanded: max 4 cols", "Never place interactive content across the hinge", "Minimum touch target 48x48dp", accessibility "TalkBack/semantics (Compose), focus order".

| Configuration | Found | Result |
|---|---|---|
| FST_Phone portrait/landscape, fs 1.0/2.0 | TalkBack swiped from the top bar straight into the endless cards; the pinned Filter (read after content) was never reached | Fixed: top bar → Filter → cards (Decisions). Layout passes: one column, rows wrap at 2.0, sheet scrolls; landscape 2.0 leaves little list room (pinned toolbar, as Songs) |
| FST_Tablet landscape/portrait, fs 1.0/2.0 | — | Pass: two columns with the permanent drawer; rail at 2.0; filter sheet width-capped |
| FST_Resizable phone/foldable/tablet/desktop, fs 1.0/2.0 | — | Pass: 1 / 1 wide (rail) / 2 / 3 columns |
| FST_Book_Fold unfolded/half/folded, portrait/landscape, fs 1.0/2.0 | — | Pass: one wide column / two columns split at the hinge, nothing across it / phone layout; folded landscape 2 columns |
| FST_Passport_Fold folded/unfolded, portrait/landscape, fs 1.0/2.0 | — | Pass: phone layout folded; one wide column with the rail unfolded (icon-only at 2.0) |
| FST_TriFold folded/partial/unfolded, fs 1.0/2.0 | Folded at 2.0 the shared one-line top-bar title truncates ("Sugges…") | Pass (shared top-bar behaviour, as other pages); 1 / 1 / 2 columns |
| Light theme | App stays dark | Documented dark-only deviation ([design](../../design/android.md)) |
| Reduced motion (animator scale 0) | — | Cards show at once (no batch fade); marquees truncate |
| TalkBack (FST_Phone, real) | Search, Notifications (N unread), Profile: <name>, Filter Suggestions, then card heading, description and one Button stop per row ("title, artist · year, metadata") | Coherent order after the fix |
| Connected ATF journey | `SuggestionsAccessibilityJourneyTest` on FST_Phone and FST_Book_Fold half-open | 0 errors; no card straddles the hinge |

Deliberate deviations kept: dark scheme only; width-capped `ModalBottomSheet` instead of an M3 side sheet on expanded windows (as Songs #101); 16 dp margins app-wide (M3 suggests 24 dp at medium+); pinned (always-visible) floating toolbar on compact windows (issue #52).

## Validation (issue #160, 2026-10-05: pinned Filter and global search from #52)

Live public service, SFentonX selected, dark scheme, animator scale 0. Each configuration: three swipes down the feed, UI tree and screenshot, open Filter while scrolled, swipe back up and compare bounds.

| Configuration | Found | Result |
|---|---|---|
| FST_Phone portrait/landscape, fs 1.0/2.0 | — | Pass: Filter (floating toolbar in portrait, top bar in landscape) and global search (top bar) keep identical bounds while scrolled; the filter sheet opens; the first card returns at the top |
| FST_Tablet, FST_Resizable (all four), FST_Book_Fold, FST_Passport_Fold, FST_TriFold (every posture) | — | Pass: Filter and global search fixed in the top app bar |
| Reduced motion | — | Nothing animates: both controls never move |
| TalkBack | — | Top bar → Filter → cards (issue #112) |
| Connected scroll journey | — | `journeys/PinnedPageControlsDeviceTest`: scrolls the feed three times, Filter and global search keep their bounds and open while scrolled, restore at the top, ATF plus traversal top bar (−2) → toolbar (−1) → list (0) on compact. Pass on FST_Phone (floating toolbar), FST_Book_Fold half-open and FST_Tablet (top bar) |

Tests: `ui/PinnedPageControlsUiTest` (phone, medium, expanded Suggestions cases) and the connected `journeys/PinnedPageControlsDeviceTest`.

## Open

- No first-run slides, scroll restoration across launches or list-detail Song Detail pane (rows push).

## IDs

`fst.suggestions.{filter-button,list,loading,loading-more,syncing,error,no-results,choose-profile,reset-filters,mix-limit,start-new-mix}`, `fst.suggestions.category.<key>[.<mix>]`, `fst.suggestions.row.<songId|songId|Solo_X>`, `fst.suggestions.filter.{form,title,instruments,general,instrument-specific,instrument-picker[.<Solo_X>],instrument.<Solo_X>,type.<type>,type.<Solo_X>.<type>,reset,cancel,apply,discard,keep-editing}`.
