# Solo accuracy and full combo (`fst.score.accuracy.*`) - partial Apple control

Source: `FortniteFestivalWeb/src/components/songs/metadata/AccuracyDisplay.tsx:13-47`,
`FortniteFestivalWeb/src/utils/formatters.ts:5-12`,
`packages/core/src/app/formatters.ts:160-171`,
`FortniteFestivalWeb/src/pages/leaderboard/global/components/LeaderboardEntry.tsx:105-147`,
`packages/theme/src/spacing.ts:142-150,244-253`,
`packages/theme/src/goldStyles.ts:17-34`, and
`FortniteFestivalWeb/src/pages/songinfo/components/InstrumentCard.tsx:226-253`.
The source checkout is independently dirty; check `contracts/source-snapshot.json`
before parity claims. Never infer a full combo from an accuracy number alone.

| Response state | Source display | Native Apple control |
|---|---|---|
| Accuracy, `isFullCombo: false` or missing | Rounded percentage pill with red-to-green background at 25% opacity | Native Fluent rounded pill with the same bounded color interpolation, white percentage and spoken "Accuracy N%" |
| Accuracy, `isFullCombo: true` | Gold outlined percentage | Gold outlined native pill visibly prefixed `FC`, announced "Full combo, accuracy N%" |
| No accuracy, explicit FC | If rendered, source displays a gold outlined `0%` | Native shows `FC` / "Full combo; accuracy unavailable" instead of inventing 0%; intentional divergence |
| Neither accuracy nor FC | If the source accuracy column is shown, its component displays a graded red `0%` | No native badge or inferred FC; intentional divergence for unknown data |
| Nonfinite / out-of-range accuracy | Source coerces `NaN` to `0%`; color clamps finite percentages to 0-100 | Native rejects nonfinite tint input with an explicit error; finite out-of-range values retain their number but clamp the color, not the whole response |
| Accessibility-size text | Compact source row adapts to space | Native expands the label, stacks values and lets the pill wrap without clipping score digits |

The shared `SongLeaderboardEntryRow` renders both Song Detail's lazy
top-ten preview and the full 25-row Solo chart, so the badge policy
must agree between them. Keep rank, player name, whole score and the
accuracy pill independently accessible. The visual gold stroke is
supplemented by both visible `FC` text and a spoken full-combo label;
color alone is not the state. Native uses a Fluent rounded border
and white text instead of the source's skewed, gold/bold/italic web
outline. These are intentional Fluent/accessibility differences, not
pixel parity. Its white text remains legible on an opaque card even
when album art is pure white. Source column mode reserves a width;
compact source rows may place accuracy inline instead.

At ordinary native text sizes reserve the same scaled **80pt text /
96pt outer badge × 24pt height** column for graded, FC and missing-accuracy rows;
the latter is invisible and excluded from accessibility. Use an
explicit compact frame, **not SwiftUI padding** inside the shared badge:
a matched iPadOS 26.5 baseline at `31b783e` passed Hide Sidebar,
whereas padding added with this badge reproduced a real main-thread
split-view/hosting-scroll-layout loop. A 5-second sample showed all
main-thread samples in UIKit/SwiftUI layout after the toggle. A plain
helper and the full graded/gold badge with explicit frame/no padding
both pass the same iPad Paths journey; the padded variant does not.
The selected Detail→Solo test also restored the sidebar transition
and asserts equal-digit FC/non-FC score right edges and badge left
edges within **1pt** on iPhone and iPad. Accessibility-size stacked
values keep unconstrained width and whole scores. An initial 30pt
badge increased List row height and introduced an unnamed iPad Solo
"Contrast nearly passed" full-audit failure despite individually
readable badge pixels. Reducing just its ordinary-size height to 24pt
restored both page-one and page-two unwaived iPad `.all` audits with
the graded fill and gold stroke intact. Badge text also passes a
direct ≥4.5:1 rendered-pixel check on the selected phone/tablet cases.

`ScoreFormatting.accuracyTint` must match the source's clamped RGB
endpoints and midpoint exactly; unit tests cover 0/50/98/100%, bounds
and nonfinite rejection. A hosted five-state visual test distinguishes
missing, unknown-FC, low-accuracy, explicit FC and FC-without-accuracy
using actual gold/red/green pixels. The selected native preview/full
chart test asserts fixture odd non-FC and even FC rows with badge
pixel counts and accessible labels. A synthetic Lead rank 3 omits
accuracy and explicitly reports non-FC while rank 4 has explicit FC
but **no** accuracy;
selected native iPhone/iPad tests compare their score right edges
to populated equal-digit rows within 1pt in **both** Detail and
Solo, require no phantom badge for rank 3 and a gold/spoken FC
without fabricated 0% for rank 4. The large-text Solo case checks
rank 1 and rank 26's distinct spoken state. These selected tests do
not certify every contrast, focus or device state. Missing accuracy
on these chart rows is a **synthetic robustness state**, not evidence
that the current service omits it: the song leaderboard entry DTO
uses a nonnullable integer and the song chart copies that value
(`FSTService/Persistence/DataTransferObjects.cs:9-16`,
`FSTService/Api/LeaderboardEndpoints.cs:389-405`). The service's
JSON option omits nulls, not a nonnullable zero
(`FSTService/Program.cs:88-97`).

On the full Solo List, `.accessibilityElement(children: .contain)` keeps
the badge's own `fst.score.accuracy.*` ID alongside the row ID.
Detail currently inherits `fst.song-detail.preview-row.*` and the
badge's spoken label; its separate child ID/focus remains pending.
Removing `.contain` from Detail did **not** independently fix the
iPad timeout, so do not attribute the cause to that wrapper. The
selected sidebar-on iPad Paths and Detail journeys now pass after
the no-padding layout fix; no-toggle tests alone would not have
proved this. A full Detail audit, VoiceOver focus bounds and
all-state four-platform automation remain open. This control and
both pages are **pending**, not parity-certified.

The larger ten-row native card also exposed an iPhone
offscreen-auto-scroll hazard when its headerless freshness
notice pushed the bottom View Full link farther away. A user-like
swipe and an unobstructed link both worked; the link is now
immediately below the chart title rather than after rows as on
the PWA. Test its direct native hit target and actual
ten-row→25-row request before treating preview navigation
as usable offline. Other automatic accessibility scrolling
and the full Detail page audit remain separate gaps.

The source only offers View All on nonempty, error-free previews,
whereas native View Full already existed during loading, empty and
error states *before* this FC slice. Moving it to the top changes
focus order, not state availability; a separate Settings/Detail
parity decision is still needed. The serial local runner gives
the iPhone offscreen Lead row, offscreen empty Bass chart, and
warm-offline Solo journey **distinct unpinned score-one-shot
listeners on ports 8774, 8775 and 8772 respectively**. Two
selected synthetic iPhone offscreen targets pass, but these
do not certify real-data/VoiceOver focus scrolling.
