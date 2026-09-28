# Android testing

> **What:** Android coverage, device-test and accessibility-test rules. **Read when:** writing or running Android tests. Architecture and the device matrix: [platforms/android.md](../platforms/android.md).

- Host (JVM) + instrumented tests together must reach **95% logic / 90% UI lines**; Android Gradle [coverage reports](https://developer.android.com/studio/test/coverage-report) include instrumented results. `tools/coverage_gate.py` parses JaCoCo XML and merges per-line hits across host and instrumented reports.
- Control-state snapshots and navigation coverage are separate evidence from line coverage.
- Installed-PWA reference (Chrome install on every FST AVD, video + measured animations): `tools/android/pwa.py`; findings and gaps in [pwa-reference/](pwa-reference/README.md).
- Use the [mock service](fixtures.md); no production POSTs. From the emulator, the host loopback is `10.0.2.2`.
- No Android coverage has been measured yet.

## Running on devices

- Run every emulator interaction through `tools/android/device.py` ([commands](../platforms/android.md#toolsandroiddevicepy)). It serializes lanes on the host emulator lock (≤300 s per hold). Never start emulators directly or run `connectedAndroidTest` outside `device.py test`.
- `device.py test <pkg.Class[#method]|package:pkg> --avd <AVD>` boots the AVD, pins `ANDROID_SERIAL=emulator-5580` and runs `:app:connectedDebugAndroidTest` (override with `--task`). Suites longer than 300 s must be split by class or package.
- Form-factor evidence: run each surface on `FST_Phone`, `FST_Book_Fold`, `FST_Passport_Fold`, `FST_TriFold` and `FST_Tablet`, in each supported posture, plus `FST_Resizable` presets for continuity. The sidecar from `shot`/`drive shot:` records API level, window size, device state and hinge angles.
- Claim fold behavior only from `device.py features` output (real `FoldingFeature`s). The tri-fold's limits are listed in [platforms/android.md](../platforms/android.md#tri-fold-emulation).
- Cold boots are headless with animations at scale 0 by default. Pass `--animations` when testing animation-scale behavior.
- Unit tests for the tooling: `python -m unittest discover -s tools/android/tests` (not yet part of CI's `tools/tests` discovery; TODO(orchestrator): wire in).

## Accessibility tooling

| Tool | Coordinates / availability |
|---|---|
| Espresso accessibility checks (View-based) | `androidx.test.espresso:espresso-accessibility:3.7.0` (`AccessibilityChecks.enable()`) |
| Accessibility Test Framework | `com.google.android.apps.common.testing.accessibility.framework:accessibility-test-framework:4.1.1` |
| Compose checks | `ComposeUiTest.enableAccessibilityChecks()` from `androidx.compose.ui:ui-test` (ATF-backed; use the project's Compose BOM version) |
| TalkBack 17.0 | Preinstalled on the API 37 Google APIs image, along with Switch Access, Voice Access and the Accessibility Menu. Toggle it with the `talkback:on\|off` drive step (secure settings) |
| Accessibility Scanner | Play Store only; not installable on the Google APIs image without a signed-in Play account. Use ATF checks instead |
| Text size, dark theme | `fontscale:<x>` and `dark:on\|off` drive steps |
> **What:** Android coverage, test layout and device-test rules. **Read when:** writing or running Android tests. Architecture: [platforms/android.md](../platforms/android.md).

## Layout

| Kind | Where | Runs on |
|---|---|---|
| JVM unit (core/data/presentation) | `android/app/src/test/.../{core,data,presentation}` | JVM (`testDebugUnitTest`) |
| Whole-shell Compose UI | `android/app/src/test/.../ui/ShellUiTest.kt` | Robolectric (SDK 34, `robolectric.properties`), phone `w411dp-h891dp` and expanded `w1280dp-h800dp` qualifiers |
| Instrumented | `android/app/src/androidTest` (Compose journeys on the real shell; shares `src/test/.../testing/` fixtures via the `androidTest` source set) | `device.py test <class> --avd <AVD> [--posture half]` on one FST AVD |

- Fixtures are synthetic (`testing/Fixtures.kt`: made-up titles, 32-hex fake account IDs); `FakeTransport` routes by path and records requests so tests assert that no forbidden header or non-GET was sent. Never copy production payloads ([service safety](../platforms/service-safety.md)).
- `AppContainer(transport =, settingsStore =)` injects the fake transport and an in-memory `DataStore` so the full `FestivalApp` runs offline.
- View models: `MainDispatcherRule` + `runTest(main.dispatcher)`; launch loaders in the test scope, not `backgroundScope` (`advanceUntilIdle` does not drive background work).

## Gotchas

- DataStore replaces its file by rename, which the **Windows JVM** refuses when the target exists: on-disk tests do one write then a cold-start reload; multi-write setters use the in-memory store. Android devices are unaffected.
- Robolectric runs coroutines on a paused main looper: advance with `shadowOf(Looper.getMainLooper()).idleFor(...)`, and `waitUntil` for `flowOn(Dispatchers.Default)` work (search debounce runs on real time).
- The phone bottom bar overlays scrolled content; after `performScrollToNode`, invoke `performSemanticsAction(SemanticsActions.OnClick)` instead of a touch click, or the touch lands on the tab (re-tap pops to root).

## Coverage

- Debug unit tests are instrumented by AGP JaCoCo (`createDebugUnitTestCoverageReport`); `fst_android.py coverage` splits **logic** (`core/`, `data/`, `presentation/`) from **UI** (everything else), excluding generated serializers/Compose singletons. Gate: `--min-logic 95`. Targets: 95% logic / 90% UI lines.

| Last measured | Logic lines | UI lines | Tests |
|---|---|---|---|
| master after and-shell-search (2026-09-28) | 97.9% | 93.2% | JVM + Robolectric (all lanes) |

- Posture evidence: `tools/android/search_journey.py` drives every FST AVD/posture against a path-logging fixture (screenshots in `android/reports/screenshots/search-*`, `shell-*`).
- Open: `MainActivity` (0%, needs an instrumented or fixture-origin activity test); instrumented tests and a TalkBack pass not started. Control-state snapshots and navigation coverage are separate evidence from line coverage.
