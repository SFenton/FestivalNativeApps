#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Privacy policy sheet

/// Issue #98: the sheet renders the contract's effective date and every section title,
/// scrolled from the top, with each heading reachable by its identifier.
@MainActor
@Test func privacyPolicySheetRendersEverySection() async throws {
    let policy = PrivacyPolicy.current
    // Tall enough that the whole policy is laid out without scrolling.
    let size = CGSize(width: 620, height: 3200)
    let host = nativeHostedView(
        PrivacyPolicySheet(policy: policy)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let headings = policy.sections.map(\.title)
    let image = try await nativeHostedSettle(host, untilText: [policy.effectiveDateText] + headings)
    _ = try nativeHostedPNG(image, filename: "privacy-policy.png", environment: "FST_PRIVACY_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: [policy.effectiveDateText] + headings,
        notContaining: ["Done"]
    )
    let ids = nativeHostedAccessibility(host).identifiers
    for section in policy.sections {
        #expect(ids.contains("fst.privacy-policy.section.\(section.id)"), "missing heading \(section.id)")
    }
}
#endif
