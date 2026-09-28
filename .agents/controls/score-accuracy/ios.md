# Score accuracy — iPhone notes

> **What:** the SwiftUI badge implementation and its layout constraints. **Read when:** changing `SongLeaderboardEntryRow` or the accuracy badge. Spec: [spec.md](spec.md); iPad-only lessons: [ipados.md](ipados.md).

- Native Fluent rounded border and white text instead of the web's skewed gold italic outline (intentional; legible on opaque cards over white art).
- Ordinary text sizes reserve one fixed column for graded, FC and missing rows: **80pt text / 96pt outer × 24pt**; the missing-accuracy slot is invisible and hidden from accessibility, so equal-digit scores align within 1pt. Accessibility sizes stack values with unconstrained width.
- Size the badge with an explicit scaled `frame` — **never `padding` inside it** (see iPad layout loop).
- Full Solo List: `.accessibilityElement(children: .contain)` keeps the badge's `fst.score.accuracy.*` ID beside the row ID. Detail preview rows still inherit `fst.song-detail.preview-row.*`; a separate child ID/focus is pending.
- Tests: `ScoreFormattingTests` (tint ramp), `scoreAccuracyBadgeRendersSourceStates` (five hosted states), `testSongDetailShowsTopScorePreviewAndFullChart` (non-FC vs FC labels and pixels in Detail and Solo), `testSoloScoresAtLargestTextSize`.
- Separate from this badge: [score-metadata pills](../song-score-metadata/ios.md) use scaled horizontal insets; do not copy that padding here.
