#if os(iOS)
import QuartzCore
import UIKit

// MARK: - Frame ticker

/// A display link that calls a closure each frame, and async waits on it (frame-accurate, unlike a timer).
@MainActor
final class FrameTicker {
    private var link: CADisplayLink?
    private var handler: (@MainActor (CFTimeInterval) -> Void)?

    /// Starts calling `handler` once per display frame with the frame's timestamp.
    ///
    /// - Parameter handler: Called on the main thread.
    func start(_ handler: @escaping @MainActor (CFTimeInterval) -> Void) {
        stop()
        self.handler = handler
        let link = CADisplayLink(target: Target(self), selector: #selector(Target.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops the link.
    func stop() {
        link?.invalidate()
        link = nil
        handler = nil
    }

    fileprivate func tick(_ link: CADisplayLink) { handler?(link.timestamp) }

    /// Waits for the first display frame on which `condition` holds.
    ///
    /// - Parameters:
    ///   - timeout: Seconds before giving up.
    ///   - condition: Checked once per frame.
    /// - Returns: `CACurrentMediaTime()` at the frame that satisfied it, nil on timeout.
    static func wait(timeout: Double, until condition: @escaping @MainActor () -> Bool) async -> CFTimeInterval? {
        let ticker = FrameTicker()
        let deadline = CACurrentMediaTime() + timeout
        let result: CFTimeInterval? = await withCheckedContinuation { continuation in
            var resumed = false
            ticker.start { _ in
                guard !resumed else { return }
                if condition() {
                    resumed = true
                    continuation.resume(returning: CACurrentMediaTime())
                } else if CACurrentMediaTime() > deadline {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
        ticker.stop()
        return result
    }

    private final class Target: NSObject {
        weak var ticker: FrameTicker?
        init(_ ticker: FrameTicker) { self.ticker = ticker }
        @MainActor @objc func tick(_ link: CADisplayLink) { ticker?.tick(link) }
    }
}
#endif
