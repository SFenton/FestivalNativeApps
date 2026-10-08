import CoreGraphics
import Foundation
import SwiftUI

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
/// | Compete root, `.compete` | `.rivalDetail` (issue #369) |
/// | Leaderboards root, `.leaderboards` | `.fullRankings`, `.bandRankings`; `.player`, `.band` (full page) |
/// | `.songDetail` | `.songLeaderboard`, `.songBandLeaderboard` (issue #367), `.playerHistory` |
/// | Settings root | `.licenses` |
///
/// Songs, Song Leaderboard, Song Band Leaderboard, Full and Band Rankings, Item Shop,
/// Suggestions, Statistics, Band Detail, Player Bands and Rivalry never split: what
/// they push opens full width. Compete splits for its rival rows only; its leaderboard
/// previews, View Full Leaderboard and View All Rivals push full width (issue #369).
///
/// **Profiles are full pages** (issue #352, agent decision the owner may override):
/// a player or band profile never sits in a half pane. Opened from the list page it
/// covers the whole width, and opened inside the trailing pane (Full Rankings beside
/// Leaderboards, a song board beside Song Detail) the trailing pane widens over the list
/// page. The list page stays alive, hidden, behind it, so Back returns to it with its
/// place kept (``Cover``).
enum OnDemandSplitPolicy {
    /// A page whose items open in the trailing pane.
    enum ListPage: Sendable, Equatable {
        /// Rivals hub or All Rivals.
        case rivals
        /// The Compete hub: its rival rows open Rival Detail beside it (issue #369).
        case compete
        /// The Leaderboards overview (instrument and band cards).
        case leaderboards
        /// Song Detail (its full instrument and band leaderboards and score history).
        case songDetail
        /// The Settings list (iPad, iPhone Duo; the Mac has a Settings window).
        case settings

        /// Whether a route pushed from this page opens in the trailing pane.
        ///
        /// - Parameter route: Route pushed directly from the list page.
        /// - Returns: True for this page's detail routes.
        func accepts(_ route: AppRoute) -> Bool {
            switch (self, route) {
            case (.rivals, .rivalDetail), (.compete, .rivalDetail),
                 (.leaderboards, .fullRankings), (.leaderboards, .bandRankings),
                 (.leaderboards, .player), (.leaderboards, .band),
                 (.songDetail, .songLeaderboard), (.songDetail, .songBandLeaderboard),
                 (.songDetail, .playerHistory),
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

        /// How the open item shares the split with the list page.
        var cover: Cover {
            guard let selection else { return .none }
            if OnDemandSplitPolicy.isFullPage(selection) { return .overList }
            return detail.contains(where: OnDemandSplitPolicy.isFullPage) ? .overSplit : .none
        }
    }

    /// Whether the trailing pane covers the list page (issue #352: profiles are full
    /// pages). A covered list page stays alive behind it, hidden from sight, touch and
    /// assistive technologies, so Back returns to it with its place kept.
    enum Cover: Sendable, Equatable {
        /// Side by side, or nothing open.
        case none
        /// A profile pushed inside the trailing pane (Full Rankings › player): the pane
        /// widens over the whole split and the hidden list page keeps its half width.
        case overSplit
        /// The open item is itself a profile (Leaderboards › player): it covers the
        /// whole width and the hidden list page keeps the full width it had. iOS pushes
        /// it on the leading stack instead (a real push, with the system Back and its
        /// edge swipe); the Mac covers the list in the trailing pane.
        case overList
    }

    /// Whether a route is a full page that never sits in a half pane: a player or band
    /// profile (issue #352).
    ///
    /// - Parameter route: Any route.
    /// - Returns: True for `.player` and `.band`.
    static func isFullPage(_ route: AppRoute) -> Bool {
        switch route {
        case .player, .band: true
        default: false
        }
    }

    /// Narrowest pane: each half must be at least this wide for the split to apply.
    static let minimumPaneWidth: CGFloat = 360

    // MARK: Path cut

    /// The list page a section's root screen is, if any.
    ///
    /// - Parameter section: Root section.
    /// - Returns: Rivals, Compete, Leaderboards or Settings; nil for every other root.
    static func rootPage(of section: FestivalSection) -> ListPage? {
        switch section {
        case .rivals: .rivals
        case .compete: .compete
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
        case .compete: .compete
        case .leaderboards: .leaderboards
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
    /// page that is not a detail, such as Songs from Song Detail) replaces the path, so
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
        /// Whether the band is a vertical hinge (iPhone Duo) rather than a midpoint.
        var isHinge = false
    }

    /// What the split needs to know about its container and window.
    struct Context: Sendable, Equatable {
        /// The split container's frame in window coordinates (leading-edge x).
        var container: CGRect
        /// Whether the window is landscape (iOS) or the platform has no portrait rule (Mac).
        var isLandscape: Bool
        /// Whether the window is regular width and height (iOS) or a Mac window.
        var isRegular: Bool
        /// A vertical hinge (iPhone Duo book-pose fold) in window coordinates, if any.
        var hinge: CGRect?
        /// The window's free horizontal span (inside the safe area, without the iPhone
        /// Duo vertical bar) in window coordinates; nil to use the whole container.
        var freeSpan: ClosedRange<CGFloat>?
    }

    /// The width of the divider band at a midpoint (no hinge).
    static let midpointDividerWidth: CGFloat = 1

    /// Whether the divider band draws its 1 pt hairline.
    ///
    /// The panes are separated by the band's space and each pane's full-page margins, not
    /// by a drawn line (owner #344: "Split View should not have visible vertical splitter
    /// component"). Increase Contrast restores the hairline at a midpoint (HIG
    /// Accessibility: provide a higher-contrast scheme when Increase Contrast is on); a
    /// hinge never draws one, the fold itself divides the panes.
    ///
    /// - Parameters:
    ///   - geometry: The open split's geometry.
    ///   - increasedContrast: Whether the system's Increase Contrast setting is on.
    /// - Returns: True to draw the hairline at the band's centre.
    static func drawsDividerLine(_ geometry: Geometry, increasedContrast: Bool) -> Bool {
        increasedContrast && !geometry.isHinge
    }

    /// The panes for a container, or nil when the split does not apply.
    ///
    /// The divider band is the hinge when a vertical hinge crosses the container (book
    /// pose), else 1 pt centred on the midpoint of the container's free space: the part
    /// of it inside ``Context/freeSpan``, so a flat iPhone Duo divides the content beside
    /// its vertical bar in half rather than at the hinge (owner, issue #361). Each pane
    /// runs from a container edge to the band, so the vertical bar stays inside its pane.
    /// The split applies in landscape, regular windows only, and only while each pane is
    /// at least ``minimumPaneWidth`` wide.
    ///
    /// - Parameter context: Container, orientation, size class and hinge.
    /// - Returns: The pane geometry, or nil (one full-width stack).
    static func geometry(_ context: Context) -> Geometry? {
        let box = context.container
        guard context.isLandscape, context.isRegular, box.width > 0 else { return nil }
        var band: ClosedRange<CGFloat>
        var isHinge = false
        if let hinge = context.hinge, hinge.height >= hinge.width,
           hinge.midX > box.minX, hinge.midX < box.maxX {
            band = hinge.minX...hinge.maxX
            isHinge = true
        } else {
            let mid = freeMidX(container: box, freeSpan: context.freeSpan)
            band = mid...mid
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
            trailingWidth: trailing, dividerMidX: (band.lowerBound + band.upperBound) / 2,
            isHinge: isHinge
        )
    }

    /// The midpoint of the part of `container` inside `freeSpan`, or of the whole
    /// container when there is no free span or it misses the container.
    ///
    /// - Parameters:
    ///   - container: The split container in window coordinates.
    ///   - freeSpan: The window's free horizontal span, if known.
    /// - Returns: The x of the free space's midpoint, in window coordinates.
    static func freeMidX(container: CGRect, freeSpan: ClosedRange<CGFloat>?) -> CGFloat {
        guard let freeSpan else { return container.midX }
        let lower = max(container.minX, freeSpan.lowerBound)
        let upper = min(container.maxX, freeSpan.upperBound)
        return upper > lower ? (lower + upper) / 2 : container.midX
    }

    // MARK: - Window changes (fold, rotation, resize)

    /// Whether the window allows a split, and whether its container has been measured.
    struct WindowState: Sendable, Equatable {
        /// The split container has a non-zero measured width.
        var measured: Bool
        /// ``geometry(_:)`` returns panes for the window.
        var allowsSplit: Bool
    }

    /// Whether a change in what the window allows waits a run-loop turn before the
    /// stacks change shape.
    ///
    /// Folding iPhone Duo with a split open (#346) moved the window to the outer display,
    /// changed its size class, pushed the open item onto the leading stack and removed the
    /// trailing stack, all in one animated update: the outer display stayed black until
    /// unfolded. As for the tab set (`ShellPresentation.applying`), the split keeps its
    /// shape while the window changes and applies the new one, unanimated, a turn later.
    /// The first measurement applies at once, so launch never shows a pushed frame first.
    ///
    /// - Parameters:
    ///   - old: The window state before the change.
    ///   - new: The window state after it.
    /// - Returns: True when the change should apply one run-loop turn later.
    static func defersWindowChange(from old: WindowState, to new: WindowState) -> Bool {
        old.measured && new.measured && old.allowsSplit != new.allowsSplit
    }

    /// The panes to lay out while a window change may be pending.
    ///
    /// - Parameters:
    ///   - live: The panes the window allows now, or nil.
    ///   - held: The last panes the window allowed, or nil.
    ///   - applied: Whether the applied shape is split; nil before the first one.
    /// - Returns: `live` once applied; while a collapse is pending, `held` (the stacks keep
    ///   their shape); while an expansion is pending, nil (one stack).
    static func appliedGeometry(live: Geometry?, held: Geometry?, applied: Bool?) -> Geometry? {
        switch applied {
        case nil: live
        case true?: live ?? held
        case false?: nil
        }
    }

    /// The context an iOS split reads from the published window layout.
    ///
    /// - Parameters:
    ///   - layout: Published window layout.
    ///   - container: The split container's frame in window coordinates.
    ///   - layoutDirection: The split's layout direction (which side the safe-area
    ///     insets are on in window coordinates).
    /// - Returns: The context (landscape, regular in both dimensions, the Duo book-pose
    ///   hinge, the window's free span).
    static func context(
        layout: DeviceLayout, container: CGRect, layoutDirection: LayoutDirection = .leftToRight
    ) -> Context {
        Context(
            container: container,
            isLandscape: layout.orientation == .landscape,
            isRegular: layout.windowWidthClass == .regular && layout.heightClass == .regular,
            hinge: layout.splitHinge,
            freeSpan: layout.freeSpan(layoutDirection: layoutDirection)
        )
    }
}
