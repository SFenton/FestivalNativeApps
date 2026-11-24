# Difficulty meter — Apple notes

> **What:** SwiftUI implementation status. **Read when:** changing the meter in `FestivalDesign`. Spec: [spec.md](spec.md).

- SwiftUI `Canvas` geometry and all seven rendered states are covered by `apple/Tests/FestivalDesignTests/DifficultyMeterTests.swift` (62×20, seven centre pixels in source colour space).
- Song Detail Intensity shares the default 8 pt horizontal hinge-grid gutter between
  SwiftUI and UIKit; 10 pt is the vertical gap only
  ([HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)).
- Open: invalid/fractional state screenshots, accessibility order in rows/cards, other platforms. Wave 1 replaces text in the Detail intensity card with instrument icons ([PROGRESS.md](../../../PROGRESS.md)).
