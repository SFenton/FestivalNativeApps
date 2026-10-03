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

    var body: some View {
        NavigationStack {
            GlobalSearchResults(model: model, session: session, open: open, showsField: false)
                .navigationTitle("Search")
                .festivalBackground(.carousel, session: session, visible: isSelected)
                .searchable(
                    text: $model.query, isPresented: $fieldPresented,
                    prompt: Text(GlobalSearch.prompt(for: model.scope))
                )
                .modifier(KeepSearchTitleWhileSearching())
                .task(id: model.runKey) { await model.search(session: session) }
                .modifier(SearchPageChrome(session: session, enabled: !asTab))
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
/// - The horizontal tab bar minimizes on scroll down, to the current tab and Search,
///   with nothing riding on it (HIG Tab bars: "scrolling down can minimize the bar").
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
