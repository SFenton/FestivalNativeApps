# Android architecture and devices

> **What:** Kotlin/Compose architecture, Android build/run tooling, emulator matrix and `tools/android/device.py`. **Read when:** working on the Android app or an emulator (built on `sfenton-music` via [windows-relay](../workflow/windows-relay.md)). Design: [design/android.md](../design/android.md); tests: [testing/android.md](../testing/android.md).

- Kotlin + Jetpack Compose, one edge-to-edge activity, domain/data/UI boundaries and lifecycle-aware state.
- Use Jetpack WindowManager display features; never identify devices by product name or pixel heuristic.
- Respect animation scale, dynamic text, contrast, TalkBack order, system/predictive Back and Android 16 edge-to-edge.
- Use fixture mock servers only; never production POSTs ([service safety](service-safety.md)).
- Record API level, window size and posture with every device result; `device.py shot` writes this and reported display features to a JSON sidecar.

## Layers (`android/app/src/main/java/com/festivalscoretracker/android/`)

| Package | Holds | Rule |
|---|---|---|
| `core/` | Wire models, `FestivalApiException`, `ServiceIssue`/freeze reasons/`ServiceRetryBackoff`, song search/sort/section index, formatting, difficulty-meter geometry, `AppRoute`, adaptive-layout policy, `DebugLaunch` | Pure Kotlin without Android imports; mirrors Apple `FestivalCore` names |
| `data/` | `RequestGate`, `FestivalApi`, `OkHttpTransport`, `ForcedFreezeTransport`, `SettingsRepository` (DataStore) | Only service path |
| `presentation/` | ViewModels, `RetryingLoader`/`LoadState`, `BackgroundController` | Logic; unit-tested |
| `ui/` | Compose screens, shell, design primitives, background | Composables only |
| root | `MainActivity`, `FestivalApplication` (Coil loader), `AppContainer` (manual DI) | |

## Service access

- `RequestGate.send` rejects non-GET and `X-API-Key`/`x-fst-selected-*`, checks cancellation on both sides, and maps 202/304/503 (including `Retry-After` and `X-FST-Public-Read-Freeze-Reason`)/other statuses to `FestivalApiException` then `ServiceIssue`. Do not create another client; see [service safety](service-safety.md).
- `FestivalApi` bootstraps `/api/publication`; it sends `X-FST-Publication-Id` only while `readyForPinning && pinningEnabled`, retries one `publication_changed` 409, adopts a newer response publication when unpinned, and keeps only an in-process ETag body/decoded-catalogue cache per publication. Clear it on publication change; do not add an HTTP disk cache.
- Debug and release use keyless `https://festivalscoretracker.com` (`BuildConfig.SERVICE_ORIGIN`). Fixtures pass `FST_ORIGIN=http://10.0.2.2:<port>`; debug cleartext is allowed only for that emulator-host loopback.
- Add an endpoint as a validated `ServiceEndpoint` case, one typed `FestivalApi` method and fake-transport tests ([add-endpoint](../skills/add-endpoint/SKILL.md)).
- `FestivalApi.readPinnedResponse(endpoint)` yields `PinnedRead(body, status, responsePublicationId?, observedPublicationId)` for documented 202 envelopes (uncached and unchecked) or header-verified selection provenance.
- `/api/songs` is about 4.6 MB; skip unknown decoder keys and stream from bytes. Since issue #155, `FestivalApi.decode` runs bodies >= `OFFLOAD_BYTES` (64 KiB), validation and transform on injectable `decodeDispatcher` (`Dispatchers.Default`); smaller bodies remain on the caller so `StandardTestDispatcher` ViewModel tests retain virtual time. Reuse the decoded catalogue for same-publication 304 or identical 200 responses. New large reads use `decode(strategy, body) { transform }`.

## Navigation and layout

- Typed Navigation-Compose routes in `core/nav/AppRoute.kt` mirror Apple `AppRoute` for every web route except Manual. Songs use IDs resolved against the current catalogue; unported routes show a placeholder.
- Use one `NavHost`. Tab roots switch with `popUpTo(start){saveState}` and `restoreState` (except Statistics); re-tapping pops to root and selected tab derives from the back stack.
- Preserve measurement that decides columns, hinge split or row plan in `ui/common/MeasuredLayout.kt` (`rememberMeasuredPx`, `rememberMeasuredBounds`, `rememberMeasuredOffset`), never a new `remember { mutableFloatStateOf(...) }` (issues #82, #185). This protects first frames after Back for `AdaptiveCardGrid`, `ProfileGrid`, both `rememberHingeSplit`s, `rememberRankingRowWidth`, Bands/Suggestions offsets and `ServiceStatus`; test with `MeasuredLayoutTest`, `CompeteReturnColumnsUiTest` and `CompeteDeviceJourneyTest`.
- Read the shell-collected `LocalShellPosture` through `shellPosture()` in `ui/common/FestivalSheet.kt`; never call `currentWindowAdaptiveInfo().windowPosture` in a page, because its empty initial hinge list flashes unfolded after Back (issue #185).

## Debug launch extras

Debug builds parse these unit-tested string extras in `DebugLaunch`: `FST_DEBUG_TAB`; `FST_DEBUG_ROUTE` (`song:<id-or-title>` with `FST_DEBUG_INSTRUMENT=<wireId>`, `songLeaderboard:<id>:<wireId>[:page[:reveal]]`, `songBandLeaderboard:<id>[:<bandType>[:page[:reveal]]]`, `player:`, `leaderboards`, `fullRankings:`, `bandRankings:`, `shop`, `rivals`, `statistics`, `suggestions`, `compete`, `bands`, `band:`, `licenses`); `FST_DEBUG_PROFILE=<accountId>:<name>` (in-memory only); `FST_DEBUG_ANONYMOUS=1`; `FST_DEBUG_DRAWER=1`; `FST_DEBUG_SHEET=profile|notifications`; `FST_DEBUG_FIRST_RUN=off|on|force`; `FST_DEBUG_WHATS_NEW=off|on|fresh|force` ([What's New](../controls/whats-new/android.md)); `FST_DEBUG_DISTRIBUTION=store|play|tester|testflight`; `FST_DEBUG_FORCE_FREEZE=1`; `FST_DEBUG_STILL_BACKGROUND=1`; `FST_DEBUG_SEARCH=<text>` with `FST_DEBUG_SEARCH_SCOPE=songs|players|bands`; and `FST_ORIGIN`.

## Android SDK on `sfenton-music`

SDK root: `C:/Users/sfent/AppData/Local/Android/Sdk`; JDK: Temurin 17.0.20. Packages coexist; never uninstall or downgrade another lane's SDK.

| Package | Version / rule |
|---|---|
| Emulator | 37.1.11 |
| Acceleration | WHPX requires UEFI AMD SVM. Both were enabled 2026-10-03; `emulator -accel-check` reports usable and headless `device.py boot FST_Phone` takes about a minute. Without it, x86_64 emulation fails; builds/JVM tests do not |
| Platform-tools | 37.0.1 |
| cmdline-tools | 23.0 beside `latest` 20.0. `sdkmanager` 23 emits a deprecation notice and exits 9 on success; use `--package_file=` because its `.bat` splits `;` |
| Platforms / build-tools | android-36, android-37.0, android-37.2; 35.0.0, 36.0.0, 36.1.0, 37.0.0 |
| System images | `android-37.2;google_apis_ps16k;x86_64` for FST AVDs, `android-37.0;google_apis;x86_64` 4 KB fallback, and legacy API 36 images |

The committed Gradle wrapper is 8.14.3; AGP 8.11, Kotlin 2.2.10, compile/target SDK 36, min SDK 26.

## FST AVD matrix

Create deterministically with `python tools/android/device.py avds --create [--force] [--only NAME]`; `AVDS` in `device.py` is authoritative. All use API 37.2, cold boot headless with `-no-snapshot -no-window -gpu swiftshader_indirect`, and set animation scales to 0 unless `--animations` is supplied. The tool never manages legacy `Pixel_5_API_36` or `Pixel_9_Pro_Fold`.

| AVD | Profile | Inner (px @ dpi) | Posture support |
|---|---|---|---|
| `FST_Phone` | `pixel_9` | 1080x2424 @ 420 | none |
| `FST_Book_Fold` | `pixel_9_pro_fold` | 2076x2152 @ 390; cover 1080x2424 | `folded`/`half`/`unfolded`; real CLOSED/HALF_OPENED/OPENED, fold x=1038 reports FLAT/HALF |
| `FST_Passport_Fold` | `pixel_fold` | 2208x1840 @ 420; cover 1080x2092 | same, fold x=1104 |
| `FST_TriFold` | custom `fst_trifold` | 2160x1584 @ 320 | `folded`/`partial`/`unfolded` or `180,0`; no half-open |
| `FST_Tablet` | `pixel_tablet` | 2560x1600 @ 320 | none |
| `FST_Resizable` | `resizable` | 1080x2400 @ 420 | `phone`/`foldable`/`tablet`/`desktop` presets |

All boot in about 20-60 seconds. Verify each claimed fold with `device.py features --avd <AVD> <postures...>`; its Gradle-free `tools/android/probe` subscribes to on-device `androidx.window.extensions` and prints window sizes plus `FoldingFeature`.

### Tri-fold and resizable emulation

No official tri-fold profile exists in emulator 37.1/cmdline-tools 23. `FST_TriFold` models three 720x1584 panels with hinges at x=720 and x=1440 (`hw.sensor.hinge.count=2`). It reports windows 720x1584 folded (360x792 dp), 1440x1584 partial (one FLAT hinge) and 2160x1584 unfolded (two FLAT hinges), and supports `adb emu sensor set hinge-angle0/1`. Device state remains `DEFAULT`; it cannot test `DeviceStateManager`, rear display, HALF_OPENED or real display switching. API 37 only switches inner/outer displays for known Pixels, so the tool uses `wm size` plus `display_features`; region 0.1 is a permanently-on cover display and apps launch on display 0. A missing region can hang or crash boot.

`adb emu resize-display` is a no-op on emulator 37.1. `device.py posture <preset> --avd FST_Resizable` applies `wm size`/density from `hw.resizable.configs`: phone 1080x2400 @ 420, foldable 2208x1840 @ 420 with one fold, tablet 1920x1200 @ 240 and desktop 1920x1080 @ 160. Each overrides the image's built-in fold, so tablet and desktop report none.

## Tooling

| Command (repo root) | Does |
|---|---|
| `python tools/android/fst_android.py build [--tests] [--coverage] [--release]` | Gradle build, JVM/Robolectric tests and JaCoCo summary |
| `python tools/android/fst_android.py coverage --min-logic 95 [--files]` | JaCoCo logic/UI gate |
| `python tools/android/licenses.py [--check]` | Regenerate or verify `assets/licenses.json`; run on dependency changes ([licenses](../pages/licenses/android.md)) |
| `python tools/android/fst_android.py session --avd FST_Phone "out.png\|posture\|wait\|KEY=V,KEY=V" ...` | Install and capture all shots in one lock hold |
| `python tools/android/search_journey.py [phone book-fold ...]` | Fixture-backed global-search/shell journeys; requires fixture `/api/bands/search`, never production |
| `python tools/android/talkback_walk.py --avd ... --route ... --name ... --out ...` | Real TalkBack walk ([testing](../testing/android.md#accessibility-tooling)) |
| `python tools/android/frame_stats.py --avd ... --steps "swipe:up;..." --name ... --out ...` | `gfxinfo framestats` timing ([performance](#performance)) |
| `python tools/android/fst_android.py device <install\|shot\|launch\|drive\|posture\|features\|list> ...` | Forward to FIFO-locked `tools/android/device.py` |

Prefer `session`: separate install and capture can lose the freshly booted app; take a warm-up shot before judging a cold boot's transient offline state. Keep live-data/art screenshots only as gitignored `android/reports/screenshots/*.local.png` ([service safety](service-safety.md)).

### `tools/android/device.py`

| Command | Effect |
|---|---|
| `list` | Matrix, installed/running emulators, lock holder and queue |
| `avds [--create] [--force] [--only NAME]` | Show or recreate FST AVDs |
| `boot <AVD>` / `shutdown` | Exclusively boot an FST AVD, or power off only FST emulators and orphaned FST qemu |
| `posture <name\|angles\|preset> [--avd]` | Apply hinge posture or resizable preset |
| `install <apk>` | `adb install -r -t -g`; issue #190 retry uninstalls a newer/differently signed app. `drive --apk` and `launch --apk` share it; `test` uninstalls an app whose version code exceeds debug's `1` before Gradle installs |
| `launch [--tab] [--route] [--extra K=V] [--apk] [--posture]` | Fresh `am start -W -S --activity-clear-task --display 0` launch with `FST_*` extras; `--activity-clear-task` and one force-stop retry prevent stale intent delivery |
| `shot <out.png>... [--no-launch] [launch options]` | Launch and screenshot physical display 0 with JSON sidecar |
| `drive --steps "..." [--steps-file] [--launch]` | UIAutomator/`adb input` steps |
| `features [postures...]` | WindowManager `FoldingFeature`s |
| `test [pkg.Class[#m]\|package:pkg] [--task] [--posture] [--runner-arg K=V]...` | Connected test with pinned `ANDROID_SERIAL`; runner arguments reproduce `android-fold` annotation and hinge requirement |

Common options: `--avd` defaults to `FST_Phone`; `--hold` is at most 300 seconds; `--wait-timeout`, `--window`, `--allow-foreign` and `--animations` apply. `--animations` only preserves existing scales: set all three animation scales to 1 and relaunch before motion evidence (issue #149). Exit 3 means device/usage error; 124 means lock timeout. Drive accepts `tap:`/`longpress:`/`waitfor:`, swipe, `type:`, `key:`, `back`, `home`, `wait:`, `rotate:`, `shot:`, `tree:`, `posture:`, `resize:`, TalkBack/font/dark toggles, bounded `record:`/`record:stop`, `logcat:` and device `shell:` commands. In Git Bash, use `C:/...` paths inside `--steps`; MSYS transforms only whole arguments. Compose test tags need `testTagsAsResourceId`, and `input tap` explores rather than activates under TalkBack.

| Drive step | Meaning |
|---|---|
| `tap:`/`longpress:`/`waitfor:<sel>[@secs]` | `sel` is `id=<resource-id or testTag>`, `text=`, `desc=`, `contains=`, or `x,y` |
| `swipe:up\|down\|left\|right` or `swipe:x1,y1,x2,y2[,ms]` | Finger direction |
| `type:<text>`, `key:<name\|KEYCODE_...>`, `back`, `home`, `wait:<s>`, `rotate:0\|90\|180\|270` | Input |
| `shot:<png>`, `tree:<xml>` | Screenshot plus sidecar; UIAutomator dump |
| `posture:<p>`, `resize:<preset>` | Fold posture or resizable preset |
| `talkback:on\|off`, `fontscale:<0.5-2>`, `dark:on\|off` | Accessibility state |
| `record:<mp4>` ... `record:stop` | Start/stop and pull an at-most-180-second screen recording; unfinished recordings stop and pull when the drive ends |
| `logcat:clear`, `logcat:<file>[@TAG]` | Clear or dump logcat, optionally one tag such as `FST_A11Y` |
| `shell:<command>` | One shell command on the FST emulator, such as TalkBack notification permission setup |

`rotate:` did not rotate `FST_Phone` in issue #111; use `shell:wm user-rotation lock 1` and restore lock 0. Named swipes retain portrait coordinates after rotation (issue #176), so use explicit landscape coordinates such as `swipe:1000,660,1000,380,500`.

## Emulator lock

- Use one product emulator per host through `tools/android/hostlock.py`: its OS byte-range lock, FIFO queue and `holder.json` serialize every lane.
- Holds end at 300 seconds; waiters default to 1800 seconds. The watchdog kills tracked children, releases the lock and exits 124.
- FST emulators use port 5580. Only `FST_*` or its port holder can be stopped; another emulator makes `boot` fail with exit 3.
- Shutdown runs `sync`, `reboot -p`, `emu kill`, then targets leftover qemu. A hard kill can lose `/data`; install and capture with `--apk` in one hold.
- Every lane installs the same app package. Always pass `--apk` for evidence: without it, a stale build can run (issue #149). Logs are `~/.fst-locks/emulator-<AVD>.log`.

## Device and accessibility rules

- One emulator per host, through `device.py` only. Never launch legacy AVDs while hosts are shared; headless `-gpu auto` in session 0 wedged adb shell, so the tool uses SwiftShader.
- `FestivalModalSheet`, `DialogHinge` and full-page service status use the single `HingeSide` rule in `core/nav/HingeSide.kt`: keep a separating hinge's wider/leading book side or the lower tabletop side; flat/non-separating hinges remain centered (issues #125, #126, #140; [modal-shell](../patterns/modal-shell.md) R8). Never create another side rule.
- `FestivalShell` keeps the NavHost in one `ModalNavigationDrawer` parent across permanent drawer/rail/modal changes to preserve scroll, sheets and Back priority (issues #106, #122, #126; [app navigation](../controls/app-navigation/android.md)).
- Compact height is under 480 dp; put live-sheet Reset beside Close so 200% text cannot shrink the pinned form. Sheet drag handles and row trailing buttons need explicit 48 dp targets; toolbar buttons retain 48x48 touch bounds even when their visuals are 40 dp (issues #72, #179).
- Lists/grids flow around a separating vertical hinge. `ShopColumnPolicy` leaves the gap; switch to one column under TalkBack or large text (issue #131). `ProvideFoldLane`/`FoldLane` keeps full-line headers and messages in the leading pane without reload (issue #343; [section headers](../patterns/section-headers.md) R10 and `android-fold-lane`).

## Performance

Use the release-like, debug-signed `benchmark` build with `--large-catalogue --large-rankings`, animations enabled and `tools/android/frame_stats.py`; do not judge jank from debug builds, which measured about 2x slower. SwiftShader total timings (30-85 ms) are host-CPU artifacts; use UI-thread `HandleInputStart` to `SyncQueued` timing. Last measured 2026-09-29:

| Scenario | Device | Frames | UI p50 / p90 / p99 ms | UI > 8.33 ms | Composition / layout / draw p90 ms |
|---|---|---:|---|---|---|
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

- Idle animation uses draw-phase `graphicsLayer`, `drawBehind` and `basicMarquee`, not per-frame row recomposition. Decode bundled bitmaps once and use `ChipGrid`; neither measured outside emulator noise.
- Issue #155 moved catalogue refresh decode off main after a 676 ms fling/pull-to-refresh gap. Issue #83 samples decorative backdrop at 30 fps and holds it while a modal is open. Issue #186 requires all decorative loops to hold when `coveredByModal()`; live service-progress indicators remain intentionally animated.
- Open: profile real-device Compose tracing with `runtime-tracing`, and a Macrobenchmark module when a lab can exceed the 300-second lock.
