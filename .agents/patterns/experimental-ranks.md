# Experimental ranks

> **What:** the Settings **Enable Experimental Leaderboard Ranks** switch and the one gate it drives. While the switch is off (the default), every ranking surface uses Total Score only. While it is on, they also offer Adjusted, Weighted, FC Rate and Max Score. **Read when:** adding or changing a Rank By control, a rank-metric route or saved choice, a Rivals leaderboard scope, a notification that carries a rank metric, or the Settings switch itself, on any platform.

Status: **current**, 2026-10-09. Provenance: #541 (the Apple switch was hard-disabled while every page offered all five metrics). Pages: [settings](../pages/settings/spec.md), [leaderboards](../pages/leaderboards/spec.md), [full-rankings](../pages/full-rankings/spec.md), [rivals](../pages/rivals/spec.md).

## Intent

The owner wants the switch "to control behavior app-wide like web" (#541). There is one stored flag and one coercion per metric family, and each consumer asks that gate. No page keeps its own list of "allowed" metrics or its own idea of the default.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/contexts/SettingsContext.tsx` (`enableExperimentalRanks`) | The flag. It defaults to `false`, and Reset App Settings restores it. |
| `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx`, `i18n/settings.en.json` | The toggle "Enable Experimental Leaderboard Ranks" / "Enable this to see more ranking mechanisms in the Leaderboards page.", after Filter Invalid Scores. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/rankingHelpers.ts` (`getEnabledRankingMetrics`, `coerceRankingMetric`) | Off means `['totalscore']` only, and any other metric is coerced to `totalscore`. |
| `FortniteFestivalWeb/src/pages/leaderboards/helpers/bandRankingHelpers.ts` (`coerceBandRankingMetric`) | Bands coerce the same way, and Max Score narrows to Total Score. |
| `FortniteFestivalWeb/src/pages/leaderboards/modals/RankByModal.tsx`, the Leaderboards / Full Rankings / Band Rankings / Rivals / All Rivals / Band pages | The Rank By control is hidden while the flag is off. A URL or saved experimental metric is read through the coercion. The Band page shows `adjusted` when the flag is on and `totalscore` when it is off. |
| `FortniteFestivalWeb/src/components/notifications/notificationSurface.ts` (`projectExperimentalRankNotification`) | The notification projection. An event with no rank metric passes through unchanged. When every event is experimental, the notification is dropped. Otherwise the notification is rebuilt from the first visible event. |
| `FortniteFestivalWeb/src/pages/player/sections/InstrumentStatsSection.tsx`, `OverallSummarySection.tsx` (`EXPERIMENTAL_METRICS`) | Experimental metric tiles are shown only while the flag is on. |

## Rules

1. **R1. One flag, off by default.** It is stored in a single setting (Apple `fst.settings.experimentalRanks`, `ExperimentalRanks.storageKey`), defaults to off, and Reset App Settings turns it off. The Settings row is an ordinary enabled platform switch, using the web label and detail, placed after Filter Invalid Scores. It is never a disabled "not yet available" row.
2. **R2. One gate per metric family.** Every consumer reads the metric through the gate:
   - Account boards: `RankingMetric.enabled` / `coerced`.
   - Bands: `BandRankingMetric`, which also narrows Max Score to Total Score.
   - Rivals leaderboard scopes: `RivalRankMetric` / `RivalScope.coerced`.

   A page never lists `allCases` for a user-facing choice, and never keeps its own list of allowed metrics.
3. **R3. Coerce when reading; never rewrite.** A saved choice, deep link or route that names an experimental metric renders as Total Score while the flag is off. The stored value is left in place, so switching the flag back on restores the earlier choice, as the web's URL parameter does. A request, reload key or board identity always uses the **coerced** metric. Turning the flag off therefore reloads every open page to Total Score and leaves no stale experimental board behind.
4. **R4. Off hides the in-page control.** With the flag off, the in-page and page-tool Rank By (Leaderboards, Full Rankings, Band Rankings, Band Detail, Rivals' Leaderboard tab) is withdrawn, as on the web. The Mac menu bar's **View › Rank By** keeps its submenu, listing only Total Score: HIG "The menu bar": "Disable, don't hide, unavailable items" and Menus: "Make sure a submenu remains available" (should). The menu bar is a fixed native surface, so its items don't come and go.
5. **R5. On offers the web's metrics.** With the flag on, account boards offer Total Score, Adjusted, Weighted, FC Rate and Max Score. Bands offer Total Score, Adjusted, Weighted and FC Rate. The Band Detail default is Adjusted.
6. **R6. Notifications project, never leak.** Rank notifications pass through the web projection before they are formatted, badged or counted unread. A notification whose events are all experimental is dropped while the flag is off. A mixed one is rebuilt from its first visible event. Toggling the flag re-projects the loaded rows without a new read.
7. **R7. First-run follows the flag.** The `leaderboards-experimental-metrics` slide appears only while the flag is on (`FirstRunGate.experimentalRanksEnabled`).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows | Web |
|---|---|---|---|---|
| Flag (R1) | `apple/Sources/FestivalCore/Rankings.swift` `ExperimentalRanks`; Settings `SettingsScreen.experimentalRanksRow` | Not yet (see Known debt) | Not yet (see Known debt) | `contexts/SettingsContext.tsx` |
| Gate (R2, R3, R5) | `Rankings.swift` `RankingMetric.enabled(experimentalRanks:)` / `coerced`, `BandRankingMetric.enabled` / `coerced` / `bandDetailDefault`; `apple/Sources/FestivalCore/Rivals.swift` `RivalRankMetric.enabled` / `coerced`, `RivalScope.coerced` | — | — | `rankingHelpers.ts`, `bandRankingHelpers.ts` |
| Rank By UI (R4) | `apple/Sources/FestivalUI/Features/Leaderboards/RankingsSupport.swift` `RankByMenu`, `BandRankByMenu`; `apple/Sources/FestivalUI/Mac/MacPageMenus.swift` `MacPageMenus.accountOptions` / `bandOptions` | — | — | `RankByModal.tsx` |
| Notifications (R6) | `apple/Sources/FestivalCore/PlayerNotification.swift` `NotificationExperimentalRanks`; `NotificationsCenter.setExperimentalRanks` | — | — | `notificationSurface.ts` |

### Apple consumers

| Area | Consumers |
|---|---|
| Rank By pages | `LeaderboardsScreen`, `FullRankingsScreen`, `BandRankingsScreen`, `BandDetailScreen`. Each keeps the selected metric and computes a coerced `rankBy`. The toolbar menu and page tool are shown only while the flag is on. |
| Rivals | `RivalsScreen` hides the Rank By picker while the flag is off. `AllRivalsScreen`, `RivalDetailScreen` and `RivalryScreen` coerce their route scope. |
| Mac menu bar | `macRankByCommands(_:experimentalRanks:)` and the fallback in `FestivalCommands`. |
| Notifications | `NotificationsButton` and `NotificationsSheet` push the flag into the center. |

The player-profile metric tiles are not ported: Apple shows only Total Score, which is the web's default while the flag is off.

### Apple tests

| Kind | Tests |
|---|---|
| Unit | `FestivalCoreTests/ExperimentalRanksTests` covers the default, the enabled lists, coercion, band narrowing, rival scopes and the notification projection cases. |
| Hosted | `FestivalUITests/NotificationsCenterTests.notificationsCenterFollowsExperimentalRanksSwitch` checks the badge and the rows when the flag is off, on and off again. `MacKeyboardNavigationTests.macRankByAccountOptions` and `macRankByBandOptions` cover the menu-bar options. |
| Accessibility | `FestivalUITests/ExperimentalRanksAccessibilityTests` checks that the switch is enabled, named and off by default, follows the web reading order, and that pressing it saves the shared key. |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android: Settings sanitizes the switch off and disables it, while Leaderboards and Band Rankings offer all metrics (Android [leaderboards](../pages/leaderboards/android.md)) | R1–R6 on Android | Android lane: port the gate (#541 `verify_surfaces`) |
| Windows: Settings keeps the toggle disabled, while the Leaderboards, Full Rankings and Band Rankings flyouts offer all metrics (Windows [leaderboards](../pages/leaderboards/windows.md)) | R1–R6 on Windows | Windows lane: port the gate (#541 `verify_surfaces`) |

## Guards (`tools/pattern_guard.py`)

- `experimental-ranks/apple-ungated-metric-list`
