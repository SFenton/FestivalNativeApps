# Experimental ranks

> **What:** the Settings switch "Enable Experimental Leaderboard Ranks" and every place it gates: which ranking metrics Rank By offers (Adjusted, Weighted, FC Rate, Max Score beside Total Score), how saved, routed or selected experimental metrics fall back, and the other surfaces that hide experimental ranks while it is off. **Read when:** adding or changing a Rank By control, a per-metric rank tile, a rank notification, a ranking route parameter or the Settings switch itself.

Status: **current**, 2026-10-08. Provenance: #541 (the native toggle was disabled while every page offered all metrics; each platform is fixed in its own #541 session).

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
| Gate (R1, R2) | pending (#541 Apple session) | pending (#541 Android session) | `Festival.Core/Domain/RankingMetrics.cs` `RankingMetricInfo.Enabled`/`Gate`/`Coerce(id, experimentalRanks)`; `Domain/BandTypes.cs` `BandRankingMetricInfo.Enabled`/`Gate`; `ViewModels/FestivalSession.Rivals.cs` `EffectiveRivalMetric`/`ResolveRivalScope` |
| Rank By control (R1) | pending | pending (#541 Android session) | Each page's Rank By `DropDownButton` / `ComboBox` binds `Visibility` to its view model's `ShowRankBy` and lists `MetricOptions` (`Enabled(…)`) |
| Notifications (R4) | pending | pending (#541 Android session) | `Festival.Core/Data/NotificationModels.cs` `NotificationRouting.ProjectExperimentalRanks` |

Windows paths are under `windows/`. Windows consumers:

- Leaderboards overview (`LeaderboardsViewModel`: `ShowRankBy`, gated `MetricOptions`/`SelectMetricAsync`, `SyncRankBy` on activation and on every Settings change reloads at Total Score; the saved `LeaderboardRankBy` stays stored), Full Rankings and Band Rankings (`LeaderboardsFullRankingsViewModel.cs`, both models keep the routed `requestedMetric`, gate it on load and `SyncExperimentalRanks()` reloads page 1 when the gate changes; the pages await it in `OnNavigatedTo`), Band Detail (`BandsDetailViewModel.ShowRankBy`, gated `MetricIndex`).
- Rivals: the hub's `ShowMetricPicker` and `FestivalSession.EffectiveRivalMetric`; All Rivals and Rival Detail scopes through `ResolveRivalScope` (`RivalDetailViewModels.cs`).
- Notifications: `NotificationsViewModel.Apply` projects each row and re-applies when the setting changes (hidden rows are not counted as unread).
- First run: `FirstRunGate.ExperimentalRanksEnabled` already gates the experimental-metrics slide.
- Settings: `SettingsPage.xaml` `fst.settings.experimental-ranks` (Fluent `ToggleSwitch`, TwoWay), `SettingsViewModel.ExperimentalRanks`; `AppSettings.Sanitized` no longer forces it off and `ResetAppSettings` turns it off.
- Player profile: no per-metric rank tiles on Windows yet (player stats is blocked), so nothing to gate.

Windows tests: Core `ExperimentalRanksTests` (gate, Settings default/persist/Reset, overview hide and saved-metric fallback, toggle reload without a stale board, Full Rankings deep-link fallback and restore, Band Rankings), `NotificationsTests` "Experimental Ranks" region, `BandsViewModelTests.RankByNeedsExperimentalRanks`, `RivalsViewModelTests.Session_ResolvesRivalScopeAgainstExperimentalRanks`, `SettingsModelsTests`/`SettingsPageTests`; accessibility journey `tools/windows/journeys/a11y-experimental-ranks.json` (`ui_ci.py` `experimental-ranks` and `-text-225`: switch name, enabled, off by default, Space toggles it, 40 epx "Rank by: Total Score, button" while on and gone after turning it off; no Rank By on Leaderboards, Full Rankings or Band Rankings with a saved or deep-linked experimental metric), `notifications_journey.py experimental-ranks-off` and `leaderboards_journey.py rank-by-off`. Journeys and matrix pages that exercise Rank By or the FC Rate rank notification seed `"settings": {"experimentalRanks": true}`.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android: Settings sanitizes the switch off and disables it; Leaderboards, Full Rankings and Band Rankings offer every metric | R1–R5 | #541 Android session |
| Apple: the Settings row is disabled ("Not yet available") and Leaderboards, Full Rankings, Band Rankings and Mac menus offer every metric | R1–R5 | #541 Apple session |

## Guards (`tools/pattern_guard.py`)

- `experimental-ranks/windows-metric-menus`
