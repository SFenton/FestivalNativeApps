import Foundation

// MARK: - Gate context

/// Runtime facts a first-run slide's gate predicate may depend on, mirroring the web's
/// `FirstRunGateContext` (`FortniteFestivalWeb/src/firstRun/types.ts`).
public struct FirstRunGateContext: Equatable, Sendable {
    /// Whether a player profile is currently selected.
    public var hasPlayer: Bool
    /// Whether Item Shop highlighting is active (Shop not hidden and not disabled).
    public var shopHighlightEnabled: Bool
    /// Whether the experimental leaderboard ranking metrics setting is enabled.
    public var experimentalRanksEnabled: Bool
    /// When false, no slide should show yet because dependent context is still resolving.
    public var ready: Bool
    /// When true, bypass seen-state and show every gate-passing slide (debug "force" mode).
    public var alwaysShow: Bool

    /// Create a gate context.
    ///
    /// - Parameters:
    ///   - hasPlayer: Whether a player profile is selected.
    ///   - shopHighlightEnabled: Whether Shop highlighting is currently active.
    ///   - experimentalRanksEnabled: Whether experimental ranking metrics are enabled.
    ///   - ready: Whether dependent context has stabilized; false delays showing anything.
    ///   - alwaysShow: Whether to bypass seen-state (debug force mode).
    public init(
        hasPlayer: Bool = false, shopHighlightEnabled: Bool = false,
        experimentalRanksEnabled: Bool = false, ready: Bool = true, alwaysShow: Bool = false
    ) {
        self.hasPlayer = hasPlayer
        self.shopHighlightEnabled = shopHighlightEnabled
        self.experimentalRanksEnabled = experimentalRanksEnabled
        self.ready = ready
        self.alwaysShow = alwaysShow
    }
}

// MARK: - Gate predicate

/// A named slide gate, evaluated against a ``FirstRunGateContext``.
///
/// Modeled as an enum (rather than a closure) so slide definitions stay `Equatable`/`Sendable`
/// and unit-testable without capturing state.
public enum FirstRunGate: Equatable, Sendable {
    /// Always visible (subject only to seen-state).
    case always
    /// Visible only once a player profile is selected.
    case hasPlayer
    /// Visible only while Item Shop highlighting is active.
    case shopHighlightEnabled
    /// Visible only while the experimental ranking metrics setting is enabled.
    case experimentalRanksEnabled

    /// Evaluate this gate.
    ///
    /// - Parameter context: Current runtime facts.
    /// - Returns: Whether a slide using this gate may be shown.
    public func passes(_ context: FirstRunGateContext) -> Bool {
        switch self {
        case .always: true
        case .hasPlayer: context.hasPlayer
        case .shopHighlightEnabled: context.shopHighlightEnabled
        case .experimentalRanksEnabled: context.experimentalRanksEnabled
        }
    }
}

// MARK: - Slide definition

/// One first-run slide, mirroring the web's `FirstRunSlideDef`. Pure data — the UI layer maps
/// `id` to a native demo view; nothing here renders.
public struct FirstRunSlide: Equatable, Sendable, Identifiable {
    /// Stable identifier, matching the web slide id (e.g. `"songs-song-list"`).
    public let id: String
    /// Replay-contract version. Only bumped when previously-dismissed users should see it again.
    public let version: Int
    /// Title Case slide title, already localized (English only for now).
    public let title: String
    /// Sentence-case slide description, already localized.
    public let description: String
    /// Overrides the string hashed to detect content changes; lets mobile/desktop copy
    /// variants share one seen-state record. Defaults to `title + description`.
    public let contentKey: String?
    /// Predicate controlling whether this slide is eligible to show at all.
    public let gate: FirstRunGate

    /// Create a slide definition.
    ///
    /// - Parameters:
    ///   - id: Stable identifier, unique within its page.
    ///   - version: Replay-contract version.
    ///   - title: Localized Title Case title.
    ///   - description: Localized sentence-case description.
    ///   - contentKey: Optional override for the hashed content key.
    ///   - gate: Visibility predicate.
    public init(
        id: String, version: Int, title: String, description: String,
        contentKey: String? = nil, gate: FirstRunGate = .always
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.description = description
        self.contentKey = contentKey
        self.gate = gate
    }

    /// The text hashed to detect a copy change, matching the web's
    /// `slide.contentKey ?? (slide.title + slide.description)`.
    public var hashedContent: String { contentKey ?? (title + description) }
}

// MARK: - Content hashing

/// A simple djb2-style string hash, matching the web's `contentHash` bit-for-bit so a slide's
/// unseen computation only ever depends on its own id/version/hash, never the platform.
public enum FirstRunHashing {
    private static let seed: UInt32 = 5381
    private static let shift: UInt32 = 5

    /// Hash text into a stable lowercase hex string.
    ///
    /// - Parameter text: Slide title/description (or `contentKey` override).
    /// - Returns: Lowercase hex digest.
    public static func contentHash(_ text: String) -> String {
        var hash = seed
        for scalar in text.unicodeScalars {
            let value = UInt32(truncatingIfNeeded: scalar.value)
            hash = (hash << shift) &+ hash &+ value
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Seen record

/// Persisted evidence that one slide has been shown, matching the web's `FirstRunSeenRecord`.
public struct FirstRunSeenRecord: Codable, Equatable, Sendable {
    public let version: Int
    public let hash: String
    public let seenAt: Date

    /// Create a seen record.
    ///
    /// - Parameters:
    ///   - version: Slide version at the time it was shown.
    ///   - hash: Content hash at the time it was shown.
    ///   - seenAt: When it was marked seen.
    public init(version: Int, hash: String, seenAt: Date) {
        self.version = version
        self.hash = hash
        self.seenAt = seenAt
    }
}

/// Slide id → seen record, matching the web's `FirstRunStorage`.
public typealias FirstRunSeenStorage = [String: FirstRunSeenRecord]

// MARK: - Unseen computation

/// Pure functions computing which slides should show, ported from `isSlideUnseen` and
/// `FirstRunContext`'s `getUnseenSlides`/`getAllSlides` in the web app.
public enum FirstRunSlideEvaluator {
    /// A slide is unseen if it has no record, its version was bumped since the record was
    /// written, or its hashed content changed — matching `isSlideUnseen` exactly.
    ///
    /// - Parameters:
    ///   - slide: Slide to check.
    ///   - seen: Persisted seen-state.
    /// - Returns: Whether the slide should be treated as not-yet-seen.
    public static func isUnseen(_ slide: FirstRunSlide, in seen: FirstRunSeenStorage) -> Bool {
        guard let record = seen[slide.id] else { return true }
        if slide.version > record.version { return true }
        return FirstRunHashing.contentHash(slide.hashedContent) != record.hash
    }

    /// Slides eligible to show right now: gate-passing and unseen (or all gate-passing slides
    /// when `context.alwaysShow` is set, matching `useFirstRun`'s debug/force branch).
    ///
    /// - Parameters:
    ///   - slides: A page's full slide catalog, in display order.
    ///   - context: Current runtime facts.
    ///   - seen: Persisted seen-state.
    /// - Returns: The slides to display, preserving catalog order.
    public static func unseenSlides(
        _ slides: [FirstRunSlide], context: FirstRunGateContext, seen: FirstRunSeenStorage
    ) -> [FirstRunSlide] {
        guard context.ready else { return [] }
        let gatePassing = slides.filter { $0.gate.passes(context) }
        if context.alwaysShow { return gatePassing }
        return gatePassing.filter { isUnseen($0, in: seen) }
    }

    /// Every gate-passing slide regardless of seen-state — the debug "force" behavior.
    ///
    /// - Parameters:
    ///   - slides: A page's full slide catalog.
    ///   - context: Current runtime facts (seen-state and `alwaysShow` are irrelevant here).
    /// - Returns: Slides whose gate currently passes, in catalog order.
    public static func gatePassingSlides(
        _ slides: [FirstRunSlide], context: FirstRunGateContext
    ) -> [FirstRunSlide] {
        slides.filter { $0.gate.passes(context) }
    }

    /// Every slide for a page, ignoring gates and seen-state entirely — matches the web's
    /// `getAllSlides`, used for Settings "view again" replay so old content isn't hidden by a
    /// stale gate (e.g. no player selected) or already-seen state.
    ///
    /// - Parameter slides: A page's full slide catalog.
    /// - Returns: The same slides, unfiltered, in catalog order.
    public static func allSlides(_ slides: [FirstRunSlide]) -> [FirstRunSlide] { slides }

    /// The record to persist once a slide has been shown.
    ///
    /// - Parameters:
    ///   - slide: Slide just displayed.
    ///   - now: Timestamp to record.
    /// - Returns: A record capturing the slide's current version and content hash.
    public static func seenRecord(for slide: FirstRunSlide, at now: Date) -> FirstRunSeenRecord {
        FirstRunSeenRecord(
            version: slide.version, hash: FirstRunHashing.contentHash(slide.hashedContent),
            seenAt: now
        )
    }
}
