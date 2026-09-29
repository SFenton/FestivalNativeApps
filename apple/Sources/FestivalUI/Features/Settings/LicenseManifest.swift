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
/// Source of truth for "actual dependencies": `apple/Package.swift` declares **zero**
/// external SwiftPM packages (checked 2026-09-27) — `FestivalCore`, `FestivalDesign` and
/// `FestivalUI` are all first-party targets. Add an entry here the same day a package
/// dependency lands so this screen never drifts from `Package.swift`/`Package.resolved`.
enum LicenseManifest {
    /// External SwiftPM packages. Empty until the app takes its first dependency.
    static let thirdPartySoftware: [SoftwareLicense] = []
}
