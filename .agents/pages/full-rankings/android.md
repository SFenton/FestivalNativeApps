# Full rankings — Android notes

> **What:** what the Android paginated instrument rankings page implements, where its controls live and why, and its open gaps. **Read when:** changing `ui/leaderboards/FullRankingsScreen.kt`, `RankingsBoardScaffold.kt` or `FullRankingsViewModel`. Behavior: [spec.md](spec.md); overview and code map: [leaderboards/android.md](../leaderboards/android.md).

## Implemented

- `FullRankingsRoute(instrument, rankBy, page)` (defaults `totalscore`, page 1; unknown values fall back). 25-row pages of `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=25`; page count `ceil(totalAccounts / 25)` (≥ 1); an out-of-range page is corrected once totals arrive; a newer request cancels an older one so a superseded page never lands.
- **Route follows the board** (spec native correction): `SyncRouteArguments` writes the current instrument, metric and page back into the back-stack entry's `SavedStateHandle`, and the entry is decoded with `savedStateHandle.toRoute()`, so Back to the board and a recreated entry (process death) restore the same page. Debug deep link: `fullRankings:<instrument>[:<page>]`.
- Title "<Instrument> Leaderboards" (web `renderPageTitle`) led by the chart's icon (issue #294: `FestivalScreen(titleIcon=)`, sized to the bar title's line height, 28 dp at font scale 1.0 and growing with it, decorative so TalkBack reads the title once; it follows the instrument picker). The M3 small top app bar is pinned, so the title never collapses and the icon stays beside it while the rows scroll. "N ranked players" sits above the rows (android-gaps #15); the instrument (current chart icon → menu of Settings-visible charts plus the current one) and Rank By (sort icon → metric menu) are **screen actions** (`TopBarChoiceAction`; the instrument icon is 24 dp, the same height as the Rank By glyph). Switching either returns to page 1; switching or paging runs the shared load swap (`LoadSwap`, issue #71: the rows fade out, the spinner `fst.full-rankings.loading` shows, the new page staggers in), like the web `PaginatedLeaderboard`. A failure replaces the rows inline.
- Selected player: highlighted in place (bold, 6.42) and scrolled into view when on the page; otherwise the web's fixed player footer: their full-width row (opening the profile) in an anchored card above the pager, from the per-instrument own-row read, in the same measured columns and inset as the rows (operator 7.9; the earlier native **Your Page** button was dropped because it narrowed the row). Loading, "Not yet ranked" and inline-failure states in the same card. Rows have hairline separators (6.5) and chevrons (7.3).
- Shared pager (`RankingsPager`, android-gaps #13, operator 6.30/7.4): the web `Paginator` — separate frosted 48 dp circle buttons « ‹ › » around a frosted "page / total" pill (polite live region "Page 2 of 34,760"); « and » drop below 400 dp windows. It is the same component, in the same bottom-anchored `RankingsBoardScaffold` slot, as the song leaderboard's pager (issue #294 checked this; nothing to change on Android). The Rank History charts use the same buttons. Rows are one line like the overview (stacked when a narrow pane can't keep the name readable, see Layout) and fade in per page (`festivalFadeIn`).
- Anonymous rows: "Unknown User", not interactive ([spec live quirk](spec.md#live-data-quirk-2026-09-28)).

## Control placement (decision, 2026-09-28)

| Control | Where | Why |
|---|---|---|
| Instrument, Rank By | Screen actions: the shell's floating toolbar on compact windows (< 600 dp, with global search), top app bar next to search on medium and wider | They change *what* the whole page shows (scope and sort), which Material 3 puts in top app bar actions and Fluent 2 in the page's command bar; the M3 Expressive floating toolbar is the compact home for page-contextual actions ([app-navigation](../../controls/app-navigation/android.md)). Anchoring them above the pager instead would stack pickers, the "your rank" card and the pager at the bottom — about a third of a phone viewport — and separate the scope from the title it changes |
| Pager, "your rank" card | Bottom-anchored over the rows, above the bottom bar / floating toolbar, on every width | Page-to-page navigation is repeated while reading, so it stays within thumb reach (M3 bottom-anchored controls; the web's floating paginator). The list reserves the anchored height as bottom padding, so the last row scrolls clear |

## Layout (`RankingsBoardScaffold`, shared with Band Rankings and the song leaderboard)

| Width / posture | Result |
|---|---|
| Every width without a separating hinge (phone, folded, unfolded, tablet, tri-fold) | Rows fill the pane up to 1100 dp, centred beyond it (issue #115); "your rank" card and floating pager anchored bottom-centre (at most 720 dp wide) |
| Separating vertical hinge (book half-open) | Rows on the leading side of the fold; page information at the top and the anchored "your rank" card + pager at the bottom of the other side |

- **Rows fade out above the footer** (issue #115, `fadeAboveFooter = true`, as on the song leaderboard, issue #93): on every single-pane width the rows are hidden beneath the floating "your rank" card and pager and fade over a linear 36 dp ramp at their top edge (#308, web `useScrollFade`), so no row shows behind or between the pager's circles. Before, rows scrolled visibly under the pager on phone, tablet, unfolded and tri-fold windows, and at font scale 2.0 or in landscape their text collided with it. Increase Contrast, High contrast text, Reduce Transparency and Reduce Motion give a hard cut at the footer's top with rows still hidden beneath it (`BoardFooterEdgeFade`, scroll-edge R7).
- **Names keep a minimum width** (issue #115): the page measures its row width and fits the columns with `LeaderboardSection.keepsNameMinimum`. When rank, a 72 dp × font-scale name, songs, score and chevron don't fit, the songs column drops; when they still don't fit, rows stack (`LeaderboardColumnPlan.stacked`, the large-text layout). Before, the ~236 dp rows pane of a half-open book fold kept every number column and squeezed the name to zero width ("#1 730 / 731 108,227,412"). The first frame (width unknown) keeps the one-line plan.

## Validation (issue #115, live public service, SFentonX selected)

The app is dark-only ([design/android.md](../../design/android.md)), so system light and dark look identical; each configuration was checked in both.

| Configuration | Findings after the fix |
|---|---|
| FST_Phone portrait 1.0 / 2.0 | One-line rows (names ellipsized then; since issue #292 a long name scrolls in its column; TalkBack reads the full name) at 1.0; stacked rows at 2.0; rows fade above the pager; the M3 single-line top app bar title ellipsizes at 2.0 |
| FST_Phone landscape 1.0 / 2.0 | Actions move to the top app bar; rows fade above the pager. At 2.0 the fixed top app bar and bottom navigation leave room for about one stacked row, which still scrolls (shell chrome, not this page) |
| FST_Tablet portrait / landscape, 1.0 / 2.0 | Navigation rail (drawer at 2.0); full one-line rows at 1.0, stacked at 2.0 (large-text rule); footer at most 720 dp, centred |
| FST_Resizable phone / foldable / tablet / desktop | Same compact → medium → expanded progression. Before the fix, desktop rows stretched about 1,600 dp, leaving names far from their scores; the board now stops at 1100 dp, centred (web page container, [Windows](windows.md) list max 1100; M3 large-window content width) |
| FST_Book_Fold folded / half / unfolded | Folded and unfolded as phone and tablet; half-open puts rows left of the hinge (stacked, names readable) and the population, pager and "your rank" right of it |
| FST_Passport_Fold folded / half / unfolded | Folded as phone; half-open splits at the vertical hinge like the book fold (~263 dp rows pane beside the rail, so rows stack with names readable; pager on the other side); unfolded is one pane with rows fading above the pager |
| FST_TriFold folded / partial / unfolded | Single pane (flat folds don't separate); rows fade above the pager |

Accessibility: TalkBack order is title, actions, population, rows (one description each: rank, name, songs, score), "your rank", then the pager. Pager buttons are 48 dp and the page pill is a polite live region. Hidden rows under the footer leave touch and TalkBack (issue #104). Font scale 2.0 shows stacked rows without clipping. With animator scale 0 the load swap and the row fade-in are instant.

## IDs

`fst.full-rankings.list`, `.population`, `.title-icon.<wireId>` (inside the shell's `fst.nav.title-icon`, beside `fst.nav.title`), `.instrument-menu` (items `.instrument-menu.<n>`), `.bottom-bar` (anchored footer + pager), `.supporting-pane` (hinge only), `.pager`, `.page-first|page-previous|page-info|page-next|page-last`, `.spotlight-footer`, `.spotlight-footer.loading`, `.spotlight-footer.unranked`, shared `fst.rankings.rank-by-menu` (items `fst.rankings.rank-by.<metric>`), `fst.rankings.row.<accountId>`.

## Open

- No band-combo filter; no percentile/rank-history extras on this page (the overview has the rank-history card).
