# Artwork background — Apple notes

> **What:** the SwiftUI shared backdrop, its transitions, caches, policies and tests. **Read when:** changing `apple/Sources/FestivalUI/Background` (Lane B) or adding a page that needs a background. Behavior: [spec.md](spec.md).

## Architecture (shared backdrop, Wave 1)

Pages only declare intent: `.festivalBackground(.carousel, session:, visible:)` or `.festivalBackground(.song(song.albumArt), session:)`. Never construct `ArtworkBackground` in a page.

- **One model per session.** `FestivalSession+Artwork.swift` gives each session one `FestivalBackgroundCoordinator` holding page registrations, the single `ArtworkCarouselEngine` and the song cover (`SongOverlay`/`ExitingOverlay`).
- **Which page wins.** Each modifier registers a token on `onAppear`, drops it on `onDisappear` and updates it when `mode`/`visible` change. The newest appeared, visible page wins (`FestivalBackgroundCoordinator.winner`). Regaining `visible` counts as a fresh appearance, so a pop (Songs `isVisible` flips back) wins before the detail disappears. With no registrations the last mode stays, which covers transient gaps.
- **Driver.** `FestivalBackgroundHost` (rendered once by `FestivalRootView`) draws nothing. It loads the catalogue if no page has (`loadArtworkCatalogIfNeeded`: 0.8 s grace for Songs, then exponential backoff), runs the carousel engine under `ArtworkPlaybackPolicy` and turns the resolved mode into cover transitions.
- **Why pages draw mirrors.** The iPhone `TabView` keeps an opaque container above anything drawn behind it. This was measured: black even with `containerBackground(.clear, for: .navigation)` and with no `NavigationStack`. So each page draws `FestivalBackdropView`, a mirror of the shared, **timestamped** state. Every copy renders the same pixels at any instant: tab switches and pushes never restart or change the carousel, and pages stay opaque (no overlapping content mid-push, and it works on iOS 17 and macOS).
- **Rendering cost.** On iOS each carousel slot is a Core Animation layer tree (`CarouselSlotLayer` in `CarouselSlotAnimation.swift`): the pure `CarouselSlotPlan` derives the pose/opacity at the shared timestamp, then one discrete keyframe animation per slot runs in the render server at `CarouselSlotPlan.preferredFramesPerSecond` (30) with `preferredFrameRateRange` 15…30. SwiftUI never runs a per-frame transaction for the backdrop. macOS keeps the SwiftUI `CarouselLayerView` (`CarouselMotionEffect` `GeometryEffect`). Song covers (`CoverLayerView`) animate opacity only. There is no `TimelineView`, blur or layout during any transition.
- **Covered by a sheet.** `.pausesFestivalBackdrop()` (applied by `festivalSheet` and the first-run sheet) counts presented sheets in the process-wide `FestivalSheetCoverage`; while any is up the host policy treats the carousel as not visible, so motion and loads pause and resume at the same position on dismiss. It is process-wide because sheets do not reliably inherit presenter environment; on iPad multi-window one window's sheet pauses every window's (decorative) backdrop.

## Song cover transition

Web source: `BackgroundImage.tsx` (song pages) fades its image in with `opacity 300ms ease` once loaded, over the still-running `AnimatedBackground`. Native matches that (operator, 2026-09-28: the earlier grow-out-of-the-tile zoom "goes against the seamless design" and was removed, with the tile-frame tracking it needed).

- Opening a song: the host decodes the cover (≤1,024 px) off the main actor, then the cover **fades in over the carousel** in 0.3 s on CSS `ease` (`cubic-bezier(0.25, 0.1, 0.25, 1)`, `BackdropEasing.cssEase`). It then holds still; ~0.35 s later the carousel pauses beneath it (loads and motion stop, position kept).
- Back to a carousel page (pop or tab switch): the cover fades out with the same curve while the carousel resumes where it paused. An exit that interrupts an entrance fades out from the opacity reached (`ExitingOverlay.from`); the leaving cover keeps its view identity (`CoverLayer.id`), so nothing restarts. Song → song replaces one cover with another (old beneath, fading out).
- Song → Song Leaderboard → Back keeps the same `.song(art)` mode, so the backdrop does not change at all.
- Reduce Motion: the root strips animations, so the cover cuts. Data saving or opaque presentation: brand surface only (no art, no overlay). Song without art, or failed art: brand surface (logged, never a substitute image).
- Debug: `FST_DEBUG_BACKGROUND_CYCLE=<seconds>` alternates carousel ↔ the first carousel cover, for `tools/ios_sim.py shot` frame sequences.

## Carousel engine (unchanged behaviour)

Ten six-second presets, five-second transition deadlines, one-second crossfades (the incoming slot fades in over the opaque outgoing one), one standby cover, paced failure recovery (three initial attempts, retry after the dwell, five failures per pool). Dim 0.7 (0.82 with Increase Contrast) is opaque colour multiplication on **opaque** art. Transparent source art still needs its own pixel check, and it may pop when the hidden slot is released. Policy combines system and in-app Reduce Motion/Transparency, Disable Animated Artwork, Low Power, scene activity and `NWPathMonitor` (constrained or unsatisfied path). Cache tiers: [architecture](../../platforms/apple/architecture.md).

## Power and frame budget (issue #28)

Cause of the "hot in first run / Settings, stuttery Suggestions" report: the SwiftUI-animated slot zoom/pan never idles, and with `CADisableMinimumFrameDurationOnPhone` (kept: owner's 120 Hz choice) it ran a SwiftUI transaction plus a full-screen recomposite and Liquid Glass re-blur up to 120 times a second, even under the first-run sheet. Rules now:

- Decorative backdrop motion is render-server only and capped at 30 fps; never drive it from a SwiftUI animation, `TimelineView` or per-frame state on iOS.
- Anything behind a sheet pauses (`pausesFestivalBackdrop`); first-run demo pulses run only on the visible slide (`firstRunSlideActive`, [first-run notes](../first-run/ios.md)).
- The simulator composites at 60 Hz and ignores `preferredFrameRateRange`, so it cannot show the 120 → 30 Hz saving; measure that on a ProMotion device (Instruments Animation Hitches / Core Animation FPS).

Last measured (iPhone 17 Pro sim, iOS 26.5, 15 s idle, `ps` CPU of the app / simulator `backboardd`): Settings 6.6 % / 25.6 % → 0.6 % / 24.6 %; first-run sheet 3.9 % / 26.1 % → 0 % / 0 %; Suggestions 4.0 % / 23.4 % → 0.8 % / 25.5 %; `FST_DEBUG_STILL_BACKGROUND=1` is ~0 / 0 everywhere. The remaining render-server load is the 30 fps backdrop recomposite (discrete keyframes: 22 % vs 29.5 % for a continuous Core Animation curve on the sim). A per-frame `TimelineView` carousel once cost ~9 % app CPU, which is why it was replaced.

## Tests

`CarouselSlotAnimationTests.swift`: Core Animation slot pose matches `CarouselMotionEffect`, plans join mid-flight/paused/finished/off-screen, keyframes, sheet coverage, first-run pulse policy. `FestivalBackgroundCoordinatorTests.swift`: winner rules, push/pop/tab sequences, sticky mode, cover lifecycle/settle, web fade timing (300 ms CSS `ease`), interrupted fades exiting from the current opacity with stable layer identity, `cubic-bezier` evaluation, pause/resume without jumps, one coordinator per session, independent catalogue load. `ArtworkBackgroundTests.swift` (standalone `ArtworkBackground` over the same engine/canvas): no-art, dim/contrast, Save Data, opaque pixels, 5/10/15 s deadlines, paced failure recovery, 404→valid. `ArtworkBackgroundPolicyTests.swift`: every suppression input. Device `testArtworkAnimationAndAccessibilityOverrides` and `art-*` scenarios: [fixtures](../../testing/fixtures.md).

Gotcha: the 16×16 grid samples the empty page behind Songs, and a saved Shop sort once put a card inside the crop. Visual tests pin Sort to Title per launch.

Open: under a page that passes no `visible` input (e.g. Shop → Song Detail), a cancelled interactive swipe-back briefly starts the fade to the carousel (the covered page's `onAppear` fires), then returns to the cover. Songs is immune because its `visible` input tracks the path. Other open items: hardware Low Data/Low Power toggles, device frame pacing and power on a ProMotion iPhone, macOS GUI, iOS 17 runtime, Duo poses.
