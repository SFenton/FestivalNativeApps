import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Selection environment

extension EnvironmentValues {
    /// Route shown as the detail column's root while a list column is on screen, or
    /// nil (stack arrangement, or nothing selected). List rows read it through
    /// ``SwiftUI/View/listDetailSelectable(_:)`` to show their selected state.
    @Entry var listDetailSelection: AppRoute?
    /// Shows a route in the detail column; set only inside a split's list column.
    /// ``ListDetailLink`` uses it instead of pushing, so the list never pushes.
    @Entry var listDetailSelect: ListDetailSelectAction?
    /// Offered to list rows while a wide window's detail column has nothing to show:
    /// every ``ListDetailLink`` on screen offers its route and position, and the
    /// top-most one becomes the detail (auto-select the first item).
    @Entry var listDetailAutoSelect: ListDetailAutoSelectAction?
    /// Tells the root shell whether a section is currently shown as two columns (the
    /// hardware-keyboard Back command pops per column); nil outside the root shell.
    @Entry var listDetailSplitReporter: ListDetailSplitReporter?
    /// Width the iPad sidebar shell leaves for the selected section (window width minus
    /// the sidebar's trailing edge); nil outside the sidebar shell.
    @Entry var sidebarShellContentWidth: CGFloat?
    /// The iPad sidebar shell's sidebar column and its visibility, handed to list/detail
    /// sections so they draw the whole shell split themselves; nil elsewhere.
    @Entry var sidebarShell: SidebarShellContext?
    /// The row a rebuilt list page should scroll back to, set only after the section
    /// switched between one stack and two columns (fold/unfold rebuilds its screens and
    /// so drops their scroll position). Nil on iPhone, where that never happens. List
    /// pages scroll to it once per value (``ListDetailScrollRestore``; `/duo` D6).
    @Entry var listDetailScrollAnchor: AppRoute?
}

/// What a list/detail section needs to draw the iPad shell split itself: the sidebar
/// column and the shared column visibility (sidebar hidden stays hidden).
struct SidebarShellContext {
    /// The sections sidebar (primary column).
    let sidebar: AnyView
    /// Shared column visibility of the shell split.
    let visibility: Binding<NavigationSplitViewVisibility>
}

// MARK: - Scroll restore across a stack/split switch

/// Which row a rebuilt list page scrolls to after a stack ↔ split switch (`/duo` D6,
/// operator 2026-10-02: keep the swap, restore list scroll).
///
/// The anchor is the selection at the moment of the switch, so folding a split and
/// going Back, or unfolding while a detail is open, shows the list at the song you were
/// on instead of the top. A list unfolded with nothing open has no anchor (its first
/// visible row is auto-selected).
enum ListDetailScrollRestore {
    /// The anchor to record when the arrangement switches.
    ///
    /// - Parameters:
    ///   - selection: The detail root in the path at the switch, if any.
    ///   - lastSelection: The last detail root shown in this section.
    /// - Returns: The route to restore to.
    static func anchor(selection: AppRoute?, lastSelection: AppRoute?) -> AppRoute? {
        selection ?? lastSelection
    }

    /// The row id to scroll to, once per anchor value.
    ///
    /// - Parameters:
    ///   - anchor: The section's current scroll anchor.
    ///   - restored: The anchor this page instance already restored.
    ///   - rowIDs: Ids of the rows the page currently lists.
    ///   - rowID: Maps a route to the page's row id (nil for routes it doesn't list).
    /// - Returns: The row id, or nil when there is nothing (new) to restore.
    static func target<ID: Hashable>(
        anchor: AppRoute?, restored: AppRoute?, rowIDs: Set<ID>, rowID: (AppRoute) -> ID?
    ) -> ID? {
        guard let anchor, anchor != restored, let id = rowID(anchor), rowIDs.contains(id) else { return nil }
        return id
    }
}

/// Reports a section's current arrangement to the root shell.
///
/// Equatable as always-equal: the root re-creates the closure on each pass and it only
/// writes root-owned state (same reasoning as `OpenProfileAction`).
struct ListDetailSplitReporter: Equatable {
    let report: @MainActor (FestivalSection, Bool) -> Void

    /// Record whether `section` shows two columns.
    @MainActor func callAsFunction(_ section: FestivalSection, isSplit: Bool) { report(section, isSplit) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// Replaces the detail column with a route pushed directly from the list page.
///
/// Equatable by section only: the action always writes the same section path, so a
/// re-created closure must not count as a change (toolbar/rail churn, see duo.md).
struct ListDetailSelectAction: Equatable {
    let section: FestivalSection
    let action: (AppRoute) -> Void

    /// Show a route in the detail column.
    ///
    /// - Parameter route: The detail route (for example `.songDetail`).
    func callAsFunction(_ route: AppRoute) { action(route) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.section == rhs.section }
}

/// Collects the rows a list shows while nothing is selected and selects the top-most.
///
/// A lazy list builds (and calls `onAppear` for) its visible rows in no guaranteed
/// order, so "the first row to appear" was sometimes the fourth row on screen. Rows
/// offer their route with their vertical position instead; a short settle window picks
/// the smallest. Equatable by section only (see ``ListDetailSelectAction``).
struct ListDetailAutoSelectAction: Equatable {
    let section: FestivalSection
    let collector: ListDetailAutoSelectCollector

    /// Offer a row.
    ///
    /// - Parameters:
    ///   - route: The row's detail route.
    ///   - minY: The row's top edge in global coordinates.
    @MainActor func offer(_ route: AppRoute, minY: CGFloat) { collector.offer(route, minY: minY) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.section == rhs.section }
}

/// Reference box behind ``ListDetailAutoSelectAction`` (not observable: offers never
/// redraw anything).
@MainActor
final class ListDetailAutoSelectCollector {
    /// How long offers are collected before the top-most row is selected.
    static let settle: Duration = .milliseconds(120)

    private var best: (route: AppRoute, minY: CGFloat)?
    private var pending: Task<Void, Never>?
    /// Writes the chosen route; set by the owning stack on every body pass.
    var select: (AppRoute) -> Void = { _ in }

    /// Record a row and schedule the choice.
    ///
    /// - Parameters:
    ///   - route: The row's detail route.
    ///   - minY: The row's top edge in global coordinates.
    func offer(_ route: AppRoute, minY: CGFloat) {
        if best == nil || minY < best!.minY { best = (route, minY) }
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard let self, !Task.isCancelled, let chosen = self.best else { return }
            self.reset()
            self.select(chosen.route)
        }
    }

    /// Forget collected offers (a new list page or a selection was made).
    func reset() {
        pending?.cancel()
        pending = nil
        best = nil
    }
}

// MARK: - List/detail stack

/// A section's navigation: one `FestivalTabStack` on iPhone and folded iPhone Duo,
/// or a `NavigationSplitView` (list column + detail `NavigationStack`) on a regular
/// width iPhone Duo inner display or a wide enough iPad sidebar-shell detail column,
/// as decided by ``ListDetailPolicy``.
///
/// Both arrangements read and write the same section path, so fold/unfold keeps the
/// selection. In the split, list rows that open a detail use ``ListDetailLink``, which
/// becomes a button writing `list + [route]` (a `NavigationLink` in the list column's
/// own stack visibly starts a push first). Any other push from the list page is still
/// written through ``ListDetailPolicy/path(settingList:in:section:)``, which lifts a
/// detail route into the detail column as a fallback.
struct ListDetailStack<Root: View>: View {
    let section: FestivalSection
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var path: [AppRoute]
    let isVisible: Bool
    /// Builds the section root; the flag is true while the root is the top of its
    /// column (nothing pushed over it), which the root uses as its own visibility.
    let root: (Bool) -> Root

    @Environment(\.deviceLayout) private var layout
    @Environment(\.listDetailSplitReporter) private var splitReporter
    @Environment(\.sidebarShell) private var sidebarShell
    /// Width the iPad sidebar shell leaves for this section (window minus the
    /// sidebar), for the column layouts its pages see; nil elsewhere.
    @Environment(\.sidebarShellContentWidth) private var shellContentWidth

    /// This section's container width in the iPad sidebar shell, else nil.
    ///
    /// Not measured here: a `NavigationStack` in a split column is hoisted into the
    /// column's navigation controller, and on iPadOS 26.5 geometry modifiers around it
    /// stopped updating. The root derives it from the window and the sidebar instead.
    private var containerWidth: CGFloat? {
        layout.sectionChrome == .sidebar ? shellContentWidth : nil
    }

    /// The split's detail column width: the container minus the list column.
    private var detailWidth: CGFloat? {
        containerWidth.map { max(0, $0 - ListDetailPolicy.splitListColumnWidth) }
    }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// The last detail root shown, restored when a list page splits again unselected.
    @State private var lastSelection: AppRoute?
    /// The list pages (by list-column path) that produced no row to auto-select.
    @State private var emptyLists: Set<[AppRoute]> = []
    /// Rows offered for auto-select while nothing is selected.
    @State private var autoSelectCollector = ListDetailAutoSelectCollector()
    /// Row the rebuilt list should scroll back to after a stack ↔ split switch.
    @State private var scrollAnchor: AppRoute?

    /// How long a split list may show no row before it collapses to full width.
    private static var emptyListTimeout: Duration { .milliseconds(2500) }

    /// Create a section stack.
    ///
    /// - Parameters:
    ///   - section: Section owning the path (decides whether it may split).
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - path: The section's navigation path.
    ///   - isVisible: Whether this section is selected.
    ///   - root: Section root screen, given whether it is the top of its column.
    init(
        section: FestivalSection, session: FestivalSession, visibleInstruments: Set<Instrument>,
        path: Binding<[AppRoute]>, isVisible: Bool, @ViewBuilder root: @escaping (Bool) -> Root
    ) {
        self.section = section
        self.session = session
        self.visibleInstruments = visibleInstruments
        _path = path
        self.isVisible = isVisible
        self.root = root
    }

    var body: some View {
        Group {
            if let sidebarShell {
                shellSplit(sidebarShell)
            } else {
                content
            }
        }
        .onChange(of: ListDetailPolicy.split(section: section, path: path)?.selection) { _, selection in
            if let selection { lastSelection = selection }
            autoSelectCollector.reset()
        }
        .onChange(of: isSplit, initial: true) { _, split in
            if isVisible { splitReporter?(section, isSplit: split) }
        }
        .onChange(of: isSplit) { _, _ in
            scrollAnchor = ListDetailScrollRestore.anchor(
                selection: ListDetailPolicy.split(section: section, path: path)?.selection,
                lastSelection: lastSelection
            )
        }
        .onChange(of: isVisible) { _, visible in
            if visible { splitReporter?(section, isSplit: isSplit) }
        }
    }

    /// iPhone and iPhone Duo: one stack, or a list/detail `NavigationSplitView`.
    @ViewBuilder private var content: some View {
        switch arrangement {
        case .stack:
            stack
        case let .split(split):
            splitView(split)
                .task(id: split.list) { await populate(split) }
        }
    }

    /// The section as one `FestivalTabStack`.
    private var stack: some View {
        FestivalTabStack(
            session: session, visibleInstruments: visibleInstruments,
            path: $path, isVisible: isVisible
        ) {
            root(path.isEmpty)
                .environment(\.listDetailScrollAnchor, scrollAnchor)
                // A wide window's list that collapsed while empty: a row that
                // appears later (or a tap) still opens the detail column.
                .transformEnvironment(\.listDetailSelect) { value in
                    if awaiting { value = selectAction }
                }
                .transformEnvironment(\.listDetailAutoSelect) { value in
                    if awaiting { value = autoSelectAction }
                }
        }
        .transformEnvironment(\.deviceLayout) { value in
            value = Self.columnLayout(value, width: containerWidth)
        }
    }

    // MARK: Shell split (iPad)

    /// The iPad shell split drawn by this section: sidebar | stack (two columns), or
    /// sidebar | list | detail (three columns; HIG Split views, iPadOS: "two vertical
    /// panes (Mail) or three (Keynote)").
    ///
    /// The two arrangements are distinct `NavigationSplitView`s, so changing between
    /// them (rotation, sidebar hide, window resize, a list page pushed) replaces the
    /// whole split. Verified on iPadOS 26.5: a list/detail split nested in the root
    /// split's detail column never reappeared after one stack had been shown there
    /// (the column's navigation controller kept the stack's pushed pages).
    ///
    /// - Parameter shell: Sidebar column and visibility from the root.
    /// - Returns: The shell split.
    @ViewBuilder private func shellSplit(_ shell: SidebarShellContext) -> some View {
        switch arrangement {
        case .stack:
            NavigationSplitView(columnVisibility: shell.visibility) {
                shell.sidebar
            } detail: {
                stack
            }
        case let .split(split):
            NavigationSplitView(columnVisibility: shell.visibility) {
                shell.sidebar
            } content: {
                listStack(split)
            } detail: {
                detailStack(split)
            }
            .navigationSplitViewStyle(.balanced)
            // A container element first: an identifier on the split itself
            // propagates to (and replaces) every row's identifier.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fst.nav.list-detail")
            .task(id: split.list) { await populate(split) }
        }
    }

    private var arrangement: ListDetailPolicy.Arrangement {
        let list = ListDetailPolicy.split(section: section, path: path)?.list ?? []
        return ListDetailPolicy.arrangement(
            section: section, path: path, layout: layout, emptyListCollapsed: emptyLists.contains(list)
        )
    }

    /// Whether the section currently shows two columns.
    private var isSplit: Bool {
        if case .split = arrangement { return true }
        return false
    }

    private var awaiting: Bool {
        ListDetailPolicy.awaitsSelection(section: section, path: path, layout: layout)
    }

    /// Keep the detail column populated: restore the last selection this list page
    /// accepts, else wait for the first row to report itself (`listDetailAutoSelect`);
    /// a list that shows no row within ``emptyListTimeout`` collapses to full width.
    ///
    /// - Parameter split: The unselected split just shown.
    private func populate(_ split: ListDetailPolicy.Split) async {
        guard split.selection == nil else { return }
        if let lastSelection, split.page.accepts(lastSelection) {
            selectAction(lastSelection)
            return
        }
        try? await Task.sleep(for: Self.emptyListTimeout)
        guard !Task.isCancelled, awaiting else { return }
        emptyLists.insert(split.list)
    }

    /// Auto-select: the top-most row on screen while nothing is selected becomes the detail.
    private var autoSelectAction: ListDetailAutoSelectAction {
        autoSelectCollector.select = { route in
            guard awaiting else { return }
            selectAction(route)
        }
        return ListDetailAutoSelectAction(section: section, collector: autoSelectCollector)
    }

    // MARK: Split

    /// Two columns over the section path (iPhone Duo inner display).
    ///
    /// - Parameter split: Current cut of the path.
    /// - Returns: The split view.
    private func splitView(_ split: ListDetailPolicy.Split) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            listStack(split)
        } detail: {
            detailStack(split)
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.nav.list-detail")
    }

    /// The list column's stack (list page root plus pushed list pages).
    ///
    /// - Parameter split: Current cut of the path.
    /// - Returns: The list column.
    private func listStack(_ split: ListDetailPolicy.Split) -> some View {
        NavigationStack(path: listPath) {
            listColumn(root(split.list.isEmpty), split: split)
                .navigationDestination(for: AppRoute.self) { route in
                    listColumn(destination(route), split: split)
                }
        }
        // The list column is always narrow.
        .transformEnvironment(\.deviceLayout) { value in
            value = Self.columnLayout(value, width: 0)
        }
    }

    /// The detail column's stack: the selection (or a quiet spinner for the frame
    /// before restore/auto-select fills it; never a "Select a …" prompt).
    ///
    /// - Parameter split: Current cut of the path.
    /// - Returns: The detail column.
    private func detailStack(_ split: ListDetailPolicy.Split) -> some View {
        NavigationStack(path: detailTail) {
            Group {
                if let selection = split.selection {
                    destination(selection).id(selection)
                } else {
                    FestivalLoadingView(accessibilityLabel: "Loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(for: AppRoute.self, destination: destination)
        }
        .transformEnvironment(\.deviceLayout) { value in
            value = Self.columnLayout(value, width: detailWidth)
        }
    }

    /// A column's layout in the iPad sidebar shell (``DeviceLayout/column(width:)``);
    /// unchanged elsewhere (iPhone, Duo) and before the column is measured.
    ///
    /// - Parameters:
    ///   - layout: Inherited layout.
    ///   - width: The column's measured width, if known.
    /// - Returns: The layout the column's pages see.
    static func columnLayout(_ layout: DeviceLayout, width: CGFloat?) -> DeviceLayout {
        guard layout.sectionChrome == .sidebar, let width else { return layout }
        return layout.column(width: width)
    }

    /// Writes a detail route after the current list (the list/detail row contract).
    private var selectAction: ListDetailSelectAction {
        ListDetailSelectAction(section: section) { route in
            let current = ListDetailPolicy.split(section: section, path: path)?.list ?? []
            path = ListDetailPolicy.path(settingList: current + [route], in: path, section: section)
        }
    }

    /// Give a list-column page the selection and the select action.
    ///
    /// Applied to the root *and* to every pushed list page: custom environment values
    /// set on the column's `NavigationStack` did not reach its pushed destinations
    /// (verified on iOS 27.1: Full Rankings rows fell back to plain links).
    ///
    /// - Parameters:
    ///   - page: Root or pushed page in the list column.
    ///   - split: Current cut of the path.
    /// - Returns: The page with list/detail selection environment.
    private func listColumn(_ page: some View, split: ListDetailPolicy.Split) -> some View {
        page
            .environment(\.listDetailScrollAnchor, scrollAnchor)
            .environment(\.listDetailSelection, split.selection)
            .environment(\.listDetailSelect, selectAction)
            .environment(\.listDetailAutoSelect, split.selection == nil ? autoSelectAction : nil)
    }

    /// One route's screen, with the section's full path for screens that pop or replace.
    ///
    /// - Parameter route: Route to display.
    /// - Returns: The feature screen.
    private func destination(_ route: AppRoute) -> some View {
        AppRouteDestination(
            route: route, session: session, visibleInstruments: visibleInstruments,
            path: $path, isVisible: isVisible
        )
    }

    /// The list column's path; writes go through ``ListDetailPolicy/path(settingList:in:section:)``.
    private var listPath: Binding<[AppRoute]> {
        Binding {
            ListDetailPolicy.split(section: section, path: path)?.list ?? path
        } set: { newList in
            path = ListDetailPolicy.path(settingList: newList, in: path, section: section)
        }
    }

    /// Detail routes after the detail root; writes go through
    /// ``ListDetailPolicy/path(settingDetailTail:in:section:)``.
    private var detailTail: Binding<[AppRoute]> {
        Binding {
            Array((ListDetailPolicy.split(section: section, path: path)?.detail ?? []).dropFirst())
        } set: { tail in
            path = ListDetailPolicy.path(settingDetailTail: tail, in: path, section: section)
        }
    }
}

// MARK: - Row selection

extension View {
    /// Mark a list row as the list/detail selection while its route is shown in the
    /// detail column: a translucent accent overlay with a leading accent bar, plus the `isSelected` accessibility trait (the
    /// same selected idiom as the iPad sections sidebar). A no-op outside a split.
    ///
    /// - Parameter route: The detail route this row opens.
    /// - Returns: The row with its selected state.
    func listDetailSelectable(_ route: AppRoute) -> some View {
        modifier(ListDetailSelectableRow(route: route))
    }
}

/// Selected-row treatment for ``SwiftUI/View/listDetailSelectable(_:)``.
private struct ListDetailSelectableRow: ViewModifier {
    let route: AppRoute
    @Environment(\.listDetailSelection) private var selection
    #if os(macOS)
    @Environment(\.macKeyboardNavigator) private var keyboard
    #endif

    func body(content: Content) -> some View {
        let selected = selection == route
        content
            // An overlay, not a background: Song rows are opaque glass cards. The
            // translucent fill keeps the row's own Shop highlight stroke readable.
            .overlay {
                #if os(macOS)
                // Accent while the list column has keyboard focus, gray otherwise
                // (HIG Focus and selection, `NSTableView`).
                if selected {
                    MacSelectionHighlight(cornerRadius: 12, focused: keyboard?.hasFocus ?? true)
                }
                #else
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandTokens.accentBlue.opacity(0.22))
                        .overlay(alignment: .leading) {
                            Capsule().fill(BrandTokens.accentBlue).frame(width: 3).padding(.vertical, 8)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A `NavigationLink(value:)` that also shows its list/detail selected state.
///
/// Drop-in for list rows whose route becomes the detail column's root. Inside a split's
/// list column it is a button that selects the route (no push in the list column);
/// everywhere else it is the plain `NavigationLink`, so iPhone is unchanged.
struct ListDetailLink<Label: View>: View {
    let value: AppRoute
    let label: Label
    @Environment(\.listDetailSelect) private var select
    @Environment(\.listDetailAutoSelect) private var autoSelect
    #if os(macOS)
    @Environment(\.macKeyboardNavigator) private var keyboard
    #endif

    /// Create a link.
    ///
    /// - Parameters:
    ///   - value: Route pushed (or shown in the detail column).
    ///   - label: Row content.
    init(value: AppRoute, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    /// The row content, with the Mac's hover tint and keyboard focus ring on its card.
    @ViewBuilder private var decoratedLabel: some View {
        #if os(macOS)
        label.modifier(MacRowInteractionEffect(cornerRadius: 12))
        #else
        label
        #endif
    }

    var body: some View {
        Group {
            if let select {
                Button {
                    select(value)
                    #if os(macOS)
                    // A clicked row gives its list column keyboard focus, so ↑/↓ continue
                    // from it (`MacKeyboardNavigation`).
                    keyboard?.requestFocus()
                    #endif
                } label: { decoratedLabel }
                    #if os(macOS)
                    // Return opens a keyboard-focused row, as Space does.
                    .onKeyPress(.return) {
                        select(value)
                        return .handled
                    }
                    #endif
            } else {
                NavigationLink(value: value) { decoratedLabel }
            }
        }
        .listDetailSelectable(value)
        #if os(iOS)
        // Pointer: the row's rounded card highlights (HIG Pointing devices: "hover for
        // large ones"; no scale, rows sit edge to edge).
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverEffect(.highlight)
        #endif
        .modifier(AutoSelectOffer(route: value, action: autoSelect))
    }
}

/// Offers a row's route and top edge to auto-select while the detail is empty.
///
/// Always attached (a conditional modifier would change the row's identity and rebuild
/// it when the selection lands); once something is selected (`action` nil) it reports
/// a constant, so scrolling never calls back.
private struct AutoSelectOffer: ViewModifier {
    let route: AppRoute
    let action: ListDetailAutoSelectAction?

    func body(content: Content) -> some View {
        let active = action != nil
        content.onGeometryChange(for: CGFloat.self, of: { active ? $0.frame(in: .global).minY : 0 }) { minY in
            action?.offer(route, minY: minY)
        }
    }
}
