import Foundation
import Observation
import SwiftUI
import FestivalDesign

// MARK: - Keyboard rows

/// One row a Mac list page offers to arrow-key navigation (HIG Focus and selection:
/// "highlight items in lists and collections"; Keyboards: "holding an arrow key moves
/// the selection by the smallest app-defined unit of distance until released").
///
/// Pages declare their rows from their data, not from the rows on screen: a lazy
/// `List`/`LazyVStack` only builds visible rows, and ↓ must reach the next one anyway.
/// Built on every platform so shared pages compile unchanged; only the Mac uses it.
struct MacKeyRow: Equatable {
    /// What Return (or a split's selection) does with the row.
    enum Action: Equatable {
        /// Show a route: the detail column's selection in a split, else a push.
        case route(AppRoute)
        /// Open an outside link (an Item Shop card without an in-app page).
        case url(URL)
    }

    /// Unique within the page; also the row's scroll identity (`.id`).
    let id: String
    /// Return's action.
    let action: Action
    /// A lazily built container holding the row (a Leaderboards card), scrolled to
    /// first when the row has not been built yet.
    var container: String?

    /// The row's route, or nil for an outside link.
    var route: AppRoute? {
        if case let .route(route) = action { return route }
        return nil
    }
}

/// One page-declared run of rows (a whole list, one card or one Rivals section).
struct MacKeyRowGroup: Equatable {
    /// Position among the page's groups (ties keep registration order).
    var order: Int
    /// Columns of a grid group (Item Shop artwork grid); 1 for a list.
    var columns: Int = 1
    /// Rows in display order.
    var rows: [MacKeyRow]
}

/// An arrow-key or Home/End movement.
enum MacKeyMove: Equatable {
    case up, down, left, right, first, last
}

// MARK: - Policy

/// Pure arrow-key rules shared by every Mac list page.
enum MacKeyboardPolicy {
    /// The row a key moves to.
    ///
    /// ↑/↓ step one row (one grid row in a grid group, the nearest last item when the
    /// next grid row is short) and cross into the neighbouring group; ←/→ step one item
    /// and only act inside grids. With nothing highlighted ↓, → and Home go to the first
    /// row, ↑ and End to the last.
    ///
    /// - Parameters:
    ///   - current: The highlighted (or selected) row id, if any.
    ///   - move: The key.
    ///   - groups: The page's groups in display order.
    /// - Returns: The target row, or nil when the key does nothing (the edge of the
    ///   list, ←/→ in a list), so the key can pass on.
    static func target(from current: String?, move: MacKeyMove, in groups: [MacKeyRowGroup]) -> MacKeyRow? {
        var flat: [(row: MacKeyRow, group: Int, start: Int, end: Int, columns: Int)] = []
        for (index, group) in groups.enumerated() where !group.rows.isEmpty {
            let start = flat.count
            let end = start + group.rows.count
            for row in group.rows {
                flat.append((row, index, start, end, max(1, group.columns)))
            }
        }
        guard !flat.isEmpty else { return nil }
        let last = flat.count - 1
        guard let current, let at = flat.firstIndex(where: { $0.row.id == current }) else {
            switch move {
            case .down, .right, .first: return flat[0].row
            case .up, .last: return flat[last].row
            case .left: return nil
            }
        }
        let entry = flat[at]
        let target: Int?
        switch move {
        case .first: target = 0
        case .last: target = last
        case .left: target = entry.columns > 1 && at > 0 ? at - 1 : nil
        case .right: target = entry.columns > 1 && at < last ? at + 1 : nil
        case .down:
            let step = at + entry.columns
            if step < entry.end {
                target = step
            } else {
                // A short last grid row: land on its last item rather than skip it.
                let row = (at - entry.start) / entry.columns
                let lastRow = (entry.end - 1 - entry.start) / entry.columns
                target = row < lastRow ? entry.end - 1 : (entry.end <= last ? entry.end : nil)
            }
        case .up:
            let step = at - entry.columns
            target = step >= entry.start ? step : (entry.start > 0 ? entry.start - 1 : nil)
        }
        guard let target, target != at else { return nil }
        return flat[target].row
    }

    /// Columns of an adaptive grid (`GridItem(.adaptive(minimum:))`) at a width.
    ///
    /// - Parameters:
    ///   - width: Grid width in points.
    ///   - minimum: The adaptive item minimum.
    ///   - spacing: Spacing between items.
    /// - Returns: At least 1.
    static func adaptiveColumns(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0, minimum > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }
}

// MARK: - Page modifiers (every platform)

extension View {
    /// Offer rows to the Mac's arrow-key navigation (a no-op on iPhone and iPad).
    ///
    /// - Parameters:
    ///   - order: The group's position among the page's groups.
    ///   - columns: Grid columns (1 for a list).
    ///   - rows: The rows in display order; evaluated only on the Mac.
    /// - Returns: The view.
    func macKeyboardRows(order: Int = 0, columns: Int = 1, _ rows: @autoclosure () -> [MacKeyRow]) -> some View {
        #if os(macOS)
        modifier(MacKeyboardRowsRegistration(group: MacKeyRowGroup(order: order, columns: columns, rows: rows())))
        #else
        self
        #endif
    }

    /// Mark a row for the Mac's arrow-key navigation: its scroll identity and its
    /// keyboard highlight outside a split (a split's selection
    /// is drawn by `listDetailSelectable`). Apply it last, so `.id` is the outermost
    /// modifier a lazy stack resolves. A no-op on iPhone and iPad.
    ///
    /// - Parameters:
    ///   - id: The row's ``MacKeyRow/id``.
    ///   - cornerRadius: The row card's corner radius.
    ///   - ring: Ring the item instead of tinting it, for artwork that fills its cell
    ///     (HIG Focus and selection: "You can ring an item that fills a cell, like a
    ///     photo"); a tint is invisible on bright art.
    /// - Returns: The row.
    func macKeyboardRow(_ id: String, cornerRadius: CGFloat = 12, ring: Bool = false) -> some View {
        #if os(macOS)
        modifier(MacKeyboardRowHighlight(id: id, cornerRadius: cornerRadius, ring: ring)).id(id)
        #else
        self
        #endif
    }
}

#if os(macOS)

// MARK: - Navigator

/// One Mac column's keyboard-navigable rows, highlight and focus (owned by
/// ``MacKeyboardNavigation``; pages reach it through the environment).
@MainActor @Observable
final class MacKeyboardNavigator {
    /// Registered groups by registration token (observation-ignored: rows never redraw).
    @ObservationIgnored private var groups: [UUID: (serial: Int, group: MacKeyRowGroup)] = [:]
    @ObservationIgnored private var nextSerial = 0
    /// Rows currently built on screen (scroll straight to them).
    @ObservationIgnored private(set) var builtRows: Set<String> = []
    /// Whether any row is registered (the column is focusable only then).
    private(set) var hasRows = false
    /// The keyboard highlight outside a split.
    var highlight: String?
    /// Whether the column has keyboard focus (accent highlight; gray otherwise).
    var hasFocus = false
    /// Incremented to ask the column to take keyboard focus (a row was clicked).
    private(set) var focusRequest = 0
    /// The row to scroll to, and a serial that changes on every request.
    private(set) var scrollTarget: (row: MacKeyRow, serial: Int)?

    /// Groups in display order.
    var orderedGroups: [MacKeyRowGroup] {
        groups.values.sorted { ($0.group.order, $0.serial) < ($1.group.order, $1.serial) }.map(\.group)
    }

    /// Add or replace a group.
    ///
    /// - Parameters:
    ///   - group: The rows.
    ///   - token: The registering view's token.
    func set(_ group: MacKeyRowGroup, token: UUID) {
        let serial = groups[token]?.serial ?? { nextSerial += 1; return nextSerial }()
        groups[token] = (serial, group)
        let any = groups.values.contains { !$0.group.rows.isEmpty }
        if any != hasRows { hasRows = any }
    }

    /// Remove a group whose view left the screen.
    ///
    /// - Parameter token: The registering view's token.
    func remove(token: UUID) {
        groups[token] = nil
        let any = groups.values.contains { !$0.group.rows.isEmpty }
        if any != hasRows { hasRows = any }
    }

    /// The first row showing a route.
    ///
    /// - Parameter route: A detail route.
    /// - Returns: Its row, if registered.
    func row(for route: AppRoute) -> MacKeyRow? {
        for group in orderedGroups {
            if let row = group.rows.first(where: { $0.route == route }) { return row }
        }
        return nil
    }

    /// A row by id.
    ///
    /// - Parameter id: Row id.
    /// - Returns: The row, if registered.
    func row(id: String) -> MacKeyRow? {
        for group in orderedGroups {
            if let row = group.rows.first(where: { $0.id == id }) { return row }
        }
        return nil
    }

    /// Record that a row was built or torn down.
    ///
    /// - Parameters:
    ///   - id: Row id.
    ///   - built: Whether it is on screen.
    func report(_ id: String, built: Bool) {
        if built { builtRows.insert(id) } else { builtRows.remove(id) }
    }

    /// Ask the column to scroll a row into view.
    ///
    /// - Parameter row: The row.
    func scroll(to row: MacKeyRow) {
        scrollTarget = (row, (scrollTarget?.serial ?? 0) + 1)
    }

    /// Ask the column to take keyboard focus.
    func requestFocus() {
        focusRequest += 1
    }
}

extension EnvironmentValues {
    /// The column's keyboard navigator (Mac list pages; nil elsewhere).
    @Entry var macKeyboardNavigator: MacKeyboardNavigator?
    /// Whether the page is the top of its column's stack (menu commands publish only
    /// from the top page; a page under a push stays alive).
    @Entry var macPageIsTop = true
    /// Whether the page is in a split's list column (Quick Links prefer the detail).
    @Entry var macColumnIsList = false
}

// MARK: - Registration

/// Registers one ``MacKeyRowGroup`` with the column's navigator while on screen.
private struct MacKeyboardRowsRegistration: ViewModifier {
    let group: MacKeyRowGroup
    @Environment(\.macKeyboardNavigator) private var navigator
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { navigator?.set(group, token: token) }
            .onChange(of: group) { _, group in navigator?.set(group, token: token) }
            .onDisappear { navigator?.remove(token: token) }
    }
}

/// The highlight of a keyboard row outside a split (accent while the column has focus,
/// gray otherwise, like a split's selection), plus its built/torn-down reports.
private struct MacKeyboardRowHighlight: ViewModifier {
    let id: String
    let cornerRadius: CGFloat
    let ring: Bool
    @Environment(\.macKeyboardNavigator) private var navigator
    @Environment(\.listDetailSelect) private var splitSelect

    func body(content: Content) -> some View {
        let highlighted = splitSelect == nil && navigator?.highlight == id
        content
            .overlay {
                if highlighted {
                    if ring {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                navigator?.hasFocus == true ? BrandTokens.accentBlue : Color(nsColor: .systemGray),
                                lineWidth: 4
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    } else {
                        MacSelectionHighlight(cornerRadius: cornerRadius, focused: navigator?.hasFocus == true)
                    }
                }
            }
            .accessibilityAddTraits(highlighted ? .isSelected : [])
            .onAppear { navigator?.report(id, built: true) }
            .onDisappear { navigator?.report(id, built: false) }
    }
}

/// The list selection look (HIG Focus and selection: "white text on an accent-color
/// highlight when focused, standard text on gray when not"): a translucent fill with a
/// leading bar over the row card, accent while the list has focus, gray otherwise.
struct MacSelectionHighlight: View {
    let cornerRadius: CGFloat
    let focused: Bool

    var body: some View {
        let tint = focused ? BrandTokens.accentBlue : Color(nsColor: .systemGray)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tint.opacity(0.22))
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 3).padding(.vertical, 8)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Column modifier

/// Arrow-key navigation for one Mac column page (``MacStack`` applies it to every
/// page): the page is one keyboard focus stop while it offers rows; ↑/↓ (←/→ in a
/// grid, Home/End) move the selection, Return opens, Escape clears an unopened
/// highlight. In a split's list column the selection *is* the detail column's route,
/// so the detail follows every move (HIG Split views: "selecting an item in the
/// primary pane shows its contents in the secondary"); elsewhere the highlight moves
/// and Return pushes. The highlighted row scrolls into view.
struct MacKeyboardNavigation: ViewModifier {
    /// The split's selection (list column only).
    let selection: AppRoute?
    /// Selects a route into the detail column (list column only).
    let select: ListDetailSelectAction?
    /// Pushes a route in this column (one-column arrangement).
    let push: (AppRoute) -> Void
    /// Whether this page is the top of its stack.
    let isTop: Bool
    @State private var navigator = MacKeyboardNavigator()
    @State private var autoFocused = false
    @FocusState private var focused: Bool
    @Environment(\.openURL) private var openURL

    private static let keys: Set<KeyEquivalent> = [
        .upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end, .return, .escape,
    ]

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.macKeyboardNavigator, navigator)
                .focusable(navigator.hasRows, interactions: .edit)
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(keys: Self.keys) { press in
                    handle(press.key, modifiers: press.modifiers) ? .handled : .ignored
                }
                .onChange(of: focused) { _, focused in navigator.hasFocus = focused }
                .onChange(of: navigator.focusRequest) { _, _ in focused = true }
                .onChange(of: navigator.hasRows, initial: true) { _, hasRows in
                    // The list takes focus once when its rows first arrive (like Mail's
                    // message list), never later: typing in Filter Songs re-selects
                    // rows and must keep the field's focus.
                    guard hasRows, isTop, !autoFocused else { return }
                    autoFocused = true
                    focused = true
                }
                .onChange(of: selection) { _, selection in
                    if let selection, let row = navigator.row(for: selection) { navigator.highlight = row.id }
                }
                .onChange(of: navigator.scrollTarget?.serial) { _, _ in scroll(proxy) }
                .focusedSceneValue(\.macListCommands, isTop && navigator.hasRows ? MacListCommands(
                    scrollToSelection: { scrollToCurrent() }
                ) : nil)
        }
    }

    /// The highlighted row: the split's selection, else the keyboard highlight.
    private var currentID: String? {
        if select != nil, let selection, let row = navigator.row(for: selection) { return row.id }
        return navigator.highlight
    }

    /// Handle one key.
    ///
    /// - Returns: Whether the key was used.
    private func handle(_ key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        // Command/Option/Control arrows belong to menus and text editing.
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return false }
        let move: MacKeyMove
        switch key {
        case .upArrow: move = .up
        case .downArrow: move = .down
        case .leftArrow: move = .left
        case .rightArrow: move = .right
        case .home: move = .first
        case .end: move = .last
        case .return:
            guard let id = currentID, let row = navigator.row(id: id) else { return false }
            open(row)
            return true
        case .escape:
            guard select == nil, navigator.highlight != nil else { return false }
            navigator.highlight = nil
            return true
        default: return false
        }
        guard let row = MacKeyboardPolicy.target(from: currentID, move: move, in: navigator.orderedGroups)
        else { return false }
        navigator.highlight = row.id
        navigator.scroll(to: row)
        if let select, let route = row.route { select(route) }
        return true
    }

    /// Return: show the row's route (selection in a split, push elsewhere) or open its link.
    private func open(_ row: MacKeyRow) {
        switch row.action {
        case let .route(route):
            if let select { select(route) } else { push(route) }
        case let .url(url):
            openURL(url)
        }
    }

    /// View › Scroll to Selection (⌘J).
    private func scrollToCurrent() {
        if let id = currentID, let row = navigator.row(id: id) { navigator.scroll(to: row) }
    }

    /// Scroll the requested row into view: straight to it when built (or in a `List`,
    /// which resolves unbuilt rows itself), else to its container first.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let row = navigator.scrollTarget?.row else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        if let container = row.container, !navigator.builtRows.contains(row.id) {
            withTransaction(instant) { proxy.scrollTo(container, anchor: .top) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                withTransaction(instant) { proxy.scrollTo(row.id, anchor: nil) }
            }
        } else {
            withTransaction(instant) { proxy.scrollTo(row.id, anchor: nil) }
        }
    }
}

// MARK: - List commands

/// The focused list's commands for the menu bar (View › Scroll to Selection ⌘J, the
/// standard "Scroll to selection" shortcut, HIG Keyboards).
struct MacListCommands: Equatable {
    /// Scrolls the selected or highlighted row into view.
    let scrollToSelection: @MainActor () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

private struct MacListCommandsKey: FocusedValueKey {
    typealias Value = MacListCommands
}

extension FocusedValues {
    /// The key window's list commands.
    var macListCommands: MacListCommands? {
        get { self[MacListCommandsKey.self] }
        set { self[MacListCommandsKey.self] = newValue }
    }
}
#endif
