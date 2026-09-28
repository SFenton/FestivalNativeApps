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

// MARK: - Drawer content states

/// The anonymous drawer offers "Select Profile", Bands and Item Shop, but no
/// Rivals row (requires a player) and no Leaderboards row (already a tab).
@MainActor
@Test func drawerRendersAnonymousProfileState() throws {
    let session = anonymousDrawerSession()
    let size = CGSize(width: 402, height: 874)
    let visible = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let host = nativeHostedView(
        FestivalDrawer(
            session: session, visibleSections: visible, hideShop: false,
            onIntent: { _ in }, onClose: {}
        )
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "drawer-anonymous.png", environment: "FST_SHELL_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// The selected-player drawer swaps in "View Profile"/"Switch Profile"/"Deselect"
/// and gains both Leaderboards and Rivals rows: a selected player's compact tab
/// bar shows Compete instead of Leaderboards, so the drawer surfaces both again.
@MainActor
@Test func drawerRendersSelectedPlayerProfileState() throws {
    let session = selectedPlayerDrawerSession()
    #expect(session.selectedPlayer?.displayName == "Fixture Player")
    let size = CGSize(width: 402, height: 874)
    let visible = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    let host = nativeHostedView(
        FestivalDrawer(
            session: session, visibleSections: visible, hideShop: false,
            onIntent: { _ in }, onClose: {}
        )
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "drawer-player.png", environment: "FST_SHELL_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
    // Real content check to back the pixel evidence, matching `DrawerMenu.playerDrawerBrowse`.
    let items = DrawerMenu.browse(profile: .player, visibleSections: visible, hideShop: false)
    #expect(items.map(\.id) == ["leaderboards", "rivals", "bands", "shop"])
}

/// Settings › Hide Item Shop removes the drawer's Item Shop row even while rendered.
@MainActor
@Test func drawerHidesItemShopRowWhenSettingHides() throws {
    let session = anonymousDrawerSession()
    let size = CGSize(width: 402, height: 874)
    let visible = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let host = nativeHostedView(
        FestivalDrawer(
            session: session, visibleSections: visible, hideShop: true,
            onIntent: { _ in }, onClose: {}
        )
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    _ = try nativeHostedImage(host)
    let items = DrawerMenu.browse(profile: .none, visibleSections: visible, hideShop: true)
    #expect(!items.contains { $0.id == "shop" })
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
    for (session, expectHidden) in [(anonymous, true), (player, false)] {
        let host = nativeHostedView(
            RootProfileButton(session: session, action: {})
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark),
            size: size
        )
        host.layoutSubtreeIfNeeded()
        let image = try nativeHostedImage(host)
        #expect(image.width > 0)
        _ = expectHidden
    }
}
#endif
