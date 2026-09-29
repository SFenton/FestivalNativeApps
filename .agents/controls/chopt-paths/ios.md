# CHOpt Paths — iPhone notes

> **What:** the SwiftUI `SongPathsSheet` as built, native decisions and open gaps. **Read when:** changing Paths on iPhone. Behavior: [spec.md](spec.md).

## Implemented (partial)

- Toolbar Paths appears if any non-Karaoke path chart is enabled; the sheet resets chart/Expert and uses the saved Settings default.
- PNG decoded off the UI actor, single frame, ≤4,096 px edge / 24 MP; response-proven PNGs in a 32 MB / 16-entry LRU; each response rejected above 8 MB before caching. Text activation rows derived once on the client actor, not per SwiftUI body pass.
- `.task(id:)` cancellation plus an exact request-key guard prevents stale paints (Expert→Hard, missing Medium 404, Bass error → Lead recovery covered).
- Karaoke warning: native alert with OK / permanent dismissal that survives cold launch; Settings Reset restores it. `FST_UI_TEST_RESET_PATH_WARNING=1` resets only that preference on Debug fixture launches.

## Native decisions

| Web | iPhone | Why |
|---|---|---|
| Translucent bottom sheet, controls at the bottom | Opaque full-height system sheet, top menu/segments | Safe areas and legibility |
| Compact table / draggable desktop columns | Activation cards with five fret colours, OD bar and CHOpt instructions | Readable at large text; column reorder pending |
| Two-column warning actions truncate "Don't show again" | System alert with stacked full-length actions | Legibility |

Fret accents are chart-content colours isolated to this control, not shared Fluent tokens.

## Open (iPhone)

Draggable column order and full table geometry; only-Karaoke-visible guard; rapid-response race and focus-return proof; large-image performance on long real charts; warning alert full audit (system title contrast + message Dynamic Type — [accessibility](../../testing/apple/accessibility.md)). Offline/unverified path disclosure predates online-only.

## Web mobile table and selector (operator batch 6.27, Lane AP5)

- Text view is the web's mobile `PathDataTable`: one glass card per activation with a Note caption over five 22 pt fret pills (inactive `surfaceMuted` with a `borderSubtle` outline), Beat / Time / Score side by side, and an Overdrive caption over the web `OdBar` (8 pt `surfaceSubtle` track, amber `#F5A623` fill, bold "NN%"); missing values are em dashes. No path summary, instruction text or max score above the cards. Each card is one VoiceOver element ("Activation N", value lists frets, beat, time, score, overdrive). The saved column order is not used (the web's mobile layout ignores it too). The text scroll view's identifier names what it shows: `fst.paths.text.<Instrument>.<difficulty>`.
- The instrument menu is now an icon toggle (`fst.paths.instrument`, web mobile instrument button with a chevron) that opens the shared `InstrumentSelector` accordion above the bottom row (required, Karaoke hidden); tapping the current instrument closes it. Difficulty and View stay native menus. The Karaoke notice stays a native alert.
