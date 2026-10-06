# Bands landing — iPhone notes

> **What:** iPhone implementation state and decisions for the `/bands` lookup landing page. **Read when:** changing this page on iPhone. Behavior: [spec.md](spec.md) (currently a stub — this file is the source of truth for what's actually built until spec.md is promoted).

Source: `FortniteFestivalWeb/src/pages/band/` (band lookup by name). Service: `FSTService/Api/RankingsEndpoints.cs:755` (`/api/bands/search`), read-only since the #320 service fix ([service-safety.md](../../platforms/service-safety.md#endpoint-allowlist)). Band search by member name lives in global search's Bands scope ([global-search/ios.md](../../controls/global-search/ios.md), issue #320), not on this page.

- Implemented: a landing screen with no search field. Shows a "Your Bands" card linking to `AppRoute.playerBands` for the selected player (hidden with no profile selected), a "Band Rankings" card linking to `AppRoute.bandRankings` for each `BandType`, and an explanatory footnote. Typed band search is global search's Bands scope (issue #320).
- Simplified vs. web this pass: no name search field on this page (global search covers it), no recent-lookups list.
- IDs: `fst.bands.screen`, `fst.bands.your-bands`, `fst.bands.rankings.<bandType>`.
- Tests: no dedicated Core logic (this screen is static composition of existing routes); covered indirectly by `BandsTests.swift`'s `PlayerBandGroup`/`BandType` coverage. Hosted coverage: `BandsRenderTests.swift` (landing with/without a selected player) (Lane U4, 2026-09-28).
