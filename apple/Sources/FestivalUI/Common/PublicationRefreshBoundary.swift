import SwiftUI
import FestivalCore

// MARK: - PublicationRefreshBoundary

/// Refreshes one page in place when the service publishes a new generation (issue #304),
/// like the web's `PublicationBoundary`, which keeps the route and remounts the pages.
///
/// The sequence is ``PublicationRefreshTransition`` (FestivalCore, load-transition R3):
/// the content fades out (300 ms), the spinner fades in (150 ms) and holds ≥400 ms and
/// until `prepare` has finished for the newest generation, the spinner fades out
/// (500 ms), then the page is rebuilt and fades in; the rebuilt page loads its own data
/// with its own load fade. The hidden content stays mounted (no hit testing, hidden from
/// VoiceOver from the start of its fade) so the page's title, toolbar and navigation stay
/// put; it is never shown again.
///
/// VoiceOver stays where the person left it (``PublicationRefreshFocus``, FestivalCore;
/// load-transition R8). When ``PublicationFocusProbe`` establishes that VoiceOver focus is
/// inside this page, a refresh adds a **page anchor**, an invisible heading named with the
/// page's ``festivalNavigationTitle(_:)`` that lives outside the rebuilt content. Focus
/// moves to it as the old content is hidden (it reads "*Title*, heading, Loading new
/// scores"), stays there through the spinner and is restored to it after the rebuild;
/// the anchor retires once the person moves on. When focus is anywhere else (tab bar,
/// navigation bar, a sheet, another column, or always on macOS) focus is not moved and
/// an on-screen page announces "Loading new scores" once per publication
/// (``PublicationRefreshAnnouncements``). HIG VoiceOver: "Give each page or screen a
/// unique, succinct title describing its content and purpose"; "Announce visible content
/// and layout changes."
///
/// HIG Progress indicators (iOS, iPadOS): "Perform automatic content updates regularly;
/// don't make people initiate every update." HIG Accessibility: with Reduce Motion "reduce
/// automatic and repetitive animation", so system or in-app Reduce Motion swaps instantly
/// while the spinner still holds 400 ms; `festivalFadeInEnabled == false` also skips the hold.
struct PublicationRefreshBoundary<Content: View>: View {
    let session: FestivalSession
    /// Readies page state for a generation before the page is rebuilt (for example,
    /// re-reading a `Song` from the new catalogue); nil when nothing needs preparing.
    let prepare: ((Int) async -> Void)?
    /// Called in the update that reveals the rebuilt content, before it is built (for
    /// example, to reopen a row stagger window), like ``FestivalReloadGate``'s `onReveal`.
    let onReveal: (() -> Void)?
    /// Whether the faded-out page stays mounted under the spinner. A page whose rows are a
    /// UIKit-backed `List` passes false: `accessibilityHidden` does not reach those rows, so
    /// VoiceOver could still read the old publication's rows under the spinner.
    let retainsHiddenContent: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.festivalFadeInEnabled) private var fadeEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var transition: PublicationRefreshTransition
    @State private var focus = PublicationRefreshFocus()
    @State private var probe = PublicationFocusProbe()
    /// Whether the page is on screen (not under a pushed page or in another tab).
    @State private var onScreen = false
    @AccessibilityFocusState private var focusedElement: PublicationRefreshFocus.Element?
    /// The page's last published title (kept across the rebuild and its own load).
    @State private var pageTitle: String?
    /// The publication revision this boundary last announced (UI-test marker only).
    @State private var announcedRevision: Int?

    /// - Parameters:
    ///   - session: Shared app session whose publication revision is watched.
    ///   - title: The page title when the page sets it outside the boundary (a root whose
    ///     search field and toolbar stay outside, like Songs); a title published from
    ///     inside with ``festivalNavigationTitle(_:)`` wins.
    ///   - prepare: Called with the new revision while the spinner is up.
    ///   - retainsHiddenContent: Whether the faded-out page stays mounted under the
    ///     spinner; pass false for a page with outside chrome whose rows are a `List`.
    ///   - onReveal: Called in the update that reveals the rebuilt content.
    ///   - content: The page.
    init(
        session: FestivalSession,
        title: String? = nil,
        retainsHiddenContent: Bool = true,
        prepare: ((Int) async -> Void)? = nil,
        onReveal: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.session = session
        self.prepare = prepare
        self.onReveal = onReveal
        self.retainsHiddenContent = retainsHiddenContent
        self.content = content
        _transition = State(initialValue: PublicationRefreshTransition(revision: session.publicationRevision))
        _pageTitle = State(initialValue: title)
    }

    /// Identifies the running wait so a phase change restarts it.
    private struct WaitID: Equatable {
        let phase: PublicationRefreshTransition.Phase
        let generation: Int
        let wait: PublicationRefreshTransition.Wait?
    }

    var body: some View {
        ZStack {
            if mountsContent {
                content()
                    .id(transition.generation)
                    .opacity(transition.showsContent ? 1 : 0)
                    .allowsHitTesting(transition.showsContent)
                    .accessibilityHidden(!transition.showsContent)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            if transition.showsSpinner {
                FestivalLoadingView(accessibilityLabel: Self.loadingLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fst.publication.refreshing")
                    .accessibilityFocused($focusedElement, equals: .spinner)
                    .transition(.opacity)
            }
        }
        .background { PublicationFocusProbeView(probe: probe) }
        .overlay(alignment: .top) {
            if showsPageAnchor { pageAnchor }
        }
        .overlay(alignment: .bottom) {
            if Self.forcedFocusInPage == false, let announcedRevision {
                announcementMarker(announcedRevision)
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onPreferenceChange(FestivalPageTitleKey.self) { title in
            if let title { pageTitle = title }
        }
        .transformPreference(FestivalPageTitleKey.self) { $0 = nil }
        .onChange(of: session.publicationRevision) { _, revision in
            update { $0.publicationChanged(to: revision) }
        }
        .onChange(of: anchorsFocus) { _, anchors in
            if !anchors { focus = PublicationRefreshFocus() }
        }
        .onChange(of: focusedElement) { old, new in
            focus.focusChanged(from: old, to: new, refreshing: transition.isRefreshing)
        }
        .task(id: focus.anchorFocusRequest) {
            guard focus.anchorFocusRequest > 0, voiceOverEnabled, focus.showsAnchor else { return }
            // Let the anchor (and, after a rebuild, the new content) enter the
            // accessibility tree before VoiceOver is pointed at it.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            focusedElement = .pageAnchor
        }
        .task(id: focus.announcementRequest) {
            guard focus.announcementRequest > 0, anchorsFocus, onScreen else { return }
            let revision = transition.targetRevision
            guard PublicationRefreshAnnouncer.gate.request(for: revision) else { return }
            // A page that moves focus to its anchor for the same publication in this
            // update cancels the announcement (the anchor reads the loading state).
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, PublicationRefreshAnnouncer.gate.shouldPost(for: revision) else { return }
            AccessibilityNotification.Announcement(Self.loadingLabel).post()
            announcedRevision = revision
        }
        .task(id: WaitID(phase: transition.phase, generation: transition.generation, wait: transition.pendingWait)) {
            guard let wait = transition.pendingWait else { return }
            let duration = timing.duration(of: wait)
            if duration > .zero {
                try? await Task.sleep(for: duration)
            }
            guard !Task.isCancelled else { return }
            update { $0.timerFired(wait) }
        }
        .task(id: transition.preparationRevision) {
            guard let revision = transition.preparationRevision else { return }
            await prepare?(revision)
            guard !Task.isCancelled else { return }
            update { $0.prepared(revision: revision) }
        }
    }

    // MARK: VoiceOver page anchor

    /// The spinner's spoken label, also the anchor's value while the spinner is up.
    private static var loadingLabel: String { PublicationPageAnchor.loadingLabel }

    /// See ``PublicationPageAnchor/forcedFocusInPage``.
    private static var forcedFocusInPage: Bool? { PublicationPageAnchor.forcedFocusInPage }

    /// Whether a refresh tracks VoiceOver focus (VoiceOver runs, or a UI test simulates it).
    private var anchorsFocus: Bool { voiceOverEnabled || Self.forcedFocusInPage != nil }

    /// Whether VoiceOver focus is inside this page now, before its content is hidden.
    private var focusIsInsidePage: Bool {
        Self.forcedFocusInPage ?? probe.voiceOverFocusIsInsidePage(pageOnScreen: onScreen)
    }

    /// Whether the page anchor is in the accessibility tree.
    private var showsPageAnchor: Bool { focus.showsAnchor && anchorsFocus }

    /// An invisible heading across the top of the page, named with the page's title; it
    /// takes no touches and draws nothing.
    private var pageAnchor: some View {
        Rectangle()
            .fill(.clear)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(pageTitle ?? "Current page")
            .accessibilityValue(transition.isRefreshing ? Self.loadingLabel : "")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.publication.page-anchor")
            .accessibilityFocused($focusedElement, equals: .pageAnchor)
    }

    /// Debug UI-test marker (`FST_UI_TEST_PAGE_ANCHOR=outside` only): XCUITest cannot hear
    /// announcements, so the boundary that posted one exposes it with the revision as its
    /// value. It persists, unlike the ~1 s spinner a slow simulator query can miss.
    ///
    /// - Parameter revision: The announced publication revision.
    /// - Returns: A 1-pt clear element.
    private func announcementMarker(_ revision: Int) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Self.loadingLabel)
            .accessibilityValue(String(revision))
            .accessibilityIdentifier("fst.publication.announced")
    }

    // MARK: Motion

    /// System or in-app Reduce Motion.
    /// Whether the page is in the tree: always when hidden content is retained, otherwise
    /// only until its fade-out completes (it is rebuilt for the new generation anyway).
    private var mountsContent: Bool {
        retainsHiddenContent || transition.phase == .content || transition.phase == .contentOut
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// Whether fades play.
    private var animates: Bool { fadeEnabled && !reduceMotion }

    /// Durations for the current motion settings (R3; instant swaps under Reduce Motion,
    /// no hold either when fades are frozen).
    private var timing: PublicationRefreshTransition.Timing {
        fadeEnabled ? .standard(reduceMotion: reduceMotion) : .instant
    }

    /// The fade for a move into `phase`, or nil for an instant swap.
    ///
    /// - Parameter phase: The phase being entered.
    /// - Returns: Content-out (300 ms ease-out), spinner-in (150 ms ease-in), spinner-out
    ///   (500 ms ease-out) or the web `fadeInUp` timing for the rebuilt content.
    private func animation(to phase: PublicationRefreshTransition.Phase) -> Animation? {
        guard animates else { return nil }
        switch phase {
        case .contentOut: return .easeOut(duration: Self.seconds(timing.contentOut))
        case .spinner: return .easeIn(duration: Self.seconds(timing.spinnerIn))
        case .spinnerOut: return .easeOut(duration: Self.seconds(timing.spinnerOut))
        case .content: return FestivalFadeIn.animation
        }
    }

    /// Apply a change, animating the phase it moves into.
    ///
    /// - Parameter change: The transition update.
    private func update(_ change: (inout PublicationRefreshTransition) -> Void) {
        var next = transition
        change(&next)
        guard next != transition else { return }
        let reveals = next.generation != transition.generation
        if next.isRefreshing && !transition.isRefreshing {
            if anchorsFocus {
                // Read focus before the content is hidden: hiding it moves VoiceOver.
                let inside = focusIsInsidePage
                focus.refreshStarted(focusInPage: inside)
                if inside { PublicationRefreshAnnouncer.gate.focusClaimed(for: next.targetRevision) }
            }
        } else if reveals {
            focus.contentRevealed()
        }
        if next.phase != transition.phase, let animation = animation(to: next.phase) {
            withAnimation(animation) {
                if reveals { onReveal?() }
                transition = next
            }
        } else {
            if reveals { onReveal?() }
            transition = next
        }
    }

    /// - Parameter duration: A duration.
    /// - Returns: The duration in seconds.
    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

// MARK: - Page anchor constants

/// Constants for the ``PublicationRefreshBoundary`` page anchor (stored statics cannot
/// live in the generic boundary).
private enum PublicationPageAnchor {
    /// The spinner's spoken label, also the anchor's value while the spinner is up.
    static let loadingLabel = "Loading new scores"

    /// Debug-only: XCUITest cannot run VoiceOver, so UI tests simulate where its focus is
    /// when a refresh starts: `FST_UI_TEST_PAGE_ANCHOR=inside` (or `1`) inside the page,
    /// `outside` elsewhere (tab bar, navigation bar). Nil runs the real focus check.
    static let forcedFocusInPage: Bool? = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["FST_UI_TEST_PAGE_ANCHOR"] {
        case "1", "inside": true
        case "outside": false
        default: nil
        }
        #else
        nil
        #endif
    }()
}

/// The process-wide once-per-publication announcement gate shared by every boundary.
@MainActor
enum PublicationRefreshAnnouncer {
    static var gate = PublicationRefreshAnnouncements()
}

extension View {
    /// Refresh this root page in place when the service publishes a new generation
    /// (``PublicationRefreshBoundary``). Apply inside `firstRun` so a refresh never
    /// re-evaluates the page's first-run carousel.
    ///
    /// - Parameter session: Shared app session.
    /// - Returns: The page inside a publication refresh boundary.
    func refreshesOnPublication(session: FestivalSession) -> some View {
        PublicationRefreshBoundary(session: session) { self }
    }
}
