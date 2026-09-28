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
