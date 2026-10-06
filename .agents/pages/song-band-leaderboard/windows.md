# Song band leaderboard — Windows notes

> **What:** what the Windows per-song band leaderboard implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsSongLeaderboardPage*` or `SongBandLeaderboardViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.SongBandLeaderboard(songId, bandType)`; an unknown band type falls back to Duos. Read `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=` (pure `SELECT`s), validated against the requested song/size and page size.
- Header: 72 px song art (the shell background switches to the static song cover), `<Size> Leaderboard` (heading 1), song title as a link to Song Detail, `artist · year · duration`, `<Size> · N entries`.
- Band size switcher: Fluent `SelectorBar` (Duos · Trios · Quads) switching in place and returning to page 1.
- Rows (`ListView`, virtualized): rank, each member's instrument icons + name + per-song member score, team score, FC badge (gold outline), accuracy pill, star images (`StarRow`), and a trailing chevron (`E76C`, decorative) because the card navigates. A row opens `AppRoute.Band(bandId, bandType, teamKey)`.
- Row accessibility (issue #196): each `ListViewItem` is one Narrator stop. `ContainerContentChanging` sets its UIA name to `SongBandRow.PageAnnouncement` (`Rank N. <member>, <instruments>, <score> points. … Team score X points, full combo, A% accuracy, N gold stars`) and its AutomationId to `.row.<bandId>:<rank>`. Every template part, including `InstrumentIcon`'s inner `Image`, is `AccessibilityView.Raw`, because Raw on a parent does not hide its children in WinUI. The Song Detail preview keeps the shorter `Announcement`.
- High contrast: the accuracy pill uses `FSTAccuracyPillFillBrush` (navy by default, `SystemColorButtonFaceColor` in HighContrast) with `FSTNeutralPillStrokeBrush`/`FSTNeutralPillTextBrush`. Before this, the static navy fill under system text was unreadable in Desert.
- Paging with the shared board pager (`LeaderboardsPager`, operator batch 7.4; floating over the rows); empty state `No band scores found` / `No <Size> scores have been recorded for this song yet.`; failure via `ServiceStatusView`. Late responses for an older size/page are discarded.
- Load-swap gate (issue #71): first load, band-size changes and paging run the shared web sequence (300 ms content-out, centered ring, 500 ms ring-out, row stagger). New rows/empty/error state commits while hidden; rapid choices are latest-wins. Reduce Motion swaps immediately.
- Footer edge (issue #308, web `useScrollFade`, [scroll-edge](../../patterns/scroll-edge.md) R2–R4/R7): Rows end at the floating pager through the shared bottom-chrome ramp `BoardFooterFade.Attach` (`Controls/BoardFooterFade`, the same component as Song Leaderboard): clear at the footer's top, opaque 36 epx above it on a linear ramp, the depth min(remaining scroll, 36) so nothing is dimmed at the end. Contrast themes, Windows transparency effects off, Increase Contrast and Less Transparency make it a hard cut at the footer's top. The source is the `BoardFadeSource` wrapper (the load swap animates the list's own visual) and the raw-view `EdgeFadeLayer` `fst.song-band-leaderboard.footer-fade` reports `hidden`, `fading:36`, `end` or `hard-edge` (journeys `tools/windows/journeys/a11y-board-footer-fade.json` and `-hard.json`). Before #308 the rows met the pager at a hard edge.

## Evidence

Fixture screenshots (mock service, compact/medium/wide): `windows/reports/screenshots/song-band-leaderboard-{compact,medium,wide}.png`. At compact (500 epx) the shell keeps the navigation pane open, leaving ~340 epx of content; pages switch to a smaller title below 560 epx page width.

Validation pass (issue #196, 2026-10-03; live public service plus fixtures):

| Configuration | Result |
|---|---|
| Compact, medium, wide, maximized, snap-left (live, Duos/Quads, paging) | Layout correct; the floating pager overlays the last visible row by design (operator batch 7.4). Non-drum instrument icons can stay blank for about 1 s right after a list rebuild while their shared bitmaps decode. |
| Dark (default) | Correct. The app is dark-only (`RequestedTheme="Dark"`), so the system Light theme is a deliberate no-op. |
| HC Desert, Night Sky, Aquatic, Dusk | Axe 0. Desert failed before the accuracy-pill fix (navy fill under system text). |
| Text 200% / 225% (compact, medium) | Axe 0; text wraps in place. Icons, stars and chevron keep their fixed size. |
| No animations, no transparency | Axe 0; Reduce Motion swaps rows without the gate. |
| Display 100% / 150% | Not changeable on the shared 300% host desktop. Layout is in epx and was checked at every preset. |
| Keyboard | The console was locked, so SendInput Tab walks were unavailable. UIA confirms one focusable `ListItem` per row, `SelectorBar` items and pager buttons in reading order. Journeys drive selection, row invoke and Back through UIA patterns. |

Journeys `song-band-leaderboard-switch-and-detail` (rows, Trios empty, Quads, row → Band, Back) and `song-band-leaderboard-error` (`tools/windows/journeys/bands.json`) cover the reachable states.

## IDs

`fst.song-band-leaderboard.screen`, `.title`, `.song`, `.subtitle`, `.band-type-menu`, `.band-type.<bandType>`, `.list`, `.row.<bandId>:<rank>` (on the `ListViewItem`), `.empty` (on the empty heading `TextBlock`; panels have no UIA peer), `.page-first|page-previous|page-info|page-next|page-last`. The failure state is found through the shared `fst.service-status.title` / `fst.service-status.retry` IDs (the `.error` name on the `ServiceStatusView` UserControl never reaches UIA).

## Open

- No instrument-combo filter (`?combo=`) and no selected-player/band pinned footer.
- Entry point from Song Detail (band leaderboard previews/links) is owned by the Songs lane. Its `SongBandPreviewRowView` accuracy pill still uses the static `FSTSurfaceMutedBrush`, which has the same High Contrast issue; it is outside the #196 scope.
