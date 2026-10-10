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
  - `FirstRunCarouselView.swift` — the paged carousel (operator batches 6–7): `TabView(.page)`
    with the system dots hidden and white `FirstRunPageDots` (current solid, others 35 %; one
    adjustable "Page, n of m" element); the system toolbar **Close** from the shared
    `FestivalModal` (`Button(role: .close)` glyph on iOS 26, issue #23; it replaced issue #4's
    text "Close", which itself replaced a hand-drawn ✕) beside an inline navigation title naming
    the page the guide explains (`FirstRunPageKey.guideTitle`, issue #24: the Settings row label,
    e.g. "Songs", "Score History"; all under 15 characters per HIG Toolbars), on launch and on a
    Settings replay alike. Controls follow Apple's onboarding layout (issue #25): a system
    toolbar **Back** chevron at the top leading edge (`fst.first-run.back`, label "Back", HIG
    Toolbars: "Leading: back/previous-document … controls, then the view title"; only after
    page one, never disabled); one large accent-tinted `.glassProminent` **Next/Done**
    (`.borderedProminent` before iOS 26; `.controlSize(.large)`, ≈48 pt on screen); then a
    full-width `.borderless` accent-tinted **Skip** beneath it (body text, ≥48 pt row; issue
    #380, see [Native controls and web motion](#native-controls-and-web-motion-issue-380)) until
    the last page. The Skip row stays reserved on the last page so Done doesn't move; a one-page
    guide shows only Done (`FirstRunControls` in `FestivalCore/FirstRunViewing.swift`:
    `showsBack`, `showsSkip`, `reservesSkipRow`, `minimumHeight`). iOS 26 draws the 86 % sheet
    about 0.96× scaled, so 48 pt layouts read ≈46 pt in XCUITest frames; the toolbar Back/Close
    report 34.6 pt frames but take system-expanded hit regions (near-miss taps at ±20 pt land).
    Embedded real sheets in demos (Sort/Filter) set `festivalModalPreview`, so `FestivalModal`
    renders only their content: a nested `NavigationStack` would otherwise merge its title
    ("Sort By") and a second, working Close into the guide's bar. Presented at an 86 % detent
    (`FirstRunSheetStyle`) so tapping the dimmed page above it, or swiping down, dismisses.
    VoiceOver focus is left to the system on open, so the navigation title is announced first
    (HIG VoiceOver: a screen's title is announced first); `@AccessibilityFocusState` then moves
    focus to each new slide on a page change. Accessibility test (#429): at AX5 the title is a
    heading read before Close and the slide, wholly on screen beside a hittable Close with a clean
    bar audit (`FirstRunJourneyTests.testGuideTitleIsReadFirstAtLargestText`, Songs and
    Leaderboards guides, in `apple-ci`'s simulator journeys). The title is navigation-bar chrome a
    macOS-hosted view cannot reproduce (a hosted `NavigationStack` bridges no window title), so a
    simulator journey, not a hosted test, is its evidence. Animations skip under Reduce Motion. Each slide's
    title and description fade up after its demo cascade (`FirstRunMotion.textDelays`).
  - **Seen pages only**: the carousel records every page shown in a `FirstRunViewing` binding;
    the presenter's `onDismiss` marks only those seen (however it closed), so unviewed pages
    show next time (web new-info rule). Settings replays do the same after resetting the page.
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
- **Stars:** demos use the web's `star_white`/`star_gold` images (shared `Design/StarRating.swift`, wrapped by
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

## Songs slide parity (9/9 — the app's real Songs UI, batch 7)

`Demo/FirstRunNativeSongsDemos.swift`. The presenter injects `\.firstRunSession`; demos show
three live catalogue songs with art (the cached keyless `/api/songs`, as the web demos switch to
catalogue songs once loaded). Demos are inert (no hit testing, hidden from VoiceOver; the slide's
title/description is the accessible content).

### Demo songs come from the catalogue (issue #26)

Every song-using demo (Songs, `statistics-top-songs`, `rivals-detail`,
`suggestions-category-card`, all four Shop demos) goes through
`FirstRunCatalogueSongs(count:source:content:)`; no demo ships invented titles.
- `FestivalCore.FirstRunDemoSongs.pick` ports the web's `useDemoSongs`/`useItemShopDemoSongs`:
  only songs with art; preferred IDs, then "Epic Games" artists, then the rest. Catalogue order
  replaces the web's shuffle so captures and tests stay deterministic (`FirstRunDemoSongsTests`).
- `.itemShop` prefers the session's already-loaded Shop songs only when Shop and catalogue
  observed publications match; demos never fetch the Shop.
- Loading, failure or no session: `FirstRunDemoSongs.placeholders` render as muted art tiles with
  `.redacted(.placeholder)` text (HIG Loading: "use placeholder text, graphics, or animations
  until content arrives"); the swap to live songs animates unless Reduce Motion is on
  (`FirstRunHostedTests.songDemosRenderPlaceholdersWithoutCatalogue`). Ranks and percentiles stay
  static `FirstRunDemoPool` numbers (Top Songs uses the web's `DEMO_PERCENTILES`).
- Song demos are decorative (HIG VoiceOver: "Exclude purely decorative images that convey no
  useful or actionable information"): placeholders and catalogue songs alike stay hidden, and
  the slide reads only "title. description", then dots, Next, Skip. Pinned per song demo in both
  states, at Large and AX5, by `FirstRunDemoSongsAccessibilityTests` (#401), and on iOS at AX5
  with `performAccessibilityAudit` by `FirstRunJourneyTests.testSongDemoSlideAccessibleAtLargestText`
  (in `apple-ci`'s simulator journeys).
- At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`) the slide takes the
  compact-height path: a 120 pt demo and the text in a `ScrollView` (#401: at AX5 the full layout
  cut the Song List description off after "Tap a song to see" under the dots). HIG Typography:
  "Keep text truncation to a minimum as font size increases." The combined slide keeps
  `.isStaticText` so the scroll path still reads as text.

| Slide id | Demo | Real UI used |
|---|---|---|
| `songs-song-list` | `FirstRunNativeSongListDemo` | `SongRowView` ×3 |
| `songs-sort` | `FirstRunNativeSortDemo` | `SongsSortSheet` (top, clipped) |
| `songs-navigation` | `FirstRunNativeNavigationDemo` | System `TabView` tab bar (Liquid Glass on 26) with the shell's `FestivalSection` titles and symbols; it sets `.tabViewStyle(.automatic)` because the carousel's `.page` style is inherited by nested tab views and would leave a blank pager with no tab bar, and on iOS 26.1 turns off the inherited page-tools bottom accessory and the tab-bar backdrop; each tab shows `BrandTokens.appBackground` inside `firstRunPreviewCard()` (fixed in #380) |
| `songs-filter` | `FirstRunNativeFilterDemo` | `SongsFilterSheet` (top, clipped) |
| `songs-icons` | `FirstRunNativeIconsDemo` | Row chrome + `SongInstrumentStatusChips` (`SongInstrumentBadge.demoPattern`) |
| `songs-metadata` | `FirstRunNativeMetadataDemo` | Row chrome + `SongMetadataFieldView` + `SongProfileMetadataPills` |
| `songs-shop-highlight` / `-new-in-shop` / `-leaving-tomorrow` | `FirstRunNativeShopDemo` | `SongRowView` with its Shop outline/badge |

Issue #380 moved the other pages' demos onto the app's real views where one exists (below);
the rest are still demo layouts built from the app's tokens.

## Native controls and web motion (issue #380)

Owner: "every single FRE needs a deep pass … to actually use platform UX that it's showing,
match web behaviors for animations, fades, infinite scrolls … and iOS needs a pass on
Next/Skip/Back". HIG Onboarding: "make onboarding fast, fun, and optional" and teach through the
app's own interface.

- **Rule: a demo shows the real control.** When the page has a reusable view for what the slide
  teaches, the demo embeds it inert (`firstRunInert()`), and sheets go in a
  `firstRunSheetPreview(height:)` frame. Never add a look-alike copy to `Demo/`. If a page's view
  can't be built without a session, extract a small public view from it (as with
  `ProfileIdentityButton`, `SongDetailShopGlyph`, `ScoreHistoryEntry.init(songId:…)` and
  `PlayerPercentileBucket.init(topPercent:count:)`, `SongPathsSelectorRow`).
- **Web motion lives in Core:**
  - `FestivalCore/FirstRunMotion.swift` holds the web timings. The cascade steps 125 ms, rows
    80 ms, Item Shop tiles 60 ms, Rivals detail 100 ms, with a 200 ms exit.
  - Each slide's `contentStaggerCount` (one per `FirstRunCatalog` slide id; `FirstRunMotionTests`
    checks coverage) delays the title by count × 125 ms and the description one step more.
  - `FirstRunAutoScroll` glides at 30 pt/s after 100 ms and wraps to the top. Its 36 pt fades
    show only on edges that hide cards.
  - Unit tests: `FirstRunMotionTests` (every catalogue slide has a count). The hosted tests
    `FirstRunDemoCoverageTests` cover the Item Shop row phases and the six scroll templates.
- **Replays like the web.** The web remounts a slide whenever it becomes visible, so cascades
  replay each time a page is shown, keyed on `\.firstRunSlideActive`. The still override
  (`FST_DEBUG_STILL_BACKGROUND`) shows everything at rest.
- **Reduce Motion** (system or app; HIG Accessibility: "reduce automatic and repetitive
  animation"):
  - no cascade and no title fade;
  - the infinite scroll holds at the top;
  - pulses hold at 0.7;
  - rotating demos never tick: they rest on their first state with no fade or transition.
  - Every First Run motion reads the one `@FirstRunReduceMotion` value (system or app).
    Never read `accessibilityReduceMotion` alone in `FirstRun/`.
- **Pulses** reuse the Item Shop row pulse (`ShopPulseLayer`, `ShopRowPulseBorder`; see
  [Apple architecture](../../platforms/apple/architecture.md)). Accent blue marks a CTA. Song rows and the
  Song Details action pulse in their own Item Shop tone.
- **Skip (agent decision, #380; the owner may override with `/choose`).**
  - Skip is now a full-width `.borderless` button: body text tinted `AccentText.blue`, ≥48 pt.
    It replaces the white plain text, which read as a web link.
  - Next/Done keep `.glassProminent`/`.borderedProminent`. HIG Buttons: "use a prominent style
    (accent-color background) for the most likely action" and "Distinguish the preferred choice
    by style, not size". This prominent primary with a tinted borderless secondary is the
    layout of Apple's own setup screens.
  - Back stays the system toolbar chevron (HIG Toolbars), and the white page dots stay (an
    operator decision).
  - Rejected: a bordered Skip, which competes with Next; and Skip in the toolbar, where Close
    already dismisses.

### FREs reviewed (#380)

One shared implementation serves every Apple form factor. Every slide was checked against the web demo and its page's real view. Rotating slides hold still under system or app Reduce Motion.

| Page | Slides | Outcome |
|---|---|---|
| Songs (9) | song-list, sort, navigation, filter, icons, metadata, shop-highlight, new-in-shop, leaving-tomorrow | Already the real Songs UI (batch 7). The text cascade was added; Item Shop rows use the real pulse |
| Song Info (8) | chart, bar-select, view-all, top-scores, paths, shop-button, new-in-shop, leaving-tomorrow | Real score rows, `PurpleActionLabel`, the Paths sheet's real menus (`SongPathsSelectorRow`) and the real Item Shop action; web cascade |
| Player History (2) | score-list, sort | Real rows and the real sort sheet |
| Statistics (6) | select-profile, drill-down, overview, instrument-breakdown, percentiles, top-songs | Real Select Player button, section header and percentile table; the stat grids already use the page's cards |
| Suggestions (4) | category-card, global-filter, instrument-filter, infinite-scroll | Real filter sheet; the infinite scroll is ported |
| Leaderboards (3) | overview, experimental-metrics, your-rank | Web cascade (80 ms rows) |
| Compete (3) | hub, leaderboards, rivals | Web cascade |
| Rivals (3) | overview, instruments, detail | Real instrument headers; web cascade (80/100 ms) |
| Item Shop (4) | overview, highlighting, new-items, leaving-tomorrow | Real Songs rows with the Item Shop pulse; 60 ms tile cascade |

What's New has no demos, so it's not applicable. Android and Windows follow in their own
platform notes.

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
- `FirstRunDemoPool.swift` — hand-picked static sample numbers (rankings, rivals, score
  history, percentiles, rival rank/score comparisons), mirroring the shape of the web's
  `demoData.ts`. It holds no songs: song-using demos read the catalogue (see "Demo songs come
  from the catalogue" above).
- `FirstRunDemoSupport.swift` — `firstRunPulse(_:)` (the web's `pulseWrap`: a 2 pt border
  tracing the surface, opacity 0 → 0.7 → 0 over 2 s, drawn by the Item Shop row pulse's
  `ShopPulseLayer`; held at 0.7 under Reduce Motion and still on any slide but the visible one,
  via `\.firstRunSlideActive` and `FirstRunPulsePolicy`, because the paged `TabView` keeps
  neighbours alive; the sheet also pauses the backdrop, see [artwork background](../artwork-background/ios.md#power-and-frame-budget-issue-28)),
  `firstRunStagger(_:interval:)` (the web's cascading `FadeIn`, replayed each time the slide
  becomes the visible page and faded out over 0.2 s as it leaves; content appears at rest under
  Reduce Motion) and `firstRunFadeIn(delay:)` for slide text, plus shared row views
  (`FirstRunRankRow`, `FirstRunRivalRow`, `FirstRunViewAllRow`, `FirstRunInstrumentHeader`,
  `FirstRunSongArt`, which draws a real song's shared-cache artwork or a muted placeholder tile;
  `FirstRunViewAllRow` draws the real buttons' `PurpleActionSurface` and each demo passes it as
  its group card's `action:`, so it ends the card inside it like the real pages,
  [view-all-cta](../../patterns/view-all-cta.md) R1, #382)
  and `firstRunAccuracyTint(_:isFullCombo:)`, an accuracy-to-color
  ramp approximating the web's `accuracyColor` gradient.

`firstRunPulse`/`firstRunStagger` are pure SwiftUI (`withAnimation`/`repeatForever`), not
`Timer`/Combine. `firstRunStagger` uses the web `FadeIn` timing (0.4 s ease-out, 125 ms per row,
12 pt rise; `FirstRunDemoTiming`).

### Data-swap rotation (issue #27)

The web demos rotate to new data on a timer (`useSlideRotation`/`useRowSwaps`, CSS `ease` fades).
Before #27 iOS showed one static state per demo; now each rotating demo swaps like the web:
- **Core:** `FestivalCore/FirstRunDemoRotation.swift` holds the web timing (`FirstRunDemoTiming`: 5 s
  interval, 400 ms fade out → swap while hidden → 400 ms fade in), `FirstRunDemoRotation.swapCount`/
  `swapIndices` (web: 1 row per tick for up to 3 rows, 2 for 4–6, else 3, chosen at random; seeded SplitMix64 here for
  determinism), `FirstRunRowRotation` (swap rows to unused pool songs, never showing a duplicate),
  `FirstRunWindowRotation` (fixed-size windows over a pool) and `FirstRunDemoScorePattern` (the
  web's per-title `hashString` → FC/scored/none chips). Unit tests: `FirstRunDemoRotationTests`.
- **Driver:** `Demo/FirstRunDemoRotationViews.swift`. `FirstRunCarouselView` sets
  `\.firstRunDemoActive` only for the visible page while the scene is `.active`, so the
  `TabView(.page)` slides mounted off-screen run no timer (the reason rotation was skipped before).
  `.firstRunDemoTicker` is a `task(id:)` sleep loop; it also stops in Low Data Mode for demos that
  load artwork and under `FST_DEBUG_STILL_BACKGROUND`. `FirstRunDemoSwap.run` performs fade out →
  update without animation → fade in; `.firstRunSwapRow` hides the fading slots (opacity 0 plus the
  web's per-demo rise). Rows use positional identity so the same view fades instead of being
  replaced. Swapped-in artwork is prefetched into the shared bounded cache during the fade-out.
- **Reduce Motion** (system or app, `@FirstRunReduceMotion`; HIG Accessibility: "reduce
  automatic and repetitive animation"): the ticker stops (`FirstRunDemoTickerPolicy`), so each
  demo rests on its first state with no fade, rise or transition (#380, load-transition R6).
- Hosted tests: `FirstRunDemoRotationUITests` (swap order, ticker policy, cancellation
  completes, web pools/templates; an active bar-select demo advances while an inactive one
  stays still, and system or app Reduce Motion holds an active one still past its interval).

| Slide | Rotation (web source) |
|---|---|
| `songs-song-list` | 1 row per 5 s from a 24-song pool (`SongListDemo`) |
| `songs-icons` | 2 rows, chips follow the per-title hash pattern (`SongIconsDemo`) |
| `songs-metadata` | 1 row; pills from the web `META_DATA` record picked by title hash (`MetadataDemo`) |
| `statistics-top-songs` | 4 rows, 2 per tick (`TopSongsDemo`) |
| `songinfo-bar-select` | Selection starts at bar 0 and moves every 2.5 s; detail card fades 300 ms (`BarSelectDemo`) |
| `suggestions-category-card` | The web's 4 templates in order, whole card fades with an 8 pt rise (`CategoryCardDemo`) |
| `leaderboards-experimental-metrics` | Selected metric advances every 5 s, no fade (`ExperimentalMetricsDemo`) |
| `compete-hub` | Alternates leaderboard and rivals layouts, 6 pt rise (`CompeteHubDemo`) |
| `compete-rivals` / `rivals-overview` | Above, then Below group swaps to the next window of the web's 6-rival pools, 4 pt rise |
| `rivals-instruments` | 6 rival slots, 2 per tick, each walking its own above/below pool |
| `rivals-detail` | Whole card fades; the category advances through the web's 6 and rows re-stagger |

The infinite-scroll demo's auto-scroll is ported in #380 (see below); Shop demos have no
rotation on the web either.

| Slide id | Live demo | Notes |
|---|---|---|
| `songinfo-chart` | `FirstRunSongInfoChartDemo` | Swift Charts `BarMark` (accuracy, gold when FC) with score annotated per bar |
| `songinfo-bar-select` | `FirstRunSongInfoBarSelectDemo` | Same chart; the selection stroke and detail card cycle bars like the web (see rotation table) |
| `songinfo-view-all` | `FirstRunSongInfoViewAllDemo` | Real `ScoreHistoryListRow`s (last one faded) + pulsing `PurpleActionLabel` "View All Scores" |
| `songinfo-top-scores` | `FirstRunSongInfoTopScoresDemo` | Instrument header + top leaderboard rows + pulsing "View full leaderboard" |
| `songinfo-paths` | `FirstRunSongInfoPathsDemo` | The Paths sheet's real Instrument/Difficulty/View menus (`SongPathsSelectorRow`, inert) below a still path-area placeholder (no network image fetch); selectors fade in first, as on the web |
| `songinfo-shop-button` | `FirstRunSongInfoShopPillDemo(tone: .shop)` | Song header card with the real Song Details Item Shop action (`SongDetailShopActionStyle`: breathing bag, or the titled `festivalCardCapsule` on a vertical section bar — a demo replica is a custom control, so never shipping glass (surface-materials `apple-glass-consumers`)); green |
| `songinfo-new-in-shop` | `FirstRunSongInfoShopPillDemo(tone: .new)` | Same, gold |
| `songinfo-leaving-tomorrow` | `FirstRunSongInfoShopPillDemo(tone: .leaving)` | Same, red |
| `playerhistory-score-list` | `FirstRunPlayerHistoryScoreListDemo` | Real `ScoreHistoryListRow`s, personal best highlighted |
| `playerhistory-sort` | `FirstRunPlayerHistorySortDemo` | The real `PlayerHistorySortSheet` in a sheet preview |
| `statistics-select-profile` | `FirstRunStatsSelectProfileDemo` | Player card with the real Profile `ProfileIdentityButton` (Select Player), pulsing |
| `statistics-drill-down` | `FirstRunStatsDrillDownDemo` | 2-col stat grid; drillable cards pulse |
| `statistics-overview` | `FirstRunStatsOverviewDemo` | 2-col global summary stat grid |
| `statistics-instrument-breakdown` | `FirstRunStatsInstrumentBreakdownDemo` | Real `InstrumentSectionHeader` + 2-col stat grid |
| `statistics-percentiles` | `FirstRunStatsPercentilesDemo` | The real `PlayerPercentileTableCard` |
| `statistics-top-songs` | `FirstRunStatsTopSongsDemo` | 4 catalogue song rows (art, artist · year) with the web's demo percentile badges |
| `suggestions-category-card` | `FirstRunSuggestionsCategoryCardDemo` | Rotating themed card of 2 catalogue songs: the real `SuggestionCategoryCardView` with a session, else a redacted approximation |
| `suggestions-global-filter` | `FirstRunSuggestionsGlobalFilterDemo` | The real `SuggestionsFilterSheet` in a sheet preview |
| `suggestions-instrument-filter` | `FirstRunSuggestionsInstrumentFilterDemo` | The same sheet with its per-instrument sections |
| `suggestions-infinite-scroll` | `FirstRunSuggestionsInfiniteScrollDemo` | The web's 6 category cards glide up at 30 pt/s and loop, with 36 pt edge fades only on edges hiding cards (`FirstRunAutoScroll`); still under Reduce Motion |
| `leaderboards-overview` | `FirstRunLeaderboardsOverviewDemo` | Instrument header + top rankings |
| `leaderboards-experimental-metrics` | `FirstRunLeaderboardsExperimentalMetricsDemo` | Metric radio list with hints |
| `leaderboards-your-rank` | `FirstRunLeaderboardsYourRankDemo` | Rank neighborhood, player row highlighted, pulsing "View all rankings" |
| `compete-hub` | `FirstRunCompeteHubDemo` | Alternates compact rankings and rivals above/below, like the web |
| `compete-leaderboards` | `FirstRunCompeteLeaderboardsDemo` | Reuses `FirstRunLeaderboardsOverviewDemo` |
| `compete-rivals` | `FirstRunCompeteRivalsDemo` | Above/Below rival rows (2 each), rotating |
| `rivals-overview` | `FirstRunRivalsOverviewDemo` | Above/Below rival rows (3 each), staggered and rotating |
| `rivals-instruments` | `FirstRunRivalsInstrumentsDemo` | Per-instrument rival sections under the real `InstrumentSectionHeader`, rotating 2 slots per tick |
| `rivals-detail` | `FirstRunRivalsDetailDemo` | Category card ("Closest Battles" first) of 3 catalogue songs with demo rank comparisons; cycles the web's 6 categories |
| `shop-overview` | `FirstRunShopOverviewDemo` | 3-column grid of 6 Item Shop/catalogue song art tiles |
| `shop-highlighting` | `FirstRunShopHighlightingDemo` | Real Songs rows (`SongRowView`) alternate the green Item Shop pulse and none |
| `shop-new-items` | `FirstRunShopNewItemsDemo` | Real Songs rows cycle gold/green/none by index (`FirstRunShopRowPhase`, no timer) |
| `shop-leaving-tomorrow` | `FirstRunShopLeavingTomorrowDemo` | Real Songs rows cycle red/green/none by index |

Simplified vs. the web on every demo: song-using demos show catalogue songs and their art, but
ranks, scores and percentiles are static demo numbers rather than the player's session data
(matching the web's own first-run pools), and there are no interactive taps (the carousel demos are
inert previews, same as Songs').

## Known gaps / follow-ups

- `shop-views` slide omitted pending the Shop grid/list view toggle (add it back to
  `FirstRunCatalog.shop` once that toggle ships).
- `ready` is always `true`: `FestivalSession` resolves the selected-player identity synchronously
  from storage at init, so there's no async gap where gates could evaluate against stale data on
  this platform. Revisit if a future async gate dependency is added.
- XCUITest: `FirstRunJourneyTests.swift` (Next first with Skip beneath and Back in the bar
  before the title (`testNextFirstThenBackAppears`), Done on the last page, ≥44 pt Next/Skip
  frames and near-miss taps on Back/Next/Skip/Close read as buttons
  (`testControlsAcceptNearMissesAndReadAsButtons`), one Close and the guide title on every
  slide (`testEmbeddedSheetDemosKeepOneCloseAndTheGuideTitle`), native navigation-bar
  Close labelled "Close" (`testCloseIsNativeToolbarButton`), the page's navigation title on launch
  and on a Settings replay (`testGuideShowsPageTitleInNavigationBar`), swipe-down and tap-outside dismissal, viewed-pages-only across a relaunch; needs `mock_service.py --port 8765`).
  Tap-outside must land below the status bar (a status-bar tap is scroll-to-top).
- `contracts/product.json` has no `first-run` control entry yet (orchestrator-owned file, not
  edited by this lane) — `check_docs.py` reports the same pending "topic not in contracts"
  warning that `songs-section-index` already has on `master`.
