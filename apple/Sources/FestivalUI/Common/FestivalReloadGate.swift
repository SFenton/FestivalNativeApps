import SwiftUI
import FestivalCore

// MARK: - FestivalReloadGate

/// A page's content area with the web's load and reload sequence (issue #71): on a new
/// selection or a refetch the shown content leaves at once and the spinner fades in, the
/// spinner stays until the data is ready, fades out, and the new content fades in with its
/// load-in stagger. The sequence logic is ``ReloadTransition`` (FestivalCore).
///
/// Keep selectors, pickers, toolbars and pagers **outside** the gate so they stay usable
/// while it runs; a newer choice simply restarts from the spinner. The content builder is
/// only called while content is shown, so it may return nothing for a loading state.
///
/// A changed `key` removes the content in the same update that delivers it, without a
/// fade-out (as the web's `Page` renders no content outside `ContentIn`): lazily built
/// rows read the live selection, so a fading copy would show old rows with the new
/// metric, instrument or sort. The content is rebuilt (`.id`) for each reveal, which restarts
/// `festivalFadeIn` staggers and scroll position (web resets scroll on these reloads).
///
/// A page whose header shares the rows' scroll view (the song leaderboard's song header,
/// issue #316) uses the **retained-frame** initializer instead: the content builder is
/// called from the first reveal on, with a ``FestivalReloadReveal`` saying whether the
/// result may show. The frame (scroll view and header) fades in with the first load and
/// then stays put; only the result inside it leaves and returns, as the web keeps
/// `SongInfoHeader` outside its `LoadGate` (load-transition R4).
///
/// Reduce Motion (system or in-app) and `festivalFadeInEnabled == false` swap instantly;
/// with Reduce Motion the spinner still holds 400 ms so it never blinks.
struct FestivalReloadGate<Key: Equatable, Content: View>: View {
    /// What is selected; a change starts a reload.
    let key: Key
    /// Whether the data for `key` is still loading.
    let isLoading: Bool
    /// Spoken label for the spinner.
    let spinnerLabel: String
    /// Accessibility identifier for the spinner, for UI tests.
    let spinnerIdentifier: String?
    /// Called in the update that reveals content, before it is built (e.g. to open a
    /// time-based stagger window).
    let onReveal: (() -> Void)?
    /// Keep the content built from the first reveal on, passing it whether the result
    /// may show, instead of removing it for each reload.
    let retainsFrame: Bool
    /// The loaded content (or its empty/error state).
    let content: (FestivalReloadReveal) -> Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.festivalFadeInEnabled) private var fadeEnabled
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var transition: ReloadTransition
    @State private var shownKey: Key

    /// - Parameters:
    ///   - key: What is selected (instrument, metric, filter, sort, mode, page…); a change
    ///     starts a reload.
    ///   - isLoading: Whether the data for `key` is still loading. Loading that starts
    ///     while content is shown (a retry or refetch) is also a reload.
    ///   - spinnerLabel: VoiceOver label for the spinner.
    ///   - spinnerIdentifier: Accessibility identifier for the spinner, for UI tests.
    ///   - onReveal: Called in the update that reveals content, before it is built.
    ///   - content: The loaded content; only built while content is shown.
    init(
        key: Key, isLoading: Bool, spinnerLabel: String = "Loading", spinnerIdentifier: String? = nil,
        onReveal: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.key = key
        self.isLoading = isLoading
        self.spinnerLabel = spinnerLabel
        self.spinnerIdentifier = spinnerIdentifier
        self.onReveal = onReveal
        retainsFrame = false
        self.content = { _ in content() }
        _transition = State(initialValue: ReloadTransition(isLoading: isLoading))
        _shownKey = State(initialValue: key)
    }

    /// A gate that keeps its frame (scroll view and page header) from the first reveal
    /// on, and swaps only the result inside it (issue #316).
    ///
    /// - Parameters:
    ///   - key: What is selected; a change starts a reload of the result only.
    ///   - isLoading: Whether the data for `key` is still loading.
    ///   - spinnerLabel: VoiceOver label for the spinner.
    ///   - spinnerIdentifier: Accessibility identifier for the spinner, for UI tests.
    ///   - onReveal: Called in the update that reveals content, before it is built.
    ///   - content: The frame, built from the first reveal on; it shows its result
    ///     (rows, empty or error state) only while ``FestivalReloadReveal/showsResult``.
    init(
        key: Key, isLoading: Bool, spinnerLabel: String = "Loading", spinnerIdentifier: String? = nil,
        onReveal: (() -> Void)? = nil,
        @ViewBuilder retainingFrame content: @escaping (FestivalReloadReveal) -> Content
    ) {
        self.key = key
        self.isLoading = isLoading
        self.spinnerLabel = spinnerLabel
        self.spinnerIdentifier = spinnerIdentifier
        self.onReveal = onReveal
        retainsFrame = true
        self.content = content
        _transition = State(initialValue: ReloadTransition(isLoading: isLoading))
        _shownKey = State(initialValue: key)
    }

    /// Identifies the running wait so a phase change restarts it.
    private struct WaitID: Equatable {
        let phase: ReloadTransition.Phase
        let generation: Int
        let wait: ReloadTransition.Wait?
    }

    var body: some View {
        // A key that arrived in this update hides the content now, before `onChange` runs.
        let keyPending = key != shownKey
        let showsResult = transition.showsContent && !keyPending
        ZStack {
            if retainsFrame {
                if transition.hasShownContent {
                    // The frame fades in with the first reveal only; the result inside
                    // it leaves at once on a new key (no inherited spinner fade).
                    content(FestivalReloadReveal(showsResult: showsResult, generation: transition.generation))
                        .animation(nil, value: key)
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            } else if showsResult {
                content(FestivalReloadReveal(showsResult: true, generation: transition.generation))
                    .id(transition.generation)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            if transition.showsSpinner || keyPending {
                FestivalLoadingView(accessibilityLabel: spinnerLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(spinnerIdentifier ?? "")
                    // Over a retained frame the spinner must not block its header.
                    .allowsHitTesting(!retainsFrame)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(animation(to: .spinner), value: key)
        .onChange(of: key) { _, newKey in
            shownKey = newKey
            update { $0.reload() }
        }
        .onChange(of: isLoading) { _, loading in
            update { $0.setLoading(loading) }
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
    }

    // MARK: Motion

    /// Whether fades play (no Reduce Motion, fades enabled).
    private var animates: Bool {
        fadeEnabled && !systemReduceMotion && !appReduceMotion
    }

    /// Durations for the current motion settings; instant when fades are disabled.
    private var timing: ReloadTransition.Timing {
        fadeEnabled
            ? .standard(reduceMotion: systemReduceMotion || appReduceMotion)
            : ReloadTransition.Timing(spinnerIn: .zero, minimumSpinner: .zero, spinnerOut: .zero)
    }

    /// The fade for a move into `phase`, or nil for an instant swap.
    ///
    /// - Parameter phase: The phase being entered.
    /// - Returns: Spinner-in (150 ms ease-in), spinner-out (500 ms ease-out) or the web
    ///   `fadeInUp` timing for new content.
    private func animation(to phase: ReloadTransition.Phase) -> Animation? {
        guard animates else { return nil }
        switch phase {
        case .spinner: return .easeIn(duration: Self.seconds(timing.spinnerIn))
        case .spinnerOut: return .easeOut(duration: Self.seconds(timing.spinnerOut))
        case .content: return FestivalFadeIn.animation
        }
    }

    /// Apply a change, animating the phase it moves into.
    ///
    /// - Parameter change: Mutation of the transition.
    private func update(_ change: (inout ReloadTransition) -> Void) {
        var next = transition
        change(&next)
        guard next != transition else { return }
        let reveals = next.phase == .content && transition.phase != .content
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
    /// - Returns: It in seconds.
    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

// MARK: - FestivalReloadReveal

/// What a retained-frame ``FestivalReloadGate`` tells its content (issue #316).
struct FestivalReloadReveal: Equatable {
    /// Whether the result (rows, empty or error state) may show now; false from a new
    /// key or refetch until the spinner has faded out.
    let showsResult: Bool
    /// Bumps for every reveal; identity for a result that must be rebuilt.
    let generation: Int
}
