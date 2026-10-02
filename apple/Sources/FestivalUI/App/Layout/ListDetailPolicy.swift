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
    /// Two windows qualify:
    /// - An iPhone Duo inner display (unfolded or partially folded, either orientation;
    ///   the shelved dual-source arrangement would replace it in portrait,
    ///   ``DualSourcePolicy/isEnabled``), measured by the window width.
    /// - The iPad sections sidebar shell (`sectionChrome == .sidebar`), measured by the
    ///   width actually left for the section beside the sidebar (`containerWidth`), so
    ///   showing or hiding the sidebar and resizing a Stage Manager window reflow live
    ///   (HIG Split views, iPadOS: "design for narrow, compact, and intermediate fluid
    ///   widths"). macOS keeps one stack until its own phase (``sidebarShellSplits``).
    ///
    /// A large iPhone in landscape is regular width but keeps its iPhone layout
    /// (`pose == .standard`, tab shell).
    ///
    /// - Parameters:
    ///   - layout: Published window layout.
    ///   - containerWidth: Width of the section's own container, when measured.
    ///   - sidebarShellSplits: Whether the sidebar shell splits (iPad: true).
    /// - Returns: True when list/detail sections should split.
    static func usesSplit(
        _ layout: DeviceLayout, containerWidth: CGFloat? = nil,
        sidebarShellSplits: Bool = ListDetailPolicy.sidebarShellSplits
    ) -> Bool {
        guard layout.contentArrangement == .listDetail else { return false }
        if layout.sectionChrome == .sidebar {
            return sidebarShellSplits && (containerWidth ?? layout.size.width) >= minimumSplitWidth
        }
        return layout.pose != .standard && layout.size.width >= minimumSplitWidth
    }

    /// Whether the sidebar shell splits list/detail pages: iPad yes; macOS not yet
    /// (Lane MAC decides its own columns).
    static var sidebarShellSplits: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Width of the list column beside a detail column in the iPad sidebar shell: 40 %
    /// of the section's width, kept between 320 and 420 pt so rows stay readable and
    /// the detail keeps the larger share (Mail-like proportions).
    ///
    /// - Parameter containerWidth: Width of the section's container.
    /// - Returns: The list column width.
    static func listColumnWidth(containerWidth: CGFloat) -> CGFloat {
        min(420, max(320, (containerWidth * 0.4).rounded()))
    }

    /// Narrowest window that fits two comfortable columns (operator, 2026-09-28: "two
    /// columns if width allows"). The Duo inner display in landscape (951 pt) splits;
    /// in portrait (669 pt, two ~330 pt columns) it keeps the full-width list.
    static let minimumSplitWidth: CGFloat = 760

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
    /// A list page on top of a wide enough window splits, and its detail column is
    /// always populated (operator, 2026-09-28: never an empty "Select a …" pane):
    /// `ListDetailStack` restores the last selection or auto-selects the first row
    /// that appears. A list that shows no row at all (`emptyListCollapsed`) falls back
    /// to one full-width stack instead of an empty column.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    ///   - layout: Published window layout.
    ///   - containerWidth: Width of the section's container, when measured.
    ///   - emptyListCollapsed: True once the list page produced no row to select.
    /// - Returns: The arrangement to render.
    static func arrangement(
        section: FestivalSection, path: [AppRoute], layout: DeviceLayout, containerWidth: CGFloat? = nil,
        emptyListCollapsed: Bool = false
    ) -> Arrangement {
        guard usesSplit(layout, containerWidth: containerWidth), let split = split(section: section, path: path) else { return .stack }
        if split.selection == nil, emptyListCollapsed { return .stack }
        return .split(split)
    }

    /// Whether a list page is on top of a split-capable window with nothing selected
    /// yet: the next row to appear (or a tap) becomes the detail.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    ///   - layout: Published window layout.
    ///   - containerWidth: Width of the section's container, when measured.
    /// - Returns: True while the next row tap should open the detail column.
    static func awaitsSelection(
        section: FestivalSection, path: [AppRoute], layout: DeviceLayout, containerWidth: CGFloat? = nil
    ) -> Bool {
        guard usesSplit(layout, containerWidth: containerWidth), let split = split(section: section, path: path) else { return false }
        return split.selection == nil
    }

    // MARK: Back (⌘[)

    /// The section path after the hardware-keyboard Back command (⌘[).
    ///
    /// In one stack it pops the top page. In a split it pops the column that has a
    /// Back button: the detail column's pushed page first, else the list column's
    /// pushed list page (with its detail); a split showing only its root list and the
    /// detail root has nothing to go back to.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    ///   - isSplit: Whether the section is currently shown as two columns.
    /// - Returns: The new path, or nil when there is nothing to go back to.
    static func pathAfterBack(section: FestivalSection, path: [AppRoute], isSplit: Bool) -> [AppRoute]? {
        guard !path.isEmpty else { return nil }
        guard isSplit, let split = split(section: section, path: path) else {
            return Array(path.dropLast())
        }
        if split.detail.count > 1 { return Array(path.dropLast()) }
        if !split.list.isEmpty { return Array(split.list.dropLast()) }
        return nil
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
