# Songs Filter — macOS notes

> **What:** how the shared SwiftUI Filter sheet differs on the Mac. **Read when:** changing Songs filtering on macOS. Spec: [spec.md](spec.md); shared implementation notes: [ios.md](ios.md).

- Same `SongsFilterSheet` and `SongGeneralFilter` as iPhone/iPad; General (Year, Duration, Item Shop, Double Bass) is offered without a selected player (issue #77).
- Accordions use the same shared motion as iPhone ([accordion](../../patterns/accordion.md), #561): the Mac `DisclosureGroup` expands, then its checkboxes fade in; closing fades them out, then it collapses. Verified on the hosted macOS render tests and `FestivalAccordionTests` (`swift test`).
- The Form's `Toggle`s render as **checkboxes**, not switches (HIG Toggles, macOS: "don't replace a checkbox with a switch"); do not force `.switch`.
- Evidence: hosted `SongsBucketSheetsRenderTests` / `SongsSortSheetRenderTests` render on macOS in `swift test`; no separate macOS UI journey yet. TODO(orchestrator): Mac UI journey for the General section.
