# XCUITest device journeys

> **What:** running device UI tests and the XCUITest pitfalls already paid for. **Read when:** the UX-test phase of a feature (UITests are frozen during Wave 1), or debugging a flaky journey.

## Serial matrix runner

```bash
python3 -m tools.apple_native_matrix --iphone-udid <FST-iPhone> --iphone-os 26.5 \
  --ipad-udid <FST-iPad> --ipad-os 26.5 --evidence-dir <new-private-dir>
# focused: add --device iphone --only-test <testMethod> --no-coverage-gate
```

- OS arguments are required and checked before anything starts (an iOS 27 device once entered a "26.5" run).
- Takes a host-wide lock, verifies FST device names/families, refuses other booted simulators, switches product devices one at a time, and starts fresh [fixture listeners](../fixtures.md) per suite (stopping only its own).
- Passes an explicit `-only-testing` selector for every discovered method (except the failing Duo pose test): Xcode once reported green while silently skipping a new test. Verifies the **exact executed test-name set**, counts and device identity, then runs the [line gate](coverage.md) unless `--no-coverage-gate`.
- Snapshots compiled Swift, UITest source, project/scheme, fixtures and gate inputs before the run and fails closed on drift. Records a SHA-256 of `FestivalMobileUITests.swift` per product DerivedData only after a verified pass; on drift it invalidates the marker **before** `xcodebuild clean` of that product's build output (never simulator data).
- Budget: 20 min minimum, 120 s per selected method, 90 min maximum. Incomplete `.xcresult` bundles (no `Info.plist`) are never aggregated.
- Xcode build logs are raw local evidence; do not share or commit them.

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
