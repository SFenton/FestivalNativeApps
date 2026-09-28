# compete (`/compete`) — iPhone notes

> **What:** iPhone implementation state and decisions for the Compete phone hub. **Read when:** changing this page on iPhone. Behavior: [spec.md](spec.md) (stub — this file is the source of truth for what's actually built until spec.md is promoted).

Source: `FortniteFestivalWeb/src/pages/compete/CompetePage.tsx`. This is the phone tab shown once a player is selected (`FestivalSection.compete`, wired up by Lane A's `FestivalRootView`); `CompeteScreen` receives `festivalRootChrome` from `FestivalRootView.tabStack(_:)` externally and must not apply it again itself.

- Implemented: `CompeteScreen` (`Features/Compete/CompeteScreen.swift`) with two `FestivalSectionHeader` groups:
  - **Leaderboards** — one `FestivalGlassSection` row per Settings-visible instrument (icon + label) plus an "Leaderboards Overview" row, all pushing straight to `AppRoute.fullRankings(instrument:rankBy: "totalscore")` / `.leaderboards`.
  - **Rivals** — reuses `RivalInstrumentSongSection` from `Features/Rivals/RivalsScreen.swift` verbatim (same live per-instrument rivals preview, "View All Rivals" push, empty-section hiding) for every Settings-visible instrument.
  No player selected → `RivalsChooseProfileState`.
- Simplified vs. web this pass, and why: the web's Leaderboards section shows live Top-10 rows plus the player's own rank per ranking scope (`getRankings`/`getComboRankings`/`getPlayerRanking`/`getPlayerComboRanking`). Building that here would mean adding a rankings-preview Core API, but `Features/Leaderboards` and its rankings domain are Lane L's ownership (per `PROGRESS.md`) and duplicating that Core surface from this lane would conflict with Lane L's own (now-landed) rankings API. Until Compete's Leaderboards section is wired to that shared API, it stays navigation-only (real routes, no fabricated numbers) rather than either blocking on Lane L or building a second, divergent rankings client. The web's settings-derived multi-instrument "combo" ranking scopes (`resolveSupportedRankingScopes`) are also not built — only single-instrument scopes.
- IDs: reuses `RivalRowContent`'s combined accessibility label; no additional identifiers beyond the Rivals hub's.
- Tests: covered indirectly by `RivalsTests.swift` (shared Core models/endpoints) since this screen has no Compete-specific Core logic of its own. `tools/ios_sim.py shot --tab compete` verified against the live public service (2026-09-28).
