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

// MARK: - List/detail stack

/// A section's navigation: one `FestivalTabStack` on iPhone and folded iPhone Duo,
/// or a `NavigationSplitView` (list column + detail `NavigationStack`) on a regular
/// width iPhone Duo inner display, as decided by ``ListDetailPolicy``.
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        switch ListDetailPolicy.arrangement(section: section, path: path, layout: layout) {
        case .stack:
            FestivalTabStack(
                session: session, visibleInstruments: visibleInstruments,
                path: $path, isVisible: isVisible
            ) {
                root(path.isEmpty)
                    // Full-width list awaiting its first selection: rows select (the
                    // detail column opens) instead of pushing and then re-splitting.
                    .transformEnvironment(\.listDetailSelect) { value in
                        guard ListDetailPolicy.awaitsSelection(section: section, path: path, layout: layout) else { return }
                        value = selectAction
                    }
            }
        case let .split(split):
            splitView(split)
        }
    }

    // MARK: Split

    /// Two columns over the section path.
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
                // `arrangement` only splits with a selection; nothing else to show.
                Group {
                    if let selection = split.selection {
                        destination(selection).id(selection)
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

    /// Create a link.
    ///
    /// - Parameters:
    ///   - value: Route pushed (or shown in the detail column).
    ///   - label: Row content.
    init(value: AppRoute, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        Group {
            if let select {
                Button { select(value) } label: { label }
            } else {
                NavigationLink(value: value) { label }
            }
        }
        .listDetailSelectable(value)
    }
}
