# Leaderboards overview — Windows notes

> **What:** what the Windows Leaderboards section root implements, its layout per window size and open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsPage*`, `LeaderboardsViewModel` or the shared rankings rows. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Section root for `AppSection.Leaderboards` and `AppRoute.Leaderboards` (`NavigationCacheMode="Required"`: returning from a pushed page keeps the cards; `ActivateAsync` reloads only when metric, Settings-visible instruments or the selected player changed).
- One top-ten card (`GET /api/rankings/{instrument}?rankBy=&page=1&pageSize=10`, publication-pinned pure read) per Settings-visible instrument, then Duos · Trios · Quads (`GET /api/rankings/bands/{bandType}`). At most four card reads are in flight (twelve at once overflowed the fixture server's listen backlog and is needlessly bursty for the service).
- Rank By: `DropDownButton` + radio `MenuFlyout` (Total Score first, then Adjusted, Weighted, FC Rate, Max Score). Persisted as `AppSettings.LeaderboardRankBy` (web `saveLeaderboardRankBy`); band cards narrow Max Score to Total Score (`coerceBandRankingMetric`). Gated by Settings' Experimental Ranks like the web (issue #541): off (the default) hides the button (`ShowRankBy`) and loads Total Score, keeping the saved metric for when it is turned back on (`RankingMetrics.Gate`, web `coerceRankingMetric`); on offers every metric. Turning it off on a cached page reloads the boards at Total Score (`SyncRankBy`). Accessibility: `tools/windows/journeys/a11y-experimental-ranks.json` (`ui_ci.py` runs `experimental-ranks`, `-text-225`).
- Per card: static skeleton (no shimmer, so no per-frame work): five `LeaderboardRowMetrics.SkeletonRows` drawn by the canonical `LeaderboardEntryRow` as bars in the loaded rows' column plan, so at every width, text size and Rank By metric the card does not jump when rows arrive (#90, #281; tests `LeaderboardSkeletonTests`, UIA journey `tools/windows/journeys/leaderboard-skeleton.json`). The selected player's "loading your rank" spotlight is the same placeholder row under a ring, empty text, inline failure with Retry and scrape-freeze countdown, rows, the selected player's spotlight row when outside the top ten, then a full-width purple "View all rankings (868,901)" button (web `viewAllRankingsWithCount`, the response's `totalAccounts`/`totalTeams`; no count when unknown) → `AppRoute.FullRankings(instrument, rankBy)` / `AppRoute.BandRankings(bandType)`. Its UIA name starts with the visible label, then the board ("View All Rankings (868,901), Lead"; WCAG 2.5.3 label in name, issue #207).
- Selected-player spotlight (`RankingSpotlight.Place`): highlighted in place (purple fill + border, UIA name "Your rank, 2nd. Name. …") when in the top ten, with no extra read; otherwise their own row from `GET /api/rankings/{instrument}/{accountId}` (`FestivalApiClient.GetPlayerInstrumentRankingAsync`, win-profile lane) below the rows, a white ring (no caption), "Not yet ranked on <instrument>." (404) or an inline retry. That separate row opens Full Rankings on its page and reveals the row ("Jump to your position", #370; [Compete notes](../compete/windows.md)); the in-place top-ten row opens the profile. No selected-band spotlight: Windows has no selected-band identity.
- Rows: rank, name ("Unknown User" when blank; a name that doesn't fit scrolls inside its column with the shared `MarqueeText`, issue #292, and ellipsizes with the full name as the tooltip under Animation effects off or Reduce Motion; Narrator reads it once in the row name), "X / Y" (web `getSongsLabel`; UIA says "X / Y songs") (full combos under FC Rate), rating ("Top N%" + Bayesian value for percentile metrics, percentages, grouped totals). A row opens `AppRoute.Player(accountId, displayName)`; band rows open `AppRoute.Band(bandId, bandType, teamKey)` (never `/api/bands/{id}`). Rows whose identity is unusable are shown but not interactive (see [full-rankings/windows.md](../full-rankings/windows.md)).
- Each card's header sits **above** the card surface like the web's `RankingCard` `cardLabel`, inside the same named UIA group (`Controls/CardHeader`): 36 px instrument icon + name only (no metric subtitle: the Rank By button names it); Duos/Trios/Quads headers have no icon. Cards and rows stagger in (`FadeIn`).
- F5 reloads every card.
- Load-swap gate (issue #71): first load and user reloads (Rank By, F5, visible-instrument changes) run the web sequence through `LoadSwap`: old cards fade out for 300 ms, a centered ring shows, the ring fades out for 500 ms, then the refreshed cards stagger in. Rows are replaced only while hidden; rapid metric changes are latest-wins. Reduce Motion makes the swap instant. Rank By loads once (it used to reload every card twice via the settings-change event).
- One leaderboard row design (operator batch 7.7): no card around a chart's rows; each is its own frosted `LeaderboardEntryRow` (4 epx apart, shared-width ranks, `X / Y` then the blue rating, purple bold selected-player row); empty or failed charts and the unranked note sit on their own card (see [design/windows.md](../../design/windows.md)). The "Bands" heading is 26 epx, a size above the Duos/Trios/Quads card headers (6.8).

## Layout

| Window | Result |
|---|---|
| Wide (1280+, maximized) | Cards in 3 columns (`LeaderboardsCardGridLayout`: equal columns ≥360 epx, max 4; each row as tall as its tallest card, so a spotlight or failure never clips like `UniformGridLayout`) |
| Medium (~900, snapped half of a 1280 epx desktop) | Two columns beside the compact (icon) pane |
| Compact (<641) | One column, 12 epx page padding, Rank By and Quick Links below the title; the shell pane collapses to the hamburger (LeftMinimal) |
| Large text | `ScaleWithText` multiplies the 360 epx minimum column by the Windows text size, so at 200% medium drops to one column. Rankings rows that still can't give the name `MinNameWidth` move the songs label under the name, then the rating too (`MetaBelowName`/`ValueBelowName`, issue #208); score rows (song leaderboard, Score History) stack the score, badge and stars under the name instead (a third line when a pinned season and the score don't fit side by side; `LeaderboardColumnPlan.Stacked`/`SplitValues`, issue #207). Chevron centered. 100% layouts are unchanged |

## Evidence

Fixture screenshots: `windows/reports/screenshots/leaderboards-{wide,medium,compact,selected-wide,unranked-medium}.png`. UI journey (fixture): `tools/windows/journeys/leaderboards.steps` via `uiwin.py drive --steps-file` (Rank By switch, View All, instrument switcher, band card, band-size switcher, Back). Every reachable overview state (issue #207): `python tools/windows/leaderboards_journey.py [--sizes compact,medium,wide] [--shots DIR]` on `tools/windows/leaderboards_fixture.py` (mock service plus per-board empty, scrape-frozen and failing overrides). Long-name marquee (issue #292): `leaderboards_journey.py --only long-name --shots DIR` starts the fixture with `--long-name` (two shots 2 s apart on the overview, plus Full Rankings, show the name scrolling inside its column). Accessibility pages `leaderboards`, `leaderboards-selected`, `leaderboards-unranked`, `leaderboards-spotlight-failed` and `leaderboards-rank-by-menu` in `tools/windows/journeys/a11y.json` (`a11y_matrix.py --scan`).

## Validation (issue #207)

Checked 2026-10 with the winui-design and winui-code-review skills, `leaderboards_journey.py` (30/30 across compact, medium and wide), `a11y_matrix.py --scan` on the fixture pages above, and the live public service (SFentonX selected, no profile headers). Axe.Windows reports 0 errors in every row, apart from the framework `PopupHost` finding in Open.

| Configuration | Finding |
|---|---|
| Compact (500 epx), snap-left (640) | One column with the hamburger pane; Rank By and Quick Links sit under the title; correct. |
| Medium (900), wide (1280, clamped by the 300% 4K desktop), maximized, snap-right | Two or three equal columns; rows of mixed card heights align (the spotlight and failed cards don't clip); correct. |
| Keyboard only | Shell → Rank By → Quick Links → for each card, its row group (one Tab stop; arrows move between rows) → View All, in reading order. 20–21 stops at medium with no repeats and nothing off-window. Focus stays visible on every stop. |
| High Contrast (Desert, Night sky) | System colours: the selected-player row uses Highlight, and text sits on backplates; correct. |
| Light and dark system theme | Same rendering. This is a deliberate deviation: the app is dark only ([design/windows.md](../../design/windows.md#content-branded-fluent-tokens)). |
| Text 200% | **Fixed:** at compact, names collapsed to "…"; at medium they disappeared. Columns now scale with the text size, and rows stack (see Layout). The shell's notification badge no longer overflows at 200% (fixed in #229, rechecked in #253). |
| Display 100% / 150% | Correct. |
| Narrator / UIA | Headings per card, and rows named with state ("Your rank, 1st. …", "Rank #1, …"). **Fixed:** View All was named "View All Lead Rankings" while showing "View All Rankings (3)" (WCAG 2.5.3). It is now the visible label then the board ("View All Rankings (3), Lead"). **Fixed:** failed cards exposed an empty countdown text element. |
| Motion | Rank By swaps the cards through the loading state and back without a layout jump (live frame sequence). |

## IDs

`fst.leaderboards` (scroller), `fst.leaderboards.card.<instrument>` (card heading), `.view-all`, `.spotlight`, `.spotlight.loading`, `.spotlight.unranked`, `fst.leaderboards.band-card.<bandType>`, `.view-all`, `fst.leaderboards.bands-header`, `fst.quick-links.open`, `fst.quick-links.item.instrument:<instrument>` / `band:<bandType>`, `fst.rankings.rank-by-menu`, `fst.rankings.rank-by.<metric>`, `fst.rankings.row.<accountId>` (or `…row.rank-<n>` without an ID), `fst.band-rankings.row.<teamKey>`.

## Back navigation

Back from a cached page keeps its scroll position: `Services/CachedPageScroll` pauses focus-follow scrolling while the page leaves (#82) and returns focus to the View All that was opened, without scrolling (#276). Accessibility test: `tools/windows/journeys/a11y-back-keeps-place.json` (Narrator phrase, role, 40 epx target, reading order and Tab from the returned focus, at 100% and 225% text in the `windows-ui` CI job; #435). Pattern: [back-keeps-place](../../patterns/back-keeps-place.md); findings in [Compete Windows notes](../compete/windows.md).

## Open

- No rank-history chart or band-combo filter (same as iPhone).
- WinUI's flyout `PopupHost` (Rank By, Quick Links) reports Axe `BoundingRectangleCompletelyObscuresContainer`: framework, [windows-accessibility.md](../../testing/windows-accessibility.md) open item 8.
