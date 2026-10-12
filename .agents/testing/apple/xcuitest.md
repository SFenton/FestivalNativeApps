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

On the weekly release branch ([release train](../../workflow/release-machine.md#release-train); the machine dispatches it), `apple-ci` runs a short list of iPhone journeys on a simulator (step "iPhone simulator journeys", `JOURNEYS` in [`apple-ci.yml`](../../../.github/workflows/apple-ci.yml)), then a list of iPad journeys (step "iPad simulator journeys", its own `JOURNEYS`). Use it for evidence the macOS-hosted suite cannot give: real Dynamic Type sizes (macOS has no Dynamic Type, [accessibility](accessibility.md)), `performAccessibilityAudit`, and the production chrome's accessibility order (the navigation bar and tab-bar accessory are system containers a hosted view cannot reproduce, e.g. the account buttons, `page-tools-and-nav-chrome` R17).

- The step starts `tools/mock_service.py --large-catalogue` on the default port 8765, creates one throwaway runner simulator with `ios_sim.py ci-device` (an iPhone 17 Pro on the runner's newest iOS runtime) and runs `ios_sim.py uitest --device <UDID> --fail-on-skip`.
- The iPad step shuts the iPhone simulator down, creates a second throwaway simulator with `ios_sim.py ci-device --type "iPad Pro 11-inch (M5)"` (`CI_IPAD_DEVICE_TYPE`, the local `ipad` alias's model; `ci-device` names each type separately so it never reuses the iPhone) and runs the iPhone step's UI-test build there (`uitest --app phone`; every iOS target is device family 1,2), so it adds no second build. List a journey there when its iPad form (landscape, the split, a wider window) is the evidence; an iPhone-only form (a portrait-only phone skips landscape) stays off the iPhone list. The What's New AX5 journeys (#434) are the first: iPhone portrait, iPad portrait and landscape. The iPad's first batch includes its cold first test launch (about 8 minutes on the runner), so its batch limit is 1500 s, not 900 s: a 900 s limit timed out a passing journey at 988 s (#544). The feedback sent/failure journeys (#565) run on both: the page-sized iPad sheet with its library pane must close before the alert, as the iPhone form does. The Paths no-gesture journeys (`PathsDismissAccessibilityJourneyTests` default and AX5, #445) run on both: the iPhone sheet and the iPad full-window cover (#368), whose swipe is `PullDownToDismiss`; its Duo folded/unfolded forms, at Large and AX5, stay on the iPhone list ([accessibility](accessibility.md#paths-without-gestures-96-backfilled-by-445)). The Songs section-jump AX XXXL journey (#451) runs on both too (the iPad's taller rail and wider List land differently); its folded-Duo form is iPhone-only. The Search title AX5 journey (#450, `GlobalSearchAccessibilityJourneyTests`) runs on both, with its Duo-folded form on the iPhone list. It checks that #100's **Search** title stays readable and is read first while the field is active. The board footer fade AX5 journey (#473) is another; its hardware-keyboard form runs after the list as its own batch with `uitest --a11y full-keyboard-access` (an `--a11y` setting applies to a whole invocation, so a selector needing one gets its own `uitest` line, not a `JOURNEYS` entry). **iPhone Duo in CI** runs as the `DebugDuoWindow` simulation on the CI iPhone (`FST_DEBUG_DUO_WINDOW_REMOTE=1`, `FST_DEBUG_DUO_WINDOW=folded|open`; e.g. `…AtLargestTextDuoFolded`), because the runner offers no iPhone Duo device type; wait for the `fst.shell.debug.duo-window` readout before asserting. Run the real Duo device type locally with `uitest --device duo`. Duo selectors skip unless the idiom is phone, so they go on the iPhone list only.
- `--fail-on-skip` fails a batch in which any test skipped or none ran: a journey that cannot find its fixture skips, and an all-skipped batch would otherwise pass.
- Add a journey only if it passes alone against that fixture, needs no other `mock_service.py` flags, and takes about two minutes or less. Launch-environment flags the fixture serves are fine (a fixture player such as `FST_DEBUG_PROFILE=fixture-player-1:…`, a text size, a route); a journey needing another fixture mode needs its own mock and step. A runtime `/__fixture__/…` control on the default listener is fine too when it is bounded and released in `tearDown` (`PathsSwitchAccessibilityJourneyTests` holds Paths reads with `hold-paths` to audit the sheet mid-switch, #430). Run it first with `ios_sim.py uitest --fail-on-skip` locally (point it at your own mock with `TEST_RUNNER_<VAR>` when another lane holds 8765).
- **Plain-fixture step** (formerly Score History; #385, [accessibility](accessibility.md#score-history-at-ax5)): `ScoreHistoryAccessibilityJourneyTests` needs the plain fixture (the large catalogue pushes `fixture-pulse` below the fold), so it has its own step (between the iPhone and iPad steps, so the iPad boots once; release-branch dispatch only, like them) and mock on an OS-assigned port (`mock_service.py --port 0`, passed as `TEST_RUNNER_FST_FIXTURE_URL`). It runs the iPad UI-test bundle (`uitest --app ipad`): `HISTORY_JOURNEYS` on the iPhone, which is then shut down, and `HISTORY_IPAD_JOURNEYS` on a throwaway iPad from `ci-device --type "iPad Pro 11-inch (M5)"` (the same simulator the iPad step then reuses). Between them, `PLAIN_JOURNEYS` runs iPhone-bundle journeys that need `fixture-pulse` and `fixture-orbit` on screen (`uitest --app phone` on the same iPhone, 1500 s limit): `SongsJourneyTests/testPlayerScoreFilterSettingsPauseAndDeselectScope` (#615, the Filter sheet's score checks under Filter Invalid Scores) failed its first row wait in the large catalogue and passes here. Such a journey reads its origin from `SongsUITestSupport.fixtureURL`, never a literal 8765. It takes about 4½ minutes on a Mac (longer than the two-minute rule, accepted because it is that change's only on-device label, state and touch-height evidence). The job's timeout is 160 minutes: the iPhone step's 30-minute limit (#388), the second bundle's build and both iPad runs, the iPad step's 1500 s cold first batch (#544), plus the plain-fixture iPhone run (#615) and the unpinned profile-notice run (#446).
- **Unpinned-fixture step** (#446, the region #97 changed): `ProfileNoticeTextSizeJourneyTests` needs a read that proves no publication, so the player profile shows its `.unverified` pause notice. Its step runs right after the iPhone step, on the same iPhone and UI-test build and before the plain-fixture step shuts that iPhone down, with its own `mock_service.py --port 18446 --unpinned` (passed as `TEST_RUNNER_FST_PROFILE_NOTICE_FIXTURE_URL`); its `UNPINNED_JOURNEYS` block lists the journey. It is the only on-device Dynamic Type evidence for the notice: the hosted `PlayerProfileAccessibilityTests` run on macOS, which has no Dynamic Type.
- `tools/tests/test_apple_ci_journeys.py` (contracts) fails when any step's `JOURNEYS`, `PLAIN_JOURNEYS`, `HISTORY_JOURNEYS`, `HISTORY_IPAD_JOURNEYS` or `UNPINNED_JOURNEYS` selector, or a Songs Filter leg's matrix `journeys` selector, names no test method in its bundle, or when the Score History journeys leave either device, so a renamed journey cannot silently leave CI.
- Run it locally on `--device iphone27` too: the runner's newest runtime is iOS 27, and the audit there flags what 26.5 did not (#388: the accessory bell badge's capped Dynamic Type).
- `ci-device` refuses to run outside GitHub Actions: on a shared Mac, use a `DEVICES` alias and never create or change simulators.
- An AX5 journey measures glyph growth and truncation with the shared `RecognizedText` (`apple/Apps/iOSUITests/RecognizedText.swift`: Vision line height and whole-label read-back from the element's own capture, `minimumGrowth` 1.35), never a copy; `WhatsNewAccessibilityJourneyTests` and `CompeteAccessibilityJourneyTests` (#407) use it. A journey file that runs in the iPad product too lists it in `project.yml`'s iPad sources.
- A reading-order walk over `app.snapshot()` stops at a button: XCUITest lists some texts inside a SwiftUI button (a ranking row's "#1") as children, but VoiceOver reads the button as one element (#407).
- A failed run uploads the `.xcresult` bundles and the mock's log as the `apple-ci-journeys` artifact.
- **Songs Filter journeys (#432).** A second job, `songs-filter-journeys`, runs in parallel with the build job, on release-branch dispatches only like the build job's journeys (release train), as a matrix of three legs, each on its own runner with the plain fixture (the build job's iPad step uses `--app phone` and the large catalogue; this leg builds the iPad target, which compiles the journey and the keyboard journey) (`tools/mock_service.py`, port 8765): `iphone` (iPhone 17 Pro), `ipad` (iPad Pro 11-inch (M5), `--app ipad`, plus the hardware-keyboard `SongsFilterKeyboardJourneyTests`) and `duo-folded` (iPhone Duo, `--pose folded`; a fresh Duo boots folded, and on a runner `ios_sim.py` gives each pose screenshot 180 s and three tries, because the first one after boot took over 30 s there, `pose_screenshot_policy`). Each runs `SongsFilterAccessibilityJourneyTests`' three methods (the Duo leg also the bottom Filter Songs field's `SongsBottomFilterFieldJourneyTests`, #474: the simulated Duo window on a plain iPhone keeps the iPhone's tab bar over the bottom field, so field journeys need the real folded Duo) with `--fail-on-skip --batch-size 1 --timeout 2400 --retries 1`: the AX5 method alone took 10 min on a Mac, far over the build job's budget. `--retries 1` reruns a batch only when a test failed (exit 65; never a timeout or setup error), because the runner's Duo timed out an XCUITest query ("Timed out while evaluating UI query") and a dismissal wait at different points of a passing journey; a deterministic failure fails both attempts, the log marks a pass on retry `FLAKY`, and the failed attempt's result bundle is kept in the artifact. `ci-device --type` names each simulator for its type (`FST CI <type>`); the Duo type needs the iOS 27.1 runtime, so its leg runs `xcodebuild -downloadPlatform iOS` when `ci-device` finds none. Each leg has 120 min: the runner ran these journeys 2–4× slower than a Mac (the iPhone leg's three methods took 26 min there). A failed or timed-out leg uploads `apple-ci-songs-filter-<leg>`. Pull requests and `master` pushes skip the legs (release train); run them locally with `ios_sim.py uitest` before pushing a change to the sheet.
- **The required check.** The release machine merges once `apple-ci` is green, so `apple-ci` is a small gate job (`needs: [build, songs-filter-journeys]`, `if: always()`) that passes only when the build job succeeded and the legs succeeded on a release dispatch, or were skipped on a pull request or `master` push; the build job is named "apple-ci build, unit tests and iPhone/iPad journeys". Add another long journey as a matrix leg or a new job in that `needs` list, never as a job the gate does not wait for. `tools/tests/test_apple_ci_journeys.py` checks that each leg's selectors exist in the target its leg builds (`FestivalMobileIPadUITests` sources from `project.yml` for `ipad`) that the legs run only on dispatch, that the gate needs every job, and runs the gate's script against each outcome.
- A failed run uploads the `.xcresult` bundles of both UI-test bundles and both mocks' logs as the `apple-ci-journeys` artifact.
- Size every wait and settle pause of a CI journey with `FestivalApp.budget(_:)`, which scales it ×4 in a VM (`kern.hv_vmm_present`, as the hosted `nativeHostedReadinessBudget`). The runner animates several times slower than a Mac: a Notifications sheet took over 5 s to leave the hierarchy there (#394), failing a Mac-sized wait. A runner audit of a long list can also exceed XCTest's own deadline ("Audit failed to complete in time", `com.apple.xcode.xctest.accessibilityAudit` -56, #388 Songs scroll-away; or `XCTFuture` 1000 "Timed out while running accessibility audit", #429 first-run guide at AX5): retry that error once, after clearing what the handler collected (`SongsUITestSupport.performAuditRetryingTimeout`), and fail on any other.
- **An audit handler accepts only what a rule dims by design, on every OS version.** No `systemVersion` exemptions in a registered journey: the runner's runtime is not the Mac's. Accept contrast issues only for text under a scroll-edge fade band ([scroll-edge](../../patterns/scroll-edge.md) R2/R5) or behind bottom chrome, never on the element the journey tests (measure its rendered contrast before accepting an unattributed issue), and measure any other flagged text's rendered contrast (`SongsUITestSupport.assertHeaderContrast`). Precedents: `SongDetailJourneyTests` `auditSoloPage`, `SongsJourneyTests` `auditSectionTitlePage`, `SuggestionsAccessibilityJourneyTests` `auditRow` (row-scoped: every row text measured on its own).

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
| "No matches found for Element at index N" walking a list | `query.allElementsBoundByIndex` re-resolves the query for every element read, and a lazy `List` still recycling rows (after a scroll, or after an audit cycles text sizes) shrinks mid-walk (#572). Read a list's frames and labels from one snapshot with `FestivalApp.snapshotNodes(in:where:)`, and bind a row you act on to its identifier (`SongsUITestSupport.songsRows(in:limit:)`), never to its index |
| Evidence element "not found" after scrolling | Lazy lists drop and add repeats while scrolling: follow the target by position, not its reading-order ordinal; normalized app coordinates stay portrait in a landscape window, so drag in screen points from the window frame |
| An identifier on a split or plain stack replaces its rows' IDs | Put `.accessibilityElement(children: .contain)` before a container identifier (`fst.nav.list-detail`, `fst.suggestions.category.<key>`, #403); `testSongsShowsTwoPopulatedColumns` and `SuggestionsAccessibilityJourneyTests` find `fst.songs.row.*` / `fst.suggestions.row.*` inside |
| Page tool missing on an `FST_DEBUG_SONG` route (no tab-bar accessory) | The DEBUG push in `SongsScreen` adds `pageTrailingItems()` but not `pageToolsScope()`, so the pushed page's `festivalPageTool`s register under the hidden Songs root and never reach the accessory (#465). Reach page tools through a production push (`FestivalTabStack` destinations apply `pageToolsScope()`), not the debug route |
