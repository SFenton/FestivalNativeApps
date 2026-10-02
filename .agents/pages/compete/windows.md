# Compete — Windows notes

> **What:** how `/compete` behaves on Windows. **Read when:** changing Compete routing in `MainWindow` or the Rivals hub. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Windows has no Compete section: the wide split keeps Leaderboards and Rivals as separate navigation items. `AppRoute.Compete` (and `/rivals`) deep links show the Rivals section root when a player is selected, otherwise push the Rivals page's "No Player Selected" state.
- The web Compete page's leaderboard top-5 cards are covered by the Leaderboards section, not duplicated here.
- Loading (#65, 2026-10-02): every hub card shows a `ProgressRing` until its rows or inline error arrive; see [Rivals Windows notes](../rivals/windows.md).
