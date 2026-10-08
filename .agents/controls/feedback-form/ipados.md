# Feedback form — iPad notes

> **What:** how the feedback form differs on iPad from the [iPhone design](ios.md). **Read when:** changing the feedback form on iPad. Spec: [spec.md](spec.md).

| Aspect | iPad |
|---|---|
| Surface | Same SwiftUI sheet. At regular width it opens page-sized (`festivalSheet(.large, sizing: .regularPage)`), not as the form card other sheets use, so the photo library has room beside it (#373, [modal-shell](../../patterns/modal-shell.md) R11). A presented sheet keeps the sizing it opened with: switching `presentationSizing` while open, or `.form.fitted`, does not resize it (tested). Compact-width windows (Slide Over, narrow Split View) keep the iPhone layout. HIG Sheets: "Prefer page or form sheet styles in an iPadOS app" |
| Platform label | `ipados` (`UIDevice.userInterfaceIdiom == .pad`) |
| Media | At regular width Attach Media › Photo Library opens the system `PhotosPicker` **inline** in a pane beside the form (`.photosPickerStyle(.inline)`, `.continuousAndOrdered`, `photoLibrary: .shared()`, selection actions hidden). Ticking attaches, unticking removes, removing a thumbnail unticks (`FeedbackPickerLinks`); refused picks untick again. The pane has a "Photo Library" header and a "Hide" button (`fst.settings.feedback.library`, `.library.hide`); the menu item reads "Hide Photo Library" while it is open. Choose File… still presents the Files picker: UIKit/SwiftUI have no public inline document browser. Drag photos, videos or image/movie files from Photos, Files or another app onto the form to attach them (`fst.settings.feedback.drop` highlight). HIG Designing for iPadOS: "minimize modal interfaces … keeping controls reachable without obscuring content"; Entering data: "As much as possible, support drag and drop and paste" |
| Keyboard | Hardware keyboard Escape triggers Cancel (`.cancellationAction`), so the discard confirmation still applies |
