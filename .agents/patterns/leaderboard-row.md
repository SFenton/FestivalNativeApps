# Leaderboard row

> **What:** shared score and ranking row geometry, columns, name overflow, pager and selected-player behavior. **Read when:** adding or changing any leaderboard, score preview, ranking card, spotlight or board footer.

Status: **current**, 2026-10-05. Provenance: #37, #38, #90, #292, #293, #294, #295, #306, #307.

## Intent

Every row in one leaderboard section must read as one aligned, accessible data table: a stable minimum height, a shared column plan, a contained name, and the same pager and pinned-row behavior regardless of entry point.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songinfo/topScoresLayout.ts` (`resolveTopScoresColumns`) | Fits Song Detail score columns from the card width. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/rankingHelpers.ts` (`computeRankWidth`) | Calculates one rank width for a section. |
| `FortniteFestivalWeb/src/components/leaderboard/PaginatedLeaderboard.tsx` (`PaginatedLeaderboard`) | Pinned score/footer, paging and staggered board rows. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`); `packages/theme/src/spacing.ts` (`Layout.entryRowHeight = 48`) | Contained overflowing text and the 48-unit row baseline. |

## Rules

- **R1. Fit columns once per section.** Rank, score, rating and songs widths include spotlight and pinned rows; individual rows never choose their own plan. Use measured row/card width, not device identity. HIG Layout: "Choose layout from size classes, not device type/idiom or orientation."
- **R2. Use a 48-unit minimum.** Loaded rows, selected and pinned rows, skeletons and spotlight placeholders share the web baseline; accessibility layouts may grow and stack. HIG Layout: "rows/containers may grow to avoid clipping/overlap and allow multiple lines."
- **R3. Keep names inside their column.** Overflowing normal-size names marquee through the shared text component; Reduce Motion, inactive/off-screen rows and motion-disabled systems tail-truncate, while accessibility text wraps and assistive technology receives the full name. HIG Motion: "When Reduce Motion is on, reduce automatic and repetitive animation."
- **R4. Decide Compete songs once per card.** Hide songs played/total on every row only when the longest drawn name cannot fit; keep it in the accessibility value. Other ranking sections keep their shared songs column.
- **R5. Reuse the board pager.** Full, band and song boards share one pager layout and button semantics; the selected player's pinned row is immediately above it and shares its columns.
- **R7. One selected-row rule for players and bands (#307).** Solo and band song boards pin the selected profile's row with the same row component. A selected row shown apart from its page (Song Detail's appended row, a footer while the row is on another page) jumps to the page containing its rank and reveals the highlighted row (instant under Reduce Motion); once the row is on screen it opens the profile (Statistics for a player, the Band page for a band). Other rows open their player or band. Labels name the destination ("Jump to your band's position" / "Open band"). HIG Lists and tables: "Provide appropriate selection feedback."
- **R6. Maintain platform-approved variants.** Android and Windows use their native shared pager and row surface; their title/header behavior is not an Apple collapsing-title requirement. MD3 transitions and Fluent theme brushes are approved native variants (#294).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Section fit and height | `FestivalCore/LeaderboardRowColumns.swift` `LeaderboardRowColumns`; `FestivalUI/Design/LeaderboardRowMetrics.swift` `LeaderboardRowMetrics` | `core/rankings/LeaderboardColumnLayout.kt` `LeaderboardColumnLayout`; `ui/leaderboards/RankingsComponents.kt` `LEADERBOARD_ROW_MIN_HEIGHT` | `Festival.Core/Domain/LeaderboardColumnLayout.cs` `LeaderboardColumnLayout`; `Festival.Core/ViewModels/LeaderboardEntryRows.cs` `LeaderboardRowMetrics` |
| Rows and name | `FestivalUI/Features/Leaderboards/RankingsSupport.swift` `RankingRowLayout`, `LeaderboardNameText`; `Features/SongLeaderboard/SongLeaderboardEntryRow.swift` | `ui/leaderboards/RankingsComponents.kt` `LeaderboardNameText`; `ui/songdetail/SongDetailScreen.kt` `ScoreRow` | `Festival.App/Controls/LeaderboardEntryRow.xaml.cs` `LeaderboardEntryRow`; `Controls/MarqueeText.cs` `MarqueeText` |
| Selected pinned row and its action (R5, R7) | `FestivalUI/Features/SongLeaderboard/SelectedScoreFooterRow.swift` `SelectedScoreFooterRow`; `FestivalCore/SelectedRowNavigation.swift` `SelectedRowAction` | Not yet audited (#307 verify lane) | Not yet audited (#307 verify lane) |
| Pager | `FestivalUI/Features/Leaderboards/RankingsSupport.swift` `RankingsPagerView` | `ui/leaderboards/RankingsComponents.kt` `RankingsPager` | `Festival.App/Controls/LeaderboardsPager.xaml.cs` `LeaderboardsPager` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple’s fitter decides difficulty and stars, but Apple score rows do not yet render them. | Full web metadata parity on Apple score rows. | `TODO(orchestrator): scope the missing Apple score metadata columns.` |

## Guards (`tools/pattern_guard.py`)

- `leaderboard-row/apple-name-owner`
- `leaderboard-row/android-row-metrics`
- `leaderboard-row/windows-row-metrics`
- `leaderboard-row/windows-pager-owner`
