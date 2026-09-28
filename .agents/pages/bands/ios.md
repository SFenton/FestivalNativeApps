# Bands landing — iPhone notes

> **What:** iPhone implementation state and decisions for the `/bands` lookup landing page. **Read when:** changing this page on iPhone. Behavior: [spec.md](spec.md) (currently a stub — this file is the source of truth for what's actually built until spec.md is promoted).

Source: `FortniteFestivalWeb/src/pages/band/` (band lookup by name). Service: `FSTService/Api/RankingsEndpoints.cs:755` (`/api/bands/search`) — **blocked**, not called from this app: when its projection is absent it deletes/rebuilds membership state as a side effect of a GET (`GlobalLeaderboardPersistence.cs:3954-3971`, `BandLeaderboardPersistence.cs:905-947`; see [service-safety.md](../../platforms/service-safety.md)).

- Implemented: a landing screen with no search field. Shows a "Your Bands" card linking to `AppRoute.playerBands` for the selected player (hidden with no profile selected), a "Band Rankings" card linking to `AppRoute.bandRankings` for each `BandType`, and an explanatory footnote naming the exact reason lookup-by-name isn't offered. This is a deliberate reduction, not a stub: the web page's only other capability (typed band search) needs the blocked endpoint.
- Simplified vs. web this pass: no name search field, no recent-lookups list. Revisit only if the service owner grants a mutation-free policy for `/api/bands/search` (see `AGENTS.md`).
- IDs: `fst.bands.screen`, `fst.bands.your-bands`, `fst.bands.rankings.<bandType>`.
- Tests: no dedicated Core logic (this screen is static composition of existing routes); covered indirectly by `BandsTests.swift`'s `PlayerBandGroup`/`BandType` coverage. No hosted-UI/XCUITest coverage yet.
