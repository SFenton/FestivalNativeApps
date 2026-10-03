// MARK: - Root tab selection

/// A tab in the phone tab bar: a root section, or the trailing Search tab (issue #92).
///
/// Search is not a ``FestivalSection``: it owns no navigation path and is transient.
/// HIG Search fields: a separate trailing search tab "focuses the field and opens the
/// keyboard immediately ... choose it for fast, transient search that returns to the
/// previous tab on exit". The section selected before Search therefore stays selected
/// underneath it, and leaving Search returns there without popping its stack.
enum RootTab: Hashable {
    /// A root section's tab.
    case section(FestivalSection)
    /// The trailing Search tab (`Tab(role: .search)`).
    case search
}

/// What the shell does when the tab bar, the search field or a search result changes
/// the selection (pure, so ``RootTabTransitionTests`` pins it).
enum RootTabTransition: Equatable {
    /// Nothing changes (the Search tab was tapped again).
    case none
    /// Show the Search tab over the current section.
    case openSearch
    /// Leave Search, back to the section selected before it, keeping its stack.
    case closeSearch
    /// Leave Search, if open, and select a section with the usual tab semantics
    /// (re-selecting the current section outside Search pops it to its root).
    case select(FestivalSection)
    /// Leave Search and push a result on the section selected before it.
    case push(AppRoute)

    /// The transition for a tab-bar selection.
    ///
    /// - Parameters:
    ///   - next: The tab the user chose.
    ///   - selected: The section selected now (underneath Search while it is open).
    ///   - searchActive: Whether the Search tab is showing.
    /// - Returns: The transition to perform.
    static func choose(_ next: RootTab, selected: FestivalSection, searchActive: Bool) -> RootTabTransition {
        switch next {
        case .search:
            return searchActive ? .none : .openSearch
        case let .section(section):
            // Returning to the tab Search was opened from keeps its stack (transient search).
            if searchActive && section == selected { return .closeSearch }
            return .select(section)
        }
    }

    /// The transition when the search field is dismissed (Cancel or the close button).
    ///
    /// - Parameter searchActive: Whether the Search tab is showing.
    /// - Returns: ``closeSearch`` while Search shows, else ``none``.
    static func dismissSearch(searchActive: Bool) -> RootTabTransition {
        searchActive ? .closeSearch : .none
    }

    /// The transition for a chosen search result.
    ///
    /// - Parameter route: The result's page.
    /// - Returns: ``push(_:)``: the result opens on the previous tab, like the search
    ///   sheet it replaces, so Search stays transient and every page keeps one owner.
    static func openResult(_ route: AppRoute) -> RootTabTransition {
        .push(route)
    }
}
