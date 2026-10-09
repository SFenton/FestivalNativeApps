# Band Detail — Windows notes

> **What:** what the Windows Band Detail page implements, its safe lookup and open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsDetailPage*` or `BandDetailViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Data (safe lookup only)

| Read | Endpoint | Notes |
|---|---|---|
| Band row | `GET /api/rankings/bands/{bandType}?teamKey=&rankBy=adjusted&page=1&pageSize=1` → `selectedBandEntry` | `null` → 404 "Band not found". Never `/api/bands/{bandId}` or `/api/rankings/bands/{bandType}/{teamKey}`: both call `GetBandConfigurations` (writes on a cache miss, see [service-safety](../../platforms/service-safety.md)) |
| Rank history | `…/{bandType}/{teamKey}/history?days=30` | `historyStatus` `catching_up`/`stale`/`disabled`/`failed` or `historyMessage` → note under the heading (web `band.rankHistory*`) |
| Best/worst | `…/{bandType}/{teamKey}/songs?limit=5` | 503 + `Retry-After` until the band-song projection is published → inline status + Retry |

`AppRoute.Band(bandId, bandType?, teamKey?)` must carry the type and key from the originating row (player bands, song band leaderboard, band rankings). A bare `bandId`, unknown type or unsafe key shows **Band Not Available** (`fst.band.unresolved`) and makes no request. `BandEndpoints.IsValidTeamKey` accepts 1–4 `:`-joined account IDs (the service joins sorted member IDs; the fixture mock uses one synthetic segment).

## Layout

- Header: joined member names (heading 1), `Duos · N appearances` (appearances = `songsPlayed`, as the web builds it from the ranking row).
- Members: `UniformGridLayout` (min 260 epx) of member cards — name + 32 px instrument icons + chevron; the card opens `AppRoute.Player`.
- Band Summary: Type, Appearances, Members.
- Band Statistics: **Rank By** `ComboBox` with a visible `Header` "Rank By" (its UIA name; default Total Score, the web's non-experimental metric; shown only with Settings' Experimental Ranks on, otherwise Total Score, issue #541), bottom-aligned with the heading. The card repeater sets `TabFocusNavigation="Local"` so Tab reaches every card. Cards: `<Metric> Rank` (links to `AppRoute.BandRankings`), Songs Played, Full Combos, Total Score, FC Rate, Avg Accuracy (`avgAccuracy ÷ 10,000`, one decimal), Avg Stars, Best Song Rank (links to Song Detail once the best song resolves in the catalogue), Avg Rank. `—` for zero/absent values.
- Band Rank History (web `BandRankHistoryChart` + `GraphCard`): the shared combined chart (`Controls/RankHistoryGraph`, model `RankHistoryCombinedChart.BuildBand`) with the selected metric's value as bars coloured by rank against the band field size, the rank line on a reversed right axis, the metric named in the legend and 96 epx bars paged older/newer; then the 10 most recent snapshots (date, rank, metric value). Redrawn on data, page or size change, and on `UISettings` `ColorValuesChanged`/`TextScaleFactorChanged`. Axis gutters and the date band are measured from the scaled labels (`RankHistoryCombinedChart.AxisGutter`/`DateBand`); under contrast themes gridlines and axes use WindowText (`FSTChartGridBrush`, `FSTChartAxisBrush`) and bars get a WindowText outline. History rows grow with text (`MinHeight`, date column `TextScaleLayout.ScaledMinWidth`). Fixture journey: `band-detail-rank-history-chart` in `tools/windows/journeys/bands.json`.
- Five Best / Five Worst Songs: 40 px art, title, `artist · year`, percentile pill (`Top N%`; `FSTPercentilePillFillBrush`/`TextBrush` with a `FSTNeutralPillStrokeBrush` outline, ButtonFace/ButtonText under contrast themes), `#rank of total`. Catalogue songs open Song Detail; unknown IDs show `Unknown Song`, not navigable.
- Quick links: right rail at window width ≥ 1280 epx, pill bar under the title otherwise; `StartBringIntoView` to each section.
- Sections fail independently: history and songs have their own inline status/Retry; the band row failure replaces the page.

## Evidence

Fixture screenshots (mock service, compact/medium/wide): `windows/reports/screenshots/band-detail-{compact,medium,wide}.png`. At compact (500 epx) the shell keeps the navigation pane open, leaving ~340 epx of content; pages switch to a smaller title below 560 epx page width.

## IDs

`fst.band.screen`, `.title`, `.subtitle`, `.unresolved`, `.error`, `.members-section`, `.member.<accountId>`, `.summary-section`, `.statistics-section`, `.stat.<id>` (`type`, `appearances`, `members`, `rank`, `songs-played`, `full-combos`, `total-score`, `fc-rate`, `avg-accuracy`, `avg-stars`, `best-rank`, `avg-rank`), `.rank-by`, `.history-section`, `.history-chart`, `.history-row.<date>`, `.history-empty`, `.songs-section`, `.best-songs`, `.worst-songs`, `.song-row.<songId>`, `.quick-links`, `.quick-link.<id>`, `.quick-links-rail`, `.rail-link.<id>`. Panels with IDs are not in the UIA control view; drive by the title or cards.

## Validation (issue #212)

Checked 2026-10-03 with the winui-design and winui-code-review skills, `a11y_matrix.py` (fixture) and the live public service (a public Duos band from the Band_Duets ranking, whose history read returns `historyStatus: disabled`; the page shows the service note and "No band rank history yet."). Axe.Windows 0 errors in every row.

| Configuration | Finding |
|---|---|
| Compact (500 epx), snap-left | Single column of cards; quick links as a pill bar. Correct. |
| Medium (900), wide (1280, clamped by the 300% 4K desktop), maximized | Three or four stat columns, two member cards, Rank By bottom-aligned with its heading. Correct. The clamped window stays just under the 1280 epx Quick Links rail breakpoint, so the pill bar shows. |
| Keyboard only | Tab: title bar → Quick Links → members → Rank By → stat cards → history chart → song rows → Back (12/15/15 stops at C/M/W). **Fixed:** the stat `ItemsRepeater` kept the default once-only Tab entry, so the linked Best Song Rank card was never reached; it now sets `TabFocusNavigation="Local"`. Song lists stay one Tab stop with arrows between rows. Journey `kb-band-detail-stats` in `tools/windows/journeys/a11y-keyboard.json` passes at all three sizes. |
| High Contrast (Desert, Night sky) | **Fixed:** the percentile pill kept its purple fill and white text, and the rank-history gridlines used the 8% glass border, which vanished. The pill now uses ButtonFace/ButtonText with an outline, and the gridlines, axes and bar outlines use WindowText. Data hues stay (rank-coloured bars, blue rank line): the legend, history rows and chart UIA name carry the meaning. |
| Light and dark system theme | Same rendering, a deliberate deviation: the app is dark only ([design/windows.md](../../design/windows.md#content-branded-fluent-tokens)). |
| Text 200% | **Fixed:** the chart's left tick labels were clipped ("49.5" without the M) by fixed 52/48 epx gutters, and history rows had a fixed 28 epx height. Gutters and the date band are now measured, and the rows grow. |
| Display 100% / 150% | Correct. |
| Narrator / UIA | Members "Band 1 Member A, Lead"; ComboBox "Rank By"; stat cards "Best Song Rank, #1"; chart as an Image named with every snapshot; song rows one Button "Fixture Pulse, Top 10%, rank #1 of 10" (unknown songs a named Group, not invokable). Reading order follows the Tab order. |

## Open

- No instrument-combo filter (web `BandInstrumentFilterModal`/`?combo=`) and no Select Band Profile (the session models only a selected player).
- Rank links go to `BandRankings(bandType)` without `rankBy`/page (the web jumps to the rank's page); needs the Leaderboards lane's route parameters.
- Deep links through `uiwin.py --route` lose everything after `&`; open Band Detail by clicking a band card in automation.
- Journeys: `tools/windows/journeys/bands.json`. Open: in the long player-bands journey the Best/Worst read against the loopback fixture intermittently fails with a client-side `WSAECONNABORTED` (10053) and the page correctly shows its inline offline state + Retry; the same read passes in isolation and under a 40-request concurrency stress test. TODO(orchestrator): root-cause the fixture transport reset (mock HTTP/1.0 server vs. the artwork burst) before gating on that journey.
- Spoken Narrator output needs the operator script ([windows-accessibility.md](../../testing/windows-accessibility.md) item 5); the UIA tree is audited above.
