# Song band leaderboard — Windows notes

> **What:** what the Windows per-song band leaderboard implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsSongLeaderboardPage*` or `SongBandLeaderboardViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.SongBandLeaderboard(songId, bandType)`; an unknown band type falls back to Duos. Read `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=` (pure `SELECT`s), validated against the requested song/size and page size.
- Header (issue #317; [song-leaderboard-header](../../patterns/song-leaderboard-header.md)): the shared song leaderboard header `Controls/SongLeaderboardHeader`, the same control as the solo board (80 epx static cover, 56 below a 760 epx window; the shell background switches to the static song cover). It shows the song title (heading 1) and the artist as one-line marquees ([song-header](../../patterns/song-header.md) R2), the band size (`Duos`/`Trios`/`Quads`) where the solo board shows the instrument, and "N <Size> entries" only when the response's `showLeaderboardEntryTotals` is true and the total is above zero (web `SongBandLeaderboardPage` `SongInfoHeader` subtitle; the solo rule). It used to be a `<Size> Leaderboard` heading with the song as a secondary link and the count always shown. Switching the size updates only the band line. The page change announcement names the board (`<Song>, <Size> leaderboard`).
- Agent decisions (issue #317, recorded as the Windows variant in [song-leaderboard-header](../../patterns/song-leaderboard-header.md#variants); the owner may override): the header stays fixed above the size switcher instead of scrolling away like the solo board, because the band rows' load gate hides the `ListView` (and any `ListView.Header`) during size swaps and the row UIA from #196 relies on the `ListView`. The song-title link to Song Detail was dropped to match the solo board (web has no title link either); Back returns to Song Detail. The page now uses the solo compaction (smaller art below 760 epx, page-title style always) instead of its own 560 epx rule.
- Band size switcher: Fluent `SelectorBar` (Duos · Trios · Quads) switching in place and returning to page 1.
- Rows (`ListView`, virtualized): rank, each member's instrument icons + name + per-song member score, then the team score footer (web `SongBandScoreFooter`) with team score, FC badge (gold outline), accuracy pill and star images (`StarRow`), and a trailing chevron (`E76C`, decorative) because the card navigates. The footer is `Controls/BandScoreFooterPanel`, shared with the Song Detail preview row: the badges move to a line under the score when they don't fit (once for the whole list, `BandScoreFooterPanel.IsSection`; [leaderboard-row R8](../../patterns/leaderboard-row.md)), so the score never truncates (at 200% text in narrow windows it had truncated; issue #264). A row opens `AppRoute.Band(bandId, bandType, teamKey)`.
- Row accessibility (issue #196): each `ListViewItem` is one Narrator stop. `ContainerContentChanging` sets its UIA name to `SongBandRow.PageAnnouncement` (`Rank N. <member>, <instruments>, <score> points. … Team score X points, full combo, A% accuracy, N gold stars`) and its AutomationId to `.row.<bandId>:<rank>`. Every template part, including `InstrumentIcon`'s inner `Image`, is `AccessibilityView.Raw`, because Raw on a parent does not hide its children in WinUI. The Song Detail preview keeps the shorter `Announcement`.
- High contrast: the accuracy pill uses `FSTAccuracyPillFillBrush` (navy by default, `SystemColorButtonFaceColor` in HighContrast) with `FSTNeutralPillStrokeBrush`/`FSTNeutralPillTextBrush`. Before this, the static navy fill under system text was unreadable in Desert.
- Paging with the shared board pager (`LeaderboardsPager`, operator batch 7.4; floating over the rows); empty state `No band scores found` / `No <Size> scores have been recorded for this song yet.`; failure via `ServiceStatusView`. Late responses for an older size/page are discarded.
- Load-swap gate (issue #71): first load, band-size changes and paging run the shared web sequence (300 ms content-out, centered ring, 500 ms ring-out, row stagger). New rows/empty/error state commits while hidden; rapid choices are latest-wins. Reduce Motion swaps immediately.

## Evidence

Fixture screenshots (mock service, compact/medium/wide): `windows/reports/screenshots/song-band-leaderboard-{compact,medium,wide}.png`. At compact (500 epx) the shell keeps the navigation pane open, leaving ~340 epx of content; the header art shrinks to 56 epx below a 760 epx window.

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

Journeys `song-band-leaderboard-switch-and-detail` (rows, Trios empty, Quads, row → Band, Back), `song-band-leaderboard-entry-totals` (`--song-band-totals` fixture: `showLeaderboardEntryTotals` true) and `song-band-leaderboard-error` (`tools/windows/journeys/bands.json`) cover the reachable states. They assert with `assertname`/`assertbelow`/`waitgone` that the title names the song, the artist and band line follow it, the band line names the selected size after every switch, the total shows only when the flag is true and the board has entries, and no `<Size> Leaderboard` heading or song link remains.

## IDs

`fst.song-band-leaderboard.screen`, `.title` (song title; collapsed when the song is missing), `.artist`, `.subtitle` (band size line), `.total` (entry total, only when shown), `.band-type-menu`, `.band-type.<bandType>`, `.list`, `.row.<bandId>:<rank>` (on the `ListViewItem`), `.empty` (on the empty heading `TextBlock`; panels have no UIA peer), `.page-first|page-previous|page-info|page-next|page-last`. The failure state is found through the shared `fst.service-status.title` / `fst.service-status.retry` IDs (the `.error` name on the `ServiceStatusView` UserControl never reaches UIA).

## Open

- No instrument-combo filter (`?combo=`) and no selected-player/band pinned footer.
- Entry point from Song Detail (band leaderboard previews) is owned by the Songs lane; its `SongBandPreviewRowView` accuracy pill uses the same contrast-aware pill roles since issue #264.
