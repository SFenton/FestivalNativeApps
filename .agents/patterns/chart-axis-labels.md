# Chart axis labels

> **What:** where a bar chart's category (date) labels sit relative to their bars: centring, edge pinning, collision hiding and accessibility. **Read when:** drawing or changing a bar chart's x-axis labels (Profile and Leaderboards rank history, Song Detail score history) or adding a new bar chart.

Status: **current**, 2026-10-05. Provenance: #314.

## Intent

Each date reads as belonging to its own bar. A label offset from its bar (pinned to the plot edges, or right-aligned) reads as the neighbouring bar's date.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankHistoryChart.tsx` (`RankHistoryChart`) | Recharts category `XAxis` (`dataKey="dateLabel"`): one tick per bar, anchored at the bar's band centre, `interval="preserveStartEnd"` hides colliding ticks and keeps the ends. |
| `FortniteFestivalWeb/src/pages/songinfo/components/chart/ScoreHistoryChart.tsx` (`ScoreHistoryChart`) | The same axis for the score-history bars. |
| `FortniteFestivalWeb/src/components/common/chartVisuals.ts` (`CHART_X_AXIS_TICK`) | Shared tick style and angle (`CHART_X_AXIS_ANGLE`, `textAnchor="end"`). |

## Rules

- **R1. One label per bar, centred on it.** A category label's horizontal centre is its bar's band centre (web tick anchor). Labels never sit at the plot's edges independent of the bars.
- **R2. Never clip.** A first or last label that would cross the chart's edge is pinned just inside it (it may extend into the axis gutters); it is never truncated.
- **R3. Hide collisions, never overlap.** When labels don't fit (narrow bands, large text), hide labels that would touch a shown neighbour, as web `preserveStartEnd` does: the newest (last) label always shows, the first shows when it fits beside the last, then the rest fill in left to right. Labels follow the platform's text size; they are one line.
- **R4. Labels follow the window.** Paging, dragging or resizing recomputes the labels from the same visible bars, so they stay under their bars.
- **R5. Decorative for assistive technology.** Axis dates are hidden from TalkBack, VoiceOver and Narrator; the chart's description or per-bar labels carry the dates.
- **R6. Horizontal, not angled.** The web's angled ticks (`CHART_X_AXIS_ANGLE`) are a narrow-viewport web device; native labels stay horizontal and use R3 instead. Established by Windows `RankHistoryGraph` and Android `SongHistoryCard`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Rank history date axis | `apple/Sources/FestivalUI/Features/Profile/PlayerProfileCharts.swift` `RankHistoryCharts` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ChartBandLabels.kt` `ChartBandLabels` | `windows/Festival.App/Controls/RankHistoryGraph.cs` `RankHistoryGraph` |
| Score history date axis | `apple/Sources/FestivalUI/Features/SongDetail/SongScoreHistorySection.swift` `SongScoreHistorySection` | `android/app/src/main/java/com/festivalscoretracker/android/core/profile/PlayerCharts.kt` `bandLabelLefts` (canvas) | `windows/Festival.App/Controls/SongScoreHistoryChart.xaml.cs` `SongScoreHistoryChart` |

Android: `ChartGeometry.bandLabelLefts` is the one placement rule (R1–R3). `ChartBandLabels` lays it out as a row under the Profile and Leaderboards rank-history plots; `SongHistoryCard` calls it from its canvas.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple rank and score history use the default Swift Charts `AxisValueLabel` placement (#314) | R1 | Apple lane, #314 |
| Windows date `TextBlock`s are slot-wide without collision hiding; not checked at large text scale | R2, R3 (unverified) | Windows lane |

## Guards (`tools/pattern_guard.py`)

- `chart-axis-labels/android-local-centring`
