# CHOpt Paths — Android notes

> **What:** the Android Paths sheet: selection, loading, image/text rendering and settings it reads. **Read when:** changing `ui/songdetail/SongPathsSheet.kt`, `presentation/songs/SongPathsViewModel.kt` or `data/paths/`. Behavior: [spec.md](spec.md).

- Opens from Song Detail's **Paths** button as a full-height `ModalBottomSheet` (`fst.song-detail.paths`, below the status bar via `festivalSheetTop`): modal, so the page can't be used behind it and focus returns on close. Layout (web `PathsModal`, operator 6.27): a "Paths" header, the image/table filling the sheet, and the web's bottom control row (`fst.paths.selectors`): frosted instrument-icon, difficulty and view buttons (`fst.paths.{instrument,difficulty,display}.open`), each opening its panel above the row: the shared Instrument Selector (required, `fst.paths.instrument.<wireId>`), a 2×2 difficulty grid and Image/Text (`fst.paths.difficulty.<label>`, `fst.paths.display.<label>`, purple when chosen). When one row cannot fit the widest difficulty label (`controlRowFits`: about 300 dp at 100% text, e.g. a 320 dp phone or a book fold's end pane), the difficulty button takes its own line above the two icon buttons (`fst.paths.selectors.stacked`; issue #130: "Expert" wrapped to "Expe / rt").
- Each opening: first path chart (visible, charted, not Karaoke — `PathCapability.menuInstruments`), **Expert**, and the saved `pathDefaultView`.
- Reads `GET /api/paths/{song}/{chart}/{difficulty}` (PNG) or `/data` (schema-2 JSON) with `generationId` = catalogue `pathArtifactGenerationId`, through the shared pinned gate. PNG IHDR is bounded before decoding (`PathImageValidation`); JSON is validated (`SongPathData.validate`).
- `SongPathsViewModel` cancels the older request and uses a revision counter, so an old reply never paints; 404 → "No … path has been generated" (`fst.paths.not-generated`), other failures → inline service status with Retry.
- Image: decoded off the main thread with `inSampleSize` (≤ 2048 px wide, ≤ 16 MP), fills the width and scrolls vertically; 100–300% zoom buttons float over its top-right corner with horizontal scroll (no pinch conflict with the sheet). The bitmap is decoded while the spinner is still up (`decodeImage`), so the chart fades in already drawn.
- Switching (issue #70, web `PathsModal`): changing instrument, difficulty or Image/Text fades the old content out (300 ms, `PathSwapPhase.ContentOut`), fades the spinner in and holds it at least 400 ms for Image / 500 ms for Text (`PathSwapTiming`), fades it out (300 ms), then fades the new content in. The fetch runs during the fade-out; `state.shown` keeps the old labels on screen until the commit. A switch made during the spinner keeps the spinner (no extra fade), and a revision check means only the latest selection is ever shown. Text→text also fades (the web hard-cuts; the issue asks for the fade). Reduce Motion: no waits or minimum spinner, alpha snaps. A polite live region (`fst.paths.status`) announces "Loading X Y path" and then what loaded (image, N activations, not generated or unavailable).
- Text (web `PathDataTable`, 6.27): no path summary or max-score line; one frosted card per activation. Phones: ACTIVATION (five 22 dp fret pills, active in the web fret colours, inactive muted with a border), BEAT / TIME `mm:ss:mmm` / SCORE, then OVERDRIVE % as an amber bar with the rounded percent. Panes ≥ 600 dp **in 100%-text dp** (`usesPathGrid(width, fontScale)`: width ÷ font scale): the desktop grid in the Settings column order (`pathColumnOrder`) under an uppercase header. Below that, cards (issue #130: a 640 dp landscape sheet at 200% used the five-column grid and clipped "187.", "01:34:"). At large text (`isLargeText()`, ≥ 1.3×) BEAT, TIME and SCORE stack one per line and values may wrap (`oneLineUnlessLarge()`); three weighted columns clipped "01:34:534" to "01:34:53" at 200% on a phone. The path instruction text is not shown (web), but each card is one TalkBack stop whose sentence includes it.
- Book posture (issue #130): a separating vertical hinge across the sheet (`rememberHingeSplit()`, read **outside** `FestivalModalSheet` because the sheet is its own window) splits it (`fst.paths.hinge-split`): the image or table (plus status and spinner) fills the start pane, the control row with its panels above it sits in the end pane, and the hinge gap holds nothing (M3 foldables: "Never place interactive content or critical information across the hinge area"). The grid/cards choice uses the path pane's width. The centred 640 dp sheet otherwise put the table's Time column and the Difficulty button across the fold. Like other hinge splits, it is one column under TalkBack or at large text (`rememberSingleColumn`).
- Karaoke warning (Karaoke visible and not permanently dismissed): a native `AlertDialog` ("Some Instruments Unavailable" / "Karaoke is not available for path visualization yet."); **OK** hides it for this opening, **Don't Show Again** sets `pathUnavailableWarningDismissed` via `SettingsRepository.update`.
- IDs: `fst.paths.{image,table,table.header,zoom,zoom-in,zoom-out,loading,status,error,not-generated,karaoke-warning,warning.ok,warning.never,close}`, `fst.paths.row.<n>`, `fst.paths.fret.<colour>.<on|off>`.

Open: column reordering from inside the sheet (Settings owns it; the sheet follows `pathColumnOrder`).

## Validation (issue #130, 2026-10-04)

Live public service (keyless `https://festivalscoretracker.com/`, no profile selected), debug APK, `tools/android/device.py drive` with `FST_DEBUG_STILL_BACKGROUND=1` on "Cake By The Ocean" (`song:009f0d51-…`), animator scale 0 unless noted. Each run opened Paths (Karaoke warning → OK), checked the image with zoom, switched to Text, then changed difficulty and instrument, at font scale 1.0 and 2.0.

| Configuration | Found | Result |
|---|---|---|
| FST_Phone portrait, fs 1.0 | Nothing | Pass: cards, BEAT / TIME / SCORE on one line |
| FST_Phone portrait / landscape, fs 2.0 | Portrait: the three value columns cut "01:34:534" to "01:34:53". Landscape: the 640 dp sheet used the five-column grid and clipped "187." and "01:34:" | Fixed: cards below 600 dp in 100%-text dp (`usesPathGrid`), and values stack and wrap at large text |
| FST_Phone system light theme | App stays dark | Pass (dark-only brand theme, deliberate) |
| FST_Tablet landscape / portrait, fs 1.0 / 2.0 | Nothing | Pass: grid with header at 1.0, cards at 2.0 |
| FST_Resizable phone / foldable / tablet / desktop, fs 1.0 / 2.0 | Nothing beyond the phone fix | Pass: cards on phone, grid on foldable, tablet and desktop at 1.0, cards at 2.0 |
| FST_Book_Fold folded / unfolded, fs 1.0 / 2.0 | Nothing beyond the phone fix | Pass |
| FST_Book_Fold half-open, fs 1.0 | The centred sheet put the Time column and the Difficulty button across the hinge; after splitting, the ~288 dp end pane wrapped "Expert" to "Expe / rt" | Fixed: path in the start pane, controls and panels in the end pane (`fst.paths.hinge-split`), difficulty on its own line when the row can't fit (`fst.paths.selectors.stacked`); switching difficulty and instrument there works |
| FST_Book_Fold half-open, fs 2.0 | Content spans the hinge | Pass (one column at large text by design, as in other hinge splits) |
| FST_Passport_Fold folded / half-open / unfolded, fs 1.0 / 2.0 | Same split and narrow end pane as the book | Fixed by the same split and stacked row |
| FST_TriFold folded (360 dp) / partial / unfolded, fs 1.0 / 2.0 | Nothing beyond the phone fix; the emulator's hinges stay flat, so there is no split | Pass: cards folded, grid partial and unfolded at 1.0; at 2.0, the stacked control row on the 360 dp cover |
| Accessibility (connected `SongPathsDeviceTest`, FST_Phone and FST_Book_Fold half-open) | Nothing | Pass: ATF in each state, reading order per state (logcat `FST_A11Y`: heading, close, status, path, zoom, controls), no clipped text, nothing across the hinge |
| Reduced motion | Animator scale 0 (tool default) and in-app Reduce Motion: no fades or minimum spinner | Pass |
| Motion (`--animations`, FST_Phone) | Difficulty and instrument switches fade out, spinner, fade in | Pass |

Touch targets: close, zoom and carousel buttons are 48 dp, the control buttons 52 dp tall, and the option cells and warning buttons 48 dp. Contrast: text passes 4.5:1 (lowest: muted text on the frosted control at 5.9:1, and white on the purple choice at 5.7:1). The active fret pills pass 3:1 against the card (lowest: red at 4.9:1). Inactive fret slots keep the web's subtle border (1.3:1) as placeholders; the coloured active pills and each card's spoken sentence carry the activation.

Material 3 review (`material-3` skill, Compose guidance):

- The controls follow the guidance: modal bottom sheet with drag handle and close; `AlertDialog` for the Karaoke warning; 48 dp minimum touch targets; content split at the hinge and kept off it (foldables: "Never place interactive content or critical information across the hinge area").
- Deliberate deviations:
  - Dark-only brand theme and frosted product surfaces ([android.md](../../platforms/android.md)).
  - A 640 dp-capped bottom sheet rather than a side sheet on expanded windows (web `PathsModal` parity; the sheet keeps the image full height).
  - Option panels stay open after a choice and close on reselect (web).
  - At large text or under TalkBack, there is no hinge split.
  - On narrow panes, the stacked control row reads difficulty before instrument and view.

Tests: `SongPathsSheetUiTest` (Robolectric, every reachable state: image/text loading and loaded, missing, offline, instrument and difficulty switch, warning, zoom, saved column order, large text, narrow pane, book posture) and the connected `SongPathsDeviceTest`. `TextLayoutResult.hasVisualOverflow` from semantics misreports wrap-content `Text` (it re-lays out at the parent's max width). The device test therefore compares each line and the paragraph against the node size.
