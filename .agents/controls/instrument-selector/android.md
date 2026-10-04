# Instrument Selector — Android notes

> **What:** Compose implementation, validation and evidence. **Read when:** adding an instrument picker on Android or changing `ui/design/InstrumentSelector.kt`. Behavior: [spec.md](spec.md).

## Implementation

- `ui/design/InstrumentSelector(instruments, selected, onSelect, hidden, disabled, muted, required, compact = null, deferSelection, keyboard, tag, content)`; pure rules in `core/songs/InstrumentSelection` (unit-tested: availability, toggle/required, auto-compact width `n × 64 + (n − 1) × 12` dp, wrap-around cycling that skips disabled charts, deferred preview).
- Full row: centred `FlowRow` of 64 dp circles with 48 dp icons; the selected chart's green disc scales in (300 ms, drawn in `drawBehind`, instant under Reduce Motion). Disabled 28% / muted 42% greyscale. Compact: previous / current / next with labelled 48 dp `IconButton` arrows ("Previous instrument" / "Next instrument").
- Deferred (Songs filter): the arrows move a preview kept in `rememberSaveable` (survives rotation and fold/unfold; resets when the visible chart list changes); pressing the preview commits it.
- `content` expands below while a rendered chart is selected (web collapsible children); expand/collapse is 300 ms, `EnterTransition.None`/`ExitTransition.None` under Reduce Motion (`$tag.detail`).
- Accessibility: one `selectableGroup`; each circle is one element named by the chart. A **required** selector is a radio group (`Role.RadioButton`); an **optional** one, where pressing the selection clears it, reads like a `FilterChip` (`Role.Checkbox`). State descriptions: "Unavailable" (disabled), "Not selected, conflicts with another choice" (muted, unselected). The compact centre is a polite live region so arrow presses announce the new chart.
- Used by: Songs Filter (deferred, optional), Paths (required, Karaoke left out by the caller), Song Detail score history (required). Suggestions uses its own `FilterChip` row (`fst.suggestions.filter.instrument-picker`); no Android caller passes `disabled`/`muted` today.
- Test tags: `$tag.<wireId>`, `$tag.compact`, `$tag.previous`, `$tag.next`, `$tag.preview`, `$tag.detail`.

## Validation (issue #129, 2026-10-04, live public service, player SFentonX)

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 | Songs filter compact + deferred (preview moves without filtering; centre commits, detail expands); Paths and Score History compact required |
| FST_Phone portrait, font 2.0 | No clipping: circles stay 64 dp, arrows 48 dp touch bounds, filter text wraps |
| FST_Phone landscape (light system theme) | Paths full row of 8 (Karaoke hidden); Songs filter (overflow → Filter, 592 dp sheet) stays compact; detail opens in the sheet's scroll area. Light renders identically: the app theme is dark-only by design |
| FST_Tablet landscape (natural) / portrait (+ font 2.0) | Filter sheet 592 dp → compact; Paths 8 and Score History 6 in full rows; no clipping at 2.0 |
| FST_Resizable phone / foldable (medium) / tablet (expanded) | Phone: compact Paths and Score History. Medium: filter compact in the 592 dp sheet with the chart's sections expanded; Score History full row. Expanded: Paths 8 and Score History 6 in full rows |
| FST_Book_Fold folded / unfolded | Cover screen: compact required selectors (Paths, Score History). Unfolded: full rows; the flat (non-separating) fold may pass under the sheet's centred selector |
| FST_Passport_Fold folded / unfolded | Same as Book Fold |
| FST_TriFold folded / unfolded | Compact folded; full rows unfolded |
| `disabled`, `muted` | No live caller; covered by Robolectric tests only |

Defects found and fixed: the optional Songs filter read every chart as a radio button although pressing the selection clears it; compact arrows changed the chart silently (TalkBack); the detail ignored Remove animations; the deferred preview reset on rotation.

## Material 3 deviations (deliberate)

Reviewed against the `material-3` skill (Compose: component catalog — chips, segmented buttons, icon buttons; motion; accessibility). Kept from the web spec: 64 dp brand circles with the #2ECC71 disc instead of `SegmentedButton`/`FilterChip` visuals, `BrandTokens` instead of colour-scheme roles, and web opacities 0.28 (disabled) / 0.42 (muted). Followed from the skill: "Toggle buttons should have descriptive labels for both states" (role + state per element), "Minimum touch target 48x48dp" (arrows), and the 300 ms Medium 2 duration with Reduce Motion honoured.

## Tests

- `InstrumentSelectorUiTest` (Robolectric, 19): none, selected (disc pixels, press-to-clear), required (radio, keeps selection), hidden (incl. hidden selection and all hidden), disabled, muted, compact (auto width, exact fit, forced modes, cycling, non-deferred), deferred (preview, commit, restore across recreation), detail-expanded, motion vs reduced motion, font 2.0 geometry.
- `InstrumentSelectorDeviceTest` (connected; FST_Phone, FST_Tablet, FST_Book_Fold folded): ATF + reading order with CheckBox/RadioButton classes for every state, font 2.0 geometry, device animator scale drives the detail animation, Songs filter deferred journey on fixtures.