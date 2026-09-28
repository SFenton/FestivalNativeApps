# XCUITest device journeys

> **What:** running device UI tests and the XCUITest pitfalls already paid for. **Read when:** the UX-test phase of a feature (UITests are frozen during Wave 1), or debugging a flaky journey.

## Running journeys

```bash
python3 tools/ios_sim.py uitest --only ShellJourneyTests --only LeaderboardsJourneyTests/testOne
```

Builds once (skipping if the compiled product's source hash is already current),
then runs the given `Class`/`Class/testMethod` selectors in bounded batches
(default 3 selectors per `xcodebuild test-without-building` call, `--timeout`
seconds each, 300 default), fully releasing `~/.fst-sim.lock` between batches
so other lanes queued on the shared simulator aren't starved by one long run
(the 5-minute lock-hold rule). Any journey file placed under
`apple/Apps/iOSUITests/` is picked up by the next build with no tool changes —
see `cmd_uitest`'s docstring in `tools/ios_sim.py` for the full contract.
`tools/ios_sim.py drive` runs one scripted `DriverTests/testDrive` step
sequence instead of a written `XCTestCase`, useful for ad hoc exploration
before writing a real journey.

### Retired: `tools/apple_native_matrix.py` (removed 2026-09-28)

The old serial two-device (iPhone+iPad) matrix runner assumed exactly one
canonical UI test source file (`FestivalMobileUITests.swift`) to discover,
count and hash every test method from. Lane U2's Wave 3 triage split that
monolith into per-feature journey files (`SongsJourneyTests.swift`,
`RivalsJourneyTests.swift`, …) under the same `apple/Apps/iOSUITests/`
directory, which the matrix runner never scanned — so by the time this was
noticed, its own tests were asserting stale counts/content against a file
that had shrunk from ~54 methods to ~13, and running it for real would have
silently omitted every migrated test from a "paired" coverage measurement.
No lane's actual work (see `PROGRESS.md`'s log) had called it since; only this
doc mentioned it. Confirmed unused elsewhere (`grep -rl apple_native_matrix`
matched only the tool, its test and this file) and deleted rather than
generalized to multi-file discovery, since `tools/ios_sim.py uitest` already
covers its real job today. A genuine iPhone+iPad **paired** `apple_xccov_gate.py`
measurement now means running `uitest`/`drive` once per device and feeding
both `.xcresult` bundles to the gate — no single combined command yet.

## Pitfalls

| Symptom | Rule |
|---|---|
| Test "passed" but new screenshot missing | A matching method name does not prove the new body ran; rely on the source-hash marker |
| Zero-test result from a green Xcode process | Treat as failure; clean only that product's DerivedData |
| Row query disappears after a swipe | Lists virtualize: query the stable `fst.songs.list`, not `CollectionView containing <row>` |
| Element `isHittable` but partly behind the tab | Assert the whole element/group frame lies inside the List viewport and above the system tab |
| Full swipes skip a narrow row | Use small in-list drags |
| Programmatic tap on an offscreen action stalls the main thread | Real swipe first, or place the action where it is visible (Song Detail's View Full sits above its rows for this reason) |
| Settings toggle "missing" | Settings keeps its Form scroll position across tabs: try the reverse swipe before failing |
| Saved Sort changes a visual fixture | Pin Sort to Title per launch via launch arguments; never erase the user's saved preference |
| Identity leaks between tests | Every `XCUIApplication` comes from the shared helper that sets `FST_UI_TEST_CLEAR_PROFILE=1`; only the explicit cold-relaunch test removes it |
| iPad grouped-header frames span both panes | Measure visible text at the detail pane's X; focus bounds stay unverified |
| Main-thread hang after a split-view toggle | Sample the app PID; compare against a clean baseline worktree before blaming the test |
