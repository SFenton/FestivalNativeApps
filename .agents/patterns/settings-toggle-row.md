# Settings toggle row

> **What:** the Settings on/off row: a title, optional description (and disabled reason) and a trailing switch, where the whole row is the switch's touch target and one accessibility element with the switch role. **Read when:** adding or changing a Settings switch, its touch target, its disabled state or how VoiceOver/TalkBack/Narrator read it.

Status: **current**, 2026-10-12. Provenance: Android Settings `ToggleRow` (whole-row `toggleable`), #496 (Apple whole-row target; agent decision), registered after the #496 design review.

## Intent

A setting is changed by tapping the setting, not by hunting for a 28-point switch at the row's end. The row's title and description name the switch, so they are part of its target; assistive technology reads one switch per row with its name, on/off state and why it is disabled.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/ToggleRow.tsx` (`ToggleRow`) | The row is a `PressableButton`: icon, label, description and the drawn track/thumb are all inside it, so a press anywhere on the row calls `onToggle` once; `disabled` dims the row and ignores presses. |
| `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx` (`ToggleRow` consumers) | Every Settings on/off setting is a `ToggleRow` (Accessibility, Item Shop, Show Instruments, metadata, experimental ranks, …). |
| `FortniteFestivalWeb/src/components/modals/modalStyles.ts` (`toggleRow`) | Row metrics: label/description column, track at the trailing end. |

The web also uses `ToggleRow` in the Songs and Suggestions filter sheets; those native sheets are not governed here yet (R7).

## Rules

1. **R1. The whole row is the target.** On touch platforms a tap anywhere on the row (title, description, leading icon, gap or switch) flips the switch. Consumers never make only the switch tappable.
2. **R2. Target size.** The row is at least 44 pt tall on iOS/iPadOS (HIG Accessibility › Mobility: "iOS, iPadOS 44×44pt", should) and at least 56 dp on Android (48 dp minimum, 56 dp with supporting text, with 16 dp horizontal and 8 dp vertical padding as [settings-value-row](settings-value-row.md) R2). The row grows with text size; it never clips the title or description.
3. **R3. One switch element.** The row is one accessibility element with the switch role: label = title, value = on/off, the description as hint/supporting text, and a disabled row reports not enabled and appends its reason (Android reads it; Apple shows it as the description). The visual switch is never a second element.
4. **R4. Disabled rows ignore every tap.** While disabled (for example Highlight Shop Items while the Shop is hidden), neither the switch nor the row's text flips it.
5. **R5. One tap, one flip.** Exactly one handler flips the value per tap: the row's tap never also reaches the switch's own action, so a tap on the switch never flips it twice.
6. **R6. One component per platform, applied once.** New Settings switches get R1–R5 with no extra code: Apple applies the row style once at the Settings page root (`settingsRowToggles()`), Android uses the Settings `ToggleRow`. Never add a per-switch `toggleStyle`, a second row-tap wrapper or a hand-built switch row.
7. **R7. Variants and exclusions.** *Mac (approved variant, agent decision #496):* the Mac Settings window keeps the system switch at the Mac control size and only the switch takes the click (HIG Toggles, macOS: "In a grouped form, consider a mini switch for a single-row setting", consider; pointer precision), so `settingsRowToggles()` is a no-op on macOS. *Not this pattern:* read-only rows ([settings-value-row](settings-value-row.md)), chevron/topic rows, the Paths default-view choice accordion (`SettingsChoiceRow`), reorder lists, and filter-sheet switches (`TODO(orchestrator)`: decide whether the Songs/Suggestions/Shop filter sheets, which share the web `ToggleRow`, join this pattern; Apple's are system `Form` rows today).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Row (R1–R5) | `apple/Sources/FestivalUI/Features/Settings/SettingsRowToggleStyle.swift` `SettingsRowToggleStyle`: keeps the system `.switch`, makes the label a ≥ 44 pt (`minimumHeight`) full-width `contentShape` whose tap flips the value only while `isEnabled`; the switch keeps its own tap | `android/app/src/main/java/com/festivalscoretracker/android/ui/settings/SettingsScreen.kt` `ToggleRow`: `Row` with `heightIn(min = 56.dp)` + `toggleable(role = Role.Switch)`, `Switch(onCheckedChange = null)`, `disabledReason` appended | `windows/Festival.App/Pages/SettingsPage.xaml` `SettingSwitchStyle` on each `ToggleSwitch` (debt: R1, R6) |
| Applied once (R6) | `settingsRowToggles()` on the `SettingsScreen` page stack (iPhone, iPad/Duo list and topic pages); no-op on macOS (R7) | every Settings switch calls `ToggleRow` | — |

Apple test IDs are the existing switch IDs (`fst.settings.motion`, `fst.settings.hide-shop`, `fst.settings.shop-highlights`, …); the row adds no element. Journeys tap a switch only through `SongsUITestSupport.tapSwitch` / `setSwitch` (bare track away from the thumb from `switchBareTrack(of:)`, held 0.2 s like a person's tap (#665), after the row's frame settles, exactly one flip and no retry; [xcuitest](../testing/apple/xcuitest.md)). Tests: Apple journeys `SettingsAccessibilityJourneyTests.testAccessibilityThenItemShopReadInOrder` and `testAccessibilityThenItemShopReadableAtAX5` (in `apple-ci` `JOURNEYS`): a tap on Reduce Motion's title flips it and a tap on its switch flips it back once (R1, R5), every switch in the Accessibility → Item Shop region has the switch role, its title as name, an on/off value and a ≥ 44 pt target at default size and AX5 (R2, R3), Highlight Shop Items reports disabled while Hide Item Shop is on (R3), and a scoped `performAccessibilityAudit` passes. Android: Robolectric `settings/SettingsUiTest` (switch state and enablement by tag).

Agent decision (#496, 2026-10-12; owner may override with `/choose`): on iOS/iPadOS every Settings switch's element and touch target was the 28 pt iOS 26 switch, so tapping a setting's title did nothing. Options weighed: (a) leave it (fails HIG "iOS, iPadOS 44×44pt"; diverges from web and Android), (b) enlarge only the accessibility frame (VoiceOver passes, the touch target stays 28 pt), (c) make the whole row the target with a `ToggleStyle` that keeps the system switch (chosen: web `ToggleRow` semantics, Android's `toggleable` rows, the native switch and its VoiceOver role, applied once so new switches inherit it). HIG Toggles: "Use the switch style only in a list row, where the row gives context" (should): the row is the switch's context, so it is also its target.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Windows Settings switches are a 52 epx `ToggleSwitch` beside an inert title/description `StackPanel`: clicking the title does nothing, and each row is hand-built in `SettingsPage.xaml` | R1, R6 | Windows check: one Settings toggle-row control whose whole row toggles, with UIA Toggle pattern on the row |
| Android Songs/Suggestions filter sheets have their own `ToggleRow` (`ui/songs/SongsSheets.kt`) with the same shape | R6 (only if filter sheets join, R7) | Decide with R7's TODO; share one Android row if they do |

## Guards (`tools/pattern_guard.py`)

- `settings-toggle-row/apple-switch-style`
