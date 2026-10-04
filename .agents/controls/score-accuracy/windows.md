# Score accuracy — Windows notes

> **What:** the WinUI 3 badge implementation, its test fixture and the issue #220 validation. **Read when:** changing `LeaderboardEntryRow`'s pill, `ScoreBadge` or the score-row models on Windows. Spec: [spec.md](spec.md).

## Implementation

- `windows/Festival.App/Controls/LeaderboardEntryRow.xaml(.cs)` is the one shared score row: Song Details top-ten preview, full song chart, Leaderboards spotlight footer and score history. The badge is `Pill` (a 58 × text-scale epx `Border`, `BackgroundSizing="OuterBorderEdge"`) holding `PillText`.
- Text policy is in Core: `ScoreFormatting.BadgeText(accuracy, fullCombo)` returns the formatted % (rounded to 0.1, decimal only when needed), `FC` for an explicit full combo without accuracy, or empty for no badge. `ILeaderboardScoreRow.BadgeText` exposes it, and `LeaderboardColumns.Measure` reserves the column when any row on the board has a badge, so `FC`-only and graded rows still line up.
- Brushes: `ScoreBadge.Fill/Stroke/Skew`. A graded pill is the web's red→green tint at 25% (`ScoreFormatting.AccuracyTint`, unit-tested at 0/50/98/100%, out of range and non-finite). A full combo is the gold #CFA500 2-epx outline, gold bold italic text, skewed −8°. Under a contrast theme the pill uses the `FSTNeutralPill*` system brushes (ButtonFace/ButtonText) instead of the data tint.
- The web pill draws a 2 px transparent border over a border-box background. WinUI's default `InnerBorderEdge` left graded tints 2 epx narrower per side than the gold outline; `OuterBorderEdge` matches the web (issue #220).
- The FC skew pivots on the pill's centre (`RenderTransformOrigin="0.5,0.5"`, CSS's default `transform-origin`). A fixed `CenterY = 10` only centred the ~20-epx pill at 100% text; at 200% text the gold badge drifted ~2 epx left of the graded pills (issue #220).
- The row fits its columns in `MeasureOverride`, from the width the list offers, before the grid measures. Fitting them only on `SizeChanged` let a row realized while scrolling at 200% text keep its one-line height after stacking its score and badge, so they drew over the next row (seen on the live board at compact width; issue #220).
- UI Automation: each row is **one** button stop whose name carries the whole row ("Rank #4, Fixture Player 4, 99,600 points, full combo, accuracy unavailable, 5 stars"). The pill is `AccessibilityView=Raw`, so it is not read twice. `PillText` still carries an automation ID for tests: `fst.score.accuracy.<accountId>` (full chart), `fst.score.accuracy.preview.<Instrument>.<accountId|rank-N>` (Song Details), `fst.score.accuracy.history.<yyyyMMddHHmmss>[.detail]` and `fst.score.accuracy.<row-id suffix>` for pinned copies (e.g. `spotlight-footer`). Select them with the driver's `raw=` selector.
- Announcements: `ScoreFormatting.FullComboAnnouncement(hasAccuracy)` gives "full combo" or "full combo, accuracy unavailable"; the % is spoken as "N% accuracy". A full combo is never inferred from 100%.

## Design decisions (winui-design)

- `winapp find-ui "badge"` offers `InfoBadge` (a notification count/dot on an icon). It isn't a value pill, so the badge stays a `Border` + `TextBlock` with the web's measurements.
- **Deviation from the spec's native rule:** an FC with accuracy shows the gold, bold, italic, skewed % without a separate `FC` text (as the web, iOS and the Windows design history in [design/windows.md](../../design/windows.md) do). Colour is never the only cue: the outline shape, italic and skew differ from graded pills, and the row name says "full combo".
- `theme-accessibility.md` ("Use system colors in high contrast"): the data-driven tint is replaced by ButtonFace/ButtonText under a contrast theme; FC keeps its outline shape and italic.
- Dark-only app theme (deliberate, see [design/windows.md](../../design/windows.md)): the light system theme still renders the dark pills.
- The pill keeps the web's fixed `FontSize="12"` SemiBold rather than `CaptionTextBlockStyle`, and scales with text size via `LeaderboardColumns` (rows stack under large text, and the column widens).

## States and reachability

Fixture: `tools/windows/score_accuracy_fixture.py` rewrites ranks 1–7 of every `/api/leaderboard/fixture-*/Solo_Guitar` page on the mock service (26 entries, two pages); other ranks keep the mock's ~98% values (FC on even ranks).

| State | Reached by | Evidence |
|---|---|---|
| `graded-high` | Rank 1, 99.5% | `assertname:raw=fst.score.accuracy.fixture-player-1\|99.5%` (chart and preview) |
| `full-combo` | Rank 2, 100% + FC | gold `100%` |
| `absent` | Rank 3, no accuracy or FC | `waitgone:raw=…-3` (no badge, column kept) |
| `full-combo-no-accuracy` | Rank 4, FC without accuracy | gold `FC`, name "full combo, accuracy unavailable" |
| `graded-mid` / `graded-low` | Ranks 5 / 6, 50% / 12% | neutral / red tint |
| `invalid` | Rank 7, 105% (out of range; colour clamps green) | `105%`; non-finite tint and text are Core-only (`ScoreAccuracyTests`), as JSON can't carry NaN |
| `aligned-columns`, `missing-accuracy-aligned` | Ranks 1–7 | `assertaligned:` pill centres within 2 px, including across the absent row |
| `badge-contrast` | `--mode hc-desert` / `hc-night-sky` | Axe 0 + screenshots |
| `normal-audit` | Normal mode, all sizes | Axe 0 |
| `preview` | Song Details Lead preview | `score-accuracy-preview` page |
| `full-chart` | `/songs/fixture-pulse/Solo_Guitar` | `score-accuracy-chart` page |
| `large-text` | `--mode text-200` | Rows stack, pill widens, no clipped digits |
| `sidebar-transition` | Window resize compact → wide → medium (pane modes change) | `score-accuracy-resize` page (badges keep their names and alignment) |
| `offscreen-targets` | Rank 20 below the fold | `scrollinto:raw=…-20` then `assertname` (`score-accuracy-offscreen`) |

Run: `python tools/windows/a11y_matrix.py --pages tools/windows/journeys/score-accuracy.json --fixture tools/windows/score_accuracy_fixture.py --scan --tabs 15 --out DIR [--mode …] [--sizes …]`. Unit tests: `ScoreAccuracyTests` (Core) and `tools/windows/tests/test_score_accuracy.py`.

## Validation (issue #220, 2026-10-03)

Fixture matrix (`a11y_matrix.py`, pages above, Axe.Windows scan on every run):

| Configuration | Result |
|---|---|
| Compact / medium / wide, maximized, snap-left, snap-right (normal) | 30/30 pass, Axe 0. Every state's name, absent badge and column alignment held; chart Tab walk 7 stops (compact/snapped) or 9 (pane open) with the list as one stop |
| Resize compact → wide → medium (`sidebar-transition`) | Pass at every start size; badges keep their names and centres through pane-mode changes |
| High contrast Aquatic, Desert, Night sky | Pass, Axe 0. Graded pills become ButtonFace pills with a system-colour outline; FC stays italic and skewed, so it differs by shape and style, not colour alone |
| Light / dark system theme | Pass, Axe 0; the app stays dark (deliberate) |
| Display 100% / 150% | Pass, Axe 0; pills crisp, graded and FC outlines the same width |
| Text 200% | First run failed: FC centres sat ~2 epx left of graded pills (fixed skew pivot), and compact couldn't reach rank 20 because the stacked list hadn't realized it (driver `scrollinto` now pages the list). After the fixes 15/15 pass, Axe 0; rows stack the score and badge under the name, the pill widens with the text, no clipped digits. The live board then showed a row realized while scrolling keeping its one-line height, its stacked score and badge drawn over the next row; rows now fit in the measure pass (rechecked live and with the fixture, 15/15 pass) |
| Keyboard | Row list one Tab stop; Down/Up row to row; Tab exits to the pager; focus visual on the row |

Live service (anonymous, default HTTPS origin, "Through the Fire and Flames" Lead): gold FC 100% badges beside a graded green 100% pill (rank 12, no FC) on page 1, 73–91% tints on the last page, Song Details preview, Night sky and Desert contrast, and 200% text at compact width all render as above. `absent`, `full-combo-no-accuracy` and `invalid` can't occur in live data (the service's accuracy is a non-nullable integer), so they are fixture-only.

- Keyboard: the row list is an `ItemsRepeater` with XY keyboard navigation, so it's one Tab stop; Down/Up move row to row (verified 1→2→3→4, Up→3) and Tab leaves to the pager. **Open (list-level, not this control):** Shift+Tab back into the list focuses the last realized row rather than the last-focused one.
- The console was locked during this pass, so Narrator itself wasn't run. Reading order was checked from the UIA names: each row reads rank, name, score, accuracy, FC, stars once.
