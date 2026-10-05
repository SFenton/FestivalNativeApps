# Solo song leaderboard (`/songs/:songId/:instrument`) — spec

> **What:** platform-neutral web behavior of the paginated solo chart: query, paging, states, reading order. **Read when:** changing the Solo leaderboard on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx:49-535`, `src/components/leaderboard/LeaderboardPaginationFooter.tsx:35-172`, `src/components/common/Paginator.tsx:62-97`. Audit ref for Solo/band paging: `LeaderboardPage.tsx:114-184`.

## Query

- `GET /api/leaderboard/{song}/{instrument}?top=25&offset=(page-1)×25`; include `leeway` only when invalid-score filtering is enabled.
- `count` is this page's row count; page count comes from `localEntries ?? totalEntries`, **not** `entries.length` (25 rows with 26 local entries = two pages).
- Entry rows carry rank, name, score, accuracy, FC, stars, season and difficulty ([score accuracy](../../controls/score-accuracy/spec.md)). The optional totals flag controls the subtitle only; hidden totals keep pagination.

## Navigation and states

- Header song title → Detail; the selected player's row → Statistics; another player → Player profile.
- An explicit deep-link page overrides the cached page, then is corrected once totals arrive. First/Previous/Next/Last disable at boundaries; native ID family `fst.song-leaderboard.page-{first,previous,info,next,last}`.
- Selected-player/band footer uses the effective valid score and opens Statistics.
- **Native selected-row rule (issue #307):** solo and band boards behave alike. A selected row shown apart from its page (Song Detail's appended row, a footer while the row is on another page) jumps to the page containing its rank and brings the row into view highlighted; a selected row already visible opens the profile (Statistics for a player, the Band page for a band). Other rows open their player or band. Web still sends both footers and Song Detail's appended band row to the profile. The footer and pagination are portalled outside the load gate: they stay in place while another page loads, and rows fade out over 36 px above them (`useScrollFade`). `navToPlayer` targets the highlighted row after rows settle.
- **Native correction (all platforms):** update route/deep-link state when paging; the PWA changes pages locally and a stale link can override.

## Accessibility order (target)

Back → header → rows → selected-profile footer → pagination → tab/sidebar (the PWA portals its paginator, so DOM order differs).

## Test matrix

No selection / player / band; first, middle, last, empty and out-of-range pages; `localEntries` present/missing; 25 vs 26 rows; totals shown/hidden; loading/error/empty; selected row on/off this page; static art; narrow/wide row columns; focused paginator; announced page change.
