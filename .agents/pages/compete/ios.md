# compete (`/compete`) — iPhone notes

> **What:** iPhone implementation state and decisions for the Compete phone hub. **Read when:** changing this page on iPhone. Behavior: [spec.md](spec.md) (stub — this file is the source of truth for what's actually built until spec.md is promoted).

Source: `FortniteFestivalWeb/src/pages/compete/CompetePage.tsx`. This is the phone tab shown once a player is selected (`FestivalSection.compete`, wired up by Lane A's `FestivalRootView`); `CompeteScreen` receives `festivalRootChrome` from `FestivalRootView.tabStack(_:)` externally and must not apply it again itself.

- Implemented: `CompeteScreen` (`Features/Compete/CompeteScreen.swift`) with two `FestivalSectionHeader` groups:
  - **Leaderboards** — a "Leaderboards Overview" row (→ `AppRoute.leaderboards`), then `CompeteInstrumentLeaderboardSection` per Settings-visible instrument: a live Top-5 `totalscore` preview via `session.rankings(instrument:rankBy:page:pageSize:)`, reusing Lane L's `AccountRankingRow`/`RankingsSkeletonRows`/`RankLoadState` (`Features/Leaderboards/RankingsSupport.swift`) so the cards render identically to `LeaderboardsScreen`'s own overview cards. "View Full Leaderboard" pushes `AppRoute.fullRankings(instrument:rankBy: "totalscore")`.
  - **Rivals** — reuses `RivalInstrumentSongSection` from `Features/Rivals/RivalsScreen.swift` verbatim (same live per-instrument rivals preview, "View All Rivals" push, empty-section hiding) for every Settings-visible instrument.
  No player selected → `RivalsChooseProfileState`.
- Simplified vs. web this pass: no "your rank" spotlight row when the player is outside the Top 5 (the web's `getPlayerRanking`/`getPlayerComboRanking`; `LeaderboardsScreen` itself has the same simplification today — see its own `ios.md`), no settings-derived multi-instrument "combo" ranking scopes (`resolveSupportedRankingScopes`), only single-instrument scopes. `CompeteInstrumentLeaderboardSection` reuses Lane L's *components* (read-only) but is this lane's own file/type — no edits to `Features/Leaderboards/**`.
- IDs: `fst.compete.leaderboard-card.<instrument>`; rival rows reuse `RivalRowContent`'s combined accessibility label with no additional identifiers.
- Tests: covered indirectly by `RivalsTests.swift` (Rivals Core models/endpoints) and Lane L's `RankingsTests.swift` (Rankings Core models/endpoints), since this screen has no Compete-specific Core logic of its own. `tools/ios_sim.py shot`/`drive --tab compete` verified real Top-5 rows and rival previews against the live public service (2026-09-28).
