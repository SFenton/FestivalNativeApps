# Song band leaderboard — Android notes

> **What:** what the Android per-song band leaderboard implements. **Read when:** changing `ui/bands/SongBandLeaderboardScreen.kt` or `SongBandLeaderboardViewModel`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implemented

- `SongBandLeaderboardRoute(songId, bandType)` (unknown type → Duos) → `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=` (pure read), validated against song, size and page size. Song Detail's band previews read the same route with `top=10` and, with a selected player, `accountId=` (adds `selectedPlayerEntry`; pure `SELECT`). Rows (`BandScoreRow`) stack the team score under the members below 400 dp and carry an in-card chevron. Debug: `FST_DEBUG_ROUTE=songBandLeaderboard:<songId>[:<bandType>]`.
- Top bar `<Size> Leaderboard`; header 72 dp art, song title as a link to Song Detail, `artist · year`, `<Size> · N entries`. The shared backdrop shows the song's static cover while visible.
- Band size switcher: Material 3 segmented buttons (Duos · Trios · Quads), switching in place and returning to page 1. A size or page change runs the shared load swap (issue #71; spinner `fst.song-band-leaderboard.loading`).
- Rows (glass cards, lazy): rank, each distinct member's instrument icons (keys variants for keyboard songs) + name + per-song member score, team score, gold `FC` outline badge, accuracy, `★ stars`; one merged TalkBack announcement. A row opens `BandRoute(bandId, membersLabel, bandType, teamKey)`.
- Shared pager, empty state (`No band scores found` / `No <Size> scores have been recorded for this song yet.`), failure `ServiceStatusView` (fixed height inside the list). Content is centered at ≤840 dp on wide windows.

## IDs

`fst.song-band-leaderboard.screen`, `.list`, `.song`, `.subtitle`, `.band-type-menu`, `.band-type.<bandType>`, `.row.<bandId>:<rank>`, `.empty`, `.error`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- Entry point from Song Detail belongs to the Songs lane. No instrument-combo filter and no selected-player/band pinned row.
