# Apple architecture

> **What:** how the shared Swift code is structured and the runtime invariants every Apple feature must keep. **Read when:** adding Apple code, a network read, a cache or a shared component. Folder ownership per lane: [PROGRESS.md §1](../../../PROGRESS.md).

## Layout

| Path | Contents |
|---|---|
| `apple/Sources/FestivalCore` | URLSession wire models, publication consistency (pin / 409 retry / 304 ETag), session cache, policies (`SongShopFilter`, `SongPlayerScoreFilter`, `SongInstrumentStatusPolicy`, …). New domains go in `FestivalAPI+<Domain>.swift` |
| `apple/Sources/FestivalDesign` | Generated `BrandTokens.swift` ([tokens](../../design/fluent.md)), `FestivalText` (text colour rule), branded controls (difficulty meter) |
| `apple/Sources/FestivalUI/App` | `AppRoute`, `AppRouteDestination`, `FestivalTabStack` (orchestrator); `FestivalRootView`, `Shell/*`; `FestivalSession` (+ `FestivalSession+<Feature>.swift`) |
| `apple/Sources/FestivalUI/{Background,Common,Design}` | Animated background host; status views; `festivalGlass`, `FestivalSectionHeader`, `InstrumentIcon`, `StarRating` |
| `apple/Sources/FestivalUI/Features/<Feature>` | One folder per page family (Songs, SongDetail, Shop, Profile, Leaderboards, SongLeaderboard, Settings, Rivals, …) |
| `apple/Apps/{iOS,macOS}`, `apple/Apps/*UITests` | App entry points and XCUITests (UITests frozen during Wave 1) |
| `apple/Tests/{FestivalCoreTests,FestivalDesignTests,FestivalUITests}` | SwiftPM tests; hosted snapshot helpers in `FestivalUITests` |

Separate navigation shells for iOS/iPadOS and macOS share Core, Design and screen state. Deployment targets: iOS 17, macOS 14.

## Runtime invariants

- **Network:** keyless public HTTPS by default; fixture origin only by explicit Debug override ([build-and-run](build-and-run.md), [service safety](../service-safety.md)).
- **One request path:** every service GET goes through `FestivalAPI.send(_:)` (`FestivalAPI+Request.swift`): keyless guard (rejects `X-API-Key`, `x-fst-selected-*`, non-GET), 30 s timeout, cancellation checks, then `mapStatus` (2xx; 202 syncing only where the endpoint accepts it; 404; 503 → `publicReadFrozen`/`unavailable` with `Retry-After`). Pinned reads use `read(_:)` (`PublicEndpoint`); unpinned reads use `fetch`/`fetchJSON` (`OperationalEndpoint`, `RivalsEndpoint`). **Add endpoints via the [add-endpoint skill](../../skills/add-endpoint/SKILL.md); never create another `URLSession` or call `transport.send` directly.**
- **Errors:** screens store `ServiceIssue(error)` and render `ServiceStatusView` / `ServiceStatusInline` ([service-status](../../controls/service-status/ios.md)); they never switch on HTTP codes.
- **Online-only:** in-process caches for speed are fine; do not build offline/warm-cache disclosure UX. Existing publication guards (`SongShopPublicationPolicy`, `SongRelatedPublicationPolicy`) stay; new features should not add provenance machinery.
- **Publication joins:** Shop-derived state and the selected-player score index each record their observed publication; catalogue, related data and session must agree before decorating Songs rows. On mismatch show a readable paused state rather than hiding, reordering or badging older rows. An observed ID is not response-header proof.
- **Caches (process-only):** `SessionResponseCache` holds publication-bound ETag responses; typed-and-validated headerless snapshots are bounded (16 MB / 128 entries), never sent as conditional ETags, and cleared when another publication is observed. `ArtworkCache` = 32 MB evictable `NSCache` + strongly held 16 MB / 64-URL recent LRU (evictable-only lost visible Shop covers on route re-entry) + 24 MB decoded thumbnails; all cleared on a known publication change; never persisted to disk; never replace a failed image with success-shaped data. CHOpt PNGs: 32 MB / 16-entry LRU, 8 MB per response before caching.
- **Cancellation:** check cancellation before any cache mutation and again inside the cache actor, so a cancelled older reply cannot overwrite a newer one or poison the next 304.
- **Accessibility settings:** the app may expose additive Reduce Motion / Contrast / Transparency / artwork-animation overrides; it never toggles VoiceOver.

### Per-entity screens

A screen showing one account, band or rival must reset its state when that entity changes. It must never draw, or accept a late response for, a different entity.

- **Key identity with the entity.** Apply `.id(entityId)` wherever the entity can change under a surviving view: `AppRouteDestination` does this for `.player`/`.playerBands` (the viewed account) and for `.allRivals`/`.rivalDetail`/`.rivalry` (the selected account). `StatisticsScreen` keys `PlayerProfileContent` by `selected.accountId`, and the Rivals/Compete hubs key their sections by `session.selectedPlayer?.accountId`. `.id` must be applied by the *parent*: inside a view's own `body` it resets only children, not that view's `@State`.
- **Include the id in `task(id:)`**, and in any late-response guard key (`PlayerBandsScreen.RequestKey` carries `accountId`). `task(id:)` alone is not enough: it reloads *after* the new id has already rendered once with the old state. That is why `PlayerProfilePhase.shown(for:)` also refuses to draw a payload whose `accountId` differs.
- **Selected-player reads** (`FestivalSession+Rivals`) resolve `session.selectedPlayer` at call time. Their views must therefore key on the selected account, not just on instrument/scope.
- **Never cache the entity in session-level singletons.** `FestivalSession` holds only the *selected* identity and its score index, never a "last viewed" profile.

### Reappearance keeps loaded content

SwiftUI restarts `.task(id:)` each time a view reappears in a `NavigationStack` (Back from a pushed page, a tab switch), even with an unchanged id. A load that starts with `state = .loading` therefore swaps loaded rows for a shorter spinner and re-fades them, shifting the page under the pop transition (#39: Compete › View Full Leaderboard › Back).

- Guard such loads with a remembered key: `ReappearanceLoadGate` (FestivalCore). Skip while `needsLoad(for:)` is false and call `markLoaded(_:)` only after a successful read, so a failure or cancellation retries on the next appearance.
- The key holds everything the read depends on. Compete/Rivals sections use `CompeteSectionLoadKey`: instrument, selected account and `session.publicationRevision`.
- Earlier inline variants: Leaderboards `loadedKey`, `PlayerProfileContent`/`InstrumentStatsCard`/`PlayerProfileCharts` `loadedKey`, Suggestions `handled*Revision`.
- Hosted macOS `NavigationStack`s keep the root appeared across a push. To test the cycle, take the host out of its window and back (`competeKeepsLoadedLeaderboardsWhenItReappears`).

### List rows hold one action

Never put several default-style `Button`s or `NavigationLink`s in **one** `List`/`Form` row (e.g. a `LazyVStack` of results inside a single `Section` row). On iOS such a row makes the whole row the hit target and fires **every** control in it on one tap. This caused the 2026-09-28 wrong-account bug: tapping any profile search result pushed one `/player/:id` per result, leaving the *last* result's profile on top. Emit one row per action (`PlayerSearchResultRows` is a bare `ForEach`), or give intentionally side-by-side controls `.buttonStyle(.borderless)`/`.plain` (as `ProfileSelectionSheet.selectedProfileRow` does). macOS hosted tests cannot reproduce the iOS tap behavior, so `ProfileSearchResultRowsTests` pins the row structure via `_VariadicView`, and `ProfileJourneyTests` covers the tap on-device.

## Shared components and conventions

| Use | Not | Why |
|---|---|---|
| `StarRating(stars:gold:style:)` (`Design/StarRating.swift`; web `star_white`/`star_gold` in `Resources/Stars.xcassets`; 6 → five gold; `.inline` 14 pt or `.mini` web `MiniStars` circles) | SF Symbol `star`/`star.fill` | Operator rule (2026-09-28): stars use the game's own artwork everywhere |
| `InstrumentSectionHeader(_:title:size:)` (`Features/Profile/InstrumentSectionHeader.swift`, web `InstrumentHeader` SM 36 pt / MD 48 pt) **above** the card it titles | Instrument icon + name inside a glass card | Operator rule (2026-09-28): instrument headers sit outside containers |
| `ServiceStatusView(ServiceIssue(error), title:)` (`.title2`/`.body`, heading trait, opaque ≥44pt Retry, scrolls at large text, freeze countdown) | `ContentUnavailableView` or a bare message for service errors | iOS 26.5's system view failed Dynamic Type audits; one vocabulary for freeze/offline/syncing |
| `.refreshable` on the loaded List only | on an error `ScrollView` | Replacing an active refresh source can strand a spinner |
| Explicit scaled `frame` inside shared badges | SwiftUI `padding` inside the fixed score badge | Padding caused an iPad split-view layout loop ([score-accuracy](../../controls/score-accuracy/ipados.md)) |
| `InstrumentSelector` (`Design/InstrumentSelector.swift`, rules in Core `InstrumentSelection`; [instrument-selector](../../controls/instrument-selector/ios.md)) | A `Picker`/menu of instrument names | Operator batch 6.36: the web's selector with all its modes, everywhere the web uses it |
| `PurpleActionLabel` (`Features/Leaderboards/PurpleActionButton.swift`) for every "View full leaderboard" / "View all …" | Per-screen purple surfaces | Operator batch 6.29/7.6: one purple button |
| `RankingRowSurface` (48 pt material row card, web `purpleHighlight` player row; glass until issue #295) for every leaderboard row | A card around rows, or a purple stroke only | Operator batch 7.4: one leaderboard design (web `entryRow`) |
| Page-level gate: spinner until the page's reads settle, then `festivalFadeIn(isLoaded:index:)` (Profile `ProfileExtrasLoader`, Song Detail `SongDetailPreloader`, `LeaderboardsPreloader`) | Cards popping in one by one | Operator batch 6.41 (web `useLoadPhase`) |
| Accessibility IDs from the `product.json` registry | Ad-hoc IDs | `tools/verify_product.py` checks the registry |

Code style: DocC `///` with parameters/returns, `// MARK: -` regions, clarifying comments only.

## Text colour rule (operator rule, 2026-09-28)

**Text is white everywhere.** Use `FestivalText.primary` (`FestivalDesign/FestivalText.swift`) for titles, values, stat-tile captions, row subtitles (artist names, "N songs together"), descriptions, and empty-state or status messages. Only HIG de-emphasis uses `FestivalText.deemphasized` (muted blue-grey, ≥4.5:1 on app and card backgrounds but **fails over bright artwork** ([fluent.md](../../design/fluent.md)), so only inside opaque cards, sheets or lists): timestamps and dates, chart axis labels, text-field placeholders, and decorative glyphs (disclosure chevrons, search magnifier, clear buttons). `FestivalText.disabled` is for inactive controls. Do not use `.secondary`/`.tertiary`/`.gray` or raw `BrandTokens.textSecondary`/`textMuted` for text in feature code. Semantic colours (gold, status green/red, accent blue) are unaffected. `FestivalTextTests` pins white and the de-emphasis contrast.

Status countdowns, `FestivalSectionHeader` subtitles and the tab-accessory Search button stay primary because they can sit over artwork. Status (2026-09-28, Lane AP): applied to Profile, Statistics, Rivals, Compete (foreground only), Suggestions, Bands, Notifications, Search, `Common` and `Design`. Songs, Song Detail, Shop, Leaderboards/Song Leaderboard, Settings, First Run and What's New still use raw `BrandTokens.text*` and need the same sweep by their owning lanes.

## New content fades in as it loads (operator rule, 2026-09-28)

Loaded content never pops in: apply `.festivalFadeIn(isLoaded:)` (`Common/FadeInOnLoad.swift`) to the view that replaces a spinner, and `.festivalFadeIn(isLoaded:index:)` to list rows and card stacks. It ports the web's `fadeInUp` (opacity 0 → 1 while rising 12 pt, 400 ms CSS `ease-out`, `FADE_DURATION`) and `staggerDelay` ((index + 1) × 125 ms; items past the first ~8 appear instantly; same values as Android and Windows). The fade plays once per view lifetime, is instant under system or in-app Reduce Motion, and is disabled in hosted snapshots (`\.festivalFadeInEnabled`, set by `NativeHostedRoot`). Put it on the loaded content, never on a container that also holds the spinner (the content is invisible until `isLoaded`). Applied to Suggestions, Profile/Statistics, Rivals, Compete, Bands, Player Bands and Notifications; other lanes adopt it on their pages. `festivalFadeInOnAppear()` (Lane W4) is the same as `festivalFadeIn(isLoaded: true)`.

**Only load-time content fades (issue #30).** A lazy container (`LazyVStack`, `LazyVGrid`, `List`) builds rows as they scroll near the screen and rebuilds them after they scroll away, so a per-view fade would replay on scroll. Each page therefore limits fading to what is visible when it opens:

- Scroll pages with lazy sections (Song Detail, Leaderboards, Player Profile, Shop) apply `.festivalFadeInScope()` to the content directly inside the `ScrollView`. `FestivalFadeInScope` records the content's resting offset in the `.scrollView` space and closes once it moves more than 4 pt; after that, newly built `festivalFadeIn` views appear instantly. A fade that is already running finishes. Don't use the scope on appending feeds.
- `List` pages stagger only until the rows settle: `FadeStagger.index(_:settled:)` plus a `.task(id:)` that calls `FadeStagger.settle` (Songs, Solo Leaderboard, Notifications, Global Search, Player Bands).
- Suggestions fades each newly loaded batch: `SuggestionsViewModel.batchGeneration`/`latestBatchIds` and `FadeStagger.batchIndexes` stagger the newest batch in display order until it settles. Earlier cards never fade again.
- Eager (`VStack`) pages build everything at load, so they need nothing extra. `ios_sim.py drive` keeps the background still and so turns Song Detail/Shop/Solo fades off; add the Debug-only `FST_DEBUG_KEEP_FADES=1` to record them.

## Publication changes refresh in place (issue #304)

A new score publication never pops a stack or shows a "returned to Songs" notice. The visible page runs the load-transition R3 phases (`PublicationRefreshTransition`): content out 300 ms, spinner in 150 ms and held at least 400 ms and until the page has prepared for the new generation, spinner out 500 ms, then the rebuilt page fades in, like the web `PublicationBoundary` with `useLoadPhase` timings. Preparation (for example re-reading the route's song) starts only once the old content is hidden, so a fading page never draws new data. Under system or in-app Reduce Motion every fade is an instant swap and the 400 ms hold stays. HIG: `apple-hig/references/hig/progress-indicators.md` ("Perform automatic content updates regularly; don't make people initiate every update"), `hig/accessibility.md` (Reduce Motion) and `hig/loading.md`.

- **Live updates:** `PublicationLiveConnection` (`App/`) keeps one anonymous `URLSessionWebSocketTask` per process on `/api/ws?publicationId=N` while any scene is active; `PublicationLiveUpdates.run` (FestivalCore) re-reads `/api/publication` on connect and on `publication_changed`, reconnecting with 1 s → 30 s backoff. It sends nothing ([service safety](../service-safety.md)). Disabled for loopback fixture origins (Debug `FST_LIVE_PUBLICATION_UPDATES=1/0` overrides). With the override on, the mock (no `/api/ws`) still drives it: each reconnect round re-reads `/api/publication`, so `testLiveRolloverKeepsVoiceOverOnDetail` sees an advance with no user action; other fixture tests change generations through Settings → Check Publication.
- **Boundary:** `Common/PublicationRefreshBoundary` keys its content with a generation (`PublicationRefreshTransition`, FestivalCore), so the rebuilt page cannot draw rows from the old publication. Hidden old content stays mounted, without hit testing or accessibility, so the navigation title and toolbar persist. `AppRouteDestination` wraps every pushed page (iPhone stacks, iPad trailing pane, Mac stacks); song routes re-resolve their `Song` against the new catalogue first (`RouteSongRefresh`). The Suggestions, Leaderboards, Compete, Rivals, Statistics and Shop roots use `.refreshesOnPublication(session:)`. Songs already runs its own `FestivalReloadGate` (issue #71) and Settings must keep its publication-check status, so neither is wrapped.
- **VoiceOver (load-transition R9):** hiding the old content would drop a VoiceOver focus inside it. Just before hiding it, `Common/PublicationFocusProbe` (an inert `UIView` behind the page) reads `UIAccessibility.focusedElement(using: .notificationVoiceOver)` and `PublicationRefreshFocus.Location` (FestivalCore) decides whether that element is inside the page: the page is on screen (appeared), nothing is presented over its view controller, the element is not in another view hierarchy (its accessibility containers lead to a view outside the page controller's view) and its frame's centre lies in the page's screen frame (so the tab bar, navigation bar and toolbar never count). Only then does the boundary show a page anchor, a clear 44 pt heading overlay (`fst.publication.page-anchor`) whose label is the page title and whose value is "Loading new scores", and move focus there with `@AccessibilityFocusState`, and back after the rebuild unless the reader moved elsewhere during the spinner. Otherwise focus is left alone and one on-screen page posts an `AccessibilityNotification.Announcement("Loading new scores")` per publication (`PublicationRefreshAnnouncements`; a page that claims focus for the same publication cancels it). macOS exposes no VoiceOver cursor to apps, so the Mac always announces and never moves focus. Debug `FST_UI_TEST_PAGE_ANCHOR=inside|outside` simulates the focus location for XCUITest, which cannot run VoiceOver; under `outside` the announcing boundary also shows a 1 pt `fst.publication.announced` marker (value: the revision), because XCUITest cannot hear announcements and a slow simulator query can miss the ~1 s spinner. The anchor label comes from `festivalNavigationTitle(_:)` (`Common/PageTitle.swift`), which sets `navigationTitle` and the `FestivalPageTitleKey` preference; guard `load-transition/apple-page-title` keeps pages inside the boundary on it.

## Loading indicators (operator rule)

Every spinner is `Common/FestivalLoadingView` (white, **no visible title/subtitle**; spoken label only). Never `ProgressView("…")` with text. Determinate progress bars (e.g. Paths image download) are exempt.

## Performance

Measured with [`tools/apple_perf.py`](../../../tools/apple_perf.py) (live SFentonX, Mac window 1280×820, FST iPad Pro 11" simulator). Rules that keep the numbers down:

- **Continuous decoration runs on Core Animation, never in SwiftUI.** A SwiftUI animation, `TimelineView` or `phaseAnimator` that never ends re-renders the window's graph every display frame (on the Mac, a NSHostingView layout per frame). The carousel (`CarouselSlotLayer`, 30 fps discrete keyframes), the Shop row border and Song Detail breathe (`ShopPulseLayer`, one wall-clock phase `ShopPulseClock` for every pulse, 30 fps) marquee scrolling (`MarqueeTrackLayer`, a bitmap of the text) and the first-run demo glow (`FirstRunGlowLayer`: a shadow-only layer on the surface's outline, `FirstRunGlowShape`, whose shadow opacity 0.12 → 0.55 and radius 3 → 10 pt ease and reverse every 1.1 s; group children need the group's duration or they stop after 0.25 s) are render-server animations; the app does no work per frame. HIG motion (`apple-hig` `distilled/motion.md`): purposeful, honours Reduce Motion, which all three still do.
- **Still states draw with SwiftUI** (Mac still carousel slot, paused pulses, fitting or paused marquees) so `ImageRenderer` captures keep their pixels; platform views do not render there.
- **Mac dimming:** AppKit composites a translucent black layer about twice as bright as SwiftUI's `colorMultiply`, so the Mac multiplies cover pixels once per cover (`DimmedArtwork`). iOS keeps the black layer (unchanged).
- **Rows must not lay out twice.** No `@State` written from geometry or preferences for every row: `MarqueeText` measures with `MarqueeFitLayout` and only overflowing text flips one Bool. A platform view per row is expensive in a `List`; create one only where needed (overflowing marquees, animating Shop rows). `ViewThatFits` costs about as much as the old double layout.
- **Fewer views per row:** status chips are pre-drawn bitmaps (`SongStatusChipImages`); a custom `Layout` with icon-only children returns nil from `explicitAlignment` (the default re-measures every child per parent alignment query).
- **No formatter construction in bodies:** use `ISO8601Parsing` (cached `ISO8601DateFormatter`s).

### Methodology

| Command | Measures |
|---|---|
| `apple_perf.py build mac\|ipad [--configuration Release] [--probe]` | `--probe` = Release optimization with the `DEBUG` condition (own DerivedData), so the Debug overrides and stall monitor run on optimized code. True Release ignores `FST_DEBUG_*` and opens on the persisted page (the first-run sheet over Songs on this Mac) |
| `apple_perf.py mac\|ipad --tab songs` | Process CPU (`ps` time delta, one core = 100%) in 2 s windows over 20 s after a 20 s settle; the Mac window must be uncovered (occlusion pauses everything) |
| `… --stress` | `FST_DEBUG_SONGS_SCROLL_STRESS` (6 rounds of animated section jumps) with `MainThreadStallMonitor`; counts units ≥ 100 ms between the pass's `marks` |
| `mac … --trace 'Time Profiler' --top 30` (or `'SwiftUI'`, `'Animation Hitches'`; xctrace cannot attach to simulator apps here) | `xctrace record --attach` for `--duration`; with `--stress` it covers the pass. `--top` lists leaf and first-app-frame symbols |

### Last measured (2026-10-02)

Before = `a64b8fae`/`301adecf`, after = this lane's commits; CPU is the mean of the 2 s windows.

| Measure | Before | After |
|---|---|---|
| Mac Songs idle CPU, Debug / Release probe | 57.7% / 59.9% | **0.6% / 0.6%** |
| Mac Leaderboards / Statistics / Item Shop idle, probe | 39.5% / 37.4% / 18.3% | 0.7% / 0.7% / 0.7% |
| Mac true Release (first-run Song Info sheet over Songs) | 38.9% | 14.3% (the sheet's `repeatForever` shadow glow) |
| Mac Songs scroll stress, units ≥ 100 ms (worst), Debug | 62 (526 ms) | 22–23 (376–436 ms) |
| Mac Songs scroll stress, probe | 68 (631 ms) | 13–29 (293–420 ms) |
| iPad Songs idle CPU, Debug / probe | 3.1% / 2.4% | 4.3% / 1.0% (iPad already used the Core Animation carousel; noise ±3%) |
| iPad Songs scroll stress, Debug / probe | 38 (714 ms) / 39 (717 ms) | 40 (378 ms) / 37 (446 ms) |

**Far jumps teleport (Lane A11Y, 2026-10-04).** A programmatic jump further than one screenful of rows (`ListJump.isFar`: row distance > viewport ÷ 56 pt) scrolls instantly behind a 70 ms fade-out / 160 ms fade-in (`ListJumpFade`, opacity read only by `ListJumpFadeEffect`, so the screen body does not re-render), then scrolls once more after 50 ms to land on built rows; an animated far scroll built every row it passed (~25 per jump). Near jumps still animate. The stress pass uses the same rule (`songs.stress.teleport` counts 36 of its 60 jumps); `FST_DEBUG_SONGS_SCROLL_STRESS=animated` restores all-animated jumps for same-binary A/B (`apple_perf.py --env` now overrides the stress defaults). Section-index and Quick Links jumps were already instant (no fade, operator batch 7); the Songs reorder-to-top jump is now explicitly instant.

| Debug `--stress`, units ≥ 100 ms (worst) / main-thread s / rows built | Animated far jumps | Teleported far jumps |
|---|---|---|
| iPad Pro 11" sim (2 runs each; before = this lane's base build) | 33–37 (438–462 ms) / 14.6–15.5 / 1419–1463 | **8–9 (149–299 ms) / 7.0–7.3 / 526–547** |
| iPhone 17 Pro sim, same binary A/B, 2 interleaved pairs | 34–39 (423–427 ms) / 13.9–15.5 / 1014–1159 | **3–4 (120 ms) / 6.0–6.2 / 313–315** |
| Mac 1280×820, same binary A/B, 2 interleaved pairs | 76–79 (418–455 ms) / 22.2 / 2589–2637 | **23–26 (432–483 ms) / 14.5–14.9 / 1474–1555** |

- The remaining iPad units are ~110–150 ms: an instant jump still builds the destination screen (~10–14 rows × ~10 ms). Cheaper rows are the next lever.
- The Mac's worst unit (~450 ms) is the same in both modes (not a jump), and its teleports still build ~3× the iPad's rows (`NSTableView` lays out more around the target). Earlier Mac stress numbers included launch work: the window's first one-column Songs list, replaced once the width is measured, recorded the pass's start mark before its cancelled task stopped (fixed: the pass checks cancellation after its 3 s wait).

iPad scroll stalls (Lane IPAD2, 2026-10-03): **not iPad-specific.** The stall log now lists the events counted during each long unit (`Stall.counts`) and the main-thread CPU at the pass's marks (`cpuMarks`; `apple_perf.py` prints `main_cpu_s` and `rows_built`). Every stall ≥ 100 ms in the pass is Songs rows being built (`songs.row`, ~10 per 100 ms); no root, split, detail or artwork work appears, and the iPad stress runs in portrait with no detail column. The iPhone 17 Pro simulator gives the same picture: 39 units, 1316 rows, 12.6 ms main-thread CPU per row, against the iPad's 32–43 units, 1150–1420 rows, 12–14.5 ms per row. Per-row CPU with one part removed (same build, flags since removed): plain card instead of Liquid Glass `glassEffect` 9.2 ms (about −27%), no invisible `ListDetailLink` 10.8 ms (−15%); fade, hover, auto-select, context menu, chips, artwork and marquee were each within noise. Measured while other lanes loaded the host (load average 20–190 on 10 cores), so wall-clock stall counts varied by ±6 between identical runs; compare `main_cpu_s` per row. Open (operator/design): the row glass is the largest single cost; the only lever is a cheaper card surface or fewer rows built per animated jump (the stress pass's jumps build ~25 rows each; real `jumpToSection` jumps are instant). Rows already built by scrolling now skip the fade modifier (`festivalFadeIn(staggerIndex:)`) and one-stack rows carry no auto-select geometry observer; neither moved the numbers measurably.

Songs row card (Lane CARD, 2026-10-03): the per-row Liquid Glass card became a standard material tuned to the same look ([liquid-glass.md § Material card](../../design/apple/liquid-glass.md#material-card)). Same-session `--stress` runs, main-thread ms per row built (`main_cpu_s` / `rows_built`), host load average 20–250:

| Target | Glass card | Material card | Stalls ≥ 100 ms (worst) |
|---|---|---|---|
| Mac Release probe, same binary (A/B switch), 3 interleaved pairs | 7.7–8.1 (mean 7.9) | 7.2–7.4 (7.3), −8% | 19–29 (297–339 ms) → 11–14 (271–327 ms) |
| iPad Pro 11" sim, Debug, separate builds (5 / 6 runs) | 11.4–12.0 (median 11.6) | 9.1–10.3 (9.9), −15% | ~38 → ~37 (worst 423–520 → 392–433 ms) |
| iPhone 17 Pro sim, Debug, separate builds (3 / 5 runs) | 12.1–13.5 (13.4) | 10.7–13.5 (11.9), −11% | ~39 → ~39 |

- On the Mac, a trace of the glass build spent 8.3% of main-thread samples under `Glass*` frames (`GlassEffectContextDisplayList`, `GlassContainerPositionModifier`, `GlassEntryModifier`, `SDFLayer`); the material build 0.6% under any material or backdrop frame.
- **Structure matters more than the effect:** material, tint and rim as one `background(_:in:)` each cost the same as the material alone (iPad 8.6–8.7 ms per row in one session); the same layers in a nested `.background { shape.fill(…).background(material, …) }` plus a gradient overlay view cost 11.4 (glass 12.2).
- iOS stall counts did not move with the cheaper card: each animated far jump built ~25 rows (25 × ~10 ms > 100 ms). Fewer rows per jump was the lever: see far jumps above.
- With `FST_DEBUG_ROW_CARD_AB` set, Debug rows also read the switch (up to ~1 ms more per row on the iOS sims); compare A/B runs only with each other.
- Other row costs on the Mac trace: `MarqueeFitLayout.sizeThatFits` 3.1% (the title and subtitle text measurement itself), `SongsScreen.songLink` 0.9%, chips 0.7%; none is a cheap win without changing the row layout.

Every card and custom control on the material card (issue #291, 2026-10-04): same-binary A/B (`FST_DEBUG_ROW_CARD_AB`) on the iPad Pro 11" sim, Debug, `apple_perf.py ipad --stress --env FST_DEBUG_PAGE_SCROLL_STRESS=1` (6 rounds of animated bottom↔top scrolls, `Common/PageScrollStress.swift`), main-thread CPU between the pass's marks (`main_cpu_s`), 2 interleaved runs each, host load average 20–200:

| Page | Glass cards | Material cards | Stalls ≥ 100 ms |
|---|---|---|---|
| Leaderboards (`--tab leaderboards`) | 14.1, 14.1 s | 4.1, 3.8 s (−72%) | 28, 26 → 0, 0 |
| Statistics / Profile (`--route statistics`) | 10.1, 10.6 s | 9.4, 5.8 s (−26%, noisy) | 26, 26 → 24, 3 |
| Settings (`--tab settings`) | 3.0, 3.0 s | 2.3, 1.9 s (−32%) | 0 → 0 |

- On iPad, `--tab statistics` leaves Songs on screen; use `--route statistics`. The Mac was not measured: its Debug app shares the bundle ID (and defaults) with a long-running Release instance on the host.

First-run sheet (Lane IPAD2, 2026-10-03, iPad Debug, sheet open on its first slide): Leaderboards 4.1% → 0.0%, Statistics ("Select This Player" pill glowing) 2.6% → 0.0%. The glow still breathes (`~/FestivalShowcase/native-ipad/2/first-run-glow-{rest,lit}.png`) and rests under Reduce Motion or off screen.
