# First-run experiences — iPhone notes

> **What:** the SwiftUI carousel, seen-state store and Settings replay as built, decisions and
> open gaps (Lane F). Spec: [spec.md](spec.md).

## Architecture

- **Core (pure logic, `FestivalCore/`):**
  - `FirstRun.swift` — `FirstRunGateContext`, `FirstRunGate` (enum predicate, not a closure, so
    slide definitions stay `Equatable`/`Sendable` and unit-testable), `FirstRunSlide` (data only —
    no `render`; the UI layer maps `id` to a view), `FirstRunHashing` (djb2, ported bit-for-bit
    from the web's `contentHash`), `FirstRunSeenRecord`, and `FirstRunSlideEvaluator` (the pure
    `isUnseen`/`unseenSlides`/`gatePassingSlides`/`allSlides` functions).
  - `FirstRunSeenStore.swift` — bounded (`maxRecords = 500`, oldest-`seenAt`-first eviction),
    validated `UserDefaults` JSON persistence (`fst.firstRun.seen.v1`). A fully-corrupt or
    oversized (>256 KB) blob resets to empty, matching the web's `catch { return {} }`;
    individually malformed records (negative version, empty/oversized hash or id) are dropped
    while the rest of the store is kept — stricter than the web, never weaker.
  - `FirstRunCatalog.swift` — the full, hand-ported slide catalog for all 9 registered pages
    (`FirstRunPageKey`: `songs`, `songinfo`, `playerhistory`, `statistics`, `suggestions`,
    `leaderboards`, `compete`, `rivals`, `shop` — the same `pageKey` strings the web registers
    from `SettingsPage.tsx`). Only the mobile copy variant is ported for slides that differ by
    `isMobile` on the web (this lane targets iPhone only); each keeps the web's `contentKey` so a
    future desktop port would share seen-state.
  - `FestivalCoreTests/FirstRunTests.swift` — 36 tests covering hashing, `isUnseen` (missing
    record, version bump, content-hash change, `contentKey` sharing, a defensive lower-stored-
    version case), slide selection (gates, `ready`, the "only the new slide shows" scenario,
    `alwaysShow`, `gatePassingSlides`, `allSlides`), and the seen store (round-trip, corrupt data,
    oversized payload, per-record validation, bounding/eviction, `resetPage`/`resetAll`).
- **UI (`FestivalUI/Features/FirstRun/`):**
  - `FirstRunCenter` (`@Observable`, `@MainActor`) — one per session, reached via
    `session.firstRunCenter` (added the same weakly-keyed-registry way as
    `FestivalSession+Artwork.swift`'s `backgroundCoordinator`, so no edit to
    `FestivalSession.swift` itself was needed). Owns the `FirstRunSeenStore` and arbitrates the
    single `activeKey` ("one carousel at a time") via `claim`/`release`. Also resolves
    `FirstRunDebugMode` from `FST_DEBUG_FIRST_RUN` once at session start.
  - `.firstRun(page:session:)` (`FirstRunModifier.swift`) — the one seam every page needs.
    Evaluates gates from live `@AppStorage` settings + `session.selectedPlayer` on appear and on
    every relevant setting/profile change, presents a `.sheet` when unseen gate-passing slides
    exist and the shared slot can be claimed, and marks them seen (releasing the slot) in the
    sheet's `onDismiss` — so a swipe-to-dismiss is handled identically to tapping Skip/Done.
  - `FirstRunCarouselView.swift` — the paged carousel: `TabView(.page)` (iOS-only; macOS falls
    back to the default style purely so `swift test` keeps compiling on the host Mac — this
    carousel never actually presents on macOS since Apple's build order ports iPhone first),
    close (✕) button, Skip/Next/Done controls, and a combined VoiceOver announcement per slide
    (`accessibilityValue = "Slide x of y"`) with `@AccessibilityFocusState` moving focus to the
    new slide's content on every index change (button-driven or swipe). `withAnimation` calls for
    the Next/Done transition are skipped under `accessibilityReduceMotion` — there is no
    web-style per-line stagger animation to gate in the first place.
  - `FirstRunDemoContent.swift` / `Demo/FirstRunSongsDemos.swift` — see the parity table below.
  - `FirstRunSettingsSection.swift` — the Settings "First Run Guides" section (web title): one
    "Show" row per `FirstRunPageKey` in the web's order (`settingsOrder`; Player History labelled
    "Score History" like the web's `history.title`), opening a carousel over `FirstRunSlideEvaluator.allSlides(...)` (gates and
    seen-state both ignored, matching `getAllSlides`), resetting that page's seen-state first
    (matching `useFirstRunReplay.open`'s `resetPage` call) and re-marking everything seen on
    dismiss. No "reset all" control — the web doesn't have one either.
- **Debug:** `FST_DEBUG_FIRST_RUN` — unset/anything else → `.off` in DEBUG (default, so other
  lanes' `ios_sim.py shot`/`drive` scripts aren't blocked by an unexpected sheet); `force` → shows
  every gate-passing slide on every page regardless of seen-state; `on` → real seen-state
  behavior in DEBUG. Release always behaves as `.normal` (real behavior), ignoring the env var
  entirely. No `FST_DEBUG_FIRST_RUN` handling existed anywhere on `master` at the time this landed
  (checked via `git log`/`grep` before starting), so there was nothing to reconcile with Lane X.

- **Slot sharing:** the launch What's New sheet claims `FirstRunCenter` slot `whats-new`, so a
  carousel and the changelog never present together ([whats-new](../whats-new/ios.md)).
- **Stars:** demos use the web's `star_white`/`star_gold` images (`Resources/Stars.xcassets`,
  `Demo/FirstRunStar.swift`), never SF Symbol stars. Text is primary white; position is announced
  only through VoiceOver's `accessibilityValue` beside the page dots (no visible "Slide x of y").

## Seam edits (narrow, additive)

- `App/AppRouteDestination.swift` — `.firstRun(...)` appended to the 8 registered-page cases in
  the `switch` (`songDetail → .songInfo`, `playerHistory → .playerHistory`, `statistics`,
  `suggestions`, `leaderboards`, `compete`, `rivals`, `shop`); every other case (song leaderboards,
  player/band pages, rankings, licenses, …) is untouched — the web doesn't register those either.
- `App/FestivalRootView.swift` — the same 6 pages that are *also* tab roots (`songs`, `suggestions`,
  `leaderboards`, `compete`, `rivals`, `statistics`) get `.firstRun(...)` on their tab-root
  composition in `content(for:)` too, since reaching them as a tab never goes through
  `AppRouteDestination`. `FirstRunCenter.claim`/`release` make it safe for both the tab-root and a
  pushed-route instance of the same page to carry the modifier — only whichever is actually
  visible ever calls `onAppear`/succeeds at `claim` in practice.
- `App/FestivalSession+FirstRun.swift` — new file, following the established
  `FestivalSession+<Feature>.swift` convention; adds `session.firstRunCenter` without touching
  `FestivalSession.swift`.
- `Features/Settings/SettingsScreen.swift` — one line added to the section list:
  `FirstRunSettingsSection(session: session)`.

## Songs slide parity (9/9 — all with live native demos)

| Slide id | Live demo | Notes |
|---|---|---|
| `songs-song-list` | Yes (`FirstRunSongListDemo`) | 3 static demo rows on glass cards |
| `songs-sort` | Yes (`FirstRunSortDemo`) | Sort-mode list + direction indicator |
| `songs-navigation` | Yes (`FirstRunNavigationDemo`) | Compact tab-bar replica |
| `songs-filter` | Yes (`FirstRunFilterDemo`) | Instrument row + two toggle rows |
| `songs-icons` | Yes (`FirstRunSongIconsDemo`) | `InstrumentIcon` + FC/played/unplayed/not-charted badges |
| `songs-metadata` | Yes (`FirstRunMetadataDemo`) | Song card + metadata pill row |
| `songs-shop-highlight` | Yes (`FirstRunShopBadgeDemo(.highlight)`) | Gold glow + sparkles badge |
| `songs-new-in-shop` | Yes (`FirstRunShopBadgeDemo(.new)`) | Same gold treatment as "new" |
| `songs-leaving-tomorrow` | Yes (`FirstRunShopBadgeDemo(.leaving)`) | Red glow + clock badge |

These reuse real design primitives (`InstrumentIcon`, `festivalGlass`, `BrandTokens`) with a
small static demo-song pool (no network/session dependency, matching the web's own hardcoded
first-run demo data) rather than instantiating the full `SongRowView`/`FestivalSession` graph —
a lighter-weight but faithful-looking equivalent. Reusing the literal `SongRowView` type is a
possible future refinement, not required for a first pass.

## Other pages (31 slides) — live native demos (Lane D2, 2026-09-28)

Every remaining registered slide across Song Info (8), Player History (2), Statistics (6),
Suggestions (4), Leaderboards (3), Compete (3), Rivals (3) and Item Shop (4, `shop-views`
intentionally omitted — this lane's Shop screen has no grid/list view toggle yet) now renders a
live native mini-demo, ported from `pages/<page>/firstRun/demo/*.tsx` and the shared
`firstRun/demoData.ts`. All 42 catalog slides (9 Songs + 33 registered here) now resolve to a
live demo; `FirstRunDemoContent.hasLiveDemo(id:)` is unit-tested
(`FirstRunDemoCoverageTests.everyCatalogSlideHasALiveDemo`) against the full catalog so a future
slide added without a demo fails the build instead of silently falling back to
`FirstRunStaticIllustration`.

Shared building blocks live in `Features/FirstRun/Demo/`:
- `FirstRunDemoPool.swift` — hand-picked static sample data (songs, rankings, rivals, score
  history, percentiles, rival comparisons), mirroring the shape of the web's `demoData.ts` so
  every page's demo pulls from one small, non-networked pool instead of each file inventing its
  own numbers.
- `FirstRunDemoSupport.swift` — `firstRunPulse(_:)` (a `repeatForever` glow, standing in for the
  web's `shopBreathe*`/`pulseWrap` CSS animations; a no-op under Reduce Motion) and
  `firstRunStagger(_:)` (a brief per-row fade/rise-in echoing the web's cascading `FadeIn`, also a
  no-op under Reduce Motion — appears immediately instead), plus shared row views
  (`FirstRunRankRow`, `FirstRunRivalRow`, `FirstRunViewAllRow`, `FirstRunInstrumentHeader`,
  `FirstRunAlbumArtPlaceholder`) and `firstRunAccuracyTint(_:isFullCombo:)`, an accuracy-to-color
  ramp approximating the web's `accuracyColor` gradient.

Both animation helpers are pure SwiftUI (`withAnimation`/`repeatForever`), not `Timer`/Combine —
they cost nothing while a slide is off-screen in the carousel's `TabView(.page)`. The web's
several *content-rotating* timers (`BarSelectDemo` cycling the selected bar, `CategoryCardDemo`
swapping templates, `CompeteHubDemo`/`RivalsInstrumentsDemo` alternating rows, etc.) were
deliberately **not** ported 1:1: `TabView(.page)` mounts every slide up front, so a real
`setInterval`-style timer per demo would keep running for slides that aren't currently visible —
exactly the "no heavy views and no timers when not visible" rule this lane was asked to keep.
Each such demo instead shows one static, representative state (documented per-slide below) —
still faithful to the slide's title/description, just not animated over time.

| Slide id | Live demo | Notes |
|---|---|---|
| `songinfo-chart` | `FirstRunSongInfoChartDemo` | Swift Charts `BarMark` (accuracy, gold when FC) with score annotated per bar |
| `songinfo-bar-select` | `FirstRunSongInfoBarSelectDemo` | Same chart with the last bar's selection stroke + a static detail row (web cycles the selection on a timer) |
| `songinfo-view-all` | `FirstRunSongInfoViewAllDemo` | Own score rows (last one faded) + pulsing "View all scores" |
| `songinfo-top-scores` | `FirstRunSongInfoTopScoresDemo` | Instrument header + top leaderboard rows + pulsing "View full leaderboard" |
| `songinfo-paths` | `FirstRunSongInfoPathsDemo` | Instrument row + difficulty row + static path-preview placeholder (no network image fetch) |
| `songinfo-shop-button` | `FirstRunSongInfoShopPillDemo(tone: .shop)` | Green pill, pulsing |
| `songinfo-new-in-shop` | `FirstRunSongInfoShopPillDemo(tone: .new)` | Gold pill, pulsing |
| `songinfo-leaving-tomorrow` | `FirstRunSongInfoShopPillDemo(tone: .leaving)` | Red pill, pulsing |
| `playerhistory-score-list` | `FirstRunPlayerHistoryScoreListDemo` | Score rows, personal best highlighted purple |
| `playerhistory-sort` | `FirstRunPlayerHistorySortDemo` | Sort-mode list (Date/Score/Accuracy/Season) + direction row, mirroring `FirstRunSortDemo`'s established layout |
| `statistics-select-profile` | `FirstRunStatsSelectProfileDemo` | Pulsing "Select This Player" pill |
| `statistics-drill-down` | `FirstRunStatsDrillDownDemo` | 2-col stat grid; drillable cards pulse |
| `statistics-overview` | `FirstRunStatsOverviewDemo` | 2-col global summary stat grid |
| `statistics-instrument-breakdown` | `FirstRunStatsInstrumentBreakdownDemo` | Instrument header + 2-col stat grid |
| `statistics-percentiles` | `FirstRunStatsPercentilesDemo` | Percentile/song-count table |
| `statistics-top-songs` | `FirstRunStatsTopSongsDemo` | Song rows with percentile badges |
| `suggestions-category-card` | `FirstRunSuggestionsCategoryCardDemo` | One themed card ("Almost Full Combo"); web rotates templates on a timer, this shows the first |
| `suggestions-global-filter` | `FirstRunSuggestionsGlobalFilterDemo` | Suggestion-type toggle list, all enabled |
| `suggestions-instrument-filter` | `FirstRunSuggestionsInstrumentFilterDemo` | Instrument row + that instrument's toggles |
| `suggestions-infinite-scroll` | `FirstRunSuggestionsInfiniteScrollDemo` | Stacked cards with a bottom fade mask (web auto-scrolls via `requestAnimationFrame`; a perpetual scroll loop is exactly the excluded "heavy" case) |
| `leaderboards-overview` | `FirstRunLeaderboardsOverviewDemo` | Instrument header + top rankings |
| `leaderboards-experimental-metrics` | `FirstRunLeaderboardsExperimentalMetricsDemo` | Metric radio list with hints |
| `leaderboards-your-rank` | `FirstRunLeaderboardsYourRankDemo` | Rank neighborhood, player row highlighted, pulsing "View all rankings" |
| `compete-hub` | `FirstRunCompeteHubDemo` | Compact rankings + one rival above/below shown together (web alternates the two layouts on a timer) |
| `compete-leaderboards` | `FirstRunCompeteLeaderboardsDemo` | Reuses `FirstRunLeaderboardsOverviewDemo` |
| `compete-rivals` | `FirstRunCompeteRivalsDemo` | Above/Below rival rows |
| `rivals-overview` | `FirstRunRivalsOverviewDemo` | Above/Below rival rows |
| `rivals-instruments` | `FirstRunRivalsInstrumentsDemo` | Per-instrument (Lead/Drums/Vocals) rival sections |
| `rivals-detail` | `FirstRunRivalsDetailDemo` | "Closest Battles" song comparison rows (web cycles categories on a timer) |
| `shop-overview` | `FirstRunShopOverviewDemo` | Grid of placeholder tiles |
| `shop-highlighting` | `FirstRunShopHighlightingDemo` | Rows alternate a pulsing green highlight and none |
| `shop-new-items` | `FirstRunShopNewItemsDemo` | Rows cycle gold/green/none by index (static per-row assignment, no timer) |
| `shop-leaving-tomorrow` | `FirstRunShopLeavingTomorrowDemo` | Rows cycle red/green/none by index |

Simplified vs. the web on every demo: no live network album art or session data (matching the
web's own hardcoded first-run pools), no interactive taps (the carousel demos are inert previews,
same as Songs'), and the several content-*rotation* timers noted above collapse to one
representative state instead of cycling.

## Known gaps / follow-ups

- `shop-views` slide omitted pending the Shop grid/list view toggle (add it back to
  `FirstRunCatalog.shop` once that toggle ships).
- `ready` is always `true`: `FestivalSession` resolves the selected-player identity synchronously
  from storage at init, so there's no async gap where gates could evaluate against stale data on
  this platform. Revisit if a future async gate dependency is added.
- No XCUITest coverage yet for the carousel or replay flow (Wave 1 is unit + visual smoke only,
  per `PROGRESS.md` §3); `fst.first-run.close/skip/next/done` and
  `fst.settings.first-run.<page>` accessibility identifiers are in place for when that lands.
- `contracts/product.json` has no `first-run` control entry yet (orchestrator-owned file, not
  edited by this lane) — `check_docs.py` reports the same pending "topic not in contracts"
  warning that `songs-section-index` already has on `master`.
