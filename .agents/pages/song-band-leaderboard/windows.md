# Song band leaderboard — Windows notes

> **What:** what the Windows per-song band leaderboard implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/BandsSongLeaderboardPage*` or `SongBandLeaderboardViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Route `AppRoute.SongBandLeaderboard(songId, bandType)`; an unknown band type falls back to Duos. Read `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=` (pure `SELECT`s), validated against the requested song/size and page size.
- Header: 72 px song art (the shell background switches to the static song cover), `<Size> Leaderboard` (heading 1), song title as a link to Song Detail, `artist · year · duration`, `<Size> · N entries`.
- Band size switcher: Fluent `SelectorBar` (Duos · Trios · Quads) switching in place and returning to page 1.
- Rows (`ListView`, virtualized): rank, each member's instrument icons + name + per-song member score, team score, FC badge (gold outline), accuracy pill, star images (`StarRow`). A row opens `AppRoute.Band(bandId, bandType, teamKey)`.
- Paging with the shared `BandsPager`; empty state `No band scores found` / `No <Size> scores have been recorded for this song yet.`; failure via `ServiceStatusView`. Late responses for an older size/page are discarded.

## Evidence

Fixture screenshots (mock service, compact/medium/wide): `windows/reports/screenshots/song-band-leaderboard-{compact,medium,wide}.png`. At compact (500 epx) the shell keeps the navigation pane open, leaving ~340 epx of content; pages switch to a smaller title below 560 epx page width.

## IDs

`fst.song-band-leaderboard.screen`, `.title`, `.song`, `.subtitle`, `.band-type-menu`, `.band-type.<bandType>`, `.list`, `.row.<bandId>:<rank>`, `.empty`, `.error`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- No instrument-combo filter (`?combo=`) and no selected-player/band pinned footer.
- Entry point from Song Detail (band leaderboard previews/links) is owned by the Songs lane.
