import CoreGraphics

// MARK: - Large-title rest

/// Decides where a `List` under a collapsing large title must come to rest when it has
/// stopped part-way through the title's collapse (issue #560).
///
/// UIKit snaps a large title fully open or fully closed only when a *drag* ends. A
/// programmatic content offset (``ListScrollNudger`` landing corrections, a `.top`
/// `scrollTo` while the inset changes, Quick Links settles) can leave the List resting
/// between the two: the large title then sits half-way up behind the leading toolbar
/// button and the first section title under the Filter field. Measured on iOS 27
/// (iPhone 17 Pro): while the title is part-way, the List keeps the expanded title's
/// top inset (222 pt) and only its content offset moves; once fully collapsed the inset
/// drops to the collapsed bar's (170 pt).
///
/// So a List at rest with the expanded inset and an offset less than the band past its
/// top is part-way collapsed. ``restingOffset(offsetY:topInset:)`` returns the nearer
/// end, as UIKit's own drag-end snap does. The band is known only once both ends have
/// been seen at this width; until then (or with no collapsing title at all: macOS, a
/// List the bar does not track) nothing moves, so a legitimate rest is never snapped.
struct LargeTitleRest: Equatable {
    /// Points of layout rounding ignored when comparing offsets and insets.
    static let tolerance: CGFloat = 1

    /// The smallest top inset seen at ``containerWidth``: the collapsed bar's.
    private(set) var collapsedInset: CGFloat?
    /// The largest top inset seen at ``containerWidth`` while the List rested at its top:
    /// the expanded title's.
    private(set) var expandedInset: CGFloat?
    /// The width the insets were measured at (a rotation or resize resets them).
    private var containerWidth: CGFloat?

    /// Fold one scroll-geometry sample into the known insets.
    ///
    /// - Parameters:
    ///   - offsetY: The scroll view's vertical content offset.
    ///   - topInset: The scroll view's current top content inset.
    ///   - containerWidth: The scroll view's visible width; 0 before first layout.
    mutating func update(offsetY: CGFloat, topInset: CGFloat, containerWidth width: CGFloat) {
        guard width > 0, offsetY.isFinite, topInset.isFinite else { return }
        if width != containerWidth {
            containerWidth = width
            collapsedInset = topInset
            expandedInset = nil
        } else {
            collapsedInset = min(collapsedInset ?? topInset, topInset)
        }
        if abs(offsetY + topInset) < Self.tolerance {
            expandedInset = max(expandedInset ?? topInset, topInset)
        }
    }

    /// The content offset a List resting at `offsetY` must move to, or `nil` when it
    /// already rests at an end of the large title's collapse.
    ///
    /// - Parameters:
    ///   - offsetY: The resting vertical content offset.
    ///   - topInset: The resting top content inset.
    /// - Returns: `-topInset` (title open, List at its top) or `-topInset + band` (title
    ///   closed), whichever is nearer; `nil` when nothing needs to move or the band is
    ///   not known yet.
    func restingOffset(offsetY: CGFloat, topInset: CGFloat) -> CGFloat? {
        guard offsetY.isFinite, topInset.isFinite, let expandedInset, let collapsedInset,
              topInset >= expandedInset - Self.tolerance else { return nil }
        let band = expandedInset - collapsedInset
        let past = offsetY + topInset
        guard band > Self.tolerance, past > Self.tolerance, past < band - Self.tolerance
        else { return nil }
        return past < band / 2 ? -topInset : -topInset + band
    }
}
