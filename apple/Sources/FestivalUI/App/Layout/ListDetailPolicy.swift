import Foundation

// MARK: - List/detail policy

/// Pure rules for presenting a section's navigation path as one stack or as a
/// list column plus a detail column (`.agents/design/apple/duo.md`, "List/detail pages").
///
/// The section's single `[AppRoute]` path stays the only navigation state. On a
/// regular-width iPhone Duo inner display the path is *viewed* as `list + detail`;
/// everywhere else it is one stack. Because ``split(section:path:)`` only cuts the
/// path and ``path(settingList:in:section:)`` / ``path(settingDetailTail:in:section:)``
/// only re-join it, folding and unfolding never lose the selected detail: folded, the
/// detail is simply pushed on the compact stack; unfolded, the first detail route is
/// lifted into the detail column again.
///
/// | List page (list column top) | Detail root (detail column) |
/// |---|---|
/// | Songs root | `.songDetail` |
/// | `.fullRankings` | `.player` |
/// | Rivals root, `.rivals`, `.allRivals` | `.rivalDetail` |
///
/// List pages are recognised by route, not only by section, so a path carried between
/// tab slots (Compete › Rivals › Rival → Leaderboards on unfold) still splits.
enum ListDetailPolicy {
    /// Kind of list page on top of the list column; it decides which pushes become the
    /// detail and the empty-selection placeholder.
    enum ListPage: Sendable, Equatable {
        /// The Songs list (Songs root).
        case songs
        /// Full Rankings.
        case rankings
        /// Rivals hub or All Rivals.
        case rivals

        /// Whether a route pushed from this page is its detail.
        ///
        /// - Parameter route: Route pushed directly from the list page.
        /// - Returns: True for this page's detail route.
        func accepts(_ route: AppRoute) -> Bool {
            switch (self, route) {
            case (.songs, .songDetail), (.rankings, .player), (.rivals, .rivalDetail): true
            default: false
            }
        }
    }

    /// A path cut into its list column and detail column.
    struct Split: Sendable, Equatable {
        /// Routes pushed in the list column (its root is the section root).
        let list: [AppRoute]
        /// Detail column: its root route first, then deeper pushes. Empty when nothing
        /// is selected (the placeholder shows).
        let detail: [AppRoute]
        /// The list page on top of the list column.
        let page: ListPage

        /// The selected row's route, if any.
        var selection: AppRoute? { detail.first }
    }

    /// How a section presents its path in the current window.
    enum Arrangement: Sendable, Equatable {
        /// One `NavigationStack` over the whole path (iPhone, Duo folded, or no list page on top).
        case stack
        /// `NavigationSplitView`: list column plus detail column.
        case split(Split)
    }

    /// Sections whose paths may split. Other sections are single pages that use the
    /// width instead (`.agents/design/apple/duo.md`).
    static let splittableSections: Set<FestivalSection> = [.songs, .leaderboards, .rivals]

    // MARK: Layout gate

    /// Whether a window shows list/detail pages as two columns.
    ///
    /// Only an iPhone Duo inner display in landscape qualifies for now (unfolded, or
    /// partially folded like a book). In portrait the inner display stacks two regions
    /// instead (``DeviceLayout/ContentArrangement/dualSource``, `DualSourceLayout`): two
    /// ~330 pt columns crossed by a horizontal fold read worse than one full-width
    /// stack with a related second source below it. A large iPhone in landscape is
    /// regular width but keeps its iPhone layout (`pose == .standard`); iPad
    /// (`.standard`, sidebar shell) joins in the iPadOS phase, which must first decide
    /// how this nests in its sections sidebar.
    ///
    /// - Parameter layout: Published window layout.
    /// - Returns: True when list/detail sections should split.
    static func usesSplit(_ layout: DeviceLayout) -> Bool {
        layout.contentArrangement == .listDetail && layout.pose != .standard
    }

    // MARK: Path split

    /// The list page a section's root screen is, if any.
    ///
    /// - Parameter section: Root section.
    /// - Returns: `.songs` for Songs, `.rivals` for Rivals, else nil (Leaderboards'
    ///   overview is a dashboard, not a list).
    static func rootPage(of section: FestivalSection) -> ListPage? {
        switch section {
        case .songs: .songs
        case .rivals: .rivals
        default: nil
        }
    }

    /// The list page a pushed route is, if any.
    ///
    /// - Parameter route: A route in a section path.
    /// - Returns: The list page kind, or nil for every other page.
    static func page(of route: AppRoute) -> ListPage? {
        switch route {
        case .fullRankings: .rankings
        case .rivals, .allRivals: .rivals
        default: nil
        }
    }

    /// Cut a section path into list and detail columns.
    ///
    /// The detail starts at the first route pushed directly from a list page that the
    /// page accepts as its detail. With no such route, the path splits with an empty
    /// detail only while a list page is on top; otherwise (Shop, a player opened from
    /// the Leaderboards overview, …) it stays one stack.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    /// - Returns: The split, or nil when the path should stay one stack.
    static func split(section: FestivalSection, path: [AppRoute]) -> Split? {
        guard splittableSections.contains(section) else { return nil }
        var owner = rootPage(of: section)
        for (index, route) in path.enumerated() {
            if let page = owner, page.accepts(route) {
                return Split(list: Array(path[..<index]), detail: Array(path[index...]), page: page)
            }
            owner = page(of: route)
        }
        return owner.map { Split(list: path, detail: [], page: $0) }
    }

    /// Decide stack or split for a section path in a window.
    ///
    /// Only a selected detail opens the second column: with nothing selected the list
    /// stays one full-width stack instead of reserving an empty "Select a …" pane
    /// (operator, 2026-09-28). Rows still select rather than push (``awaitsSelection(section:path:layout:)``),
    /// so the first selection opens the detail column without a push animation.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    ///   - layout: Published window layout.
    /// - Returns: The arrangement to render.
    static func arrangement(
        section: FestivalSection, path: [AppRoute], layout: DeviceLayout
    ) -> Arrangement {
        guard usesSplit(layout), let split = split(section: section, path: path), split.selection != nil else {
            return .stack
        }
        return .split(split)
    }

    /// Whether a list page is on top of a split-capable window with nothing selected:
    /// the list is shown full width, and its rows select into a detail column that
    /// opens on the first selection.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    ///   - layout: Published window layout.
    /// - Returns: True while the next row tap should open the detail column.
    static func awaitsSelection(section: FestivalSection, path: [AppRoute], layout: DeviceLayout) -> Bool {
        guard usesSplit(layout), let split = split(section: section, path: path) else { return false }
        return split.selection == nil
    }

    // MARK: Column writes

    /// The section path after the list column's `NavigationStack` writes its path.
    ///
    /// A pop drops the detail with the list page it belonged to; a push replaces the
    /// detail (tapping a row pushes onto the list column, and ``split(section:path:)``
    /// then lifts the pushed detail route into the detail column, so the list never
    /// visibly pushes it). An unchanged list keeps the current detail.
    ///
    /// - Parameters:
    ///   - newList: Path the list column's stack wrote.
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The new section path.
    static func path(
        settingList newList: [AppRoute], in path: [AppRoute], section: FestivalSection
    ) -> [AppRoute] {
        guard let split = split(section: section, path: path), newList == split.list else {
            return newList
        }
        return path
    }

    /// The section path after the detail column's `NavigationStack` writes its path
    /// (every detail route after the detail root).
    ///
    /// - Parameters:
    ///   - tail: Path the detail column's stack wrote.
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The new section path; unchanged when nothing is selected.
    static func path(
        settingDetailTail tail: [AppRoute], in path: [AppRoute], section: FestivalSection
    ) -> [AppRoute] {
        guard let split = split(section: section, path: path), let root = split.selection else {
            return path
        }
        return split.list + [root] + tail
    }
}
