import SwiftUI
import FestivalCore

// MARK: - Search tab

/// Global search as the trailing Search tab of the phone tab bar (issue #92).
///
/// HIG Search fields: a separate trailing search tab "focuses the field and opens the
/// keyboard immediately ... choose it for fast, transient search that returns to the
/// previous tab on exit"; HIG Tab bars: "A dedicated Search tab may be trailing". The
/// system `.searchable` field holds the query (on iOS 26 it rises from the tab bar), the
/// scope bar and results are the shared ``GlobalSearchResults``. Dismissing the field
/// returns to the previous tab; a result opens there too
/// (``RootTabTransition/openResult(_:)``).
///
/// On the iPhone Duo inner display the system field left the bottom trailing ~370 pt of
/// the page, out of line with the full-width scope bar, so the tab shows the shared
/// ``BottomSearchField`` instead, with the scope bar in the same column
/// (``GlobalSearchFieldPlacement``, issue #349).
struct GlobalSearchTab: View {
    let session: FestivalSession
    @Bindable var model: GlobalSearchModel
    /// The Search tab (or sidebar row) is showing.
    let isSelected: Bool
    /// The phone Search tab: focus the field when chosen, return to the previous tab when
    /// it is dismissed. False in the iPad sidebar's detail column, which leaves the field
    /// unfocused (HIG Search fields: "on iPad with only a virtual keyboard, leave it
    /// unfocused to avoid unexpected keyboard coverage") and shows the account items.
    let asTab: Bool
    /// Open a result on the previous tab.
    let open: (AppRoute) -> Void
    /// The field was dismissed: return to the previous tab.
    let dismiss: () -> Void
    @State private var fieldPresented = false
    @Environment(\.deviceLayout) private var layout
    /// The bottom field's top in ``pageSpace``, for the result rows' fade.
    @State private var bottomFieldTop: CGFloat?

    /// Coordinate space shared by the bottom field and the faded result rows.
    static let pageSpace = "fst.global-search.page"

    var body: some View {
        let hasBottomField = GlobalSearchFieldPlacement.resolve(pose: layout.pose, asTab: asTab) == .bottom
        let hinge = BottomSearchFieldPlacement.pageHinge(for: layout)
        NavigationStack {
            GlobalSearchResults(
                model: model, session: session, open: open, showsField: false,
                hasBottomField: hasBottomField, bottomFieldHinge: hinge,
                bottomFieldTop: bottomFieldTop, bottomFieldSpace: Self.pageSpace
            )
                // iPhone Duo inner display: the field at the bottom, full width, or on the
                // trailing page across a book-pose fold (owner, issue #349). A bottom
                // safe-area inset, so results end above it and the keyboard lifts it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if hasBottomField {
                        BottomSearchField(
                            text: $model.query, prompt: GlobalSearch.prompt(for: model.scope),
                            accessibilityLabel: "Search songs, players and bands",
                            identifier: "fst.global-search.field",
                            clearIdentifier: "fst.global-search.clear", hinge: hinge,
                            focusesOnAppear: isSelected, submit: { model.submit() },
                            space: Self.pageSpace
                        ) { top in
                            if top != bottomFieldTop { bottomFieldTop = top }
                        }
                    }
                }
                .coordinateSpace(.named(Self.pageSpace))
                .navigationTitle("Search")
                .modifier(SearchTitleDisplayMode(style: GlobalSearchTitleStyle.resolve(asTab: asTab)))
                .festivalBackground(.carousel, session: session, visible: isSelected)
                .modifier(GlobalSearchSystemField(
                    text: $model.query, isPresented: $fieldPresented,
                    prompt: GlobalSearch.prompt(for: model.scope), enabled: !hasBottomField
                ))
                // No Retry button (issue #299): Search re-runs a failed or empty search.
                .onSubmit(of: .search) { model.submit() }
                .modifier(KeepSearchTitleWhileSearching())
                .task(id: model.runKey) { await model.search(session: session) }
                .modifier(SearchPageChrome(session: session, enabled: !asTab))
                .rootTabBarVisibility()
        }
        .onAppear { if asTab && isSelected { fieldPresented = true } }
        // Focus the field (and raise the keyboard) every time the tab is chosen; iOS 26
        // also does this itself (`tabViewSearchActivation(.searchTabSelection)`).
        .onChange(of: isSelected) { _, selected in
            if asTab && selected { fieldPresented = true }
        }
        .onChange(of: fieldPresented) { wasPresented, presented in
            if asTab, wasPresented, !presented, isSelected { dismiss() }
        }
    }
}

// MARK: - Field placement

/// Where the Search tab's field sits (issue #349).
///
/// The system `.searchable` field everywhere but the iPhone Duo inner display. There,
/// beside the vertical tab bar, the system field took only the bottom trailing ~370 pt
/// and rose centred over the keyboard while the scope bar spanned the page. The owner
/// asked for a field across the full bottom width when flat, on the right page when
/// book-folded ("search bar when keyboard is closed and unfolded should take full
/// bottom width. Can stay on right side if hinge is unfolded but device is not
/// completely unfolded"), which no system search API sets, so the tab shows the shared
/// ``BottomSearchField`` (Songs' Duo field, issue #333) and the scope bar shares its
/// column. HIG Search fields: "Place search at the bottom if there's room; this keeps
/// priority search easy to reach". The folded outer display keeps the system field,
/// which already spans its bottom like an iPhone's.
enum GlobalSearchFieldPlacement: Equatable {
    /// The system `.searchable` field of the Search tab (or the iPad sidebar page).
    case system
    /// The tab's own ``BottomSearchField`` (iPhone Duo inner display).
    case bottom

    /// The placement for a device pose.
    ///
    /// - Parameters:
    ///   - pose: The window's ``DeviceLayout/pose``.
    ///   - asTab: Whether search is the phone Search tab (false: the iPad sidebar page).
    /// - Returns: `.bottom` for the Search tab on an unfolded or partially folded iPhone
    ///   Duo, else `.system`.
    nonisolated static func resolve(pose: DeviceLayout.Pose, asTab: Bool) -> GlobalSearchFieldPlacement {
        guard asTab else { return .system }
        switch pose {
        case .unfolded, .partiallyFolded: return .bottom
        case .standard, .folded: return .system
        }
    }
}

/// The system `.searchable` Search field, left off where the tab shows its own bottom
/// field (iPhone Duo inner display, issue #349).
private struct GlobalSearchSystemField: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String
    /// Whether this window uses the system field (``GlobalSearchFieldPlacement/system``).
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, isPresented: $isPresented, prompt: Text(prompt))
        } else {
            content
        }
    }
}

/// Keeps the "Search" navigation title on screen while the field is active (issue #100).
///
/// Choosing the Search tab activates its field at once, and `.searchable` hides the
/// navigation bar on activation by default, so the page never showed its title. HIG
/// VoiceOver: "Give each page or screen a unique, succinct title describing its content
/// and purpose; assistive technology announces it first." `ProfileSelectionSheet` keeps
/// its title the same way. No-op before iOS 17.1 and on macOS (search is a sheet there).
private struct KeepSearchTitleWhileSearching: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 17.1, *) {
            content.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Title style

/// How the Search page draws its large "Search" title (issue #611).
///
/// The transient phone Search tab has nothing in its navigation bar (no drawer, bell or
/// Profile; HIG Search fields: a Search tab is "fast, transient search that returns to
/// the previous tab on exit"), so the standard large title left that bar's whole row
/// empty above it: a 54 pt dead band between the status bar and "Search" that every
/// other root fills with its drawer and Profile buttons. The tab draws the same large
/// system title inside that row instead (`ToolbarTitleDisplayMode.inlineLarge`), so the
/// scope bar sits directly under it. The iPad sidebar's Search page keeps the standard
/// large title: its row holds the bell and Profile.
enum GlobalSearchTitleStyle: Equatable {
    /// The large title inside the navigation bar's row (the phone Search tab).
    case inlineLarge
    /// The system default: the large title below the bar's row (iPad sidebar page).
    case standard

    /// The title style for a Search page.
    ///
    /// - Parameter asTab: Whether search is the phone Search tab (false: the iPad
    ///   sidebar page, whose bar row holds the account items).
    /// - Returns: `.inlineLarge` for the Search tab, else `.standard`.
    nonisolated static func resolve(asTab: Bool) -> GlobalSearchTitleStyle {
        asTab ? .inlineLarge : .standard
    }
}

/// Applies ``GlobalSearchTitleStyle`` (iOS; macOS shows search in a sheet).
private struct SearchTitleDisplayMode: ViewModifier {
    let style: GlobalSearchTitleStyle

    func body(content: Content) -> some View {
        #if os(iOS)
        switch style {
        case .inlineLarge: content.toolbarTitleDisplayMode(.inlineLarge)
        case .standard: content
        }
        #else
        content
        #endif
    }
}

/// The account items (bell, profile) on the iPad sidebar's search page, like every other
/// page in the detail column; the transient phone Search tab has none.
private struct SearchPageChrome: ViewModifier {
    let session: FestivalSession
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.festivalRootChrome(session: session)
        } else {
            content
        }
    }
}

// MARK: - Tab bar behaviour

/// iOS 26 tab-bar behaviour for the root tabs (issue #92).
///
/// - Choosing the Search tab activates its field (`.searchTabSelection`), so the keyboard
///   comes up at once (HIG Search fields).
/// - The horizontal tab bar minimizes on scroll down, to the current tab and Search;
///   the iPhone floating page tools above it stay put (issue #632).
struct RootTabBarBehavior: ViewModifier {
    @Environment(\.deviceLayout) private var layout

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content
                .tabViewSearchActivation(.searchTabSelection)
                .tabBarMinimizeBehavior(layout.sectionChrome == .tabBar ? .onScrollDown : .automatic)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
