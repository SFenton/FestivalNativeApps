import SwiftUI
import FestivalCore

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
        modifier(MacDetailTopPublisher(keyPath: \.macRankBy, value: RankByMenuCommands(
            options: RankByMenuCommands.accountOptions(experimentalRanks: experimentalRanks),
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
        modifier(MacDetailTopPublisher(keyPath: \.macRankBy, value: RankByMenuCommands(
            options: RankByMenuCommands.bandOptions(experimentalRanks: experimentalRanks),
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
        modifier(MacDetailTopPublisher(keyPath: \.macInstrument, value: InstrumentMenuCommands(
            options: InstrumentMenuCommands.options(for: instruments),
            selected: selection.wrappedValue.rawValue,
            select: { id in Instrument(rawValue: id).map { selection.wrappedValue = $0 } }
        )))
    }

    /// Publish a band board's band size to View › Band Size (macOS and the iPadOS menu
    /// bar; a no-op on iPhone).
    ///
    /// - Parameter selection: The page's band size.
    /// - Returns: The view.
    func macBandSizeCommands(_ selection: Binding<BandType>) -> some View {
        modifier(MacDetailTopPublisher(keyPath: \.macBandSize, value: BandSizeMenuCommands(
            selected: selection.wrappedValue,
            select: { selection.wrappedValue = $0 }
        )))
    }
}

private struct MacRankByCommandsKey: FocusedValueKey {
    typealias Value = RankByMenuCommands
}

private struct MacInstrumentCommandsKey: FocusedValueKey {
    typealias Value = InstrumentMenuCommands
}

private struct MacBandSizeCommandsKey: FocusedValueKey {
    typealias Value = BandSizeMenuCommands
}

private struct MacQuickLinksPageKey: FocusedValueKey {
    typealias Value = QuickLinksMenuCommand
}

private struct MacQuickLinksListKey: FocusedValueKey {
    typealias Value = QuickLinksMenuCommand
}

extension FocusedValues {
    /// The front rankings page's Rank By.
    var macRankBy: RankByMenuCommands? {
        get { self[MacRankByCommandsKey.self] }
        set { self[MacRankByCommandsKey.self] = newValue }
    }

    /// The front rankings page's instrument switcher.
    var macInstrument: InstrumentMenuCommands? {
        get { self[MacInstrumentCommandsKey.self] }
        set { self[MacInstrumentCommandsKey.self] = newValue }
    }

    /// The front band board's band size.
    var macBandSize: BandSizeMenuCommands? {
        get { self[MacBandSizeCommandsKey.self] }
        set { self[MacBandSizeCommandsKey.self] = newValue }
    }

    /// Quick Links of the page in the detail (or only) column.
    var macQuickLinksPage: QuickLinksMenuCommand? {
        get { self[MacQuickLinksPageKey.self] }
        set { self[MacQuickLinksPageKey.self] = newValue }
    }

    /// Quick Links of the page in a split's list column (used when the detail has none).
    var macQuickLinksList: QuickLinksMenuCommand? {
        get { self[MacQuickLinksListKey.self] }
        set { self[MacQuickLinksListKey.self] = newValue }
    }
}

/// Publishes a page's View-menu choice (Rank By, Instrument, Band Size) only from the
/// top page of its column, and not from the list beside an open trailing pane
/// (Leaderboards beside Full Rankings, issue #352: the detail wins).
private struct MacDetailTopPublisher<Published>: ViewModifier {
    let keyPath: WritableKeyPath<FocusedValues, Published?>
    let value: Published
    @Environment(\.macPageIsTop) private var isTop
    @Environment(\.macColumnIsList) private var isList

    func body(content: Content) -> some View {
        if MenuBarCommandsSupport.isAvailable {
            let published: Published? = isTop && !isList ? value : nil
            content.focusedSceneValue(keyPath, published)
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
        let command = isTop ? QuickLinksMenuCommand(controller: controller) : nil
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

