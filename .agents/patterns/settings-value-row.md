# Settings value row

> **What:** the read-only Settings row with a title on the leading side and a value or state on the trailing side: Version (App Version, Build, Service Version, Service) and the Service Info "Leaderboard Service State" row. It sits side by side when it fits and stacks the value under the title when it doesn't. **Read when:** adding or changing a read-only title/value row in Settings, or touching how Settings rows react to narrow windows and large text.

Status: **current**, 2026-10-06. Provenance: #121 (Android Version rows), #81/#22 (Service Info state row), #184 (consolidated on Android; agent decision).

## Intent

A Settings row that reports a value never squeezes its title into a sliver or clips the value. Whether a row stacks depends on whether it actually fits, not on a text-size threshold: a wide tablet column at the largest text keeps the value beside the title, and a half-open fold pane or a 360 dp cover stacks it even at default size.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx` (`versionRow`) | Version card rows: label start, value (`versionValue`, secondary text) end. |
| `FortniteFestivalWeb/src/pages/settings/SettingsServiceProgress.tsx` (`ServiceInfoRow`) | Service Info rows (`modalStyles.toggleRow`): label and description in a flexible column, the process state (`ProcessStateDisplay`, text plus spinner) as the trailing element. |

The web lets the browser's flex layout wrap; the natives make the same "never crush the title" outcome explicit with a measured fit rule.

## Rules

1. **R1. Inline only when it fits.** The value sits at the row's end, vertically centred, when the title's natural (unwrapped) width + a 12-unit gap + the value's natural width fit the row's content width. Otherwise the value stacks under the title (and its supporting text), start-aligned. Supporting text never counts toward the fit: it wraps under the title. Never decide by font scale or window class alone.
2. **R2. Metrics.** 12 dp/pt/epx inline gap; 4 between title, supporting text and a stacked value; Android rows are at least 48 dp tall (56 dp with supporting text) with 16 dp horizontal and 8 dp vertical padding. Title uses the body style in primary text; supporting text and a text value use secondary text.
3. **R3. One read-only item.** The row is one non-interactive accessibility item read title → supporting → value ("App Version, 2610.06.01 (…)", "Leaderboard Service State, Scraping Leaderboard Scores, Updating"). It has no click action and no role. Interactive trailing controls (a button, a switch) are not this pattern.
4. **R4. One component per platform.** Consumers pass the title, optional supporting text and the value (text or a composable state such as "Updating" with a spinner). They never write their own fit layout, gap or stacked spacing.
5. **R5. Not this pattern.** Navigation rows (Licenses, Privacy Policy), toggle rows, What's New and First Run rows with a trailing button, and the Service Info phase row (title + progress bar) are separate patterns or one-offs.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Fit rule and metrics (R1, R2) | `apple/Sources/FestivalUI/Features/Settings/SettingsServiceInfoSection.swift` `stateRow`; `apple/Sources/FestivalUI/Features/Settings/SettingsScreen.swift` `versionRow` | `android/app/src/main/java/com/festivalscoretracker/android/ui/settings/SettingsValueRow.kt` `SettingsValueRowMetrics` (`fitsInline`) | `windows/Festival.Core/Domain/SettingValueLayout.cs` `SettingValueLayout` (`ShouldStack`) |
| Row (R3, R4) | per row (see debt) | `SettingsValueRow` (text value overload; `supporting` + composable `trailing` overload) | `windows/Festival.App/Controls/SettingValueGrid.cs` `SettingValueGrid` (Version card) |

Android consumers: `SettingsScreen.kt` Version section (`fst.settings.build`, `service-version`, `service-origin`) and `AppVersionRow` (`fst.settings.app-version`); `ServiceInfoSection.kt` state row (`fst.settings.service-info.state`, the process state tagged `.process`). Tests: `settings/SettingsValueRowMetricsTest.kt` (fit rule and metrics), Robolectric `SettingsValueRowUiTest`, `LargeTextSettingsValueRowUiTest`, `AppVersionRowUiTest`, `ServiceInfoSectionUiTest` (inline at 1×, stacked at 2× on a phone and at 1× on a 260 dp pane, inline at 2× on an 808 dp column), connected `journeys/ServiceInfoJourneyTest` (fit/stack at font scale 1.0 and 2.0 on the device, reading order).

Agent decision (#184, owner may override with `/choose`): Android's Version rows and the Service Info state row were two hand-written `Layout`s with the same fit decision and gaps. They are now one `SettingsValueRow`. Options weighed: (a) keep two copies with shared constants (still two placements that can drift), (b) one parameterized row with optional supporting text and a composable trailing slot (chosen; matches the web's single `ServiceInfoRow` shape and Windows' single `SettingValueLayout` rule), (c) a font-scale threshold like Apple/Windows Service Info (rejected: it stacked wide tablet columns and squeezed half-open fold panes at 1.0).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `stateRow` stacks at accessibility text sizes and Windows `ServiceInfoText.StacksStateRow` at a text-scale threshold, instead of measuring the fit | R1, R4 | Apple and Windows checks (out of #184's Android scope): move the state row onto the platform's fit rule (`SettingValueLayout` on Windows) |
| Apple `versionRow` is a plain `HStack` + `Spacer` that never stacks | R1 | Apple check |
| `SettingValueLayout`'s doc comment still names the removed Android `ValueRow` | docs | Next Windows change in Settings: cite `SettingsValueRow` |

## Guards (`tools/pattern_guard.py`)

- `settings-value-row/android-parallel-fit`
