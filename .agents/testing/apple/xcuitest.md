# XCUITest device journeys

> **What:** running device UI tests and the XCUITest pitfalls already paid for. **Read when:** the UX-test phase of a feature (UITests are frozen during Wave 1), or debugging a flaky journey.

## Running journeys

```bash
python3 tools/ios_sim.py uitest --only ShellJourneyTests --only LeaderboardsJourneyTests/testOne
```

Builds once (skipping if the compiled product's source hash is already current),
then runs the given `Class`/`Class/testMethod` selectors in bounded batches
(default 3 selectors per `xcodebuild test-without-building` call, `--timeout`
seconds each, 300 default), fully releasing `~/.fst-sim.lock` between batches
so other lanes queued on the shared simulator aren't starved by one long run
(the 5-minute lock-hold rule). Any journey file placed under
`apple/Apps/iOSUITests/` is picked up by the next build with no tool changes —
see `cmd_uitest`'s docstring in `tools/ios_sim.py` for the full contract.
`tools/ios_sim.py drive` runs one scripted `DriverTests/testDrive` step
sequence instead of a written `XCTestCase`, useful for ad hoc exploration
before writing a real journey.

## CI journeys

`apple-ci` runs a short list of iPhone journeys on a simulator (step "iPhone simulator journeys", `JOURNEYS` in [`apple-ci.yml`](../../../.github/workflows/apple-ci.yml)). Use it for evidence the macOS-hosted suite cannot give: real Dynamic Type sizes (macOS has no Dynamic Type, [accessibility](accessibility.md)), `performAccessibilityAudit`, and the production chrome's accessibility order (the navigation bar and tab-bar accessory are system containers a hosted view cannot reproduce, e.g. the account buttons, `page-tools-and-nav-chrome` R17).

- The step starts `tools/mock_service.py --large-catalogue` on the default port 8765, creates one throwaway runner simulator with `ios_sim.py ci-device` (an iPhone 17 Pro on the runner's newest iOS runtime) and runs `ios_sim.py uitest --device <UDID> --fail-on-skip`.
- `--fail-on-skip` fails a batch in which any test skipped or none ran: a journey that cannot find its fixture skips, and an all-skipped batch would otherwise pass.
- Add a journey only if it passes alone against that fixture, needs no other `mock_service.py` flags, and takes about two minutes or less. Launch-environment flags the fixture serves are fine (a fixture player such as `FST_DEBUG_PROFILE=fixture-player-1:…`, a text size, a route); a journey needing another fixture mode needs its own mock and step. Run it first with `ios_sim.py uitest --fail-on-skip` locally (point it at your own mock with `TEST_RUNNER_<VAR>` when another lane holds 8765).
- `tools/tests/test_apple_ci_journeys.py` (contracts) fails when a `JOURNEYS` selector in any simulator step names no test method, so a renamed journey cannot silently leave CI.
- `ci-device` refuses to run outside GitHub Actions: on a shared Mac, use a `DEVICES` alias and never create or change simulators.
- A failed run uploads the `.xcresult` bundles and the mock's log as the `apple-ci-journeys` artifact.
- **Rival Detail accessibility journeys** (#444, its own step and `JOURNEYS` list): `RivalDetailFrozenAccessibilityJourneyTests` needs selected-player fixtures (`fixture-riv-frozen`, `fixture-riv-503`), so the step starts its own mock on port 18944 (`TEST_RUNNER_FST_FIXTURE_URL`). It runs the same universal test build (`uitest --app phone`) on an iPhone 17 Pro, an iPad Pro 11-inch (M5) and an iPhone Duo, one at a time, and shuts each down after its run. The iPhone reuses the warm `FST CI iPhone` of the step above; the iPad and Duo come from `ci-device --type "<type>" --name "FST CI rivals <device>"`. A step with several device types names each device: `ci-device` reuses a device by name whatever its type. The runner image ships only the iOS 27.0 simulator runtime, which has no iPhone Duo device type: when `ci-device` finds no runtime for a device, the step runs `xcodebuild -downloadPlatform iOS` (the selected Xcode 27.1's runtime) once and retries, just before the Duo, so the iPhone steps keep the image's runtime. The runner is several times slower than a Mac host (each app launch takes minutes; with up to seven launches per device a device took ~15 min in run 37879210531 and the iPad hit `--timeout 900`), so the journeys launch the app once per state and text size (default, then AX5): the iPhone then took ~3 min and the iPad ~8 min (run 37886354524). The step gives each device `--timeout 1500` within the job's `timeout-minutes: 120`. Keep a journey's launches to the sizes it asserts: resolve a default-size audit's Dynamic Type flags on the test's own AX5 launch, not a relaunch. Measure a page only once it has settled: Rival Detail's cards stagger in (`load-transition`), and in run 37889575028 a row that already existed was still fading in and not hittable on the iPad, so `waitForRows` waits for the first row to be hittable and for two snapshots to agree on every row and View All frame (budgeted waits). The Duo runs folded: a new Duo boots folded and `--pose folded` checks it by screenshot, with no Device Hub. Add a journey to this step when it is the only test of an iPad or iPhone Duo size class.
- Size every wait and settle pause of a CI journey with `FestivalApp.budget(_:)`, which scales it ×4 in a VM (`kern.hv_vmm_present`, as the hosted `nativeHostedReadinessBudget`). The runner animates several times slower than a Mac: a Notifications sheet took over 5 s to leave the hierarchy there (#394), failing a Mac-sized wait.
- **An audit handler accepts only what a rule dims by design, on every OS version.** No `systemVersion` exemptions in a registered journey: the runner's runtime is not the Mac's. Accept contrast issues only for text under a scroll-edge fade band ([scroll-edge](../../patterns/scroll-edge.md) R2/R5) or behind bottom chrome, never on the element the journey tests (measure its rendered contrast before accepting an unattributed issue), and measure any other flagged text's rendered contrast (`SongsUITestSupport.assertHeaderContrast`). Precedents: `SongDetailJourneyTests` `auditSoloPage`, `SongsJourneyTests` `auditSectionTitlePage`.

### Shared launch helper (`FestivalApp.swift`, added 2026-09-28)

Every journey launches through `FestivalApp.makeApp(_:)` (build, don't launch)
or `FestivalApp.launch(_:)` (build and launch), never `XCUIApplication()`
directly — `tools/tests/test_launch_helper.py` fails if any other file under
`apple/Apps/iOSUITests/` constructs one. The helper always defaults
`FST_DEBUG_STILL_BACKGROUND=1`: more than one journey file (`SongsUITestSupport
.fixtureApp()`, `FestivalMobileUITests.fixtureApp()`, `SuggestionsJourneyTests
.fixtureApp()`) had forgotten it entirely, which is exactly the "app never
idles" failure mode below — a caller overrides it explicitly (a `String` value,
not the key's absence) when it genuinely needs animation, as `DriverTests.swift`
does to keep `ios_sim.py drive --animate`'s opt-out working.

### Journey hangs traced to a missing still-background flag (2026-09-28)

`SongsJourneyTests` and `SuggestionsJourneyTests` were reported hanging the
shared simulator's lock. Investigation found two contributing causes, both
now fixed:

1. The two files' fixture launchers never set `FST_DEBUG_STILL_BACKGROUND=1`
   at all (see the shared helper above — now impossible to omit).
2. `Design/MarqueeText.swift`'s forever-repeating scroll (then a `TimelineView`, now a `phaseAnimator`)
   (used by every Songs row and, since this lane's work, Song Detail's header
   and Suggestion category rows) checked `reduceMotion`/`isOnScreen`/
   `scenePhase` but never the app's own `DebugAnimationOverride.stillBackground`
   — so even with the flag set, any row whose title/artist/year overflowed its
   container kept a `TimelineView` ticking forever, the same "app never idles"
   failure already fixed once for the artwork background carousel and
   `FirstRunPulse`. Now gated the same way.

Re-running `SongsJourneyTests/testSelectedShopSortSongsRowsClearFloatingTab`
after this fix confirms it: the hang is gone (18.8s total test execution,
well inside budget), but the test now fails a real, separate assertion (a
Shop "leaving tomorrow" section never appears) that the hang had been
masking — filed as a follow-up (`fst.songs.shop-section.leaving-tomorrow`
never renders; possibly a date-relative `mock_service.py` fixture gone stale
against the real wall-clock date, possibly a genuine Shop grouping
regression — not yet root-caused).

`SettingsJourneyTests`' three tests were also skipped as "consistently hung
300s under heavy concurrent-lane load, inconclusive root cause." No
Settings-specific product bug was found on inspection (no `TimelineView`/
`repeatForever`/`Timer` anywhere in `Features/Settings/**` or
`FirstRunSettingsSection.swift`, unlike the `MarqueeText` cause above) or
reproduced via `ios_sim.py drive` against the live simulator (a plain load,
then a scroll-and-tap sequence, both completed in under 20s). Re-run
individually via `ios_sim.py uitest` after the shared-helper fix (Settings
doesn't use `MarqueeText`, so only that fix applied here), all three passed:
`testSongRowOrderReorderSheetOpensAndCloses` in 267.8s (cold build-for-testing),
`testResetAppSettingsRestoresChangedToggle` in 68.2s,
`testAccessibilityToggleSurvivesRelaunch` (full terminate+relaunch) in
281.8s — all three skips removed. Running two together in one 200s batch did
time out once during this investigation; the wide per-test spread (68s–282s)
under varying concurrent-lane load is consistent with the original hang
being contention, not a deterministic bug. Batch Settings tests with a
generous `--timeout` (300s+ per selector) rather than the 300s *total*
default when running more than one together.

### Retired: `tools/apple_native_matrix.py` (removed 2026-09-28)

The old serial two-device (iPhone+iPad) matrix runner assumed exactly one
canonical UI test source file (`FestivalMobileUITests.swift`) to discover,
count and hash every test method from. Lane U2's Wave 3 triage split that
monolith into per-feature journey files (`SongsJourneyTests.swift`,
`RivalsJourneyTests.swift`, …) under the same `apple/Apps/iOSUITests/`
directory, which the matrix runner never scanned — so by the time this was
noticed, its own tests were asserting stale counts/content against a file
that had shrunk from ~54 methods to ~13, and running it for real would have
silently omitted every migrated test from a "paired" coverage measurement.
No lane's actual work (see `PROGRESS.md`'s log) had called it since; only this
doc mentioned it. Confirmed unused elsewhere (`grep -rl apple_native_matrix`
matched only the tool, its test and this file) and deleted rather than
generalized to multi-file discovery, since `tools/ios_sim.py uitest` already
covers its real job today. A genuine iPhone+iPad **paired** `apple_xccov_gate.py`
measurement now means running `uitest`/`drive` once per device and feeding
both `.xcresult` bundles to the gate — no single combined command yet.

## Pitfalls

| Symptom | Rule |
|---|---|
| Test "passed" but new screenshot missing | A matching method name does not prove the new body ran; rely on the source-hash marker |
| Zero-test result from a green Xcode process | Treat as failure; clean only that product's DerivedData |
| Row query disappears after a swipe | Lists virtualize: query the stable `fst.songs.list`, not `CollectionView containing <row>` |
| Element `isHittable` but partly behind the tab | Assert the whole element/group frame lies inside the List viewport and above the system tab |
| Full swipes skip a narrow row | Use small in-list drags |
| Programmatic tap on an offscreen action stalls the main thread | Real swipe first, or place the action where it is visible (Song Detail's View Full sits above its rows for this reason) |
| Settings toggle "missing" | Settings keeps its Form scroll position across tabs: try the reverse swipe before failing |
| Saved Sort changes a visual fixture | Pin Sort to Title per launch via launch arguments; never erase the user's saved preference |
| Identity leaks between tests | Every `XCUIApplication` comes from the shared helper that sets `FST_UI_TEST_CLEAR_PROFILE=1`; only the explicit cold-relaunch test removes it |
| Notification seen-state leaks between runs | `FST_UI_TEST_CLEAR_PROFILE=1` also clears `NotificationSeenStore`; before that, any journey that closed `fixture-player-1`'s sheet hid the unread badge `NotificationsJourneyTests` asserts on every later run |
| iPad grouped-header frames span both panes | Measure visible text at the detail pane's X; focus bounds stay unverified |
| Main-thread hang after a split-view toggle | Sample the app PID; compare against a clean baseline worktree before blaming the test |
| Stall timings look bad only under XCUITest | Each element query snapshots the accessibility tree on the app's main thread (100–350 ms on Songs). Measure hangs with the Debug stall log while the runner idles: the app drives itself (`FST_DEBUG_SONGS_SCROLL_STRESS`) and the test reads the report ([Songs iOS](../../pages/songs/ios.md)) |
| iPad journey starts in a small window | iPadOS remembers resized windows across launches: `IPadShellJourneyTests` launches through `launchFilled` and `WindowResize.fill` in `tearDown`; driver scripts end with `fill` |
| iPhone Duo capture is black | `XCUIScreen.main` is the outer panel while the app runs on the inner display: pick the `XCUIScreen.screens` entry matching the window, and turn it by the page's own labels (Vision reads flipped text too). `XCUIApplication.screenshot()` is black there as well |
| iPhone Duo pose lost mid-run | Another lane's batch shuts the Duo down and it boots closed: `uitest --pose P --set-pose [--rotate right]` re-checks the pose inside every batch's lock hold; the audit JSON records the `window` |
| Green batch, no evidence | `FST_UITEST_KEEP_RESULTS=1` keeps a passing batch's `.xcresult` and log (an all-skipped or zero-test batch also exits 0) |
| Evidence element "not found" after scrolling | Lazy lists drop and add repeats while scrolling: follow the target by position, not its reading-order ordinal; normalized app coordinates stay portrait in a landscape window, so drag in screen points from the window frame |
| iPad identifier on a split replaces its rows' IDs | Put `.accessibilityElement(children: .contain)` before a container identifier (`fst.nav.list-detail`); `testSongsShowsTwoPopulatedColumns` asserts a `fst.songs.row.*` is findable inside the split |
