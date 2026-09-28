#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - LicensesScreen

/// `/settings/licenses` renders its "no external dependencies" footnote (this build
/// currently has zero third-party SwiftPM packages) alongside the bundled-assets
/// section, which always has at least the instrument iconography entry.
@MainActor
@Test func licensesScreenRendersEmptyThirdPartyAndBundledAssetsSections() throws {
    #expect(LicenseManifest.thirdPartySoftware.isEmpty)
    #expect(LicenseManifest.bundledAssets.count == 1)
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        LicensesScreen(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "licenses.png", environment: "FST_LICENSES_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}
#endif
