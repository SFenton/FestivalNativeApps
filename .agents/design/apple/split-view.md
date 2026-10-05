# Split view and flyout redesign (iPad, iPhone Duo, macOS)

> **What:** the operator's 2026-10-04 redesign of list/detail ("split view") layouts and the iPad/Duo navigation flyout; supersedes earlier always-on two/three-column layouts. **Read when:** changing any list/detail, split, sidebar or flyout layout on iPad, Duo or Mac.

Operator verdict (2026-10-04): the always-on split layouts on iPad, Duo and Mac look bad — the split is not aligned with the Duo's fold or the screen's midpoint, and screens like Songs should never be split. Replace them with an **on-demand split** used only on pages where it helps, aligned to the **exact vertical midpoint** (Duo: the fold). Every implementation decision still goes through the `apple-hig` skill (split views, sidebars, layout, iPhone Duo).

## On-demand split (the only split pattern)

- **Starts full width.** The page uses the whole content width with no empty detail pane.
- **Selecting an item splits:** the page animates to the leading half and the "navigated-to" content appears in the trailing half. Selecting another item replaces the trailing half. Closing it (close button in the trailing pane's toolbar, Escape, ⌘[, or Back) animates back to full width.
- **Geometry:** the divider sits at the **exact vertical midpoint** of the content area — 50/50, never content-sized. On iPhone Duo's inner display it aligns to the **hinge**: leading pane ends at the hinge's leading edge, trailing pane starts at its trailing edge (the rail/vertical bar is accounted for inside the panes, never by shifting the divider). On Mac the content area is the window minus the persistent sidebar; the divider is fixed at that area's midpoint.
- **When it applies:** landscape / wide regular width only, and only when each half is at least ~360 pt. Portrait (iPad portrait, Duo inner portrait, narrow Mac windows) and compact width use ordinary push navigation (full-screen detail with Back). This supersedes Duo D1/J3 (inner-portrait two columns) and the iPad three-column sidebar|list|detail layout.
- **Motion:** spring resize of the leading pane with the trailing pane sliding in from the trailing edge; Reduce Motion → crossfade. Keep the selected row highlighted while its detail is open.

## Page classification

| Split on demand (landscape/wide) | Leading half → trailing half |
|---|---|
| Rivals hub, All Rivals | rivals list → Rival Detail (Rivalry pushes inside the trailing pane) |
| Leaderboards overview | cards → selected player's profile; "View all rankings" pushes Full Rankings full width |
| Full Rankings, Band Rankings | rankings → player profile / band detail |
| Song Detail | song page → full instrument **Song Leaderboard** or **score history** (operator 2026-10-04) |
| Settings (iPad/Duo) | settings list → sub-page (Licenses, First Run Guides, Service Info, …); Mac keeps its Settings window panes |

| Never split (full width, push navigation) | Landscape treatment |
|---|---|
| Songs | full width; **two-column grid of rows under each section header** in landscape |
| Song Leaderboard (full instrument board) | full width; tapping a player navigates **directly** to the profile (push, no split; operator 2026-10-04) |
| Paths | **always a modal sheet** on every platform (self-contained task; operator 2026-10-04) |
| Item Shop, Suggestions, Statistics/Player profile, Compete, Band Detail, Player Bands, Rivalry | full width; existing adaptive grids |
| Search, Notifications, What's New, first run, sheets | modal/sheet presentations, unchanged |

## Navigation flyout (iPad, iPhone Duo)

- The side panel is an **overlay flyout like iPhone's drawer**: it slides **over** the content with a scrim, from the leading edge, opened by the toolbar/sidebar button or edge swipe, closed by tapping the scrim, Escape or selecting a destination. It never pushes or resizes content, and there is no persistent sidebar column.
- macOS keeps its persistent sidebar (Mac convention, [macos.md](macos.md)); the Mac split rules above apply to its content area.
