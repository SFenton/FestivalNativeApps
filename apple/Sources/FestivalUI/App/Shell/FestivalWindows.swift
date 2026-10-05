import SwiftUI
import FestivalCore
#if os(iOS)
import UIKit
#endif

// MARK: - Window routes

/// What an iPad "Open in New Window" request opens (`WindowGroup(for:)` value, so it
/// is `Codable` and survives window restoration). Only stable identifiers travel: a
/// song window looks its song up in the shared session's catalogue.
///
/// HIG Windows: "Consider offering a context-menu or File-menu command to view content
/// in a new window"; "Choose the right moment to open a new window ... avoid it as
/// default behavior" — the app never opens one by itself.
public enum FestivalWindowRoute: Codable, Hashable, Sendable {
    /// Song Detail for a catalogue song id.
    case song(songId: String)
    /// A player's profile.
    case player(accountId: String, displayName: String?)

    /// The destination the window opens on.
    var section: FestivalSection {
        switch self {
        case .song: .songs
        case .player: .leaderboards
        }
    }

    /// The route pushed at launch, when it needs no lookup (players).
    var immediateRoute: AppRoute? {
        switch self {
        case .song: nil
        case let .player(accountId, displayName): .player(accountId: accountId, displayName: displayName)
        }
    }
}

// MARK: - Open in New Window

extension View {
    /// iPad: a context menu with **Open in New Window** for a row showing `route`
    /// (HIG Windows, iPadOS). A no-op where the system cannot open windows (iPhone),
    /// so phone rows keep their plain tap behaviour.
    ///
    /// - Parameter route: The content the new window shows.
    /// - Returns: The row.
    func openInNewWindowMenu(_ route: FestivalWindowRoute) -> some View {
        modifier(OpenInNewWindowMenu(entries: [(nil, route)]))
    }

    /// iPad: one context menu for a list row that shows several items side by side (the
    /// Songs landscape grid), with an **Open “Title” in New Window** item per item. A
    /// `List` row honours only one context menu, so each card cannot carry its own.
    ///
    /// - Parameter entries: Each item's title and window route, in row order.
    /// - Returns: The row.
    func openInNewWindowMenu(_ entries: [(title: String, route: FestivalWindowRoute)]) -> some View {
        modifier(OpenInNewWindowMenu(entries: entries.count == 1
            ? [(nil, entries[0].route)] : entries.map { (Optional($0.title), $0.route) }))
    }
}

/// Context menu behind ``SwiftUI/View/openInNewWindowMenu(_:)``.
private struct OpenInNewWindowMenu: ViewModifier {
    /// The routes to offer; a nil title reads "Open in New Window".
    let entries: [(title: String?, route: FestivalWindowRoute)]
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        #if os(iOS)
        if supportsMultipleWindows && UIDevice.current.userInterfaceIdiom == .pad {
            content.contextMenu {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Button(
                        entry.title.map { "Open “\($0)” in New Window" } ?? "Open in New Window",
                        systemImage: "macwindow.badge.plus"
                    ) {
                        openWindow(value: entry.route)
                    }
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
