# iPhone Duo design

> **What:** layout rules for iPhone Duo's outer and inner displays. **Read when:** the Duo phase starts (after iPhone). Runtime/posture facts: [platforms/apple/duo.md](../../platforms/apple/duo.md).

- Bespoke outer/inner layout with supported poses (folded, unfolded, outer rotations) — a separate phase, not inherited from iPhone or iPad evidence.
- Per Apple's [Duo guidance](https://developer.apple.com/videos/play/tech-talks/111466/): compact layout outside, regular layout inside; use margins and safe areas, not device-name breakpoints.
- Respect camera and fold reserved regions for custom overlays; keep system navigation outside split arrangements. System `TabView`/toolbars/sheets handle reserved regions better than a hand-built tab lane — never build one.
- Do not port the web app's Duo pixel detector or guess fold/camera positions.
