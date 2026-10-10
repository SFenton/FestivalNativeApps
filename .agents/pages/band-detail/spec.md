# band-detail (`/bands/:bandId`) — spec

> **What:** the band page's web behavior, sections and native rules. **Read when:** changing the band page on any platform. Platform state: [ios.md](ios.md), [android.md](android.md), [windows.md](windows.md).

- Guard: `none` · Web source: `FortniteFestivalWeb/src/pages/band/BandPage.tsx` (route `App.tsx:126`)

## Web behavior

- **Header** (`PageHeader`): title = member names joined with " + " (`formatBandTitle`), subtitle `band.subtitle` "{type} • {N} appearances" (N = songs played). Native: the system navigation title plus a subtitle line as the first content row (#555).
- **Members**: one card per member, avatar initial, name, instrument icons, chevron; opens the player page.
- **Summary**: `StatCard`s Type, Appearances, Members.
- **Statistics**: `StatBox` grid. The rank tiles first (Adjusted Percentile, Weighted Percentile and FC Rate only with Settings › Experimental Ranks on, then Total Score), each opening Band Rankings for that metric at the band's page (25 per page); then Songs Played and Full Combos (`x / total`, gold when complete), Total Score, FC Rate, Avg Accuracy, Avg Stars (gold at 6), Best Song Rank (opens the best song) and Avg Rank.
- **Rank History**: `BandRankHistoryChart` over the past 30 days for the page's metric (web: Adjusted with Experimental Ranks on, Total Score while off; native Rank By picks it while on), with the history status sentence.
- **Songs**: `BandSongsSection` Five Best Songs and Five Worst Songs, each with a description ("{name}'s highest/lowest-ranked band songs, sorted by percentile."), album art, title, artist and percentile bucket; rows open Song Detail.
- Quick Links: Members, Summary, Statistics, Rank History, Songs in page order.

## Native rules

- R1. The band name is the standard navigation title; pages keep the system display mode for their platform (Apple large title on iPhone/iPad/Duo, [page-tools-and-nav-chrome](../../patterns/page-tools-and-nav-chrome.md) R14). The subtitle is page content directly under it, not `navigationSubtitle` (same as Band Rankings' count header).
- R2. Section titles are the canonical white Title Case heading ([section-headers](../../patterns/section-headers.md) R1) over card surfaces ([surface-materials](../../patterns/surface-materials.md)); stat tiles reuse the player profile's stat grid.
- R3. Rank History reuses the player profile chart and its centred date axis ([chart-date-axis](../../patterns/chart-date-axis.md)).
- R4. Band song percentiles are bucketed from `rank / totalEntries` (the service's `percentile` is a 0–1 fraction, which web `formatPercentileBucket` reads as a percentage and clamps to "Top 1%"; agent decision #555). Each row speaks "rank X of Y".
- R5. Settings › Experimental Ranks gates the page (pattern [experimental-ranks](../../patterns/experimental-ranks.md) R1/R3/R4, as web `BandPage`): while off the metric is Total Score, Rank By is hidden and Total Score Rank is the only rank tile; turning it on adds Rank By (Adjusted by default, Total Score first in its list) and the Adjusted, Weighted and FC Rate rank tiles to the open page, and turning it off removes them again.
- R6. No "Select Band Profile" action yet: no native platform persists a selected band.
- Never call `GET /api/bands/{bandId}` (write side effect, see [ios.md](ios.md)); read the rankings board by `teamKey`.
