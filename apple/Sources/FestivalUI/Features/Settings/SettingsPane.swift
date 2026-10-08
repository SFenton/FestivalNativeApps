import Foundation

// MARK: - Settings panes

/// The Mac Settings window's panes (HIG Settings › macOS: "Choosing Settings from the
/// App menu opens a window, typically a toolbar of related panes").
///
/// Each pane shows a subset of the one shared ``SettingsScreen`` with the same
/// settings, storage keys and accessibility identifiers; iPhone and iPad keep the
/// single long page (`pane == nil`), like the web.
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    /// Accessibility overrides, Item Shop, Leaderboards, Feedback, Reset.
    case general
    /// Song rows (icons, visual order), visible instruments and instrument metadata.
    case songs
    /// CHOpt path view and columns, and the invalid-score filter derived from paths.
    case paths
    /// First-run guide replay.
    case guides
    /// Service version, publication and fixture tools (Debug).
    case service
    /// App version, What's New and Licenses.
    case about

    /// UserDefaults key restoring the last pane (HIG Settings › macOS: "restore the
    /// last pane").
    static let storageKey = "fst.mac.settingsPane"

    var id: Self { self }

    /// Toolbar label and window title (HIG Settings › macOS: "title the window for
    /// its pane"; Toolbars: titles under 15 characters).
    var title: String {
        switch self {
        case .general: "General"
        case .songs: "Songs"
        case .paths: "Paths"
        case .guides: "Guides"
        case .service: "Service"
        case .about: "About"
        }
    }

    /// SF Symbol for the pane's toolbar button.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .songs: "music.note.list"
        case .paths: "point.topleft.down.to.point.bottomright.curvepath"
        case .guides: "sparkles"
        case .service: "server.rack"
        case .about: "info.circle"
        }
    }

    /// Stable accessibility identifier of the pane's toolbar button.
    var accessibilityIdentifier: String { "fst.settings.pane.\(rawValue)" }

    /// The pane to show at launch: the stored one, else General.
    ///
    /// - Parameter raw: The stored raw value, if any.
    /// - Returns: A valid pane.
    static func restored(from raw: String?) -> SettingsPane {
        raw.flatMap(SettingsPane.init(rawValue:)) ?? .general
    }
}
