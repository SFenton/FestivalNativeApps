# Native hosted snapshots (macOS host)

> **What:** rendering real AppKit-backed SwiftUI states inside `swift test`, without a simulator or the Mac app GUI, and proving each capture shows real content. **Read when:** adding a per-state UI snapshot test (UX-test phase), or judging how much hosted UX coverage is visual evidence.

Helpers: `apple/Tests/FestivalUITests/NativeHostedSnapshot.swift`; self-tests in `NativeHostedSnapshotTests.swift`.

| Helper | Use |
|---|---|
| `nativeHostedView(_:size:forceGlassFallback:)` | Host a screen. Forces the glass fallback (see root causes) and turns on the in-process accessibility tree |
| `nativeHostedWindow(_:size:)` | Offscreen, never-shown window; required for lazy `List` rows. Keep it alive through capture |
| `nativeHostedSettle(_:untilText:excluding:)` / `(_:until:)` | Wait for the **final** state (text present, loading text absent, or any predicate), then for two identical frames. Returns the capture; records an issue on timeout (20 s of the wait's own time (requested sleeps plus its own work), not wall-clock; every budget ×4 in a VM such as `apple-ci`) |
| `NativeHostedPollBudget` | The bound for a bespoke polling loop: `while !ready, !budget.isExhausted { try await budget.sleep(for:) }`. Charges the requested sleeps and the loop's own work, never the delay before a poll resumes |
| `assertRendersContent(_:image:minimumNonBackgroundFraction:minimumInkFraction:containing:notContaining:)` | Fail blank, spinner-only or wrong-state pages. Defaults: 1% non-background, 0.2% ink |
| `nativeHostedAccessibility(_:)` | Labels/titles/values/identifiers, walking accessibility children **and** AppKit subviews (List/Form cells) |
| `nativeHostedContent(_:)` | Non-background and ink fractions plus detected background |
| `nativeHostedControlPixels` / `nativeHostedStatusPixels` | State-specific colour checks (bright text, selected blue, gold/green/red fills) |
| `nativeHostedImage` / `nativeHostedPNG` | Raw capture; optional private PNG output |

## Recipe

1. Build a `FestivalSession` over an **in-memory transport** that rejects writes, privileged keys, selected-profile headers, wrong routes and mismatched publication pins (a throwing factory is fine for error states; never fall through to production). Rivals/Compete reads bypass `HTTPTransport`, so they use the loopback `RivalsMockService` (`tools/mock_service.py --port 0`). Use a separate `UserDefaults` suite via `.defaultAppStorage` and clean it up.
2. Apply `.preferredColorScheme(.dark)` and the app tint, then host with `nativeHostedView` (+ `nativeHostedWindow` for anything with a `List`). A standalone `Form` (e.g. Songs Sort) is the opposite: a window makes pickers look inactive, so render its content bare. Wrap a page whose rows are `NavigationLink`s in a `NavigationStack`, as the app does: outside one the rows are disabled, drawn at 50% opacity and slow to capture (see the settling rule).
3. **Never wait with `Task.sleep`.** Call `nativeHostedSettle(host, untilText: [final-state text], excluding: ["Loading…"])`. For a *loading*-state shot, capture synchronously right after `layoutSubtreeIfNeeded()`. See the settling rule below.
4. Assert with `assertRendersContent(host, image:, containing:, notContaining:)` on every full-page render counted as visual evidence, plus state-specific pixel checks where colour carries meaning. Bitmaps are at backing scale, never below 2× (`nativeHostedImage` upsamples 1× headless CI captures so stride-sampled thresholds match a Retina Mac); AppKit/ColorSync shifts token RGB slightly, so assert geometry, painted foreground and selected state, not exact token bytes.
5. Optional private captures: `FST_<AREA>_RENDER_OUT` (e.g. `FST_LEADERBOARDS_RENDER_OUT`) pointing at an **existing private** directory. Never commit screenshots, service payloads or game artwork.
6. AppKit `NSTextField` accepts a typed `controlTextDidChange` to drive the real 250 ms search task; `NSSegmentedControl` can switch scopes. SwiftUI result buttons expose no `NSButton`, so viewed/select/focus flows still need device tests.

## Settling rule (parallel runs)

Under `swift test --parallel` every hosted test shares one main actor, which runs ~99% busy for most of the ~3-minute bundle. A wait that takes 3 s alone can take 80 s there, and a `.task` load moves just as slowly. So:

- **Wait on a condition, never on time.** The condition is the final text, an accessibility identifier, a toolbar item, a transport's `requests(atLeast:)` or a `ManualTestClock` sleeper. Do not use a fixed sleep or a `clock.now < deadline` loop.
- **Bound every wait in poll time.** `nativeHostedSettle` and `NativeHostedPollBudget` charge the sleeps they request and their own work but not the delay before each poll resumes, so starvation stretches the wait instead of spending its budget, while an expensive loop still stops after about its bound. (A first version charged only the sleeps. On `apple-ci` a reveal loop that walked the accessibility tree for ~100 ms every 20 ms then ran for 22 minutes before it failed.) The bound is a hang guard: give it at least 20 s (60 s for a full page with many reads), never a tight value.
- **Keep each main-actor turn cheap**, because one slow capture delays every other test's turn. Profile with `sample <swiftpm-testing-helper pid>` during a full run. Usual causes are translucent layers (next table) and per-pixel `NSColor` loops.
- Serialize (`@Suite(.serialized)` / `@Test(.serialized, arguments:)`) only tests that share global state, such as `UserDefaults.standard` or process-wide caches. Serializing does not relieve the shared main actor.

| Cause (fixed 2026-10-06) | Symptom | Fix |
|---|---|---|
| Wall-clock readiness bounds (`nativeHostedSettle`'s, plus bespoke `deadline` loops) | `leaderboardsScreenShows{Spotlight{Footer…,FailureInline},UnrankedSpotlightText}` passed alone (3 s) but failed at 62–80 s against a 60 s bound in every full run, and on the base commit too. This blocked `lane_integrate.sh --test` | `NativeHostedPollBudget`: settle and the Mac-tree/reveal loops count their own time (sleeps plus work), not queueing delay |
| `LeaderboardsScreen` hosted without a `NavigationStack` | Its `NavigationLink` rows were disabled and drawn at 50% opacity. `cacheDisplay` composites each translucent layer through a full-size transparency layer, so ~150 rows cost **1.35 s of main actor per capture** (a plain page costs 2–9 ms) | The tests host the overview in a `NavigationStack`: 9 ms per capture, and the rows render as they do in the app |

Still heavy, by design: `bandBoardRowsFadeAbovePagerWithoutPlayerFooter` (BandRankings/SongBand without a stack, about 1 s per capture × 80 captures, `.serialized`). Its brightness thresholds are tuned for the dimmed rows, so moving it into a `NavigationStack` means re-measuring them. `selectedRowRevealFadesTheRowItReaches` measures mid-fade opacity, which is translucent on purpose.

## Why full pages captured blank (fixed 2026-09-28)

| Cause | Symptom | Fix |
|---|---|---|
| Any **tinted** Liquid Glass (`Glass.regular.tint`, i.e. every `festivalGlass(.card/.overlay)`) in the tree | The *whole* `NSHostingView` captured fully transparent through `cacheDisplay` **and** `CALayer.render(in:)`, window or not; untinted/shaped/interactive glass captures fine | `NativeHostedRoot` sets `\._accessibilityReduceTransparency` (the product's own Reduce Transparency fallback, same branch as Increase Contrast). The canary `hostedHarnessForcesGlassFallbackBecauseTintedGlassCapturesBlank` fails if AppKit ever fixes this |
| Fixed `Task.sleep` waits | ~200 `@MainActor` tests share one executor; a 300 ms sleep resumed seconds late, so captures showed spinners ("Loading Notifications", "Loading your rank") | `nativeHostedSettle` readiness predicates |
| Mac-sized readiness budgets on the `apple-ci` VM | A different test timed out on each saturated run (e.g. 4 s alone, 66 s against a 60 s budget in the full bundle) | `nativeHostedReadinessBudget` scales every budget ×4 when `kern.hv_vmm_present` is 1 |
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
- **`.toolbar` items need a toolbar-bridged window.** `nativeHostedWindow`'s bare borderless window never gets an `NSToolbar` (`window.toolbar` reads `nil`), and `nativeHostedAccessibility` starts from the content view, outside the toolbar. Host the page in an `NSHostingController` with `sceneBridgingOptions = [.toolbars, .title]` as the content of a titled, offscreen, never-shown `NSWindow`: SwiftUI then fills `window.toolbar.items` (labels, tooltips, `NSSearchToolbarItem` for `.searchable`) within a few run-loop turns. `macTreeToolbarItemsAreLabelled` (`MacAccessibilityTreeTests.swift`) does this for the Mac window. Toolbar *actions* (Cancel/Apply/Close tapped) and sheet toolbars still need a device journey.

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
