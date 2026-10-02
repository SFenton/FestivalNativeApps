# CHOpt Paths — iPhone notes

> **What:** the SwiftUI `SongPathsSheet` as built, native decisions and open gaps. **Read when:** changing Paths on iPhone. Behavior: [spec.md](spec.md).

## Implemented (partial)

- Toolbar Paths appears if any non-Karaoke path chart is enabled; the sheet resets chart/Expert and uses the saved Settings default.
- PNG decoded off the UI actor, single frame, ≤4,096 px edge / 24 MP; response-proven PNGs in a 32 MB / 16-entry LRU; each response rejected above 8 MB before caching. Text activation rows derived once on the client actor, not per SwiftUI body pass.
- `.task(id:)` cancellation plus an exact request-key guard prevents stale paints (Expert→Hard, missing Medium 404, Bass error → Lead recovery covered).
- Switch fades (issue #70): `PathSwitchTransition` (FestivalCore) runs web `PathImage`'s sequence for every instrument, difficulty, view, retry or publication change: the old image/table/error fades out (300 ms), the spinner fades in and stays at least 400 ms (image) / 500 ms (text), fades out (300 ms), and the new content fades in (300 ms). The fetch starts during the fade-out. The content and spinner are separate `.transition(.opacity)` layers in a `ZStack`, so a removed chart fades from its last frame and is never shown again; a newer choice cancels the task before it can apply `showContent`. Reduce Motion: instant swaps, spinner minimum kept so it never blinks. VoiceOver hears "Loading Lead Hard image path" on a switch, then "Lead Hard path image" / "…path, N activations" (errors keep `ServiceStatusView`'s announcement). Zoom resets when the spinner appears, not on the old image while it fades.
- Chrome (issue #23): the shared `FestivalModal` title bar — inline title "Paths", image zoom out / percentage / zoom in as a leading toolbar group (image mode only; `fst.paths.zoom-out`/`-in`), and the system Close top-right (`fst.paths.close`). The hand-drawn header row with its own ✕ circle is gone. Swipe-to-dismiss stays disabled (pinch/pan), so Close is the only dismissal.
- Karaoke warning: native alert with OK / permanent dismissal that survives cold launch; Settings Reset restores it. `FST_UI_TEST_RESET_PATH_WARNING=1` resets only that preference on Debug fixture launches.

## Native decisions

| Web | iPhone | Why |
|---|---|---|
| Translucent bottom sheet, controls at the bottom | Opaque full-height system sheet, bottom row of native pop-up menus | Safe areas and legibility |
| Mobile instrument accordion (`InstrumentSelector`) | Native instrument pop-up menu with icons (issue #88) | Platform convention for a flat list of exclusive options |
| Compact table / draggable desktop columns | Activation cards with five fret colours, OD bar and CHOpt instructions | Readable at large text; column reorder pending |
| Two-column warning actions truncate "Don't show again" | System alert with stacked full-length actions | Legibility |

Fret accents are chart-content colours isolated to this control, not shared Fluent tokens.

## Open (iPhone)

Draggable column order and full table geometry; only-Karaoke-visible guard; focus-return proof; large-image performance on long real charts; warning alert full audit (system title contrast + message Dynamic Type — [accessibility](../../testing/apple/accessibility.md)). Offline/unverified path disclosure predates online-only.

## Web mobile table and selector (operator batch 6.27, Lane AP5)

- Text view is the web's mobile `PathDataTable`: one glass card per activation with a Note caption over five 22 pt fret pills (inactive `surfaceMuted` with a `borderSubtle` outline), Beat / Time / Score side by side, and an Overdrive caption over the web `OdBar` (an amber `#F5A623` tinted system progress bar — custom drawn tracks failed the contrast audit — and a bold "NN%"); missing values are em dashes. No path summary, instruction text or max score above the cards. Each card is one VoiceOver element ("Activation N", value lists frets, beat, time, score, overdrive). The saved column order is not used (the web's mobile layout ignores it too). The text scroll view's identifier names what it shows: `fst.paths.text.<Instrument>.<difficulty>`.
- Instrument, Difficulty and View are three native pop-up menus in the bottom row (issue #88 replaced the web mobile instrument accordion). Each is a `Menu` holding an inline `Picker` (system menu, checkmark on the current option, source order kept with `.menuOrder(.fixed)` when it opens upward). The label shows the current value and an up/down chevron on the glass capsule. The 44 pt frame sits inside the label, because a frame outside a `Menu` doesn't grow its tap area; a bare `.menu` `Picker` measured 34.7–38 pt tall. Instrument items list only the enabled non-Karaoke path instruments in source order, each with its artwork (`InstrumentIcon.menuImage`, redrawn at 24 pt because menus ignore `resizable()`); the label always shows icon + name, and long names wrap to a second line. An icon-only `ViewThatFits` fallback failed the XCUITest Dynamic Type audit ("Dynamic Type font sizes are partially unsupported" on the name), because the text vanished at larger sizes. VoiceOver reads "Instrument, <name>" (label + value), like "Difficulty, Expert". IDs unchanged: `fst.paths.{instrument,difficulty,display}`. macOS uses the system pop-up button (`Picker(.menu)`, icons in the button and items; hosted render `SongPathsSheetRenderTests`). The Karaoke notice stays a native alert. HIG: pop-up-buttons › "A pop-up button presents a flat list of mutually exclusive options; after selection, the menu closes and the button can show the current selection"; menus › "Treat items in the same group uniformly: icons for all or none"; accessibility › iOS, iPadOS 44×44 pt.
