# Leaderboard row columns — iPad notes

> **What:** iPad behaviour of the shared column fitting. **Read when:** the iPadOS phase or changing leaderboard sections in split view. Behavior: [spec.md](spec.md); implementation: [ios.md](ios.md).

- Same Swift code as iPhone. Widths are each section's measured width (Song Detail card, Solo chart column), never the device idiom, so split view and Slide Over get the narrow layout automatically.
- Full-width Solo charts (≥ 520 pt) now show the season column; ≥ 768 pt marks stars as fitting, but no native score row draws stars yet (open gap, see [spec.md](spec.md)).
- Compete's songs fit (#38) uses the measured card width, so wide iPad cards keep songs and narrow split-view cards drop them; not yet captured on iPad.
- Not yet captured on an iPad simulator (iPhone-first order); verify alignment and the season column there in the iPadOS phase.
- **Row height (#90):** the shared `LeaderboardRowMetrics.minHeight` (48 pt minimum) applies here too through the shared rows; verified on iPhone and in the macOS-hosted `LeaderboardRowHeightHostedTests`, not yet by a separate capture on this platform.
