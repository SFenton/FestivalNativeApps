# Artwork background — Apple notes

> **What:** the SwiftUI backdrop implementation, caches, policies and tests. **Read when:** changing `apple/Sources/FestivalUI/Background` (Lane B). Behavior: [spec.md](spec.md).

## Implementation (partial)

- `ArtworkBackground.swift`: two stable compositor layers, the ten six-second presets, five-second transition-start deadlines and one-second overlapping crossfades on Songs, Settings and the no-profile Leaderboards overview. A standby cover loads during the current dwell; each layer keeps its own motion rather than being retargeted after a fade. Cancellation is checked before clearing, showing or staging after async work.
- Dim 0.7 (0.82 with Increase Contrast) is applied as opaque colour multiplication on **opaque** art to avoid translucent compositing; transparent source art still needs its own pixel check.
- Policy combines system + in-app Reduce Motion / Transparency, Disable Animated Artwork, Low Power Mode, scene visibility and `NWPathMonitor.isConstrained`; waits for a satisfied network path before fetching decoration. Data-saving or opaque presentation shows **neither images nor overlay**.
- `FestivalSession` reshuffles ≤100 catalogue paths only when source artwork changes. Backdrops downsample to ≤1,024 px. Cache tiers: [architecture](../../platforms/apple/architecture.md).
- Wave 1 (Lane B): one background hosted by the shell with no restart across tabs/pushes; Song Detail animates from the carousel to its own art ([PROGRESS.md](../../../PROGRESS.md)).

## Tests

`ArtworkBackgroundTests.swift` (no-art, dim/contrast, Save Data, opaque pixels, 5/10/15 s deadlines, paced failure recovery, 404→valid), `ArtworkBackgroundPolicyTests.swift` (every suppression input), device `testArtworkAnimationAndAccessibilityOverrides` (16×16 grid over the real six-second journey), `art-error`/`art-skip`/`art-white` scenarios ([fixtures](../../testing/fixtures.md)).

Gotcha: the 16×16 grid samples the empty page behind Songs; a saved Shop sort once put a grouped card inside the crop (opaque-state distance 574 > 100). Visual tests pin Sort to Title per launch instead of relaxing the threshold.

Open: hardware Low Data/Low Power toggles, frame pacing under load, macOS GUI, iOS 17, Duo poses.
