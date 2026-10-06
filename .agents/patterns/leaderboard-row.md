# Leaderboard row

> **What:** shared score and ranking row geometry, columns, name overflow, pager and selected-player behavior. **Read when:** adding or changing any leaderboard, score preview, ranking card, spotlight or board footer.

Status: **current**, 2026-10-05. Provenance: #37, #38, #90, #172, #264, #292, #293, #294, #295, #306, #307.

## Intent

Every row in one leaderboard section must read as one aligned, accessible data table: a stable minimum height, a shared column plan, a contained name, and the same pager and pinned-row behavior regardless of entry point.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songinfo/topScoresLayout.ts` (`resolveTopScoresColumns`) | Fits Song Detail score columns from the card width. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/rankingHelpers.ts` (`computeRankWidth`) | Calculates one rank width for a section. |
| `FortniteFestivalWeb/src/components/leaderboard/PaginatedLeaderboard.tsx` (`PaginatedLeaderboard`) | Pinned score/footer, paging and staggered board rows. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`); `packages/theme/src/spacing.ts` (`Layout.entryRowHeight = 48`) | Contained overflowing text and the 48-unit row baseline. |
| `FortniteFestivalWeb/src/components/bands/SongBandScoreFooter.tsx` (`SongBandScoreFooter`, `getSongBandScoreWidth`) | Band team score footer: score, stars and accuracy; the score never shrinks (`flexShrink: 0`) and its width is decided once from every entry of the board. |

## Rules

- **R1. Fit columns once per section.** Rank, score, rating and songs widths include spotlight and pinned rows; individual rows never choose their own plan. Use measured row/card width, not device identity. HIG Layout: "Choose layout from size classes, not device type/idiom or orientation."
- **R2. Use a 48-unit minimum.** Loaded rows, selected and pinned rows, skeletons and spotlight placeholders share the web baseline; accessibility layouts may grow and stack. HIG Layout: "rows/containers may grow to avoid clipping/overlap and allow multiple lines."
- **R3. Keep names inside their column.** Overflowing normal-size names marquee through the shared text component; Reduce Motion, inactive/off-screen rows and motion-disabled systems tail-truncate, while accessibility text wraps and assistive technology receives the full name. HIG Motion: "When Reduce Motion is on, reduce automatic and repetitive animation."
- **R4. Decide Compete songs once per card.** Hide songs played/total on every row only when the longest drawn name cannot fit; keep it in the accessibility value. Other ranking sections keep their shared songs column.
- **R5. Reuse the board pager.** Full, band and song boards share one pager layout and button semantics; the selected player's pinned row is immediately above it and shares its columns.
- **R7. One selected-row rule for players and bands (#307).** Solo and band song boards pin the selected profile's row with the same row component. A selected row shown apart from its page (Song Detail's appended row, a footer while the row is on another page) jumps to the page containing its rank and reveals the highlighted row (instant under Reduce Motion); once the row is on screen it opens the profile (Statistics for a player, the Band page for a band). Other rows open their player or band. Labels name the destination ("Jump to your band's position" / "Open band"). HIG Lists and tables: "Provide appropriate selection feedback."
- **R8. Stack score footers once per section, never truncate the score (#264).** A row's team score footer (web `SongBandScoreFooter`: score, then FC, accuracy and stars) keeps the score whole at every width and text size. When any realized row in a section (one Song Detail band preview card, one song band board) measures that its badges don't fit beside its score, every row in that section puts the badges on a line under the score; the plan is a measured section-wide decision (R1), made at measure time so virtualized rows report the stacked height at once, and rows grow (R2). Rows report only their own need, so the plan converges. Badges may clip at their own line's edge only at extreme sizes; the score never does. A new footer reuses the platform's canonical footer below instead of its own grid, wrap or trimming. WCAG 1.4.4 (Resize text); HIG Layout: "rows/containers may grow to avoid clipping/overlap and allow multiple lines."
- **R6. Maintain platform-approved variants.** Android and Windows use their native shared pager and row surface; their title/header behavior is not an Apple collapsing-title requirement. MD3 transitions and Fluent theme brushes are approved native variants (#294).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Section fit and height | `FestivalCore/LeaderboardRowColumns.swift` `LeaderboardRowColumns`; `FestivalUI/Design/LeaderboardRowMetrics.swift` `LeaderboardRowMetrics` | `core/rankings/LeaderboardColumnLayout.kt` `LeaderboardColumnLayout`; `ui/leaderboards/RankingsComponents.kt` `LEADERBOARD_ROW_MIN_HEIGHT` | `Festival.Core/Domain/LeaderboardColumnLayout.cs` `LeaderboardColumnLayout`; `Festival.Core/ViewModels/LeaderboardEntryRows.cs` `LeaderboardRowMetrics` |
| Rows and name | `FestivalUI/Features/Leaderboards/RankingsSupport.swift` `RankingRowLayout`, `LeaderboardNameText`; `Features/SongLeaderboard/SongLeaderboardEntryRow.swift` | `ui/leaderboards/RankingsComponents.kt` `LeaderboardNameText`; `ui/songdetail/SongDetailScreen.kt` `ScoreRow`; band score rows `ui/bands/SongBandLeaderboardScreen.kt` `BandScoreRow`, `BandRowColumns`, `rememberBandRankWidth`, `bandBoardColumns` (full band board: one plan for page rows and the pinned footer) | `Festival.App/Controls/LeaderboardEntryRow.xaml.cs` `LeaderboardEntryRow`; `Controls/MarqueeText.cs` `MarqueeText` |
| Selected pinned row and its action (R5, R7) | `FestivalUI/Features/SongLeaderboard/SelectedScoreFooterRow.swift` `SelectedScoreFooterRow`; `FestivalCore/SelectedRowNavigation.swift` `SelectedRowAction` | `core/rankings/SelectedRowNavigation.kt` `SelectedRowAction`; `ui/songdetail/SongLeaderboardScreen.kt` `SelectedScoreFooterRow`; `ui/leaderboards/SelectedRowRevealEffect.kt` `revealSelectedRow` | Not yet audited (#307 verify lane) |
| Band score footer stack plan (R8) | Not yet audited (#264 is the Windows lane; `FestivalUI/Features/SongDetail/SongBandPreviewSection.swift` `SongBandPreviewRow` draws the footer) | Not yet audited (#264 is the Windows lane; `ui/bands/SongBandLeaderboardScreen.kt` `BandScoreFooter` draws the footer) | `Festival.App/Controls/BandScoreFooterPanel.cs` `BandScoreFooterPanel` (score first child, badges second; `BandScoreFooterPanel.IsSection` on the section's rows host); `Festival.Core/Domain/BandScoreFooterLayout.cs` `BandScoreFooterLayout.Stacks`, `BandScoreFooterSection`. Consumers: `Controls/SongBandPreviewRowView.xaml` (Song Detail), `Pages/BandsSongLeaderboardPage.xaml` (Song Band Leaderboard) |
| Pager | `FestivalUI/Features/Leaderboards/RankingsSupport.swift` `RankingsPagerView` | `ui/leaderboards/RankingsComponents.kt` `RankingsPager` | `Festival.App/Controls/LeaderboardsPager.xaml.cs` `LeaderboardsPager` |

### Agent decision: Android selected rows (#307)

Agent decision (2026-10-06, owner may override with `/choose`): Android pins the selected player's and band's rows on the solo and band song boards whenever the board returns them, as on the web and Apple, instead of hiding the footer while the row is on screen; the band board moved onto the shared `RankingsBoardLayout` so both footers sit above one pager, and the band footer reuses `SelectedScoreFooterRow` through `SongBandLeaderboardEntry.footerLeaderboardEntry`. Routes carry `navToPlayer` / `navToBand` with the page, and the reveal centres the row above the footer, instantly under Reduce Motion. Rejected: keeping hide-when-visible footers (a second rule beside web and Apple) and an in-list band footer (diverges from the solo board). MD3 Lists: "In Compose, prefer Material3 list patterns"; touch targets stay 48dp and TalkBack click labels name the destination.

### Agent decision: Android band board columns (#172)

Agent decision (2026-10-06, owner may override with `/choose`): on the full song band board, the member cards adopt the pinned footer row's geometry instead of the footer adopting the cards'. `bandBoardColumns` builds one plan from the page rows and the pinned band (rank width measured in both rank styles), fits the footer's `SelectedScoreFooterRow` with it (`rememberScoreColumns(minRankWidth)`) and starts the cards' rank at the footer's 20 dp inset with the footer's gap, so an off-page "#9,968" lines up with the page (R1, R5). R7 keeps the solo-style footer row, which the web also uses (`SongBandLeaderboardPage` renders `LeaderboardEntry` in its footer, although it sizes that rank column separately). Rejected: drawing the footer as a full member card (a four-member card pinned over the list costs most of a phone screen at 2.0 text and breaks R7), and shrinking the footer's insets to the card's 12 dp (the purple highlight would touch the card edge). Song Detail's band cards keep their 12 dp inset and 10 dp gap, as Song Detail's solo cards keep theirs. `StackedScoreRow` now puts its 8 dp gap outside the shared rank width, so names start at the same x on every large-text row. MD3 Lists: "In Compose, prefer Material3 list patterns".
## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple’s fitter decides difficulty and stars, but Apple score rows do not yet render them. | Full web metadata parity on Apple score rows. | `TODO(orchestrator): scope the missing Apple score metadata columns.` |

## Guards (`tools/pattern_guard.py`)

- `leaderboard-row/apple-name-owner`
- `leaderboard-row/android-row-metrics`
- `leaderboard-row/windows-row-metrics`
- `leaderboard-row/windows-pager-owner`
- `leaderboard-row/windows-score-footer-owner`: no second score-footer panel, line plan or section plan outside the canonical files (R8). The guard can only forbid; consumers are listed in the canonical table and their page notes.
