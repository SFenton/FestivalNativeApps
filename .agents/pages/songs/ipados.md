# Songs — iPad notes

> **What:** iPad-specific Songs behavior and open gaps. **Read when:** the iPadOS phase, or when a change affects split-view Songs. Behavior: [spec.md](spec.md); iPhone: [ios.md](ios.md).

- Split navigation recreates Songs on a section switch, so its initial `.loading` task recovers independently of the iPhone retained-error fix; the instrument filter is scene-owned and survives section switches.
- The detail pane wraps nine status chips 5+4; the 820px web tablet shows one row. Explicit platform-layout gap, not a match.
- Sort sheet is centered; Reset may need a Form scroll above the pinned footer.
- Open: full `.all` audits report unnamed "Potentially inaccessible text"; grouped Shop headers report full-window accessibility frames (focus bounds unverified) — see [accessibility](../../testing/apple/accessibility.md). Always test Hide/Show Sidebar with Detail visible.
