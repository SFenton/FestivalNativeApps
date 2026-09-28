# Festival Score Tracker — Android

Native Kotlin + Jetpack Compose app (single activity, Material 3), API 26–36.
Keyless public HTTPS by default; see `.agents/platforms/android.md` for the
architecture, service rules, debug launch extras and device tooling, and
`.agents/testing/android.md` for tests and coverage.

```
python tools/android/fst_android.py build --tests --coverage   # from the repo root
python tools/android/fst_android.py device shot out.png --avd FST_Phone --tab songs
```

Requires JDK 17 and the Android SDK (`local.properties` or `ANDROID_HOME`).
The Gradle wrapper pins Gradle 8.14.3.
