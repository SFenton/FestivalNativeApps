# Statistics — Windows notes

> **What:** how the Windows Statistics section renders the selected player's profile. **Read when:** changing `windows/Festival.App/Pages/StatisticsPage*` or the follow-selection mode of `PlayerProfileViewModel`. Shared page: [player-profile/windows.md](../player-profile/windows.md).

- `AppSection.Statistics` root page is `StatisticsPage`, hosting the same `PlayerProfileView` as `/player/:id` with `PlayerProfileViewModel(session, accountId: null)` (`FollowsSelection`). It is always the "This Is Me" state (web `App.tsx` routes `/statistics` to `PlayerPage` for the tracked player).
- It mirrors the session's selected-player read (`FestivalSession.SelectedProfile`/`SelectedProfileStatus`) instead of reading again; Retry forces `LoadSelectedProfileAsync(force: true)`.
- Per-entity reset: a switch re-targets the page to the new account and reloads; a deselect removes the section (the shell falls back to Songs) and the page shows `fst.player.no-profile` for the brief interval before that.
- The section frame keeps the page alive across section switches (`FrameHost` swaps frames without navigating), so the view model keeps following the selection while hidden.
- Root automation ID `fst.statistics`; everything inside uses the `fst.player.*` IDs. Layout, stat links and motion: [player-profile/windows.md](../player-profile/windows.md) (Statistics is always the selected player, so every link opens at once).

## Validation (issue #204)

Checked 2026-10 with the winui-design and winui-code-review skills, `a11y_matrix.py --scan` (fixture pages `statistics` and `statistics-chart`) and the live public service (SFentonX). Axe.Windows reported 0 errors in every row, with no focus outside the app and no repeated stops.

| Configuration | Finding |
|---|---|
| Compact (500 epx), snap-left, snap-right | Stat cards in 2 columns at compact and 3 when snapped left; the chart pages 3 bars at compact. Correct. |
| Medium, wide, maximized | 4 card columns, and the chart fills the card. Correct. |
| Keyboard only | Header → Deselect → Quick Links → overview stat links → rank-history plot (arrows page; then `.older`/`.newer`) → instrument stat links → percentile rows → Bands See All (`fst.player.bands-link`) → band cards → View All Bands. Each stop shows the system focus visual. |
| High Contrast (Desert, Night sky) | **Fixed:** the Rank History bars were translucent brand fills with no outline, and the gridlines (20% white) disappeared on Desert's cream background. In contrast themes, `RankHistoryGraph` now draws opaque bars outlined in `FSTChartAxisBrush` (WindowText), gridlines in the same brush, and an outlined legend swatch. It redraws on `UISettings.ColorValuesChanged`. The placement hues and the `#4C7DFF` rank line stay as data colours (about 3.5:1 on Desert, 5.7:1 on Night sky); the legend and each bar's UIA name carry the values. |
| Light and dark system theme | Both render the same, a deliberate deviation: the app is dark only ([design/windows.md](../../design/windows.md#content-branded-fluent-tokens)). |
| Text 200% | Tiles grow taller without clipping. **Fixed:** the chart's axis labels were clipped ("89.4\|") by fixed 52/48 epx gutters. The gutters, date band and label centring are now measured from the scaled text (`RankHistoryCombined.AxisGutter`, unit-tested), and the chart re-measures on `TextScaleFactorChanged`. The shell's notification badge no longer overflows at 200% (fixed in #229, rechecked in #253). |
| Display 100% / 150% | Correct. |
| Narrator / UIA | Stat cards are buttons named with value, label and destination help text. The chart plot is one stop with a summary name, and each bar carries "date, score, rank". Headings are marked, and the reading order follows the Tab order. |

UI journeys (`profile.py`): `statistics-content` (cards, chart and older/newer paging), `statistics-quick-links`, `statistics-link` (Lead Songs Played → filtered Songs), `statistics-syncing`, `statistics-denied`, `statistics-empty`, `statistics-unranked` and `statistics-rank-fail`. A rank-history read failure has no fixture route; `PlayerViewModelTests` covers it. Pre-existing failures, unchanged by #204: `select`, `history*`, `bands-scope`, and in `bands.json`, `band-detail-rank-history-chart` (it `invoke`s a Quick Links `ToggleMenuFlyoutItem`, which needs `toggle:`).
