# Leaderboard row columns — Mac notes

> **What:** Mac behaviour of the shared column fitting. **Read when:** the macOS phase or changing leaderboard sections on the Mac. Behavior: [spec.md](spec.md); implementation: [ios.md](ios.md).

- Same Swift code as iPhone; window resizing re-fits each section from its measured width, so narrow windows drop the season column below 520 pt.
- Compete's songs fit (#38) follows the window width; `RankingSongsFitHostedTests` run on macOS hosts (13 pt body), so they exercise the Mac measurement.
- The hosted alignment tests (`LeaderboardRowColumnsHostedTests`) run on macOS AppKit hosts, so they cover the Mac row layout; a full Mac app capture is still pending the macOS phase.
- **Row height (#90):** the shared `LeaderboardRowMetrics.minHeight` (48 pt minimum) applies here too through the shared rows; verified on iPhone and in the macOS-hosted `LeaderboardRowHeightHostedTests`, not yet by a separate capture on this platform.
