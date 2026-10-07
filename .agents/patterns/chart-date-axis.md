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

Natives keep the web's anchor point (the bar's centre) and its `preserveStartEnd` thinning. They draw labels horizontally instead of at the web's angle (R7 and its decision record).

## Rules

1. **R1. Centre each date on its bar.** The label's horizontal centre equals its bar's centre (within glyph side bearings), on every visible page. HIG Charts (consider): "Anchor an unassociated-looking label to its grid line with a tick."
2. **R2. Label only visible bars.** A paged chart labels the bars in its visible window; paging, dragging or resizing recomputes the labels from the same visible bars, so they move with their bars.
3. **R3. Keep tick text out of the accessibility tree.** Bars carry their dates in their accessibility labels and the axis is one static element; HIG Charts: "Hide visible axis and tick text labels from assistive technologies."
4. **R4. One axis component per platform.** Charts get their date axis from the canonical component below, not a feature-local axis.
5. **R5. Never clip.** A first or last label that would cross the chart's edge is pinned just inside it (it may extend into the axis gutters); it is never truncated. The date row is as tall as its tallest label at the current text size, never a fixed band sized for default text (#314 review: a fixed 18 dp canvas band cut the dates off at 200%).
6. **R6. Hide collisions, never overlap.** When labels don't fit (narrow bars, large text), hide labels that would touch a shown neighbour, as web `preserveStartEnd` does: the newest (last) label always shows, the first shows when it fits beside the last, then the rest fill in left to right. Labels follow the platform's text size and stay on one line.
7. **R7. Horizontal, not angled.** Native date labels stay horizontal and centred on the bar's centre (the web's anchor point), and R6 handles crowding instead of the web's −35° ticks (`CHART_X_AXIS_ANGLE`). **Agent decision (#314, 2026-10-06): option A below; owner may override with `/choose`.**

## Decision record: label orientation (#314)

**Question.** The owner asked: "[Bug] in graphs, date should be centered on its bar. Looks more right aligned." Should native date labels copy the web's angled ticks, or stay horizontal and drop labels that don't fit?

**Evidence.**

- **Web** (`SFenton/FortniteFestivalLeaderboardScraper` @ `35fb548899`): `ScoreHistoryChart` and `RankHistoryChart` use `XAxis angle={CHART_X_AXIS_ANGLE} textAnchor="end" interval="preserveStartEnd"`. `CHART_X_AXIS_ANGLE` is `Layout.chartXAxisAngle = -35` (`packages/theme/src/spacing.ts`). With `textAnchor="end"`, the label's **end** sits at the bar's centre and the text runs down and to the left, so the label's visual centre is to the left of the bar.
- **Native precedent (before #314):** all horizontal. Windows `RankHistoryGraph` (a slot-wide date `TextBlock`, `TextAlignment.Center`) and `SongScoreHistoryChart` (`AddText(point.DateLabel, centre - slot / 2, …, TextAlignment.Center)`) rotate only the y-axis title. Android `SongHistoryCard` drew `drawText(label, axis + slot * i + (slot - label.width) / 2, …)` with no rotation. Apple `barChartDateAxis` uses horizontal Swift Charts `AxisValueLabel`s.
- **Material 3** (`material-3` skill: `SKILL.md` and `references/`): there is **no chart, axis or data-visualization recommendation**, so no M3 rule favours either orientation. General guidance applies to both options: the Label type role "Buttons, chips, captions" (consider) and "TalkBack/semantics … verify contrast" (should). R3 and the existing label style meet both.
- **Apple HIG Charts** (consider; the triage guidance): "Anchor an unassociated-looking label to its grid line with a tick." A label reads as belonging to the bar its centre is above.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| **A. Horizontal, centred, R6 collision hiding** | Each date sits level and centred under its bar. Crowded labels drop out, keeping the newest. | M3: no chart guidance. HIG Charts anchoring (consider): met. | Web anchor point and `preserveStartEnd` thinning. Windows, Android and Apple native charts were already horizontal. | At very large text, fewer dates show; every bar still names its date to TalkBack (R3). |
| B. Web-style −35°, end-anchored | Slanted dates whose last letter touches the bar's centre line. | M3: none. HIG anchoring: weaker, because the text body lies left of the bar. | Literal web copy. No native precedent. | The visual centre is left of the bar, which repeats the owner's "not centred" complaint in the other direction. A rotated row is taller and grows with font scale, so the plot or card shrinks. Rotated text is harder to read. |
| C. Horizontal, rotating only when crowded | Level dates, which switch to slanted ones on narrow bars or large text. | M3: none. | No web or native precedent. | Two looks for one axis. Same centring problem as B when rotated. More code and more states to test. |

**Chose A.** No platform *must* applies (M3 is silent on charts). The owner's explicit request comes next: the date should be *centred* on its bar. Only A centres every shown label, because B and C end-anchor rotated text left of the bar. A keeps the web's semantics (the tick anchors at the bar's category centre, and colliding ticks are thinned as `preserveStartEnd` does, R6) without copying its narrow-viewport rotation. It is also the existing behaviour on every native platform (least churn). The choice was not prototyped as screenshots: B and C contradict the owner's wording at the geometry level, before any styling.

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
