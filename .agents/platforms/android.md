# Android architecture and devices

> **What:** Kotlin/Compose architecture and device rules for Android. **Read when:** working on the Android app (built on `sfenton-primary` via [windows-relay](../workflow/windows-relay.md)). Design: [design/android.md](../design/android.md); tests: [testing/android.md](../testing/android.md).

- Kotlin + Jetpack Compose, single activity, domain/data/UI boundaries, lifecycle-aware state.
- Observe fold/display features with Jetpack WindowManager, never product names or pixel checks.
- Respect system animation scale, dynamic text, contrast, TalkBack traversal, system/predictive back and Android 16 edge-to-edge.
- Fixture mock server only; no production POSTs ([service safety](service-safety.md)).
- Devices: run one emulator at a time on the Windows host; verify real hinge features before claiming tri-fold emulation; record API level, window size and pose with each result.
- Tooling on `sfenton-primary` (verified 2026-09-28): Android SDK at `C:/Users/sfent/AppData/Local/Android/Sdk` (emulator, platform-tools, NDK, system images), JDK 17 (Temurin), AVDs `Pixel_5_API_36` and `Pixel_9_Pro_Fold`. Project: `android/` (Gradle Kotlin DSL).
