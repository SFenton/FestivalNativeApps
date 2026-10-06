import CoreGraphics
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
/// 1. **Refresh starts:** only when VoiceOver focus is **inside the page** (``Location``)
///    does the anchor appear and focus move to it (``anchorFocusRequest`` changes). Its
///    value speaks the loading state, so VoiceOver reads "*Title*, heading, Loading new
///    scores" instead of losing its place. When focus is elsewhere (tab bar, navigation
///    bar, a sheet, another column) focus is left alone and the update is announced
///    instead (``announcementRequest``; ``PublicationRefreshAnnouncements`` posts it once).
/// 2. **Rebuilt content appears:** focus is restored to the anchor, unless the person
///    moved VoiceOver out of the page while the spinner was up.
/// 3. **The person moves on:** once focus leaves the anchor after the refresh, the anchor
///    retires so it never adds a stray element to the page.
///
/// HIG Focus and selection: "Don't change focus without user interaction … Exception: if a
/// focused item disappears while navigating with discrete directional input, move focus to
/// the nearest remaining item." HIG VoiceOver: "Give each page or screen a unique, succinct
/// title describing its content and purpose" and "Announce visible content and layout
/// changes."
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

    /// Where VoiceOver focus is when a refresh starts, relative to the refreshing page.
    ///
    /// The view fills this from the platform's VoiceOver focus (iOS/iPadOS
    /// `UIAccessibility.focusedElement(using: .notificationVoiceOver)`); a platform that
    /// cannot report the VoiceOver cursor (macOS) leaves ``focusedFrame`` nil, so focus is
    /// never moved there.
    public struct Location: Equatable, Sendable {
        /// Whether the page is on screen (not a covered stack page or another tab).
        public var pageOnScreen: Bool
        /// Whether a sheet, popover or alert is presented over the page.
        public var pageCovered: Bool
        /// The page's frame, in the same coordinates as ``focusedFrame``.
        public var pageFrame: CGRect
        /// The VoiceOver-focused element's frame, or nil when there is none or the
        /// platform cannot report it.
        public var focusedFrame: CGRect?
        /// Whether the focused element belongs to the page's own view hierarchy, or nil
        /// when that cannot be established.
        public var focusedInPageHierarchy: Bool?

        /// - Parameters:
        ///   - pageOnScreen: Whether the page is on screen.
        ///   - pageCovered: Whether something is presented over the page.
        ///   - pageFrame: The page's frame.
        ///   - focusedFrame: The focused element's frame, if known.
        ///   - focusedInPageHierarchy: Whether the element is in the page's hierarchy, if known.
        public init(
            pageOnScreen: Bool, pageCovered: Bool, pageFrame: CGRect,
            focusedFrame: CGRect?, focusedInPageHierarchy: Bool?
        ) {
            self.pageOnScreen = pageOnScreen
            self.pageCovered = pageCovered
            self.pageFrame = pageFrame
            self.focusedFrame = focusedFrame
            self.focusedInPageHierarchy = focusedInPageHierarchy
        }

        /// Whether VoiceOver focus is inside the page: the page is on screen and
        /// uncovered, the focused element is not known to be outside its hierarchy, and
        /// the element's centre lies in the page's frame (so the tab bar, navigation bar
        /// and toolbar, which sit outside it, never count).
        public var isInsidePage: Bool {
            guard pageOnScreen, !pageCovered, focusedInPageHierarchy != false,
                  let focusedFrame, !focusedFrame.isNull, !pageFrame.isEmpty else { return false }
            return pageFrame.contains(CGPoint(x: focusedFrame.midX, y: focusedFrame.midY))
        }
    }

    /// Whether the page anchor is in the accessibility tree.
    public private(set) var showsAnchor = false
    /// Changes each time the view must move VoiceOver focus to the page anchor.
    public private(set) var anchorFocusRequest = 0
    /// Changes each time the view must announce the refresh instead of moving focus.
    public private(set) var announcementRequest = 0
    /// Whether the person moved VoiceOver out of the page during the current refresh.
    private var leftPage = false

    /// No refresh yet: no anchor.
    public init() {}

    /// The page's content was hidden for a refresh. With VoiceOver focus inside the page,
    /// show the anchor and focus it; otherwise leave focus where it is and announce.
    ///
    /// - Parameter focusInPage: Whether VoiceOver focus was inside the page
    ///   (``Location/isInsidePage``) just before its content was hidden.
    public mutating func refreshStarted(focusInPage: Bool) {
        leftPage = false
        if focusInPage {
            showsAnchor = true
            anchorFocusRequest += 1
        } else {
            showsAnchor = false
            announcementRequest += 1
        }
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

// MARK: - Publication refresh announcements

/// Posts at most one "Loading new scores" announcement per publication, and none when a
/// page moved VoiceOver to its anchor for it (the anchor already reads the loading state).
///
/// Several pages refresh for one publication (a split stack shows two; covered stack
/// pages and other tabs refresh off screen). Each on-screen page whose focus is elsewhere
/// asks to announce; the view waits briefly so a page that claims focus for the same
/// publication in the same update cancels it.
public struct PublicationRefreshAnnouncements: Equatable, Sendable {
    /// The newest publication a page moved focus for.
    private var claimedRevision = Int.min
    /// The newest publication announced or waiting to be.
    private var requestedRevision = Int.min

    /// Nothing announced yet.
    public init() {}

    /// A page moved VoiceOver to its anchor for a publication.
    ///
    /// - Parameter revision: The publication revision.
    public mutating func focusClaimed(for revision: Int) {
        claimedRevision = max(claimedRevision, revision)
    }

    /// A page asks to announce a publication.
    ///
    /// - Parameter revision: The publication revision.
    /// - Returns: True when the caller should schedule the announcement (the first ask
    ///   for this publication, with no focus claim yet).
    public mutating func request(for revision: Int) -> Bool {
        guard revision > requestedRevision, revision > claimedRevision else { return false }
        requestedRevision = revision
        return true
    }

    /// Whether a scheduled announcement should still be posted.
    ///
    /// - Parameter revision: The publication the announcement was scheduled for.
    /// - Returns: False once a page claimed focus for it or a newer one was requested.
    public func shouldPost(for revision: Int) -> Bool {
        revision == requestedRevision && revision > claimedRevision
    }
}
