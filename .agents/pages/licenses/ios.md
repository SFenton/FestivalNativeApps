# licenses — iPhone notes

> **What:** what the iPhone Licenses page implements, native decisions and open gaps. **Read when:** changing Licenses on iPhone, or adding a SwiftPM dependency anywhere in `apple/`. Behavior: [spec.md](spec.md).

## Implementation

- `Features/Settings/LicenseManifest.swift` — a hand-maintained `SoftwareLicense` array (`thirdPartySoftware` only), not a generated import of the web's `licenseManifest.ts`: none of that JS/NuGet tooling ships inside the iOS binary, so reusing it would misrepresent what this app bundles.
- `thirdPartySoftware` remains **empty**: the app's only new package reference is the private, first-party `SFenton/FentonPlatform` foundation pinned at `0b9592686a90a89181e442cdc0f5058bca9af001`. FentonPlatform's private repository has no redistribution license, so it is documented as an internal source provenance rather than shown as a third-party acknowledgement row. External packages must be added here when they land.
- No Bundled Assets section and no iconography entry (operator batch 6); the star images are never mentioned.
- `Features/Settings/LicensesScreen.swift` — one "Third-Party Software" card in Settings' readable, centred column (`ReadableWidthContainer`), fading in; rows show a chevron and a pressed highlight (`LicenseRowButtonStyle`); tapping presents `LicenseDetailSheet` (`festivalSheet(.large)`) with monospaced selectable text, built on the shared `FestivalModal` (system toolbar Close top-right, `fst.licenses.close`; issue #23 removed the bottom full-width Close). SwiftUI's `.sheet(item:)` returns focus to the triggering row. `entries:` is injectable for hosted tests (`LicensesHostedTests.swift`).
- Settings links here with the web's standalone row (title + description + chevron, `fst.settings.licenses`).

## Decisions and gotchas

- **Keep this file in sync with `Package.swift`.** The day this app takes its first SwiftPM dependency, add its license to `thirdPartySoftware` in the same commit — do not let the list silently drift empty.
- No network calls, no `FestivalSession` dependency beyond the shared animated backdrop.
- The UIKit Privacy Policy pilot is covered by the existing hosted selector
  `UKSettingsJourneyTests.testPrivacyPolicyOpensAsASheetAndCloses`, not by the
  Mac SwiftPM `FestivalUITests` target. Run it against the UIKit app with the
  loopback fixture origin (`--app uikit`).

## Open (iPhone)

None currently tracked; revisit if a dependency is added or an app icon / font is licensed from a third party.
