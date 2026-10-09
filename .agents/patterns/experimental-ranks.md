# Experimental ranks

> **What:** the Settings switch "Enable Experimental Leaderboard Ranks" and every place it gates: which ranking metrics Rank By offers (Adjusted, Weighted, FC Rate, Max Score beside Total Score), how saved, routed or selected experimental metrics fall back, and the other surfaces that hide experimental ranks while it is off. **Read when:** adding or changing a Rank By control, a per-metric rank tile, a rank notification, a ranking route parameter or the Settings switch itself.

Status: **current**, 2026-10-08. Provenance: #541 (the native toggle was disabled while every page offered all metrics; Android consolidated first, Apple and Windows in their own #541 sessions).

## Intent

Experimental ranking metrics are opt-in, app-wide, exactly like the web. With the setting off (the default) the app ranks by Total Score only and never shows an experimental rank anywhere; turning it on adds the experimental metrics everywhere at once; turning it off again takes every open page back to Total Score.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/contexts/SettingsContext.tsx` (`enableExperimentalRanks`) | The setting, default `false`, cleared by Reset. `SettingsPage.tsx` shows it as the toggle "Enable Experimental Leaderboard Ranks". |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/rankingHelpers.ts` (`getEnabledRankingMetrics`, `coerceRankingMetric`) | Offered metrics: Total Score only when off, all five when on. Any unknown or disabled metric becomes `totalscore`. Used by Leaderboards, Full Rankings, Rivals, All Rivals and the Rank By modal. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/bandRankingHelpers.ts` (`coerceBandRankingMetric`) | Band boards: Total Score, Adjusted, Weighted, FC Rate (no Max Score); off coerces to Total Score. Used by Band Rankings and Band. |
| `FortniteFestivalWeb/src/pages/player/sections/InstrumentStatsSection.tsx` (`EXPERIMENTAL_METRICS`) | Player profile: one rank card per metric, the experimental ones only when on. |
| `FortniteFestivalWeb/src/components/notifications/notificationSurface.ts` (`projectExperimentalRankNotification`) | Notifications: while off, rows whose rank events are all experimental are hidden, and a mixed coalesced row keeps only its other events. |

## Rules

1. **R1. Offered metrics.** Rank By offers `enabled(experimentalRanks)`: Total Score only while off (the Rank By control is then **hidden**, as on the web), all metrics while on. Band boards offer Total Score, Adjusted, Weighted and FC Rate while on. A menu never lists metrics on its own.
2. **R2. Coerce at read.** A saved preference, a route or deep link (`fullRankings:<chart>:<metric>`, a Rivals leaderboard scope) and a selection request are passed through `coerce(…, experimentalRanks)` before they are used: a disabled or unknown metric becomes Total Score. A saved preference stays stored, so turning the setting back on restores it (web behavior). Selecting a disabled metric is ignored.
3. **R3. Turning it off resets open pages.** A page showing an experimental board switches to Total Score (Full Rankings back to page 1) as soon as the setting turns off, without showing a stale experimental board.
4. **R4. Gated surfaces.** The same setting gates the Rivals Leaderboard tab's Rank By (not persisted), the player profile's experimental rank tiles, experimental rank-change notifications (web projection; Mark All Read marks only the shown rows) and the experimental-metrics first-run slide.
5. **R5. Settings switch.** A standard enabled platform switch, off by default, saved like every other app setting and turned off by Reset.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Gate (R1, R2) | pending (#541 Apple session) | `core/rankings/Rankings.kt` `RankingMetric.enabled`/`coerce`; `core/bands/BandTypes.kt` `BandRankingMetric.enabled`/`coerce`; `core/rivals/RivalsModels.kt` `RivalRankMetric.gated`, `core/rivals/RivalScope.kt` `RivalScopes.gated` | pending (#541 Windows session) |
| Rank By control (R1) | pending | `ui/leaderboards/RankingsComponents.kt` `RankByAction` (renders nothing while off; `tagPrefix` for Rivals) and `BandRankByAction` | pending |
| Notifications (R4) | pending | `core/notifications/Notifications.kt` `NotificationRouting.projectExperimentalRanks` | pending |

Android paths are under `android/app/src/main/java/com/festivalscoretracker/android/`. Android consumers:

- Leaderboards overview and Full Rankings (`LeaderboardsViewModel`, `FullRankingsViewModel`: coerced saved/routed metric, `experimentalRanks` flow, reset to Total Score page 1 on off), Band Rankings (`BandRankingsViewModel`), Band Detail (`BandDetailViewModel`, `BandDetailScreen`).
- Rivals: `RivalsHubViewModel.rankByOptions`/`selectRankBy` (per-metric leaderboard lists), `RivalsNavigation` gates All Rivals and Rival Detail scopes.
- Player profile: `RankLoad.tiles(load, experimentalRanks)` (one tile per metric, web labels, each opening its metric's Full Rankings page).
- Notifications: `NotificationsViewModel(experimentalRanks = …)`.
- First run: `FirstRunCenter`/`FirstRunHost` already gate the experimental-metrics slide on `AppSettings.experimentalRanks`.
- Settings: `SettingsScreen` `fst.settings.experimental-ranks`, `SettingsViewModel.setExperimentalRanks`; `AppSettings.sanitized` no longer forces it off.

Android tests: `rankings/ExperimentalRanksTest` (gate and coercion), `RankingsViewModelTest` "Experimental Ranks (#541)" region (selection gate, deep-link fallback, reset on off for Full and Band Rankings), `BandsViewModelTest.detailRankByFollowsExperimentalRanks`, `RivalsViewModelTest.leaderboardRankByFollowsExperimentalRanks`, `NotificationsTest` "Experimental Ranks (#541)" region, `ProfileActionsTest.tilesCarryTheWebActions`, Robolectric `LeaderboardsUiTest.rankByWaitsForExperimentalRanks`/`bandRankingsHideRankByWithoutExperimentalRanks`, `BandsUiTest.bandDetailRankByWaitsForExperimentalRanks`, `SettingsUiTest.everySettingPersistsAndPropagates`, and the connected ATF journey `journeys/ExperimentalRanksAccessibilityJourneyTest` (switch role/state/48 dp at 1.0 and 2.0, Rank By absent from TalkBack while off and a full-size "Rank By, Total Score" control while on). Journeys that exercise Rank By launch with the setting on.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple: the Settings row is disabled ("Not yet available") and Leaderboards, Full Rankings, Band Rankings and Mac menus offer every metric | R1–R5 | #541 Apple session |
| Windows: Settings sanitizes the toggle off and disables it; Leaderboards and Band Rankings offer every metric | R1–R5 | #541 Windows session |

## Guards (`tools/pattern_guard.py`)

- `experimental-ranks/android-metric-menus`
