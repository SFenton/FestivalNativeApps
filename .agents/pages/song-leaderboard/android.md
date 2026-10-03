# Solo song leaderboard — Android notes

> **What:** Android state of the per-song solo leaderboard (`/songs/:songId/:instrument`). **Read when:** changing `ui/songdetail/SongLeaderboardScreen.kt` or `SongLeaderboardViewModel`. Behavior: [spec.md](spec.md); Song Detail: [song-detail/android.md](../song-detail/android.md).

## Implemented

- 25-row pages of `GET /api/leaderboard/{song}/{instrument}?top=25&offset=[&leeway=]` (`leeway` only while Filter Invalid Scores is on; `SongLeaderboardRouteScreen`, re-read when it changes); page count from `localEntries ?? totalEntries`; out-of-range pages corrected.
- Paging runs the shared load swap (issue #71): the rows fade out, the spinner `fst.song-leaderboard.loading` shows, the new page staggers in. Only the rows item swaps: the song header, instrument picker, pinned score and pager stay in place while the page loads (issue #93, checked: already so; `songLeaderboardKeepsItsHeaderPinnedScoreAndPagerWhilePaging` holds the `offset=25` read).
- Footer edge (issue #93, web `useScrollMask`): this screen passes `fadeAboveFooter = true` to `RankingsBoardScaffold` (the other boards keep the default `false`), so in a single pane rows are cleared beneath the floating "your score" card and pager and fade out over a 40 dp eased band ending at the footer's top (`BoardFooterEdgeFade`, offscreen layer + `DstIn` gradient, draw phase only). The band eases away over the last 40 dp of scrolling so the last row is never faded. Increase Contrast and Reduce Transparency keep the previous hard edge (rows pass under the opaque card). Around a hinge the footer sits in the other pane, so nothing is masked. Pixel test: `BoardFooterFadeDrawUiTest`.
- The page is written back into the back-stack entry's route (`SongLeaderboardRoute.page` via `SyncRouteArguments`), so Back and a recreated entry restore it (spec native correction).
- Uses the rankings board scaffold and shared floating pager ([full-rankings/android.md](../full-rankings/android.md)): header (instrument icon + label) scrolls with the rows; the "your score" card and pager are anchored to the bottom above the bottom bar / floating toolbar, or on the far side of a hinge.
- Rows (`ScoreRow`: rank, name, FC/accuracy pill, score, and from 600 dp the star images — `StarRating`, web `MiniStars` with `star_white`/`star_gold`, never Material glyphs) open the player's profile; the selected player's row opens Statistics (web `LeaderboardPage.tsx`) and is highlighted in place. Rows without a usable account ID are not interactive ("Profile unavailable").
- Selected player off the page: a pinned row above the pager built from the Profile lane's `SelectedProfileStore.scoreIndex` (no extra read; `SongScoreSpotlight.footer`), shown **only** when the score index and the page were observed under the same publication. With Filter Invalid Scores on, an invalid best score is replaced by its next valid score and filtered rank (`PlayerScore.effective`), like the web. It opens Statistics; **Your Page** jumps to `pageForRank(rank)` (native addition — the web footer never re-pages) and hides once there.

## IDs

`fst.song-leaderboard.list`, `.instrument`, `.row.<accountId|rank-N>`, `.spotlight-footer`, `.spotlight-jump`, `.bottom-bar`, `.pager`, `fst.stars`, `fst.score` (score cell; aligned per section), `.page-first|page-previous|page-info|page-next|page-last`.

## Open

- No entry-totals subtitle; no season pill column.
