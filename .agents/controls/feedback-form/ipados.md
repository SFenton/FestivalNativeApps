# Feedback form — iPad notes

> **What:** how the feedback form differs on iPad from the [iPhone design](ios.md). **Read when:** changing the feedback form on iPad. Spec: [spec.md](spec.md).

| Aspect | iPad |
|---|---|
| Surface | Same SwiftUI sheet; `festivalSheet(.large)` applies `presentationSizing(.form)` at regular width, so it is a centred form card rather than an edge-to-edge page. HIG Sheets (iPadOS): "Use a sheet for a scoped task; use a full-screen modal only for immersive content" |
| Platform label | `ipados` (`UIDevice.userInterfaceIdiom == .pad`) |
| Media | Same Photos picker / Files importer and Quick Look preview as iPhone |
| Keyboard | Hardware keyboard Escape triggers Cancel (`.cancellationAction`), so the discard confirmation still applies |
