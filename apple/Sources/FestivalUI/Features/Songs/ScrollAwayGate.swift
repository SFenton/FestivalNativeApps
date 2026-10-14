import CoreGraphics

// MARK: - Scrolled-away decision

/// Decides whether a scroll view has moved away from its top without feeding back on
/// the chrome that decision changes.
///
/// Songs moves Filter/Sort/Quick Links into the navigation bar and removes the inline
/// title once scrolled. Restoring the title briefly reports the fully expanded top
/// inset (232pt instead of the collapsed 116pt on an iPhone 17 Pro) while the content
/// offset stays put, so a decision taken from `contentOffset.y + contentInsets.top`
/// flipped back on every inset change near the top: an endless toolbar update loop
/// that froze, then crashed, the app (issue #5).
///
/// The gate measures distance from the **smallest** top inset seen at the current
/// width (the collapsed navigation bar), which the title toggle cannot change; it
/// re-decides only when the content offset itself moves (user scrolling, momentum or
/// a programmatic jump), never on an inset-only change; and it uses hysteresis so a
/// slow drag across the threshold cannot flicker the chrome.
///
/// The decision now shows Songs' pinned section title (``SongsSectionBar``), so it flips
/// where the first section title reaches its pin line: the collapsed top itself. While
/// the large title collapses the List's first row rides on the navigation bar's bottom
/// edge (the pin line) and the distance stays 0; once the title has collapsed the row
/// moves above the line point for point. Entering 24 pt past the collapsed top let the
/// in-list title slide 24 pt under the bar before its pinned copy popped back in at the
/// line, and leaving at 8 pt showed it 8 pt above the line (issue #631). The collapsed
/// top is still where the navigation bar stops moving, so the row masks this enables
/// never follow the large title's transition (issue #383).
struct ScrollAwayGate: Equatable {
    /// Distance past the collapsed top that counts as scrolled away: the title-pass
    /// tolerance (``SongsScrollChrome/headerTolerance``), so the pinned copy takes over
    /// within a point of where the in-list title crosses its pin line (issue #631).
    static let enterDistance: CGFloat = SongsScrollChrome.headerTolerance
    /// Distance below which a scrolled list counts as back at the top: half a point, so
    /// the in-list title takes back over within a point of the pin line and the List's
    /// own top (distance 0) always counts as the top (issue #631).
    static let exitDistance: CGFloat = 0.5
    /// Offset movement smaller than this is layout jitter, not scrolling.
    static let offsetTolerance: CGFloat = 0.5

    /// Whether the scroll view currently counts as scrolled away from its top.
    private(set) var isScrolled = false
    /// The content offset of the last decision.
    private var decidedOffset: CGFloat?
    /// The smallest top inset seen at ``containerWidth``.
    private var collapsedTopInset: CGFloat?
    /// The width the collapsed inset was measured at (a rotation or resize resets it).
    private var containerWidth: CGFloat?

    /// Fold one scroll-geometry sample into the decision.
    ///
    /// - Parameters:
    ///   - offsetY: The scroll view's vertical content offset.
    ///   - topInset: The scroll view's current top content inset.
    ///   - containerWidth: The scroll view's visible width; 0 before first layout.
    /// - Returns: True when ``isScrolled`` changed.
    @discardableResult
    mutating func update(
        offsetY: CGFloat, topInset: CGFloat, containerWidth width: CGFloat
    ) -> Bool {
        guard width > 0 else { return false }
        if width != containerWidth {
            containerWidth = width
            collapsedTopInset = topInset
            decidedOffset = nil
        } else {
            collapsedTopInset = min(collapsedTopInset ?? topInset, topInset)
        }
        if let decidedOffset, abs(offsetY - decidedOffset) < Self.offsetTolerance {
            return false
        }
        decidedOffset = offsetY
        let distance = offsetY + (collapsedTopInset ?? topInset)
        let scrolled = isScrolled
            ? distance >= Self.exitDistance
            : distance > Self.enterDistance
        guard scrolled != isScrolled else { return false }
        isScrolled = scrolled
        return true
    }
}
