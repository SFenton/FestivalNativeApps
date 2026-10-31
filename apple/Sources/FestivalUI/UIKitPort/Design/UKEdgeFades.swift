#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Gradient mask

/// A vertical alpha mask on a view's layer, built from stops in points. Mask the
/// scroll view's non-scrolling container (a mask on a `UIScrollView` itself moves with
/// its content offset). Keep it alive as long as the fade should apply.
@MainActor
final class UKEdgeFadeMask {
    /// One stop: a y offset in the masked view and the alpha there (0 hides, 1 shows).
    typealias Stop = (y: CGFloat, alpha: CGFloat)

    private let gradient = CAGradientLayer()
    private(set) weak var view: UIView?
    private var stops: [Stop] = [(0, 1)]

    /// Masks `view`.
    ///
    /// - Parameter view: The container whose content fades.
    init(view: UIView) {
        self.view = view
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.frame = view.bounds
        view.layer.mask = gradient
        apply(stops: [(0, 1)])
    }

    /// Removes the mask.
    func remove() {
        if view?.layer.mask === gradient { view?.layer.mask = nil }
    }

    /// Resizes the mask to the view; call from `layoutSubviews` / `viewDidLayoutSubviews`.
    func layout() {
        guard let view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = view.bounds
        CATransaction.commit()
        apply(stops: stops)
    }

    /// Sets the stops, ascending in y.
    ///
    /// - Parameter stops: Alpha stops; the last one extends to the bottom edge.
    func apply(stops: [Stop]) {
        self.stops = stops
        let height = max(gradient.bounds.height, 1)
        var previous: CGFloat = 0
        var locations: [NSNumber] = []
        var colors: [CGColor] = []
        for stop in stops {
            let location = min(max(stop.y / height, previous), 1)
            previous = location
            locations.append(NSNumber(value: Double(location)))
            colors.append(UIColor.black.withAlphaComponent(min(max(stop.alpha, 0), 1)).cgColor)
        }
        if previous < 1, let last = stops.last {
            locations.append(1)
            colors.append(UIColor.black.withAlphaComponent(min(max(last.alpha, 0), 1)).cgColor)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.locations = locations
        gradient.colors = colors
        CATransaction.commit()
    }
}

// MARK: - Modal top fade

/// Content under a sheet's header fades in as it scrolls (``ModalTopEdgeFadeModifier``):
/// the header area is hidden and a ramp of ``ModalTopEdgeFade/rampHeight`` below it grows
/// from clear to opaque with the scroll offset. A hard edge under Reduce Transparency or
/// increased contrast (``ScrollEdgeHardEdge``).
@MainActor
final class UKModalTopEdgeFade {
    private let mask: UKEdgeFadeMask
    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var settingsObserver: UKAccessibilityObserver?
    /// A ramp height the content asks for (`ModalTopEdgeFadeRampKey`); nil for the default.
    var rampOverride: CGFloat? { didSet { update() } }

    /// Attaches the fade.
    ///
    /// - Parameters:
    ///   - maskedView: The non-scrolling container that holds the scroll view, under the
    ///     navigation bar.
    ///   - scrollView: The scroll view that drives the ramp.
    init(maskedView: UIView, scrollView: UIScrollView) {
        mask = UKEdgeFadeMask(view: maskedView)
        self.scrollView = scrollView
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        settingsObserver = UKAccessibilityObserver { [weak self] in self?.update() }
        update()
    }

    /// Recomputes the mask; call after layout.
    func layout() {
        mask.layout()
        update()
    }

    /// Recomputes the mask from the scroll offset and the settings.
    func update() {
        guard let view = mask.view, let scrollView else { return }
        let hardEdge = UKAccessibility.hardEdge(view.traitCollection)
        let ramp = hardEdge ? 0 : (rampOverride ?? ModalTopEdgeFade.rampHeight)
        let header = ModalTopEdgeFade.headerHeight(safeAreaInset: view.safeAreaInsets.top, containerOffset: 0)
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let edge = ModalTopEdgeFade.edgeOpacity(progress: ModalTopEdgeFade.progress(scrollOffset: offset, rampHeight: ramp))
        var stops: [UKEdgeFadeMask.Stop] = [(0, 0), (header, 0)]
        if ramp > 0 {
            stops += [(header, edge), (header + ramp, 1)]
        } else {
            stops += [(header, 1)]
        }
        mask.apply(stops: stops)
    }

    /// Removes the fade.
    func remove() { mask.remove() }
}

// MARK: - Bottom chrome fade

/// Rows fade out where bottom chrome (a pager, switcher or footer) overlaps them
/// (``BottomChromeFade``): the ramp's distance follows how much content is left under
/// the last visible row (``ScrollEdgeFade/bottomDistance(lastRowOverflow:)``).
@MainActor
final class UKBottomChromeFade {
    private let mask: UKEdgeFadeMask
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var settingsObserver: UKAccessibilityObserver?
    /// Top of the bottom chrome in the masked view's coordinates; nil while there is none
    /// (nothing fades).
    var chromeTop: CGFloat? { didSet { update() } }

    /// Attaches the fade.
    ///
    /// - Parameters:
    ///   - maskedView: The non-scrolling container that holds the scroll view.
    ///   - scrollView: The scroll view that drives the ramp distance.
    init(maskedView: UIView, scrollView: UIScrollView) {
        mask = UKEdgeFadeMask(view: maskedView)
        self.scrollView = scrollView
        observations = [
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            },
        ]
        settingsObserver = UKAccessibilityObserver { [weak self] in self?.update() }
        update()
    }

    /// Recomputes the mask; call after layout.
    func layout() {
        mask.layout()
        update()
    }

    /// Recomputes the mask.
    func update() {
        guard let view = mask.view, let scrollView else { return }
        guard let chromeTop else {
            mask.apply(stops: [(0, 1)])
            return
        }
        let overflow = ScrollEdgeFade.contentOverflow(
            contentHeight: Double(scrollView.contentSize.height), offsetY: Double(scrollView.contentOffset.y),
            containerHeight: Double(scrollView.bounds.height), bottomInset: Double(scrollView.adjustedContentInset.bottom)
        )
        let distance = ScrollEdgeFade.bottomDistance(lastRowOverflow: overflow).rounded()
        let ramp = UKAccessibility.hardEdge(view.traitCollection) ? 0 : ScrollEdgeFade.ramp(distance, hardEdge: false)
        let height = Double(view.bounds.height)
        let stops = ScrollEdgeFade.bottom(height: height, obscured: height - Double(chromeTop), distance: ramp)
        mask.apply(stops: [
            (0, 1), (CGFloat(stops.fadeStart) * view.bounds.height, 1), (CGFloat(stops.fadeEnd) * view.bounds.height, 0),
        ])
    }

    /// Removes the fade.
    func remove() { mask.remove() }
}

// MARK: - Pinned header fade

/// Rows scrolling under a pinned section title or large-title bar fade in below its
/// bottom edge (``PinnedHeaderFadeMask``): clear above `edge`, a linear ramp as deep as
/// the scroll offset (up to ``PinnedHeaderEdgeFade/height``) below it, opaque after.
@MainActor
final class UKPinnedHeaderEdgeFade {
    private let mask: UKEdgeFadeMask

    /// Attaches the fade.
    ///
    /// - Parameter maskedView: The non-scrolling container that holds the list.
    init(maskedView: UIView) {
        mask = UKEdgeFadeMask(view: maskedView)
    }

    /// Recomputes the mask after layout.
    func layout() { mask.layout() }

    /// Updates the fade.
    ///
    /// - Parameters:
    ///   - edge: The pinned header's bottom edge in the masked view's coordinates; nil
    ///     draws everything.
    ///   - scrollOffset: Distance scrolled from the resting top (offset plus top inset).
    func update(edge: CGFloat?, scrollOffset: CGFloat) {
        guard let view = mask.view, let edge else {
            mask.apply(stops: [(0, 1)])
            return
        }
        let fade = PinnedHeaderEdgeFade.height(hardEdge: UKAccessibility.hardEdge(view.traitCollection))
        let depth = PinnedHeaderEdgeFade.depth(scrollOffset: scrollOffset, fade: fade)
        mask.apply(stops: [
            (0, 0), (edge, PinnedHeaderEdgeFade.opacity(at: 0)), (edge + depth, PinnedHeaderEdgeFade.opacity(at: 1)),
        ])
    }

    /// Removes the fade.
    func remove() { mask.remove() }
}
#endif
