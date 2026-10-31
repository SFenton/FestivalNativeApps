#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Backdrop view

/// The one shared, animated album-art backdrop of a window: the UIKit counterpart of
/// ``ArtworkBackdropCanvas`` plus ``FestivalBackgroundHost``.
///
/// The window root installs it once, behind the tab container (``install(in:)``), so every
/// page shows through it, the carousel never restarts on a tab switch or push, and opening
/// a song fades that song's cover over the carousel (and back on pop) because pages declare
/// their mode through ``UKBackgroundRegistration``. It is decorative: not interactive and
/// hidden from accessibility (pattern R3).
///
/// Cost: carousel slots are ``CarouselSlotView``s (the SwiftUI app's own Core Animation
/// slot, pre-sampled keyframes capped at 30 fps) and covers fade with one `CABasicAnimation`
/// each, so a running transition does no per-frame app work. Nothing here uses a display
/// link.
final class UKBackgroundView: UIView {
    /// Backdrops created in this process; the debug probe reports it so a test can tell
    /// whether the view was rebuilt.
    private(set) static var installCount = 0

    private let session: FestivalSession
    private let host: UKBackgroundHost
    private let observation = UKObservationBag()
    private var slotViews: [Int: CarouselSlotView] = [:]
    private var coverViews: [UUID: UKCoverLayerView] = [:]
    private var settingsObserver: NSObjectProtocol?
    private var probe: UKBackgroundProbeView?

    /// Creates the backdrop for a session.
    ///
    /// - Parameter session: Artwork cache and coordinator owner.
    init(session: FestivalSession) {
        self.session = session
        host = UKBackgroundHost(session: session)
        super.init(frame: .zero)
        Self.installCount += 1
        backgroundColor = BrandUIColors.appBackground
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UKSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (view: UKBackgroundView, _) in
            view.apply()
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["FST_DEBUG_BACKGROUND_PROBE"] == "1" {
            probe = UKBackgroundProbeView()
            host.didEvaluate = { [weak self] in self?.updateProbe() }
        }
        #endif
        observation.observe { [weak self] in self?.apply() }
        host.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    // MARK: Installation

    /// Fills `root` with the backdrop, beneath everything already in it.
    ///
    /// - Parameter root: The window root's view.
    func install(in root: UIView) {
        frame = root.bounds
        root.insertSubview(self, at: 0)
        if let probe {
            probe.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            root.addSubview(probe)
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        host.resize(bounds.size, scale: window?.screen.scale ?? traitCollection.displayScale)
        slotViews.values.forEach { $0.frame = bounds }
        coverViews.values.forEach { $0.frame = bounds }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
        apply()
    }

    // MARK: Drawing

    /// Black-overlay equivalent (0.7, or 0.82 with increased contrast).
    private var dimming: Double {
        BackdropPresentation.dimming(
            appMoreContrast: UKSettings.bool("fst.accessibility.moreContrast", default: false),
            systemIncreased: traitCollection.accessibilityContrast == .high
        )
    }

    /// Show the shared state: the carousel slots, then the song covers above them.
    ///
    /// Runs inside the observation, so it re-runs when the carousel's slots, the cover or
    /// the network's Low Data state change.
    private func apply() {
        let coordinator = session.backgroundCoordinator
        let carousel = coordinator.carousel.state
        let overlay = coordinator.overlay
        let exiting = coordinator.exiting
        let constrained = ArtworkNetworkStatus.shared.isConstrained
        let dimming = self.dimming
        defer { updateProbe() }

        if DebugAnimationOverride.noBackdrop {
            showOnly(color: BrandUIColors.appBackground)
            return
        }
        if DebugAnimationOverride.flatBackdrop {
            showOnly(color: UIColor(white: 0.5 * (1 - dimming), alpha: 1))
            return
        }
        backgroundColor = BrandUIColors.appBackground
        let showsArt = BackdropPresentation.showsArt(
            appLessTransparency: UKSettings.bool("fst.accessibility.lessTransparency", default: false),
            systemReduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
            constrained: constrained
        )
        let animate = window != nil
        let lightness = 1 - dimming

        // Carousel slots (a slot without an image has no view, as in SwiftUI).
        var liveSlots: Set<Int> = []
        if showsArt {
            for layer in carousel.layers {
                guard let image = layer.image else { continue }
                liveSlots.insert(layer.id)
                let view = slotViews[layer.id] ?? makeSlot(layer.id)
                view.layer.zPosition = layer.id == carousel.active ? 1 : 0
                view.apply(
                    image: image, layer: layer, isActive: layer.id == carousel.active,
                    lightness: lightness, animate: animate
                )
            }
        }
        for id in slotViews.keys where !liveSlots.contains(id) {
            slotViews[id]?.removeFromSuperview()
            slotViews[id] = nil
        }

        // Song covers: the exiting one beneath the entering one.
        let covers = showsArt ? CoverLayer.layers(overlay: overlay, exiting: exiting) : []
        for (index, cover) in covers.enumerated() {
            let view = coverViews[cover.id] ?? makeCover(cover.id)
            view.layer.zPosition = 2 + CGFloat(index)
            view.apply(layer: cover, lightness: lightness, animate: animate)
        }
        let liveCovers = Set(covers.map(\.id))
        for id in coverViews.keys where !liveCovers.contains(id) {
            coverViews[id]?.removeFromSuperview()
            coverViews[id] = nil
        }
    }

    /// Debug override: nothing but one flat colour.
    private func showOnly(color: UIColor) {
        backgroundColor = color
        slotViews.values.forEach { $0.removeFromSuperview() }
        slotViews.removeAll()
        coverViews.values.forEach { $0.removeFromSuperview() }
        coverViews.removeAll()
    }

    private func makeSlot(_ id: Int) -> CarouselSlotView {
        let view = CarouselSlotView(frame: bounds)
        view.isUserInteractionEnabled = false
        addSubview(view)
        slotViews[id] = view
        return view
    }

    private func makeCover(_ id: UUID) -> UKCoverLayerView {
        let view = UKCoverLayerView(frame: bounds)
        addSubview(view)
        coverViews[id] = view
        return view
    }

    // MARK: Debug probe

    /// Publishes the shared state through the probe element (`FST_DEBUG_BACKGROUND_PROBE=1`
    /// in a Debug build only), so a UI test can see whether the carousel restarted.
    private func updateProbe() {
        guard let probe else { return }
        let coordinator = session.backgroundCoordinator
        let state = coordinator.carousel.state
        let mode: String
        switch coordinator.resolvedMode {
        case .carousel: mode = "carousel"
        case .song: mode = "song"
        }
        probe.accessibilityValue = [
            "mode=\(mode)",
            "cover=\(coordinator.overlay?.raw ?? "none")",
            "slot=\(state.active)",
            "raw=\(state.currentRaw ?? "none")",
            "moving=\(state.animating ? 1 : 0)",
            "plays=\(host.carouselPlays)",
            "views=\(Self.installCount)",
        ].joined(separator: ";")
    }
}

/// The accessibility element a UI test reads (``UKBackgroundView/updateProbe()``); never
/// created unless the launch asks for it.
private final class UKBackgroundProbeView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "fst.debug.backgroundProbe"
        accessibilityLabel = "Background probe"
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Song cover

/// One song cover, faded by Core Animation from the shared timestamps: the UIKit
/// counterpart of ``CoverLayerView``.
///
/// On first sight and whenever the fade changes direction it jumps (without animation) to
/// the timestamp value for "now", then animates the remainder on the web's `ease` curve.
/// Only opacity animates, so a fade is composited without layout or app work per frame.
final class UKCoverLayerView: UIView {
    private let imageLayer = CALayer()
    private let dimLayer = CALayer()
    private var syncedKey: SyncKey?
    private var shownImage: CGImage?

    /// Inputs that require re-synchronising with the shared clock.
    private struct SyncKey: Equatable {
        let exitStart: Date?
        let animate: Bool
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        dimLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(imageLayer)
        layer.addSublayer(dimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        CATransaction.commit()
    }

    /// Show a cover and (re)sync its fade when its timing changed.
    ///
    /// - Parameters:
    ///   - layer: Cover and fade timing.
    ///   - lightness: Remaining brightness for art (the brand surface is never dimmed).
    ///   - animate: Whether the window is on screen.
    func apply(layer cover: CoverLayer, lightness: Double, animate: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let image = cover.overlay.image {
            backgroundColor = nil
            if shownImage !== image {
                shownImage = image
                imageLayer.contents = image
            }
            imageLayer.isHidden = false
            dimLayer.isHidden = false
            dimLayer.opacity = Float(max(0, min(1, 1 - lightness)))
        } else {
            backgroundColor = BrandUIColors.appBackground
            imageLayer.isHidden = true
            dimLayer.isHidden = true
        }
        CATransaction.commit()
        let key = SyncKey(exitStart: cover.exit?.start, animate: animate)
        guard key != syncedKey else { return }
        syncedKey = key
        sync(cover, animate: animate)
    }

    /// Jump to the shared clock's current opacity, then animate the remainder.
    private func sync(_ cover: CoverLayer, animate: Bool) {
        let now = Date()
        let current = Float(cover.opacity(at: now))
        let left = cover.remaining(at: now)
        let target = Float(cover.target)
        layer.removeAnimation(forKey: "fade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = animate || left <= 0 ? target : current
        CATransaction.commit()
        guard animate, left > 0 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = current
        fade.toValue = target
        fade.duration = left
        // CSS `ease`, the web's default `transition` timing.
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
        layer.add(fade, forKey: "fade")
    }
}
#endif
