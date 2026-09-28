# Android testing

> **What:** Android coverage, device-test and accessibility-test rules. **Read when:** writing or running Android tests. Architecture and the device matrix: [platforms/android.md](../platforms/android.md).

- Host (JVM) + instrumented tests together must reach **95% logic / 90% UI lines**; Android Gradle [coverage reports](https://developer.android.com/studio/test/coverage-report) include instrumented results. `tools/coverage_gate.py` parses JaCoCo XML and merges per-line hits across host and instrumented reports.
- Control-state snapshots and navigation coverage are separate evidence from line coverage.
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
