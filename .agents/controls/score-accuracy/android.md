# Score accuracy — Android notes

> **What:** the Compose accuracy badge, its deliberate deviations, tests and the 2026-10 validation matrix (#127). **Read when:** changing `AccuracyPill`, `ScoreAccuracyBadge` or a score row that shows accuracy. Spec: [spec.md](spec.md); platform: [android.md](../../platforms/android.md).

## Implementation

- Policy (pure, JVM-tested): `core/format/ScoreAccuracyBadge.kt` turns `(accuracy, isFullCombo)` into `Graded` / `FullCombo` / `FullComboNoAccuracy` / `Invalid` or `null` (absent), with the visible text, the spoken label and the web tint (`GRADED_TINT_ALPHA` 0.25). Never infers FC from 100%. Non-finite accuracy is `Invalid` ("—", "Accuracy unavailable"); out-of-range numbers keep their value and only the colour clamps.
- Rendering: `ui/design/AccuracyPill.kt`. Graded = white `labelMedium` SemiBold on the red→green tint at 25% in an 8 dp rounded rect (web `Radius.xs`). FC = bold italic `BrandTokens.gold` text inside a 2 dp `goldStroke` outline sheared like CSS `skewX(-8deg)`, inset so it stays inside its column. Minimum width 56 dp = `LeaderboardColumnLayout.ACCURACY_WIDTH`, so graded, FC and absent rows share one column.
- Test tag `fst.score.accuracy.<accountId|bandKey>` on the badge (`ACCURACY_TAG_PREFIX`). Semantics are `clearAndSetSemantics { contentDescription = announcement }`; rows merge it, so TalkBack reads "#9. KingBryce98. 105,220. Full combo, accuracy 100%. Button".
- Large text (`isLargeText()`, font scale ≥ 1.3) uses `StackedScoreRow`: the badge shows the full announcement ("Accuracy 98%", "Full combo, accuracy 100%") unskewed and may wrap.
- Callers: Song Detail `ScoreRow` and `StackedScoreRow` (preview and full chart), band chart rows (`accuracy > 0` only), player history rows. `ScoreSectionTexts.hasAccuracy` counts FC-only sections, so the column stays.

## Deliberate deviations

- **Operator 7.11 overrides the spec's "Gold outline plus visible FC":** FC shows only the gold percentage (the web look), never a separate FC chip. The spoken label still says "Full combo".
- **Web pill rather than the M3 `Badge`:** the material-3 skill's Badge is a `full`-shape count dot using Label Small (`typography-and-shape.md`: "Badge count | Label Small"). This is a data value in a table column, so it keeps the web's 8 dp rect, which is M3's `small` shape ("`small` | 8 | 8px | Text fields, menus, chips"), and `labelMedium`.
- **Fixed colours rather than M3 roles:** the tint ramp and gold come from the web tokens. Contrast is enforced instead: white on every tint over the card, frosted and selected backdrops ≥ 4.5:1, gold text ≥ 4.5:1, gold outline ≥ 3:1 (SKILL.md: "Only combine colors in their intended pairs"; `color-system.md`: "Outline … 3:1 contrast"). See `ScoreAccuracyContrastTest`.
- **Dark only:** the app has a single dark scheme ([design/android.md](../../design/android.md)), so system light mode does not change the badge (verified on FST_Phone with `dark:off`).
- The badge isn't a touch target: the whole row is the 48 dp+ button (`component-catalog.md`: "Minimum touch target 48x48dp").
- In band and history rows the row's `clearAndSetSemantics` hides the badge tag from the semantics tree; the badge is still announced through the row label.

## States → evidence

| State | How it is shown/tested |
|---|---|
| `absent`, `graded-low/mid/high`, `full-combo`, `full-combo-no-accuracy`, `invalid` | `ScoreAccuracyBadgeTest` (policy), `ScoreAccuracyUiTest` (rendered text, label, pixels) |
| `aligned-columns`, `missing-accuracy-aligned` | `ScoreAccuracyUiTest.alignedColumns…`, `.fullComboOnlySection…`; `LeaderboardColumnLayoutTest`; connected journey (centres within 1 px) |
| `badge-contrast` | `ScoreAccuracyContrastTest`, `ScoreAccuracyUiTest.badgeContrast…` |
| `normal-audit` | `ScoreAccuracyJourneyTest` ATF (no errors), TalkBack walk |
| `preview`, `full-chart` | `ScoreAccuracyUiTest.previewAndFullChart…`, connected journey on both routes |
| `large-text` | `ScoreAccuracyUiTest.largeText…`; emulator at font scale 2.0 |
| `sidebar-transition` | No sidebar on Android: rail/drawer/bottom-bar changes on rotation, resize and fold posture. Live captures across all of them; the journey asserts no badge straddles a hinge |
| `offscreen-targets` | Rows cut off by their list are ATF clipping artifacts the harness ignores; the badge has no own target |

Fixture-only states (`invalid`, `full-combo-no-accuracy`, `absent`) are not in live data, so they are proven only by tests.

## Validation matrix (2026-10-04, live public service, Blinding Lights)

| Configuration | Findings |
|---|---|
| FST_Phone portrait, 1.0 | Preview and full chart: graded 94–99% pills and gold skewed FC 100% aligned in one column. Connected journey passes. |
| FST_Phone, 2.0 | Stacked rows with full labels; FC labels wrap inside the unskewed gold outline; no clipping. |
| FST_Phone landscape | Full chart list is short (header scrolls with it); rows show season, score, badge and stars aligned. |
| FST_Phone `dark:off` | Unchanged (dark-only app). |
| FST_Tablet portrait / landscape | Rail plus two-column grid; permanent drawer in landscape. Aligned in both. |
| FST_Resizable phone / foldable / tablet / desktop | Bottom bar → rail → drawer; desktop adds season and stars. Aligned in each. |
| FST_Book_Fold folded / unfolded | Single column folded; two columns either side of the hinge unfolded. Connected journey passes unfolded. |
| FST_Passport_Fold folded / unfolded | As Book_Fold. |
| FST_TriFold | Rail plus two-column grid; aligned. |
| TalkBack (FST_Phone, full chart) | Rows read in visual order, each with "Accuracy N%" or "Full combo, accuracy 100%", then the pager and tabs. |
| Animator scale 0 | The device tools' default; the badge has no animation. |

## Tests

`ScoreAccuracyBadgeTest`, `ScoreAccuracyContrastTest`, `ScoreAccuracyUiTest` (Robolectric), `LeaderboardColumnLayoutTest`, `BandsUiTest`; connected `journeys/ScoreAccuracyJourneyTest` (`device.py test com.festivalscoretracker.android.journeys.ScoreAccuracyJourneyTest --avd …`). It checks the shared badge column only below `LARGE_TEXT_SCALE` (rows stack at large text, so it passes at font scale 1.0 and 2.0), waits for the outgoing Song Detail before walking the full chart (the preview rows reuse the badge tags), and re-walks until the UiAutomation tree, which trails Compose semantics after navigation, no longer reads Song Detail.
