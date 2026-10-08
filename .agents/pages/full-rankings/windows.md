# Full rankings — Windows notes

> **What:** what the Windows paginated global rankings page implements, its live findings and open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsFullRankingsPage*` or `FullRankingsViewModel`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md); band variant: [band-rankings/windows.md](../band-rankings/windows.md).

## Implemented

- Route `AppRoute.FullRankings(instrument, rankBy)` (unknown or missing `rankBy`, including a bare `/leaderboards/all` deep link, → Total Score, web `DEFAULT_METRIC`). 25-row pages of `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=25`; page count `ceil(totalAccounts / 25)` (≥1); an out-of-range page is clamped once totals arrive; a superseded response (older instrument/metric/page) is dropped.
- Header: instrument icon, "<Instrument> Rankings" (heading 1), "N ranked players"; instrument switcher (Settings-visible charts plus the current one) and Rank By, both radio `MenuFlyout`s; switching either returns to page 1. The picker's instrument icon and the Rank By glyph render at the same 18 epx height (operator 2026-09-28; the icon is never shrunk). Rows read "X / Y" (web `getSongsLabel`). The selected player's spotlight loads behind a white ring with no subtitle.
- Rows in a card (`ItemsRepeater` in a `ScrollViewer`); the selected player's row is highlighted. A page change scrolls to the top, or to the selected row when it is on the new page.
- Pinned "your rank" row above the pager on every page whenever the selected player is ranked, their own page included (issue #318, [leaderboard-row](../../patterns/leaderboard-row.md) R7; web `FullRankingsPage` `hasPlayerFooter = !!playerRanking`): `RankingSpotlightViewModel(pinned: true)` places it with `RankingSpotlight.PlacePinned`, which never goes inline; the overview cards keep `Place` and still hide a player in their top rows (web `RankingCard`). The own-row read is per instrument, independent of the page, and always made; until it answers, the player's page row stands in. The pinned row is itself the control (R7, `SelectedRowAction.Footer`, the same rule as the song and song band boards since #307): while the player's row is on another page it runs the spotlight's `JumpCommand` (`LeaderboardEntryRow.Command`) and is named "Your rank, 40th. Jump to your position. …"; once the row is on the shown page (or the shown page is its rank's page) it opens the player's profile (detail column in two columns), named "… Open your statistics. …". There is no separate **Your page** button (removed in the #318 review: it split R7's one control in two). Before #318 the footer was hidden while the player's row was on the page. Loading / unranked / inline-failure states as on the overview.
- Shared pager (`LeaderboardsPager`): First · Previous · "page / total" (polite live region, "Page 2 of 34,760") · Next · Last; First/Last collapse below 380 epx; hidden with one page; Left/Right/Home/End in the pager, Ctrl+Left/Right on the page.
- Rows are the shared `LeaderboardEntryRow` (operator batch 7.7): separate frosted rows, the `X / Y` songs label then the blue rating, like the web `RankingEntry`.
- Back restores the page, switcher and metric: pushed pages keep their view model per back-stack entry (`LeaderboardsPageState`, keyed by the route object Frame hands back).
- Load-swap gate (issue #71): first load, F5, instrument/metric changes and paging run content out (300 ms) → centered ring → ring out (500 ms) → row stagger. Old rows stay only during content-out; new rows, empty and failure states are applied while hidden; rapid choices are latest-wins. Reduce Motion skips the waits and swaps immediately. `ShowContent` is not gated by the swap (issue #208): collapsing the content mid-page-change dropped keyboard focus from the pager to the window.
- The pinned "your rank" row is part of the gate when its value can change (issue #270, [load-transition](../../patterns/load-transition.md) R2 agent decision): `SpotlightGate` (a `LoadSwapGate`, keyed by `PinnedRowGate` on instrument + Rank By) fades it out with the rows and removes it from UI Automation, so a Rank By or instrument switch never shows the old value beside the spinner. Paging, F5 and Retry keep it visible and usable beside the spinner, like the web footer (`footerAnimKey={cacheKey}` ignores the page). After a gated reload it fades in with the first row (`PinnedRowReveal`), and a late own-rank read fades in on its own. `FullRankingsViewModel` keeps the old instrument's spotlight until the new board commits; a failed switch drops it. Same mechanism as the song leaderboard (#295).
- After the pinned row's jump the page centres the selected row (`StartBringIntoView`, ratio 0.5) once the load swap reveals the new page (`ContentRevealed`), after a forced layout pass, and skips the scroll-to-top for that page: centring rows the repeater had not yet laid out, or racing a pending `ChangeView(0)`, intermittently left the row off screen (#318 review, 2 of 6 keyboard runs before, 9 of 9 after). The centring runs through `SelectedRowReveal` (issues #307 and #323): it waits for the row's own entrance while the rows below the first screen wait for the jump, rushes the fades still waiting so the rows it reaches fade in together, and gives way if the reader scrolled meanwhile ([load-transition](../../patterns/load-transition.md) Windows selected-row reveal). Keyboard focus stays on the pinned row, which stays in place, so a second Enter opens the profile (#318; before it, the collapsing Your page button handed focus to the list row, issue #208). `OnRowsBringIntoViewRequested` grows every unaligned focus scroll by the floating footer's height (`LeaderboardPaging.RevealAboveFooter`), so a focused row never sits under the pager (WCAG 2.4.11; same pattern as Song Detail's pinned header).
- Opened with `navToPlayer=true` (`AppRoute.FullRankings.RevealSelected`, from a Leaderboards card's "your rank" row, #370) the page reveals the selected row on its first load the same way, as the song board does for `navToPlayer`; Back to an already-created page does not reveal it again.
- At large text a ranking row that cannot fit moves the "X / Y" songs label under the name (`LeaderboardColumnPlan.MetaBelowName`, `LeaderboardEntryRow.PlaceMeta`) instead of truncating the name to "…" (issue #208, WCAG 1.4.4). If the name is still squeezed (live: "#1,450" with an 11-character rating at 200% text, compact), the row stacks on two lines (`ValueBelowName`): rank and name across the rating's column, then the songs label from the rank's edge and the rating. The songs label ellipsizes rather than clip. Applies to every ranking board that uses the shared row.
- Footer edge (issue #308, web board `Page.tsx` `useScrollMask`, 40 px linear, [scroll-edge](../../patterns/scroll-edge.md) R2–R4/R7): Rows end at the floating pager and pinned your-rank row through the shared bottom-chrome ramp `BoardFooterFade.Attach` (`Controls/BoardFooterFade`, the same component as Song Leaderboard): clear at the footer's top, opaque 40 epx above it on a linear ramp, the depth min(remaining scroll, 40) so nothing is dimmed at the end. Contrast themes, Windows transparency effects off, Increase Contrast and Less Transparency make it a hard cut at the footer's top. The source is the `BoardFadeSource` wrapper (the load swap animates the list's own visual) and the raw-view `EdgeFadeLayer` `fst.full-rankings.footer-fade` reports `hidden`, `fading:40`, `end` or `hard-edge` (journeys `tools/windows/journeys/a11y-board-footer-fade.json` and `-hard.json`). Before #308 the rows met the pager and pinned your-rank row at a hard edge. The contrast `FooterPlate` stays behind the footer.

## Live findings (2026-09-28)

- Production serves ranking rows with an **empty `accountId` and no `displayName`** (Lead, Total Score, rank 15). Validating every row's ID rejected the whole page; such rows are now accepted, shown as "Unknown User" and not interactive (`AccountRankingEntry.HasProfile`). The same tolerance applies to band rows without `bandId`/`teamKey` and solo chart rows.
- Lead Total Score: 869,000 ranked players (34,760 pages); a rank-40 selected player's pinned row → page 2 verified live (then via Your page; since #318 the pinned row jumps).

## Layout

| Window | Result |
|---|---|
| Wide / medium | Switchers beside the title; list max width 1100 epx |
| Compact | Switchers below the title, instrument switcher icon-only, 12 epx padding, pager without First/Last |

## Evidence

Fixture: `windows/reports/screenshots/full-rankings-{medium,compact,selected-wide}.png`. Live captures (not committed): `C:\Users\sfent\workspace\showcase\win-leaderboards\live-full-rankings-*.png`, `live-spotlight-full-*.png`.

## IDs

`fst.full-rankings.title`, `.list`, `.instrument-menu`, `.instrument.<instrument>`, `.page-first|page-previous|page-info|page-next|page-last`, `.spotlight-footer` (the pinned row's Button), `.spotlight-footer.loading` (the ring), `.spotlight-footer.unranked`, `.spotlight-footer.retry` (no `.spotlight-jump` since #318: the pinned row is the jump), shared `fst.rankings.rank-by-menu`, `fst.rankings.rank-by.<metric>`, `fst.rankings.row.<accountId>`.

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

Deliberate deviations: a custom pager instead of `PagerControl` (web `Paginator` parity, Fluent circle buttons, keyboard arrows); the songs label below the name at large text differs from the web's single line. Axe reports `BoundingRectangleCompletelyObscuresContainer` on WinUI's own `PopupHost`/`InputSiteWindowClass` while a menu or the pager tooltip is open ([windows-accessibility.md](../../testing/windows-accessibility.md#open-issues) item 8); no app element is involved.

## Footer edge (issue #305)

Rows end at the floating footer (pinned row or pager) through the shared 40 epx bottom-chrome ramp (`BoardFooterFade.Attach`, #308) with or without a selected player ([scroll-edge](../../patterns/scroll-edge.md) R9). Before #305/#308 the page had no fade, so rows ran straight under the pager. `tools/windows/journeys/a11y-board-footer-fade-no-player.json` asserts the no-player case. Live check, 2026-10-06: anonymous Lead, medium, scrolled to 40% and to the end.

## Validation (issue #270)

Checked 2026-10-06 against the [load-transition](../../patterns/load-transition.md) sequence with the winui-design and winui-code-review skills. Fixture journeys `full-rankings.json` (11 states), `full-rankings-keyboard.json` and `full-rankings-swap.json` (`rankings_fixture.py --rankings-delay 3`: an off-page player, delayed Rank By and instrument reloads with the spinner up and the pinned row absent from UIA, then the new row back; paging keeps it; normal and `--reduce-motion`); live films with SFentonX selected (Lead, Rank By on page 2, instrument switch).

| Configuration | Finding |
|---|---|
| Compact, medium, wide, maximized, snap-left/right | Rows, empty and failure states fade out → ring → fade in. **Fixed:** the pinned "your rank" row stayed outside the gate: Rank By kept the old metric's value beside the ring and popped at commit, and an instrument switch dropped it immediately. It is now gated with the rows on Rank By and instrument changes and stays put while paging (above). Tab stops 9–14 (empty 6–8, error 7–9), none outside the app, no repeats. |
| High Contrast (Desert, Night sky), text 200%, display 100% / 150% | Same sequence; ring and pinned row visible in contrast themes; 0 Axe errors. |
| Light and dark system theme | Same: the app is dark only. |
| Reduce Motion (`--reduce-motion`) | Swaps without waits; the pinned row appears with no fade (`FadeIn.Enter` resets it) and the jump to the selected row is immediate; 0 Axe errors. |
| Keyboard only | Pager, menus + Esc, Your page and rows journeys pass at compact, medium and wide; focus stays on the pager while the board reloads. |
| Narrator / UIA | The ring is named "Loading rankings"; the title, switchers and pager stay readable during a reload. **Fixed:** the gated pinned row and Your page stayed in the UIA control view under the ring (`AccessibilityView="Raw"` doesn't hide descendants); `LoadSwapGate` now reports no children while gated (`full-rankings-swap.json` asserts it). |

Deliberate deviation: winui-design's layout review asks for loading "progress text or skeleton; not just a spinner with no context". The ring follows web (R1); the context comes from the title, switchers and pager, which stay visible, and from the ring's name. Axe reports only the known WinUI `PopupHost` finding (item 8 above) while a menu or the pager tooltip is open.

## Validation (issue #318)

Checked 2026-10-06 with the winui-design and winui-code-review skills. Reproduced on master with `full-rankings.json` (`rankings_fixture.py`): `fr-selected-on-page` and `fr-jumped` found no `fst.full-rankings.spotlight-footer`. After the fix, all 11 states pass at compact, medium and wide (Axe 0 except item 8 on menus/tooltips); `fr-selected-on-page` asserts the pinned row and no Your page, and `fr-jumped` asserts the row stays after the jump. `full-rankings-swap.json` (normal, Reduce Motion), `full-rankings-keyboard.json` and the Full Rankings `a11y-board-footer-fade.json` states (fade, end, More Contrast, Less Transparency; the page-1 player now has a footer) pass. Live: SFentonX on Lead is #4 on page 1, highlighted in the list and pinned above "1 / 34,691".

Review follow-up (R7 row-as-control, 2026-10-06): the separate **Your page** button is gone; the pinned row reads "Your rank, 40th. Jump to your position. …" off-page and "… Open your statistics. …" once the row is shown. `full-rankings.json` (12 states; new `fr-pinned-opens-profile`: invoke the footer → row 40 on page 2 → invoke it again → `fst.player`) passes at compact, medium and wide; `kb-fr-jump` (Enter on the footer → row 40, focus kept on the footer → Enter → profile) passes 3 × 3 sizes; `full-rankings-swap.json` and all `a11y-board-footer-fade.json` states pass. Overview cards keep opening the profile (no jump command).

## Open

- Paging does not update the back-stack route (a restored page comes from the kept view model, not the route).
- No band-combo filter; no percentile/rank-history extras.
- ~~The shared `ServiceStatusView` Retry gets WinUI's default text backplate in Night sky~~: fixed in issue #233 ([service-status/windows.md](../../controls/service-status/windows.md)).

Band Rankings got the same ungated `ShowContent` fix and a contrast `FooterPlate` in issue #209 ([band-rankings/windows.md](../band-rankings/windows.md#validation-issue-209-2026-10-03)).

## Pager (operator batch 6.30)

`Controls/LeaderboardsPager` follows the web `Paginator` + `FixedLeaderboardPagination` (refined in operator batch 7.4, see [design/windows.md](../../design/windows.md)): 40 epx circles with double chevrons for first/last and single ones for previous/next either side of a "page / total" badge, all on the rows' card surface (`FSTCardSurfaceBrush` + `FSTCardStrokeBrush`, #319) with no plate behind them, floating with the pinned selected-player row over the bottom of the rows (`Controls/BoardFooter`). Shared by every paged board.

## Two columns (wide)

From a 1100 epx page the rankings keep a 560 epx column and the chosen player's profile (`PlayerProfilePage` in `DetailFrame`, `fst.full-rankings.detail-pane`) fills the rest (operator 2026-09-28: two populated columns, never an empty detail). The profile starts on the selected player's row when it is on the page, else the first row; it follows row clicks (rows ask an `IRouteHost` ancestor before pushing) and survives paging while that player is still listed. The shown player's row gets a subtle fill (`LeaderboardEntryRow.IsCurrent`). Below 1100 epx, or without rows, the page is the single 1100 epx column again. Band Rankings and All Rivals use the same split ([band-rankings](../band-rankings/windows.md#two-columns), [all-rivals](../all-rivals/windows.md#two-columns)).
