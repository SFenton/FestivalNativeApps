#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Fade in

/// The app-wide "new content fades in as it loads" rule (``FestivalFadeIn``): opacity 0
/// to 1 while rising 12 pt over 400 ms on the web `ease-out` curve, items staggered by
/// 125 ms up to the first screenful. Nothing animates under Reduce Motion (system or
/// in-app) or while ``isEnabled`` is off.
@MainActor
enum UKFadeIn {
    /// Whether fades run (`festivalFadeInEnabled`; UI tests that freeze animations turn
    /// it off).
    static var isEnabled = true

    /// The web `ease-out` curve, 400 ms.
    ///
    /// - Parameter duration: Seconds; the shared fade length by default.
    /// - Returns: An animator for it, not yet started.
    static func animator(duration: TimeInterval = FestivalFadeIn.duration) -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(duration: duration, controlPoint1: CGPoint(x: 0, y: 0), controlPoint2: CGPoint(x: 0.58, y: 1))
    }

    /// Fades a view in (``View/festivalFadeIn(staggerIndex:)``).
    ///
    /// - Parameters:
    ///   - view: The view; set to transparent and shifted down first.
    ///   - staggerIndex: Its place in a staggered list; nil fades it at once; negative
    ///     shows it without a fade (a row rebuilt after the first reveal).
    ///   - rises: Whether it also rises 12 pt (`fadeInUp`).
    static func fadeIn(_ view: UIView, staggerIndex: Int? = nil, rises: Bool = true) {
        let start: FestivalFadeInStart = staggerIndex.map { FestivalFadeIn.start(forIndex: $0) } ?? .after(0)
        let delay: TimeInterval
        switch start {
        case .never:
            view.alpha = 1
            view.transform = .identity
            return
        case let .after(seconds), let .card(seconds):
            delay = seconds
        case .pastFirstScreen:
            delay = Double(FestivalFadeIn.maxStaggeredItems) * FestivalFadeIn.staggerInterval
        }
        guard isEnabled, !UKAccessibility.reduceMotion else {
            view.alpha = 1
            view.transform = .identity
            return
        }
        view.alpha = 0
        view.transform = rises ? CGAffineTransform(translationX: 0, y: FestivalFadeIn.riseDistance) : .identity
        let animator = animator()
        animator.addAnimations {
            view.alpha = 1
            view.transform = .identity
        }
        animator.startAnimation(afterDelay: delay)
    }
}

// MARK: - Reload gate

/// What the content under a ``UKReloadGate`` is told on each change (``FestivalReloadReveal``).
typealias UKReloadReveal = FestivalReloadReveal

/// The spinner-to-content transition for a reloading region (``FestivalReloadGate``): a
/// spinner fades in (150 ms), holds at least 400 ms, fades out (500 ms), then the content
/// fades in (400 ms). Driven by the shared ``ReloadTransition`` state machine. A new `key`
/// restarts it. With `retainsFrame` the content stays laid out after its first reveal and
/// is told whether it shows its result (``onRevealChange``), so a list keeps its frame
/// while it reloads.
@MainActor
final class UKReloadGate: UIView {
    /// The content the gate reveals.
    let contentView = UIView()
    private let spinner: UKLoadingView
    private var transition: ReloadTransition
    private var shownKey: AnyHashable?
    private var keyPending = false
    private var timer: Task<Void, Never>?
    private let retainsFrame: Bool
    private var lastReveal: UKReloadReveal?

    /// Called just before the content is revealed (``FestivalReloadGate`` `onReveal`).
    var onReveal: (() -> Void)?
    /// Retaining mode: called whenever the content's reveal state changes.
    var onRevealChange: ((UKReloadReveal) -> Void)?

    /// Creates a gate.
    ///
    /// - Parameters:
    ///   - key: What the content depends on; changing it reloads.
    ///   - isLoading: Whether a load is in flight.
    ///   - spinnerLabel: Spoken label of the spinner.
    ///   - spinnerIdentifier: Spinner identifier.
    ///   - retainsFrame: Keep the content laid out after its first reveal.
    init(key: AnyHashable, isLoading: Bool, spinnerLabel: String = "Loading", spinnerIdentifier: String? = nil, retainsFrame: Bool = false) {
        transition = ReloadTransition(isLoading: isLoading)
        shownKey = key
        self.retainsFrame = retainsFrame
        spinner = UKLoadingView(accessibilityLabel: spinnerLabel, placement: .fill)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for view in [contentView, spinner] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        spinner.accessibilityIdentifier = spinnerIdentifier
        spinner.isUserInteractionEnabled = !retainsFrame
        render(animation: nil)
        scheduleWait()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { timer?.cancel() }

    // MARK: Inputs

    /// Updates the gate; call whenever the key or the loading flag changes.
    ///
    /// - Parameters:
    ///   - key: What the content depends on.
    ///   - isLoading: Whether a load is in flight.
    func update(key: AnyHashable, isLoading: Bool) {
        if key != shownKey {
            shownKey = key
            apply { $0.reload() }
        }
        apply { $0.setLoading(isLoading) }
    }

    private var timing: ReloadTransition.Timing {
        ReloadTransition.Timing.standard(reduceMotion: UKAccessibility.reduceMotion)
    }

    private var animates: Bool { UKFadeIn.isEnabled && !UKAccessibility.reduceMotion }

    private func apply(_ change: (inout ReloadTransition) -> Void) {
        var next = transition
        change(&next)
        guard next != transition else { return }
        let reveals = next.phase == .content && transition.phase != .content
        let phaseChanged = next.phase != transition.phase
        if reveals { onReveal?() }
        let previous = transition.phase
        transition = next
        render(animation: phaseChanged ? animation(from: previous, to: next.phase) : nil)
        scheduleWait()
    }

    private enum FadeKind {
        case spinnerIn, spinnerOut, content
    }

    private func animation(from old: ReloadTransition.Phase, to new: ReloadTransition.Phase) -> (FadeKind, TimeInterval)? {
        guard animates else { return nil }
        switch new {
        case .spinner: return (.spinnerIn, seconds(timing.spinnerIn))
        case .spinnerOut: return (.spinnerOut, seconds(timing.spinnerOut))
        case .content: return (.content, FestivalFadeIn.duration)
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    // MARK: Render

    private func render(animation: (FadeKind, TimeInterval)?) {
        let hasContent = transition.hasShownContent
        let showsResult = transition.showsContent && !keyPending
        let spinnerAlpha: CGFloat = transition.showsSpinner || keyPending ? 1 : 0
        let contentAlpha: CGFloat = retainsFrame ? (hasContent ? 1 : 0) : (showsResult ? 1 : 0)
        let apply = { [self] in
            spinner.alpha = spinnerAlpha
            contentView.alpha = contentAlpha
        }
        contentView.isHidden = retainsFrame ? !hasContent : !showsResult && contentView.alpha == 0 && animation == nil
        contentView.isUserInteractionEnabled = retainsFrame || showsResult
        contentView.accessibilityElementsHidden = retainsFrame ? !hasContent : !showsResult
        spinner.isHidden = false
        if let (kind, duration) = animation, duration > 0 {
            contentView.isHidden = false
            let animator: UIViewPropertyAnimator
            switch kind {
            case .spinnerIn: animator = UIViewPropertyAnimator(duration: duration, curve: .easeIn)
            case .spinnerOut: animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut)
            case .content: animator = UKFadeIn.animator(duration: duration)
            }
            animator.addAnimations(apply)
            animator.addCompletion { [weak self] _ in self?.contentView.isHidden = !(self?.retainsFrame == true ? hasContent : showsResult) }
            animator.startAnimation()
        } else {
            apply()
        }
        if retainsFrame {
            let reveal = UKReloadReveal(showsResult: showsResult, generation: transition.generation)
            if reveal != lastReveal {
                lastReveal = reveal
                onRevealChange?(reveal)
            }
        }
    }

    private func scheduleWait() {
        timer?.cancel()
        guard let wait = transition.pendingWait else { return }
        let duration = timing.duration(of: wait)
        timer = Task { @MainActor [weak self] in
            if duration > .zero { try? await Task.sleep(for: duration) }
            guard !Task.isCancelled, let self else { return }
            self.apply { $0.timerFired(wait) }
        }
    }
}

// MARK: - List jump

/// A far jump in a long list (A-Z scrubber, "jump to me"): fade out 70 ms, scroll with no
/// animation, scroll again after 50 ms to correct estimated row heights, fade in 160 ms
/// (``ListJump``). Near jumps scroll normally.
@MainActor
enum UKListJump {
    /// Whether a jump of `rowDistance` rows is far for a viewport (more than a screenful).
    ///
    /// - Parameters:
    ///   - rowDistance: Rows between the current position and the target.
    ///   - viewportHeight: Height of the list.
    static func isFar(rowDistance: Int, viewportHeight: CGFloat) -> Bool {
        ListJump.isFar(rowDistance: rowDistance, viewportHeight: viewportHeight)
    }

    /// Runs the teleport on a list view.
    ///
    /// - Parameters:
    ///   - view: The list (or its container); its alpha is animated.
    ///   - scroll: Scrolls to the target without animation; called twice.
    static func teleport(_ view: UIView, scroll: @escaping @MainActor () -> Void) async {
        UIView.animate(withDuration: ListJump.fadeOut, delay: 0, options: .curveEaseOut) { view.alpha = 0 }
        try? await Task.sleep(for: .seconds(ListJump.fadeOut))
        UIView.performWithoutAnimation { scroll() }
        try? await Task.sleep(for: ListJump.correction)
        UIView.performWithoutAnimation { scroll() }
        UIView.animate(withDuration: ListJump.fadeIn, delay: 0, options: .curveEaseIn) { view.alpha = 1 }
    }
}
#endif
