#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - LicensesScreen

/// `/settings/licenses` renders its "no external dependencies" footnote (this build has
/// zero third-party SwiftPM packages) and, per the operator's batch-6 rule, no Bundled Assets
/// section and no instrument iconography entry.
@MainActor
@Test func licensesScreenRendersEmptyThirdPartyOnly() async throws {
    #expect(LicenseManifest.thirdPartySoftware.isEmpty)
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        NavigationStack { LicensesScreen(session: session) }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Third-Party Software", "no external Swift package dependencies"]
    )
    _ = try nativeHostedPNG(image, filename: "licenses.png", environment: "FST_LICENSES_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: ["Third-Party Software", "no external Swift package dependencies"],
        notContaining: ["Bundled Assets", "Iconography", "First-party"]
    )
}

/// A listed package shows its name, version and license badge as one tappable row.
@MainActor
@Test func licensesScreenRendersInjectedPackageRows() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let entry = SoftwareLicense(
        id: "example", name: "ExampleKit", versionOrRole: "SwiftPM · 1.2.3",
        licenseType: "MIT", licenseText: "Permission is hereby granted…", url: nil
    )
    let size = CGSize(width: 402, height: 500)
    let host = nativeHostedView(
        NavigationStack { LicensesScreen(session: session, entries: [entry]) }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["ExampleKit, SwiftPM · 1.2.3, MIT"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "licenses-row.png", environment: "FST_LICENSES_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected, notContaining: ["no external"])
}

/// The license text sheet renders its selectable text and no bottom Close/Done: Close is
/// the shared `FestivalModal`'s system toolbar button (issue #23), which the hosted AppKit
/// view has no window toolbar to draw. `ModalCloseJourneyTests` proves that Close on iOS for
/// every reachable modal (this one is unreachable while the license manifest is empty).
@MainActor
@Test func licenseDetailSheetRendersTextWithoutBottomClose() async throws {
    let text = Array(
        repeating: "Permission is hereby granted, free of charge, to any person obtaining a copy.",
        count: 12
    ).joined(separator: "\n")
    let entry = SoftwareLicense(
        id: "example", name: "ExampleKit", versionOrRole: "SwiftPM · 1.2.3",
        licenseType: "MIT", licenseText: text, url: nil
    )
    let size = CGSize(width: 402, height: 600)
    let host = nativeHostedView(
        LicenseDetailSheet(entry: entry)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Permission is hereby granted"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "license-detail.png", environment: "FST_LICENSES_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected, notContaining: ["Done"])
}
#endif
