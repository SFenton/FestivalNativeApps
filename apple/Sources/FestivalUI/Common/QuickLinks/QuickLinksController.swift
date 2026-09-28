import SwiftUI
import Observation
import FestivalCore

// MARK: - Controller

/// Page-owned state for one page's quick links ("Jump to Section").
///
/// A page creates one with `@State`, hands it to both `.quickLinks(_:title:sections:)`
/// on its scroll view and `QuickLinksToolbarItem(_:)` in its toolbar, and tags each
/// anchor view with `.quickLinkSection(…)`. Frames are observation-ignored so
/// scrolling only invalidates views when the *active section* changes.
@MainActor
@Observable
public final class QuickLinksController {
    // MARK: Published state

    /// Menu, sheet and rotor title (web `PageQuickLinksConfig.title`).
    public internal(set) var title: String = "Quick Links"
    /// Display-ordered sections currently offered.
    public internal(set) var sections: [QuickLinkSection] = []
    /// Section highlighted in the menu and announced as the button's value.
    public private(set) var activeID: String?
    /// Increments on every jump; drives the scroll request and selection haptic.
    public private(set) var jumpSerial = 0
    /// Target of the latest jump request.
    public private(set) var jumpTarget: String?

    // MARK: Geometry (not observed)

    @ObservationIgnored private var tracker = QuickLinkTracker()
    @ObservationIgnored private var frames: [String: QuickLinkFrame] = [:]
    @ObservationIgnored private var viewportHeight: Double = 0
    @ObservationIgnored var activationOffset: Double = QuickLinks.defaultActivationOffset
    @ObservationIgnored private var explicitSections: [QuickLinkSection]?
    @ObservationIgnored private var discoveredSections: [QuickLinkSection] = []

    /// Create an empty controller; the `.quickLinks` modifier fills it in.
    public init() {}

    // MARK: Derived

    /// Whether the page should show its "Jump to Section" entry point.
    public var isAvailable: Bool { QuickLinks.isAvailable(sectionCount: sections.count) }

    /// The active section, if any.
    public var activeSection: QuickLinkSection? {
        sections.first { $0.id == activeID }
    }

    // MARK: Jumping

    /// Request an animated jump to a section. The `.quickLinks` modifier performs the
    /// scroll (instantly under Reduce Motion) and calls back when it lands.
    ///
    /// - Parameter id: Target section id; ignored when the page does not offer it.
    public func jump(to id: String) {
        guard sections.contains(where: { $0.id == id }) else { return }
        tracker.beginJump(to: id)
        jumpTarget = id
        jumpSerial += 1
        publishActive()
    }

    /// Mark the in-flight jump as landed.
    func jumpDidSettle() {
        tracker.settle(
            sections: sections, frames: frames,
            viewportHeight: viewportHeight, activationOffset: activationOffset
        )
        publishActive()
    }

    // MARK: Inputs from the view layer

    /// Update the page-declared title and sections.
    ///
    /// - Parameters:
    ///   - title: Menu title.
    ///   - explicit: Page-declared sections, or `nil` to use discovered ones.
    func configure(title: String, explicit: [QuickLinkSection]?) {
        if self.title != title { self.title = title }
        explicitSections = explicit
        resolveSections()
    }

    /// Replace the sections reported by `.quickLinkSection` views in tree order.
    ///
    /// - Parameter discovered: Discovered sections.
    func discover(_ discovered: [QuickLinkSection]) {
        discoveredSections = discovered
        resolveSections()
    }

    /// Record one section's viewport-relative frame, or `nil` when it leaves the tree.
    ///
    /// - Parameters:
    ///   - id: Section id.
    ///   - frame: New frame, or `nil` to forget it.
    func report(_ id: String, frame: QuickLinkFrame?) {
        guard frames[id] != frame else { return }
        frames[id] = frame
        refresh()
    }

    /// Record the height of the scroll view's visible region.
    ///
    /// - Parameter height: Visible height in points.
    func reportViewport(height: Double) {
        guard viewportHeight != height else { return }
        viewportHeight = height
        refresh()
    }

    /// The most recently reported frame for a section, if any.
    ///
    /// Used by `QuickLinksContainerModifier.correctAndSettle` to poll a jump
    /// target's geometry until it stops changing before calling
    /// `jumpDidSettle()`, instead of guessing a fixed delay.
    ///
    /// - Parameter id: Section id.
    /// - Returns: The last frame `report(_:frame:)` recorded, or `nil`.
    func currentFrame(for id: String) -> QuickLinkFrame? { frames[id] }

    // MARK: Private

    private func resolveSections() {
        let resolved = QuickLinks.ordered(explicit: explicitSections, discovered: discoveredSections)
        if resolved != sections { sections = resolved }
        refresh()
    }

    private func refresh() {
        tracker.update(
            sections: sections, frames: frames,
            viewportHeight: viewportHeight, activationOffset: activationOffset
        )
        publishActive()
    }

    private func publishActive() {
        if activeID != tracker.activeID { activeID = tracker.activeID }
    }
}
