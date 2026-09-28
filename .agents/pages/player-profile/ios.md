# Player profile (`/player/:accountId`) — iPhone notes

> **What:** iPhone implementation state and decisions for the player-profile page, both viewed (someone else, or no selection) and selected ("this is me"). **Read when:** changing `Features/Profile/PlayerProfileContent.swift`, `PlayerProfileScreen.swift` or `Features/Statistics/StatisticsScreen.swift`. Behavior: [spec.md](spec.md) (currently a stub — this file is the source of truth for what's actually built until spec.md is promoted). Selection/session mechanics: [profile-selection/ios.md](../../controls/profile-selection/ios.md).

Source: `FortniteFestivalWeb/src/pages/leaderboard/player/components/PlayerContent.tsx`, `.../pages/player/PlayerPage.tsx`, `.../pages/player/sections/OverallSummarySection.tsx`, `.../sections/InstrumentStatsSection.tsx`, `.../components/player/StatBox.tsx`. `App.tsx:95-105` also points the `/statistics` route at `PlayerPage` for the tracked/selected account. Service: `FSTService/Api/PlayerEndpoints.cs:14-83,190-259` (`GET /api/player/{accountId}`, side-effect-free per `.agents/controls/profile-selection/spec.md`).

## Implemented

- One `PlayerProfileContent` view is shared by two routes: the pushed `AppRoute.player(accountId:displayName:)` (`PlayerProfileScreen`) and the Statistics tab root (`StatisticsScreen`, only reachable once a player is selected — `FestivalTabPolicy.sections(profile:)`). Both use the identical header, Overview section, per-instrument sections and states; Statistics always renders in the "This Is Me" state (its accountId is `session.selectedPlayer!.accountId`), with a defensive "no profile" `ContentUnavailableView` for the brief window between an explicit deselect and the tab bar hiding Statistics.
- Read: only `FestivalSession.viewPlayer(accountId:)` → the existing keyless, publication-aware `GET /api/player/{accountId}` (`FestivalAPI.playerProfile(accountId:)`, `FestivalCore/PlayerProfile.swift`). No selected-profile header, no tracking POST.
- Header: avatar monogram, display name (server `displayName` when available, else the route's or search result's), "This Is Me" vs "Public Profile" subtitle. Identity action is one of: Deselect (already selected), Select/Switch (viewed, response-proven, publication matches), or an honest "unverified"/"changed" notice (headerless or stale response) — same rule `ProfileSelectionSheet` already used for its old in-sheet preview (`payload.publicationId == session.publicationId`).
- Overview: one glass section, five stat tiles (Songs Played, Full Combos, Gold Stars, Avg Accuracy, Best Rank) computed **client-side** from the compact `scores` array across Settings-visible instruments only.
- One glass section per Settings-visible instrument (`fst.settings.show*`, read directly via `@AppStorage`, matching `FestivalRootView.visibleInstruments` — no new init parameter, no edit to the Shell): instrument icon + name, then Songs Played / Full Combos / Gold Stars / 5 Stars / Avg Accuracy / Best Rank, or an empty-state footnote when that instrument has no scores.
- Bands link (`NavigationLink` to `AppRoute.playerBands(accountId:displayName:)`, now owned by the Bands lane — `PlayerBandsScreen.swift` itself is untouched).
- Loading (`ProgressView`), syncing (202, reusing `ServiceUnavailableView` with manual Retry) and error (reusing `ServiceUnavailableView`, manual Retry) states, keyed on `accountId` + a retry counter + `session.publicationRevision` so a generation rollover re-fetches automatically.

## Client-side stats, not the player-stats GET

`PlayerOverallStats`/`PlayerInstrumentStats` (`FestivalCore/PlayerProfile.swift`) mirror the web's `computeOverallStats`/`computeInstrumentStats` (`pages/player/helpers/playerStats.ts`) exactly enough for songs played, full-combo count/percent (floored to one decimal, matching the source), gold-star count (`stars == 6`, since the wire's validated range is already 0...6), average accuracy and best rank — computed **only** from the same compact `scores` array the Songs tab already decodes. `.agents/controls/profile-selection/spec.md` documents the player-stats GET as **not unconditionally read-only** (it can compute and store missing tiers), so this page never calls it, and therefore has **no** per-instrument global rank, no percentile table and no rank-history chart — those need a separate mutation-free read policy before they can be native. This is the same kind of documented reduction as the existing Songs status-chip row.

`PlayerScore.accuracy`/`PlayerValidScoreVariant.accuracy` already decode into the exact scale `ScoreFormatting.accuracy(_:)`/`accuracyTint(_:)` expect (compact wire `acc` × 1,000 = the leaderboard's ten-thousandths-of-a-percent unit) — no extra rescale needed; an earlier draft of this page added one, which was wrong and has been removed.

## Simplified vs. web this pass

No family/global statistics cards (`OverallSummarySection`'s `pad`/`pro_strings`/`pro_drums` scopes — needs per-instrument ranks), no rank-history chart, no percentile table, no band/member card, no first-run carousel. Stat tiles are flat (non-interactive) — the web's tap-to-filter-Songs actions would need writing into `SongPlayerScoreFilter`/Songs `@AppStorage` state, which belongs to the Songs lane; not done here to avoid a cross-lane write. "Best Rank" has no tap target for the same reason it can't deep-link to `.songLeaderboard` — that route needs a full `Song` value this page never fetches (no catalog cross-reference).

## IDs

`fst.player.loading`, `fst.player.syncing`, `fst.player.error`, `fst.player.available`, `fst.player.name`, `fst.player.deselect`, `fst.player.unverified`, `fst.player.preview-changed`, `fst.player.select`, `fst.player.action-error`, `fst.player.overview`, `fst.player.instrument.<Instrument rawValue>`, `fst.player.instrument-empty.<Instrument rawValue>`, `fst.player.bands-link`. (`fst.player.*` is pre-registered to this page in `contracts/product.json`.)

## Tests

`PlayerProfileTests.swift` (Core) adds `overallStatsAggregatesAcrossVisibleInstrumentsOnly` and `instrumentStatsIsolatesOneChartAndReportsAnEmptyState`, covering visible-instrument filtering, unique-song counting across instruments, the floored full-combo percent, gold-star threshold and empty-instrument zeroing. No hosted-UI/XCUITest coverage yet (Wave 1 phase — unit + visual smoke only, per `PROGRESS.md` §3). Visual smoke: `python3 tools/ios_sim.py drive` search → view → select flow (see [profile-selection/ios.md](../../controls/profile-selection/ios.md) for the exact script and screenshots).
