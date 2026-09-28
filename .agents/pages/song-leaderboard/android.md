# Solo song leaderboard — Android notes

> **What:** Android state of the per-song solo leaderboard (`/songs/:songId/:instrument`). **Read when:** changing `ui/songdetail/SongLeaderboardScreen.kt` or `SongLeaderboardViewModel`. Behavior: [spec.md](spec.md); Song Detail: [song-detail/android.md](../song-detail/android.md).

## Implemented

- 25-row pages of `GET /api/leaderboard/{song}/{instrument}?top=25&offset=`; page count from `localEntries ?? totalEntries`; out-of-range pages corrected.
- Uses the rankings board scaffold and shared pager ([full-rankings/android.md](../full-rankings/android.md)): header (instrument icon + label) scrolls with the rows, the pager is pinned above the bottom bar on compact/medium widths and sits in the supporting pane on expanded widths or across a hinge.
- Rows (`ScoreRow`: rank, name, FC/accuracy pill, score) open the player's profile; the selected player's row opens Statistics (web `LeaderboardPage.tsx`) and is highlighted in place. Rows without a usable account ID are not interactive ("Profile unavailable").

## IDs

`fst.song-leaderboard.list`, `.instrument`, `.row.<accountId|rank-N>`, `.pager`, `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- No selected-player footer or **Your page** jump: it needs the selected player's score index (Profile lane's `SelectedProfileStore`), not a rankings read.
- No `leeway` (invalid-score filtering) and no entry-totals subtitle; paging does not rewrite the route.
