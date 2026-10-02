import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Core Animation marquee track

/// The scrolling two-copy track of a ``MarqueeText``, played by Core Animation.
///
/// The track is rendered once into a bitmap (`ImageRenderer`, at the display scale,
/// with the marquee's own environment so font and colour match) and scrolled by a
/// repeating keyframe animation on the render server. The former `phaseAnimator`
/// over an `offset` re-rendered the whole window's SwiftUI graph every display frame
/// for as long as any marquee scrolled: about a fifth of a core on the Mac Songs page
/// for a few overflowing titles. One cycle keeps the web's timing: hold
/// ``MarqueeTiming/dwellFraction``, scroll linearly by `distance`, hold, jump back.
struct MarqueeTrackLayer {
    /// Track content (two copies of the text, `fixedSize`), drawn into the bitmap.
    let track: AnyView
    /// Restart and re-render identity (text, font, distance, scale, …).
    let renderKey: AnyHashable
    /// Points scrolled per cycle.
    let distance: CGFloat
    /// Seconds per cycle.
    let cycleDuration: Double

    /// Keyframe times of one cycle: hold, scroll, hold, jump back.
    static var keyTimes: [Double] {
        [0, MarqueeTiming.dwellFraction, 1 - MarqueeTiming.dwellFraction, 1]
    }

    /// Horizontal offsets at ``keyTimes``.
    ///
    /// - Parameter distance: Points scrolled per cycle.
    /// - Returns: Offsets from the rest position.
    static func offsets(distance: CGFloat) -> [Double] {
        [0, 0, -Double(distance), -Double(distance)]
    }

    /// Draw the track at the environment's display scale.
    ///
    /// - Parameter environment: The marquee's environment (font, colour, scale).
    /// - Returns: The bitmap and its size in points, or nil when rendering failed.
    @MainActor
    func render(in environment: EnvironmentValues) -> (image: CGImage, size: CGSize)? {
        let renderer = ImageRenderer(content: track.environment(\.self, environment))
        renderer.scale = environment.displayScale
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        let scale = max(environment.displayScale, 1)
        return (image, CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
    }
}

#if os(iOS)
extension MarqueeTrackLayer: UIViewRepresentable {
    func makeUIView(context: Context) -> MarqueeTrackView { MarqueeTrackView() }

    func updateUIView(_ view: MarqueeTrackView, context: Context) {
        view.apply(self, environment: context.environment)
    }
}
#elseif os(macOS)
extension MarqueeTrackLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> MarqueeTrackView { MarqueeTrackView() }

    func updateNSView(_ view: MarqueeTrackView, context: Context) {
        view.apply(self, environment: context.environment)
    }
}
#endif

/// Clipping host whose single sublayer holds the track bitmap at the leading edge,
/// vertically centred.
final class MarqueeTrackView: PlatformLayerHostView {
    private let trackLayer = CALayer()
    private var renderKey: AnyHashable?
    private var trackSize: CGSize = .zero
    private var distance: CGFloat = 0
    private var cycleDuration: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackLayer.contentsGravity = .resize
        #if os(iOS)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        layer.addSublayer(trackLayer)
        #elseif os(macOS)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = true
        layer?.addSublayer(trackLayer)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTrack()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { restart() }
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        layoutTrack()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { restart() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Re-render and restart only when the track itself changed.
    ///
    /// - Parameters:
    ///   - track: Representable inputs.
    ///   - environment: The marquee's environment.
    func apply(_ track: MarqueeTrackLayer, environment: EnvironmentValues) {
        guard track.renderKey != renderKey else { return }
        renderKey = track.renderKey
        distance = track.distance
        cycleDuration = track.cycleDuration
        let rendered = track.render(in: environment)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.contents = rendered?.image
        trackSize = rendered?.size ?? .zero
        CATransaction.commit()
        layoutTrack()
        restart()
    }

    private func layoutTrack() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Bounds + position so the running translation stays valid.
        trackLayer.bounds = CGRect(origin: .zero, size: trackSize)
        trackLayer.position = CGPoint(x: trackSize.width / 2, y: bounds.midY)
        CATransaction.commit()
    }

    /// Start one loop from rest now (as the web restarts its CSS animation on mount).
    private func restart() {
        trackLayer.removeAnimation(forKey: "marquee")
        guard window != nil, distance > 0, cycleDuration > 0 else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = MarqueeTrackLayer.offsets(distance: distance).map { NSNumber(value: $0) }
        animation.keyTimes = MarqueeTrackLayer.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = cycleDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = CACurrentMediaTime()
        trackLayer.add(animation, forKey: "marquee")
    }
}
