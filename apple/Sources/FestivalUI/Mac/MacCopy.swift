import Foundation
import FestivalCore
#if os(macOS)
import AppKit
#endif

// MARK: - Copy policy

/// What Edit › Copy (⌘C) copies when no text is focused: the name of the selected row
/// (HIG The menu bar › Edit menu: "Copy … To the Clipboard"; the system implements
/// Copy for selected text in standard text fields, which keep precedence).
enum MacCopyPolicy {
    /// The text for a route: a song's title, a player's, band's or rival's name.
    ///
    /// - Parameter route: The selected (or shown) route.
    /// - Returns: The text to copy, or nil when the route names nothing.
    static func text(for route: AppRoute) -> String? {
        let text: String?
        switch route {
        case let .songDetail(song), let .songLeaderboard(song, _, _, _),
             let .songBandLeaderboard(song, _, _, _), let .playerHistory(song, _):
            text = song.title
        case let .player(_, name), let .playerBands(_, name, _):
            text = name
        case let .band(_, name, _, _):
            text = name
        case let .rivalDetail(_, name, _), let .rivalry(_, _, name, _):
            text = name
        default:
            text = nil
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The route whose name Copy uses: the open item while the trailing pane shows it,
    /// else the page on top of the destination's path.
    ///
    /// - Parameters:
    ///   - path: The selected destination's path.
    ///   - section: Its shared section (split rules), nil for Item Shop.
    ///   - split: Whether the trailing pane is open.
    /// - Returns: The route, or nil at a destination root.
    static func selectedRoute(path: [AppRoute], section: FestivalSection?, split: Bool) -> AppRoute? {
        if split, let section, let selection = OnDemandSplitPolicy.cut(section: section, path: path)?.selection {
            return selection
        }
        return path.last
    }

    #if os(macOS)
    /// Put text on a pasteboard.
    ///
    /// - Parameters:
    ///   - text: Plain text to copy.
    ///   - pasteboard: The general pasteboard (tests pass a private one).
    @MainActor static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    #endif
}

#if os(macOS)
// MARK: - Window responder

/// A responder after the main window in its responder chain that answers the standard
/// Edit › Copy (`copy:`) with the selected row's name when nothing earlier in the
/// chain (a focused text field) handles it. Keeping the system Edit menu keeps its
/// validation: Copy is disabled when there is neither selected text nor a selection
/// (HIG The menu bar: "Disable, don't hide, unavailable items").
final class MacSelectionCopyResponder: NSResponder {
    /// Supplies the selected row's text (nil when nothing is selected).
    var selectionText: @MainActor () -> String? = { nil }
    /// Where Copy writes (the general pasteboard; tests pass a private one).
    var pasteboard: NSPasteboard = .general

    @objc func copy(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let text = selectionText() else {
                NSSound.beep()
                return
            }
            MacCopyPolicy.copy(text, to: pasteboard)
        }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(copy(_:)) {
            return MainActor.assumeIsolated { selectionText() != nil }
        }
        return super.responds(to: aSelector)
    }
}
#endif
