# Song Detail — Android notes

> **What:** Android implementation state and decisions for Song Detail and the full song leaderboard. **Read when:** changing Song Detail on Android (`ui/songdetail/`). Behavior: [spec.md](spec.md).

## Implemented

- `SongDetailRouteScreen` wires the view model with shared Shop, selected-profile and Settings state; the shell calls it for both the pushed route and the two-pane detail.
- Song resolved by ID (debug: or exact title) against the current catalogue; the shared backdrop shows the song's static cover.
- **Load gate** (batch 6.41): `SongDetailViewModel.startPreviews` starts every visible chart's ten-row preview together, plus the selected player's song history; `FestivalLoadGate` (`ui/common/LoadGate.kt`) shows only the spinner until all settle (loaded or failed, `core/songs/SongDetailLayout.ready`), fades it, then staggers header → Intensity → Score History → card rows → bands. Cached data returning shows at once.
- **Header** (6.40): 88 dp album art, title and `artist · year · length` in the list; it scrolls away and the top bar shows the title only once it has (`firstVisibleItemIndex > 0`), like iOS.
- Header actions: **Paths** (only when a visible, charted, non-Karaoke chart exists) and, for a same-publication Shop offer, the **Item Shop** official-link pill (validated host only), which breathes in the status colour (web `shopBreathe*`, static under reduced motion). A failed Shop read shows `fst.song-detail.shop-error`.
- **Intensity** (6.31): every charted instrument, two columns everywhere; compact cards show icon + meter (left-aligned, web cell), cards ≥ 480 dp add the label.
- **Score History** (6.39, `SongHistoryCard.kt`, web `ScoreHistoryChart` in a `GraphCard`): `GET /api/player/{id}/history?songId=` (no instrument; `data/songs/FestivalApiSongHistory.kt`), invalid scores dropped while Filter Invalid Scores is on (`SongHistoryChart.valid`). Instrument Selector (required) over visible charts with history (auto: current → Lead → first); one canvas draws accuracy bars (red→green, gold for a 100% FC, ≤ 72 dp wide) and the blue score line; tapping a bar selects it (purple stroke) and shows its detail row; « ‹ › » paging (`SongHistoryPaging`, web `useChartPagination`); the five best scores (best purple and bold); **View All Scores** → `PlayerHistoryRoute` when there are more than five. Hidden when the player has no history on visible charts.
- **Instrument cards** (6.4/6.5/6.29/6.31/6.38/6.42): instrument header (icon, name, "N total entries") above a card of rows separated by hairlines (`RowSeparator`), rank column measured from the widest rank (`rememberRankWidth`), the shared `AccuracyPill` and an in-card chevron on navigable rows; the selected player's row has the web purple highlight and bold texts, every row shares the same 4 dp inset so columns align; when outside the top ten the player's row follows after a separator (`fst.song-detail.your-rank.<chart>`, opens the page containing it). No "Your score" line. Cards end with the shared purple **View Full Leaderboard** (`ui/design/ViewFullLeaderboardButton`). Two columns when the content is ≥ 600 dp, and either side of a separating vertical hinge (book half-open) via `rememberHingeSplit` + `CardGridRow`.
- An empty chart shows the web `InstrumentEmptyState` text; a failed chart shows an inline retry.
- Band Leaderboards chips (Duos/Trios/Quads → `SongBandLeaderboardRoute`).
- With Filter Invalid Scores on, previews read with `leeway=` and show the service's rows and raw Epic ranks exactly like the web (production Winterfest Wish Lead: 7 valid entries of 12,438; verified live 2026-09-28, test `filterInvalidScoresUsesTheLeewayBoardAndDropsInvalidHistory`).
- Full board (`SongLeaderboardScreen`): the song header (64 dp art, title, artist) and instrument switcher scroll with the rows; the top bar takes the title once they're gone (7.8). Rows use the same `ScoreRow`; the selected player's pinned footer is just their row (opens Statistics, no page-jump button, 7.9).
- Paths sheet: see [chopt-paths/android.md](../../controls/chopt-paths/android.md).

## Open

Promoted band previews (web band cards on the page), scrolling to an initial instrument (`?instrument=`), Quick Links; the Intensity and Score History cards still span a book-posture hinge.
