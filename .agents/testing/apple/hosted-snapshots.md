# Native hosted snapshots (macOS host)

> **What:** rendering real AppKit-backed SwiftUI states inside `swift test`, without a simulator or the Mac app GUI, and proving each capture shows real content. **Read when:** adding a per-state UI snapshot test (UX-test phase), or judging how much hosted UX coverage is visual evidence.

Helpers: `apple/Tests/FestivalUITests/NativeHostedSnapshot.swift`; self-tests in `NativeHostedSnapshotTests.swift`.

| Helper | Use |
|---|---|
| `nativeHostedView(_:size:forceGlassFallback:)` | Host a screen. Forces the glass fallback (see root causes) and turns on the in-process accessibility tree |
| `nativeHostedWindow(_:size:)` | Offscreen, never-shown window; required for lazy `List` rows. Keep it alive through capture |
| `nativeHostedSettle(_:untilText:excluding:)` / `(_:until:)` | Wait for the **final** state (text present, loading text absent, or any predicate), then for two identical frames. Returns the capture; records an issue on timeout (20 s) |
| `assertRendersContent(_:image:minimumNonBackgroundFraction:minimumInkFraction:containing:notContaining:)` | Fail blank, spinner-only or wrong-state pages. Defaults: 1% non-background, 0.2% ink |
| `nativeHostedAccessibility(_:)` | Labels/titles/values/identifiers, walking accessibility children **and** AppKit subviews (List/Form cells) |
| `nativeHostedContent(_:)` | Non-background and ink fractions plus detected background |
| `nativeHostedControlPixels` / `nativeHostedStatusPixels` | State-specific colour checks (bright text, selected blue, gold/green/red fills) |
| `nativeHostedImage` / `nativeHostedPNG` | Raw capture; optional private PNG output |

## Recipe

1. Build a `FestivalSession` over an **in-memory transport** that rejects writes, privileged keys, selected-profile headers, wrong routes and mismatched publication pins (a throwing factory is fine for error states; never fall through to production). Rivals/Compete reads bypass `HTTPTransport`, so they use the loopback `RivalsMockService` (`tools/mock_service.py --port 0`). Use a separate `UserDefaults` suite via `.defaultAppStorage` and clean it up.
2. Apply `.preferredColorScheme(.dark)` and the app tint, then host with `nativeHostedView` (+ `nativeHostedWindow` for anything with a `List`). A standalone `Form` (e.g. Songs Sort) is the opposite: a window makes pickers look inactive, so render its content bare.
3. **Never wait with `Task.sleep`.** Call `nativeHostedSettle(host, untilText: [final-state text], excluding: ["Loading…"])`. For a *loading*-state shot, capture synchronously right after `layoutSubtreeIfNeeded()`.
4. Assert with `assertRendersContent(host, image:, containing:, notContaining:)` on every full-page render counted as visual evidence, plus state-specific pixel checks where colour carries meaning. Bitmaps are at backing scale (2×); AppKit/ColorSync shifts token RGB slightly, so assert geometry, painted foreground and selected state, not exact token bytes.
5. Optional private captures: `FST_<AREA>_RENDER_OUT` (e.g. `FST_LEADERBOARDS_RENDER_OUT`) pointing at an **existing private** directory. Never commit screenshots, service payloads or game artwork.
6. AppKit `NSTextField` accepts a typed `controlTextDidChange` to drive the real 250 ms search task; `NSSegmentedControl` can switch scopes. SwiftUI result buttons expose no `NSButton`, so viewed/select/focus flows still need device tests.

## Why full pages captured blank (fixed 2026-09-28)

| Cause | Symptom | Fix |
|---|---|---|
| Any **tinted** Liquid Glass (`Glass.regular.tint`, i.e. every `festivalGlass(.card/.overlay)`) in the tree | The *whole* `NSHostingView` captured fully transparent through `cacheDisplay` **and** `CALayer.render(in:)`, window or not; untinted/shaped/interactive glass captures fine | `NativeHostedRoot` sets `\._accessibilityReduceTransparency` (the product's own Reduce Transparency fallback, same branch as Increase Contrast). The canary `hostedHarnessForcesGlassFallbackBecauseTintedGlassCapturesBlank` fails if AppKit ever fixes this |
| Fixed `Task.sleep` waits | ~200 `@MainActor` tests share one executor; a 300 ms sleep resumed seconds late, so captures showed spinners ("Loading Notifications", "Loading your rank") | `nativeHostedSettle` readiness predicates |
| `#expect(image.width > 0)` as the only assertion | Neither problem failed a test | `assertRendersContent` |
| SwiftUI builds no accessibility nodes until an assistive client appears | `accessibilityChildren()` empty | `nativeHostedEnableAccessibility` sets `AXEnhancedUserInterface` on the in-process `NSApplication` (no TCC permission needed) |

Not causes: `NavigationStack`/`ScrollView` layout, lazy stacks (with a window), size proposals, or Metal layers. A plain `ScrollView` captured fine throughout.

## Pitfalls

- **Never use `ImageRenderer` output as evidence**: it paints yellow crossed placeholders for native `Form`, `Picker`, `TextField` and `List`, and a synchronous render of a `NavigationStack` with a prefilled path paints only the brand surface. (A genuinely gold Shop badge is not a placeholder.)
- Real Liquid Glass *appearance* is never hosted evidence; hosted pixels show the fallback surface. Glass appearance needs simulator/device screenshots.
- Keep hosted polling cheap: per-pixel `NSColor` loops (`colorAt`) cost ~0.2 s per wide capture and starve the shared main actor for every other test. Read raw bytes (`nativeHostedForEachSample`). Tests with wall-clock deadlines (countdowns, dwell timers) are the first to flake under that load.
- `tools/mock_service.py` detail routes only accept rival ids matching `[A-Za-z0-9]+`; a hyphenated id 404s, and the client's documented 404-as-empty mapping then renders "No Shared Songs" whatever the test meant. Use a hex fixture id.
- Page-level full renders: `LeaderboardsScreen` spotlight rows load per card; wait on the card under test, not on "no loading text anywhere".
- Artwork tests time retries from the view's start and enforce the five-request pool even when a busy host misses the transient three-request observation.
- Host pixels do not increase device coverage and are not macOS GUI, VoiceOver or focus evidence.

## Tests that execute views but are not visual evidence

- Find Rival's loading shot asserts only the painted sheet and query: a busy run can outlast the 250 ms debounce.
- Component tests using `ImageRenderer` (chips, pills, difficulty meter, artwork) assert layout/geometry, not native control rendering.

Fixed 2026-09-28 (Lane C): `RivalCommonSection.load()` (`Features/Rivals/RivalsScreen.swift`)
used `try?` per instrument read, so a 503 across every visible instrument silently
intersected an empty list and rendered `EmptyView()` instead of its `.failed`
`ServiceStatusInline` branch — the only Rivals/Compete section that hid its error
rather than showing it, unlike `RivalComboSection`/per-instrument sections'
try/catch. Now propagates the first read's error the same way. Regression:
`rivalsScreenRendersCommonAndComboSectionErrors` in `RivalsRenderTests.swift`
asserts "Common Rivals" reaches the accessibility tree during a 503 directly,
no longer wrapped in `withKnownIssue`.

Content-asserted full-page selector (test IDs are `FestivalUITests.<function>()`, so filter on function names, not files):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apple --filter 'leaderboardsScreen|fullRankingsScreen|bandRankingsScreen|soloLeaderboard|rivalsScreen|allRivalsScreen|rivalDetailScreen|rivalryScreen|findRivalSheet|competeScreen|notificationsSheet|playerHistoryScreen|licensesScreen|firstRun(Carousel|Settings)|drawer|rootProfileButton|settingsScreenRenders|playerProfileScreenRenders|hosted(Harness|Content|Accessibility|Settle)'
```
