# Modal shell

> **What:** the shared sheet, dialog and alert container with its title, dismissal and standard Close affordance. **Read when:** presenting a scoped task, confirmation or notice.

Status: **current**, 2026-10-05. Provenance: #23, #24, #25, #94, #96, #125, #139, #140, #183, #360.

## Intent

A modal identifies one short, scoped task, exposes its platform-standard dismissal and closes before another modal opens. Features own body content and actions; the shared shell owns chrome, focus/dismissal behavior and the header.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/modals/components/ModalShell.tsx` (`ModalShell`, `DEFAULT_TRANSITION_MS`, `FOCUSABLE_SELECTOR`) | One portal shell owns overlay, Escape, focus containment, focus restoration and nested-layer inertness. |
| `FortniteFestivalWeb/src/components/modals/Modal.tsx` (`Modal`) | Variant content supplies reset/apply behavior inside the common shell. |

## Rules

- **R1. Use only the shared shell.** Every feature modal uses its platform canonical component; never construct an unowned sheet, dialog or `ContentDialog`.
- **R2. Name the task.** The common header/dialog title is concise and announced before body content. Apple HIG Modality: “Identify the task with a title or explanatory/guidance text so people can regain their place after switching context.” **Owner-approved variant (#360, Paths sheet on folded iPhone Duo only):** where `DeviceLayout.pose == .folded`, the Paths title names the selected instrument, "Paths · <instrument>" (updating as it changes), and its instrument selector shows only the instrument icon (owner: "On Duo folded, don’t show instrument name in paths modal selector- icon is fine. Title can say Paths {dot} {instrument name}"; HIG Designing for iPhone Duo: "prefer a symbol wherever one works"). The selector keeps its VoiceOver label and value ("Instrument, <name>") and its icon scales with Dynamic Type. Every other pose and platform (unfolded/book Duo, iPhone, iPad, Mac) and every other modal keep the plain task title; do not revert or spread it without an owner ask. `SongPathsSheet.title(for:pose:)` / `showsInstrumentName(pose:)` own it. Evidence: `SongPathsSelectorTests` (rule) and `DuoPathsSelectorJourneyTests` (rendered: folded icon-only selector measured in pixels, title following an instrument switch, "Instrument, <name>" kept, unfold/refold, standard iPhone).
- **R3. Offer the native dismissal.** Apple sheets use the system Close and permit vertical dismissal where no input is at risk; Android uses the Material Close button plus back/scrim/swipe; Windows uses the standard `ContentDialog` Close command and Esc/light dismiss. Apple HIG Modality: “Always provide an obvious, platform-conventional dismissal.”
- **R4. Keep Close out of feature bodies.** Do not draw a custom xmark, footer Close or live-apply Done control. Apple’s system `FestivalSheetCloseItem`, Android’s 48 dp `FestivalModalCloseButton` and Windows’ command row are the only shared close affordances.
- **R5. Keep the body below the header.** The Apple shell applies the shared top fade (#94); Android and Windows retain a hard content edge. Modal presentation never covers its own title or Close control.
- **R6. Preserve the feedback-form exception.** It has potentially lossy text input, so it uses Cancel and Submit with discard confirmation rather than the ordinary Close-only task shell. Apple HIG Sheets: “Single-view sheets: Cancel on the top toolbar's leading edge; Done, when present, trailing.”
- **R7. Serialize presentations.** Dismiss a sheet before opening another; a confirmation alert may sit above a modal, but never stack independent alerts. Apple HIG Sheets: “Display only one sheet at a time from the main interface.”
- **R8. Keep surfaces off a separating hinge with one side rule (Android).** Sheets, centred dialogs and the full-page service status ([empty-error-states](empty-error-states.md) R7) never straddle a **separating** fold or hinge. Material 3: “Never place interactive content or critical information across the hinge area.” A vertical hinge (book posture) keeps the wider side of the surface's page, the leading side on a tie; a horizontal hinge (tabletop) always keeps the part **below** it, whichever half is larger, and only a page that ends inside the hinge keeps the part above. Flat folds keep the ordinary placement. The rule lives once in `core/nav/HingeSide.kt` (`HingeSide.keep` / `HingeSide.padding`, page-rectangle aware); `SheetHinge`, `DialogHinge` and `serviceStatusHingeSide` only adapt its result to sheet padding, a centring area or page padding. Agent decision (#140, design review of #212): one shared helper after the three surfaces' copies drifted on tabletop; the owner may override.
- **R9. Size centred dialogs from the window (Android).** `FestivalModalDialog` always takes the window width less 16 dp margins, capped at 560 dp (Material 3: “Centered dialog (max 560dp wide)”), and never the platform's preferred dialog width (`usePlatformDefaultWidth`), which measured 320 dp in a 923 dp landscape phone window. First run (#139) fixed this for itself with a `compact` flag; #183 found What's New and Privacy Policy still 320 dp wide on landscape phones and moved the rule into the shell, removing the flag. Feature dialogs never set their own width.
- **R10. Hold the page's decorative motion while a modal covers it (Android).** Every Festival modal registers with `ModalCoverage` through `CoversBackdrop` (the shell does it; the feedback form, the R6 exception, wraps its own `Dialog` in it) and gives its window one more `LocalModalDepth`. Content behind the newest modal reads `coveredByModal()` and holds a still frame: the shared backdrop (#83), the `FestivalMarqueeText` scroll (held at its start, semantics `Held`), the Songs/Shop pulse and breathe (their reduced-motion frame), the first-run demo pulse and the service-status pulse. The newest modal's own content keeps animating (the first-run demos run inside the tour; a confirmation alert holds the sheet beneath it). Material 3 modal dialogs and sheets “block interaction” and sit over a scrim, so the page's loops are unseen work: a clipped leaderboard name kept the Leaderboards page drawing every vsync (837 frames in 15 s) behind the first-run tour on the FST_Phone emulator. Each consumer has a Robolectric regression that opens a real Festival modal over it and checks the held frame and the resume (`FestivalModalTest`, `MarqueeTextTest`, `ShopMotionHoldTest`; the first-run and service-status pulses sample their drawn alpha through the internal `LocalMotionProbe`, `null` in the app, in `FirstRunDemoPulseHoldTest` and `ServiceStatusUiTest`), so a new loop that reads `coveredByModal()` adds one too. Agent decision (#186): Android holds every covered page loop, not just the backdrop #83 asked for; Apple and Windows keep their own #28/#83 scope until checked. The owner may override.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Sheet/dialog shell | `apple/Sources/FestivalUI/Design/FestivalModal.swift` `FestivalModal` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalModal.kt` `FestivalModalSheet`, `FestivalModalDialog` | `windows/Festival.App/Controls/FestivalDialog.cs` `FestivalDialog` |
| Standard Close | `apple/Sources/FestivalUI/Design/SheetStyle.swift` `FestivalSheetCloseItem` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalModal.kt` `FestivalModalCloseButton` | `windows/Festival.App/Controls/FestivalDialog.cs` `Create` |
| Confirmation | `apple/Sources/FestivalUI/Design/FestivalModal.swift` `FestivalModal` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalModal.kt` `FestivalAlertDialog` | `windows/Festival.App/Controls/FestivalDialog.cs` `ShowAsync` |
| Separating-hinge side (R8) | — (Duo layouts: [design/apple/duo.md](../design/apple/duo.md)) | `android/app/src/main/java/com/festivalscoretracker/android/core/nav/HingeSide.kt` `HingeSide` | — (no hinge posture) |
| Covered page holds its motion (R10) | — (backdrop only: #28) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalModal.kt` `CoversBackdrop`, `coveredByModal` | — (backdrop only: #83) |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| None verified. | — | Keep the shared-shell guards enabled; the feedback form is the documented R6 exception. |

## Guards (tools/pattern_guard.py)

- `modal-shell/windows-content-dialog`
- `modal-shell/android-bottom-sheet`
- `modal-shell/android-alert-dialog`
- `modal-shell/apple-manual-modal-close` (precise single-line `ToolbarItem` Close/xmark forms; current-tree scan has no outside-`Design/` match)
- `modal-shell/android-hinge-side` (a new `…HingeSide/Insets/Area/Padding` function outside `core/nav` and the three adapters)
- `modal-shell/android-dialog-platform-width` (any `usePlatformDefaultWidth` other than `false`, R9)
