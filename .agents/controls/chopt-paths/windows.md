# CHOpt Paths — Windows notes

> **What:** the Windows Paths dialog. **Read when:** changing `windows/Festival.App/Controls/SongPathsView*` or `SongPathsViewModel`. Behavior and wire: [spec.md](spec.md).

- Opened from Song Detail's accent **Paths** button as a modal `ContentDialog` (`fst.paths`), `FullSizeDesired`, max width `min(1200, window − 48)`; the dialog contains and restores focus (the web dialog doesn't). Esc/Close dismiss and cancel any in-flight read.
- Each opening resets to the first visible charted path instrument (Karaoke excluded), **Expert**, and Settings' `PathDefaultView`. Selectors wrap (`FlowPanel`): instrument `ComboBox`, difficulty and Image/Text `RadioButtons`.
- Reads: `GetPathImageAsync` / `GetPathDataAsync` with the catalogue's `pathArtifactGenerationId`; a revision counter drops any response older than the current selection. HTTP 404 shows "No path has been generated…" (`fst.paths.empty`), not an error; other failures use the service-status view with Retry.
- Image: PNG header/size validated in Core before decode (≤ 8 MB, ≤ 8192 × 30000, ≤ 24 MP); decoded at ≤ 4096 px wide; fit to width, native pinch / Ctrl+wheel zoom (1–3×) plus Zoom out/in buttons.
- Text: summary, max score, one card per activation with columns in Settings' `PathColumnOrder` (Note frets, Beat, Time `mm:ss:SSS`, Overdrive % bar, Score).
- Karaoke warning: informational `InfoBar` when Karaoke is visible; close hides it for this opening, **Don't Show Again** persists `PathUnavailableWarningDismissed`.
