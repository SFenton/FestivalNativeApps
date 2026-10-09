# Settings value row

> **What:** the read-only Settings row with a title on the leading side and a value or state on the trailing side: Version (App Version, Build, Service Version, Service) and the Service Info "Leaderboard Service State" row. It sits side by side when it fits and stacks the value under the title when it doesn't. **Read when:** adding or changing a read-only title/value row in Settings, or touching how Settings rows react to narrow windows and large text.

Status: **current**, 2026-10-06. Provenance: #121 (Android Version rows), #81/#22 (Service Info state row), #184 (consolidated on Android; agent decision), #387 (consolidated on Apple).

## Intent

A Settings row that reports a value never squeezes its title into a sliver or clips the value. Whether a row stacks depends on whether it actually fits, not on a text-size threshold: a wide tablet column at the largest text keeps the value beside the title, and a half-open fold pane or a 360 dp cover stacks it even at default size.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/settings/SettingsVersionList.tsx` (`SettingsVersionList`) | Version card rows as a description list (`<dt>` label start, `<dd>` value end in secondary text); the row is a wrapping flex row, so the value drops under the label when both don't fit, and assistive technology ties each value to its label. |
| `FortniteFestivalWeb/src/pages/settings/SettingsServiceProgress.tsx` (`ServiceInfoRow`) | Service Info rows (`modalStyles.toggleRow`): label and description in a flexible column, the process state (`ProcessStateDisplay`, text plus spinner) as the trailing element. |

The web lets the browser's flex layout wrap; the natives make the same "never crush the title" outcome explicit with a measured fit rule.

## Rules

1. **R1. Inline only when it fits.** The value sits at the row's end, vertically centred, when the title's natural (unwrapped) width + a 12-unit gap + the value's natural width fit the row's content width. Otherwise the value stacks under the title (and its supporting text), start-aligned. Supporting text never counts toward the fit: it wraps under the title. Never decide by font scale or window class alone.
2. **R2. Metrics.** 12 dp/pt/epx inline gap; 4 between title, supporting text and a stacked value; Android rows are at least 48 dp tall (56 dp with supporting text) with 16 dp horizontal and 8 dp vertical padding. Title uses the body style in primary text; supporting text and a text value use secondary text.
3. **R3. One read-only item.** The row is one non-interactive accessibility item read title → supporting → value ("App Version, 2610.06.01 (…)", "Leaderboard Service State, Scraping Leaderboard Scores, Updating"). It has no click action and no role. Interactive trailing controls (a button, a switch) are not this pattern.
4. **R4. One component per platform.** Consumers pass the title, optional supporting text and the value (text or a composable state such as "Updating" with a spinner). They never write their own fit layout, gap or stacked spacing.
5. **R5. Not this pattern.** Navigation rows (Licenses, Privacy Policy), toggle rows, What's New and First Run rows with a trailing button, and the Service Info phase row (title + progress bar) are separate patterns or one-offs. The Service Info phase row still follows R3's accessibility shape: one static-text item, title as label, spoken progress as value (Apple issue #399).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Fit rule and metrics (R1, R2) | `apple/Sources/FestivalUI/Features/Settings/SettingsValueRow.swift` `SettingsValueRowLayout` (`fitsInline`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/settings/SettingsValueRow.kt` `SettingsValueRowMetrics` (`fitsInline`) | `windows/Festival.Core/Domain/SettingValueLayout.cs` `SettingValueLayout` (`ShouldStack`) |
| Row (R3, R4) | `SettingsValueRow` (text value init; `detail` + `@ViewBuilder` value init), `SettingsAppVersionRow` | `SettingsValueRow` (text value overload; `supporting` + composable `trailing` overload) | `windows/Festival.App/Controls/SettingValueGrid.cs` `SettingValueGrid` (Version card) |

Android consumers: `SettingsScreen.kt` Version section (`fst.settings.build`, `service-version`, `service-origin`) and `AppVersionRow` (`fst.settings.app-version`); `ServiceInfoSection.kt` state row (`fst.settings.service-info.state`, the process state tagged `.process`). Tests: `settings/SettingsValueRowMetricsTest.kt` (fit rule and metrics), Robolectric `SettingsValueRowUiTest`, `LargeTextSettingsValueRowUiTest`, `AppVersionRowUiTest`, `ServiceInfoSectionUiTest` (inline at 1×, stacked at 2× on a phone and at 1× on a 260 dp pane, inline at 2× on an 808 dp column), connected `journeys/ServiceInfoJourneyTest` (fit/stack at font scale 1.0 and 2.0 on the device, reading order) and `journeys/SettingsVersionAccessibilityJourneyTest` (App Version stamped and unstamped at 1.0 and 2.0: one read-only item, 48 dp minimum, unclipped value, Version card reading order; ATF). Both run in the `android-device` pull-request check (`.github/workflows/android-device.yml`, `:app:connectedDebugAndroidTest`).

Windows consumer: the Settings Version card (`fst.settings.app-version`, `fst.settings.service-version`). Tests: `Festival.Core.Tests/SettingValueLayoutTests.cs` (fit rule) and the live UIA matrix pages in `tools/windows/journeys/a11y-settings-version.json`, split by R1 outcome at compact (issue #413): `settings-version-large-text` (text 150/200%) asserts App Version is level with and apart from its label, and `settings-version-stacked` (text 225%) asserts the value is below its label with Build Configuration below the value. A Windows large-text page must assert the R1 outcome it expects (`assertlevel` inline, `assertbelow` stacked), not only non-overlap: the pre-#243 two-column Grid kept the value inline at 225% and still never overlapped, while clipping `Build Configuration`. `tools/windows/tests/test_settings_journeys.py` pins both pages.
Apple consumers (issue #387): `SettingsScreen` Version section (`fst.settings.app-version`, `fst.settings.build`, `fst.settings.service-version`, the same IDs as Android) and `SettingsServiceInfoSection.stateRow` (`fst.settings.service-info.state`); iPhone, iPad/Duo topic pages and the Mac Settings window share them. The row is `.accessibilityElement(children: .ignore)` + `.isStaticText` with label = title (", supporting") and value = the spoken value: without the static-text trait the Mac tree reports an unknown role and drops the value. App Version's spoken value names its parts (`AppBuildInfo.spokenVersionText`: "2610.08.01, build 42, commit 42edc57") instead of the printed parentheses and `·`. Tests: hosted `SettingsVersionRowAccessibilityTests` (one `AXStaticText` per row with label/value, Version reading order App Version → Build Configuration → Service Version → What's New, inline at 370 pt, stacked and wrapped at 220/150/110 pt, `fitsInline` boundary, state row), `SettingsServiceInfoAccessibilityTests` (the whole Service Info card: state, phase and publication rows, loading/failed, reading order, narrow-column wrap), `FestivalCoreTests/AppBuildInfoTests` (`spokenVersion`). macOS hosting does not scale Dynamic Type, so the tests narrow the column instead; the rule is width-based, so it is the same decision AX5 makes on an iPhone.

Agent decision (#184, owner may override with `/choose`): Android's Version rows and the Service Info state row were two hand-written `Layout`s with the same fit decision and gaps. They are now one `SettingsValueRow`. Options weighed: (a) keep two copies with shared constants (still two placements that can drift), (b) one parameterized row with optional supporting text and a composable trailing slot (chosen; matches the web's single `ServiceInfoRow` shape and Windows' single `SettingValueLayout` rule), (c) a font-scale threshold like Apple/Windows Service Info (rejected: it stacked wide tablet columns and squeezed half-open fold panes at 1.0).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple supporting text and text values use primary text, not secondary | R2 | Apple check against the web's `versionValue` colour (kept in #387, an accessibility-only change) |
| Windows `ServiceInfoText.StacksStateRow` stacks at a text-scale threshold instead of measuring the fit (Apple moved onto `SettingsValueRow` in #387) | R1, R4 | Windows check: move the state row onto `SettingValueLayout` |

## Guards (`tools/pattern_guard.py`)

- `settings-value-row/android-parallel-fit`
- `settings-value-row/apple-parallel-fit`
