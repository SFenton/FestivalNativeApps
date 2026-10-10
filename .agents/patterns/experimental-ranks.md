# Experimental ranks

> **What:** the Settings switch "Enable Experimental Leaderboard Ranks" and every place it gates: which ranking metrics Rank By offers (Adjusted, Weighted, FC Rate, Max Score beside Total Score), how saved, routed or selected experimental metrics fall back, and the other surfaces that hide experimental ranks while it is off. **Read when:** adding or changing a Rank By control, a per-metric rank tile, a rank notification, a ranking route parameter, a Rivals leaderboard scope or the Settings switch itself, on any platform.

Status: **current**, 2026-10-09. Provenance: #541 (the native toggle was disabled while every page offered all metrics; Android and Windows consolidated first, Apple in its own #541 session). Pages: [settings](../pages/settings/spec.md), [leaderboards](../pages/leaderboards/spec.md), [full-rankings](../pages/full-rankings/spec.md), [rivals](../pages/rivals/spec.md).

## Intent

Experimental ranking metrics are opt-in, app-wide, exactly like the web: the owner wants the switch "to control behavior app-wide like web" (#541). With the setting off (the default) the app ranks by Total Score only and never shows an experimental rank anywhere; turning it on adds the experimental metrics everywhere at once; turning it off again takes every open page back to Total Score. There is one stored flag and one coercion per metric family, and each consumer asks that gate. No page keeps its own list of allowed metrics or its own idea of the default.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/contexts/SettingsContext.tsx` (`enableExperimentalRanks`) | The setting, default `false`, cleared by Reset App Settings. |
| `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx`, `i18n/settings.en.json` | The toggle "Enable Experimental Leaderboard Ranks" / "Enable this to see more ranking mechanisms in the Leaderboards page.", after Filter Invalid Scores. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/rankingHelpers.ts` (`getEnabledRankingMetrics`, `coerceRankingMetric`) | Offered metrics: Total Score only when off, all five when on. Any unknown or disabled metric becomes `totalscore`. Used by Leaderboards, Full Rankings, Rivals, All Rivals and the Rank By modal. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/bandRankingHelpers.ts` (`coerceBandRankingMetric`) | Band boards: Total Score, Adjusted, Weighted, FC Rate (no Max Score, which narrows to Total Score); off coerces to Total Score. Used by Band Rankings and Band; the Band page shows `adjusted` when on and `totalscore` when off. |
| `FortniteFestivalWeb/src/pages/leaderboards/modals/RankByModal.tsx` and the Leaderboards / Full Rankings / Band Rankings / Rivals / All Rivals / Band pages | The Rank By control is hidden while the flag is off. A URL or saved experimental metric is read through the coercion. |
| `FortniteFestivalWeb/src/pages/player/sections/InstrumentStatsSection.tsx`, `OverallSummarySection.tsx` (`EXPERIMENTAL_METRICS`) | Player profile: one rank card per metric, the experimental ones only when on. |
| `FortniteFestivalWeb/src/components/notifications/notificationSurface.ts` (`projectExperimentalRankNotification`) | Notifications: an event with no rank metric passes through unchanged; while off, rows whose rank events are all experimental are hidden, and a mixed coalesced row is rebuilt from its first visible event. |

## Rules

1. **R1. Offered metrics.** Rank By offers `enabled(experimentalRanks)`: Total Score only while off, all metrics while on. While off the in-page and page-tool Rank By control (Leaderboards, Full Rankings, Band Rankings, Band Detail, Rivals' Leaderboard tab) is **hidden**, as on the web. Account boards offer Total Score, Adjusted, Weighted, FC Rate and Max Score while on; band boards offer Total Score, Adjusted, Weighted and FC Rate, and Band Detail defaults to Adjusted. Options appear in the web's order, Total Score first, from one explicit canonical list per platform (never an enum's declaration order); every band picker, including Band Detail, reads that list. A menu never lists metrics on its own (never `allCases` / `entries` for a user-facing choice). Exception: the Mac menu bar's **View › Rank By** keeps its submenu and lists only Total Score while off. HIG "The menu bar": "Disable, don't hide, unavailable items"; Menus: "Make sure a submenu remains available" (should). The menu bar is a fixed native surface, so its items don't come and go.
2. **R2. Coerce at read; never rewrite.** A saved preference, a route or deep link (`fullRankings:<chart>:<metric>`, a Rivals leaderboard scope) and a selection request are passed through the family's coercion (`coerce(…, experimentalRanks)`; bands also narrow Max Score) before they are used: a disabled or unknown metric becomes Total Score. A saved preference stays stored, so turning the setting back on restores it (web behavior). Selecting a disabled metric is ignored. A request, reload key or board identity always uses the **coerced** metric.
3. **R3. Turning it off resets open pages.** A page showing an experimental board switches to Total Score (Full Rankings back to page 1) as soon as the setting turns off, without showing a stale experimental board.
4. **R4. Gated surfaces.** The same setting gates the Rivals Leaderboard tab's Rank By (not persisted), the player profile's experimental rank tiles, experimental rank-change notifications (web projection, applied before rows are formatted, badged or counted unread; toggling re-projects loaded rows without a new read; Mark All Read marks only the shown rows) and the `leaderboards-experimental-metrics` first-run slide.
5. **R5. Settings switch.** A standard enabled platform switch with the web label and detail, after Filter Invalid Scores, off by default, saved like every other app setting in a single setting and turned off by Reset. It is never a disabled "not yet available" row.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Flag (R5) | `apple/Sources/FestivalCore/Rankings.swift` `ExperimentalRanks` (`fst.settings.experimentalRanks`); `SettingsScreen.experimentalRanksRow` | `SettingsScreen` `fst.settings.experimental-ranks`, `SettingsViewModel.setExperimentalRanks` | `Festival.Core/ViewModels/SettingsViewModel.cs` `ExperimentalRanks`, `Festival.App/Pages/SettingsPage.xaml` `fst.settings.experimental-ranks` |
| Gate (R1, R2) | `Rankings.swift` `RankingMetric.enabled(experimentalRanks:)` / `coerced`, `BandRankingMetric.enabled` / `coerced` / `bandDetailDefault`; `apple/Sources/FestivalCore/Rivals.swift` `RivalRankMetric.menuOrder` / `enabled` / `coerced`, `RivalScope.coerced` | `core/rankings/Rankings.kt` `RankingMetric.enabled`/`coerce`; `core/bands/BandTypes.kt` `BandRankingMetric.enabled`/`coerce`; `core/rivals/RivalsModels.kt` `RivalRankMetric.gated`, `core/rivals/RivalScope.kt` `RivalScopes.gated` | `Festival.Core/Domain/RankingMetrics.cs` `RankingMetricInfo.Enabled`/`Gate`/`Coerce(id, experimentalRanks)`; `Domain/BandTypes.cs` `BandRankingMetricInfo.Enabled`/`Gate`; `ViewModels/FestivalSession.Rivals.cs` `EffectiveRivalMetric`/`ResolveRivalScope` |
| Rank By control (R1) | `apple/Sources/FestivalUI/Features/Leaderboards/RankingsSupport.swift` `RankByMenu`, `BandRankByMenu`; `apple/Sources/FestivalUI/Mac/MacPageMenus.swift` `MacPageMenus.accountOptions` / `bandOptions` | `ui/leaderboards/RankingsComponents.kt` `RankByAction` (renders nothing while off; `tagPrefix` for Rivals) and `BandRankByAction` | Each page's Rank By `DropDownButton` / `ComboBox` binds `Visibility` to its view model's `ShowRankBy` and lists `MetricOptions` (`Enabled(…)`) |
| Notifications (R4) | `apple/Sources/FestivalCore/PlayerNotification.swift` `NotificationExperimentalRanks`; `NotificationsCenter.setExperimentalRanks` | `core/notifications/Notifications.kt` `NotificationRouting.projectExperimentalRanks` | `Festival.Core/Data/NotificationModels.cs` `NotificationRouting.ProjectExperimentalRanks` |

### Apple consumers

| Area | Consumers |
|---|---|
| Rank By pages | `LeaderboardsScreen`, `FullRankingsScreen`, `BandRankingsScreen`, `BandDetailScreen`. Each keeps the selected metric and computes a coerced `rankBy`. The toolbar menu and page tool are shown only while the flag is on. |
| Rivals | `RivalsScreen` hides the Rank By picker while the flag is off and lists `RivalRankMetric.menuOrder`. Its `tab:`/`rankBy:` opening state mirrors the web's `?tab=leaderboard&rankBy=` route and is coerced like any saved choice. `AllRivalsScreen`, `RivalDetailScreen` and `RivalryScreen` coerce their route scope. |
| Mac menu bar | `macRankByCommands(_:experimentalRanks:)` and the fallback in `FestivalCommands`. |
| Notifications | `NotificationsButton` and `NotificationsSheet` push the flag into the center. |
| First run | `FirstRunGate.experimentalRanksEnabled` gates the experimental-metrics slide. |

The Apple player-profile metric tiles are not ported: Apple shows only Total Score, which is the web's default while the flag is off.

Apple tests:

| Kind | Tests |
|---|---|
| Unit | `FestivalCoreTests/ExperimentalRanksTests` covers the default, the exact `menuOrder` lists (account, band, rival) in web order (Total Score first), coercion, band narrowing, rival scopes and the notification projection cases. |
| Hosted | `FestivalUITests/NotificationsCenterTests.notificationsCenterFollowsExperimentalRanksSwitch` checks the badge and the rows when the flag is off, on and off again. `MacKeyboardNavigationTests.macRankByAccountOptions` and `macRankByBandOptions` cover the menu-bar options. `FestivalUITests/ExperimentalRanksPagesHostedTests` hosts the real Leaderboards, Full Rankings, Band Rankings, Band Detail and Rivals pages (iPhone page-tool accessory path) against the loopback fixture: off, Rank By is absent and a saved or opening experimental metric requests `rankBy=totalscore`; on, the page tool lists the web-ordered choices with the routed metric selected; off again with an experimental board open, Rank By goes and the page reloads as Total Score. Rivals' SwiftUI `Menu` can't be opened in an offscreen host, so its test checks the control's name and requests and the core test checks its order. |
| Accessibility | `FestivalUITests/ExperimentalRanksAccessibilityTests` checks that the switch is enabled, named and off by default, follows the web reading order, and that pressing it saves the shared key. |

### Android consumers

Android paths are under `android/app/src/main/java/com/festivalscoretracker/android/`.

- Leaderboards overview and Full Rankings (`LeaderboardsViewModel`, `FullRankingsViewModel`: coerced saved/routed metric, `experimentalRanks` flow, reset to Total Score page 1 on off), Band Rankings (`BandRankingsViewModel`), Band Detail (`BandDetailViewModel`, `BandDetailScreen`).
- Rivals: `RivalsHubViewModel.rankByOptions`/`selectRankBy` (per-metric leaderboard lists), `RivalsNavigation` gates All Rivals and Rival Detail scopes.
- Player profile: `RankLoad.tiles(load, experimentalRanks)` (one tile per metric, web labels, each opening its metric's Full Rankings page).
- Notifications: `NotificationsViewModel(experimentalRanks = …)`.
- First run: `FirstRunCenter`/`FirstRunHost` already gate the experimental-metrics slide on `AppSettings.experimentalRanks`.
- Settings: `AppSettings.sanitized` no longer forces it off.

Android tests: `rankings/ExperimentalRanksTest` (gate and coercion), `RankingsViewModelTest` "Experimental Ranks (#541)" region (selection gate, deep-link fallback, reset on off for Full and Band Rankings), `BandsViewModelTest.detailRankByFollowsExperimentalRanks`, `RivalsViewModelTest.leaderboardRankByFollowsExperimentalRanks`, `NotificationsTest` "Experimental Ranks (#541)" region, `ProfileActionsTest.tilesCarryTheWebActions`, Robolectric `LeaderboardsUiTest.rankByWaitsForExperimentalRanks`/`bandRankingsHideRankByWithoutExperimentalRanks`, `BandsUiTest.bandDetailRankByWaitsForExperimentalRanks`, `SettingsUiTest.everySettingPersistsAndPropagates`, and the connected ATF journey `journeys/ExperimentalRanksAccessibilityJourneyTest` (switch role/state/48 dp at 1.0 and 2.0, Rank By absent from TalkBack while off and a full-size "Rank By, Total Score" control while on), and `journeys/ExperimentalRanksSurfacesAccessibilityJourneyTest` (`@DeviceCi`, ATF, review of #531) for the other R4 regions with the flag persisted off and on: the profile shows only the Total Score Rank tile while off; while on it shows all five rank tiles in metric order, each a labelled 48 dp `Button` at 1.0 and 2.0 text, and turning the flag off live drops the experimental tiles; Rivals' Leaderboard tab has no Rank By and requests only `rankBy=totalscore` while off, and while on it has one full-size "Rank By, Total Score" control that lists all five metrics and re-requests `rankBy=adjusted`; and the persisted flag excludes or includes the `leaderboards-experimental-metrics` first-run slide, which TalkBack reads. `journeys/BandFoldAccessibilityJourneyTest` (`@DeviceCi`, `@HalfOpenFoldJourney`) checks Band Detail both ways: with the setting on, Rank By is a labelled 48 dp button clear of the hinge; with it off, Rank By is absent from the page and TalkBack while Band Statistics stays a heading clear of the hinge (#563). Journeys that exercise Rank By launch with the setting on (`MemoryPreferences` with `SettingsRegistry.EXPERIMENTAL_RANKS` true: `BandRankingsJourneyTest`, `LoadSwapAccessibilityJourneyTest`, `BandFoldAccessibilityJourneyTest`); a default launch has no Rank By node, so a tag lookup throws an empty-list `NoSuchElementException` (#564 broke the required `android-fold` check and #563 the `android-device` check that way).

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
| Apple: the player-profile per-metric rank tiles are not ported (Total Score only) | none while off; R4 tiles while on | Port with the profile stat tiles |

## Guards (`tools/pattern_guard.py`)

- `experimental-ranks/android-metric-menus`
- `experimental-ranks/apple-ungated-metric-list`
- `experimental-ranks/windows-metric-menus`
