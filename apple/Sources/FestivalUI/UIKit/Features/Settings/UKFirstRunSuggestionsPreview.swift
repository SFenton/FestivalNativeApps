#if os(iOS)
import FestivalCore
import UIKit

/// The Suggestions guide's sample cards, using the page's native card and the shared
/// templates. The guide supplies bounded catalogue songs and owns artwork permission.
@MainActor
final class UKFirstRunSuggestionsPreview: UIView {
    enum Mode {
        case category, scrolling

        fileprivate var templates: [FirstRunSuggestionsCategoryCardDemo.Template] {
            switch self {
            case .category: FirstRunSuggestionsCategoryCardDemo.templates
            case .scrolling: FirstRunSuggestionsCategoryCardDemo.scrollTemplates
            }
        }

        /// Maximum songs drawn across this demo's cards.
        var songCount: Int { templates.count * FirstRunSuggestionsCategoryCardDemo.songsPerCard }
    }

    private let session: FestivalSession
    private let mode: Mode
    private let track = UIStackView()
    private let slots: [UIView]
    private var pool: [Song]
    private var artwork = false
    private var currentTemplate = 0
    private var playbackTask: Task<Void, Never>?
    private var swapAnimator: UIViewPropertyAnimator?
    private var edgeMask: UKEdgeFadeMask?
    private var lastEdges: FirstRunAutoScroll.Edges?
    private var hardEdge = false
    private var startedAt: CFTimeInterval?

    /// Each scrolling card cascades separately; the single category swaps as a unit.
    var entrances: [(view: UIView, delay: TimeInterval)] {
        guard mode == .scrolling else { return [] }
        return slots.enumerated().map { ($0.element, Double($0.offset) * FirstRunMotion.staggerSeconds) }
    }

    /// - Parameters:
    ///   - session: The guide's shared session, used only for artwork.
    ///   - mode: One rotating card or the scrolling stack.
    init(session: FestivalSession, mode: Mode) {
        self.session = session
        self.mode = mode
        pool = FirstRunDemoSongs.placeholders(count: mode.songCount)
        slots = (0..<(mode == .scrolling ? mode.templates.count : 1)).map { _ in UIView() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        track.axis = .vertical
        track.spacing = 12
        track.translatesAutoresizingMaskIntoConstraints = false
        slots.forEach(track.addArrangedSubview)
        addSubview(track)
        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        if mode == .scrolling {
            track.topAnchor.constraint(equalTo: topAnchor).isActive = true
            edgeMask = UKEdgeFadeMask(view: self)
        } else {
            let center = track.centerYAnchor.constraint(equalTo: centerYAnchor)
            center.priority = .defaultLow
            NSLayoutConstraint.activate([track.topAnchor.constraint(greaterThanOrEqualTo: topAnchor), center])
        }
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { playbackTask?.cancel() }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeMask?.layout()
        updateScroll(at: CACurrentMediaTime(), refreshingMask: true)
    }

    /// Refreshes the currently displayed cards and gates their decorative art.
    ///
    /// - Parameters:
    ///   - songs: Successful, bounded catalogue result; nil retains the redacted layout.
    ///   - allowsArtwork: True only on the active slide in a visible, unconstrained scene.
    func configure(songs: [Song]?, allowsArtwork: Bool) {
        let nextPool = songs ?? (pool.first?.isFirstRunPlaceholder == true
            ? pool : FirstRunDemoSongs.placeholders(count: mode.songCount))
        guard pool != nextPool || artwork != allowsArtwork else { return }
        pool = nextPool
        artwork = allowsArtwork
        rebuild()
    }

    /// Starts or cancels the current lesson's motion without restarting it on a layout pass.
    ///
    /// - Parameters:
    ///   - enabled: Whether decorative motion is allowed.
    ///   - hardEdge: Whether the fade ramps must be replaced by a clipped edge.
    func setPlayback(enabled: Bool, hardEdge: Bool) {
        if self.hardEdge != hardEdge {
            self.hardEdge = hardEdge
            updateScroll(at: CACurrentMediaTime(), refreshingMask: true)
        }
        if enabled, playbackTask == nil {
            startedAt = CACurrentMediaTime()
            playbackTask = Task { [weak self, mode] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: mode == .scrolling ? .milliseconds(33) : FirstRunDemoTiming.swapInterval)
                    } catch { return }
                    guard let self else { return }
                    switch mode {
                    case .category: await self.advanceCategory()
                    case .scrolling: self.updateScroll(at: CACurrentMediaTime())
                    }
                }
            }
        } else if !enabled, let playbackTask {
            playbackTask.cancel()
            self.playbackTask = nil
            startedAt = nil
            if swapAnimator?.state == .active { swapAnimator?.stopAnimation(true) }
            swapAnimator = nil
            track.alpha = 1
            track.transform = .identity
            updateScroll(at: CACurrentMediaTime())
        }
    }

    private func rebuild() {
        for (index, slot) in slots.enumerated() {
            slot.subviews.forEach { $0.removeFromSuperview() }
            let template = mode == .scrolling ? index : currentTemplate
            let songs = FirstRunSuggestionsCategoryCardDemo.window(of: pool, template: template)
            let card = UKSuggestionCardView(
                category: mode.templates[template].category(songs), session: session,
                presentation: .guide(allowsArtwork: artwork)
            )
            slot.ukPin(card)
        }
        setNeedsLayout()
    }

    private func advanceCategory() async {
        animateCategory(visible: false)
        do { try await Task.sleep(for: FirstRunDemoTiming.fade) } catch { return }
        currentTemplate = (currentTemplate + 1) % mode.templates.count
        rebuild()
        animateCategory(visible: true)
    }

    private func animateCategory(visible: Bool) {
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1), controlPoint2: CGPoint(x: 0.25, y: 1))
        let animator = UIViewPropertyAnimator(duration: FirstRunDemoTiming.fadeSeconds, timingParameters: timing)
        animator.addAnimations { [track] in
            track.alpha = visible ? 1 : 0
            track.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 8)
        }
        swapAnimator = animator
        animator.startAnimation()
    }

    private func updateScroll(at time: CFTimeInterval, refreshingMask: Bool = false) {
        guard let edgeMask else { return }
        let maxOffset = Double(max(0, track.bounds.height - bounds.height))
        let offset = FirstRunAutoScroll.offset(elapsed: startedAt.map { time - $0 } ?? 0, maxOffset: maxOffset)
        track.transform = CGAffineTransform(translationX: 0, y: -offset)
        let edges = FirstRunAutoScroll.edges(offset: offset, maxOffset: maxOffset)
        guard refreshingMask || edges != lastEdges else { return }
        lastEdges = edges
        let ramp = min(bounds.height / 2, CGFloat(ScrollEdgeFade.ramp(FirstRunAutoScroll.edgeFade, hardEdge: hardEdge)))
        edgeMask.apply(stops: [
            (0, edges.top && ramp > 0 ? 0 : 1),
            (ramp, 1),
            (bounds.height - ramp, 1),
            (bounds.height, edges.bottom && ramp > 0 ? 0 : 1),
        ])
    }
}
#endif
