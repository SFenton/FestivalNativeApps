# Leaderboard row columns — Mac notes

> **What:** Mac behaviour of the shared column fitting. **Read when:** the macOS phase or changing leaderboard sections on the Mac. Behavior: [spec.md](spec.md); implementation: [ios.md](ios.md).

- Same Swift code as iPhone; window resizing re-fits each section from its measured width, so narrow windows drop the season column below 520 pt.
- The hosted alignment tests (`LeaderboardRowColumnsHostedTests`) run on macOS AppKit hosts, so they cover the Mac row layout; a full Mac app capture is still pending the macOS phase.
