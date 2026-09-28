# Android foundation build evidence — 2026-09-24

- Branch: `feature/android-foundation`; JDK 17, installed Gradle 8.14.3,
  Android SDK platform 36 and build-tools 36.0.0.
- `:app:lintDebug :app:testDebugUnitTest :app:assembleDebug
  :app:assembleRelease :app:compileDebugAndroidTestKotlin` — **passed**,
  exit 0, using
  `--console=plain --no-daemon --quiet`.
- Host JUnit XML: `SongCatalogTest` 6 tests, 0 failures;
  `DifficultyGeometryTest` 2 tests, 0 failures (8 total).
- `app-debug.apk`: 11,119,236 bytes;
  SHA-256 `78FC87397A984E8743D1C4955654BC8DEA26A52394B3C58C40EA00F8778300E0`.
- `app-release-unsigned.apk`: 7,239,012 bytes;
  SHA-256 `C34AAAC5F3DEA9AB53F896A7444FB6DE4AE31E12E6583C1654917C3FE0CFFFFC`.
- Android lint passed with 10 dependency-update warnings only (pinned versions
  are build-tested); its HTML report remains local in ignored build output.
- Release manifest inspection with SDK `aapt dump permissions` showed no
  `android.permission.INTERNET`; debug manifest contains INTERNET and cleartext
  only for the emulator fixture origin.
- `python tools/verify_product.py` — valid non-strict inventory: 24 pending
  pages and 2 pending controls. Strict parity is not claimed.
- Instrumented Compose UI test source **compiled but did not run**. No emulator
  was launched, no production request or POST was made, and no coverage,
  screenshot, TalkBack, pose or performance result was measured. Build outputs
  are ignored by git and remain local; this tracked report travels in the git
  bundle, not the APK binaries.
