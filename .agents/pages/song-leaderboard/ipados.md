# Solo leaderboard — iPad notes

> **What:** iPad-specific Solo chart findings. **Read when:** the iPadOS phase, or changing score-row height/badges. Behavior: [spec.md](spec.md).

- A 30pt accuracy badge raised row height and failed the normal page-one `.all` audit (unnamed contrast); the 24pt badge restored unwaived page-one/page-two audits ([score-accuracy/ipados.md](../../controls/score-accuracy/ipados.md)).
- Launching directly at AccessibilityXXXL reports three nil-element "Text clipped" findings — open, not certified.
- Issue #93 (floating chrome, fade under the footer, chrome kept while paging, no title before scroll) is shared Swift; see [ios.md](ios.md). On the Duo vertical bar, `RankingsPagerView` renders nothing and the pager stays in the rail, so only the footer floats.
- Issue #295 (player row fading in after the other rows) is the shared `RankingRowSurface` fix; see [ios.md](ios.md). The same rows on macOS share it.
