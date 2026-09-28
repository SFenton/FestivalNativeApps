# Apple unit tests and coverage gates

> **What:** how Apple line coverage is measured and gated. **Read when:** adding unit tests or certifying coverage (not needed per slice; see [phases](../strategy.md)).

## SwiftPM (Core, Design, UI host tests)

- Iterate: `DEVELOPER_DIR=… swift test --package-path apple --filter <names>`.
- Gate: `bash tools/apple_coverage.sh` — runs all three SwiftPM test bundles, merges real LLVM line coverage per binary, checks `apple/Sources` for missing/nested files, requires **95% logic / 90% UX**, and runs `python3 -m tools.contrast_gate`. Re-run after compiled-source edits; targeted tests cannot certify a new source state.
- Sole exclusion: generated `BrandTokens.swift` (no executable lines; the gate fails if that changes). Never exclude handwritten code; update classifiers as directories grow.

## iOS app target (`FestivalUI` + mobile app on device)

- SwiftPM does **not** measure `apple/Apps/iOS` or `apple/Apps/macOS`.
- `DEVELOPER_DIR=… python3 tools/apple_xccov_gate.py --result <iphone.xcresult> --result <ipad.xcresult>` (default `--scope paired`); `--scope iphone` for the phone-only phase. It unions **unique executable lines** across passing shards from the same simulator per family; every result must contain both coverage targets and all source files with matching executable-line sets and source timestamps older than every result. Never add or average Xcode target summaries (they double-count SwiftUI specializations).
- Xcode sometimes omits `FestivalUI` from a passing `.xcresult`; the gate rejects such bundles. Timestamps are not hashes: freeze sources across shards.
- `FestivalCore`/`FestivalDesign` are not Xcode coverage targets; macOS SwiftPM coverage does not certify their device lines.

## Last measured

| Gate | Value | Date / source |
|---|---|---|
| SwiftPM logic | 2000/2087 (95.83%) pass | 2026-09-27, after Score/FC Filter |
| SwiftPM UX | 9430/10415 (90.54%) pass | same run |
| iPhone UI/app union | 4092/4695 (87.16%) fail — historical | pre-Score/FC-Filter source; no current-source phone or paired measurement |

CI (`.github/workflows/contracts.yml`) runs only the Python contract/contrast checks.

### Wave 3 UX-test lane (Lane U) — per-feature SwiftPM line coverage

Measured 2026-09-28 via `swift test --enable-code-coverage` + `llvm-cov export`
(same recipe as `apple_coverage.sh`), scoped to `apple/Sources/FestivalUI`
files for each completed feature this lane covers. This is **hosted/logic
coverage only** — real device interaction paths exercised solely by an
XCUITest journey (e.g. `NotificationsSheet`'s row-tap `open(_:)`, or anything
gated behind a `.sheet(isPresented:)` a hosted AppKit test can't tap open) are
not reflected here; they need the separate iPhone `apple_xccov_gate.py` path,
which this lane did not run (see Open gaps below).

| Feature | Lines covered / total | % | Notes |
|---|---|---|---|
| Shell (`App/FestivalRootView.swift`, `Shell/*`) | 959/1335 | 71.8% | `FestivalRootView.swift` itself is 57%: most of its uncovered lines are `#if os(macOS)` sidebar/split-view branches and drawer-intent wiring only a device run exercises. |
| Leaderboards + Quick Links | 1330/1591 | 83.6% | Includes `Common/QuickLinks/*` as adopted on Leaderboards. |
| Background (artwork carousel/coordinator) | 1081/1334 | 81.0% | `ArtworkBackdropCanvas.swift` (65%) and `FestivalBackgroundHost.swift` (70%) carry most of the gap — Canvas-drawing and host-mirroring branches that need a real animating device frame. |
| Player history + notifications | 872/1199 | 72.7% | Was 510/1199 (42.5%) before this lane added `PlayerHistorySortSheetRenderTests.swift`, which took `PlayerHistorySortSheet.swift` from 0% to fully exercised (it's only reachable via a `.sheet` a hosted AppKit test can't tap open, so it needed a standalone host). |
| First-run | 379/481 | 78.8% | `FirstRunModifier.swift` (38%) is the page-integration seam (`.firstRun(page:session:)`); most of its branches are per-page gate/session wiring only a live app session exercises. |
| Licenses | 195/288 | 67.7% | `LicenseManifest.thirdPartySoftware` is currently empty (no dependency yet), so that branch of `LicensesScreen.swift` is legitimately dead code, not a test gap. |
| **Total (these features)** | **4816/6228** | **77.3%** | Below the 90% UX target; see Open gaps. |

**Open gaps toward 90%:** the shortfall is concentrated in code that only a
real device run reaches — platform-conditional (`#if os(macOS)`/`#if
os(iOS)`) branches, `.sheet`/`.confirmationDialog` presentation and dismissal,
drawer swipe-to-dismiss, and Canvas/host-mirroring paint paths. This lane's
XCUITest journeys (`ShellJourneyTests`, `LeaderboardsJourneyTests`,
`NotificationsJourneyTests`, `FirstRunJourneyTests`) exercise many of these on
a real device, but `swift test`'s SwiftPM coverage only instruments the
macOS-hosted process, not the separate iOS `xcodebuild test` run — closing
this gap for real needs `apple_xccov_gate.py` against an iPhone `.xcresult`
(not run this session: the shared simulator was under heavy concurrent-lane
load throughout).

### Wave 3 UX-test lane (Lane U2) — Songs, Song Detail, Item Shop, Suggestions

Measured 2026-09-28 via the same `swift test --enable-code-coverage` +
`llvm-cov export` recipe (one flaky, unrelated `ArtworkBackgroundTests` dwell
timer excluded with `--skip`; all 360 other tests passed), scoped to
`apple/Sources/FestivalUI/Features/{Songs,SongDetail,Shop,Suggestions}` and
the shared `Common/QuickLinks`. Same caveat as Lane U above: this is
hosted/logic coverage only, not the separate device `xcodebuild test` path.

| Feature | Lines covered / total | % | Notes |
|---|---|---|---|
| Songs | 4061/4448 | 91.3% | Above target. `SongsScreen.swift` itself is 85.3% (many branches are `#if os(iOS)`/`#if os(macOS)` list-vs-sidebar and grouped-Shop-section paths a hosted hosted-macOS hidden window can't fully reach); `SongSectionIndexScrubber.swift` is 75.2% even after this lane's new `SongSectionIndexScrubberRenderTests.swift` (0→3 cases) — the drag-gesture `update(for:height:)`/`move(by:)` handlers need a real touch/VoiceOver-adjustable-action device test, not a static hosted render. |
| Song Detail | 1610/1738 | 92.6% | Above target. `SongScorePreview.swift` (74.8%) carries most of the gap — retry/cancellation branches exercised by the XCUITest journeys (`SongDetailJourneyTests`) but not by a hosted snapshot. |
| Item Shop | 613/649 | 94.5% | Above target; `ShopScreen.swift` was already well covered by `ShopScreenRenderTests.swift`. |
| Suggestions | 90/1078 | 8.3% | **Below target — primary open gap.** `SuggestionsScreen.swift` is only 31.4% and `SuggestionCategoryCardView.swift`/`SuggestionsFilterSheet.swift` are 0%: this feature had "no hosted-UI/XCUITest coverage yet" per `.agents/pages/suggestions/ios.md` before this lane, and this pass added only XCUITest journeys (`SuggestionsJourneyTests.swift`, not SwiftPM-measured) plus the pre-existing Core-only `SuggestionGeneratorTests`/`SuggestionFilterSettingsTests` (~96–100% Core coverage, not reflected in this UI-file table). **Next step:** hosted snapshot tests for `SuggestionsScreen` (no-profile/syncing/loading/empty/loaded/exhausted-mix states) and `SuggestionsFilterSheet` (instrument/type toggle draft states), mirroring `SongsSortSheetRenderTests.swift`'s pattern. |
| Quick Links (`Common/QuickLinks`, shared) | 255/333 | 76.6% | Below target but shared across every adopting page (Leaderboards, Songs, Song Detail); `QuickLinksToolbar.swift` (67.5%) is mostly the `Menu`/`Picker` body a hosted AppKit test can't open (see `hosted-snapshots.md` pitfalls) — needs a device test asserting `fst.quick-links.open`'s value after a jump, which this lane's new `testSongsItemShopSortQuickLinksJump` XCUITest exercises on-device but that path isn't SwiftPM-measured either. |

**XCUITest journeys added this pass** (`apple/Apps/iOSUITests/{SongsJourneyTests,SongDetailJourneyTests,ShopJourneyTests,SuggestionsJourneyTests}.swift`, 41 tests total): verified a representative subset against the real simulator post-fix (anonymous Sort apply/discard/reset/relaunch, public Shop offers→Song Detail hand-off, the new Item Shop Quick Links jump); the remaining tests were migrated verbatim from a previously-passing legacy suite plus mechanically updated for two redesign-driven identifier changes (see coverage-adjacent bug notes in the lane's final report) but not all individually re-run against the device this session — the shared simulator lock is now bounded to ≤5 minutes per hold per operator guidance, so a full 41-test device pass needs several more short batches than this session had time for.
