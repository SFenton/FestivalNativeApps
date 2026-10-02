# licenses — iPhone notes

> **What:** what the iPhone Licenses page implements, native decisions and open gaps. **Read when:** changing Licenses on iPhone, or adding a SwiftPM dependency anywhere in `apple/`. Behavior: [spec.md](spec.md).

## Implementation

- `Features/Settings/LicenseManifest.swift` — a hand-maintained `SoftwareLicense` array (`thirdPartySoftware` only), not a generated import of the web's `licenseManifest.ts`: none of that JS/NuGet tooling ships inside the iOS binary, so reusing it would misrepresent what this app bundles.
- `thirdPartySoftware` is **empty** as of 2026-09-27: `apple/Package.swift` declares zero external SwiftPM packages (`FestivalCore`/`FestivalDesign`/`FestivalUI` are all first-party targets, no `Package.resolved` exists). The list renders an explanatory footnote instead of an empty card.
- No Bundled Assets section and no iconography entry (operator batch 6); the star images are never mentioned.
- `Features/Settings/LicensesScreen.swift` — one "Third-Party Software" card in Settings' readable, centred column (`ReadableWidthContainer`), fading in; rows show a chevron and a pressed highlight (`LicenseRowButtonStyle`); tapping presents `LicenseDetailSheet` (`festivalSheet(.large)`) with monospaced selectable text, built on the shared `FestivalModal` (system toolbar Close top-right, `fst.licenses.close`; issue #23 removed the bottom full-width Close). SwiftUI's `.sheet(item:)` returns focus to the triggering row. `entries:` is injectable for hosted tests (`LicensesHostedTests.swift`).
- Settings links here with the web's standalone row (title + description + chevron, `fst.settings.licenses`).

## Decisions and gotchas

- **Keep this file in sync with `Package.swift`.** The day this app takes its first SwiftPM dependency, add its license to `thirdPartySoftware` in the same commit — do not let the list silently drift empty.
- No network calls, no `FestivalSession` dependency beyond the shared animated backdrop.

## Open (iPhone)

None currently tracked; revisit if a dependency is added or an app icon / font is licensed from a third party.
