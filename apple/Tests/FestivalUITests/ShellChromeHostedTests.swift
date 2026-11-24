#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Sessions

/// A session with no client access needed (the drawer itself never reads the network).
@MainActor
private func anonymousDrawerSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

/// A session with a stored selected player, matching the pattern used by
/// `PlayerHistoryNotificationsRenderTests.hostedHistorySession`.
@MainActor
private func selectedPlayerDrawerSession() -> FestivalSession {
    let suite = "fst.tests.shell.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(
        Data("""
        {"accountId":"fixture-1","displayName":"Fixture Player"}
        """.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }, selectionStorage: defaults
    )
}

// MARK: - Root profile button / avatar

/// The top-right action shows an add-profile glyph when anonymous and the
/// player's monogram once selected — the same avatar used in the toolbar capsule
/// (`RootChrome.swift`'s `RootProfileButton`/`ProfileAvatar`).
@MainActor
@Test func rootProfileButtonSwitchesFromAddGlyphToAvatarInitial() throws {
    #expect(ProfileAvatar.initial(for: "Fixture Player") == "F")
    let anonymous = anonymousDrawerSession()
    let player = selectedPlayerDrawerSession()
    #expect(anonymous.selectedPlayer == nil)
    #expect(player.selectedPlayer?.displayName == "Fixture Player")
    let size = CGSize(width: 200, height: 60)
    for (session, label) in [(anonymous, "Choose Profile"), (player, "Profile: Fixture Player")] {
        let host = nativeHostedView(
            RootProfileButton(session: session, action: {})
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark),
            size: size
        )
        host.layoutSubtreeIfNeeded()
        let image = try nativeHostedImage(host)
        // A 200×60 control: most of the frame is intentionally empty.
        assertRendersContent(
            host, image: image, minimumNonBackgroundFraction: 0.05, containing: [label]
        )
    }
}
#endif
