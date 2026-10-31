# UIKit port performance

> **What:** how the SwiftUI app and its UIKit port are measured A/B on simulators (frame rate, hitches, main-thread cost, CPU, GPU, memory, cold launch, navigation), how to run it, how to read the tables and the last measured numbers. **Read when:** running `tools/uikit_perf.py` or judging a port change's cost.

The method is the one Fenton-HASS-Native used for its UIKit port (owner request, 2026-10-31), rebuilt for FST. Both apps run the same session, loaders, routes and fixtures, so a difference between the rows of one table is the cost of the view layer.

## Method

Per surface, per round, per app (the app order alternates each round so neither always runs first):

1. **Fresh install** (`simctl uninstall` then `install`), so no cache, stored profile or setting is carried over.
2. **Launch** with `SIMCTL_CHILD_` environment that opens the surface (`FST_DEBUG_TAB`, `FST_DEBUG_ROUTE`, `FST_DEBUG_PROFILE`, `FST_DEBUG_SONG` … from `tools/uikit-perf-surfaces.txt`), points the app at the fixture service (`FST_API_BASE_URL`, `tools/mock_service.py --large-catalogue --large-rankings`, started and stopped by the tool) and asks the app to measure itself (`FST_PERF_AUTORUN=<settle s>`).
3. **In-app autorun** ([`Diagnostics/ScrollCostAutorun.swift`](../../../apple/Sources/FestivalUI/Diagnostics/ScrollCostAutorun.swift)): after the settle time it writes the *launch* line, then **8 s idle** and **two 8 s scrolls at 900 pt/s**. The scroll is a `CADisplayLink` setting the front scroll view's content offset each frame (`ScrollCostDriver`, up and down, back to the resting top inset every pass so a large title collapses and expands), so no XCUITest swipe or accessibility snapshot is in the number. The code finds the scroll view in the key window and needs no SwiftUI view or UIKit controller, so the same code measures both apps; `FestivalMobileApp.init` starts it for the SwiftUI app and `UKApp.didFinishLaunching` for the port.
4. **Probes** over each run: `FramePacer` (display-link frames per second, dropped frames, hitch ms per second, `phys_footprint` now and peak) and `MainThreadCostMeter` (main-thread CPU, process CPU, run-loop turns over 4/8/16 ms, worst and p95 turn; `ProcessCPU` reads `proc_pid_rusage`).
5. **Host sampler** (`tools/perf_sampler.py`, 4 Hz): the Mac GPU's utilisation (IOAccelerator; the simulator renders on the Mac GPU, so this is its only GPU signal), the simulator render server's (`backboardd`) cumulative CPU, and the app process's CPU and RSS. The report matches the samples to each run's `t0`/`t1` wall-clock window.
6. **Navigation scenarios** (`[nav]` section, `FST_PERF_NAV=<route tokens separated by ;>`): instead of scrolling, the app pushes the route and pops it `FST_PERF_NAV_CYCLES` (default 6) times through hooks each root registers (`PerfNavigationHooks`: the SwiftUI root's `paths`, the port's `UKNavigating`), watching the front `UINavigationController` (a `NavigationStack` is one) with the same rule in both apps.

Measure with **optimized code**: `uikit_perf.py` builds both schemes as `Release` with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG` (the `apple_perf.py --probe` flavour: `-O`, whole module, Debug launch overrides and probes compiled in) into `apple/DerivedData/perf-probe`. A true Release build ignores every `FST_DEBUG_*`/`FST_PERF_*` key; never ship the probe build. The autorun is `#if DEBUG`, so it cannot run in a store build.

### Definitions

| Term | Meaning |
|---|---|
| **first content** | Milliseconds from the process's start (`kern.proc.pid` start time) to the first display frame on which the key window's front vertical scroll view shows content: at least three rows for a list or collection view, content taller than 300 pt for any other scroll view. Spinners and placeholders do not count. A page may call `FirstContentProbe.markFirstContent()` to declare it itself; the earlier of the two wins. `-1` = never seen (a placeholder page has no scroll view) |
| **launch code ms** | Process start to `startIfRequested` (pre-main, runtime and `App.init`/app-delegate time; a floor shared by both apps) |
| **push / pop first** | Milliseconds from the call to the first display frame on which the stack has changed and the new top page's view is in the window |
| **push / pop settled** | Milliseconds until the stack's transition coordinator is gone (animation finished) |
| **cold first** | The first cycle's first-frame time; the percentiles use the remaining cycles |
| **main p95 / turns >8 ms** | A run-loop turn is one wake-to-sleep of the main run loop; over 8 ms of main-thread CPU in a turn is a missed 120 Hz frame whatever the display link says |

## Surfaces

`tools/uikit-perf-surfaces.txt` (`Name|ENV=value …`): Songs (long list), Song Detail, Song Leaderboard, Leaderboards, Full Rankings, Player Profile, Statistics, Rivals, Suggestions, Settings, Shop, Global Search, plus `[nav]` scenarios (push Leaderboards, Shop, Full Rankings, Player Profile, a Settings topic). Data are the fixtures (`fixture-pulse`, `fixture-player-1`, a 108-song padded catalogue, 1,200-account rankings). `--live` uses the keyless public service for read-only GETs the allowlist permits ([service-safety](../../platforms/service-safety.md)); never anything it blocks. A page the UIKit port has not built yet is a placeholder: its row reads `no scroll view: …` (n = 0), which is a gap, not a pass.

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

Results: `apple/build/perf/<label>/` (`r<round>-<app>-<surface>.tsv` from the app, `….samples.tsv` from the sampler, `report.md`). Do not run it while other simulator work is active on the Mac: GPU and CPU numbers share the host. The `duo` family needs the iPhone Duo simulator in the pose you want measured (`tools/ios_sim.py pose`).

## Reading the tables

Medians over rounds (`n` = runs behind the cell; a scroll cell has two runs per round).

- **Scroll and idle:** `fps`/`dropped frames`/`hitch ms/s` are the display link (the simulator's 60 Hz); `main p95 ms`, `turns >8 ms`, `main CPU ms` and `process CPU ms` are the stable signals (CPU instructions do not move with other work on the Mac). Subtract the **idle** row from the **scroll** row of the same app for the cost of scrolling. `render server CPU ms` is `backboardd` compositing the layer tree; `Mac GPU %` is the host GPU during the window; `memory MB`/`peak MB` are `phys_footprint`.
- **Cold launch:** `first content ms` (lower is better) with the CPU, instructions and memory the process had used at the end of the settle time.
- **Navigation:** first-frame and settled percentiles in ms, and the main thread's turn costs while pushing/popping.

`render server CPU ms` comes from `ps` TIME deltas of `backboardd` (coarse, often 0 for an idle run) and `Mac GPU %` is blank when `ioreg` returned no reading in the window; compare scroll minus idle over several rounds, not single cells. A difference smaller than the spread between rounds is noise; rerun with more rounds before reading it. The simulator's frame rate says little; trust CPU, turns over 8 ms, render-server CPU and memory first.

## Pure-logic tests

`apple/Tests/FestivalUITests/PerfProbeTests.swift` (report math, percentiles, `HitchTally`, config parsing, result lines) and `tools/tests/test_uikit_perf.py` (surfaces file, run plan, launch environment, sampler and report parsing, table rendering).

## Last measured

| Date | Family | Scope | Result |
|---|---|---|---|
| 2026-10-31 | iPhone (FST iOS 26.5 iPhone 17 Pro) | Smoke: Songs (long list) and Settings, 1 round, fixtures, optimized probe builds. UIKit pages are still placeholders (no scroll view, first content -1); the idle rows and launch CPU/memory are the empty shell's | Pipeline proven end to end. SwiftUI Songs scroll: 52 fps, 59 dropped frames, main p95 21 ms, 170 turns over 8 ms, 4.3 s main CPU per 16 s of scrolling, first content 2.8 s; SwiftUI Settings scroll: main p95 2.1 ms, 0 turns over 8 ms; SwiftUI idle main CPU 100-106 ms vs UIKit shell 50-60 ms |
| 2026-10-31 | iPhone | Smoke navigation: push Leaderboards from Songs, 6 cycles, 1 round | Both apps push and pop through the shared hooks. First frame p50: SwiftUI 203 ms push / 234 ms pop, UIKit 22 / 24 ms (the port's page is still a placeholder); settled 684 vs 500 ms |
