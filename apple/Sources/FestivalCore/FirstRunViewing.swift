import Foundation

// MARK: - Viewed slides

/// Which carousel pages a person actually saw, so dismissing a guide early only records
/// those pages as "don't show again" (operator batch 6, item 6.7). Unseen pages keep
/// showing next time, matching the web's rule that new or changed slides reappear.
public struct FirstRunViewing: Equatable, Sendable {
    /// Slide IDs shown on screen at least once during this presentation.
    public private(set) var viewedIDs: Set<String>

    /// Start a presentation; its first page is on screen as soon as it opens.
    ///
    /// - Parameter slides: Slides in presentation order.
    public init(slides: [FirstRunSlide]) {
        viewedIDs = slides.first.map { [$0.id] } ?? []
    }

    /// Record that the page at `index` is on screen.
    ///
    /// - Parameters:
    ///   - index: Page index; ignored when out of range.
    ///   - slides: Slides in presentation order.
    public mutating func view(_ index: Int, of slides: [FirstRunSlide]) {
        guard slides.indices.contains(index) else { return }
        viewedIDs.insert(slides[index].id)
    }

    /// Slides to mark seen when the presentation closes, in presentation order.
    ///
    /// - Parameter slides: Slides in presentation order.
    /// - Returns: Only the slides that were on screen.
    public func seenSlides(_ slides: [FirstRunSlide]) -> [FirstRunSlide] {
        slides.filter { viewedIDs.contains($0.id) }
    }
}

// MARK: - Controls

/// Which buttons a carousel page shows (operator batch 6 item 6.7, batch 7 item 1): a primary
/// Next/Done that comes first; Back only when there is a page to go back to; Skip only
/// while pages remain after this one. A one-page guide shows only Done — no disabled Back
/// and no Skip.
public struct FirstRunControls: Equatable, Sendable {
    /// Primary action title: "Next", or "Done" on the last (or only) page.
    public let primaryTitle: String
    /// Whether the primary action closes the carousel.
    public let primaryFinishes: Bool
    /// Whether a Back button is shown.
    public let showsBack: Bool
    /// Whether a Skip button is shown.
    public let showsSkip: Bool

    /// Controls for one page.
    ///
    /// - Parameters:
    ///   - index: Current page index.
    ///   - count: Number of pages.
    /// - Returns: The page's controls.
    public static func forPage(_ index: Int, of count: Int) -> FirstRunControls {
        let last = index >= count - 1
        return FirstRunControls(
            primaryTitle: last ? "Done" : "Next",
            primaryFinishes: last,
            showsBack: index > 0 && count > 1,
            showsSkip: !last
        )
    }
}
