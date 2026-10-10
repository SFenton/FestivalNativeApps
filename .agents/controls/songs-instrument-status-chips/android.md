# Instrument status chips — Android notes

> **What:** Android rendering of the selected-player per-chart status chips on Songs rows, deliberate deviations, the states→tests map and the 2026-10 validation matrix (#134). **Read when:** changing `StatusChips` in `ui/songs/SongRow.kt` or `SongInstrumentStatusPolicy`. Behavior: [spec.md](spec.md); platform: [android.md](../../platforms/android.md).

## Implementation

- `SongInstrumentStatusPolicy.showsChips` (`core/songs/SongRowProjection.kt`): selected player, publication-matched available scores, Show Instrument Icons on, no single-chart filter, ≥1 visible chart. **Differs from spec.md:** Filter Invalid Scores does *not* hide the chips. Since `8e796ee8` the chips use the effective (next valid) scores, and the row adds the red/gold invalid-score indicator (`fst.songs.invalid-score.<songId>`) plus a "Filtered score" phrase in its label, matching the web row fallback.
- Chip: 34 dp circle (doesn't scale with font), 2 dp ring, the chart's icon at 70% (keys variant for Lead/Pro Lead on `Keyboard` songs), 4 dp gaps. Colors come from `contracts/fluent-tokens.json` via `SongsTokens.chip(status, selected)`: gold/`goldStroke` FC, green scored, red no score, amber inconsistent FC, muted/disabled not charted. There is no corner glyph (color-only native deviation, spec.md).
- **Selected two-pane row (#134):** the purple highlight (`accentPurple` at 35%) left No score (fill 2.33:1, `8B0000` ring 1.31:1) and Not charted (fill 1.02:1, `textDisabled` ring 2.6:1) under 3:1. On that row only, the No score ring is `statusRedStrokeSelected` `E57373` (4.38:1) and the Not charted ring is `textMuted` (4.47:1). Fills and plain rows keep web parity. `SongChipContrastTest` gates every status on the card, frosted, selected-frosted and selected-card backdrops.
- Layout: one `Spacer` drawn with `drawBehind`, measured by `ChipGrid` in balanced, centred rows (9 → 5+4 when one row doesn't fit; Apple `SongChipRows` rule). No `FlowRow` or per-chip nodes. Tag `fst.songs.instrument-status.<songId>`. The test-only `SongChipStatuses` semantics property lists `<wireId>.<Status>` in order.
- Accessibility: the chips are not separate nodes. The row column uses `clearAndSetSemantics`, so TalkBack makes one stop per row, whose label (`SongRowModel.announcement`) lists "Lead, full combo, Bass, scored, …" in service order.

## Deliberate deviations (material-3 skill)

- **Not M3 `Chip`s:** `component-catalog.md` defines Chips as interactive Assist/Filter/Input/Suggestion controls. These are decorative status marks inside one row button, so they behave like status badges with the `full` shape ("`full` … Buttons, badges, pills", `typography-and-shape.md`). They are not separate 48 dp targets: the whole row is the ≥48 dp button (SKILL.md: "touch targets (~48dp)").
- **Fixed web colors, not M3 roles:** contrast is enforced instead. Each status's fill or ring is ≥3:1 on every row backdrop (SKILL.md: "UI components often need **3:1** for large text/borders"; `color-system.md`: Outline "3:1 contrast").
- **Dark only:** the app has one dark scheme, so system light mode doesn't change the chips (checked with `dark:off`).
- **Fixed 34 dp at large text:** the chips are graphics, not text. The title and artist wrap at font scale 2.0, and the chips keep their size and row count.

## States → evidence

| State | Evidence |
|---|---|
| `anonymous`, `loading`, `syncing`, `failed` | `SongsInstrumentStatusChipsUiTest` (`anonymous…`, `loading…`, `syncing…` 202, `failed…` 500): no chips, explicit score state |
| `available-empty` | `…availableEmptyIndexIsNoScoreOnChartedParts…` |
| `full-combo`, `scored`, `no-score`, `not-charted`, `inconsistent-zero-fc`, `keyboard-variant` | `…eachStatusFollowsTheChartAndScoreInServiceOrder` (s-beta keys); `SongsCoreTest` (policy); live (SFentonX: gold, green, red, muted) |
| `instrument-hidden`, `chart-filtered`, `icons-off` | `…hiddenInstrumentsDropTheirChips`, `…singleChartFilterSwaps…`, `…iconsOffShowsMetadata…` |
| `invalid-filter-paused` | `…filterInvalidScoresKeepsChipsOnEffectiveScoresWithTheWarning`, `…filterInvalidScoresOffShowsTheRawFullCombo` |
| `compact`, `wide` | `…compactWidthWrapsNineChipsIntoBalancedRows` (w320, 72 dp), `…phoneWidthFits…` (34 dp), `…wideSinglePaneCard…` (w700), `…twoPaneSelectedRow…` (w1280, 5+4); `ChipGridTest`; live matrix |
| `largest-text` | `…largestTextKeepsChipSizeAndEveryStatus` (`fontScale = 2f`); FST_Phone and FST_Tablet at 2.0 |
| `high-contrast` | `…increaseContrastKeepsEveryChip`; `SongChipContrastTest` (opaque card) |
| `screen-reader` | `…screenReaderHearsOneRowSummary…`; connected `SongsAccessibilityJourneyTest#songsInstrumentStatusChipsReadAsOneRowSummary` (ATF, reading order, ≥48 dp row, no hinge straddle, selected two-pane row); TalkBack walk |
| `band-blocked` | Not reachable on Android: there is no selected band, and band search is blocked by service safety |

Fixture-only states (loading, 202, failure, empty index, inconsistent FC, invalid-score filter) are proven by tests only, never by live captures.

## Validation matrix (2026-10-04, live public service, SFentonX)

| Configuration | Findings |
|---|---|
| FST_Phone portrait, 1.0 / 2.0 | Nine chips in one centred row under each title. At 2.0 the title and artist wrap, and the chips keep 34 dp in one row, inside the card. The connected journey passes. |
| FST_Phone landscape | Two-pane: the list column wraps 5+4, and the auto-selected purple row shows the lighter No score rings. |
| FST_Phone `dark:off` | Unchanged (dark-only app). |
| FST_Tablet landscape / portrait | Landscape two-pane: 5+4 in the list column, and the selected row keeps every chip distinct after the fix. Portrait: one row. At 2.0 the layout falls back to one pane with one row of chips. The connected journey passes (selected two-pane branch). |
| FST_Resizable phone / foldable / tablet / desktop | One row on phone. Two-pane 5+4 on foldable, tablet and desktop. The chips stay inside the card in each. |
| FST_Book_Fold folded / half / unfolded | Folded: one row. Half and unfolded: the list pane sits left of the hinge, 5+4. The connected journey passes half-open (no chip straddles the hinge). Since #581 Songs has no list pane: each two-column cell keeps every chip inside its card (`SongsInstrumentStatusChipsUiTest.twoColumnCellKeepsEveryChipInsideItsCard`). |
| FST_Passport_Fold folded / half / unfolded | As Book_Fold. |
| FST_TriFold folded / partial / unfolded | Folded: the narrow cover wraps a balanced 5+4. Partial: one pane, one row. Unfolded: two-pane 5+4, and the selected row is legible. |
| TalkBack (FST_Phone) | One stop per row: "The Way Life Goes, Lil Uzi Vert … Lead, full combo, Bass, full combo, Drums, full combo, Tap Vocals, full combo, Pro Lead, no score, … Pro Drums, no score, Last played …". Every chart is read in service order, and no chip is a separate stop. |
| Animator scale 0 | The device tools' default. The chips have no animation (static draw), so there's nothing to reduce. |

## Tests

`SongsInstrumentStatusChipsUiTest`, `SongChipContrastTest`, `ChipGridTest`, `SongsDrawUiTest` (Robolectric/JVM), `SongsCoreTest` (policy); connected `journeys/SongsAccessibilityJourneyTest#songsInstrumentStatusChipsReadAsOneRowSummary` (`device.py test … --avd FST_Phone|FST_Tablet|FST_Book_Fold --posture half`).