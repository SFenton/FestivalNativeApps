import SwiftUI
import FestivalCore

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

    /// The account metrics (Leaderboards, Full Rankings), shown disabled when no
    /// rankings page is in front so the submenu keeps its items (HIG Menus: "Make sure
    /// a submenu remains available even when its items are unavailable").
    static let accountOptions = RankingMetric.allCases.map { Option(id: $0.rawValue, label: $0.label) }
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
    /// Publish an account rankings page's Rank By to View › Rank By (a no-op on
    /// iPhone and iPad).
    ///
    /// - Parameter selection: The page's metric.
    /// - Returns: The view.
    func macRankByCommands(_ selection: Binding<RankingMetric>) -> some View {
        #if os(macOS)
        modifier(MacRankByPublisher(commands: MacRankByCommands(
            options: MacRankByCommands.accountOptions, selected: selection.wrappedValue.rawValue,
            select: { id in RankingMetric(rawValue: id).map { selection.wrappedValue = $0 } }
        )))
        #else
        self
        #endif
    }

    /// Publish a band rankings page's Rank By to View › Rank By (no Max Score; a no-op
    /// on iPhone and iPad).
    ///
    /// - Parameter selection: The page's band metric.
    /// - Returns: The view.
    func macRankByCommands(_ selection: Binding<BandRankingMetric>) -> some View {
        #if os(macOS)
        modifier(MacRankByPublisher(commands: MacRankByCommands(
            options: BandRankingMetric.allCases.map { .init(id: $0.rawValue, label: $0.label) },
            selected: selection.wrappedValue.rawValue,
            select: { id in BandRankingMetric(rawValue: id).map { selection.wrappedValue = $0 } }
        )))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct MacRankByCommandsKey: FocusedValueKey {
    typealias Value = MacRankByCommands
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

/// Publishes Rank By only from the top page of its column.
private struct MacRankByPublisher: ViewModifier {
    let commands: MacRankByCommands
    @Environment(\.macPageIsTop) private var isTop

    func body(content: Content) -> some View {
        content.focusedSceneValue(\.macRankBy, isTop ? commands : nil)
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
        content
            .focusedSceneValue(\.macQuickLinksPage, isList ? nil : command)
            .focusedSceneValue(\.macQuickLinksList, isList ? command : nil)
    }
}
#endif
