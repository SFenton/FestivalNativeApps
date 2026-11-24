import FestivalCore
import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Page commands

/// Front-page commands and their availability, adapted by UIKit and native Mac menus.
struct PageToolMenuState {
    var page: PageMenuCommands?
    var rankBy: RankByMenuCommands?
    var instrument: InstrumentMenuCommands?
    var bandSize: BandSizeMenuCommands?
    var profile: ProfilePageMenuCommands?
    var song: SongMenuCommands?
    var experimentalRanks = ExperimentalRanks.defaultValue
    /// Covered pages cannot present another sheet.
    var blocked = false
}

/// Sort, Filter, Find Rival and List/Grid commands published by the current page.
struct PageMenuCommands: Equatable {
    var sort: (@MainActor () -> Void)?
    var filter: (@MainActor () -> Void)?
    var findRival: (@MainActor () -> Void)?
    var layout: PageMenuLayoutChoice?

    static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.sort == nil) == (rhs.sort == nil) && (lhs.filter == nil) == (rhs.filter == nil)
            && (lhs.findRival == nil) == (rhs.findRival == nil) && lhs.layout == rhs.layout
    }
}

/// The current view mode and action for the menu's List/Grid choices.
struct PageMenuLayoutChoice: Equatable {
    var isGrid: Bool
    var select: @MainActor (Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.isGrid == rhs.isGrid }
}

/// Song Detail's Paths and official Item Shop actions.
struct SongMenuCommands: Equatable {
    var songId: String
    var paths: (@MainActor () -> Void)?
    var shopURL: URL?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.songId == rhs.songId && (lhs.paths == nil) == (rhs.paths == nil) && lhs.shopURL == rhs.shopURL
    }
}

/// A player or rival page's actions for the Profile menu.
struct ProfilePageMenuCommands: Equatable {
    var identity: ProfileIdentityAction?
    var performIdentity: (@MainActor () -> Void)?
    var viewRivalProfile: (@MainActor () -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && (lhs.performIdentity == nil) == (rhs.performIdentity == nil)
            && (lhs.viewRivalProfile == nil) == (rhs.viewRivalProfile == nil)
    }

    /// - Parameter identity: The published action for the profile being viewed.
    /// - Returns: The action title, distinct from the top-level Select Profile command.
    static func identityMenuTitle(for identity: ProfileIdentityAction?) -> String {
        identity == .switchTo ? "Switch to This Profile" : "Select This Profile"
    }
}

// MARK: - Rankings

/// The enabled metrics and selection for a page's Rank By menu.
struct RankByMenuCommands: Equatable {
    struct Option: Equatable, Identifiable {
        let id: String
        let label: String
    }

    let options: [Option]
    let selected: String
    let select: @MainActor (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.options == rhs.options && lhs.selected == rhs.selected
    }

    /// - Parameter experimentalRanks: Whether Settings enables experimental metrics.
    /// - Returns: The enabled account metrics in menu order.
    static func accountOptions(experimentalRanks: Bool) -> [Option] {
        RankingMetric.enabled(experimentalRanks: experimentalRanks).map { Option(id: $0.rawValue, label: $0.label) }
    }

    /// - Parameter experimentalRanks: Whether Settings enables experimental metrics.
    /// - Returns: The enabled band metrics in menu order.
    static func bandOptions(experimentalRanks: Bool) -> [Option] {
        BandRankingMetric.enabled(experimentalRanks: experimentalRanks).map { Option(id: $0.rawValue, label: $0.label) }
    }
}

/// The enabled charts and selection for a page's Instrument menu.
struct InstrumentMenuCommands: Equatable {
    struct Option: Equatable, Identifiable {
        let id: String
        let label: String
    }

    let options: [Option]
    let selected: String
    let select: @MainActor (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.options == rhs.options && lhs.selected == rhs.selected
    }

    /// - Parameter instruments: The page's selectable charts.
    /// - Returns: One option per chart, in input order and keyed by wire id.
    static func options(for instruments: [Instrument]) -> [Option] {
        instruments.map { Option(id: $0.rawValue, label: $0.label) }
    }

    /// The disabled options shown when no rankings page is in front.
    static let allOptions = options(for: Instrument.allCases)
}

/// The selection and action for a board's Band Size menu.
struct BandSizeMenuCommands: Equatable {
    let selected: BandType
    let select: @MainActor (BandType) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.selected == rhs.selected }
}

// MARK: - Quick Links

/// A page's Quick Links for Go › Quick Links and Next/Previous Section.
struct QuickLinksMenuCommand: Equatable {
    let controller: QuickLinksController

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.controller === rhs.controller }

    /// - Parameters:
    ///   - active: The active section, if any.
    ///   - ids: Section ids in page order.
    ///   - offset: +1 for next, -1 for previous.
    /// - Returns: The target id, or nil when the command is disabled.
    static func neighbor(of active: String?, in ids: [String], offset: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let active, let index = ids.firstIndex(of: active) else {
            return offset > 0 ? ids.first : nil
        }
        let target = index + offset
        return ids.indices.contains(target) ? ids[target] : nil
    }
}

/// The devices that expose page commands through the system menu or shortcut overlay.
enum MenuBarCommandsSupport {
    @MainActor static var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}
