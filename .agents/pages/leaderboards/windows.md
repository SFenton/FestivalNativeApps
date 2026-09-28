# Leaderboards overview — Windows notes

> **What:** what the Windows Leaderboards section root implements, its layout per window size and open gaps. **Read when:** changing `windows/Festival.App/Pages/LeaderboardsPage*`, `LeaderboardsViewModel` or the shared rankings rows. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- Section root for `AppSection.Leaderboards` and `AppRoute.Leaderboards` (`NavigationCacheMode="Required"`: returning from a pushed page keeps the cards; `ActivateAsync` reloads only when metric, Settings-visible instruments or the selected player changed).
- One top-ten card (`GET /api/rankings/{instrument}?rankBy=&page=1&pageSize=10`, publication-pinned pure read) per Settings-visible instrument, then Duos · Trios · Quads (`GET /api/rankings/bands/{bandType}`). At most four card reads are in flight (twelve at once overflowed the fixture server's listen backlog and is needlessly bursty for the service).
- Rank By: `DropDownButton` + radio `MenuFlyout` (Total Score first, then Adjusted, Weighted, FC Rate, Max Score). Persisted as `AppSettings.LeaderboardRankBy` (web `saveLeaderboardRankBy`); band cards narrow Max Score to Total Score (`coerceBandRankingMetric`). All metrics are offered, as on iPhone; the web hides them behind its experimental-ranks flag.
- Per card: static skeleton (no shimmer, so no per-frame work), empty text, inline failure with Retry and scrape-freeze countdown, rows, "View All" → `AppRoute.FullRankings(instrument, rankBy)` / `AppRoute.BandRankings(bandType)`. "Browse Bands" beside the Bands heading opens `AppRoute.Bands` (the landing is not in the navigation pane).
- Selected-player spotlight (`RankingSpotlight.Place`): highlighted in place (purple fill + border, UIA name "Your rank, 2nd. Name. …") when in the top ten, with no extra read; otherwise their own row from `GET /api/rankings/{instrument}/{accountId}` (`FestivalApiClient.GetPlayerInstrumentRankingAsync`, win-profile lane) below the rows, "Loading your rank…", "Not yet ranked on <instrument>." (404) or an inline retry. No selected-band spotlight: Windows has no selected-band identity.
- Rows: rank, name ("Unknown User" when blank), "X / Y songs" (full combos under FC Rate), rating ("Top N%" + Bayesian value for percentile metrics, percentages, grouped totals). A row opens `AppRoute.Player(accountId, displayName)`; band rows open `AppRoute.Band(bandId, bandType, teamKey)` (never `/api/bands/{id}`). Rows whose identity is unusable are shown but not interactive (see [full-rankings/windows.md](../full-rankings/windows.md)).
- Each card's header (36 px instrument icon or band glyph, title as heading 2, metric subtitle) sits **above** the card surface like the web's `RankingCard` `cardLabel`, inside the same named UIA group.
- F5 reloads every card.

## Layout

| Window | Result |
|---|---|
| Wide (1440+) | Cards in 3 columns (`LeaderboardsCardGridLayout`: equal columns ≥360 epx, max 4; each row as tall as its tallest card, so a spotlight or failure never clips like `UniformGridLayout`) |
| Medium (~900) | One column (the fixed 240 epx pane leaves ~540 epx) |
| Compact (~500) | One column, 12 epx page padding, Rank By below the title; names and song counts trim. The shell keeps the navigation pane expanded at this width, leaving ~340 epx (TODO(orchestrator): shell pane display mode below ~640 epx) |

## Evidence

Fixture screenshots: `windows/reports/screenshots/leaderboards-{wide,medium,compact,selected-wide,unranked-medium}.png`. UI journey (fixture): `tools/windows/journeys/leaderboards.steps` via `uiwin.py drive --steps-file` (Rank By switch, View All, instrument switcher, band card, band-size switcher, Back).

## IDs

`fst.leaderboards` (scroller), `fst.leaderboards.card.<instrument>` (card heading), `.view-all`, `.spotlight`, `.spotlight.loading`, `.spotlight.unranked`, `fst.leaderboards.band-card.<bandType>`, `.view-all`, `fst.leaderboards.bands-link`, `fst.rankings.rank-by-menu`, `fst.rankings.rank-by.<metric>`, `fst.rankings.row.<accountId>` (or `…row.rank-<n>` without an ID), `fst.band-rankings.row.<teamKey>`.

## Open

- No rank-history chart, band-combo filter or quick links (same as iPhone).
- Narrator and keyboard-order audit not yet done (a later phase); the card containers themselves have no UIA element (the heading carries the card ID).
