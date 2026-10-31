#if os(iOS)
import QuartzCore
import UIKit

// MARK: - Scroll cost driver

/// Scrolls the front scroll view by itself for a fixed time and reports what that cost.
///
/// The scroll is a `CADisplayLink` setting the content offset each frame, so none of the cost is an XCUITest swipe or the
/// accessibility snapshot it asks for, and it needs no SwiftUI view or UIKit controller: it finds the scroll view in the
/// key window, so the same code measures the SwiftUI app and the UIKit port. The idle run (same length, no motion) is the
/// floor to subtract.
@MainActor
final class ScrollCostDriver {
    /// The largest top inset any run saw, carried to the next run (which may start with the large title already collapsed).
    private var restingTop: CGFloat = 0
    private var link: CADisplayLink?
    private var target: DisplayLinkTarget?
    private let config: PerfConfig

    /// Creates a driver.
    ///
    /// - Parameter config: Run length, speed and axis.
    init(config: PerfConfig) { self.config = config }

    /// Runs one measurement.
    ///
    /// - Parameter scrolling: Drag the front scroll view, or wait without touching anything.
    /// - Returns: The cost summary line, or nil when scrolling was asked for and no scroll view is on screen.
    func run(scrolling: Bool) async -> String? {
        var scrollView: UIScrollView?
        if scrolling {
            scrollView = Self.frontScrollView(horizontal: config.horizontal)
            guard scrollView != nil else { return nil }
        }
        let meter = MainThreadCostMeter()
        let end = ContinuousClock.now + .seconds(config.seconds)
        // Let the previous turn settle before counting.
        try? await Task.sleep(for: .milliseconds(300))
        meter.begin()
        let pacer = FramePacer()
        pacer.begin()
        let wallStart = Date().timeIntervalSince1970
        var distance = 0.0
        if let scrollView {
            let mover = Mover(scrollView: scrollView, speed: config.speed, horizontal: config.horizontal)
            mover.restingTop = restingTop
            start(mover)
            try? await Task.sleep(until: end, clock: .continuous)
            stop()
            restingTop = mover.restingTop
            distance = mover.travelled
        } else {
            try? await Task.sleep(until: end, clock: .continuous)
        }
        pacer.finish()
        let wallEnd = Date().timeIntervalSince1970
        var report = meter.finish()
        report.travelledPoints = distance
        // The wall-clock window lets the host's GPU and render-server samples (`tools/perf_sampler.py`) be matched to this run.
        report.note = pacer.summary
            + " t0=\(String(format: "%.3f", wallStart)) t1=\(String(format: "%.3f", wallEnd))"
        return report.summary
    }

    private func start(_ mover: Mover) {
        let target = DisplayLinkTarget(mover: mover)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        target = nil
    }

    // MARK: Finding the page

    /// The key window of the foreground scene.
    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
        return scene.keyWindow ?? scene.windows.first
    }

    /// The visible scroll view that covers the most of the front-most presented screen.
    ///
    /// - Parameter horizontal: Look for a sideways carousel or rail instead of a vertical page.
    /// - Returns: The scroll view, or nil when none qualifies.
    static func frontScrollView(horizontal: Bool = false) -> UIScrollView? {
        guard let window = keyWindow() else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        let root: UIView = controller?.view ?? window
        var best: (view: UIScrollView, area: CGFloat)?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01, scroll.window != nil else { continue }
            let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            if horizontal {
                // A carousel or rail: wider content than the view, and not the page.
                guard visible.width > 200, visible.height > 20,
                      scroll.contentSize.width > scroll.bounds.width + 1, scroll.contentSize.height <= scroll.bounds.height + 1
                else { continue }
            } else {
                guard visible.width > 200, visible.height > 200 else { continue }
                guard scroll.contentSize.height > scroll.bounds.height + 1 else { continue }
            }
            let area = visible.width * visible.height
            if best == nil || area > best!.area { best = (scroll, area) }
        }
        return best?.view
    }

    /// Every scroll view in the key window with the facts ``frontScrollView(horizontal:)`` judges, for a run that finds none.
    static func describeScrollViews() -> String {
        guard let window = keyWindow() else { return "no window" }
        var found: [String] = []
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView else { continue }
            let frame = scroll.convert(scroll.bounds, to: window)
            found.append("\(type(of: scroll)) \(Int(frame.width))x\(Int(frame.height)) content=\(Int(scroll.contentSize.height)) alpha=\(scroll.alpha) hidden=\(scroll.isHidden)")
        }
        let presented = window.rootViewController?.presentedViewController.map { "\(type(of: $0))" } ?? "none"
        return "presented=\(presented) " + found.joined(separator: "; ")
    }

    // MARK: Mover

    /// Moves a scroll view up and down at a steady speed, one step per frame.
    @MainActor
    final class Mover {
        let scrollView: UIScrollView
        let speed: Double
        let horizontal: Bool
        private(set) var travelled = 0.0
        private var direction = 1.0
        private var last: CFTimeInterval?
        var restingTop: CGFloat = 0

        init(scrollView: UIScrollView, speed: Double, horizontal: Bool = false) {
            self.scrollView = scrollView
            self.speed = speed
            self.horizontal = horizontal
        }

        func step(_ link: CADisplayLink) {
            defer { last = link.timestamp }
            guard let last else { return }
            let delta = min(link.timestamp - last, 0.1) * speed
            let inset = scrollView.adjustedContentInset
            if horizontal {
                let start = -inset.left
                let end = max(start, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
                var x = scrollView.contentOffset.x + direction * delta
                if x >= end { x = end; direction = -1 } else if x <= start { x = start; direction = 1 }
                travelled += delta
                scrollView.setContentOffset(CGPoint(x: x, y: scrollView.contentOffset.y), animated: false)
                return
            }
            // The page's real top is the largest top inset seen (the large title expanded). The scroll goes back to it every
            // pass, so the title collapses and expands each pass like a hand's flick does.
            restingTop = max(restingTop, inset.top)
            let top = -restingTop
            let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            var y = scrollView.contentOffset.y + direction * delta
            if y >= bottom { y = bottom; direction = -1 } else if y <= top { y = top; direction = 1 }
            travelled += delta
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
        }
    }

    private final class DisplayLinkTarget: NSObject {
        let mover: Mover
        init(mover: Mover) { self.mover = mover }
        @MainActor @objc func tick(_ link: CADisplayLink) { mover.step(link) }
    }
}
#endif
