import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Shared pulse clock

/// The one clock every Shop pulse follows.
///
/// A pulse's phase is a pure function of wall time (`timeIntervalSinceReferenceDate`
/// modulo its period), so every row, the Song Detail button and any page that
/// appears later pulse in lockstep without sharing a timer. The value curve is
/// pre-sampled once per period at ``framesPerSecond`` and handed to Core Animation as
/// a repeating discrete keyframe animation, which the render server plays without
/// waking the app: no per-row `TimelineView`, no SwiftUI update per frame.
enum ShopPulseClock {
    /// Frame-rate ceiling, as the former `TimelineView(.animation(minimumInterval: 1/30))`.
    static let framesPerSecond: Float = 30

    /// Seconds into the current cycle at an instant.
    ///
    /// - Parameters:
    ///   - period: Cycle length in seconds.
    ///   - date: Instant.
    /// - Returns: Elapsed seconds in `0..<period` (0 for a non-positive period).
    static func elapsed(period: Double, at date: Date) -> Double {
        guard period > 0 else { return 0 }
        let value = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return value < 0 ? value + period : value
    }

    /// One cycle of a value curve, sampled at ``framesPerSecond``.
    ///
    /// - Parameters:
    ///   - period: Cycle length in seconds.
    ///   - value: Value at seconds into the cycle.
    /// - Returns: Samples from the cycle start to its end inclusive (at least two).
    static func keyframes(period: Double, value: (Double) -> Double) -> [Double] {
        let steps = max(1, Int((period * Double(framesPerSecond)).rounded()))
        return (0...steps).map { value(period * Double($0) / Double(steps)) }
    }
}

// MARK: - Pulse shape

/// What a pulse layer draws.
enum ShopPulseShape: Equatable {
    /// A centred 2-point-style stroke on a continuous rounded rectangle, like
    /// SwiftUI's `RoundedRectangle(cornerRadius:style: .continuous).stroke(lineWidth:)`
    /// (half the line falls outside the frame).
    case roundedStroke(cornerRadius: CGFloat, lineWidth: CGFloat)
    /// A filled circle of the frame's shorter side, centred, like SwiftUI's `Circle().fill`.
    case disc

    /// Layer frame, corner radius and border width for a host size.
    ///
    /// - Parameter size: Host view size.
    /// - Returns: Geometry for a `CALayer` drawing this shape.
    func geometry(in size: CGSize) -> (frame: CGRect, cornerRadius: CGFloat, borderWidth: CGFloat) {
        switch self {
        case let .roundedStroke(radius, width):
            // A centred stroke's outer edge is the path offset by half the line.
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: -width / 2, dy: -width / 2)
            return (frame, radius + width / 2, width)
        case .disc:
            let side = min(size.width, size.height)
            let frame = CGRect(
                x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side
            )
            return (frame, side / 2, 0)
        }
    }
}

// MARK: - Pulse layer

/// A shape whose opacity follows ``ShopPulseClock`` on the render server.
///
/// `running == false` (Reduce Motion, inactive scene, hidden window, UI-test still
/// override) shows the static `restingOpacity`.
struct ShopPulseLayer {
    let shape: ShopPulseShape
    let color: Color
    let period: Double
    let restingOpacity: Double
    let running: Bool
    /// Opacity at seconds into a cycle.
    let opacity: (Double) -> Double
}

#if os(iOS)
extension ShopPulseLayer: UIViewRepresentable {
    func makeUIView(context: Context) -> ShopPulseView { ShopPulseView() }

    func updateUIView(_ view: ShopPulseView, context: Context) {
        view.apply(self, color: color.resolve(in: context.environment).cgColor)
    }
}
#elseif os(macOS)
extension ShopPulseLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> ShopPulseView { ShopPulseView() }

    func updateNSView(_ view: ShopPulseView, context: Context) {
        view.apply(self, color: color.resolve(in: context.environment).cgColor)
    }
}
#endif

/// Platform host of one pulse: a single `CALayer` (border or fill), never clipped,
/// never a hit-test or accessibility target.
final class ShopPulseView: PlatformLayerHostView {
    private let shapeLayer = CALayer()
    private var shape: ShopPulseShape = .disc
    private var key: Key?
    private var keyframes: [Double] = []
    private var restingOpacity: Float = 1

    /// Inputs that require re-planning the animation.
    private struct Key: Equatable {
        let period: Double
        let running: Bool
        let resting: Double
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(iOS)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = false
        layer.addSublayer(shapeLayer)
        #elseif os(macOS)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = false
        layer?.addSublayer(shapeLayer)
        #endif
        shapeLayer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutShape()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Animations can be dropped while detached (toolbar re-hosting, cell reuse).
        if window != nil { replan() }
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        layoutShape()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { replan() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Apply inputs; the running animation is only replaced when its timing changed.
    ///
    /// - Parameters:
    ///   - pulse: Representable inputs.
    ///   - color: Resolved colour.
    func apply(_ pulse: ShopPulseLayer, color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if pulse.shape != shape {
            shape = pulse.shape
            layoutShape()
        }
        switch shape {
        case .roundedStroke:
            shapeLayer.backgroundColor = nil
            shapeLayer.borderColor = color
        case .disc:
            shapeLayer.borderColor = nil
            shapeLayer.backgroundColor = color
        }
        CATransaction.commit()
        let next = Key(period: pulse.period, running: pulse.running, resting: pulse.restingOpacity)
        guard next != key else { return }
        key = next
        restingOpacity = Float(pulse.restingOpacity)
        keyframes = pulse.running
            ? ShopPulseClock.keyframes(period: pulse.period, value: pulse.opacity) : []
        replan()
    }

    private func layoutShape() {
        let geometry = shape.geometry(in: bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = geometry.frame
        shapeLayer.cornerRadius = geometry.cornerRadius
        shapeLayer.borderWidth = geometry.borderWidth
        CATransaction.commit()
    }

    /// Join the shared clock: a repeating discrete animation whose cycle starts at the
    /// clock's last period boundary.
    private func replan() {
        guard let key else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.removeAnimation(forKey: "pulse")
        guard key.running, keyframes.count > 1, window != nil else {
            shapeLayer.opacity = restingOpacity
            CATransaction.commit()
            return
        }
        shapeLayer.opacity = Float(keyframes[0])
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = keyframes.map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = key.period
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = CACurrentMediaTime()
            - ShopPulseClock.elapsed(period: key.period, at: Date())
        let fps = ShopPulseClock.framesPerSecond
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: fps, preferred: fps)
        shapeLayer.add(animation, forKey: "pulse")
        CATransaction.commit()
    }
}
