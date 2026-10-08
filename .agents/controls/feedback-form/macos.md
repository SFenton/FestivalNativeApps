# Feedback form — Mac notes

> **What:** how the feedback form differs on macOS from the [iPhone design](ios.md). **Read when:** changing the feedback form on the Mac. Spec: [spec.md](spec.md).

| Aspect | Mac |
|---|---|
| Entry | Settings window › **General** pane › **Feedback** section (Report an Issue, Request a Feature), shown only when `/api/features` reports `feedback: true`; the Mac has no App Settings card since Settings became panes. HIG Settings (macOS): "Choosing Settings from the App menu opens a window, typically a toolbar of related panes" |
| Surface | Window-modal sheet with the same grouped `Form`; Cancel is the cancellation action (Escape) and Submit the default confirmation action. HIG Sheets (macOS): "Present a sheet in a reasonable default size" |
| Platform label | `macos` |
| Media | Attach Media's Photo Library uses `PhotosPicker` (no permission); Choose File… uses the open panel via `.fileImporter`. The app is not sandboxed, so security-scoped access is a no-op. Both stay presented (#373): the sheet keeps `.form` sizing at its reasonable default size, and macOS has no inline open panel. Drag images, movies or files from Finder, Photos or Preview onto the sheet to attach them (same limits; accent outline and "Drop to Attach" while over it). Drop is verified by build and `FeedbackFormModelTests`: the Mac host has Automation Mode off, so no GUI drag test runs |
| Opening media | `NSWorkspace.shared.open` hands the copy to the default app (Preview, QuickTime Player); no Quick Look panel and no in-app player |
| Discard | No swipe on Mac; Cancel/Escape with input shows the same confirmation |
