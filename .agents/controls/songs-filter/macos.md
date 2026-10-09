# Songs Filter — macOS notes

> **What:** how the shared SwiftUI Filter sheet differs on the Mac. **Read when:** changing Songs filtering on macOS. Spec: [spec.md](spec.md); shared implementation notes: [ios.md](ios.md).

- Same `SongsFilterSheet` and `SongGeneralFilter` as iPhone/iPad; General (Year, Duration, Item Shop, Double Bass) is offered without a selected player (issue #77).
- The Form's `Toggle`s render as **checkboxes**, not switches (HIG Toggles, macOS: "don't replace a checkbox with a switch"); do not force `.switch`.
- The Form is identified with `festivalFormIdentifier`: a plain `.accessibilityIdentifier` on a Mac `Form` replaced every row's identifier ([hosted snapshots](../../testing/apple/hosted-snapshots.md#pitfalls)).
- Evidence: hosted `SongsBucketSheetsRenderTests` / `SongsSortSheetRenderTests` render on macOS in `swift test`; `SongsFilterAccessibilityTests` (#432) reads the Mac accessibility tree: General's disclosure triangles, checkboxes and named Select All / Clear All in drawn order, and the accessibility press. macOS keeps the system checkbox and borderless header-button metrics (HIG Accessibility: "Strive for the platform's recommended minimum control size", a should). No separate macOS UI journey yet. TODO(orchestrator): Mac UI journey for the General section.
