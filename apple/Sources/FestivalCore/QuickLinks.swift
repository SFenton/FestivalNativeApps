import Foundation

// MARK: - Section model

/// Glyph shown beside a quick link.
///
/// Kept platform-neutral so FestivalCore stays free of UI frameworks; the UI
/// layer maps `.system` to an SF Symbol and `.instrument` to the bundled
/// instrument artwork (web `InstrumentIcon`).
public enum QuickLinkIcon: Hashable, Sendable {
    /// An SF Symbol name (the web uses an Ionicon in the same slot).
    case system(String)
    /// The bundled icon of one solo instrument chart.
    case instrument(Instrument)
}

/// One jump target on a page: web `PageQuickLinkItem`
/// (`FortniteFestivalWeb/src/hooks/ui/usePageQuickLinks.ts:18-24`).
public struct QuickLinkSection: Identifiable, Hashable, Sendable {
    /// Stable anchor identifier, reused from the web config (e.g. `instrument-Solo_Guitar`).
    public let id: String
    /// Visible label and VoiceOver name (web `label` / `landmarkLabel`).
    public let title: String
    /// Optional leading glyph.
    public let icon: QuickLinkIcon?
    /// Indentation level; 0 for top-level sections (web `depth`).
    public let depth: Int
    /// Spoken name when the short visible `title` relies on its indented parent for
    /// context (e.g. "Rank History" under "Lead" is spoken "Lead Rank History").
    public let spokenTitle: String?

    /// VoiceOver name for menu rows and the rotor: `spokenTitle`, else `title`.
    public var accessibilityTitle: String { spokenTitle ?? title }

    /// Create a quick link section.
    ///
    /// - Parameters:
    ///   - id: Stable anchor identifier, unique within the page.
    ///   - title: Visible label, also the accessibility label unless `spokenTitle` is set.
    ///   - icon: Optional leading glyph.
    ///   - depth: Indentation level; negative values clamp to 0.
    ///   - spokenTitle: Fuller VoiceOver name for a short, context-dependent title.
    public init(
        id: String, title: String, icon: QuickLinkIcon? = nil, depth: Int = 0,
        spokenTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.depth = max(0, depth)
        self.spokenTitle = spokenTitle
    }
}

/// A section's vertical extent in viewport coordinates: `0` is the top edge of the
/// scroll view's visible (safe-area-adjusted) region, positive values are below it.
public struct QuickLinkFrame: Hashable, Sendable {
    /// Top edge relative to the visible region's top.
    public let minY: Double
    /// Bottom edge relative to the visible region's top.
    public let maxY: Double

    /// Create a frame.
    ///
    /// - Parameters:
    ///   - minY: Top edge relative to the visible region's top.
    ///   - maxY: Bottom edge relative to the visible region's top.
    public init(minY: Double, maxY: Double) {
        self.minY = minY
        self.maxY = max(minY, maxY)
    }
}

// MARK: - Pure rules

/// Pure visibility, ordering and active-section rules shared by every platform's
/// quick-links presentation. See `.agents/controls/quick-links/spec.md`.
public enum QuickLinks {
    /// Fewer sections than this hide the entry point: a one-item jump list does nothing.
    public static let minimumSectionCount = 2
    /// A jump lands its target's top this many points below the viewport top, and a
    /// section becomes "natural" active once its top is within it (web default
    /// `offset`, 32 px, used for both). It clears the iOS 26 navigation bar's
    /// scroll-edge effect, which blurs and dims roughly the first 30 pt of content.
    public static let defaultActivationOffset: Double = 32
    /// After a jump, the target stays active while its top is within this band
    /// around the landing position (web `REACHABLE_TARGET_OWNERSHIP_PX`).
    public static let reachableBand: Double = 96
    /// Scroll drift tolerated before a settled jump releases ownership
    /// (web `scrollCompleteThreshold`).
    public static let completeThreshold: Double = 8

    /// Whether a page should show its quick-links entry point at all.
    ///
    /// - Parameter sectionCount: Number of sections the page currently offers.
    /// - Returns: `true` when there are at least `minimumSectionCount` sections.
    public static func isAvailable(sectionCount: Int) -> Bool {
        sectionCount >= minimumSectionCount
    }

    /// Discovery order for a section that contains other tagged sections.
    ///
    /// A container starts above everything inside it, so it comes first and its
    /// descendants keep their own tree order after it. This keeps nested entries
    /// (Profile's per-instrument Rank History and Percentiles) in the page's
    /// top-to-bottom order instead of letting the container hide or follow them.
    ///
    /// - Parameters:
    ///   - section: The containing section.
    ///   - descendants: Sections reported from inside it, in tree order.
    /// - Returns: `section` followed by `descendants`.
    public static func nesting(
        _ section: QuickLinkSection,
        descendants: [QuickLinkSection]
    ) -> [QuickLinkSection] {
        [section] + descendants
    }

    /// Resolve the ordered list shown in the jump menu.
    ///
    /// An explicit list (required for lazy containers whose off-screen sections
    /// have not been built yet) is authoritative. Otherwise sections discovered
    /// from the view tree are used in tree order. Duplicate ids keep their first
    /// occurrence.
    ///
    /// - Parameters:
    ///   - explicit: Page-declared sections, or `nil` to use discovery.
    ///   - discovered: Sections reported by `.quickLinkSection` views, in tree order.
    /// - Returns: De-duplicated sections in display order.
    public static func ordered(
        explicit: [QuickLinkSection]?,
        discovered: [QuickLinkSection]
    ) -> [QuickLinkSection] {
        var seen = Set<String>()
        return (explicit ?? discovered).filter { seen.insert($0.id).inserted }
    }

    /// Whether any part of a section is inside the viewport.
    ///
    /// - Parameters:
    ///   - frame: The section's viewport-relative frame, or `nil` if not laid out.
    ///   - viewportHeight: Height of the visible region.
    /// - Returns: `true` when the section intersects `[0, viewportHeight)`.
    public static func isVisible(_ frame: QuickLinkFrame?, viewportHeight: Double) -> Bool {
        guard let frame else { return false }
        return frame.maxY > 0 && frame.minY < viewportHeight
    }

    /// Whether a jump target sits close enough to its landing position to keep ownership.
    ///
    /// - Parameters:
    ///   - frame: The target's viewport-relative frame.
    ///   - activationOffset: The page's activation offset.
    /// - Returns: `true` when the target's top is within `reachableBand` of the landing band.
    public static func isReachable(_ frame: QuickLinkFrame, activationOffset: Double) -> Bool {
        frame.minY >= -reachableBand && frame.minY <= activationOffset + reachableBand
    }

    /// The activation line in a container's section-frame space (issue #286).
    ///
    /// A `ScrollView` measures its sections from the visible top, but a `List` measures
    /// them from its own top under the bars, so a `List`'s line moves down by its top
    /// content inset. Without that, Songs' line sat under the navigation bar and a
    /// section became active only well after the floating section bar named it.
    ///
    /// - Parameters:
    ///   - offset: The page's activation offset below the visible top.
    ///   - listTopInset: A `List`'s top content inset; 0 for a `ScrollView`. Negative or
    ///     non-finite values count as 0.
    /// - Returns: The line's distance from the frames' origin.
    public static func activationLine(offset: Double, listTopInset: Double) -> Double {
        guard listTopInset.isFinite, listTopInset > 0 else { return offset }
        return offset + listTopInset
    }

    /// Vertical scroll anchor that lands a section's top `inset` points below the
    /// visible region's top.
    ///
    /// `ScrollViewProxy.scrollTo(_:anchor:)` aligns the point at `anchor` within the
    /// section with the same unit point of the visible region, so the section's top
    /// lands at `anchor × (viewportHeight − sectionHeight)`. Solving for `inset` gives
    /// `inset / (viewportHeight − sectionHeight)`; sections taller than the viewport
    /// get a negative anchor. There is no offset parameter on iOS 17. A `List` centres
    /// the row for any such anchor, so Lists land with `.top` and then move by the
    /// remainder (`ListScrollNudger`, issue #286).
    ///
    /// - Parameters:
    ///   - inset: Wanted distance from the visible top to the section's top.
    ///   - viewportHeight: Height of the visible region.
    ///   - sectionHeight: Height of the target section.
    /// - Returns: The unit-point `y`, or `nil` (use `.top`) when there is nothing to
    ///   offset or the section is within a point of the viewport's height, where
    ///   the anchor cannot move it.
    public static func landingAnchorY(
        inset: Double, viewportHeight: Double, sectionHeight: Double
    ) -> Double? {
        let slack = viewportHeight - sectionHeight
        guard inset > 0, viewportHeight > 0, sectionHeight >= 0, abs(slack) >= 1 else { return nil }
        return inset / slack
    }

    /// The section a reader is "in" from scroll position alone
    /// (web `resolveActiveQuickLink`, `usePageQuickLinks.ts:163-191`).
    ///
    /// The last section, in display order, whose top has crossed the activation
    /// line wins; sections without a known frame (not yet laid out by a lazy
    /// container) are skipped. With no section past the line, the first wins.
    ///
    /// - Parameters:
    ///   - sections: Display-ordered sections.
    ///   - frames: Known viewport-relative frames by section id.
    ///   - activationOffset: Distance below the viewport top that counts as "reached".
    /// - Returns: The active id, or `nil` when there are no sections.
    public static func naturalActive(
        sections: [QuickLinkSection],
        frames: [String: QuickLinkFrame],
        activationOffset: Double = defaultActivationOffset
    ) -> String? {
        guard var active = sections.first?.id else { return nil }
        let threshold = activationOffset + 1
        for section in sections {
            guard let frame = frames[section.id] else { continue }
            if frame.minY <= threshold {
                active = section.id
            } else {
                break
            }
        }
        return active
    }
}

// MARK: - Jump tracker

/// Active-section state machine: natural scroll tracking plus jump ownership, so a
/// jump's target stays highlighted while the scroll animates and after it lands,
/// even when the target is too near the bottom to reach the top
/// (web `usePageQuickLinks.ts:281-493`, compact branch).
public struct QuickLinkTracker: Equatable, Sendable {
    /// Where a jump is in its lifecycle.
    public enum Phase: Equatable, Sendable {
        /// No jump in flight; the active section follows scroll position.
        case idle
        /// A jump was requested and its scroll is animating.
        case scrolling(target: String)
        /// The jump landed; the target owns "active" until the reader scrolls away.
        case owned(target: String, anchorMinY: Double, lockWhileVisible: Bool)
    }

    /// Current jump phase.
    public private(set) var phase: Phase = .idle
    /// The section to highlight in the menu, rotor value and toolbar label.
    public private(set) var activeID: String?

    /// Create an idle tracker.
    public init() {}

    /// Begin a jump. Compact presentations (menu, sheet) mark the target active
    /// immediately, matching the web mobile modal.
    ///
    /// - Parameter id: Target section id.
    public mutating func beginJump(to id: String) {
        phase = .scrolling(target: id)
        activeID = id
    }

    /// Record that a jump's scroll finished (animation completion, or immediately
    /// when Reduce Motion skips the animation). Replaces the web 120 ms settle timer.
    ///
    /// - Parameters:
    ///   - sections: Display-ordered sections.
    ///   - frames: Known viewport-relative frames.
    ///   - viewportHeight: Height of the visible region.
    ///   - activationOffset: Page activation offset.
    public mutating func settle(
        sections: [QuickLinkSection],
        frames: [String: QuickLinkFrame],
        viewportHeight: Double,
        activationOffset: Double = QuickLinks.defaultActivationOffset
    ) {
        guard case let .scrolling(target) = phase else { return }
        guard sections.contains(where: { $0.id == target }), let frame = frames[target],
              QuickLinks.isVisible(frame, viewportHeight: viewportHeight) else {
            phase = .idle
            activeID = QuickLinks.naturalActive(
                sections: sections, frames: frames, activationOffset: activationOffset
            )
            return
        }
        // A target that could not scroll up to the activation line sits near the end
        // of the content: keep it active for as long as it stays on screen.
        let lock = frame.minY > activationOffset + QuickLinks.completeThreshold
        phase = .owned(target: target, anchorMinY: frame.minY, lockWhileVisible: lock)
        activeID = target
    }

    /// Re-resolve the active section after the sections or their geometry changed.
    ///
    /// - Parameters:
    ///   - sections: Display-ordered sections.
    ///   - frames: Known viewport-relative frames.
    ///   - viewportHeight: Height of the visible region.
    ///   - activationOffset: Page activation offset.
    public mutating func update(
        sections: [QuickLinkSection],
        frames: [String: QuickLinkFrame],
        viewportHeight: Double,
        activationOffset: Double = QuickLinks.defaultActivationOffset
    ) {
        let natural = QuickLinks.naturalActive(
            sections: sections, frames: frames, activationOffset: activationOffset
        )
        switch phase {
        case .idle:
            activeID = natural
        case let .scrolling(target):
            // Hold the target while the animation runs, even before a lazy container
            // has built it; release only if the page removed the section.
            if sections.contains(where: { $0.id == target }) {
                activeID = target
            } else {
                release(to: natural)
            }
        case let .owned(target, anchorMinY, lock):
            guard sections.contains(where: { $0.id == target }), let frame = frames[target] else {
                release(to: natural)
                return
            }
            let visible = QuickLinks.isVisible(frame, viewportHeight: viewportHeight)
            if lock {
                visible ? (activeID = target) : release(to: natural)
            } else if visible && abs(frame.minY - anchorMinY) <= QuickLinks.completeThreshold {
                activeID = target
            } else if QuickLinks.isReachable(frame, activationOffset: activationOffset) {
                activeID = target
            } else {
                release(to: natural)
            }
        }
    }

    /// Drop jump ownership and fall back to the natural section.
    ///
    /// - Parameter natural: The naturally active section id.
    private mutating func release(to natural: String?) {
        phase = .idle
        activeID = natural
    }
}
