# Leaderboard row columns — Android notes

> **What:** where Android decides leaderboard row columns (issue #37) and what the issue #149 device pass found. **Read when:** changing `core/rankings/LeaderboardColumnLayout.kt`, `ui/leaderboards/LeaderboardSectionColumns.kt`, `ScoreRow`/`StackedScoreRow` or `RankingRowLayout`/`StackedRankingRow`. Rules: [spec.md](spec.md).

## Implemented

- One fitter: `LeaderboardColumnLayout.fit(section, rowWidth, fontScale)` (pure Kotlin, unit-tested for narrow and wide widths) returns a `LeaderboardColumnPlan` for the whole section. Composables measure the section's texts once (`LeaderboardSectionColumns`, `rememberScoreColumns`), including the pinned row (`LeaderboardSectionMember` "rows"/"footer"), and fit to the narrowest member.
- Score rows: season from a 520 dp row, stars from 700 dp, accuracy slot always reserved when any row has accuracy; stars, then season, drop before the name falls under 72 dp × font scale. Rankings sections: songs label rules per page (`nameWidth`, `keepsNameMinimum`, `stackNarrowNames`).
- Large text (`isLargeText`) stacks rows, but they keep the section's rank column: `StackedScoreRow` applies its 8 dp end padding *before* `widthIn(min = rankWidth)` and `StackedRankingRow(rankWidth)` reserves the same width, so `#9`/`#10`/a bold pinned `#28` start their names on one x (issue #149).
- The anchored pinned row spans the board like the rows (`RankingsBoardScaffold.AnchoredFooter`, issue #149); before, it stopped at 720 dp and centred, so on tablets and wide windows every column of the pinned row sat inward of the rows.

## Validation (issue #149)

Per-configuration findings: [song-leaderboard/android.md](../../pages/song-leaderboard/android.md#validation-issue-149-column-alignment-from-issue-37-2026-10). Full Rankings: [full-rankings/android.md](../../pages/full-rankings/android.md). Song Detail cards: [song-detail/android.md](../../pages/song-detail/android.md).

Tests: `LeaderboardColumnLayoutTest` (fitter), `LeaderboardsExpandedUiTest.expandedSongLeaderboardPinnedRowLinesUpWithTheRows`, `FullRankingsDesktopUiTest.desktopPinnedRankSpansTheBoard`, `ScoreAccuracyUiTest.largeTextNamesLineUpWhateverTheRankWidth`, `LeaderboardRowHeightUiTest.largeTextRankingNamesLineUpWhateverTheRankWidth`.
