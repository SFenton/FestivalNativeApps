# Compete — Windows notes

> **What:** how `/compete` behaves on Windows. **Read when:** changing Compete routing in `MainWindow` or the Rivals hub. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Windows has no Compete section: the wide split keeps Leaderboards and Rivals as separate navigation items. `AppRoute.Compete` (and `/rivals`) deep links show the Rivals section root when a player is selected, otherwise push the Rivals page's "No Player Selected" state.
- The web Compete page's leaderboard top-5 cards are covered by the Leaderboards section, not duplicated here.
- Loading (#65, 2026-10-02): every hub card shows a `ProgressRing` until its rows or inline error arrive; see [Rivals Windows notes](../rivals/windows.md).
- **Back keeps the scroll position (#82, 2026-10-02):** the iOS #39 check. Leaderboards → View All → Back and Rivals → rival → Back did not reload (both models are key-gated), but they came back scrolled several sections further down. When the clicked control left the window with the cached page, WinUI walked focus through the page's other controls, and the page `ScrollViewer` brought each one into view. `Services/CachedPageScroll` (attached to every section `Frame`) pauses `BringIntoViewOnFocusChange` on an outgoing cached page's scrollers and restores it when the page is shown again; focus still lands where it did. Regression: the Quick Links → Drums → View All → Back block in `tools/windows/journeys/leaderboards.steps` (fails without the fix).
