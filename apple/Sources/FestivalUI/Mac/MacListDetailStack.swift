#if os(macOS)
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Mac stack

/// One `NavigationStack` with every `AppRoute` destination, for a Mac column.
struct MacStack<Root: View>: View {
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var stackPath: [AppRoute]
    /// The destination's whole path, for screens that pop or replace.
    @Binding var fullPath: [AppRoute]
    let isVisible: Bool
    /// Whether this column carries the window's global toolbar group (the single stack,
    /// or the detail column of two): toolbar items placed outside a `NavigationStack`
    /// disappear once a page is pushed, so every page of this column adds them.
    let providesGlobalToolbar: Bool
    /// Widest root content (``MacLayoutPolicy/pageMaxWidth(for:isShopRoot:)``).
    let rootMaxWidth: CGFloat
    let root: Root

    /// Create a column stack.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - stackPath: This column's path.
    ///   - fullPath: The destination's whole path.
    ///   - isVisible: Whether the destination is on screen.
    ///   - providesGlobalToolbar: Whether its pages carry the global toolbar group.
    ///   - root: Column root.
    init(
        session: FestivalSession, visibleInstruments: Set<Instrument>,
        stackPath: Binding<[AppRoute]>, fullPath: Binding<[AppRoute]>, isVisible: Bool,
        providesGlobalToolbar: Bool = true, rootMaxWidth: CGFloat = MacLayoutPolicy.pageMaxWidth(for: nil),
        @ViewBuilder root: () -> Root
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        _stackPath = stackPath
        _fullPath = fullPath
        self.isVisible = isVisible
        self.providesGlobalToolbar = providesGlobalToolbar
        self.rootMaxWidth = rootMaxWidth
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $stackPath) {
            root
                .modifier(MacPageWidth(maxWidth: rootMaxWidth))
                .modifier(MacGlobalToolbar(isEnabled: providesGlobalToolbar))
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(
                        route: route, session: session, visibleInstruments: visibleInstruments,
                        path: $fullPath, isVisible: isVisible
                    )
                    .modifier(MacPageWidth(maxWidth: MacLayoutPolicy.pageMaxWidth(for: route)))
                    .modifier(MacGlobalToolbar(isEnabled: providesGlobalToolbar))
                }
        }
        // Each column publishes its own layout, so its pages pick one or two card
        // columns and readable widths from the column's width, not the window's.
        .publishesDeviceLayout(usesSidebarShell: true)
    }
}

/// Centres a page at most `maxWidth` wide in its column (web page max width).
struct MacPageWidth: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content.frame(maxWidth: maxWidth)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - List/detail stack

extension EnvironmentValues {
    /// How long a Mac list page may show no row before its second column collapses
    /// (2.5 s; hosted tests lengthen it so a loaded test machine cannot race it).
    @Entry var macListCollapseDelay: Duration = .milliseconds(2500)
}

/// A Mac destination's content: one stack, or **two populated columns** (list and
/// detail) when the window is wide enough, as decided by ``MacLayoutPolicy`` over the
/// shared ``ListDetailPolicy`` path cut.
///
/// The detail column is never empty: it restores the last selection, else the first
/// list row to appear selects itself (`listDetailAutoSelect`, the same contract
/// `ListDetailLink` rows use on iPhone Duo). A list that shows no row within 2.5 s
/// collapses to one column, and its first row to appear later splits it again.
/// The columns sit beside a draggable 1 pt ``MacColumnDivider``; the list takes 38% of
/// the width within ``MacLayoutPolicy/listColumn`` until the person drags it, and the
/// dragged width is remembered (an `HSplitView` lost its divider position when a
/// pushed list page split after first layout, leaving the detail at zero width).
struct MacListDetailStack<Root: View>: View {
    let section: FestivalSection
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var path: [AppRoute]
    let isVisible: Bool
    /// Reports whether two columns are showing (Go › Back rules).
    let onSplitChange: (Bool) -> Void
    /// Builds the root page, given whether it is the top of its column.
    let root: (Bool) -> Root

    private enum Arrangement { case stack, split }

    @State private var width: CGFloat = 0
    @State private var lastSelection: AppRoute?
    @State private var emptyLists: Set<[AppRoute]> = []
    /// Rows offered for auto-select (the top-most one on screen wins).
    @State private var autoSelectCollector = ListDetailAutoSelectCollector()
    @State private var collapsedCollector = ListDetailAutoSelectCollector()
    /// The list width the person dragged the divider to (0 = automatic 38%).
    @AppStorage(MacLayoutPolicy.listWidthKey) private var storedListWidth = 0.0
    /// Live width during a divider drag.
    @State private var dragListWidth: CGFloat?
    /// How long a list may show no row before it collapses to one column.
    @Environment(\.macListCollapseDelay) private var collapseDelay

    /// The list column width drawn now: a live drag, else the remembered width, else
    /// automatic; always clamped by ``MacLayoutPolicy/listWidth(forContentWidth:preferred:)``.
    private var listColumnWidth: CGFloat {
        MacLayoutPolicy.listWidth(
            forContentWidth: width, preferred: dragListWidth ?? (storedListWidth > 0 ? storedListWidth : nil)
        )
    }

    private var cut: ListDetailPolicy.Split? { ListDetailPolicy.split(section: section, path: path) }

    private var split: ListDetailPolicy.Split? {
        guard let cut else { return nil }
        let collapsed = cut.selection == nil && emptyLists.contains(cut.list)
        return MacLayoutPolicy.showsSplit(width: width, hasListPage: true, emptyListCollapsed: collapsed)
            ? cut : nil
    }

    var body: some View {
        Group {
            if let split {
                splitView(split)
                    .task(id: split.list) { await populate(split) }
                    // A fresh identity per arrangement: otherwise the split view keeps
                    // presenting the one-column stack's pushed page over the columns.
                    .id(Arrangement.split)
            } else {
                MacStack(
                    session: session, visibleInstruments: visibleInstruments,
                    stackPath: $path, fullPath: $path, isVisible: isVisible
                ) {
                    root(path.isEmpty)
                        // A list that collapsed while it was still loading: its first row
                        // brings the second column back, already selected.
                        .environment(\.listDetailAutoSelect, collapsedAutoSelect)
                }
                .id(Arrangement.stack)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: split != nil, initial: true) { _, isSplit in onSplitChange(isSplit) }
        .onChange(of: cut?.selection) { _, selection in
            if let selection { lastSelection = selection }
            autoSelectCollector.reset()
        }
    }

    // MARK: Columns

    private func splitView(_ split: ListDetailPolicy.Split) -> some View {
        HStack(spacing: 0) {
            // Neither column shows pushed pages: inside the window's
            // `NavigationSplitView` a page pushed in a nested stack is presented over
            // both columns (list) or not at all (detail). Each column draws its top
            // route as its root, and links pushed there extend the path instead.
            MacStack(
                session: session, visibleInstruments: visibleInstruments,
                stackPath: pushes(after: path.count - split.detail.count), fullPath: $path,
                isVisible: isVisible, providesGlobalToolbar: false
            ) {
                Group {
                    if let page = split.list.last {
                        listColumn(destination(page), split: split)
                    } else {
                        listColumn(root(true), split: split)
                    }
                }
                .id(split.list.last)
            }
            .frame(width: listColumnWidth)
            MacColumnDivider(
                listWidth: listColumnWidth, range: MacLayoutPolicy.listWidthRange(forContentWidth: width),
                dragWidth: $dragListWidth
            ) { preferred in
                // Remember the clamped width, so a later wider window does not jump.
                storedListWidth = preferred.map {
                    Double(MacLayoutPolicy.listWidth(forContentWidth: width, preferred: $0))
                } ?? 0
            }
            MacStack(
                session: session, visibleInstruments: visibleInstruments,
                stackPath: pushes(after: path.count), fullPath: $path, isVisible: isVisible
            ) {
                Group {
                    if let top = split.detail.last {
                        destination(top).id(top)
                    } else {
                        FestivalLoadingView(accessibilityLabel: "Loading")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .toolbar {
                    if let back = MacSidebarPolicy.backPath(path, section: section, split: true) {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                path = back
                            } label: {
                                Label("Back", systemImage: "chevron.backward")
                            }
                            .help("Back (⌘[)")
                            .accessibilityIdentifier("fst.nav.split-back")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        // A container element, so its identifier names the split and does not replace
        // the divider's and rows' own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.nav.list-detail")
    }

    /// A column stack's path as the stack sees it: always empty (the column draws its
    /// top route as root). A link pushed there replaces everything after `prefix`
    /// routes of the destination path with the pushed routes, through the shared
    /// list/detail write rules.
    ///
    /// - Parameter prefix: Routes of the destination path kept before the push.
    /// - Returns: The binding for the column's `NavigationStack`.
    private func pushes(after prefix: Int) -> Binding<[AppRoute]> {
        Binding {
            []
        } set: { pushed in
            guard !pushed.isEmpty else { return }
            let kept = Array(path.prefix(max(0, prefix)))
            path = ListDetailPolicy.path(settingList: kept + pushed, in: path, section: section)
        }
    }

    /// Give the list column's root the selection and the select actions. Pages pushed
    /// inside the list column keep plain links; their detail routes are lifted into the
    /// detail column by ``ListDetailPolicy/path(settingList:in:section:)``.
    private func listColumn(_ page: some View, split: ListDetailPolicy.Split) -> some View {
        page
            .environment(\.listDetailSelection, split.selection)
            .environment(\.listDetailSelect, selectAction)
            .environment(\.listDetailAutoSelect, split.selection == nil ? autoSelectAction : nil)
    }

    private func destination(_ route: AppRoute) -> some View {
        AppRouteDestination(
            route: route, session: session, visibleInstruments: visibleInstruments,
            path: $path, isVisible: isVisible
        )
    }

    // MARK: Selection

    private func populate(_ split: ListDetailPolicy.Split) async {
        guard split.selection == nil else { return }
        if let lastSelection, split.page.accepts(lastSelection) {
            selectAction(lastSelection)
            return
        }
        try? await Task.sleep(for: collapseDelay)
        guard !Task.isCancelled, cut?.selection == nil else { return }
        emptyLists.insert(split.list)
    }

    private var selectAction: ListDetailSelectAction {
        ListDetailSelectAction(section: section) { route in
            let current = cut?.list ?? []
            path = ListDetailPolicy.path(settingList: current + [route], in: path, section: section)
        }
    }

    private var autoSelectAction: ListDetailAutoSelectAction {
        autoSelectCollector.select = { route in
            guard split != nil, cut?.selection == nil else { return }
            selectAction(route)
        }
        return ListDetailAutoSelectAction(section: section, collector: autoSelectCollector)
    }

    /// Offered to the one-column root only while its list collapsed for lack of rows.
    private var collapsedAutoSelect: ListDetailAutoSelectAction? {
        guard let cut, cut.selection == nil, emptyLists.contains(cut.list),
              MacLayoutPolicy.showsSplit(width: width, hasListPage: true, emptyListCollapsed: false)
        else { return nil }
        collapsedCollector.select = { route in
            guard let current = self.cut, current.selection == nil else { return }
            emptyLists.remove(current.list)
            selectAction(route)
        }
        return ListDetailAutoSelectAction(section: section, collector: collapsedCollector)
    }

}
#endif
