# Apple accessibility audits

> **What:** audit rules, rendered-contrast checks and the currently open Apple audit findings. **Read when:** the accessibility phase, or when a change touches text over artwork, the tab edge or large text.

## Rules

- Run XCTest `performAccessibilityAudit` (`.all`) **unwaived**. No blanket waivers; keep failing crops/xcresults as private evidence.
- The only scoped exception: iOS 26.5 Songs "Retry Item Shop status" may report ≤1 contrast and ≤1 Dynamic Type issue for that exact identifier/label, **after** the test independently proves ≥4.5:1 rendered text (measured 18.72:1) and >1.35× AX5 glyph growth. Never extend it.
- Named visible text gets a rendered-pixel contrast assertion (≥4.5:1 text, ≥3:1 meaningful edges) from the app screenshot — token math (`tools.contrast_gate`) is not rendered evidence.
- Large text: assert real glyph growth (>1.35× at AX5) and that actions remain reachable above native chrome in portrait and landscape.
- Use `FST_FIXTURE_SCENARIO=art-white` for worst-case contrast over artwork.
- A single passing run of a flaky audit is not certification; a source-identical rerun must pass too.

## Open findings (not waived)

| Screen | Device | Finding |
|---|---|---|
| Song Detail full page | iPhone 26.5 | Score rows at y≈792/849 under the Liquid Glass tab (tab starts y=791); edge/inset/footer attempts did not fix it and were reverted. Large-type Intensity labels also flagged |
| Settings full page | iPhone | Partly offscreen heading / translucent compact title reported as contrast |
| Grouped Songs (Shop sort) | iPhone | Intermittent nil-element Dynamic Type issue; saved Shop sort + failed Shop offline state has an unidentified contrast node |
| Karaoke path warning alert | iPhone | System alert title contrast and message Dynamic Type |
| Sort sheet, Paths sheet, profile sheet, selected Songs | iPad 26.5 | Unnamed "Potentially inaccessible text" |
| Solo launched at AccessibilityXXXL | iPad | Three nil-element "Text clipped" findings |
| Grouped headers | iPad | Accessibility frames span both split panes; VoiceOver focus bounds unverified |
