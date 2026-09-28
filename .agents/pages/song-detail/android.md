# Song Detail — Android notes

> **What:** Android implementation state and decisions for Song Detail and the full song leaderboard. **Read when:** changing Song Detail on Android (`ui/songdetail/`). Behavior: [spec.md](spec.md).

## Implemented

- `SongDetailRouteScreen` wires the view model with shared Shop, selected-profile and Settings state; the shell calls it for both the pushed route and the two-pane detail.
- Song resolved by ID (debug: or exact title) against the current catalogue; header art + title + `artist · year · duration` (+ album); the shared backdrop shows the song's static cover.
- Header actions: **Paths** (only when a visible, charted, non-Karaoke chart exists) and, for a same-publication Shop offer, the availability badge + **Item Shop** official link (validated host only). A failed Shop read shows `fst.song-detail.shop-error`; a hidden Shop shows neither.
- Intensity card: every **charted** instrument (even hidden ones).
- Band Leaderboards chips (Duos/Trios/Quads → `SongBandLeaderboardRoute`).
- One lazily-started ten-row preview per **visible** charted instrument; with Filter Invalid Scores on the read adds `leeway=` (`data/songs/FestivalApiSongs.leaderboardPage`) and previews are keyed by leeway so a change re-reads.
- With a selected player each card shows a gold **Your score** line (`SongDetailSummary`: score · accuracy · FC · Top N% · #rank, or loading/syncing/paused/failed/no-score text), highlights the player's row, offers **Show My Rank** (the 25-row page containing it) when the rank is outside the preview, and **View {chart} Score History** (`PlayerHistoryRoute`).
- Preview rows open the player (`RankingNavigation.playerRoute`); rows with no account read **Unknown User** and are not interactive.
- Paths sheet: see [chopt-paths/android.md](../../controls/chopt-paths/android.md).

## Open

Selected-player history chart on the page, promoted band previews, scrolling to an initial instrument, Quick Links.
