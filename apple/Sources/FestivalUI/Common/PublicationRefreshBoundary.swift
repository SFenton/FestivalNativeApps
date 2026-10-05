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
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var transition: PublicationRefreshTransition

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
                FestivalLoadingView(accessibilityLabel: "Loading new scores")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fst.publication.refreshing")
                    .transition(.opacity)
            }
        }
        .onChange(of: session.publicationRevision) { _, revision in
            update { $0.publicationChanged(to: revision) }
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
