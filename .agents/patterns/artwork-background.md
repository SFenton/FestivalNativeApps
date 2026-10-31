# Artwork background

> **What:** the shared decorative album-art backdrop and its load recovery. **Read when:** changing carousel or song artwork, motion, retry pacing or artwork caches.

Status: **current**. Provenance: existing [artwork-background control](../controls/artwork-background/spec.md), registered in #623.

## Intent

Every page shares one dimmed decorative backdrop. A transient read failure must not permanently disable the carousel or a song's still cover. Reduced motion changes motion, not whether artwork can load.

## Web source (behavior reference)

`FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx` (`AnimatedBackground`) owns shuffled covers, dwell, crossfade, motion presets, dimming and visibility policy. `FortniteFestivalWeb/src/components/page/BackgroundImage.tsx` owns the song's static artwork. Native load pacing and bounded caches follow the existing control spec rather than browser caching.

## Rules

1. **R1. One canonical host.** Shell consumers share the same carousel state across tabs, navigation layouts and splits. No feature-local carousel. A split's band stays clear over that backdrop ([split-panes](split-panes.md) R3).
2. **R2. Preserve the control's motion and dim.** At most 100 distinct shuffled covers, five-second dwell, one-second crossfade, six-second zoom/pan using the web's ten presets, scale at most 1.18 and translation at most 18 logical units. Dim only loaded art by 0.7 black: a missing or failed cover leaves the undimmed brand surface. Keep a successfully drawn outgoing cover until its successor loads.
3. **R3. Respect accessibility and visibility.** Artwork is decorative, noninteractive and absent from the screen-reader reading order. Reduce Motion and Disable Animated Artwork show a still cover; Data Saver shows neither artwork nor dim. Pause rotation, preloading and retries when inactive or covered by a modal. Read system changes live.
4. **R4. Song pages focus the shared backdrop.** Song Detail and song leaderboards push the song's static, dimmed cover through the canonical platform focus mechanism. Each destination owns and releases its focus ([song-leaderboard-header](song-leaderboard-header.md) R4), including a split's trailing page.
5. **R5. Failure is not an empty catalogue.** Report failed catalogue reads and recover on a later successful read without an app restart. Use capped service backoff and honour Retry-After. Failed covers are logged, skipped or retried under the existing control's five-failure pool budget and three-attempt/five-second pacing; still or focused artwork must not rely on the animation timer to retry. Never substitute fake successful imagery.
6. **R6. Artwork is ephemeral.** Use the shared bounded in-process cache, never disk persistence or bundled third-party artwork. On a known newer publication, invalidate the old pool, decoded cache, rendered layers and failure budget even when cover URLs are identical.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Pool, motion, dim and recovery | `apple/Sources/FestivalUI/Background/ArtworkBackground.swift` `ArtworkCarouselEngine`, `ArtworkBackground` | `android/app/src/main/java/com/festivalscoretracker/android/presentation/BackgroundController.kt` `BackgroundController`, `BackgroundPolicy`, `CoverFailurePacer`; `android/app/src/main/java/com/festivalscoretracker/android/ui/background/ArtworkBackground.kt` `ArtworkBackground` | `windows/Festival.Core/Domain/ArtworkCarousel.cs` `ArtworkCarousel`; `windows/Festival.App/Controls/ArtworkBackground.cs` `ArtworkBackground` |
| Focused song cover | `apple/Sources/FestivalUI/Background/FestivalBackgroundCoordinator.swift` `FestivalBackgroundCoordinator` (UIKit: `apple/Sources/FestivalUI/UIKitPort/Background/UKBackgroundRegistration.swift` `UKBackgroundRegistration`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/background/SongCoverBackdrop.kt` `SongCoverBackdrop` | `windows/Festival.App/Controls/ArtworkBackground.cs` `ArtworkBackground` |

**UIKit port (iOS/iPadOS, 2026-10-31).** The same coordinator, engine and policy types, hosted once per window instead of mirrored per page: `apple/Sources/FestivalUI/UIKitPort/Background/UKBackgroundView.swift` `UKBackgroundView` (installed under the tab container by `UKRootViewController`; `CarouselSlotView` slots plus `UKCoverLayerView` Core Animation fades, no display link), driven by `UKBackgroundHost` (policy, sheet coverage, scene and Low Data/Power state). Pages declare their mode with `UKBackgroundRegistration` (`viewWillAppear` / `viewDidDisappear`, `.song(art)` for Song Detail and song leaderboards; trailing split panes pass `registers: false`); sheets pause the backdrop with `UKSheetCoverageToken`; thumbnails are `UKArtworkTileView`. Shared logic (`ArtworkPlaybackPolicy.resolve`, `BackdropPresentation`, `FestivalBackgroundCoordinator.present`) lives beside the SwiftUI types. Debug: `FST_DEBUG_BACKGROUND_PROBE=1` publishes `fst.debug.backgroundProbe` (mode, slot, plays) for `UKBackgroundJourneyTests`.

Android: `ArtworkBackground` starts the catalogue watcher only while resumed, uncovered and outside Data Saver. `BackgroundController` follows `FestivalApi.publicationChanges` and clears the singleton Coil memory cache on a newer generation through `AppContainer`. Publication-keyed render state resets failed and outgoing layers even if every URL stayed the same. The shared service backoff paces catalogue retries; a still/focused cover gets a five-second retry deadline without enabling motion. Successful pools do not poll or reshuffle on resume. Coil preloads one cover ahead and cancels that request when playback pauses.

Material 3 Compose guidance (`material-3`, `references/layout-and-responsive.md`): "Use `enableEdgeToEdge()` on your `Activity` ... when you draw behind the system bars." The native edge-to-edge host is retained. Accessibility guidance: normal text needs 4.5:1 contrast; art-only dimming and the existing content surfaces remain unchanged.

## Consumers and tests

- Android: all shell tabs (Songs, Suggestions, Compete, Leaderboards, Rivals, Statistics, Item Shop, Settings), bottom bar/rail/drawer layouts and on-demand splits; Song Detail, solo song leaderboard and band song leaderboard through `SongCoverBackdrop`. First-run demos use the same host, paused while their modal is open.
- Android regression tests: `BackgroundRecoveryTest` (initial failure, Retry-After, cancellation and publication catch-up), `ArtworkBackgroundUiTest` (drawn recovery, still/focused failures, Data Saver and same-URL publication reset), `SongCoverBackdropTest` (focus ownership), and connected `journeys/ArtworkRecoveryAccessibilityJourneyTest` (loaded synthetic covers, 100%/200% text, unchanged TalkBack order, reduced motion and Data Saver; ATF).

## Known debt

- Apple and Windows catalogue/publication recovery are not certified by the Android #623 change. Their independent implementations remain unchanged; this worker's evidence is Android-only.
