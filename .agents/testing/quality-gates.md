# Evidence and test gates

**Two independent gates:** source line coverage of at least **95% for non-UX and 90% for UX code**, per native language, *and* complete reachable control states/transitions with visual, navigation and accessibility assertions. A screenshot or an automation count is not a line-coverage percentage.

- Logic: wire decoding (including compact fields and numeric transforms), publication pin/409 retry/304 ETag consistency, session-cache invalidation, filters/sorting and navigation guards. Negative, stale, missing, retry and offline cases belong in fixtures.
- UI: snapshots for each declared control state/theme/text scale, nested controls and controls driving other controls; page/guard/modal/back/deep-link journeys; accessibility order, labels, focus, hit targets, contrast and reduced motion. Store named test IDs and source references in the manifest; mocks replace side-effecting live endpoints.
- Android: combine host and instrumented coverage. Apple: Xcode code coverage plus hosted UI/a11y audits. Windows: testable view-model coverage and a proven WinUI UI-test host. Each platform's report must include the same source files that the coverage gate classifies.
- Run simulators **serially**, not in parallel; screenshots must include OS/device/pose/theme/text-size metadata. Unavailable OS runtimes and posture controls are gaps, not passes. Verify scrolling/animation at target refresh rates with representative workloads and compare Windows app/game impact in Release builds.

`python3 tools/verify_product.py` validates inventory consistency and prints pending surfaces. Strict mode also requires evidence for every listed page, control and state on all four platforms. A separate source-coverage ingestion tool will normalize Xcode, Android and Windows reports; until actual native test reports exist, the 95/90 bar is **not yet met**.
