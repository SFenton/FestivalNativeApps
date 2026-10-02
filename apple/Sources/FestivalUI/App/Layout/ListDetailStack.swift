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
    /// Width of this section's container (the detail column of the iPad sidebar shell),
    /// measured so sidebar show/hide and window resizing re-decide stack or split.
    @State private var containerWidth: CGFloat?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// The last detail root shown, restored when a list page splits again unselected.
    @State private var lastSelection: AppRoute?
    /// The list pages (by list-column path) that produced no row to auto-select.
    @State private var emptyLists: Set<[AppRoute]> = []
    /// Rows offered for auto-select while nothing is selected.
    @State private var autoSelectCollector = ListDetailAutoSelectCollector()

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
            switch arrangement {
            case .stack:
                FestivalTabStack(
                    session: session, visibleInstruments: visibleInstruments,
                    path: $path, isVisible: isVisible
                ) {
                    root(path.isEmpty)
                        // A wide window's list that collapsed while empty: a row that
                        // appears later (or a tap) still opens the detail column.
                        .transformEnvironment(\.listDetailSelect) { value in
                            if awaiting { value = selectAction }
                        }
                        .transformEnvironment(\.listDetailAutoSelect) { value in
                            if awaiting { value = autoSelectAction }
                        }
                }
            case let .split(split):
                splitView(split)
                    .task(id: split.list) { await populate(split) }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            // Only the sidebar shell measures; ignore sub-point jitter.
            guard layout.sectionChrome == .sidebar, abs((containerWidth ?? 0) - width) >= 1 else { return }
            containerWidth = width
        }
        .onChange(of: ListDetailPolicy.split(section: section, path: path)?.selection) { _, selection in
            if let selection { lastSelection = selection }
            autoSelectCollector.reset()
        }
        .onChange(of: isSplit, initial: true) { _, split in
            if isVisible { splitReporter?(section, isSplit: split) }
        }
        .onChange(of: isVisible) { _, visible in
            if visible { splitReporter?(section, isSplit: isSplit) }
        }
    }

    private var arrangement: ListDetailPolicy.Arrangement {
        let list = ListDetailPolicy.split(section: section, path: path)?.list ?? []
        return ListDetailPolicy.arrangement(
            section: section, path: path, layout: layout, containerWidth: containerWidth,
            emptyListCollapsed: emptyLists.contains(list)
        )
    }

    /// Whether the section currently shows two columns.
    private var isSplit: Bool {
        if case .split = arrangement { return true }
        return false
    }

    private var awaiting: Bool {
        ListDetailPolicy.awaitsSelection(
            section: section, path: path, layout: layout, containerWidth: containerWidth
        )
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

    /// Two columns over the section path.
    ///
    /// In the iPad sidebar shell this split sits in the root split's detail column: the
    /// result is the three-pane iPad layout (sidebar, list, detail; HIG Split views,
    /// iPadOS: "two vertical panes (Mail) or three (Keynote)"), each column with its own
    /// toolbar. Verified on iPadOS 26.5: the inner list column floats as its own glass
    /// column with its own hide/show button; an `HStack` of two `NavigationStack`s
    /// instead merged both toolbars (and the Filter Songs field) into one bar.
    ///
    /// - Parameter split: Current cut of the path.
    /// - Returns: The split view.
    private func splitView(_ split: ListDetailPolicy.Split) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack(path: listPath) {
                listColumn(root(split.list.isEmpty), split: split)
                    .navigationDestination(for: AppRoute.self) { route in
                        listColumn(destination(route), split: split)
                    }
            }
        } detail: {
            NavigationStack(path: detailTail) {
                // Populated by restore/auto-select within a frame of the first row
                // appearing; a quiet spinner covers the moment before (never a
                // "Select a …" prompt).
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
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("fst.nav.list-detail")
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

    func body(content: Content) -> some View {
        let selected = selection == route
        content
            // An overlay, not a background: Song rows are opaque glass cards. The
            // translucent fill keeps the row's own Shop highlight stroke readable.
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandTokens.accentBlue.opacity(0.22))
                        .overlay(alignment: .leading) {
                            Capsule().fill(BrandTokens.accentBlue).frame(width: 3).padding(.vertical, 8)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
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
                Button { select(value) } label: { decoratedLabel }
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
