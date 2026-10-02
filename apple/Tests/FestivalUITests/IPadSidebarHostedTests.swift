#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - iPad sidebar hosted renders

/// A session that never reaches the network, optionally with a selected player.
@MainActor
private func sidebarSession(player: Bool) throws -> FestivalSession {
    let identity = try player ? SelectedPlayerIdentity(searchResult: JSONDecoder().decode(
        PlayerSearchResult.self,
        from: Data(#"{"accountId":"fixture-player-1","displayName":"Fixture Player 1"}"#.utf8)
    )) : nil
    return FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }, selectionStorage: nil,
        debugSelectedPlayer: identity
    )
}

/// Render the sidebar column for a profile state and return its image and accessibility.
@MainActor
private func renderSidebar(
    player: Bool, hideShop: Bool, selected: FestivalSection, filename: String
) async throws -> NativeHostedAccessibility {
    let session = try sidebarSession(player: player)
    let size = CGSize(width: 320, height: 760)
    let view = NavigationStack {
        FestivalSidebar(
            session: session,
            browse: SidebarMenu.browse(profile: player ? .player : .none, hideShop: hideShop),
            selected: selected, onSelect: { _ in }, onOpenPlayer: { _ in }, onChooseProfile: {}
        )
    }
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let footer = player ? "Fixture Player 1" : "Select Profile"
    let image = try await nativeHostedSettle(host, untilText: ["Songs", "Leaderboards", footer, "Settings"])
    _ = try nativeHostedPNG(image, filename: filename, environment: "FST_SHELL_RENDER_OUT")
    return nativeHostedAccessibility(host)
}

/// Anonymous: Songs, Leaderboards, Item Shop, then Select Profile and Settings.
@MainActor
@Test func iPadSidebarAnonymousRows() async throws {
    let tree = try await renderSidebar(
        player: false, hideShop: false, selected: .songs, filename: "ipad-sidebar-anonymous.png"
    )
    #expect(tree.texts.contains("Item Shop"))
    #expect(!tree.texts.contains("Suggestions"))
    #expect(tree.identifiers.contains("fst.nav.settings"))
    #expect(tree.identifiers.contains("fst.profile.sidebar"))
}

/// Player: profile rows in web order, the player and Deselect in the footer; Hide Item
/// Shop drops the Item Shop row.
@MainActor
@Test func iPadSidebarPlayerRowsAndFooter() async throws {
    let tree = try await renderSidebar(
        player: true, hideShop: true, selected: .settings, filename: "ipad-sidebar-player.png"
    )
    for row in ["Suggestions", "Statistics", "Rivals", "Leaderboards", "Fixture Player 1", "Deselect"] {
        #expect(tree.contains(row), "missing \(row)")
    }
    #expect(!tree.texts.contains("Item Shop"))
    #expect(!tree.texts.contains("Compete"))
    #expect(tree.identifiers.contains("fst.nav.sidebar.deselect-profile"))
}
#endif
