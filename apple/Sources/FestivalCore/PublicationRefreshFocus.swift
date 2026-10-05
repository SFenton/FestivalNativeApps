import Foundation

// MARK: - Publication refresh focus (issue #304)

/// Where VoiceOver focus stays while a page refreshes in place for a new publication
/// (``PublicationRefreshTransition``).
///
/// The refresh hides the old page content from accessibility, because it must never be
/// read again, so the element VoiceOver had focused inside it disappears. Rather than let
/// VoiceOver fall to the spinner, the tab bar or whatever comes first on screen, the page
/// keeps a **page anchor**: an invisible heading named with the page's own title that
/// stays mounted, outside the rebuilt content, for the whole refresh.
///
/// 1. **Refresh starts:** the anchor appears and focus moves to it
///    (``anchorFocusRequest`` changes). Its value speaks the loading state, so VoiceOver
///    reads "*Title*, heading, Loading new scores" instead of losing its place.
/// 2. **Rebuilt content appears:** focus is restored to the anchor, unless the person
///    moved VoiceOver out of the page while the spinner was up.
/// 3. **The person moves on:** once focus leaves the anchor after the refresh, the anchor
///    retires so it never adds a stray element to the page.
///
/// HIG Focus and selection: "Avoid changing focus without people's interaction.
/// Exception: if the focused item disappears during discrete, directional input …, moving
/// focus to an item one step away keeps it findable." HIG VoiceOver: "Give each page or
/// screen a unique, succinct title describing its content and purpose."
///
/// A pure value type: the view reports VoiceOver focus changes and applies
/// ``showsAnchor`` and ``anchorFocusRequest``.
public struct PublicationRefreshFocus: Equatable, Sendable {
    /// The boundary's own accessibility elements that can hold VoiceOver focus.
    public enum Element: Hashable, Sendable {
        /// The page anchor (the page's title as a heading).
        case pageAnchor
        /// The refresh spinner.
        case spinner
    }

    /// Whether the page anchor is in the accessibility tree.
    public private(set) var showsAnchor = false
    /// Changes each time the view must move VoiceOver focus to the page anchor.
    public private(set) var anchorFocusRequest = 0
    /// Whether the person moved VoiceOver out of the page during the current refresh.
    private var leftPage = false

    /// No refresh yet: no anchor.
    public init() {}

    /// The page's content was hidden for a refresh: show the anchor and focus it.
    public mutating func refreshStarted() {
        showsAnchor = true
        leftPage = false
        anchorFocusRequest += 1
    }

    /// The rebuilt content appeared: restore focus to the anchor, or retire the anchor
    /// when the person already moved VoiceOver elsewhere.
    public mutating func contentRevealed() {
        guard showsAnchor else { return }
        if leftPage {
            showsAnchor = false
            leftPage = false
        } else {
            anchorFocusRequest += 1
        }
    }

    /// VoiceOver focus moved onto, between or off the boundary's own elements.
    ///
    /// - Parameters:
    ///   - old: The boundary element that held focus, or nil.
    ///   - new: The boundary element that holds focus now, or nil when focus is elsewhere.
    ///   - refreshing: Whether the spinner is up (old content hidden).
    public mutating func focusChanged(from old: Element?, to new: Element?, refreshing: Bool) {
        guard showsAnchor, old != new else { return }
        if new != nil {
            leftPage = false
        } else if refreshing {
            // The old content is hidden, so focus off the anchor and spinner left the page.
            leftPage = true
        } else if old == .pageAnchor {
            showsAnchor = false
        }
        // Spinner → nil after the reveal is the spinner leaving with the rebuild; the
        // restore request already owns focus.
    }
}
