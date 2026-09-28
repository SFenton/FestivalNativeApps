# Android testing

> **What:** Android coverage and device-test rules. **Read when:** writing or running Android tests. Architecture: [platforms/android.md](../platforms/android.md).

- Host (JVM) + instrumented tests together must reach **95% logic / 90% UI lines**; Android Gradle [coverage reports](https://developer.android.com/studio/test/coverage-report) include instrumented results. `tools/coverage_gate.py` parses JaCoCo XML and merges per-line hits across host and instrumented reports.
- Control-state snapshots and navigation coverage are separate evidence from line coverage.
- One emulator at a time (on the Windows host); capture API level, window size and pose with every result; verify real hinge features before claiming tri-fold emulation.
- Use the [mock service](fixtures.md); no production POSTs.
- No Android coverage has been measured yet.
