# CHOpt Paths — Android notes

> **What:** the Android Paths sheet: selection, loading, image/text rendering and settings it reads. **Read when:** changing `ui/songdetail/SongPathsSheet.kt`, `presentation/songs/SongPathsViewModel.kt` or `data/paths/`. Behavior: [spec.md](spec.md).

- Opens from Song Detail's **Paths** button as a full-height `ModalBottomSheet` (`fst.song-detail.paths`): modal, so the page can't be used behind it and focus returns on close. Layout (operator, like the web modal): a one-line "Paths · {song}" header, the image/table filling the sheet, and one bottom row (`fst.paths.selectors`) of M3 **exposed dropdown menus** for Instrument (with icons), Difficulty and View; options are `fst.paths.<selector>.<value>`.
- Each opening: first path chart (visible, charted, not Karaoke — `PathCapability.menuInstruments`), **Expert**, and the saved `pathDefaultView`.
- Reads `GET /api/paths/{song}/{chart}/{difficulty}` (PNG) or `/data` (schema-2 JSON) with `generationId` = catalogue `pathArtifactGenerationId`, through the shared pinned gate. PNG IHDR is bounded before decoding (`PathImageValidation`); JSON is validated (`SongPathData.validate`).
- `SongPathsViewModel` cancels the older request and uses a revision counter, so an old reply never paints; 404 → "No … path has been generated" (`fst.paths.not-generated`), other failures → inline service status with Retry.
- Image: decoded off the main thread with `inSampleSize` (≤ 2048 px wide, ≤ 16 MP), fills the width and scrolls vertically; 100–300% zoom buttons float over its top-right corner with horizontal scroll (no pinch conflict with the sheet). Image and table fade in when they arrive.
- Text: summary, max score, then rows in the Settings column order (`pathColumnOrder`: Note fret dots, Beat, Time `mm:ss:mmm`, OD, Score) with the instruction underneath; each row is one TalkBack stop with a full sentence.
- Karaoke warning (Karaoke visible and not permanently dismissed): **OK** hides it for this opening, **Don't Show Again** sets `pathUnavailableWarningDismissed` via `SettingsRepository.update`.
- IDs: `fst.paths.{instrument,difficulty,display,image,table,zoom,zoom-in,zoom-out,loading,error,not-generated,karaoke-warning,close}`, `fst.paths.row.<n>`.

Open: column reordering from inside the sheet (Settings owns it), accessibility audit.
