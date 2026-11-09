# UIKit port performance

> **What:** matched SwiftUI/UIKit simulator and physical-iOS measurements, their instrumentation boundaries and qualification gates. **Read when:** running `tools/uikit_perf.py`, `tools/uikit_perf_device.py` or judging a port change's cost.

The method is the one Fenton-HASS-Native used for its UIKit port (owner request, 2026-10-31), rebuilt for FST. Both apps run the same session, loaders, routes and fixtures, so a difference between the rows of one table is the cost of the view layer.

## Method

Per manifest case, per round, per app (the app order alternates each round so neither always runs first):

1. **Fresh install** (`simctl uninstall` then `install`), so no cache, stored profile or setting is carried over.
2. **Launch** with `SIMCTL_CHILD_` environment that opens the surface (`FST_DEBUG_TAB`, `FST_DEBUG_ROUTE`, `FST_DEBUG_PROFILE`, `FST_DEBUG_SONG` … from `tools/uikit-perf-surfaces.txt`), points the app at the fixture service (`FST_API_BASE_URL`, `tools/mock_service.py --large-catalogue --large-rankings`, started and stopped by the tool) and asks the app to measure itself (`FST_PERF_AUTORUN=<settle s>`).
3. **In-app autorun** ([`Diagnostics/ScrollCostAutorun.swift`](../../../apple/Sources/FestivalUI/Diagnostics/ScrollCostAutorun.swift)): after the settle time it writes the *launch* line, then **8 s idle** and **two 8 s scrolls at 900 pt/s**. The scroll is a `CADisplayLink` setting the front scroll view's content offset each frame (`ScrollCostDriver`, up and down, back to the resting top inset every pass so a large title collapses and expands), so no XCUITest swipe or accessibility snapshot is in the number. The code finds the scroll view in the key window and needs no SwiftUI view or UIKit controller, so the same code measures both apps; `FestivalMobileApp.init` starts it for the SwiftUI app and `UKApp.didFinishLaunching` for the port.
4. **Probes** over each run: `FramePacer` (display-link frames per second, dropped frames, hitch ms per second, `phys_footprint` now and peak) and `MainThreadCostMeter` (main-thread CPU, process CPU, run-loop turns over 4/8/16 ms, worst and p95 turn; `ProcessCPU` reads `proc_pid_rusage`).
5. **Host sampler** (`tools/perf_sampler.py`, 4 Hz): the Mac GPU's utilisation (IOAccelerator; the simulator renders on the Mac GPU, so this is its only GPU signal), the simulator render server's (`backboardd`) cumulative CPU, and the app process's CPU and RSS. The report matches the samples to each run's `t0`/`t1` wall-clock window.
6. **Navigation scenarios** (`[nav]` section, `FST_PERF_NAV=<route tokens separated by ;>`): instead of scrolling, the app pushes the route and pops it `FST_PERF_NAV_CYCLES` (default 6) times through hooks each root registers (`PerfNavigationHooks`: the SwiftUI root's `paths`, the port's `UKNavigating`), watching the front `UINavigationController` (a `NavigationStack` is one) with the same rule in both apps.
7. **Modal/task and component cases** (`[modal]` / `[components]`): the same first-frame/settled timing is driven through the narrow DEBUG seams in `PerfNavigationHooks`. Missing hooks produce an explicit incomplete case, never a zero-sample pass.
The first-run carousel component case presents the existing Settings guide through its canonical presentation owner, advances the visible native page through real paging completion, and stops through the normal dismissal completion; presentation alone is not readiness.
8. **No-scroll cases** (`FST_PERF_MODE=latency`): valid pages such as Shop, Global Search, Settings topic pages, Licenses, Bands landing, All Rivals, and Rivalry record launch content status plus a timed CPU/memory interval; they are not coerced into `n=0` scroll results. These pages explicitly mark their canonical loaded body in both SwiftUI and UIKit, so latency mode never hides a failed route or placeholder. All Rivals and Rivalry use finite fixture bodies whose measured adjusted scroll range is zero in the supported viewport; their latency results describe loaded-body first content and timed cost, not long-list scrolling throughput.

Measure with **optimized code**: `uikit_perf.py` builds both schemes as `Release` with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` (the `apple_perf.py --probe` flavour: `-O`, whole module, Debug launch overrides and probes compiled in) into `apple/DerivedData/perf-probe`. A true Release build ignores every `FST_DEBUG_*`/`FST_PERF_*` key; never ship the probe build. The autorun is `#if DEBUG`, so it cannot run in a store build.

The runner writes `manifest.json` beside every raw result. It records the exact source commit/dirty state, tool and surface-file digests, fixture mode, simulator UDID, build family, and case inventory. `uikit_perf_report.py` applies a hard qualification gate: three alternating rounds, one completed launch per case/app/round, real first content (not a spinner/placeholder/blank shell), all expected idle/scroll or open/close events, and at least three warm samples for latency families. `--allow-incomplete` is for smoke diagnostics only and must not be used for a comparison claim.

### Definitions

| Term | Meaning |
|---|---|
| **first content** | Milliseconds from the process's start (`kern.proc.pid` start time) to the first display frame on which the key window's front vertical scroll view shows content: at least three rows for a list or collection view, content taller than 300 pt for any other scroll view. Spinners and placeholders do not count. A page may call `FirstContentProbe.markFirstContent(rows:)` after attaching its real loaded body when the generic heuristic cannot identify the rows; the reported count is the actual loaded-body count and the front scroll view supplies the measured height. Failed, loading and empty states must not mark content. `-1` = never seen (a placeholder page has no scroll view) |
| **launch code ms** | Process start to `startIfRequested` (pre-main, runtime and `App.init`/app-delegate time; a floor shared by both apps) |
| **push / pop first** | Milliseconds from the call to the first display frame on which the stack has changed and the new top page's view is in the window |
| **push / pop settled** | Milliseconds until the stack's transition coordinator is gone (animation finished) |
| **cold first** | The first cycle's first-frame time; the percentiles use the remaining cycles |
| **main p95 / turns >8 ms** | A run-loop turn is one wake-to-sleep of the main run loop; over 8 ms of main-thread CPU in a turn is a missed 120 Hz frame whatever the display link says |

## Surfaces

`tools/uikit-perf-surfaces.txt` (`Name|ENV=value …`) covers the twelve landing pages, Player History/Bands, Bands and Band Detail, Song Band Leaderboard, instrument/combo/Band Rankings, Compete, Rivals/All Rivals/Rival Detail/Rivalry, Licenses, every Settings topic family, `[nav]` page pushes, `[modal]` task/sheet open-close, and `[components]` shared animation classes. Data are the fixtures (`fixture-pulse`, `fixture-player-1`, `fixture-band-1`, rival `f1c749…`, a 108-song padded catalogue, 1,200-account rankings). Cases that share a controller are named separately with their route token; none are silently omitted. `--live` uses the keyless public service for read-only GETs the allowlist permits ([service-safety](../../platforms/service-safety.md)); never anything it blocks. A page the UIKit port has not built yet is an incomplete case: in scroll mode, `no scroll view: …`, a missing content marker, a placeholder, or an unexecuted event cannot qualify. Declared latency-mode cases may legitimately have no scroller, but still require their canonical loaded-content marker and timed latency samples in both apps; a missing marker or failed/loading body remains incomplete.

## Commands

```bash
# Full A/B, one family at a time (each takes the simulator lock and a devcap slot; builds under the build lock)
python3 tools/uikit_perf.py --family iphone --rounds 3 --label iphone-final
python3 tools/uikit_perf.py --family ipad   --rounds 3 --label ipad-final
python3 tools/uikit_perf.py --family duo    --rounds 3 --label duo-final

# A subset, one app, without rebuilding
python3 tools/uikit_perf.py --family iphone --only "Songs (long list),Settings" --apps uikit --rounds 1 --no-build

# Re-print the tables of a finished run
python3 tools/uikit_perf.py --report apple/build/perf/<label>
python3 tools/uikit_perf_report.py apple/build/perf/<label> --csv apple/build/perf/<label>/report.csv
```

Results: `apple/build/perf/<label>/` (`manifest.json`, `r<round>-<app>-<surface>.tsv` from the app, `….samples.tsv` from the sampler, `report.md`). The sampler declares unavailable GPU readings as missing; it never converts them to zero. Do not claim matched idle-host GPU results while another simulator workload is active on the Mac; per-process CPU/memory may still be retained with that limitation explicitly reported. The `duo` family needs the iPhone Duo simulator in the pose you want measured (`tools/ios_sim.py pose`).

### Three-arm before/after/reference runs

For a real comparison, keep the frozen412 UIKit bundle, final candidate UIKit bundle, and SwiftUI reference bundle in separate Release-probe worktrees/DerivedData. Pass them as explicit arms; the runner rotates the first arm each round and records each bundle digest:

```bash
python3 tools/uikit_perf.py --family iphone --udid <owned-udid> --no-build --rounds 3 \
  --apps uikit-before,uikit-after,swiftui-reference \
  --app-bundle 'uikit-before|/validation/frozen412/FestivalMobileUIKit.app|com.sfenton.festivalscoretracker.native.uikit|FestivalMobileUIKit' \
  --app-bundle 'uikit-after|/validation/final/FestivalMobileUIKit.app|com.sfenton.festivalscoretracker.native.uikit|FestivalMobileUIKit' \
  --app-bundle 'swiftui-reference|/validation/final/FestivalMobile.app|com.sfenton.festivalscoretracker.native|FestivalMobile' \
  --label iphone-three-arm
```

`--app-bundle` never builds or mutates those worktrees; it requires absolute `.app` paths and `--no-build`. A three-arm result is not an improvement claim until all arms use the same fixture, runtime/device, probe source digest, and qualified case inventory. Separate before datasets collected on different days are context only, not a matched before/after claim.

For the marquee component case, add `--long-titles` to all three arms' command so the loopback fixture supplies the same overflowing `fixture-pulse` content. Its manifest also sets `FST_DEBUG_SONG=fixture-pulse`, causing both roots' existing Songs debug path to push the real song-detail/header renderer before the shared marquee request; the hook waits for actual marquee activity rather than treating a fitting label as animation.

If Marquee does not settle, the DEBUG component failure includes aggregate renderer count, measured overflow and visibility counts, Reduce Motion and active-scene counts, animation registrations, renderer classes, the requested debug route, and maximum canonical text length, measured text width, and viewport width. This is diagnostic evidence only; it does not qualify readiness or extend the settle deadline. The report parser retains such failure lines as error rows rather than metric samples.

The modal/component hooks must be registered after the existing base navigation registration (which clears optional hooks) at `FestivalRootView.swift`'s DEBUG `.onAppear` and `UIKitPort/App/UKApp.swift`'s DEBUG root setup:

```swift
PerfNavigationHooks.register(
    presentModal: { token in /* parent-owned token dispatch */ },
    dismissModal: { /* dismiss current task/sheet */ },
    startComponent: { token in /* parent-owned animation dispatch */ },
    stopComponent: { /* restore the prior component state */ },
    componentIsReady: { /* visible + settled state */ true }
)
```

The exact token inventory is in `tools/uikit-perf-surfaces.txt`. Until both roots register these seams, those cases remain explicit instrumentation gaps rather than supported zero-sample measurements.

## Physical iOS

`tools/uikit_perf_device.py` reuses the case inventory, optimized probes and report math, not `simctl` or the Mac sampler. Build both schemes from identical source/SDK with the same Release-probe condition and product-owned signing; retain a matching source/bundle-digest receipt. Use only `com.sfenton.festivalscoretracker.perf.swiftui` and `.perf.uikit`: fresh installs/reset knobs must never touch the normal SwiftUI/UIKit identities.

Export immutable synthetic responses with `python3 tools/uikit_perf_device.py export --output <archive.json>`. `--request` / `--requests-file` extend the finite relative-GET inventory from the same owned large publication-7 mock. State-changing fixture controls and external origins are rejected. This is replay, not a complete dynamic mock: an unrecorded request makes the trial incomplete and is retained in `*-missing-requests.txt` for a new frozen archive. Smoke the selected inventory before expensive repeated trials; never modify an archive or signed bundle mid-series.

The DEBUG-only `PhysicalPerfFixture` starts before client creation, binds **127.0.0.1 on the phone**, and reads the archive copied into its dedicated Documents directory. Existing client origin/header/read gates remain unchanged. The Mac mock is never exposed on the LAN and the runner has no production option. Both arms include the same replay server; process CPU and memory include its cost, so physical values must not be compared directly with external-server simulator values.

```bash
python3 tools/uikit_perf_device.py run --device <physical-udid> \
  --app 'swiftui|<absolute-FestivalMobile.app>|com.sfenton.festivalscoretracker.perf.swiftui|FestivalMobile' \
  --app 'uikit|<absolute-FestivalMobileUIKit.app>|com.sfenton.festivalscoretracker.perf.uikit|FestivalMobileUIKit' \
  --archive <archive.json> --build-receipt <receipt.json> --output <new-output-directory> --rounds 3
```

Each trial takes the exact physical-device capacity gate, fresh-installs one arm, copies the archive, queries the actual writable container, launches with `devicectl` environment JSON, copies the result back and terminates only its returned PID. A default 30-second inter-trial cooldown supplements mandatory nominal thermal/Low Power Mode checks at start/end. An unlocked, paired, Developer-Mode-enabled phone and usable signing are required; never bypass a device lock. The app temporarily suppresses its idle timer only during a physical trial, restoring the prior policy afterward.

Raw `context` records retain thermal/power state, maximum display capability and fixture reads/misses. The start record may have no scene yet (`maximum_hz=0`); the end record must expose the real scene's display capability. Actual display-link intervals, not an assumed 60/120 Hz, determine frame pacing. Missing context, warm/Low-Power runs, unrecorded reads, unexecuted cases and existing content/event/sample gaps cannot qualify. Device GPU counters and render-server CPU remain unavailable in this adapter; no Mac readings stand in for them.

## Reading the tables

Medians over rounds (`n` = runs behind the cell; a scroll cell has two runs per round).

- **Scroll and idle:** `fps`/`dropped frames`/`hitch ms/s` are the display link (the simulator's 60 Hz); `main p95 ms`, `turns >8 ms`, `main CPU ms` and `process CPU ms` are the stable signals (CPU instructions do not move with other work on the Mac). Subtract the **idle** row from the **scroll** row of the same app for the cost of scrolling. `render server CPU ms` is `backboardd` compositing the layer tree; `Mac GPU %` is the host GPU during the window; `memory MB`/`peak MB` are `phys_footprint`.
- **Cold launch:** `first content ms` (lower is better) with the CPU, instructions and memory the process had used at the end of the settle time.
- **Navigation:** first-frame and settled percentiles in ms, and the main thread's turn costs while pushing/popping.

`render server CPU ms` comes from `ps` TIME deltas of `backboardd` (coarse, often 0 for an idle run) and `Mac GPU %` is blank when `ioreg` returned no reading in the window; compare scroll minus idle over several rounds, not single cells. Tables include the observed range of the primary signal; a difference smaller than that spread is noise, not an improvement. The simulator's frame rate says little; trust CPU, turns over 8 ms, render-server CPU and memory first. Simulator GPU is a host signal, not an on-device GPU counter; unsupported GPU is a declared missing metric.

### Leaderboards memory diagnosis boundary

The source-bound content-parity diagnostic found **12 cards and 120 identical entry IDs in both arms**, with the same **nine instrument and three band settings** and no extra spotlight content. Settled content height was approximately **7,460 pt UIKit versus 7,508 pt SwiftUI**; the earlier **3,752 pt UIKit** reading was first-frame geometry, not missing content. A four-phase census counted **2,267 UIKit views and 2,647 layers**; SwiftUI's UIKit-host counts were not an equivalent whole-framework object graph (its reference path uses a lazy stack and different render ownership). The evidence supports eager native card graphs versus the reference's lazy content, and an actual n=3 footprint difference of approximately **80 MiB UIKit versus 55 MiB SwiftUI**, but does **not** prove a leak.

The first collection prototype reached approximately **32.7 MiB** but remained a rejected diagnostic n=1: approximately **55 FPS, 36 dropped frames, 76 ms/s hitch time, and 1,029 ms versus 549 ms main CPU per measured scroll interval**. It is not an accepted optimization or performance claim. A subsequent matched three-arm fitted-height probe (one round, diagnosis only) likewise remained a rejection: approximately **1,076 ms main CPU per eight-second scroll interval, 55 FPS, 37 dropped frames and 77.3 ms/s hitch time**, versus the current UIKit baseline at **442 ms, 59.8 FPS, 0 drops and 1.2 ms/s**. The fitting candidate remains rejected.

Bounded per-cell graph reconfiguration passed its actual hosted suite (**70 tests / 73 invocations**) and all **six original Leaderboards navigation/Quick Links journeys**, but its matched one-round comparison also failed the scroll-cost target. Baseline UIKit / graph / SwiftUI scroll values were **446 / 892 / 1452 ms main CPU per eight-second interval**, **59.9 / 56.3 / 54.2 FPS**, **0 / 27 / 44 drops**, **0 / 56.9 / 94.4 ms/s hitch time**, and **90.8 / 35.8 / 62.4 MiB**. First content was **2986 / 2275 / 3721 ms**. The memory and startup gains do not promote a candidate with approximately twice the baseline scroll CPU. The report remains incomplete because n=1 is below three alternating rounds; no n=3 run or optimization acceptance is claimed.

Two later public samples targeted the exact controlled simulator PID and byte-verified frozen graph executable during live warm-scroll phases. They observed collection layout/self-sizing and an app-owned Quick Links-to-root-chrome update path; row `arrange`/`setRows` frames were not observed in those samples. This supports a bounded next hypothesis, not a proven fix: update active-section state without reconstructing root chrome, while preserving the actual floating control's accessibility value and legacy notifications for non-opt-in owners. Intrusive sample-run timing is not benchmark evidence, and host GPU/render-server results remain non-idle-comparable.

Evidence: retained session artifacts `native-phone-qualified-a9c4-n3-report.md`, `native-phone-leaderboards-n3/`, `native-reuse-smoke-v1/`, `native-memory-fit-v3-n1/`, `native-memory-graph-v1-n1/`, `native-memory-graph-probe-v1-receipt.json`, `native-memory-graph-warm-profile-v2/`, and `native-card-scroll-stack-v1/`; these are evidence locations, not repository paths.

## Pure-logic tests

`apple/Tests/FestivalUITests/PerfProbeTests.swift` (report math, percentiles, `HitchTally`, config parsing, result lines) and `tools/tests/test_uikit_perf.py` (surfaces file, run plan, launch environment, sampler and report parsing, table rendering).

## Toolchain parity and runtime readiness

Matched arms must use the same pinned Xcode build and SDK, not merely the same
source and optimization flags. Retain each bundle's `DTXcodeBuild`, `DTSDKName`
and `DTSDKBuild` with its byte/source receipts. Rebuild all required source arms
under one toolchain before qualifying a comparison after an Xcode update; never
rewrite older bundle metadata or reinterpret an earlier measurement as a new run.

The retained a9 UIKit/SwiftUI, fitted-height, graph and before412 probe bundles
record Xcode **27.1 (27A9269)** and **iphonesimulator27.1 (24A94403)**.
The host subsequently changed to Xcode **27.2 (27B52)**; the current unaccepted
Quick Links hosted build records **iphonesimulator27.2 (24B8118)**. Those are not
matched-toolchain arms.

Current simulator qualification is operator-gated: installed CoreSimulator
**1174.9.2** is older than required **1174.21.0**,
`xcodebuild -checkFirstLaunchStatus` returns **69**, and component installation
reports that authorization is required. Complete the host's approved Xcode
first-launch/component setup before resuming runtime validation. Do not recover
by restarting shared simulator services, changing security settings or silently
substituting another developer directory. Zero-test/destination failures from
this gate are not product-test results. Older qualified evidence retains its
original scope.

A subsequent simulator-free Release attempt could not start because the pinned
`/Applications/Xcode.app/Contents/Developer` directory was no longer present.
Restore that approved installation and complete its setup before either SDK
builds or runtime qualification resume; no alternate toolchain was selected.

## Last measured

| Date | Family | Scope | Result |
|---|---|---|---|
| 2026-11-09 | Clean `a9c4ddd10` current UIKit / SwiftUI; owned phone `8A85002F…`, iPhone 17 Pro model, iOS 27.0 | **54 active cases, three alternating rounds, 324 trials; QUALIFIED** | Songs scroll medians, SwiftUI / UIKit: main CPU **3342 / 883 ms per measured interval**, footprint **50.6 / 36.0 MiB**. Leaderboards footprint **55.0 / 80.0 MiB**; the source-bound content-parity diagnostic found 12 cards and 120 identical entry IDs, the same nine instrument and three band settings, no extra spotlight content, and settled heights approximately **7,460 / 7,508 pt** UIKit / SwiftUI. No retention repair is accepted yet. Host GPU/render-server values are not idle-host comparable. Exact source, bundles and raw records: `~/fp-validation/festival-native-qualified-a9c4/apple/build/perf/phone-qualified-a9c4-n3/`. Frozen412, Duo/iPad, current physical and full state/coverage gates remain separate. |
| 2026-11-05 | frozen412 / afterV17 / SwiftUI reference; exact owned phone `8A85002F…`, folded Duo `F01963C1…`, iPad `B03787B7…` | Three rotating rounds with the expanded case inventory; **incomplete** | Missing route content/scroll evidence and active modal/component records prevent an improvement claim. GPU/render-server values are non-idle-comparable. Raw artifacts and exact commands: `~/fp-validation/full-uikit-perf/artifact-index.json`. |
| 2026-11-08 | Physical iPhone 18 Pro, iOS 27.0.1, SDK 27.1; matching optimized probe-v2 builds and synthetic archive | **Songs primary case qualified**, three alternating rounds; full inventory not qualified | SwiftUI / UIKit medians: first content **1,158 / 155 ms**; scrolling main CPU **390.1 / 175.4 ms per elapsed second**; scrolling footprint **43.2 / 25.9 MiB**. Both sustain approximately 120 Hz. These compare the current app implementations, not an isolated framework swap; the shared replay server is included. Device GPU unavailable. Raw results, original/reassessed context and signed-source receipt: `~/fp-validation/iphone18pro-physical-perf/songs-three-round-v2/`. |
| 2026-11-08 | Current native-repair checkpoint; optimized SwiftUI/UIKit probes, 54 active cases | **108-trial n=1 smoke complete; not qualified** | The current v3+repairs hosted SDK build passes 65 tests / 68 invocations with 0 failures and 0 skips. The full 54-case inventory completed 108 trials with no timeout, missing-content, event or component errors; its sole hard gate is rounds=1<3. Explicit app/FestivalUI coverage collection is running separately; no archive or 95–90% coverage claim is made. Full n=3 simulator/physical, state/AX/pose and coverage qualification remain pending. macOS remains sidelined. |
