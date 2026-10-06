# Chart date axis

> **What:** where the date labels sit on history bar charts (one bar per score or snapshot). **Read when:** adding or changing a chart's x axis, or any chart whose bars stand for dates.

Status: **current**, 2026-10-05. Provenance: #314.

## Intent

A date names the bar above it. Each date label is horizontally centred on its bar, so it never reads as belonging to the neighbouring bar, at every page of a paged chart and at every text size.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songinfo/components/chart/ScoreHistoryChart.tsx` (`ScoreHistoryChart`) | Recharts category `XAxis` on `dateLabel`: each tick sits at its bar's category centre (angled, `textAnchor="end"`). |
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankHistoryChart.tsx` (`RankHistoryChart`) | The same axis for rank history (Profile, Leaderboards); `interval="preserveStartEnd"` hides colliding ticks and keeps the ends. |
| `FortniteFestivalWeb/src/components/common/chartVisuals.ts` (`CHART_X_AXIS_TICK`) | Shared tick style and angle (`CHART_X_AXIS_ANGLE`, `textAnchor="end"`). |

Natives draw the labels horizontally (one bar per ≥ 96 pt slot leaves room); the anchor point (the bar's centre) is the web's.

## Rules

1. **R1. Centre each date on its bar.** The label's horizontal centre equals its bar's centre (within glyph side bearings), on every visible page. HIG Charts (consider): "Anchor an unassociated-looking label to its grid line with a tick."
2. **R2. Label only visible bars.** A paged chart labels the bars in its visible window; paging, dragging or resizing recomputes the labels from the same visible bars, so they move with their bars.
3. **R3. Keep tick text out of the accessibility tree.** Bars carry their dates in their accessibility labels and the axis is one static element; HIG Charts: "Hide visible axis and tick text labels from assistive technologies."
4. **R4. One axis component per platform.** Charts get their date axis from the canonical component below, not a feature-local axis.
5. **R5. Never clip.** A first or last label that would cross the chart's edge is pinned just inside it (it may extend into the axis gutters); it is never truncated. The date row is as tall as its tallest label at the current text size, never a fixed band sized for default text (#314 review: a fixed 18 dp canvas band cut the dates off at 200%).
6. **R6. Hide collisions, never overlap.** When labels don't fit (narrow bars, large text), hide labels that would touch a shown neighbour, as web `preserveStartEnd` does: the newest (last) label always shows, the first shows when it fits beside the last, then the rest fill in left to right. Labels follow the platform's text size and stay on one line.
7. **R7. Horizontal, not angled.** The web's angled ticks (`CHART_X_AXIS_ANGLE`) are a narrow-viewport web device; native labels stay horizontal and use R6 instead (agent decision, #314; Windows `RankHistoryGraph` and Android `SongHistoryCard` precedent; the owner may override).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Date per bar, centred | `apple/Sources/FestivalUI/Common/BarChartDateAxis.swift` `barChartDateAxis` (Swift Charts `AxisMarks(preset: .aligned)`; the default numeric preset put the label's leading edge at the tick, and `AxisValueLabel(anchor:)` alone did not move it) `android/app/src/main/java/com/festivalscoretracker/android/core/profile/PlayerCharts.kt` `ChartGeometry.bandLabelLefts` (R1, R5, R6 placement), laid out by `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ChartBandLabels.kt` `ChartBandLabels` | `windows/Festival.App/Controls/RankHistoryGraph.cs` `RankHistoryGraph`, `windows/Festival.App/Controls/SongScoreHistoryChart.xaml.cs` `SongScoreHistoryChart` (slot-wide, centre-aligned date) |

Android consumers: `ChartBandLabels` under the Profile (`ui/profile/RankHistoryCard.kt`) and Leaderboards (`ui/leaderboards/RankHistoryCard.kt`) rank-history plots and under the Song Details `SongHistoryCard` canvas (its plot keeps a fixed height; the date row below grows with the text). Canvas charts never draw their own dates. The Player History line chart's start/end dates are inset to sit under the plot, not the y-axis gutter.

Apple consumers: `RankHistoryCharts` (Profile, Statistics, Leaderboards rank-history pane, dual-source Profile) and `SongScoreHistorySection` (Song Details, Player History), on iPhone, iPad, iPhone Duo and Mac. The first-run Song demos plot categorical (string) dates, which Swift Charts already centres.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Windows date `TextBlock`s are slot-wide without collision hiding; not checked at large text scale | R5, R6 (unverified) | Windows lane |

## Guards (`tools/pattern_guard.py`)

- `chart-date-axis/apple-x-axis`
- `chart-date-axis/android-local-centring`
- `chart-date-axis/android-band-labels`
