# Android architecture and devices

> **What:** Kotlin/Compose architecture, the emulator device matrix and `tools/android/device.py`. **Read when:** working on the Android app or running it on an emulator (built on `sfenton-music` via [windows-relay](../workflow/windows-relay.md)). Design: [design/android.md](../design/android.md); tests: [testing/android.md](../testing/android.md).

- Kotlin + Jetpack Compose, single activity, domain/data/UI boundaries, lifecycle-aware state.
- Observe fold/display features with Jetpack WindowManager, never product names or pixel checks.
- Respect system animation scale, dynamic text, contrast, TalkBack traversal, system/predictive back and Android 16 edge-to-edge.
- Fixture mock server only; no production POSTs ([service safety](service-safety.md)).
- Record API level, window size and pose with each device result (`device.py shot` writes a `.json` sidecar with all three plus the reported display features).

## Android SDK on `sfenton-music`

SDK root `C:/Users/sfent/AppData/Local/Android/Sdk`; JDK 17 (Temurin 17.0.20). Packages are installed side by side; never uninstall or downgrade one another lane may be using.

| Package | Version |
|---|---|
| Emulator | 37.1.11 |
| Acceleration | Windows Hypervisor Platform (WHPX), which needs CPU virtualization (AMD SVM) enabled in the UEFI. On `sfenton-music` both are on (2026-10-03): `emulator -accel-check` reports "WHPX … is installed and usable" and `device.py boot FST_Phone` boots headless in about a minute. Without it, `device.py boot` fails with "x86_64 emulation currently requires hardware acceleration"; builds and JVM unit tests are unaffected |
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
| `launch [--tab] [--route] [--extra K=V] [--apk] [--posture]` | Cold start (`am start -W -S --activity-clear-task --display 0`) with string intent extras `FST_DEBUG_TAB`/`FST_DEBUG_ROUTE`/any `FST_*`. Right after `install`, `-S` alone could hand the intent to the old instance and drop the extras; `--activity-clear-task` plus one force-stop retry makes the launch fresh, and the launch fails if it still isn't |
| `shot <out.png>… [--no-launch] [launch options]` | Launch, then screenshot the physical display backing logical display 0, plus a `.json` sidecar |
| `drive --steps "…" [--steps-file] [--launch]` | UIAutomator/`adb input` steps (below) |
| `features [postures…]` | FoldingFeatures seen by WindowManager, per posture |
| `test [pkg.Class[#m]\|package:pkg] [--task] [--posture]` | Connected tests on one AVD with `ANDROID_SERIAL` pinned (posture applied first), killed at the hold limit |

Common options: `--avd` (default `FST_Phone`), `--hold` (≤300 s), `--wait-timeout`, `--window` (only works in an interactive session), `--allow-foreign`, `--animations`. `--animations` only skips zeroing the scales; the AVD keeps whatever an earlier lane left (usually 0), so for motion evidence set them in the steps (`shell:settings put global animator_duration_scale 1`, likewise `transition_animation_scale` and `window_animation_scale`) and relaunch with a `shell:am start -W -S …` step before recording (issue #149). Exit codes: 3 for device/usage errors, 124 for lock timeouts.

Drive steps (`;`- or newline-separated; `#` comments):

| Step | Meaning |
|---|---|
| `tap:`/`longpress:`/`waitfor:<sel>[@secs]` | `sel` = `id=<resource-id or testTag>`, `text=`, `desc=`, `contains=`, or `x,y` |
| `swipe:up\|down\|left\|right` or `swipe:x1,y1,x2,y2[,ms]` | Finger direction |
| `type:<text>`, `key:<name\|KEYCODE_…>`, `back`, `home`, `wait:<s>`, `rotate:0\|90\|180\|270` | Input |
| `shot:<png>`, `tree:<xml>` | Screenshot plus sidecar; UIAutomator dump |
| `posture:<p>`, `resize:<preset>` | Fold posture; resizable preset |
| `talkback:on\|off`, `fontscale:<0.5–2>`, `dark:on\|off` | Accessibility state |
| `record:<mp4>` … `record:stop` | `adb shell screenrecord` (≤180 s) in the background; `stop` pulls the clip. A recording still running when the drive ends is stopped and pulled |
| `logcat:clear`, `logcat:<file>[@TAG]` | Clear the log, or dump it (optionally one tag, e.g. `FST_A11Y` reading orders from the accessibility journeys) |
| `shell:<command>` | One device shell command on the FST emulator (e.g. `pm grant com.google.android.marvin.talkback android.permission.POST_NOTIFICATIONS` before a TalkBack walkthrough) |

From Git Bash, pass Windows paths (`C:/…`) inside `--steps`: MSYS converts only whole arguments, so `/c/…` inside a step becomes `C:\c\…`.

Compose `testTag`s appear as resource ids only when the app sets `testTagsAsResourceId`. Under TalkBack, `input tap` explores rather than activates.

`rotate:` writes `user_rotation`, which did not rotate FST_Phone in issue #111 (2026-10-03). Use `shell:wm user-rotation lock 1` for landscape and `shell:wm user-rotation lock 0` to restore portrait. After that rotation, named `swipe:up|down` still uses portrait coordinates: on FST_Phone it starts at y = 1800, off the 1080 px landscape screen, and nothing scrolls (issue #176). Use explicit `swipe:x1,y1,x2,y2,ms` in landscape, e.g. `swipe:1000,660,1000,380,500` on FST_Phone.

## Emulator lock

- One product emulator per host, shared by every lane through the `emulator` host lock (`tools/android/hostlock.py`). It is an OS byte-range lock on `~/.fst-locks/emulator.lock`, released automatically if the holder dies, plus a FIFO ticket queue in `~/.fst-locks/emulator.queue/`. `holder.json` records the command and the caller's worktree.
- A hold lasts at most **300 s**. A watchdog kills tracked children, releases the lock and exits with 124. Waiters give up after `--wait-timeout` (default 1800 s).
- FST emulators always use console port **5580** (`emulator-5580`). Only `FST_*` AVDs, or whatever holds port 5580, are ever stopped. Any other running emulator makes `boot` refuse (exit 3) rather than kill it.
- Shutdown runs `sync` + `reboot -p`, then `emu kill`, then kills leftover qemu processes. A hard `emu kill` can lose recent `/data` writes such as a fresh install. Install and shoot in one hold with `--apk`.
- Every lane installs its own build of the same package on the shared AVDs. A `drive` or `launch` without `--apk` runs whatever another session installed last. In issue #149 that misled one capture: a stale build showed a misalignment the current branch had already fixed. Pass `--apk` for every evidence or validation run.
- Emulator logs: `~/.fst-locks/emulator-<AVD>.log`.
# Android architecture and devices

> **What:** Kotlin/Compose architecture, build/run tooling and device rules for Android. **Read when:** working on the Android app (built on `sfenton-music` via [windows-relay](../workflow/windows-relay.md)). Design: [design/android.md](../design/android.md); tests: [testing/android.md](../testing/android.md).

## Layers (`android/app/src/main/java/com/festivalscoretracker/android/`)

| Package | Holds | Rule |
|---|---|---|
| `core/` | Wire models, `FestivalApiException`, `ServiceIssue` + freeze reasons + `ServiceRetryBackoff`, song search/sort/section index, formatting, difficulty-meter geometry, `AppRoute`, tab/adaptive-layout policy, `DebugLaunch` | Pure Kotlin, no Android imports; mirrors Apple `FestivalCore` names |
| `data/` | `RequestGate`, `FestivalApi`, `OkHttpTransport`, `ForcedFreezeTransport`, `SettingsRepository` (DataStore) | Only path to the service |
| `presentation/` | ViewModels, `RetryingLoader`/`LoadState`, `BackgroundController` | Logic; unit-tested |
| `ui/` | Compose screens, shell, design primitives, background | Composables only |
| root | `MainActivity` (single activity, edge-to-edge), `FestivalApplication` (Coil loader), `AppContainer` (manual DI) | |

## Service access

- One request path: `RequestGate.send` rejects non-GET and `X-API-Key` / `x-fst-selected-*`, checks cancellation both sides, and `mapStatus` maps 202/304/503(+`Retry-After`, `X-FST-Public-Read-Freeze-Reason`)/other → `FestivalApiException` → `ServiceIssue`. Never create another client. Rules: [service-safety](service-safety.md).
- `FestivalApi` bootstraps `/api/publication`, sends `X-FST-Publication-Id` only while `readyForPinning && pinningEnabled`, retries one `publication_changed` 409, adopts a newer response publication when unpinned, and keeps an in-process ETag body cache + decoded catalogue per publication (cleared on change). No HTTP disk cache (online-only).
- Origin: keyless `https://festivalscoretracker.com` in debug and release (`BuildConfig.SERVICE_ORIGIN`); a fixture run passes `FST_ORIGIN=http://10.0.2.2:<port>` (loopback/emulator host only; debug network config allows cleartext only there).
- Add an endpoint: a `ServiceEndpoint` case with validated segments + one typed method on `FestivalApi` + fake-transport tests (same steps as [add-endpoint](../skills/add-endpoint/SKILL.md)).
- `FestivalApi.readPinnedResponse(endpoint)` returns `PinnedRead(body, status, responsePublicationId?, observedPublicationId)`: use it when a 202 envelope is documented (returned uncached, without publication checks) or when selection needs header-verified provenance (player profile).
- `/api/songs` is ~4.6 MB (population tiers); the decoder skips unknown keys and streams from bytes.
- Decode off the main thread (issue #155): `FestivalApi.decode` moves bodies ≥ `OFFLOAD_BYTES` (64 KiB) and their validation/transform onto the injectable `decodeDispatcher` (`Dispatchers.Default`). Smaller bodies decode in place, so `StandardTestDispatcher` ViewModel tests stay on virtual time. OkHttp resumes on the caller's dispatcher and loaders run in `viewModelScope` (Main), so without this a pull-to-refresh decoded the whole catalogue on the UI thread. A refresh whose body is unchanged for the same publication (304, or the identical 200 the live service returns to `If-None-Match`) reuses the decoded catalogue memo. Large reads added later should use `decode(strategy, body) { transform }`.

## Navigation

- Typed Navigation-Compose routes in `core/nav/AppRoute.kt` mirror Apple `AppRoute` (every web route except Manual). Songs are addressed by ID and resolved against the current catalogue. Unported routes render a placeholder.
- One `NavHost`; tab roots (`*Tab`) switch with `popUpTo(start){saveState}` + `restoreState` (Statistics does not restore); re-tapping a tab pops to its root. Selected tab is derived from the back stack.
- Measured layout survives Back (issues #82, #185). Navigation recomposes a destination when Back returns to it, and a plain `remember` loses what the page measured, so its first frame is drawn unmeasured. The Compete grid fell back to one column, and board rows dropped or restacked their songs column for a frame before snapping back. Keep any measurement that picks columns, a hinge split or a row plan (a container's window position or width, a card's row width) in the saved helpers in `ui/common/MeasuredLayout.kt` (`rememberMeasuredPx`, `rememberMeasuredBounds`, `rememberMeasuredOffset`). They already back `AdaptiveCardGrid`, `ProfileGrid`, both `rememberHingeSplit`s, `rememberRankingRowWidth`, the Bands and Suggestions hinge offsets and `ServiceStatus`. Never add a new `remember { mutableFloatStateOf(…) }` measurement for these. Read hinges through `shellPosture()` (`ui/common/FestivalSheet.kt`), which returns the shell's already-collected `LocalShellPosture`. Never call `currentWindowAdaptiveInfo().windowPosture` in a page: that collector starts with an empty hinge list, so a destination recomposed on Back draws one frame as if unfolded. On the half-open Book Fold, Compete then flashed full-width cards. `ShellPostureTest` covers this. Tests: `MeasuredLayoutTest` (restoration), and `CompeteReturnColumnsUiTest` and connected `CompeteDeviceJourneyTest`, which check that the card's bounds and songs cells stay the same on every frame of the return.

## Debug launch extras (debug builds only)

String intent extras, same names as Apple: `FST_DEBUG_TAB`, `FST_DEBUG_ROUTE` (`song:<id-or-title>`, with `FST_DEBUG_INSTRUMENT=<wireId>` for its `?instrument=` focus, `songLeaderboard:<id>:<wireId>[:page[:reveal]]`, `songBandLeaderboard:<id>[:<bandType>[:page[:reveal]]]`, `player:`, `leaderboards`, `fullRankings:`, `bandRankings:`, `shop`, `rivals`, `statistics`, `suggestions`, `compete`, `bands`, `band:`, `licenses`), `FST_DEBUG_PROFILE=<accountId>:<name>` (in memory only), `FST_DEBUG_ANONYMOUS=1`, `FST_DEBUG_DRAWER=1`, `FST_DEBUG_SHEET=profile|notifications`, `FST_DEBUG_FIRST_RUN=off|on|force` (default off in debug), `FST_DEBUG_WHATS_NEW=off|on|fresh|force` (default off in debug; [What's New](../controls/whats-new/android.md)), `FST_DEBUG_DISTRIBUTION=store|play|tester|testflight` (What's New channel override; default from the installer), `FST_DEBUG_FORCE_FREEZE=1`, `FST_DEBUG_STILL_BACKGROUND=1`, `FST_DEBUG_SEARCH=<text>` (opens global search with that text) + `FST_DEBUG_SEARCH_SCOPE=songs|players|bands`, `FST_ORIGIN`. Parsed by `DebugLaunch` (unit-tested).

## Tooling

| Command (repo root) | Does |
|---|---|
| `python tools/android/fst_android.py build [--tests] [--coverage] [--release]` | Gradle wrapper build, JVM + Robolectric tests, JaCoCo report + logic/UI summary |
| `python tools/android/fst_android.py coverage --min-logic 95 [--files]` | Gate/summary from the JaCoCo XML |
| `python tools/android/licenses.py [--check]` | Regenerate (or verify) `assets/licenses.json` from the release runtime graph; run with every dependency change ([licenses](../pages/licenses/android.md)) |
| `python tools/android/fst_android.py session --avd FST_Phone "out.png\|posture\|wait\|KEY=V,KEY=V" …` | Installs the debug APK and takes every listed screenshot inside **one** shared-lock hold (with `device.py` JSON sidecars) |
| `python tools/android/search_journey.py [phone book-fold …]` | Global search + shell journeys per form factor/posture against a request-path-logging fixture (one hold each); fails on any `/api/bands/search` |
| `python tools/android/talkback_walk.py --avd … --route … --name … --out …` | Real TalkBack walk of one screen (or a sheet opened with `--before`), what it says in order ([testing](../testing/android.md#accessibility-tooling)) |
| `python tools/android/frame_stats.py --avd … --steps "swipe:up;…" --name … --out …` | Frame timing of one scenario from `gfxinfo framestats` (UI-thread and total percentiles) ([results](#performance)) |
| `python tools/android/fst_android.py device <install\|shot\|launch\|drive\|posture\|features\|list> …` | Forwards to the shared FIFO-locked `tools/android/device.py` (device-lab lane) with this app's package/activity |

- Prefer `session`: the lab boots AVDs fresh (`-no-snapshot`) and may shut them down between holds, so a separate `install` then `shot` can find the app gone. A shot right after a cold boot can show "You're offline" before networking is up — take a warm-up shot first.
- Screenshots of live data show production names, titles and third-party art: keep them as `android/reports/screenshots/*.local.png` (gitignored), never commit them ([service safety](service-safety.md)).
- Foldables: `--avd FST_Book_Fold --posture folded|unfolded` (and `device features` to see what WindowManager reports).

## Performance

Measured 2026-09-29 (FST-and-a11y2) with `tools/android/frame_stats.py --animations-on` on the **`benchmark` build type** (release-like, not debuggable, debug-signed, keeps the `FST_*` extras; `./gradlew :app:assembleBenchmark`), against the `--large-catalogue --large-rankings` mock service, 8 swipes up + 4 down per scroll. A debuggable debug build measures about 2× slower on the UI thread (Songs scroll p50 15.6 ms vs 9.8 ms under the older Vsync-based metric), so never judge jank from a debug build. SwiftShader renders on the host CPU, so **total** frame times (30–85 ms) are an emulator artefact; the UI-thread time (`HandleInputStart` → `SyncQueued`) is the app's own cost.

| Scenario | Device | Frames | UI p50 / p90 / p99 ms | UI > 8.33 ms | Composition / layout / draw p90 ms |
|---|---|---|---|---|---|
| Songs scroll | FST_Phone | 348 | 2.7 / 9.6 / 16.3 | 14% | 8.1 / 0.1 / 1.8 |
| Songs scroll | FST_Book_Fold unfolded | 259 | 1.7 / 3.8 / 15.7 | 3% | 3.2 / 0.2 / 0.7 |
| Song Detail scroll | FST_Phone | 301 | 1.9 / 6.0 / 18.0 | 5% | 4.9 / 0.2 / 1.2 |
| Song Detail scroll | FST_Book_Fold unfolded | 251 | 2.0 / 6.0 / 15.4 | 3% | 3.9 / 0.2 / 1.4 |
| Leaderboards scroll | FST_Phone | 340 | 2.2 / 6.6 / 24.3 | 7% | 5.5 / 0.2 / 0.9 |
| Leaderboards scroll | FST_Book_Fold unfolded | 240 | 2.9 / 7.3 / 23.4 | 6% | 4.6 / 0.1 / 1.3 |
| Full Rankings scroll | FST_Phone | 353 | 1.1 / 3.8 / 9.3 | 1% | 3.1 / 0.2 / 0.3 |
| Background animation (Settings, idle 15 s) | FST_Phone | 942 | 0.5 / 0.9 / 3.4 | 0 | 0.8 / 0.1 / 0.0 |
| Background + Shop pulse (Songs, idle 12 s) | FST_Phone | 745 | 0.6 / 1.3 / 6.2 | 2 frames | 1.1 / 0.1 / 0.0 |
| Background animation | FST_Book_Fold unfolded | 856 | 0.6 / 1.3 / 8.2 | 6 frames | 1.1 / 0.1 / 0.0 |

- No per-frame recomposition: the idle scenarios render every frame (artwork Ken Burns, Shop pulse/breathe, marquee) at 0.5–0.6 ms of UI work, all in the draw phase (`graphicsLayer`, `drawBehind`, `basicMarquee`).
- The remaining cost is composing rows that scroll in (Songs rows on a phone, p90 ≈ 8 ms on the emulator; a device CPU is faster). Changes made: instrument/star PNGs decoded once (`ui/design/BundledBitmaps.kt`; `painterResource` decoded them per call site) and the nine Songs status chips drawn by one node (`ChipGrid`) instead of a `BoxWithConstraints` subcomposition plus ~18 nodes. Both were within the emulator's run-to-run noise (±25% on the over-budget share), so neither is claimed as a measured win.
- Leaderboards/Song Detail p99 spikes (18–24 ms) are cards composing as they enter (rank history, instrument cards).
- Issue #155 (2026-10-05, FST_Phone, `benchmark` build, live service, SFentonX): a Perfetto trace of a Songs scroll stress pass (fast swipes near the top, flings down, flings back to the top) found one 676 ms frame gap. It was a fling at the top edge triggering pull-to-refresh, with ~490 ms of main-thread catalogue decode plus a GC storm. After the off-main decode fix, the longest 500 ms window of main-thread running time fell from 389 ms to ~212 ms (frames included), and the refresh decode runs on `DefaultDispatcher`. doFrame p50/p90/p99 was 20.3/29.3/63.7 ms. The two remaining ~290 ms frames are the main thread *sleeping* in `postAndWait` while RenderThread runs SwiftShader's first-use `shader_compile`, an emulator artefact that does not recur. Method: `perfetto` (sched + `gfx view am` atrace, 150 s background) during `input swipe` steps, then trace_processor queries on `Choreographer#doFrame` slices and main-thread `sched` time per window.
- Issue #83 (2026-10-02): the idle backdrop rows above are every-vsync work (942 frames in 15 s ≈ 63 fps), also while a sheet or the first-run dialog covers it. The backdrop now samples at 30 fps through `SteppedFrameClock` and holds its frame while any Festival modal is open ([artwork background](../controls/artwork-background/android.md)); expect ~450 frames per idle 15 s visible and ~0 under a modal. Not re-measured: this host has no emulator (see Devices). First-run demos already animate only the settled page, and Suggestions covers come from Coil's memory cache.
- Open: a Perfetto trace with `androidx.compose.runtime:runtime-tracing` on a real device to split Songs row composition by composable; a Macrobenchmark module (not added: needs a separate test module and a device lab that holds the emulator for longer than the 300 s lock).

## Devices

- One emulator per host, only through `device.py` (FST AVDs, API 37). Never start `Pixel_5_API_36`/`Pixel_9_Pro_Fold` by hand while lanes share the host; headless `-gpu auto` in session 0 wedged adb shell — the shared tool uses `swiftshader_indirect`.
- On 2026-10-02 `device.py boot` failed on `sfenton-music` with "x86_64 emulation currently requires hardware acceleration" because AMD SVM was off in the UEFI. It was enabled on 2026-10-03, and the emulator now boots there. Verify Android on the emulator (one at a time) rather than only through Robolectric and the generated `BuildConfig`.
- Observe folds with Jetpack WindowManager (`currentWindowAdaptiveInfo().windowPosture.hingeList`), never product names or pixels. Record API level, window size and posture with each result (`device.py` writes a JSON sidecar).
- Sheets and folds (issues #125, #126): `FestivalModalSheet` stays on one side of a separating hinge (the wider or leading half in book posture, below the hinge in tabletop) via `festivalSheetHingeSide()` and the pure `SheetHinge`. Material 3: "Never place interactive content or critical information across the hinge area." Flat or non-separating hinges (unfolded book, passport, tri-fold) keep the centred sheet. `JourneyHarness.assertNothingStraddles` checks this on `--posture half`. Centred dialogs (`DialogHinge`) and the full-page service status (`serviceStatusHingeSide`, issue #140) use the same side rule, implemented once in `core/nav/HingeSide.kt` ([modal-shell](../patterns/modal-shell.md) R8): a horizontal (tabletop) hinge always keeps the **lower** half, whichever half is larger, never "the larger side". The three surfaces only adapt `HingeSide`'s kept rectangle; never write another side rule.
- Shell continuity (issues #106, #122, #126): `FestivalShell` keeps the NavHost under one parent at every width (always inside `ModalNavigationDrawer`, whose sheet stays closed and empty beside the permanent drawer), so the PermanentDrawer ⇄ Rail/modal switch on rotation or resize keeps scroll, open sheets and their state. Hosting the pages bare in the permanent layout moved their composition position and reset all of it; `movableContentOf` also kept it but let the moved NavHost's back callback outrank the drawer's. Details: [app-navigation](../controls/app-navigation/android.md).
- Compact-height windows (`AdaptiveLayoutPolicy.isCompactHeight`, < 480 dp) move live-sheet Reset into the header beside Close, so a pinned footer never shrinks the form at 200 % text in landscape.
- The sheet drag handle keeps a 48 dp actionable area (`Modifier.minimumInteractiveComponentSize()`). Material's handle is 32 dp wide and TalkBack-actionable, which fails ATF `TouchTargetSizeCheck`.
- Scrolling content and folds (issue #131): full-width lists and grids flow around a separating vertical hinge rather than drawing over it. Item Shop does this with one `LazyVerticalGrid` whose custom `GridCells` + `Arrangement.Horizontal` leave a hinge-wide gap (pure `ShopColumnPolicy.resolve`). Like every hinge split, it is off under TalkBack or large text (`rememberSingleColumn`).
- An M3 `IconButton` inside a row's trailing slot measured 40 dp wide in Robolectric (`minimumInteractiveComponentSize` did not widen it). Give row-trailing icon buttons an explicit `Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)` and assert the width in a UI test.
- Host: Android SDK `C:/Users/sfent/AppData/Local/Android/Sdk`, JDK 17 (Temurin), Gradle 8.14.3 wrapper, AGP 8.11, Kotlin 2.2.10, compile/target SDK 36, min 26.
