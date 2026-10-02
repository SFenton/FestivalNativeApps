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
    let root: Root

    /// Create a column stack.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - stackPath: This column's path.
    ///   - fullPath: The destination's whole path.
    ///   - isVisible: Whether the destination is on screen.
    ///   - root: Column root.
    init(
        session: FestivalSession, visibleInstruments: Set<Instrument>,
        stackPath: Binding<[AppRoute]>, fullPath: Binding<[AppRoute]>, isVisible: Bool,
        @ViewBuilder root: () -> Root
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        _stackPath = stackPath
        _fullPath = fullPath
        self.isVisible = isVisible
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $stackPath) {
            root
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(
                        route: route, session: session, visibleInstruments: visibleInstruments,
                        path: $fullPath, isVisible: isVisible
                    )
                }
        }
        // Each column publishes its own layout, so its pages pick one or two card
        // columns and readable widths from the column's width, not the window's.
        .publishesDeviceLayout(usesSidebarShell: true)
    }
}

// MARK: - List/detail stack

/// A Mac destination's content: one stack, or **two populated columns** (list and
/// detail) when the window is wide enough, as decided by ``MacLayoutPolicy`` over the
/// shared ``ListDetailPolicy`` path cut.
///
/// The detail column is never empty: it restores the last selection, else the top-most
/// list row on screen selects itself (`listDetailAutoSelect`, the same contract
/// `ListDetailLink` rows use on iPhone Duo). A list that shows no row within 2.5 s
/// collapses to one column, and its first row to appear later splits it again. Columns are an `HSplitView` with the system thin divider.
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

    @State private var width: CGFloat = 0
    @State private var lastSelection: AppRoute?
    @State private var emptyLists: Set<[AppRoute]> = []
    /// Rows offered for auto-select (the top-most one on screen wins).
    @State private var autoSelectCollector = ListDetailAutoSelectCollector()
    @State private var collapsedCollector = ListDetailAutoSelectCollector()

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
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: split != nil, initial: true) { _, isSplit in onSplitChange(isSplit) }
        .onChange(of: cut?.selection) { _, selection in
            if let selection { lastSelection = selection }
        }
    }

    // MARK: Columns

    private func splitView(_ split: ListDetailPolicy.Split) -> some View {
        HSplitView {
            MacStack(
                session: session, visibleInstruments: visibleInstruments,
                stackPath: listPath, fullPath: $path, isVisible: isVisible
            ) {
                listColumn(root(split.list.isEmpty), split: split)
            }
            .frame(
                minWidth: MacLayoutPolicy.listColumn.min, idealWidth: MacLayoutPolicy.listColumn.ideal,
                maxWidth: MacLayoutPolicy.listColumn.max
            )
            MacStack(
                session: session, visibleInstruments: visibleInstruments,
                stackPath: detailTail, fullPath: $path, isVisible: isVisible
            ) {
                Group {
                    if let selection = split.selection {
                        destination(selection).id(selection)
                    } else {
                        FestivalLoadingView(accessibilityLabel: "Loading")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minWidth: MacLayoutPolicy.detailMinimumWidth, maxWidth: .infinity)
        }
        .accessibilityIdentifier("fst.nav.list-detail")
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
        try? await Task.sleep(for: .milliseconds(2500))
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

    private var listPath: Binding<[AppRoute]> {
        Binding {
            cut?.list ?? path
        } set: { newList in
            path = ListDetailPolicy.path(settingList: newList, in: path, section: section)
        }
    }

    private var detailTail: Binding<[AppRoute]> {
        Binding {
            Array((cut?.detail ?? []).dropFirst())
        } set: { tail in
            path = ListDetailPolicy.path(settingDetailTail: tail, in: path, section: section)
        }
    }
}
#endif
