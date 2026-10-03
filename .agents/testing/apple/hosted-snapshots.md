# Native hosted snapshots (macOS host)

> **What:** rendering real AppKit-backed SwiftUI states inside `swift test`, without a simulator or the Mac app GUI, and proving each capture shows real content. **Read when:** adding a per-state UI snapshot test (UX-test phase), or judging how much hosted UX coverage is visual evidence.

Helpers: `apple/Tests/FestivalUITests/NativeHostedSnapshot.swift`; self-tests in `NativeHostedSnapshotTests.swift`.

| Helper | Use |
|---|---|
| `nativeHostedView(_:size:forceGlassFallback:)` | Host a screen. Forces the glass fallback (see root causes) and turns on the in-process accessibility tree |
| `nativeHostedWindow(_:size:)` | Offscreen, never-shown window; required for lazy `List` rows. Keep it alive through capture |
| `nativeHostedSettle(_:untilText:excluding:)` / `(_:until:)` | Wait for the **final** state (text present, loading text absent, or any predicate), then for two identical frames. Returns the capture; records an issue on timeout (20 s on a Mac; every budget ×4 in a VM such as `apple-ci`) |
| `assertRendersContent(_:image:minimumNonBackgroundFraction:minimumInkFraction:containing:notContaining:)` | Fail blank, spinner-only or wrong-state pages. Defaults: 1% non-background, 0.2% ink |
| `nativeHostedAccessibility(_:)` | Labels/titles/values/identifiers, walking accessibility children **and** AppKit subviews (List/Form cells) |
| `nativeHostedContent(_:)` | Non-background and ink fractions plus detected background |
| `nativeHostedControlPixels` / `nativeHostedStatusPixels` | State-specific colour checks (bright text, selected blue, gold/green/red fills) |
| `nativeHostedImage` / `nativeHostedPNG` | Raw capture; optional private PNG output |

## Recipe

1. Build a `FestivalSession` over an **in-memory transport** that rejects writes, privileged keys, selected-profile headers, wrong routes and mismatched publication pins (a throwing factory is fine for error states; never fall through to production). Rivals/Compete reads bypass `HTTPTransport`, so they use the loopback `RivalsMockService` (`tools/mock_service.py --port 0`). Use a separate `UserDefaults` suite via `.defaultAppStorage` and clean it up.
2. Apply `.preferredColorScheme(.dark)` and the app tint, then host with `nativeHostedView` (+ `nativeHostedWindow` for anything with a `List`). A standalone `Form` (e.g. Songs Sort) is the opposite: a window makes pickers look inactive, so render its content bare.
3. **Never wait with `Task.sleep`.** Call `nativeHostedSettle(host, untilText: [final-state text], excluding: ["Loading…"])`. For a *loading*-state shot, capture synchronously right after `layoutSubtreeIfNeeded()`.
4. Assert with `assertRendersContent(host, image:, containing:, notContaining:)` on every full-page render counted as visual evidence, plus state-specific pixel checks where colour carries meaning. Bitmaps are at backing scale, never below 2× (`nativeHostedImage` upsamples 1× headless CI captures so stride-sampled thresholds match a Retina Mac); AppKit/ColorSync shifts token RGB slightly, so assert geometry, painted foreground and selected state, not exact token bytes.
5. Optional private captures: `FST_<AREA>_RENDER_OUT` (e.g. `FST_LEADERBOARDS_RENDER_OUT`) pointing at an **existing private** directory. Never commit screenshots, service payloads or game artwork.
6. AppKit `NSTextField` accepts a typed `controlTextDidChange` to drive the real 250 ms search task; `NSSegmentedControl` can switch scopes. SwiftUI result buttons expose no `NSButton`, so viewed/select/focus flows still need device tests.

## Why full pages captured blank (fixed 2026-09-28)

| Cause | Symptom | Fix |
|---|---|---|
| Any **tinted** Liquid Glass (`Glass.regular.tint`, i.e. every `festivalGlass(.card/.overlay)`) in the tree | The *whole* `NSHostingView` captured fully transparent through `cacheDisplay` **and** `CALayer.render(in:)`, window or not; untinted/shaped/interactive glass captures fine | `NativeHostedRoot` sets `\._accessibilityReduceTransparency` (the product's own Reduce Transparency fallback, same branch as Increase Contrast). The canary `hostedHarnessForcesGlassFallbackBecauseTintedGlassCapturesBlank` fails if AppKit ever fixes this |
| Fixed `Task.sleep` waits | ~200 `@MainActor` tests share one executor; a 300 ms sleep resumed seconds late, so captures showed spinners ("Loading Notifications", "Loading your rank") | `nativeHostedSettle` readiness predicates |
| Mac-sized readiness budgets on the `apple-ci` VM | A different test timed out on each saturated run (e.g. 4 s alone, 66 s against a 60 s budget in the full bundle) | `nativeHostedReadinessBudget` scales every budget ×4 when `kern.hv_vmm_present` is 1 |
| Mac list/detail tests on the default 2.5 s `\.macListCollapseDelay` (2026-10-03) | On the saturated `apple-ci` VM Full Rankings rows arrived after the collapse; the page stayed one column and never auto-selected (`macFullRankingsAutoSelectsTopRankedPlayer`, `macListDetailDividerUsesRememberedWidth` hit the 240 s budget; locally they pass in < 1 s) | Every hosted `MacListDetailStack` test that waits for a split sets `.environment(\.macListCollapseDelay, .seconds(120))` |
| `#expect(image.width > 0)` as the only assertion | Neither problem failed a test | `assertRendersContent` |
| SwiftUI builds no accessibility nodes until an assistive client appears | `accessibilityChildren()` empty | `nativeHostedEnableAccessibility` sets `AXEnhancedUserInterface` on the in-process `NSApplication` (no TCC permission needed) |

Not causes: `NavigationStack`/`ScrollView` layout, lazy stacks (with a window), size proposals, or Metal layers. A plain `ScrollView` captured fine throughout.

## Pitfalls

- **Never use `ImageRenderer` output as evidence**: it paints yellow crossed placeholders for native `Form`, `Picker`, `TextField` and `List`, and a synchronous render of a `NavigationStack` with a prefilled path paints only the brand surface. (A genuinely gold Shop badge is not a placeholder.)
- Real Liquid Glass *appearance* is never hosted evidence; hosted pixels show the fallback surface. Glass appearance needs simulator/device screenshots.
- Keep hosted polling cheap: per-pixel `NSColor` loops (`colorAt`) cost ~0.2 s per wide capture and starve the shared main actor for every other test. Read raw bytes (`nativeHostedForEachSample`).
- **Never assert against wall-clock deadlines** (countdowns, dwell timers). A 1 s Retry-After countdown missed an 8 s deadline, and a 150 ms artwork dwell missed a 15 s ceiling, once page-settle polls loaded the shared main actor. Inject a clock instead: `ServiceStatusView`/`ServiceStatusInline` read `\.serviceRetryClock`; `ArtworkBackground(clock:)` and `ArtworkCarouselEngine.play(_:maxPixels:policy:clock:)` take one. Tests pass a `ManualTestClock` (`FestivalUITests/ManualTestClock.swift`), wait for events with no deadline (`sleepers(atLeast:)`, a transport's `requests(atLeast:)`, an `AsyncStream` of callbacks), check pacing as clock instants, then `advance(by:)`. Add `.timeLimit(.minutes(10))` only as a hang guard: a starved `@MainActor` test finishes near the end of the whole suite (these took 23–25 s of a 28 s run), so keep it far above suite wall time. Real-time visual fades still run on `Date`; wait for their frame without a ceiling.
- `tools/mock_service.py` detail routes only accept rival ids matching `[A-Za-z0-9]+`; a hyphenated id 404s, and the client's documented 404-as-empty mapping then renders "No Shared Songs" whatever the test meant. Use a hex fixture id.
- Page-level full renders: `LeaderboardsScreen` spotlight rows load per card; wait on the card under test, not on "no loading text anywhere".
- Artwork retry tests check the paced sleep's clock instant (one dwell after the view's first attempt) and the exact request count at each step. `artworkEngineStopsAfterPoolFailureBudget` awaits `play` returning to prove the five-failure pool stops.
- **Hosted CI (`apple-ci` on the GitHub `xcode-27` VM) differs from the Mac:** Light system appearance, 1× headless display, a paravirtual GPU and ~3 cores. `nativeHostedView`/`nativeHostedWindow` pin `.darkAqua` (AppKit controls follow the view's appearance, not `preferredColorScheme`); the tinted-glass canary is skipped when `kern.hv_vmm_present` is 1 because the VM composites the glass; and blocking reads (e.g. `RivalsMockService`'s ready line) must run on a Dispatch thread, never the Swift cooperative pool that the parallel render tests saturate. Failed runs upload every `FST_*_RENDER_OUT` capture as the `apple-ci-renders` artifact.
- Host pixels do not increase device coverage and are not macOS GUI, VoiceOver or focus evidence.

## Tests that execute views but are not visual evidence

- Find Rival's loading shot asserts only the painted sheet and query: a busy run can outlast the 250 ms debounce.
- Component tests using `ImageRenderer` (chips, pills, difficulty meter, artwork) assert layout/geometry, not native control rendering.
- **`.toolbar` items are not hosted evidence at all**, not even structurally: a `NavigationStack`'s `.cancellationAction`/`.confirmationAction` items attach to the window's `NSToolbar`, but `nativeHostedWindow`'s bare offscreen window never gets one (`window.toolbar` reads `nil` even after `nativeHostedImage`), and `nativeHostedAccessibility`'s walk starts from the content view, which a toolbar's items live outside of. Every sheet using semantic toolbar placements (`FindRivalSheet`, `ProfileSelectionSheet`, `SuggestionsFilterSheet`, `PlayerHistorySortSheet`, …) can only prove its Cancel/Apply/Close buttons exist and work via an XCUITest journey on-device; hosted tests can still cover the Form content and draft-state logic beneath the toolbar.

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
