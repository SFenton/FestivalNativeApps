# CHOpt Paths — macOS notes

> **What:** Mac-specific Paths findings for the shared SwiftUI `SongPathsSheet`. **Read when:** changing the Paths sheet on macOS. Behavior: [spec.md](spec.md); shared layout: [ios.md](ios.md).

- Image placement (issue #87): AppKit's two-axis scroll view also put a narrower path image at the leading edge. The shared centred `.top` frame fixes it. The hosted render test `pathSheetPaintsValidatedTextAndImageArtifacts` asserts equal side margins.
- Scroll bars use `.scrollIndicators(.hidden)`, not `.never`. macOS still shows them when System Settings asks to always show scroll bars, for example with a mouse connected, so mouse users can still pan a zoomed path sideways (HIG [scroll-views](https://developer.apple.com/design/human-interface-guidelines/scroll-views), macOS: "scroll indicators are scroll bars").
