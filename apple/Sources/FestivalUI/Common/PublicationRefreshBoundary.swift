import SwiftUI
import FestivalCore

// MARK: - PublicationRefreshBoundary

/// Refreshes one page in place when the service publishes a new generation (issue #304),
/// like the web's `PublicationBoundary`, which keeps the route and remounts the pages.
///
/// The sequence is ``PublicationRefreshTransition`` (FestivalCore): the content fades out
/// as the spinner fades in, the spinner holds ≥400 ms and until `prepare` has finished for
/// the newest generation, then the page is rebuilt and fades in while the spinner fades
/// out; the rebuilt page loads its own data with its own load fade. The hidden content
/// stays mounted (no hit testing, hidden from VoiceOver) so the page's title, toolbar and
/// navigation stay put; it is never shown again.
///
/// VoiceOver stays on the page (``PublicationRefreshFocus``, FestivalCore): while
/// VoiceOver runs, a refresh adds a **page anchor**, an invisible heading named with the
/// page's ``festivalNavigationTitle(_:)`` that lives outside the rebuilt content. Focus
/// moves to it as the old content is hidden (it reads "*Title*, heading, Loading new
/// scores"), stays there through the spinner and is restored to it after the rebuild;
/// the anchor retires once the person moves on. HIG VoiceOver: "Give each page or screen
/// a unique, succinct title describing its content and purpose."
///
/// HIG Progress indicators (iOS, iPadOS): "Perform automatic content updates regularly;
/// don't make people initiate every update." HIG Accessibility: with Reduce Motion "reduce
/// automatic and repetitive animation", so system or in-app Reduce Motion (and
/// `festivalFadeInEnabled == false`) swaps instantly while the spinner still holds 400 ms.
struct PublicationRefreshBoundary<Content: View>: View {
    let session: FestivalSession
    /// Readies page state for a generation before the page is rebuilt (for example,
    /// re-reading a `Song` from the new catalogue); nil when nothing needs preparing.
    let prepare: ((Int) async -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.festivalFadeInEnabled) private var fadeEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var transition: PublicationRefreshTransition
    @State private var focus = PublicationRefreshFocus()
    @AccessibilityFocusState private var focusedElement: PublicationRefreshFocus.Element?
    /// The page's last published title (kept across the rebuild and its own load).
    @State private var pageTitle: String?

    /// - Parameters:
    ///   - session: Shared app session whose publication revision is watched.
    ///   - prepare: Called with the new revision while the spinner is up.
    ///   - content: The page.
    init(
        session: FestivalSession,
        prepare: ((Int) async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.session = session
        self.prepare = prepare
        self.content = content
        _transition = State(initialValue: PublicationRefreshTransition(revision: session.publicationRevision))
    }

    /// Identifies the running spinner hold so a new spinner restarts it.
    private struct HoldID: Equatable {
        let generation: Int
        let wait: PublicationRefreshTransition.Wait?
    }

    var body: some View {
        ZStack {
            content()
                .id(transition.generation)
                .opacity(transition.showsContent ? 1 : 0)
                .allowsHitTesting(transition.showsContent)
                .accessibilityHidden(!transition.showsContent)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            if transition.showsSpinner {
                FestivalLoadingView(accessibilityLabel: Self.loadingLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fst.publication.refreshing")
                    .accessibilityFocused($focusedElement, equals: .spinner)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if showsPageAnchor { pageAnchor }
        }
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
            focus.focusChanged(from: old, to: new, refreshing: transition.showsSpinner)
        }
        .task(id: focus.anchorFocusRequest) {
            guard focus.anchorFocusRequest > 0, voiceOverEnabled, focus.showsAnchor else { return }
            // Let the anchor (and, after a rebuild, the new content) enter the
            // accessibility tree before VoiceOver is pointed at it.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            focusedElement = .pageAnchor
        }
        .task(id: HoldID(generation: transition.generation, wait: transition.pendingWait)) {
            guard transition.pendingWait != nil else { return }
            // Frozen fades (`festivalFadeInEnabled == false`) skip the hold, like
            // `FestivalReloadGate`; Reduce Motion keeps it so the spinner never blinks.
            if fadeEnabled {
                try? await Task.sleep(for: PublicationRefreshTransition.minimumSpinnerDuration)
            }
            guard !Task.isCancelled else { return }
            update { $0.minimumSpinnerElapsed() }
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

    /// See ``PublicationPageAnchor/forced``.
    private static var forcesPageAnchor: Bool { PublicationPageAnchor.forced }

    /// Whether a refresh keeps VoiceOver on a page anchor.
    private var anchorsFocus: Bool { voiceOverEnabled || Self.forcesPageAnchor }

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
            .accessibilityValue(transition.showsSpinner ? Self.loadingLabel : "")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.publication.page-anchor")
            .accessibilityFocused($focusedElement, equals: .pageAnchor)
    }

    // MARK: Motion

    /// System or in-app Reduce Motion.
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// Whether fades play.
    private var animates: Bool { fadeEnabled && !reduceMotion }

    /// Apply a change, animating the phase it moves into: content out / spinner in
    /// (150 ms ease-in), or the rebuilt content in (web `fadeInUp` timing).
    ///
    /// - Parameter change: The transition update.
    private func update(_ change: (inout PublicationRefreshTransition) -> Void) {
        var next = transition
        change(&next)
        guard next != transition else { return }
        if next.showsSpinner && !transition.showsSpinner {
            if anchorsFocus { focus.refreshStarted() }
        } else if next.generation != transition.generation {
            focus.contentRevealed()
        }
        guard animates, next.phase != transition.phase else {
            transition = next
            return
        }
        let animation: Animation = next.showsSpinner
            ? .easeIn(duration: Self.seconds(PublicationRefreshTransition.fadeOutDuration))
            : FestivalFadeIn.animation
        withAnimation(animation) { transition = next }
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

    /// Debug-only: UI tests set `FST_UI_TEST_PAGE_ANCHOR=1` to keep the anchor without
    /// VoiceOver (XCUITest cannot run VoiceOver), so a journey can see where focus goes.
    static let forced: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FST_UI_TEST_PAGE_ANCHOR"] == "1"
        #else
        false
        #endif
    }()
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
