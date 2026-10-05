# Solo leaderboard — iPad notes

> **What:** iPad-specific Solo chart findings. **Read when:** the iPadOS phase, or changing score-row height/badges. Behavior: [spec.md](spec.md).

- A 30pt accuracy badge raised row height and failed the normal page-one `.all` audit (unnamed contrast); the 24pt badge restored unwaived page-one/page-two audits ([score-accuracy/ipados.md](../../controls/score-accuracy/ipados.md)).
- Launching directly at AccessibilityXXXL reports three nil-element "Text clipped" findings — open, not certified.
- Issue #93 (floating chrome, fade under the footer, chrome kept while paging, no title before scroll) is shared Swift; see [ios.md](ios.md). So is issue #293 (no header gradient; the list ends one row gap above the footer or pager, with no reserved margin): the same code serves iPad, Duo and Mac. On the Duo vertical bar, `RankingsPagerView` renders nothing and the pager stays in the rail, so only the footer floats. Issue #307's selected-row rule (footer jumps to an off-page row and centres it; Song Detail's appended solo and band rows open the full board focused on them) is shared Swift as well, so iPad, Duo and Mac follow it; see [ios.md](ios.md).
- Issue #295 (player row fading in after the other rows) is the shared `RankingRowSurface` fix; see [ios.md](ios.md). The same rows on macOS share it.
