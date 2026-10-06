# Song band leaderboard — Windows notes

> **What:** what the Windows per-song band leaderboard implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsSongLeaderboardPage*` or `SongBandLeaderboardViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.SongBandLeaderboard(songId, bandType, page, revealSelected)` (`/songs/{id}/bands/{type}?page=N&navToBand=true`, web); an unknown band type falls back to Duos. Read `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=[&accountId=]` (pure `SELECT`s; the selected player as the query `accountId` only, no selected-profile headers), validated against the requested song/size and page size, including its `selectedPlayerEntry`/`selectedBandEntry` (members present, same size).
- Header: 72 px song art (the shell background switches to the static song cover), `<Size> Leaderboard` (heading 1), song title as a link to Song Detail, `artist · year · duration`, `<Size> · N entries`.
- Band size switcher: Fluent `SelectorBar` (Duos · Trios · Quads) switching in place and returning to page 1.
- Rows (`ListView`, virtualized): rank, each member's instrument icons + name + per-song member score, then the team score footer (web `SongBandScoreFooter`) with team score, FC badge (gold outline), accuracy pill and star images (`StarRow`), and a trailing chevron (`E76C`, decorative) because the card navigates. The footer is `Controls/BandScoreFooterPanel`, shared with the Song Detail preview row: the badges move to a line under the score when they don't fit (once for the whole list, `BandScoreFooterPanel.IsSection`; [leaderboard-row R8](../../patterns/leaderboard-row.md)), so the score never truncates (at 200% text in narrow windows it had truncated; issue #264). A row opens `AppRoute.Band(bandId, bandType, teamKey)`.
- Row accessibility (issue #196): each `ListViewItem` is one Narrator stop. `ContainerContentChanging` sets its UIA name to `SongBandRow.PageAnnouncement` (`Rank N. <member>, <instruments>, <score> points. … Team score X points, full combo, A% accuracy, N gold stars`) and its AutomationId to `.row.<bandId>:<rank>`. Every template part, including `InstrumentIcon`'s inner `Image`, is `AccessibilityView.Raw`, because Raw on a parent does not hide its children in WinUI. The Song Detail preview keeps the shorter `Announcement`.
- High contrast: the accuracy pill uses `FSTAccuracyPillFillBrush` (navy by default, `SystemColorButtonFaceColor` in HighContrast) with `FSTNeutralPillStrokeBrush`/`FSTNeutralPillTextBrush`. Before this, the static navy fill under system text was unreadable in Desert.
- Selected band (issue #307, pattern `leaderboard-row` R7, same rule as the solo board): the selected player's band (`selectedBandEntry ?? selectedPlayerEntry`; Windows has no selected-band identity yet, so the service picks the player's best band) is highlighted in place with the player-row brushes and bold rank (re-applied on `ContrastTheme.Changed`; PageAnnouncement prefixed "Your band, ") and pinned above the pager in the shared `LeaderboardEntryRow` (`fst.song-band-leaderboard.spotlight-footer`, `SongBandSpotlightRow`). While its row is on another page the footer jumps there (`SelectedRowAction.Footer`, Narrator "Your band's rank, 29th. Jump to your band's position. …") and the list scrolls to the highlighted row once the rows are revealed (`RevealRow`, centred, no animation); on its page it opens Band Detail ("… Open band. …"). An arrival from Song Detail's appended band row (`revealSelected`) lands on that page and reveals the row the same way. **Reveal timing:** a freshly swapped `ListView` defers `ScrollIntoView`, and scroll requests made in the same dispatcher tick (`ScrollIntoView` + `UpdateLayout`) or inside `LayoutUpdated` never commit, so the list stayed at the top (found by the live #307 journey on page 15 of 379). `RevealRow` therefore works once per `CompositionTarget.Rendering` frame: it asks the list to realize the row, then calls `StartBringIntoView` (ratio 0.5), and stops when the row lies inside the list, when the rows change, when the page unloads or after 60 frames. In practice the row is realized on frame 2 and centred on frame 3. The footer shares the rows' load gate on the first load and a band-size change and fades in with row 0 (`PinnedRowReveal.RevealDelay`); paging (including its own jump) keeps it in place beside the spinner, like the solo board (`PinnedRowGate` keyed by band size inside `LoadSwapGate`, which drops it from UIA while hidden; [load-transition](../../patterns/load-transition.md) R2). A failed read hides it.
- Paging with the shared board pager (`LeaderboardsPager`, operator batch 7.4; floating over the rows); empty state `No band scores found` / `No <Size> scores have been recorded for this song yet.`; failure via `ServiceStatusView`. Late responses for an older size/page are discarded.
- Load-swap gate (issue #71): first load, band-size changes and paging run the shared web sequence (300 ms content-out, centered ring, 500 ms ring-out, row stagger). New rows/empty/error state commits while hidden; rapid choices are latest-wins. Reduce Motion swaps immediately.

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

`fst.song-band-leaderboard.screen`, `.title`, `.song`, `.subtitle`, `.band-type-menu`, `.band-type.<bandType>`, `.list`, `.row.<bandId>:<rank>` (on the `ListViewItem`), `.spotlight-footer` (pinned selected band), `.empty` (on the empty heading `TextBlock`; panels have no UIA peer), `.page-first|page-previous|page-info|page-next|page-last`. The failure state is found through the shared `fst.service-status.title` / `fst.service-status.retry` IDs (the `.error` name on the `ServiceStatusView` UserControl never reaches UIA).

## Open

- No instrument-combo filter (`?combo=`). The pinned footer shows the service's pick for the selected player (no selected-band identity on Windows yet).
- Entry point from Song Detail (band leaderboard previews) is owned by the Songs lane; its `SongBandPreviewRowView` accuracy pill uses the same contrast-aware pill roles since issue #264.
