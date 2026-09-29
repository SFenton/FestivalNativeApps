# Artwork background — Apple notes

> **What:** the SwiftUI shared backdrop, its transitions, caches, policies and tests. **Read when:** changing `apple/Sources/FestivalUI/Background` (Lane B) or adding a page that needs a background. Behavior: [spec.md](spec.md).

## Architecture (shared backdrop, Wave 1)

Pages only declare intent: `.festivalBackground(.carousel, session:, visible:)` or `.festivalBackground(.song(song.albumArt), session:)`. Never construct `ArtworkBackground` in a page.

- **One model per session.** `FestivalSession+Artwork.swift` gives each session one `FestivalBackgroundCoordinator` holding page registrations, the single `ArtworkCarouselEngine` and the song cover (`SongOverlay`/`ExitingOverlay`).
- **Which page wins.** Each modifier registers a token on `onAppear`, drops it on `onDisappear` and updates it when `mode`/`visible` change. The newest appeared, visible page wins (`FestivalBackgroundCoordinator.winner`). Regaining `visible` counts as a fresh appearance, so a pop (Songs `isVisible` flips back) wins before the detail disappears. With no registrations the last mode stays, which covers transient gaps.
- **Driver.** `FestivalBackgroundHost` (rendered once by `FestivalRootView`) draws nothing. It loads the catalogue if no page has (`loadArtworkCatalogIfNeeded`: 0.8 s grace for Songs, then exponential backoff), runs the carousel engine under `ArtworkPlaybackPolicy` and turns the resolved mode into cover transitions.
- **Why pages draw mirrors.** The iPhone `TabView` keeps an opaque container above anything drawn behind it. This was measured: black even with `containerBackground(.clear, for: .navigation)` and with no `NavigationStack`. So each page draws `FestivalBackdropView`, a mirror of the shared, **timestamped** state. Every copy renders the same pixels at any instant: tab switches and pushes never restart or change the carousel, and pages stay opaque (no overlapping content mid-push, and it works on iOS 17 and macOS).
- **Rendering cost.** Carousel slots (`CarouselLayerView`) and song covers (`CoverLayerView`) jump to the timestamp-derived value on appear/timing change, then run implicit animations for the remainder (`CarouselMotionEffect` is a `GeometryEffect`; covers animate opacity only). There is no per-frame body re-evaluation, `TimelineView`, blur or layout during any transition.

## Song cover transition

Web source: `BackgroundImage.tsx` (song pages) fades its image in with `opacity 300ms ease` once loaded, over the still-running `AnimatedBackground`. Native matches that (operator, 2026-09-28: the earlier grow-out-of-the-tile zoom "goes against the seamless design" and was removed, with the tile-frame tracking it needed).

- Opening a song: the host decodes the cover (≤1,024 px) off the main actor, then the cover **fades in over the carousel** in 0.3 s on CSS `ease` (`cubic-bezier(0.25, 0.1, 0.25, 1)`, `BackdropEasing.cssEase`). It then holds still; ~0.35 s later the carousel pauses beneath it (loads and motion stop, position kept).
- Back to a carousel page (pop or tab switch): the cover fades out with the same curve while the carousel resumes where it paused. An exit that interrupts an entrance fades out from the opacity reached (`ExitingOverlay.from`); the leaving cover keeps its view identity (`CoverLayer.id`), so nothing restarts. Song → song replaces one cover with another (old beneath, fading out).
- Song → Song Leaderboard → Back keeps the same `.song(art)` mode, so the backdrop does not change at all.
- Reduce Motion: the root strips animations, so the cover cuts. Data saving or opaque presentation: brand surface only (no art, no overlay). Song without art, or failed art: brand surface (logged, never a substitute image).
- Debug: `FST_DEBUG_BACKGROUND_CYCLE=<seconds>` alternates carousel ↔ the first carousel cover, for `tools/ios_sim.py shot` frame sequences.

## Carousel engine (unchanged behaviour)

Ten six-second presets, five-second transition deadlines, one-second crossfades (the incoming slot fades in over the opaque outgoing one), one standby cover, paced failure recovery (three initial attempts, retry after the dwell, five failures per pool). Dim 0.7 (0.82 with Increase Contrast) is opaque colour multiplication on **opaque** art. Transparent source art still needs its own pixel check, and it may pop when the hidden slot is released. Policy combines system and in-app Reduce Motion/Transparency, Disable Animated Artwork, Low Power, scene activity and `NWPathMonitor` (constrained or unsatisfied path). Cache tiers: [architecture](../../platforms/apple/architecture.md).

## Performance (iPhone 17 Pro sim, iOS 26.5, `ps` %CPU of the app, 0.5 s samples)

| State | Before (per-page backgrounds) | Shared backdrop |
|---|---|---|
| Songs, carousel animating | ~4.5 % | ~4.4 % |
| Song cover held | n/a | **0 %** (carousel paused) |
| Cover transition | n/a | one ~0.5 s spike (cover decode) |

A first attempt that used a per-frame `TimelineView` for the carousel cost ~9 %, which is why it was replaced. Device frame pacing under a game load is still unmeasured.

## Tests

`FestivalBackgroundCoordinatorTests.swift`: winner rules, push/pop/tab sequences, sticky mode, cover lifecycle/settle, web fade timing (300 ms CSS `ease`), interrupted fades exiting from the current opacity with stable layer identity, `cubic-bezier` evaluation, pause/resume without jumps, one coordinator per session, independent catalogue load. `ArtworkBackgroundTests.swift` (standalone `ArtworkBackground` over the same engine/canvas): no-art, dim/contrast, Save Data, opaque pixels, 5/10/15 s deadlines, paced failure recovery, 404→valid. `ArtworkBackgroundPolicyTests.swift`: every suppression input. Device `testArtworkAnimationAndAccessibilityOverrides` and `art-*` scenarios: [fixtures](../../testing/fixtures.md).

Gotcha: the 16×16 grid samples the empty page behind Songs, and a saved Shop sort once put a card inside the crop. Visual tests pin Sort to Title per launch.

Open: under a page that passes no `visible` input (e.g. Shop → Song Detail), a cancelled interactive swipe-back briefly starts the fade to the carousel (the covered page's `onAppear` fires), then returns to the cover. Songs is immune because its `visible` input tracks the path. Other open items: hardware Low Data/Low Power toggles, device frame pacing, macOS GUI, iOS 17 runtime, Duo poses.
