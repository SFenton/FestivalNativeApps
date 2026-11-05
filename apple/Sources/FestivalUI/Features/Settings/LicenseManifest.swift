import Foundation

// MARK: - LicenseManifest

/// One acknowledgeable third-party dependency shown on `LicensesScreen`.
///
/// Mirrors the shape of the web's generated `licenseManifest.ts`
/// (`FortniteFestivalWeb/src/generated/licenseManifest.ts`) closely enough that a future
/// build-time generator could target the same fields, but this app hand-maintains its own
/// (much shorter) list rather than importing the web's npm/NuGet manifest: none of that
/// JavaScript or .NET tooling ships inside the iOS binary, so including it here would
/// misrepresent what this app actually bundles.
struct SoftwareLicense: Identifiable, Hashable {
    let id: String
    let name: String
    /// Package version, or a short role description for a non-versioned entry.
    let versionOrRole: String
    let licenseType: String
    let licenseText: String
    let url: URL?
}

/// The native app's actual third-party software acknowledgements.
///
/// Licenses lists third-party software only: no bundled-asset section and no first-party
/// artwork entries (operator, 2026-09-28, batch 6 — `.agents/pages/licenses/spec.md`).
///
/// Source of truth for "actual dependencies": `apple/Package.swift` now references
/// the private, first-party `SFenton/FentonPlatform` foundation at commit
/// `0b9592686a90a89181e442cdc0f5058bca9af001`. It is not a third-party package and
/// has no redistribution license, so it does not become a row in this third-party
/// acknowledgements list. Add an entry here for any external package the same day it
/// lands so this screen never drifts from `Package.swift`/`Package.resolved`.
enum LicenseManifest {
    /// External SwiftPM packages. The private FentonPlatform foundation is first-party.
    static let thirdPartySoftware: [SoftwareLicense] = []
}
