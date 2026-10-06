# Full rankings — Windows notes

> **What:** what the Windows paginated global rankings page implements, its live findings and open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsFullRankingsPage*` or `FullRankingsViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md); band variant: [band-rankings/windows.md](../band-rankings/windows.md).

## Implemented

- Route `AppRoute.FullRankings(instrument, rankBy)` (unknown or missing `rankBy`, including a bare `/leaderboards/all` deep link, → Total Score, web `DEFAULT_METRIC`). 25-row pages of `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=25`; page count `ceil(totalAccounts / 25)` (≥1); an out-of-range page is clamped once totals arrive; a superseded response (older instrument/metric/page) is dropped.
- Header: instrument icon, "<Instrument> Rankings" (heading 1), "N ranked players"; instrument switcher (Settings-visible charts plus the current one) and Rank By, both radio `MenuFlyout`s; switching either returns to page 1. The picker's instrument icon and the Rank By glyph render at the same 18 epx height (operator 2026-09-28; the icon is never shrunk). Rows read "X / Y" (web `getSongsLabel`). The selected player's spotlight loads behind a white ring with no subtitle.
- Rows in a card (`ItemsRepeater` in a `ScrollViewer`); the selected player's row is highlighted. A page change scrolls to the top, or to the selected row when it is on the new page.
- Pinned "your rank" row above the pager when the selected player is not on the page (own-row read is per instrument, independent of the page), with **Your page** (`LeaderboardPaging.PageForRank`): a native addition — the web footer only links to the profile. Loading / unranked / inline-failure states as on the overview.
- Shared pager (`LeaderboardsPager`): First · Previous · "page / total" (polite live region, "Page 2 of 34,760") · Next · Last; First/Last collapse below 380 epx; hidden with one page; Left/Right/Home/End in the pager, Ctrl+Left/Right on the page.
- Rows are the shared `LeaderboardEntryRow` (operator batch 7.7): separate frosted rows, the `X / Y` songs label then the blue rating, like the web `RankingEntry`.
- Back restores the page, switcher and metric: pushed pages keep their view model per back-stack entry (`LeaderboardsPageState`, keyed by the route object Frame hands back).
- Load-swap gate (issue #71): first load, F5, instrument/metric changes and paging run content out (300 ms) → centered ring → ring out (500 ms) → row stagger. Old rows stay only during content-out; new rows, empty and failure states are applied while hidden; rapid choices are latest-wins. Reduce Motion skips the waits and swaps immediately. `ShowContent` is not gated by the swap (issue #208): collapsing the content mid-page-change dropped keyboard focus from the pager to the window.
- **Your page** (issue #208) focuses the selected row first, then centres it (`StartBringIntoView`, ratio 0.5); `FocusedJump` tells the page the spotlight button is about to collapse. `OnRowsBringIntoViewRequested` grows every unaligned focus scroll by the floating footer's height (`LeaderboardPaging.RevealAboveFooter`), so a focused row never sits under the pager (WCAG 2.4.11; same pattern as Song Detail's pinned header).
- At large text a ranking row that cannot fit moves the "X / Y" songs label under the name (`LeaderboardColumnPlan.MetaBelowName`, `LeaderboardEntryRow.PlaceMeta`) instead of truncating the name to "…" (issue #208, WCAG 1.4.4). If the name is still squeezed (live: "#1,450" with an 11-character rating at 200% text, compact), the row stacks on two lines (`ValueBelowName`): rank and name across the rating's column, then the songs label from the rank's edge and the rating. The songs label ellipsizes rather than clip. Applies to every ranking board that uses the shared row.
- Footer edge (issue #308, web `useScrollFade`, [scroll-edge](../../patterns/scroll-edge.md) R2–R4/R7): Rows end at the floating pager and pinned your-rank row through the shared bottom-chrome ramp `BoardFooterFade.Attach` (`Controls/BoardFooterFade`, the same component as Song Leaderboard): clear at the footer's top, opaque 36 epx above it on a linear ramp, the depth min(remaining scroll, 36) so nothing is dimmed at the end. Contrast themes, Windows transparency effects off, Increase Contrast and Less Transparency make it a hard cut at the footer's top. The source is the `BoardFadeSource` wrapper (the load swap animates the list's own visual) and the raw-view `EdgeFadeLayer` `fst.full-rankings.footer-fade` reports `hidden`, `fading:36`, `end` or `hard-edge` (journeys `tools/windows/journeys/a11y-board-footer-fade.json` and `-hard.json`). Before #308 the rows met the pager and pinned your-rank row at a hard edge. The contrast `FooterPlate` stays behind the footer.

## Live findings (2026-09-28)

- Production serves ranking rows with an **empty `accountId` and no `displayName`** (Lead, Total Score, rank 15). Validating every row's ID rejected the whole page; such rows are now accepted, shown as "Unknown User" and not interactive (`AccountRankingEntry.HasProfile`). The same tolerance applies to band rows without `bandId`/`teamKey` and solo chart rows.
- Lead Total Score: 869,000 ranked players (34,760 pages); a rank-40 selected player's pinned row and Your page → page 2 verified live.

## Layout

| Window | Result |
|---|---|
| Wide / medium | Switchers beside the title; list max width 1100 epx |
| Compact | Switchers below the title, instrument switcher icon-only, 12 epx padding, pager without First/Last |

## Evidence

Fixture: `windows/reports/screenshots/full-rankings-{medium,compact,selected-wide}.png`. Live captures (not committed): `C:\Users\sfent\workspace\showcase\win-leaderboards\live-full-rankings-*.png`, `live-spotlight-full-*.png`.

## IDs

`fst.full-rankings.title`, `.list`, `.instrument-menu`, `.instrument.<instrument>`, `.page-first|page-previous|page-info|page-next|page-last`, `.spotlight-footer` (the pinned row's Button), `.spotlight-footer.loading` (the ring), `.spotlight-footer.unranked`, `.spotlight-footer.retry`, `.spotlight-jump`, shared `fst.rankings.rank-by-menu`, `fst.rankings.rank-by.<metric>`, `fst.rankings.row.<accountId>`.

## Validation (issue #208)

Checked 2026-10-03 with the winui-design and winui-code-review skills. Fixture states (`tools/windows/rankings_fixture.py`, journeys `tools/windows/journeys/full-rankings.json`): anonymous, selected on page, selected off page, jumped, unranked, spotlight failed, empty, error. Keyboard journeys (`full-rankings-keyboard.json`): pager, menus + Esc, Your page, rows. Live public service: SFentonX on Lead (#4, on page 1) and Pro Lead (#1,450, page 58). Axe.Windows 0 errors in every row except the WinUI popup findings below.

| Configuration | Finding |
|---|---|
| Compact (500 epx), snap-left/right | Switchers below the title, icon-only instrument switcher (First/Last collapse only below 380 epx). Tab stops 9–13. **Fixed:** at 200% text every name truncated to "…" (the songs label never drops); the label now moves under the name, and with live five-digit ranks and 11-character ratings the row stacks on two lines (fixture ranks were too short to show this; the label had been clipped to "222 / 7"). |
| Medium (900), wide, maximized | Correct; two columns from 1100 epx. Tab stops 12–15. **Fixed:** after Your page the row could land under the floating footer; it is now focused and centred. |
| Keyboard only | Header → instrument → Rank By → rows (one stop, arrows between rows) → pinned row / Your page → pager. Esc closes both menus and returns focus. **Fixed:** Next/Previous/First/Last lost focus to the window during the load swap (`ShowContent` was gated); Your page left focus on a collapsed button and did not scroll to the row. |
| High Contrast (Desert, Night sky, Aquatic, Dusk) | **Fixed:** the floating spotlight cards were translucent over rows (now an opaque `FooterPlate` with ButtonFace in contrast themes), the loading ring was hard-coded White, and the selected row's fill was replaced by the system backplate (now Highlight with `HighContrastAdjustment="None"`). |
| Light and dark system theme | Same rendering: the app is dark only ([design/windows.md](../../design/windows.md#content-branded-fluent-tokens)). |
| Text 200% | Header and pager reflow; at compact the songs label wraps under the name or the row stacks (above). Medium and wide stay on one line. Live compact: 0 Axe errors, plus once the item 8 popup finding. |
| Display 100% / 150% | Correct. |
| Narrator / UIA | Rows are Buttons named "Rank #4, SFentonX. Total Score 105,593,371, 731 / 731 songs"; page info is a polite live region ("Page 2 of 34,694"); menus are radio items with checked state; Your page, Retry and the pinned row have names and IDs. Reading order follows the Tab order. |

Deliberate deviations: a custom pager instead of `PagerControl` (web `Paginator` parity, Fluent circle buttons, keyboard arrows); in non-contrast themes rows scroll under the floating footer like the web backdrop; no scroll fade; the songs label below the name at large text differs from the web's single line. Axe reports `BoundingRectangleCompletelyObscuresContainer` on WinUI's own `PopupHost`/`InputSiteWindowClass` while a menu or the pager tooltip is open ([windows-accessibility.md](../../testing/windows-accessibility.md#open-issues) item 8); no app element is involved.

## Open

- Paging does not update the back-stack route (a restored page comes from the kept view model, not the route).
- No band-combo filter; no percentile/rank-history extras.
- ~~The shared `ServiceStatusView` Retry gets WinUI's default text backplate in Night sky~~: fixed in issue #233 ([service-status/windows.md](../../controls/service-status/windows.md)).

Band Rankings got the same ungated `ShowContent` fix and a contrast `FooterPlate` in issue #209 ([band-rankings/windows.md](../band-rankings/windows.md#validation-issue-209-2026-10-03)).

## Pager (operator batch 6.30)

`Controls/LeaderboardsPager` follows the web `Paginator` + `FixedLeaderboardPagination` (refined in operator batch 7.4, see [design/windows.md](../../design/windows.md)): 40 epx circles with double chevrons for first/last and single ones for previous/next either side of a `cardBackground` "page / total" badge, no plate behind them, floating with the pinned selected-player row over the bottom of the rows (`Controls/BoardFooter`). Shared by every paged board.

## Two columns (wide)

From a 1100 epx page the rankings keep a 560 epx column and the chosen player's profile (`PlayerProfilePage` in `DetailFrame`, `fst.full-rankings.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). The profile starts on the selected player's row when it is on the page, else the first row; it follows row clicks (rows ask an `IRouteHost` ancestor before pushing) and survives paging while that player is still listed. The shown player's row gets a subtle fill (`LeaderboardEntryRow.IsCurrent`). Below 1100 epx, or without rows, the page is the single 1100 epx column again. Band Rankings and All Rivals use the same split ([band-rankings](../band-rankings/windows.md#two-columns), [all-rivals](../all-rivals/windows.md#two-columns)).
