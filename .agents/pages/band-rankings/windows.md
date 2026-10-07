# Band rankings — Windows notes

> **What:** what the Windows paginated band rankings page implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsBandRankingsPage*` or `BandRankingsViewModel`. Behavior: [spec.md](spec.md); account variant: [full-rankings/windows.md](../full-rankings/windows.md).

## Implemented

- Route `AppRoute.BandRankings(bandType)` (unknown type → Duos). 25-row pages of `GET /api/rankings/bands/{bandType}?rankBy=&page=&pageSize=25` (publication-pinned pure read); page count from `totalTeams`; out-of-range pages clamped; superseded responses dropped.
- Header: "<Size> Rankings" (heading 1), "N ranked bands"; band-size switcher (Duos · Trios · Quads) and band Rank By (no Max Score; starts from the persisted Leaderboards metric narrowed like `coerceBandRankingMetric`). Switching returns to page 1.
- Rows: rank, roster ("Unknown User" for blank member names), songs, rating; a row opens `AppRoute.Band(bandId, bandType, teamKey)` so Band Detail uses the safe rankings read, never `/api/bands/{bandId}` ([service-safety](../../platforms/service-safety.md)). Rows without `bandId`/`teamKey` are shown but not interactive.
- Shared pager and Back-state behavior as Full Rankings; compact collapses the band-size label to its icon.
- Load-swap gate (issue #71): first load, F5, band-size/metric changes and paging run the shared web sequence (300 ms content-out, centered ring, 500 ms ring-out, row stagger). New rows, empty and failure states commit only while hidden; rapid choices are latest-wins. Reduce Motion swaps immediately.
- Footer edge (issue #308, web `useScrollFade`, [scroll-edge](../../patterns/scroll-edge.md) R2–R4/R7): Rows end at the floating pager through the shared bottom-chrome ramp `BoardFooterFade.Attach` (`Controls/BoardFooterFade`, the same component as Song Leaderboard): clear at the footer's top, opaque 36 epx above it on a linear ramp, the depth min(remaining scroll, 36) so nothing is dimmed at the end. Contrast themes, Windows transparency effects off, Increase Contrast and Less Transparency make it a hard cut at the footer's top. The source is the `BoardFadeSource` wrapper (the load swap animates the list's own visual) and the raw-view `EdgeFadeLayer` `fst.band-rankings.footer-fade` reports `hidden`, `fading:36`, `end` or `hard-edge` (journeys `tools/windows/journeys/a11y-board-footer-fade.json` and `-hard.json`). Before #308 the rows met the pager at a hard edge. The contrast `FooterPlate` stays behind the pager.

## Evidence

Fixture: `windows/reports/screenshots/band-rankings-wide.png`; journeys in `tools/windows/journeys/band-rankings.json` (pager keys, menus, row → Band Detail, anonymous, empty, error/Retry) and `tools/windows/journeys/leaderboards.steps`. A11y pages `band-rankings-paged|anonymous|empty|error` in `tools/windows/journeys/a11y.json` use the fixture scenarios `--large-rankings` and `--band-rankings empty|unavailable|anonymous` (`tools/windows/rivals_fixture.py`).

## Validation (issue #209, 2026-10-03)

Debug build, 3840×2160 at 300%, `a11y_matrix.py --scan --tabs 30` on the four fixture states, `band-rankings.json` journeys (6/6), and live public-service captures of Duos (no selected profile, so no profile headers). Axe.Windows reported 0 errors in every run.

| Configuration | Result |
|---|---|
| Compact / medium / wide (500/900/1440 epx) | ✅ all four states; tab stops 9/12/12 paged, 7/10/10 single page; ≥1100 epx shows the Band Detail column |
| Maximized, snapped left/right | ✅ paged and single page |
| Light system theme | The app is dark-only by design (`App.xaml RequestedTheme="Dark"`, web parity). Deliberate deviation |
| High contrast Desert / Night sky | ✅ after the `FooterPlate` fix. Before it, row borders and text showed between the floating pager's buttons, as on the song leaderboard (#197) |
| Text size 200% | ✅ compact/medium/wide. At compact the rank, songs and rating columns used to leave the band name only "…". Rankings rows now move the songs label (then the rating) under the name when large text would squeeze the name below its minimum (the shared #208 rule; this branch first dropped the label, and the merge kept #208's placement) |
| Display scale 100% / 150% | ✅ medium and maximized |
| Keyboard | Tab: title bar → pane → band size → Rank By → rows (one stop, Up/Down) → pager. Left/Right/Home/End/Ctrl+arrows page and focus stays on the pager after the fix below. Enter opens the menus, Esc returns focus to the button and Enter on a row opens Band Detail; Alt+Left comes back |
| UIA | Each row is one Button named "Rank #N, members. Metric value, played / total songs"; rows without a band page aren't openable but keep their columns. The menu items are `RadioMenuFlyoutItem`s with the Toggle pattern (no Invoke). Page text is a polite live region named "Page N of M" |

Fixed:
- **Pager focus:** the pager was hidden while the next page loaded (`ShowContent` waited for the load swap), so keyboard focus fell to Back after the first arrow key. It now stays mounted like the song leaderboard's (#93).
- **Contrast pager:** a window-colour `FooterPlate` behind the pager, only under contrast themes.
- **Column alignment:** a row without a band page (no `teamKey`) dropped its chevron, which shifted its songs and rating columns. The chevron slot is now reserved section-wide (`LeaderboardSection.HasRoutes`), and unopenable rows draw it transparent.
- **Empty state:** the empty text gained `fst.band-rankings.empty`, wraps and is centred.

Post-merge re-run (master with #207/#208, 2026-10-04): `band-rankings.json` journeys 6/6; Axe 0 errors with tab stops 9/12/12 paged and 7/10/10 anonymous at compact, medium and wide; text 200% at C/M/W also had 0 errors. At 200% compact, rows stack: rank and name on the first line, songs label and rating on the second.

Design review (`winui-design`): Fluent `DropDownButton` + `MenuFlyout` radio items for band size and Rank By, theme brushes, system colours in contrast themes, defined loading/empty/error states. The custom pager stays for web Paginator parity (`winapp find-api` finds no `PagerControl` in the app's WinAppSDK). The web's `BandRankingPlayerCard` cards are the shared native leaderboard rows (operator batch 7.7).

## IDs

`fst.band-rankings.title`, `.list`, `.empty`, `.band-type-menu`, `.band-type.<bandType>`, `.rank-by-menu`, `.rank-by.<metric>`, `.page-first|page-previous|page-info|page-next|page-last`, `.row.<teamKey>`, `.detail-pane`.

## Open

- No selected-band pinned row (no selected-band identity on Windows) and no band-combo filter.
- Narrator audio was not scripted; announcements are covered by the UIA tree and `LoadAnnouncer` tests.

## Two columns

From a 1100 epx page the rankings keep a 560 epx column and the chosen band's Band Detail (`BandsDetailPage` in `DetailFrame`, `fst.band-rankings.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). It starts on the first openable row, follows row clicks (`IRouteHost`) and survives paging while that band is listed; its row gets `LeaderboardEntryRow.IsCurrent`. Below 1100 epx, or without openable rows, the page is one 1100 epx column. Journey: `tools/windows/journeys/split-panes.json`.
