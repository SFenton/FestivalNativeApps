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
    ///   ``DualSourcePolicy/isEnabled``): regular width and regular height (HIG Designing
    ///   for iPhone Duo: "Split views expand to multiple panes inner and one pane outer").
    /// - The iPad sidebar shell (`sectionChrome == .sidebar`) at least
    ///   ``minimumSidebarSplitWidth`` wide: sidebar, list and detail side by side.
    ///   Decided by the window alone, never by the sidebar's own width: the system
    ///   tiles or overlays the sidebar per width, and following it would flip the
    ///   layout while someone opens the sidebar. Rotation and window resizing reflow
    ///   live (HIG Split views, iPadOS: "design for narrow, compact, and intermediate
    ///   fluid widths"). macOS keeps one stack until its own phase (``sidebarShellSplits``).
    ///
    /// A large iPhone in landscape is regular width but compact height, so it keeps its
    /// iPhone layout. No width breakpoint or hinge pose is involved (`/duo` D2).
    ///
    /// - Parameters:
    ///   - layout: Published window layout.
    ///   - sidebarShellSplits: Whether the sidebar shell splits (iPad: true).
    /// - Returns: True when list/detail sections should split.
    static func usesSplit(
        _ layout: DeviceLayout, sidebarShellSplits: Bool = ListDetailPolicy.sidebarShellSplits
    ) -> Bool {
        guard layout.contentArrangement == .listDetail else { return false }
        if layout.sectionChrome == .sidebar {
            return sidebarShellSplits && layout.size.width >= minimumSidebarSplitWidth
        }
        // `/duo` D1/D2 (operator, 2026-10-02): size classes decide, in both orientations.
        return layout.isRegularInBothDimensions
    }

    /// Narrowest iPad window that shows sidebar, list and detail: three readable
    /// columns (320 + 320 + ~400 pt). An 11-inch iPad in landscape (1194 pt) splits;
    /// in portrait (834 pt) it shows the sidebar beside a full-width list.
    static let minimumSidebarSplitWidth: CGFloat = 1000

    /// Whether the sidebar shell splits list/detail pages: iPad yes; macOS not yet
    /// (Lane MAC decides its own columns).
    static var sidebarShellSplits: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Width the nested list column takes in the iPad sidebar shell (the system
    /// `.balanced` split's primary column, measured 320 pt on iPadOS 26.5).
    static let splitListColumnWidth: CGFloat = 320

    /// The detail column's width while a section shows list and detail, for the
    /// column's own width class (``DeviceLayout/column(width:)``).
    ///
    /// - iPad sidebar shell: the section's container minus the list column.
    /// - iPhone Duo inner display (`/duo` J3, operator 2026-10-02): the window inside
    ///   its horizontal safe area (the vertical bar in landscape) minus the list
    ///   column; with a vertical fold (book pose) the system equalises the columns at
    ///   the fold (HIG Designing for iPhone Duo: "split columns adjust width/margins
    ///   for inner-display symmetry"), so the detail starts after the fold. About
    ///   350 pt in portrait and 400–560 pt in landscape: compact, so a detail page
    ///   never draws two dashboard columns in half the display.
    ///
    /// - Parameters:
    ///   - layout: The section's inherited layout.
    ///   - containerWidth: The sidebar shell's width for the section, if any.
    /// - Returns: The detail width, or nil when the layout has no measured split.
    static func detailColumnWidth(layout: DeviceLayout, containerWidth: CGFloat?) -> CGFloat? {
        if layout.sectionChrome == .sidebar {
            return containerWidth.map { max(0, $0 - splitListColumnWidth) }
        }
        guard layout.isRegularInBothDimensions, layout.size.width > 0 else { return nil }
        let trailingEdge = layout.size.width - layout.safeAreaInsets.trailing
        if let fold = layout.foldFrame, fold.height > fold.width {
            return max(0, trailingEdge - fold.maxX)
        }
        return max(0, trailingEdge - layout.safeAreaInsets.leading - splitListColumnWidth)
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
    ///   - emptyListCollapsed: True once the list page produced no row to select.
    /// - Returns: The arrangement to render.
    static func arrangement(
        section: FestivalSection, path: [AppRoute], layout: DeviceLayout, emptyListCollapsed: Bool = false
    ) -> Arrangement {
        guard usesSplit(layout), let split = split(section: section, path: path) else { return .stack }
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
    /// - Returns: True while the next row tap should open the detail column.
    static func awaitsSelection(section: FestivalSection, path: [AppRoute], layout: DeviceLayout) -> Bool {
        guard usesSplit(layout), let split = split(section: section, path: path) else { return false }
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

    // MARK: Collapse

    /// The section path after its split collapses to one stack on iPad (portrait, a
    /// narrower window, or a compact window's tab shell): a detail nobody chose would
    /// stay pushed over the list, so it is popped, like Mail. A row the person picked
    /// (or anything pushed inside the detail) stays.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    ///   - automatic: The detail root the split chose by itself, if any.
    /// - Returns: The list-only path, or nil when nothing should change.
    static func pathDroppingAutomaticDetail(
        section: FestivalSection, path: [AppRoute], automatic: AppRoute?
    ) -> [AppRoute]? {
        guard let automatic, let split = split(section: section, path: path),
              split.detail == [automatic]
        else { return nil }
        return split.list
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
