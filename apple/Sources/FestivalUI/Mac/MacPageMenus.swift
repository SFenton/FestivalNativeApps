import SwiftUI
import FestivalCore
#if os(iOS)
import UIKit
#endif

// MARK: - Rank By

/// A rankings page's Rank By choice for View › Rank By (HIG Toolbars › macOS: "Every
/// toolbar item must also be a menu-bar command"; Menus: "Consider a checkmark to show
/// an attribute is in effect").
struct MacRankByCommands: Equatable {
    /// One metric.
    struct Option: Equatable, Identifiable {
        let id: String
        let label: String
    }

    /// The page's metrics in menu order.
    let options: [Option]
    /// The metric in effect.
    let selected: String
    /// Applies a metric by id.
    let select: @MainActor (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.options == rhs.options && lhs.selected == rhs.selected
    }

    /// The account metrics (Leaderboards, Full Rankings) Settings › Experimental Ranks
    /// enables (Total Score alone while off; pattern `experimental-ranks`), shown
    /// disabled when no rankings page is in front so the submenu keeps its items (HIG
    /// Menus: "Make sure a submenu remains available even when its items are
    /// unavailable").
    ///
    /// - Parameter experimentalRanks: The Settings switch.
    /// - Returns: One option per enabled metric, in menu order.
    static func accountOptions(experimentalRanks: Bool) -> [Option] {
        RankingMetric.enabled(experimentalRanks: experimentalRanks).map { Option(id: $0.rawValue, label: $0.label) }
    }

    /// The band metrics (Band Rankings, Band Detail) Settings › Experimental Ranks
    /// enables (no Max Score; Total Score alone while off).
    ///
    /// - Parameter experimentalRanks: The Settings switch.
    /// - Returns: One option per enabled band metric, in menu order.
    static func bandOptions(experimentalRanks: Bool) -> [Option] {
        BandRankingMetric.enabled(experimentalRanks: experimentalRanks).map { Option(id: $0.rawValue, label: $0.label) }
    }
}

// MARK: - Instrument

/// A rankings page's instrument switcher for View › Instrument (issue #294: the Full
/// Rankings instrument menu is a toolbar item, and HIG Toolbars › macOS says "Every
/// toolbar item must also be a menu-bar command").
struct MacInstrumentCommands: Equatable {
    /// One chart.
    struct Option: Equatable, Identifiable {
        let id: String
        let label: String
    }

    /// The page's selectable charts in menu order.
    let options: [Option]
    /// The chart in effect.
    let selected: String
    /// Applies a chart by id.
    let select: @MainActor (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.options == rhs.options && lhs.selected == rhs.selected
    }

    /// Menu options for the given charts, in their order.
    ///
    /// - Parameter instruments: The page's selectable charts.
    /// - Returns: One option per chart, keyed by its wire id.
    static func options(for instruments: [Instrument]) -> [Option] {
        instruments.map { Option(id: $0.rawValue, label: $0.label) }
    }

    /// Every chart, shown disabled when no rankings page is in front so the submenu
    /// keeps its items (HIG Menus: "Make sure a submenu remains available even when its
    /// items are unavailable").
    static let allOptions = options(for: Instrument.allCases)
}

// MARK: - Quick Links

/// A page's Quick Links for Go › Quick Links and Next/Previous Section.
struct MacQuickLinksCommand: Equatable {
    let controller: QuickLinksController

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.controller === rhs.controller }

    /// The section a Next/Previous Section command jumps to.
    ///
    /// - Parameters:
    ///   - ids: Section ids in page order.
    ///   - active: The active section, if any.
    ///   - offset: +1 for next, −1 for previous.
    /// - Returns: The target id, or nil at either end (the command is disabled).
    static func neighbor(of active: String?, in ids: [String], offset: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let active, let index = ids.firstIndex(of: active) else {
            return offset > 0 ? ids.first : nil
        }
        let target = index + offset
        return ids.indices.contains(target) ? ids[target] : nil
    }
}

// MARK: - Publishing (every platform)

extension View {
    /// Publish an account rankings page's Rank By to View › Rank By (macOS and the
    /// iPadOS menu bar; a no-op on iPhone).
    ///
    /// - Parameters:
    ///   - selection: The page's metric.
    ///   - experimentalRanks: Settings › Experimental Ranks; while off only Total Score
    ///     is listed (pattern `experimental-ranks`).
    /// - Returns: The view.
    func macRankByCommands(_ selection: Binding<RankingMetric>, experimentalRanks: Bool) -> some View {
        modifier(MacRankByPublisher(commands: MacRankByCommands(
            options: MacRankByCommands.accountOptions(experimentalRanks: experimentalRanks),
            selected: selection.wrappedValue.coerced(experimentalRanks: experimentalRanks).rawValue,
            select: { id in RankingMetric(rawValue: id).map { selection.wrappedValue = $0 } }
        )))
    }

    /// Publish a band rankings page's Rank By to View › Rank By (no Max Score; a no-op
    /// on iPhone).
    ///
    /// - Parameters:
    ///   - selection: The page's band metric.
    ///   - experimentalRanks: Settings › Experimental Ranks; while off only Total Score
    ///     is listed (pattern `experimental-ranks`).
    /// - Returns: The view.
    func macRankByCommands(_ selection: Binding<BandRankingMetric>, experimentalRanks: Bool) -> some View {
        modifier(MacRankByPublisher(commands: MacRankByCommands(
            options: MacRankByCommands.bandOptions(experimentalRanks: experimentalRanks),
            selected: selection.wrappedValue.coerced(experimentalRanks: experimentalRanks).rawValue,
            select: { id in BandRankingMetric(rawValue: id).map { selection.wrappedValue = $0 } }
        )))
    }

    /// Publish a rankings page's instrument switcher to View › Instrument (macOS and
    /// the iPadOS menu bar; a no-op on iPhone).
    ///
    /// - Parameters:
    ///   - instruments: The charts the page's own menu offers, in order.
    ///   - selection: The page's chart.
    /// - Returns: The view.
    func macInstrumentCommands(_ instruments: [Instrument], selection: Binding<Instrument>) -> some View {
        modifier(MacInstrumentPublisher(commands: MacInstrumentCommands(
            options: MacInstrumentCommands.options(for: instruments),
            selected: selection.wrappedValue.rawValue,
            select: { id in Instrument(rawValue: id).map { selection.wrappedValue = $0 } }
        )))
    }
}

private struct MacRankByCommandsKey: FocusedValueKey {
    typealias Value = MacRankByCommands
}

private struct MacInstrumentCommandsKey: FocusedValueKey {
    typealias Value = MacInstrumentCommands
}

private struct MacQuickLinksPageKey: FocusedValueKey {
    typealias Value = MacQuickLinksCommand
}

private struct MacQuickLinksListKey: FocusedValueKey {
    typealias Value = MacQuickLinksCommand
}

extension FocusedValues {
    /// The front rankings page's Rank By.
    var macRankBy: MacRankByCommands? {
        get { self[MacRankByCommandsKey.self] }
        set { self[MacRankByCommandsKey.self] = newValue }
    }

    /// The front rankings page's instrument switcher.
    var macInstrument: MacInstrumentCommands? {
        get { self[MacInstrumentCommandsKey.self] }
        set { self[MacInstrumentCommandsKey.self] = newValue }
    }

    /// Quick Links of the page in the detail (or only) column.
    var macQuickLinksPage: MacQuickLinksCommand? {
        get { self[MacQuickLinksPageKey.self] }
        set { self[MacQuickLinksPageKey.self] = newValue }
    }

    /// Quick Links of the page in a split's list column (used when the detail has none).
    var macQuickLinksList: MacQuickLinksCommand? {
        get { self[MacQuickLinksListKey.self] }
        set { self[MacQuickLinksListKey.self] = newValue }
    }
}

/// Publishes Rank By only from the top page of its column, and not from the list beside
/// an open trailing pane (Leaderboards beside Full Rankings, issue #352: the detail wins).
private struct MacRankByPublisher: ViewModifier {
    let commands: MacRankByCommands
    @Environment(\.macPageIsTop) private var isTop
    @Environment(\.macColumnIsList) private var isList

    func body(content: Content) -> some View {
        if MenuBarCommandsSupport.isAvailable {
            content.focusedSceneValue(\.macRankBy, isTop && !isList ? commands : nil)
        } else {
            content
        }
    }
}

/// Publishes the instrument switcher only from the top page of its column, and not from
/// the list beside an open trailing pane (the detail wins, as for Rank By).
private struct MacInstrumentPublisher: ViewModifier {
    let commands: MacInstrumentCommands
    @Environment(\.macPageIsTop) private var isTop
    @Environment(\.macColumnIsList) private var isList

    func body(content: Content) -> some View {
        if MenuBarCommandsSupport.isAvailable {
            content.focusedSceneValue(\.macInstrument, isTop && !isList ? commands : nil)
        } else {
            content
        }
    }
}

/// Publishes a `.quickLinks` container's controller from the top page of its column,
/// keyed by column so the detail page's sections win over the list's.
struct MacQuickLinksPublisher: ViewModifier {
    let controller: QuickLinksController
    @Environment(\.macPageIsTop) private var isTop
    @Environment(\.macColumnIsList) private var isList

    func body(content: Content) -> some View {
        let command = isTop ? MacQuickLinksCommand(controller: controller) : nil
        if MenuBarCommandsSupport.isAvailable {
            content
                .focusedSceneValue(\.macQuickLinksPage, isList ? nil : command)
                .focusedSceneValue(\.macQuickLinksList, isList ? command : nil)
        } else {
            content
        }
    }
}

// MARK: - Availability

extension EnvironmentValues {
    /// Whether the page is the top of its column's stack (menu commands publish only
    /// from the top page; a page under a push stays alive). macOS and iPad.
    @Entry var macPageIsTop = true
    /// Whether the page is in a split's list column (Quick Links prefer the detail).
    @Entry var macColumnIsList = false
}

/// Where page menu-bar commands are published: macOS, and iPad (iPadOS menu bar and
/// the ⌘-hold shortcut overlay). Never on iPhone, which has no menu bar, so phone
/// pages publish nothing (`.agents/design/apple/ipados.md`, Menu bar).
enum MenuBarCommandsSupport {
    /// Whether this device shows menu-bar commands.
    @MainActor static var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

#if os(iOS)
/// Publishes a page's menu-bar value from the top page of its column only (a page
/// under a push, or in an unselected tab, stays alive in iOS navigation), and only on
/// iPad.
struct MenuBarTopPagePublisher<Published>: ViewModifier {
    let keyPath: WritableKeyPath<FocusedValues, Published?>
    let value: Published
    @Environment(\.macPageIsTop) private var isTop

    func body(content: Content) -> some View {
        if MenuBarCommandsSupport.isAvailable {
            let published: Published? = isTop ? value : nil
            content.focusedSceneValue(keyPath, published)
        } else {
            content
        }
    }
}
#endif

