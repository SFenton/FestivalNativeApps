# Score accuracy — iPad notes

> **What:** the iPad layout-loop and audit lessons behind the badge's fixed frame. **Read when:** changing the badge's size or padding, or any row shown in iPad split view.

- **Keep padding outside the badge's explicit frame.** Padding inside caused a main-thread layout loop when the old iPad sidebar resized Detail. The owner-approved [on-demand split](../../design/apple/split-view.md) replaces the persistent sidebar; the flyout overlays the window and does not resize it. Keep the equivalent size change in device tests: `IPadShellJourneyTests.testSongDetailOpensLeaderboardInTrailingHalf` keeps the same named full-combo badge and enabled pager while Solo page two moves from landscape split to portrait push and back.
- Removing `.contain` from Detail did not fix the hang — do not attribute it to that wrapper.
- A 30pt badge raised List row height and failed the normal Solo page-one `.all` audit (unnamed "Contrast nearly passed"); 24pt restored unwaived page-one/page-two audits with graded fill and gold stroke intact.
