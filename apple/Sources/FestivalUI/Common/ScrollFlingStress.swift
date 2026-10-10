import Foundation
import QuartzCore
#if os(iOS)
import UIKit
#endif

// MARK: - Fling stress pass (Debug)

/// Debug-only fast-flick scroll pass for any page (issue #553), the counterpart of
/// ``PageScrollStress`` that moves the page the way a person's flick does.
///
/// With `FST_DEBUG_FLING_STRESS=1` the app waits ``initialDelay`` seconds (live data has
/// loaded by then), takes the largest visible vertical scroll view in the key window and
/// flings it: each fling starts at ``velocity`` and decelerates at UIKit's normal rate,
/// one display frame at a time, down until the end of the content and back up, for
/// ``rounds`` rounds. Driving the scroll view's content offset per frame is what UIKit's
/// own deceleration does, so rows are built and chrome reacts exactly as under a finger.
///
/// Every flinging frame is tallied (``FrameBudgetTally``): the display interval (late
/// frames are dropped frames) and the main-thread CPU spent since the previous frame,
/// against the 120 Hz (8.3 ms) and 60 Hz budgets. The pass records the
/// ``MainThreadStallMonitor`` start and end marks the other passes share and writes the
/// tally as `fling.*` peaks, so
/// `tools/apple_perf.py ipad --device iphone27 --fling [--tab …|--route …]` reports it.
enum ScrollFlingStress {
    /// Environment key that starts the pass.
    static let environmentKey = "FST_DEBUG_FLING_STRESS"
    /// Seconds after launch before the first fling; `FST_DEBUG_FLING_DELAY` overrides it.
    static let initialDelay: Double = 14
    /// Down-and-up rounds.
    static let rounds = 2
    /// Most flings per direction in one round (long lists never reach their end).
    static let flingsPerDirection = 8
    /// Starting speed of every fling, in points per second: a fast flick.
    static let velocity: Double = 5000
    /// A fling ends below this speed (the slow tail builds no new rows).
    static let stopVelocity: Double = 300
    /// UIKit's normal deceleration (`UIScrollView.DecelerationRate.normal`), per ms.
    static let decelerationPerMillisecond: Double = 0.998
    /// Seconds between flings.
    static let pause: Double = 0.25

    /// True when the launch environment asks for a pass.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    /// The delay before the first fling.
    static var delay: Double {
        ProcessInfo.processInfo.environment["FST_DEBUG_FLING_DELAY"].flatMap(Double.init) ?? initialDelay
    }

    /// One frame of a fling: the new offset and speed after `seconds`, clamped to the
    /// scrollable range.
    ///
    /// - Parameters:
    ///   - offset: Current content offset.
    ///   - velocity: Current speed in points per second (positive scrolls down).
    ///   - seconds: Time since the previous frame.
    ///   - range: The scrollable offsets.
    /// - Returns: The next offset and speed, and whether the fling has ended (slow enough
    ///   or at an end of the content).
    static func step(
        offset: Double, velocity: Double, seconds: Double, range: ClosedRange<Double>
    ) -> (offset: Double, velocity: Double, done: Bool) {
        guard seconds.isFinite, seconds > 0, offset.isFinite, velocity.isFinite else {
            return (offset, 0, true)
        }
        let next = offset + velocity * seconds
        let clamped = min(max(next, range.lowerBound), range.upperBound)
        let speed = velocity * pow(decelerationPerMillisecond, seconds * 1000)
        let done = clamped != next || abs(speed) < stopVelocity
        return (clamped, done ? 0 : speed, done)
    }
}

// MARK: - Frame budget tally

/// Per-frame main-thread cost over a scroll pass: pure, so it is unit-tested
/// (`ScrollFlingStressTests`).
struct FrameBudgetTally: Equatable {
    /// The 120 Hz ProMotion frame budget, in milliseconds.
    static let promotionBudgetMs = 1000.0 / 120
    /// The 60 Hz frame budget, in milliseconds.
    static let standardBudgetMs = 1000.0 / 60

    /// Frames tallied.
    private(set) var frames = 0
    /// Frames whose display interval exceeded 1.5× the target (a dropped frame).
    private(set) var late = 0
    /// Display time lost to late frames (interval beyond the target), in milliseconds.
    private(set) var hitchMs = 0.0
    /// Frames whose main-thread work exceeded the 120 Hz budget.
    private(set) var overPromotion = 0
    /// Frames whose main-thread work exceeded the 60 Hz budget.
    private(set) var overStandard = 0
    /// Total main-thread work, in milliseconds.
    private(set) var workMs = 0.0
    /// Longest display interval, in milliseconds.
    private(set) var worstIntervalMs = 0.0
    /// Most main-thread work in one frame, in milliseconds.
    private(set) var worstWorkMs = 0.0
    /// Wall time tallied, in milliseconds.
    private(set) var elapsedMs = 0.0

    /// Tally one frame.
    ///
    /// - Parameters:
    ///   - intervalMs: Time since the previous display callback.
    ///   - targetMs: The display's frame duration.
    ///   - workMs: Main-thread CPU spent since the previous callback.
    mutating func record(intervalMs: Double, targetMs: Double, workMs: Double) {
        guard intervalMs.isFinite, targetMs.isFinite, targetMs > 0, workMs.isFinite else { return }
        frames += 1
        elapsedMs += intervalMs
        if intervalMs > targetMs * 1.5 {
            late += 1
            hitchMs += intervalMs - targetMs
        }
        self.workMs += workMs
        if workMs > Self.promotionBudgetMs { overPromotion += 1 }
        if workMs > Self.standardBudgetMs { overStandard += 1 }
        worstIntervalMs = max(worstIntervalMs, intervalMs)
        worstWorkMs = max(worstWorkMs, workMs)
    }

    /// Apple's hitch-time ratio: milliseconds lost to late frames per second of scrolling.
    var hitchRatio: Double { elapsedMs > 0 ? hitchMs / (elapsedMs / 1000) : 0 }

    /// Mean main-thread work per frame, in milliseconds.
    var meanWorkMs: Double { frames > 0 ? workMs / Double(frames) : 0 }

    /// The tally as named values for the stall report's peaks.
    var summary: [String: Double] {
        [
            "fling.frames": Double(frames), "fling.late": Double(late),
            "fling.hitchMsPerS": hitchRatio, "fling.over8ms": Double(overPromotion),
            "fling.over16ms": Double(overStandard), "fling.meanWorkMs": meanWorkMs,
            "fling.worstWorkMs": worstWorkMs, "fling.worstIntervalMs": worstIntervalMs,
        ]
    }
}

#if DEBUG && os(iOS)
// MARK: - Runner

/// Drives ``ScrollFlingStress`` on the key window's main scroll view with a display link.
@MainActor
final class ScrollFlingStressRunner: NSObject {
    private static var running: ScrollFlingStressRunner?

    private var link: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var tally = FrameBudgetTally()
    private var lastTimestamp: CFTimeInterval = 0
    private var lastCPU: Double = 0
    private var velocity: Double = 0
    private var direction: Double = 1
    private var flingsThisDirection = 0
    private var round = 0
    private var pausedUntil: CFTimeInterval = 0

    /// Start the pass once per process (no-op unless requested).
    static func startIfRequested() {
        guard ScrollFlingStress.isRequested, running == nil else { return }
        let runner = ScrollFlingStressRunner()
        running = runner
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ScrollFlingStress.delay))
            runner.begin()
        }
    }

    private func begin() {
        MainThreadStallMonitor.count(PageScrollStress.startCounter)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        startFling()
    }

    private func finish() {
        link?.invalidate()
        link = nil
        for (name, value) in tally.summary { MainThreadStallMonitor.peak(name, value) }
        MainThreadStallMonitor.count(PageScrollStress.endCounter)
    }

    private func startFling() {
        scrollView = scrollView?.window != nil ? scrollView : Self.mainScrollView()
        velocity = ScrollFlingStress.velocity * direction
        lastTimestamp = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let cpu = Self.threadCPU()
        defer {
            lastTimestamp = now
            lastCPU = cpu
        }
        if pausedUntil > 0 {
            guard now >= pausedUntil else { return }
            pausedUntil = 0
            startFling()
            return
        }
        guard let scrollView else { return finish() }
        let target = max(1.0 / 240, link.targetTimestamp - link.timestamp)
        if lastTimestamp > 0 {
            tally.record(
                intervalMs: (now - lastTimestamp) * 1000, targetMs: target * 1000,
                workMs: (cpu - lastCPU) * 1000
            )
        }
        let insets = scrollView.adjustedContentInset
        let range = Double(-insets.top)...Double(max(
            -insets.top, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
        ))
        let next = ScrollFlingStress.step(
            offset: Double(scrollView.contentOffset.y), velocity: velocity,
            seconds: lastTimestamp > 0 ? now - lastTimestamp : target, range: range
        )
        scrollView.contentOffset.y = CGFloat(next.offset)
        velocity = next.velocity
        guard next.done else { return }
        flingsThisDirection += 1
        let atEnd = direction > 0 ? next.offset >= range.upperBound : next.offset <= range.lowerBound
        if atEnd || flingsThisDirection >= ScrollFlingStress.flingsPerDirection {
            flingsThisDirection = 0
            if direction < 0 { round += 1 }
            direction = -direction
            if round >= ScrollFlingStress.rounds { return finish() }
        }
        pausedUntil = now + ScrollFlingStress.pause
    }

    /// The largest visible, vertically scrollable scroll view in the key window.
    private static func mainScrollView() -> UIScrollView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard let window else { return nil }
        var best: (view: UIScrollView, area: CGFloat)?
        var queue: [UIView] = [window]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            guard !view.isHidden, view.alpha > 0.01 else { continue }
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
               scroll.contentSize.height > scroll.bounds.height + 1, scroll.bounds.height > 200 {
                let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                let area = visible.isNull ? 0 : visible.width * visible.height
                if area > (best?.area ?? 0) { best = (scroll, area) }
            }
            queue.append(contentsOf: view.subviews)
        }
        return best?.view
    }

    /// CPU seconds used by the calling (main) thread.
    private static func threadCPU() -> Double {
        var time = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0 else { return 0 }
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
}
#endif
