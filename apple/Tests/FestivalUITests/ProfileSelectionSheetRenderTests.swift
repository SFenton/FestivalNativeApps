#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Paint the actual native profile sheet without issuing a public account request.
///
/// - Parameters:
///   - session: Anonymous or identity-only synthetic app session.
///   - size: Phone-like or wide native content dimensions.
///   - typeSize: Native text scaling used by the sheet and Close action.
/// - Returns: AppKit-hosted pixels, including real Form and segmented controls.
/// - Throws: A missing hosted rendering.
@MainActor
private func profileSheetImage(
    session: FestivalSession, size: CGSize,
    typeSize: DynamicTypeSize = .large
) throws -> CGImage {
    let host = nativeHostedView(
        ProfileSelectionSheet(session: session)
            .environment(\.dynamicTypeSize, typeSize)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue),
        size: size
    )
    return try nativeHostedImage(host)
}

/// Initial and stored-selection states paint distinct, readable sheets at two widths.
@MainActor
@Test func profileSheetPaintsAnonymousAndSelectedIdentityWithoutAService() throws {
    let suiteName = "fst-profile-render-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let viewed = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1"}
    """.utf8))
    let identity = try SelectedPlayerIdentity(searchResult: viewed)
    storage.set(try JSONEncoder().encode(identity), forKey: SelectedPlayerIdentity.storageKey)
    let anonymous = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let selected = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource },
        selectionStorage: storage
    )
    #expect(selected.selectedPlayer?.accountId == viewed.accountId)
    #expect(selected.selectedPlayerScores.isEmpty)

    for size in [CGSize(width: 390, height: 844), CGSize(width: 820, height: 1180)] {
        let initial = try profileSheetImage(session: anonymous, size: size)
        let chosen = try profileSheetImage(session: selected, size: size)
        let scale = CGFloat(initial.width) / size.width
        #expect((1...3).contains(scale))
        #expect(abs(CGFloat(initial.height) / size.height - scale) < 0.02)
        #expect(chosen.width == initial.width && chosen.height == initial.height)
        let anonymousPixels = nativeHostedControlPixels(initial)
        let chosenPixels = nativeHostedControlPixels(chosen)
        #expect(anonymousPixels.bright > 20 && anonymousPixels.selected > 40)
        #expect(chosenPixels.bright > anonymousPixels.bright)
        #expect(chosenPixels.selected > 40)
        #expect(anonymousPixels.placeholder == 0 && chosenPixels.placeholder == 0)
        let first = try nativeHostedPNG(
            initial, filename: "profile-anonymous-\(Int(size.width)).png",
            environment: "FST_PROFILE_RENDER_OUT"
        )
        let second = try nativeHostedPNG(
            chosen, filename: "profile-selected-\(Int(size.width)).png",
            environment: "FST_PROFILE_RENDER_OUT"
        )
        #expect(first != second)
    }

    let largeText = try profileSheetImage(
        session: selected, size: CGSize(width: 390, height: 844),
        typeSize: .accessibility5
    )
    #expect(abs(CGFloat(largeText.width) / 390
        - CGFloat(largeText.height) / 844) < 0.02)
    let largePixels = nativeHostedControlPixels(largeText)
    #expect(largePixels.bright > 20 && largePixels.selected > 40)
    #expect(largePixels.placeholder == 0)
    _ = try nativeHostedPNG(
        largeText, filename: "profile-selected-ax5.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
}

/// The same root profile action paints a real selected name rather than a generic icon.
@MainActor
@Test func profileActionPaintsDistinctSelectedAndAnonymousLabels() throws {
    let suiteName = "fst-profile-action-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-2","displayName":"Fixture Player 2"}
    """.utf8))
    storage.set(
        try JSONEncoder().encode(SelectedPlayerIdentity(searchResult: result)),
        forKey: SelectedPlayerIdentity.storageKey
    )
    let anonymous = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let selected = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }, selectionStorage: storage
    )
    func image(for session: FestivalSession) throws -> CGImage {
        let renderer = ImageRenderer(content:
            ProfileActionButton(session: session, onPress: {})
                .preferredColorScheme(.dark)
                .tint(BrandTokens.accentBlue)
                .frame(width: 260, height: 64)
                .background(BrandTokens.cardBackground)
        )
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }
    let initial = try image(for: anonymous)
    let chosen = try image(for: selected)
    #expect(initial.width == 260 && chosen.width == 260)
    #expect(paintedPixels(near: (45, 130, 230), in: chosen, sampleStep: 1) > 20)
    let first = try #require(
        NSBitmapImageRep(cgImage: initial).representation(using: .png, properties: [:])
    )
    let second = try #require(
        NSBitmapImageRep(cgImage: chosen).representation(using: .png, properties: [:])
    )
    #expect(first != second)
}
#endif
