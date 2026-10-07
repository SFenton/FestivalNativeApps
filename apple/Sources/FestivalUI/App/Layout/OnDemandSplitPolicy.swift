import CoreGraphics
import Foundation

// MARK: - On-demand split policy

/// Pure rules for the on-demand split (`.agents/design/apple/split-view.md`, operator
/// 2026-10-04): a list page starts full width; selecting one of its items splits the
/// content area 50/50 at its exact vertical midpoint (iPhone Duo: at the hinge) and shows
/// the item in the trailing half; closing returns to full width.
///
/// The section's single `[AppRoute]` path stays the only navigation state. When the
/// window allows a split, the path is *viewed* as `list + detail`: the leading pane's
/// stack shows `list`, the trailing pane's stack shows `detail`. Everywhere else the
/// whole path is one pushed stack, so rotating, resizing or folding never loses the
/// open item: it is simply pushed (portrait) or lifted into the trailing pane again.
///
/// | List page (leading pane top) | Detail roots (trailing pane) |
/// |---|---|
/// | Rivals root, `.rivals`, `.allRivals` | `.rivalDetail` |
/// | Leaderboards root, `.leaderboards` | `.player`, `.band` |
/// | `.fullRankings` | `.player` |
/// | `.bandRankings` | `.band` |
/// | `.songDetail` | `.songLeaderboard`, `.playerHistory` |
/// | Settings root | `.licenses` |
///
/// Songs, Song Leaderboard, Item Shop, Suggestions, Statistics, Compete, Band Detail,
/// Player Bands and Rivalry never split: what they push opens full width.
enum OnDemandSplitPolicy {
    /// A page whose items open in the trailing pane.
    enum ListPage: Sendable, Equatable {
        /// Rivals hub or All Rivals.
        case rivals
        /// The Leaderboards overview (instrument and band cards).
        case leaderboards
        /// Full Rankings.
        case rankings
        /// Band Rankings.
        case bandRankings
        /// Song Detail (its full leaderboards and score history).
        case songDetail
        /// The Settings list (iPad, iPhone Duo; the Mac has a Settings window).
        case settings

        /// Whether a route pushed from this page opens in the trailing pane.
        ///
        /// - Parameter route: Route pushed directly from the list page.
        /// - Returns: True for this page's detail routes.
        func accepts(_ route: AppRoute) -> Bool {
            switch (self, route) {
            case (.rivals, .rivalDetail),
                 (.leaderboards, .player), (.leaderboards, .band),
                 (.rankings, .player),
                 (.bandRankings, .band),
                 (.songDetail, .songLeaderboard), (.songDetail, .playerHistory),
                 (.settings, .licenses):
                true
            default:
                false
            }
        }
    }

    /// A path cut at its first detail route.
    struct Cut: Sendable, Equatable {
        /// Routes pushed in the leading pane (its root is the section root).
        let list: [AppRoute]
        /// The trailing pane: the detail root first, then deeper pushes. Empty while
        /// nothing is open (the list page is full width).
        let detail: [AppRoute]
        /// The list page on top of the leading pane.
        let page: ListPage

        /// The open item's route, if any.
        var selection: AppRoute? { detail.first }
    }

    /// Narrowest pane: each half must be at least this wide for the split to apply.
    static let minimumPaneWidth: CGFloat = 360

    // MARK: Path cut

    /// The list page a section's root screen is, if any.
    ///
    /// - Parameter section: Root section.
    /// - Returns: Rivals, Leaderboards or Settings; nil for every other root.
    static func rootPage(of section: FestivalSection) -> ListPage? {
        switch section {
        case .rivals: .rivals
        case .leaderboards: .leaderboards
        case .settings: .settings
        default: nil
        }
    }

    /// The list page a pushed route is, if any.
    ///
    /// - Parameter route: A route in a section path.
    /// - Returns: The list page kind, or nil for pages that never split.
    static func page(of route: AppRoute) -> ListPage? {
        switch route {
        case .rivals, .allRivals: .rivals
        case .leaderboards: .leaderboards
        case .fullRankings: .rankings
        case .bandRankings: .bandRankings
        case .songDetail: .songDetail
        default: nil
        }
    }

    /// Cut a section path at its first detail route.
    ///
    /// The detail starts at the first route pushed directly from a list page that the
    /// page accepts. Without one the cut has an empty detail while a list page is on
    /// top (rows then open the trailing pane), else there is no cut.
    ///
    /// - Parameters:
    ///   - section: Section owning the path.
    ///   - path: The section's navigation path.
    /// - Returns: The cut, or nil when the top page is not a list page.
    static func cut(section: FestivalSection, path: [AppRoute]) -> Cut? {
        var owner = rootPage(of: section)
        for (index, route) in path.enumerated() {
            if let page = owner, page.accepts(route) {
                return Cut(list: Array(path[..<index]), detail: Array(path[index...]), page: page)
            }
            owner = page(of: route)
        }
        return owner.map { Cut(list: path, detail: [], page: $0) }
    }

    /// The section path after the leading pane's stack writes its path.
    ///
    /// An unchanged list keeps the open item; anything else (a pop, or a push of a
    /// page that is not a detail, such as "View all rankings") replaces the path, so
    /// the open item closes with the list page it belonged to. A detail route pushed
    /// by a plain link stays in the new path and the cut lifts it into the trailing pane.
    ///
    /// - Parameters:
    ///   - newList: Path the leading pane's stack wrote.
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The new section path.
    static func path(settingList newList: [AppRoute], in path: [AppRoute], section: FestivalSection) -> [AppRoute] {
        guard let cut = cut(section: section, path: path), newList == cut.list else { return newList }
        return path
    }

    /// The section path after the trailing pane's stack writes its path (every route
    /// after the detail root).
    ///
    /// - Parameters:
    ///   - tail: Path the trailing pane's stack wrote.
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The new path; unchanged while nothing is open.
    static func path(settingDetailTail tail: [AppRoute], in path: [AppRoute], section: FestivalSection) -> [AppRoute] {
        guard let cut = cut(section: section, path: path), let root = cut.selection else { return path }
        return cut.list + [root] + tail
    }

    /// The section path after selecting a list row: the list page plus the row's route
    /// (replacing any open item).
    ///
    /// - Parameters:
    ///   - route: The row's detail route.
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The new path.
    static func path(selecting route: AppRoute, in path: [AppRoute], section: FestivalSection) -> [AppRoute] {
        (cut(section: section, path: path)?.list ?? path) + [route]
    }

    /// The section path after closing the trailing pane (close button, Escape).
    ///
    /// - Parameters:
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The list-only path, or nil when nothing is open.
    static func pathClosingDetail(_ path: [AppRoute], section: FestivalSection) -> [AppRoute]? {
        guard let cut = cut(section: section, path: path), cut.selection != nil else { return nil }
        return cut.list
    }

    /// The section path after Back on the leading pane's page (issue #347): an open
    /// item closes first and the list page stays; with nothing open, the list page pops.
    ///
    /// - Parameters:
    ///   - path: Current section path.
    ///   - section: Section owning the path.
    /// - Returns: The new path, or nil when the leading pane is at its section root.
    static func pathAfterListBack(_ path: [AppRoute], section: FestivalSection) -> [AppRoute]? {
        if let closed = pathClosingDetail(path, section: section) { return closed }
        let list = cut(section: section, path: path)?.list ?? path
        return list.isEmpty ? nil : Array(list.dropLast())
    }

    // MARK: Geometry

    /// Where the two panes sit in the split's container.
    struct Geometry: Sendable, Equatable {
        /// Leading pane width (container leading edge to the divider band).
        let leadingWidth: CGFloat
        /// Divider band width: 1 pt at a midpoint, the hinge's own width on iPhone Duo.
        let dividerWidth: CGFloat
        /// Trailing pane width (divider band to the container trailing edge).
        let trailingWidth: CGFloat
        /// The divider band's centre in window coordinates.
        let dividerMidX: CGFloat
    }

    /// What the split needs to know about its container and window.
    struct Context: Sendable, Equatable {
        /// The split container's frame in window coordinates (leading-edge x).
        var container: CGRect
        /// Whether the window is landscape (iOS) or the platform has no portrait rule (Mac).
        var isLandscape: Bool
        /// Whether the window is regular width and height (iOS) or a Mac window.
        var isRegular: Bool
        /// A vertical hinge (iPhone Duo fold) in window coordinates, if any.
        var hinge: CGRect?
    }

    /// The width of the divider drawn at a midpoint (no hinge).
    static let midpointDividerWidth: CGFloat = 1

    /// The panes for a container, or nil when the split does not apply.
    ///
    /// The divider band is the hinge when a vertical hinge crosses the container,
    /// else 1 pt centred on the container's midpoint. Each pane runs from a container
    /// edge to the band, so an iPhone Duo vertical bar stays inside its pane rather
    /// than shifting the divider. The split applies in landscape, regular windows only,
    /// and only while each pane is at least ``minimumPaneWidth`` wide.
    ///
    /// - Parameter context: Container, orientation, size class and hinge.
    /// - Returns: The pane geometry, or nil (one full-width stack).
    static func geometry(_ context: Context) -> Geometry? {
        let box = context.container
        guard context.isLandscape, context.isRegular, box.width > 0 else { return nil }
        var band: ClosedRange<CGFloat>
        if let hinge = context.hinge, hinge.height >= hinge.width,
           hinge.midX > box.minX, hinge.midX < box.maxX {
            band = hinge.minX...hinge.maxX
        } else {
            band = box.midX...box.midX
        }
        if band.upperBound - band.lowerBound < midpointDividerWidth {
            let mid = (band.lowerBound + band.upperBound) / 2
            band = (mid - midpointDividerWidth / 2)...(mid + midpointDividerWidth / 2)
        }
        let leading = band.lowerBound - box.minX
        let trailing = box.maxX - band.upperBound
        guard leading >= minimumPaneWidth, trailing >= minimumPaneWidth else { return nil }
        return Geometry(
            leadingWidth: leading, dividerWidth: band.upperBound - band.lowerBound,
            trailingWidth: trailing, dividerMidX: (band.lowerBound + band.upperBound) / 2
        )
    }

    /// The context an iOS split reads from the published window layout.
    ///
    /// - Parameters:
    ///   - layout: Published window layout.
    ///   - container: The split container's frame in window coordinates.
    /// - Returns: The context (landscape, regular in both dimensions, the Duo hinge).
    static func context(layout: DeviceLayout, container: CGRect) -> Context {
        Context(
            container: container,
            isLandscape: layout.orientation == .landscape,
            isRegular: layout.windowWidthClass == .regular && layout.heightClass == .regular,
            hinge: layout.splitHinge
        )
    }
}
