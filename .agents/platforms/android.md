# Android architecture and devices

> **What:** Kotlin/Compose architecture and device rules for Android. **Read when:** starting Android work (not yet integrated; see [PROGRESS.md](../../PROGRESS.md)). Design: [design/android.md](../design/android.md); tests: [testing/android.md](../testing/android.md).

- Kotlin + Jetpack Compose, single activity, domain/data/UI boundaries, lifecycle-aware state.
- Observe fold/display features with Jetpack WindowManager, never product names or pixel checks.
- Respect system animation scale, dynamic text, contrast, TalkBack traversal, system/predictive back and Android 16 edge-to-edge.
- Fixture mock server only; no production POSTs ([service safety](service-safety.md)).
- Devices: run one emulator at a time on the Windows host; verify real hinge features before claiming tri-fold emulation; record API level, window size and pose with each result.
- Android review branches are not integrated. TODO(orchestrator): record the Android project path and build command once integrated.
