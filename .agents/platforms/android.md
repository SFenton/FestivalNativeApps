# Android architecture and devices

> **What:** Kotlin/Compose architecture, the emulator device matrix and `tools/android/device.py`. **Read when:** working on the Android app or running it on an emulator (built on `sfenton-primary` via [windows-relay](../workflow/windows-relay.md)). Design: [design/android.md](../design/android.md); tests: [testing/android.md](../testing/android.md).

- Kotlin + Jetpack Compose, single activity, domain/data/UI boundaries, lifecycle-aware state.
- Observe fold/display features with Jetpack WindowManager, never product names or pixel checks.
- Respect system animation scale, dynamic text, contrast, TalkBack traversal, system/predictive back and Android 16 edge-to-edge.
- Fixture mock server only; no production POSTs ([service safety](service-safety.md)).
- Record API level, window size and pose with each device result (`device.py shot` writes a `.json` sidecar with all three plus the reported display features).

## Android SDK on `sfenton-primary`

SDK root `C:/Users/sfent/AppData/Local/Android/Sdk`; JDK 17 (Temurin 17.0.17). Packages are installed side by side; never uninstall or downgrade one another lane may be using.

| Package | Version |
|---|---|
| Emulator | 37.1.11 |
| Platform-tools (adb) | 37.0.1 |
| cmdline-tools | 23.0 (side by side with `latest` = 20.0). `sdkmanager` 23 prints a deprecation notice (replacement: `android sdk`) and exits 9 even on success, and its `.bat` splits `;`, so pass packages with `--package_file=` |
| Platforms | android-36, android-37.0, **android-37.2** (latest stable) |
| Build-tools | 35.0.0, 36.0.0, 36.1.0, **37.0.0** |
| System images | `android-37.2;google_apis_ps16k;x86_64` (FST AVDs; API 37.2 x86_64 Google APIs exists only as a 16 KB page-size image), `android-37.0;google_apis;x86_64` (4 KB fallback), plus the API 36 images used by the legacy AVDs |

## FST AVD matrix

Created deterministically by `python tools/android/device.py avds --create [--force] [--only NAME]` (the source of truth is `AVDS` in `device.py`). All use the API 37.2 image and are cold-booted headless (`-no-snapshot -no-window -gpu swiftshader_indirect`, animations scaled to 0 unless `--animations` is passed). Legacy `Pixel_5_API_36` and `Pixel_9_Pro_Fold` are never managed by the tool.

| AVD | Profile | Inner (px @ dpi) | Posture support |
|---|---|---|---|
| `FST_Phone` | `pixel_9` | 1080×2424 @ 420 | none |
| `FST_Book_Fold` | `pixel_9_pro_fold` | 2076×2152 @ 390; cover 1080×2424 | `folded`/`half`/`unfolded`: real device states CLOSED/HALF_OPENED/OPENED; fold at x=1038 reported FLAT/HALF |
| `FST_Passport_Fold` | `pixel_fold` | 2208×1840 @ 420; cover 1080×2092 | same, fold at x=1104 |
| `FST_TriFold` | custom `fst_trifold` (see below) | 2160×1584 @ 320 | `folded`/`partial`/`unfolded` (or explicit `180,0` angles); no half-open |
| `FST_Tablet` | `pixel_tablet` | 2560×1600 @ 320 | none |
| `FST_Resizable` | `resizable` | 1080×2400 @ 420 | presets `phone`/`foldable`/`tablet`/`desktop` |

Every AVD boots headless in roughly 20–60 s. Verify folding features with `device.py features --avd <AVD> <postures…>`: it builds a Gradle-free probe APK (`tools/android/probe`) that subscribes to the on-device `androidx.window.extensions` library, which Jetpack WindowManager wraps, and prints each window size and `FoldingFeature`.

### Tri-fold emulation

No official tri-fold profile ships with emulator 37.1 or cmdline-tools 23.0. `FST_TriFold` models a Galaxy Z TriFold-class device: three 720×1584 px panels with two vertical hinges (`hw.sensor.hinge.count=2`, areas at x=720 and x=1440).

| Emulated (verified through the WindowManager extensions) | Not emulated |
|---|---|
| Window 720×1584 (folded, one panel, 360×792 dp), 1440×1584 (partial, one FLAT fold at x=720), 2160×1584 (unfolded, two FLAT folds) | Device states: stays `DEFAULT`, so `DeviceStateManager`-based APIs, rear display and HALF_OPENED do not change |
| Two hinge-angle sensors (`adb emu sensor set hinge-angle0/1`) | Real display switching: API 37 images only switch inner/outer displays for known Pixel profiles, so the tool emulates folds with `wm size` plus the `display_features` global setting |
| Configuration changes and continuity across posture changes, since the window size changes | An independent cover screen: display region 0.1 is a second, always-on 720×1584 display that never takes over. Apps are launched with `--display 0`. The emulator hangs or crashes at boot if the hinge profile has no region |

### Resizable

`adb emu resize-display` is a no-op on emulator 37.1 (headless or windowed), and the profile's `desktop` config is ignored. `device.py posture <preset> --avd FST_Resizable` instead applies `wm size`/`wm density` from `hw.resizable.configs`: phone resets to 1080×2400 @ 420, foldable is 2208×1840 @ 420 with one fold, tablet 1920×1200 @ 240, desktop 1920×1080 @ 160. Every preset also overrides the image's built-in fold, so tablet and desktop report none.

## `tools/android/device.py`

| Command | Effect |
|---|---|
| `list` | Matrix, installed/running emulators, lock holder and queue |
| `avds [--create] [--force] [--only NAME]` | Show or (re)create FST AVDs |
| `boot <AVD>` | Boot exclusively (gracefully powers off any other FST emulator) and print metadata |
| `shutdown` | Power off FST emulators (never foreign ones) and reap orphaned FST qemu processes |
| `posture <name\|angles\|preset> [--avd]` | Hinge posture or resizable preset |
| `install <apk>` | `adb install -r -t -g` |
| `launch [--tab] [--route] [--extra K=V] [--apk] [--posture]` | Cold start (`am start -W -S --display 0`) with string intent extras `FST_DEBUG_TAB`/`FST_DEBUG_ROUTE`/any `FST_*` |
| `shot <out.png>… [--no-launch] [launch options]` | Launch, then screenshot the physical display backing logical display 0, plus a `.json` sidecar |
| `drive --steps "…" [--steps-file] [--launch]` | UIAutomator/`adb input` steps (below) |
| `features [postures…]` | FoldingFeatures seen by WindowManager, per posture |
| `test [pkg.Class[#m]\|package:pkg] [--task]` | Connected tests on one AVD with `ANDROID_SERIAL` pinned, killed at the hold limit |

Common options: `--avd` (default `FST_Phone`), `--hold` (≤300 s), `--wait-timeout`, `--window` (only works in an interactive session), `--allow-foreign`, `--animations`. Exit codes: 3 for device/usage errors, 124 for lock timeouts.

Drive steps (`;`- or newline-separated; `#` comments):

| Step | Meaning |
|---|---|
| `tap:`/`longpress:`/`waitfor:<sel>[@secs]` | `sel` = `id=<resource-id or testTag>`, `text=`, `desc=`, `contains=`, or `x,y` |
| `swipe:up\|down\|left\|right` or `swipe:x1,y1,x2,y2[,ms]` | Finger direction |
| `type:<text>`, `key:<name\|KEYCODE_…>`, `back`, `home`, `wait:<s>`, `rotate:0\|90\|180\|270` | Input |
| `shot:<png>`, `tree:<xml>` | Screenshot plus sidecar; UIAutomator dump |
| `posture:<p>`, `resize:<preset>` | Fold posture; resizable preset |
| `talkback:on\|off`, `fontscale:<0.5–2>`, `dark:on\|off` | Accessibility state |

Compose `testTag`s appear as resource ids only when the app sets `testTagsAsResourceId`. Under TalkBack, `input tap` explores rather than activates.

## Emulator lock

- One product emulator per host, shared by every lane through the `emulator` host lock (`tools/android/hostlock.py`). It is an OS byte-range lock on `~/.fst-locks/emulator.lock`, released automatically if the holder dies, plus a FIFO ticket queue in `~/.fst-locks/emulator.queue/`. `holder.json` records the command and the caller's worktree.
- A hold lasts at most **300 s**. A watchdog kills tracked children, releases the lock and exits with 124. Waiters give up after `--wait-timeout` (default 1800 s).
- FST emulators always use console port **5580** (`emulator-5580`). Only `FST_*` AVDs, or whatever holds port 5580, are ever stopped. Any other running emulator makes `boot` refuse (exit 3) rather than kill it.
- Shutdown runs `sync` + `reboot -p`, then `emu kill`, then kills leftover qemu processes. A hard `emu kill` can lose recent `/data` writes such as a fresh install. Install and shoot in one hold with `--apk`.
- Emulator logs: `~/.fst-locks/emulator-<AVD>.log`.
