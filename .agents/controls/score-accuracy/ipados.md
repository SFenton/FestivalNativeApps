# Score accuracy — iPad notes

> **What:** the iPad layout-loop and audit lessons behind the badge's fixed frame. **Read when:** changing the badge's size or padding, or any row shown in iPad split view.

- **Padding inside the badge caused a repeatable main-thread layout loop** after tapping Hide Sidebar with Detail visible (UIKit split-view + SwiftUI hosting-scroll layout; a 5 s sample showed only layout frames). A clean baseline worktree passed; a plain helper and the full badge with an explicit frame and no padding both pass the Paths and Detail sidebar-toggle journeys. Keep that transition in device tests.
- Removing `.contain` from Detail did not fix the hang — do not attribute it to that wrapper.
- A 30pt badge raised List row height and failed the normal Solo page-one `.all` audit (unnamed "Contrast nearly passed"); 24pt restored unwaived page-one/page-two audits with graded fill and gold stroke intact.
