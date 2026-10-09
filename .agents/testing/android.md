# Android testing

> **What:** Android coverage, test layout, connected-test, accessibility and CI rules. **Read when:** writing or running Android tests. Architecture, tooling and the device matrix: [platforms/android.md](../platforms/android.md).

- Host (JVM) and instrumented tests together target **95% logic / 90% UI lines**. Android Gradle [coverage reports](https://developer.android.com/studio/test/coverage-report) feed JaCoCo; `tools/coverage_gate.py` merges host and device hits per line.
- Control-state screenshots, navigation, accessibility and real-device evidence are separate from line coverage.
- Use the [mock service](fixtures.md), fixture-only transports and emulator host loopback `10.0.2.2`; never send a production POST. Installed-PWA comparison uses `tools/android/pwa.py`; retain findings in [pwa-reference/](pwa-reference/README.md).

## Test layout

| Kind | Where | Runs on |
|---|---|---|
| JVM unit | `android/app/src/test/.../{core,data,presentation}` | `testDebugUnitTest` |
| Whole-shell Compose UI | `android/app/src/test/.../ui/ShellUiTest.kt` | Robolectric SDK 34 with `w411dp-h891dp` and `w1280dp-h800dp` |
| Instrumented | `android/app/src/androidTest` (real-shell Compose journeys, shared `src/test/.../testing/` fixtures) | `device.py test <class> --avd <AVD> [--posture half]` |

- Fixtures in `testing/Fixtures.kt` use made-up titles and 32-hex account IDs. `FakeTransport` records requests so tests assert no forbidden header or non-GET; `AppContainer(transport =, settingsStore =)` runs the entire app from fake transport and in-memory `DataStore`.
- View models use `MainDispatcherRule` plus `runTest(main.dispatcher)`, and launch loaders in the test scope rather than `backgroundScope`.
- DataStore rename replacement fails when the target exists on the Windows JVM: on-disk tests make one write then cold-start reload; multi-write setters use the in-memory store.
- Robolectric's main looper is paused: advance with `shadowOf(Looper.getMainLooper()).idleFor(...)`, and use `waitUntil` for `flowOn(Dispatchers.Default)`. After `performScrollToNode`, call `SemanticsActions.OnClick` rather than touch the phone bottom bar. Apply `WindowLayoutInfoPublisherRule.overrideWindowLayoutInfo` after composition, then idle the looper, for simulated hinges.
- Robolectric cannot prove real 200% glyph wrapping on this host; assert centering/no overflow there and prove wrapping on the emulator. For pixel assertions, draw the content view to software `Bitmap` and crop `boundsInRoot`, because `captureToImage()` times out. `clearAndSetSemantics` removes the child text semantic: assert its description, size or pixels.

## Running on devices

- Run every emulator interaction through `tools/android/device.py` ([commands](../platforms/android.md#toolsandroiddevicepy)); never invoke an emulator directly or `connectedAndroidTest` outside `device.py test`. It serializes the host lock with a maximum 300-second hold.
- `device.py test <pkg.Class[#method]|package:pkg|annotation:pkg.Annotation> --avd <AVD>` boots one emulator, pins `ANDROID_SERIAL=emulator-5580`, and runs `:app:connectedDebugAndroidTest`; use `--task` to override and split longer suites by class/package.
- `@DeviceCi` is a **local subset annotation**, not the complete device CI suite. Run it locally with `device.py test annotation:com.festivalscoretracker.android.journeys.DeviceCi --avd FST_Phone`; it remains fixture-only and must pass without a hinge.
- Form-factor evidence covers `FST_Phone`, `FST_Book_Fold`, `FST_Passport_Fold`, `FST_TriFold`, `FST_Tablet` in every supported posture and `FST_Resizable` presets. Claim fold behavior only from `device.py features` output; the sidecar records API level, window size, device state and hinge angles. See [tri-fold limits](../platforms/android.md#tri-fold-and-resizable-emulation).
- Cold boots disable animations by default; pass `--animations` to test scale behavior. Tool unit tests: `python -m unittest discover -s tools/android/tests`.

## CI

- `android-device` in [`.github/workflows/android-device.yml`](../../.github/workflows/android-device.yml) runs the **whole** `:app:connectedDebugAndroidTest` suite on a phone emulator for relevant pull requests and `master` pushes. It uses KVM, cached Gradle/AVD state, API 35 Google APIs x86_64 Pixel 6 (411 dp, closest supported phone geometry to `FST_Phone`) and disabled animations. It uploads `android-device-reports` (HTML/XML) and `android-device-logcat` with `FST_ATF` findings on failure.
- `android-fold` in [`.github/workflows/android-fold.yml`](../../.github/workflows/android-fold.yml) runs only `@HalfOpenFoldJourney` connected journeys on API 35 Google APIs x86_64 Pixel 9 Pro Fold with its hinge at 90 degrees (`FST_Book_Fold` `half`) and runner arguments `annotation=...HalfOpenFoldJourney` and `fstRequireHinge=true`. It runs for Android workflow-relevant pull requests and `master` pushes, and uploads `android-fold-reports`.
- A half-open journey calls `JourneyHarness.requireHingeWhenAsked()`: with `fstRequireHinge=true`, no separating vertical WindowManager hinge fails rather than skipping checks (issue #384). Tag only after the equivalent local `device.py test ... --avd FST_Book_Fold --posture half --runner-arg annotation=...HalfOpenFoldJourney --runner-arg fstRequireHinge=true` succeeds. `SongPathsDeviceTest#halfOpenSheetStaysOnOneSideAndReadsInOrderAtEveryTextSize` is tagged (#384); `ModalCloseJourneyTest`, `ShopSortDeviceJourneyTest`, `ProfileDeviceJourneyTest`, `GlobalSearchDeviceTest`, `PinnedPageControlsDeviceTest`, `FeedbackFormJourneyTest`, `ServiceStatusDeviceTest` and `WhatsNewDeviceTest` remain device-lab runs until tagged.
- The Robolectric half-open companions (for example `SongPathsSheetUiTest` with `WindowLayoutInfoPublisherRule`) stay in `android-unit`; they do not exercise ATF or the real accessibility tree.
- Every connected test must undo process-wide resource configuration, system settings and singletons. `JourneyHarness.launch(fontScale = ...)` restores shared resources on `ON_DESTROY` (issue #528, guarded by `JourneyHarnessFontScaleDeviceTest`). Rotated tests must restore natural rotation and sensor state: `ShellHitTargetDeviceTest` restores `accelerometer_rotation`/`user_rotation`, waits for `mProposedRotation` 0 when auto-rotate is on and logs `FST_ROTATION`. Reproduce order dependence by passing the earlier class first in a comma-separated `device.py test` filter. CI quarantines: none.

## Accessibility tooling

| Tool | Coordinates / availability |
|---|---|
| Espresso View checks | `androidx.test.espresso:espresso-accessibility:3.7.0` (`AccessibilityChecks.enable()`) |
| Accessibility Test Framework | `com.google.android.apps.common.testing.accessibility.framework:accessibility-test-framework:4.1.1` |
| Compose checks | `ComposeUiTest.enableAccessibilityChecks()` (ATF-backed, project Compose BOM) |
| TalkBack 17.0 | API 37 Google APIs image; toggle `talkback:on\|off` |
| Accessibility Scanner | Play Store only; use ATF on the Google APIs image |
| Text/dark | `fontscale:<x>` and `dark:on\|off` |

- All `androidTest/.../journeys/` use `JourneyHarness`: `BandsSettingsJourneyTest`, `BandRankingsJourneyTest`, `SongsAccessibilityJourneyTest`, `PlayerAccessibilityJourneyTest`, `ShellAccessibilityJourneyTest`, `ScoreAccuracyJourneyTest`, `ModalCloseJourneyTest`, `SongDetailPreviewRowsJourneyTest`, `SongLeaderboardJourneyTest`, `DrawerCornersAccessibilityJourneyTest`, `SongsBucketHeaderAccessibilityJourneyTest`, `PinnedPageControlsDeviceTest`, `SongPathsDeviceTest`, `CompeteReturnAccessibilityJourneyTest` and `ProfileIdentityAccessibilityJourneyTest`.
- Modal Close is labelled, 48 dp, after the heading and dismisses; no modal straddles a separating hinge (#146). Account-bearing Song Detail top-10 rows are 48 dp `Button` stops labelled "Open profile"; no-account rows are not clickable (#171). Song leaderboard reading order is title after scroll, then rows, pinned score and pager; its jump row is one 48 dp button (#190).
- Drawer corners must keep 48 dp labelled/selected rows and visible title inside the recalculated concentric outline at device and 200% text; order is title, entries, footer (#419). Transparent Songs bucket headers are unclickable spoken headings before their rows, including sticky handoff; on in-place 200% text they grow without clipping (#441). Paths at half-open stay entirely on one hinge side, read heading/Close/cards/controls and clip no text at 100% and 200% (#289, #384).
- Configure `setComposeAccessibilityValidator` before interactions and each `readingOrder`; it writes `FST_ATF` and `assertAccessible()` fails once with all findings. Ignore only clipped-off viewport nodes below 8 dp and an off-screen 40 dp visual toolbar button after its fresh 48 dp touch bounds pass; API 34's exposed 8 dp sheet scrim strip is equivalent to the header Close/Back (#171, #418).
- `readingOrder` derives labels from text, unfocusable child labels and state as TalkBack does (#123). Call `readingOrder(..., fresh = true)` after in-place font-scale changes to clear the API 34+ UiAutomation cache (#397). For sheet/dialog 200% tests, use `@SystemFontScale(2f)` before the Compose rule because composition-local scale does not cross a window boundary (#384, #428). A bare `ComponentActivity` hosting full-height `FestivalModalSheet` must call `enableEdgeToEdge(...)` before composition or API 34 exposes the too-small scrim (#434). Prove clipping from line widths/paragraph height, not `hasVisualOverflow`.
- `publishTalkBackTree()` activates accessibility and follows Compose `traversalBefore`/`After` after every scroll. Assert ordered positions, not membership; clear the node cache after scroll. Run the journey package then `drive --steps "logcat:<file>@FST_ATF"`.
- `tools/android/talkback_walk.py` drives real TalkBack with kernel Meta+Right key events (or a one-finger virtual multi-touch swipe after hiding an IME), reads and clears verbose logcat per step, and writes `<name>.md`, `.json` and `.log`. UIAutomator and injected input do not drive TalkBack and dumps reset focus. Use `--before "tap:desc=Sort songs;wait:2"` for a sheet; results are in [android-accessibility.md](android-accessibility.md).
- Live-region tests force `ViewRootForTest` accessibility on/off around the test, count live-region `TYPE_WINDOW_CONTENT_CHANGED` events and include a positive control; see `ServiceStatusDeviceTest.countdownTicksDoNotReannounceButANewStatusDoes` (#140).
- `ShopSortDeviceJourneyTest` persists Duration/Descending sort through relaunch, checks Reset and hinge/ATF in grid/list (#379; [catalogue sort](../patterns/catalogue-sort.md)). `CompeteReturnAccessibilityJourneyTest` checks position/reading order through Full Leaderboards Back at 1x/2x text, including a newer publication, and accounts for the hidden-on-scroll Quick Links item (#82, #435; [app navigation](../controls/app-navigation/android.md)). `ProfileIdentityAccessibilityJourneyTest` reads the player title once, never avatar initials, and checks identity actions/notice at 1x/2x (#97, #446).
- `tools/android/frame_stats.py` resets `gfxinfo`, drives or idles, merges `IntendedVsync` frames and reports UI-thread (`Vsync` to `SyncQueued`) and total percentiles. SwiftShader inflates total timing; set all three animation scales before fling evidence.

## Coverage

- `createDebugUnitTestCoverageReport` supplies JaCoCo. `fst_android.py coverage` defines logic as `core/`, `data/`, `presentation/` and UI as the remainder, excluding generated serializers/Compose singletons; gate with `--min-logic 95`.
- Last measured: report/190 Android song leaderboard validation (2026-10-06) - 98.1% logic, 96.6% UI, 1,623 JVM/Robolectric tests. Posture evidence is `tools/android/search_journey.py` against a path-logging fixture.
- Open: `MainActivity` remains 0% and needs fixture-origin/instrumented coverage; finish instrumented and TalkBack evidence. Control-state and navigation coverage remain independent requirements.
