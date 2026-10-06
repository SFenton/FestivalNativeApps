# Chart date axis

> **What:** where the date labels sit on history bar charts (one bar per score or snapshot). **Read when:** adding or changing a chart's x axis, or any chart whose bars stand for dates.

Status: **current**, 2026-10-05. Provenance: #314.

## Intent

A date names the bar above it. Each date label is horizontally centred on its bar, so it never reads as belonging to the neighbouring bar, at every page of a paged chart and at every text size.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songinfo/components/chart/ScoreHistoryChart.tsx` (`ScoreHistoryChart`) | Recharts category `XAxis` on `dateLabel`: each tick sits at its bar's category centre (angled, `textAnchor="end"`). |
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankHistoryChart.tsx` (`RankHistoryChart`) | The same axis for rank history (Profile, Leaderboards). |

Natives draw the labels horizontally (one bar per ≥ 96 pt slot leaves room); the anchor point (the bar's centre) is the web's.

## Rules

1. **R1. Centre each date on its bar.** The label's horizontal centre equals its bar's centre (within glyph side bearings), on every visible page. HIG Charts (consider): "Anchor an unassociated-looking label to its grid line with a tick."
2. **R2. Label only visible bars.** A paged chart labels the bars in its visible window; labels move with their bars while paging.
3. **R3. Keep tick text out of the accessibility tree.** Bars carry their dates in their accessibility labels and the axis is one static element; HIG Charts: "Hide visible axis and tick text labels from assistive technologies."
4. **R4. One axis component per platform.** Charts get their date axis from the canonical component below, not a feature-local axis.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Date per bar, centred | `apple/Sources/FestivalUI/Common/BarChartDateAxis.swift` `barChartDateAxis` (Swift Charts `AxisMarks(preset: .aligned)`; the default numeric preset put the label's leading edge at the tick, and `AxisValueLabel(anchor:)` alone did not move it) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongHistoryCard.kt` `SongHistoryCard` (`drawText` at `axis + slot*i + (slot - width)/2`) | `windows/Festival.App/Controls/RankHistoryGraph.cs` `RankHistoryGraph`, `windows/Festival.App/Controls/SongScoreHistoryChart.xaml.cs` `SongScoreHistoryChart` (slot-wide, centre-aligned date) |

Apple consumers: `RankHistoryCharts` (Profile, Statistics, Leaderboards rank-history pane, dual-source Profile) and `SongScoreHistorySection` (Song Details, Player History), on iPhone, iPad, iPhone Duo and Mac. The first-run Song demos plot categorical (string) dates, which Swift Charts already centres.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `ui/profile/RankHistoryCard.kt` and `ui/leaderboards/RankHistoryCard.kt` show only the first and last dates in a `SpaceBetween` row at the plot edges | R1, R4 | Android check filed from #314 |

## Guards (`tools/pattern_guard.py`)

- `chart-date-axis/apple-x-axis`
