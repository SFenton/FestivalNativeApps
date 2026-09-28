# Artwork background — Apple notes

> **What:** the SwiftUI shared backdrop, its transitions, caches, policies and tests. **Read when:** changing `apple/Sources/FestivalUI/Background` (Lane B) or adding a page that needs a background. Behavior: [spec.md](spec.md).

## Architecture (shared backdrop, Wave 1)

Pages only declare intent: `.festivalBackground(.carousel, session:, visible:)` or `.festivalBackground(.song(song.albumArt), session:)`. Never construct `ArtworkBackground` in a page.

- **One model per session.** `FestivalSession+Artwork.swift` gives each session one `FestivalBackgroundCoordinator` holding page registrations, the single `ArtworkCarouselEngine`, the song cover (`SongOverlay`/`ExitingOverlay`) and tile frames.
- **Which page wins.** Each modifier registers a token on `onAppear`, drops it on `onDisappear` and updates it when `mode`/`visible` change. The newest appeared, visible page wins (`FestivalBackgroundCoordinator.winner`). Regaining `visible` counts as a fresh appearance, so a pop (Songs `isVisible` flips back) wins before the detail disappears. With no registrations the last mode stays, which covers transient gaps.
- **Driver.** `FestivalBackgroundHost` (rendered once by `FestivalRootView`) draws nothing. It loads the catalogue if no page has (`loadArtworkCatalogIfNeeded`: 0.8 s grace for Songs, then exponential backoff), runs the carousel engine under `ArtworkPlaybackPolicy` and turns the resolved mode into cover transitions.
- **Why pages draw mirrors.** The iPhone `TabView` keeps an opaque container above anything drawn behind it. This was measured: black even with `containerBackground(.clear, for: .navigation)` and with no `NavigationStack`. So each page draws `FestivalBackdropView`, a mirror of the shared, **timestamped** state. Every copy renders the same pixels at any instant: tab switches and pushes never restart or change the carousel, and pages stay opaque (no overlapping content mid-push, and it works on iOS 17 and macOS).
- **Rendering cost.** Carousel slots (`CarouselLayerView`) jump to the timestamp-derived value on appear/timing change, then run implicit animations for the remainder (`CarouselMotionEffect` is a `GeometryEffect`). There is no per-frame body re-evaluation. Cover transitions use a `TimelineView` that exists only while a cover is present and ticks only while one animates.

## Song cover transition

- Opening a song: the host decodes the cover (≤1,024 px). If a list tile for that art was on a carousel page (`ArtworkTile` reports its global frame, non-observed, via `onGeometryChange`), the cover **zooms out of the tile** (0.55 s, undimmed→dimmed, rounded→square). Otherwise it **dissolves** in (0.5 s, slight settle and blur). It then holds still; ~0.6 s later the carousel pauses beneath it (its loads and motion stop, and its position is kept).
- Back to a carousel page (pop or tab switch): the cover dissolves away (0.45 s) while the carousel resumes where it paused.
- Reduce Motion: opacity-only fades, no zoom or blur. Data saving or opaque presentation: brand surface only (no art, no overlay). Song without art, or failed art: brand surface (logged, never a substitute image).
- Debug: `FST_DEBUG_BACKGROUND_CYCLE=<seconds>` alternates carousel ↔ the top visible tile's cover, for `tools/ios_sim.py shot` frame sequences.

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

`FestivalBackgroundCoordinatorTests.swift`: winner rules, push/pop/tab sequences, sticky mode, tile-origin lifetime, cover lifecycle/settle, eased progress, tile→full placement, pause/resume without jumps, one coordinator per session, independent catalogue load. `ArtworkBackgroundTests.swift` (standalone `ArtworkBackground` over the same engine/canvas): no-art, dim/contrast, Save Data, opaque pixels, 5/10/15 s deadlines, paced failure recovery, 404→valid. `ArtworkBackgroundPolicyTests.swift`: every suppression input. Device `testArtworkAnimationAndAccessibilityOverrides` and `art-*` scenarios: [fixtures](../../testing/fixtures.md).

Gotcha: the 16×16 grid samples the empty page behind Songs, and a saved Shop sort once put a card inside the crop. Visual tests pin Sort to Title per launch.

Open: under a page that passes no `visible` input (e.g. Shop → Song Detail), a cancelled interactive swipe-back briefly starts the dissolve to the carousel (the covered page's `onAppear` fires), then returns to the cover. Songs is immune because its `visible` input tracks the path. The zoom has no reverse "shrink into tile" on pop. Other open items: hardware Low Data/Low Power toggles, device frame pacing, macOS GUI, iOS 17 runtime, Duo poses.
