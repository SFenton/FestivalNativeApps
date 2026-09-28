# licenses — iPhone notes

> **What:** what the iPhone Licenses page implements, native decisions and open gaps. **Read when:** changing Licenses on iPhone, or adding a SwiftPM dependency anywhere in `apple/`. Behavior: [spec.md](spec.md).

## Implementation

- `Features/Settings/LicenseManifest.swift` — a hand-maintained `SoftwareLicense` array (`thirdPartySoftware`, `bundledAssets`), not a generated import of the web's `licenseManifest.ts`: none of that JS/NuGet tooling ships inside the iOS binary, so reusing it would misrepresent what this app bundles.
- `thirdPartySoftware` is **empty** as of 2026-09-27: `apple/Package.swift` declares zero external SwiftPM packages (`FestivalCore`/`FestivalDesign`/`FestivalUI` are all first-party targets, no `Package.resolved` exists). The list renders an explanatory footnote instead of an empty card.
- `bundledAssets` lists the Instruments.xcassets iconography as a first-party attribution entry (copied from the operator's own website, not a third-party asset — see `AGENTS.md`'s "never bundle third-party album art" rule, which this satisfies by construction).
- `Features/Settings/LicensesScreen.swift` — one `FestivalGlassSection` per group; tapping a row presents `LicenseDetailSheet` (`festivalSheet(.large)`) with the full text in a monospaced, selectable `Text`. SwiftUI's `.sheet(item:)` returns focus/VoiceOver to the triggering row on dismiss, matching the web's modal.

## Decisions and gotchas

- **Keep this file in sync with `Package.swift`.** The day this app takes its first SwiftPM dependency, add its license to `thirdPartySoftware` in the same commit — do not let the list silently drift empty.
- No network calls, no `FestivalSession` dependency beyond the shared animated backdrop.

## Open (iPhone)

None currently tracked; revisit if a dependency is added or an app icon / font is licensed from a third party.
