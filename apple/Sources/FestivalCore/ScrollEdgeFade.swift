import Foundation

// MARK: - Scroll edge fade

/// Where scrolling rows fade out above chrome pinned to the bottom of a page, like
/// the web's `useScrollFade` (36 px, `FortniteFestivalWeb/src/hooks/ui/useScrollFade.ts`):
/// rows are fully drawn until `distance` above the chrome's top edge, fade to clear
/// at that edge and are not drawn beneath the chrome at all (issue #93).
public enum ScrollEdgeFade {
    /// Web `DEFAULT_DISTANCE`: the height of the fade above the chrome.
    public static let distance: Double = 36

    /// Unit gradient locations (0 = top of the masked area, 1 = bottom).
    public struct Stops: Equatable, Sendable {
        /// Last fully opaque location; the fade starts here.
        public let fadeStart: Double
        /// First fully clear location: the chrome's top edge.
        public let fadeEnd: Double

        /// - Parameters:
        ///   - fadeStart: Last fully opaque location.
        ///   - fadeEnd: First fully clear location.
        public init(fadeStart: Double, fadeEnd: Double) {
            self.fadeStart = fadeStart
            self.fadeEnd = fadeEnd
        }
    }

    /// Fade stops for a masked area whose bottom `obscured` points sit under chrome.
    ///
    /// - Parameters:
    ///   - height: Height of the masked area, including the part under the chrome.
    ///   - obscured: Height of the area's bottom covered by the chrome.
    ///   - distance: Height of the fade above the chrome.
    /// - Returns: Clamped unit stops; an empty or invalid area stays fully opaque.
    public static func bottom(height: Double, obscured: Double, distance: Double = distance) -> Stops {
        guard height.isFinite, height > 0, obscured.isFinite, distance.isFinite else {
            return Stops(fadeStart: 1, fadeEnd: 1)
        }
        let end = min(max((height - max(0, obscured)) / height, 0), 1)
        let start = min(max((height - max(0, obscured) - max(0, distance)) / height, 0), end)
        return Stops(fadeStart: start, fadeEnd: end)
    }

    /// Height of the bottom fade for how far the list's last row still runs past its
    /// resting place above the chrome.
    ///
    /// The web drops its bottom fade once the list is scrolled to the end
    /// (`useScrollFade` `atBottom`); here the fade shrinks with the remaining scroll,
    /// so it never pops and the last row comes to rest unfaded, one row gap above the
    /// chrome, with no reserved band under it (issue #293).
    ///
    /// - Parameters:
    ///   - lastRowOverflow: Points the last row's bottom sits below its resting
    ///     position (``contentOverflow(contentHeight:offsetY:containerHeight:bottomInset:)``);
    ///     nil when unknown.
    ///   - distance: Full fade height.
    /// - Returns: A fade height between 0 and `distance`.
    public static func bottomDistance(lastRowOverflow: Double?, distance: Double = distance) -> Double {
        let full = distance.isFinite ? max(0, distance) : 0
        guard let lastRowOverflow else { return full }
        guard lastRowOverflow.isFinite else { return lastRowOverflow > 0 ? full : 0 }
        return min(max(lastRowOverflow, 0), full)
    }

    /// How far a scroll view's content still runs below its unobscured bottom edge:
    /// positive while there is more to scroll, 0 at the end, negative when the content
    /// is shorter than the view or overscrolled past its end (issue #293).
    ///
    /// Measured from the scroll view itself rather than from the last row: a row in a
    /// `List` did not report its moving frame while scrolling, so the fade stayed on it.
    ///
    /// - Parameters:
    ///   - contentHeight: Height of the scrollable content (including its last row's
    ///     bottom inset).
    ///   - offsetY: Vertical content offset (negative under a top inset).
    ///   - containerHeight: Full height of the scroll view, including the regions
    ///     under its insets (`ScrollGeometry.visibleRect`; a `ScrollView`'s
    ///     `containerSize` leaves its safe-area insets out, issue #305).
    ///   - bottomInset: Content inset at the bottom (pinned chrome and safe area).
    /// - Returns: Points of content past the unobscured bottom, or nil for a
    ///   non-finite input.
    public static func contentOverflow(
        contentHeight: Double, offsetY: Double, containerHeight: Double, bottomInset: Double
    ) -> Double? {
        let overflow = contentHeight - (offsetY + containerHeight - bottomInset)
        return overflow.isFinite ? overflow : nil
    }
}

// MARK: - Pinned chrome spacing

/// Padding for a list's pinned bottom chrome (the selected player's footer row above
/// a pager), so the list's last row rests exactly one row gap above whichever piece
/// of chrome shows first, and the footer sits one row gap above the pager
/// (issue #293).
public struct PinnedChromeSpacing: Equatable, Sendable {
    /// Space above the footer row.
    public let footerTop: Double
    /// Space below the footer row.
    public let footerBottom: Double
    /// Space above the pager.
    public let pagerTop: Double

    /// - Parameters:
    ///   - footerTop: Space above the footer row.
    ///   - footerBottom: Space below the footer row.
    ///   - pagerTop: Space above the pager.
    public init(footerTop: Double, footerBottom: Double, pagerTop: Double) {
        self.footerTop = footerTop
        self.footerBottom = footerBottom
        self.pagerTop = pagerTop
    }

    /// Resolve the chrome's padding for what it shows.
    ///
    /// - Parameters:
    ///   - rowGap: Space between two list rows (top plus bottom row inset).
    ///   - rowBottomInset: The list row's own bottom inset, already below the last row.
    ///   - edgePadding: Space below the footer when nothing follows it.
    ///   - hasFooter: Whether the selected player's footer row shows.
    ///   - hasPager: Whether the pager shows (not in the iPhone Duo rail).
    /// - Returns: Non-negative paddings.
    public static func resolve(
        rowGap: Double, rowBottomInset: Double, edgePadding: Double,
        hasFooter: Bool, hasPager: Bool
    ) -> PinnedChromeSpacing {
        let gap = max(0, rowGap)
        let lead = max(0, gap - max(0, rowBottomInset))
        return PinnedChromeSpacing(
            footerTop: lead,
            footerBottom: hasPager ? 0 : max(0, edgePadding),
            pagerTop: hasFooter ? gap : lead
        )
    }
}
