import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Pure slot plan

/// Scale and offset of one carousel slot (scale about the center, then translate).
struct CarouselSlotPose: Equatable {
    let scale: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Pose of a motion preset at a fraction of its journey.
    ///
    /// - Parameters:
    ///   - motion: Zoom/pan preset.
    ///   - fraction: Progress in 0...1 (clamped).
    init(_ motion: ArtworkMotionPreset, at fraction: Double) {
        let value = motion.value(at: fraction)
        scale = value.scale
        x = value.x
        y = value.y
    }

    /// Layer transform about a center anchor; matches `CarouselMotionEffect`.
    ///
    /// A point `q` relative to the anchor maps to `scale · q + (x, y)`.
    var transform: CATransform3D {
        CATransform3DConcat(
            CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(x, y, 0)
        )
    }
}

/// What one carousel slot shows and animates at an instant, derived from the
/// shared timestamps so every mirror and every re-sync joins in step.
///
/// Pure and platform-independent; the iOS Core Animation view applies it.
struct CarouselSlotPlan: Equatable {
    /// A running linear zoom/pan.
    struct Motion: Equatable {
        let preset: ArtworkMotionPreset
        let from: CarouselSlotPose
        let to: CarouselSlotPose
        let duration: TimeInterval
        /// Seconds since the motion began (negative when it starts later).
        let elapsed: TimeInterval
    }

    /// A running fade-in of the top slot.
    struct Fade: Equatable {
        let duration: TimeInterval
        /// Seconds since the fade began (negative when it starts later).
        let elapsed: TimeInterval
    }

    /// Length of one zoom/pan journey (`ArtworkTransitionSchedule.motion`).
    static let motionDuration: TimeInterval = 6
    /// Length of one crossfade (`ArtworkTransitionSchedule.fade`).
    static let fadeDuration: TimeInterval = 1
    /// Frame-rate ceiling for the drift and crossfade. The pan moves well under a
    /// point per frame at 30 fps, so ProMotion rates add GPU work but no visible
    /// smoothness to a decorative layer under Liquid Glass.
    static let preferredFramesPerSecond: Float = 30

    /// Pose at the planning instant (the resting value when nothing runs).
    let pose: CarouselSlotPose
    /// Opacity at the planning instant.
    let opacity: Double
    /// Zoom/pan to run, if any.
    let motion: Motion?
    /// Fade-in to run, if any.
    let fade: Fade?

    /// Plan a slot from shared timestamps.
    ///
    /// - Parameters:
    ///   - layer: Slot timing from the shared backdrop state.
    ///   - isActive: Whether this is the top (fading-in) slot.
    ///   - animate: Whether the owning page is on screen and may animate.
    ///   - now: Planning instant.
    init(layer: ArtworkBackdropState.Layer, isActive: Bool, animate: Bool, now: Date) {
        let fraction = layer.fraction(at: now)
        pose = CarouselSlotPose(layer.motion, at: fraction)
        if animate, layer.moving, let start = layer.motionStart, fraction < 1 {
            motion = Motion(
                preset: layer.motion,
                from: CarouselSlotPose(layer.motion, at: 0),
                to: CarouselSlotPose(layer.motion, at: 1),
                duration: Self.motionDuration,
                elapsed: now.timeIntervalSince(start)
            )
        } else {
            motion = nil
        }
        guard isActive else {
            opacity = 1
            fade = nil
            return
        }
        opacity = layer.fadeOpacity(at: now)
        if animate, let start = layer.fadeStart,
           now.timeIntervalSince(start) < Self.fadeDuration {
            fade = Fade(duration: Self.fadeDuration, elapsed: now.timeIntervalSince(start))
        } else {
            fade = nil
        }
    }

    /// Whether any animation runs (otherwise the slot is a still image).
    var isAnimating: Bool { motion != nil || fade != nil }

    /// Evenly spaced progress samples, one per frame at `preferredFramesPerSecond`.
    ///
    /// Played as discrete keyframes, the layer's value changes at most that often
    /// even where the frame-rate range is not honoured (60 Hz displays, Simulator),
    /// so the render server can skip recomposition between steps.
    ///
    /// - Parameter duration: Animation length in seconds.
    /// - Returns: Fractions from 0 to 1 inclusive (at least two).
    static func keyframeFractions(duration: TimeInterval) -> [Double] {
        let steps = max(1, Int((duration * Double(preferredFramesPerSecond)).rounded()))
        return (0...steps).map { Double($0) / Double(steps) }
    }

    /// Fade-in opacities on the backdrop's cubic ease-in-out (`BackdropEasing.inOut`).
    ///
    /// - Parameter duration: Fade length in seconds.
    /// - Returns: Opacities from 0 to 1, one per keyframe.
    static func fadeKeyframes(duration: TimeInterval) -> [Double] {
        keyframeFractions(duration: duration).map(BackdropEasing.inOut)
    }

    /// Linear zoom/pan poses for a motion preset, one per keyframe.
    ///
    /// - Parameters:
    ///   - motion: Zoom/pan preset.
    ///   - duration: Motion length in seconds.
    /// - Returns: Poses from the start to the end of the journey.
    static func motionKeyframes(
        _ motion: ArtworkMotionPreset, duration: TimeInterval
    ) -> [CarouselSlotPose] {
        keyframeFractions(duration: duration).map { CarouselSlotPose(motion, at: $0) }
    }
}

/// Inputs that require re-planning a slot; anything else leaves running
/// animations untouched.
struct CarouselSlotKey: Equatable {
    let image: ObjectIdentifier
    let motion: ArtworkMotionPreset
    let moving: Bool
    let motionStart: Date?
    let motionFraction: Double
    let fadeStart: Date?
    let isActive: Bool
    let animate: Bool

    /// Key a slot's timing.
    ///
    /// - Parameters:
    ///   - image: Decoded cover.
    ///   - layer: Slot timing.
    ///   - isActive: Whether this is the top slot.
    ///   - animate: Whether the owning page may animate.
    init(image: CGImage, layer: ArtworkBackdropState.Layer, isActive: Bool, animate: Bool) {
        self.image = ObjectIdentifier(image)
        motion = layer.motion
        moving = layer.moving
        motionStart = layer.motionStart
        motionFraction = layer.motionFraction
        fadeStart = layer.fadeStart
        self.isActive = isActive
        self.animate = animate
    }
}

// MARK: - Core Animation slot

#if os(iOS)
/// Platform view hosting Core Animation layers (carousel slots, Shop pulses, marquees).
typealias PlatformLayerHostView = UIView
#elseif os(macOS)
/// Platform view hosting Core Animation layers (carousel slots, Shop pulses, marquees).
typealias PlatformLayerHostView = NSView
#endif

/// One carousel slot rendered by Core Animation instead of SwiftUI.
///
/// A SwiftUI `GeometryEffect` driven from the app's display link costs a SwiftUI
/// graph update in the app for every frame of the never-ending zoom/pan and, with
/// ProMotion, up to 120 Hz of full-screen recomposition and Liquid Glass re-sampling
/// (issue #28 on iPhone; on the Mac it was about half of the Songs page's idle CPU,
/// see `.agents/platforms/apple/architecture.md`, Performance).
/// Here the motion and crossfade are discrete `CAKeyframeAnimation`s sampled at
/// `CarouselSlotPlan.preferredFramesPerSecond`, which the render server plays
/// without waking the app, with a matching frame-rate range.
struct CarouselSlotLayer {
    let image: CGImage
    let layer: ArtworkBackdropState.Layer
    let isActive: Bool
    let lightness: Double
    let animate: Bool
}

#if os(iOS)
extension CarouselSlotLayer: UIViewRepresentable {
    /// Create the hosting view.
    ///
    /// - Parameter context: Representable context.
    /// - Returns: An empty slot view, configured in `updateUIView`.
    func makeUIView(context: Context) -> CarouselSlotView {
        CarouselSlotView()
    }

    /// Apply new inputs; re-plans animations only when timing changed.
    ///
    /// - Parameters:
    ///   - view: Slot view.
    ///   - context: Representable context.
    func updateUIView(_ view: CarouselSlotView, context: Context) {
        view.apply(image: image, layer: layer, isActive: isActive,
                   lightness: lightness, animate: animate)
    }
}
#elseif os(macOS)
extension CarouselSlotLayer: NSViewRepresentable {
    /// Create the hosting view.
    ///
    /// - Parameter context: Representable context.
    /// - Returns: An empty slot view, configured in `updateNSView`.
    func makeNSView(context: Context) -> CarouselSlotView {
        CarouselSlotView()
    }

    /// Apply new inputs; re-plans animations only when timing changed.
    ///
    /// - Parameters:
    ///   - view: Slot view.
    ///   - context: Representable context.
    func updateNSView(_ view: CarouselSlotView, context: Context) {
        view.apply(image: image, layer: layer, isActive: isActive,
                   lightness: lightness, animate: animate)
    }
}
#endif

/// Platform host of one slot: the cover (aspect-fill, transformed) and a static
/// black dimming layer above it, equivalent to SwiftUI's gray `colorMultiply`
/// over opaque art.
final class CarouselSlotView: PlatformLayerHostView {
    /// Faded container (the view's own layer is left to SwiftUI).
    private let fadeLayer = CALayer()
    private let imageLayer = CALayer()
    private let dimLayer = CALayer()
    private var image: CGImage?
    #if os(macOS)
    private var appliedLightness: Double?
    #endif
    private var key: CarouselSlotKey?
    private var timing: ArtworkBackdropState.Layer?
    private var active = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageLayer.contentsGravity = .resizeAspectFill
        dimLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        fadeLayer.addSublayer(imageLayer)
        fadeLayer.addSublayer(dimLayer)
        #if os(iOS)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        layer.addSublayer(fadeLayer)
        #elseif os(macOS)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = true
        layer?.addSublayer(fadeLayer)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Layout

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSlot()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The render server may drop animations while detached; rejoin the clock.
        if window != nil { replan() }
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        layoutSlot()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The render server may drop animations while detached; rejoin the clock.
        if window != nil { replan() }
    }

    /// Decorative: never a click target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Size the layers to the view without disturbing a running transform.
    private func layoutSlot() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Bounds + position (not frame) so the running transform stays valid.
        imageLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        fadeLayer.frame = bounds
        dimLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: - Configuration

    /// Show a slot and (re)start its animations when its timing changed.
    ///
    /// - Parameters:
    ///   - image: Decoded cover.
    ///   - layer: Slot timing.
    ///   - isActive: Whether this is the top (fading-in) slot.
    ///   - lightness: Remaining brightness after dimming.
    ///   - animate: Whether the owning page may animate.
    func apply(
        image: CGImage, layer: ArtworkBackdropState.Layer, isActive: Bool,
        lightness: Double, animate: Bool
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        #if os(macOS)
        // AppKit composites the black dimming layer so that it reads about twice as
        // bright as SwiftUI's `colorMultiply` (measured on the Songs page), so the
        // Mac multiplies the pixels once per cover instead.
        if self.image !== image || appliedLightness != lightness {
            self.image = image
            appliedLightness = lightness
            imageLayer.contents = DimmedArtwork.image(image, lightness: lightness)
        }
        if dimLayer.opacity != 0 { dimLayer.opacity = 0 }
        #else
        if self.image !== image {
            self.image = image
            imageLayer.contents = image
        }
        let dim = Float(max(0, min(1, 1 - lightness)))
        if dimLayer.opacity != dim { dimLayer.opacity = dim }
        #endif
        CATransaction.commit()
        let next = CarouselSlotKey(image: image, layer: layer, isActive: isActive, animate: animate)
        timing = layer
        active = isActive
        guard next != key else { return }
        key = next
        replan()
    }

    /// Jump to the shared clock's current values, then let Core Animation play
    /// the remainder.
    private func replan() {
        guard let timing, let key else { return }
        let plan = CarouselSlotPlan(
            layer: timing, isActive: active, animate: key.animate && window != nil, now: Date()
        )
        let mediaNow = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.removeAllAnimations()
        fadeLayer.removeAllAnimations()
        if let motion = plan.motion {
            imageLayer.transform = motion.to.transform
            let animation = CAKeyframeAnimation(keyPath: "transform")
            animation.values = CarouselSlotPlan.motionKeyframes(
                motion.preset, duration: motion.duration
            ).map { NSValue(caTransform3D: $0.transform) }
            Self.schedule(
                animation, duration: motion.duration, elapsed: motion.elapsed, at: mediaNow
            )
            imageLayer.add(animation, forKey: "motion")
        } else {
            imageLayer.transform = plan.pose.transform
        }
        if let fade = plan.fade {
            fadeLayer.opacity = 1
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = CarouselSlotPlan.fadeKeyframes(duration: fade.duration)
                .map { NSNumber(value: $0) }
            Self.schedule(
                animation, duration: fade.duration, elapsed: fade.elapsed, at: mediaNow
            )
            fadeLayer.add(animation, forKey: "fade")
        } else {
            fadeLayer.opacity = Float(plan.opacity)
        }
        CATransaction.commit()
    }

    /// Play pre-sampled keyframes as discrete steps on the shared clock, capped
    /// at `CarouselSlotPlan.preferredFramesPerSecond` (ProMotion would otherwise
    /// run a decorative layer at 120 Hz).
    ///
    /// - Parameters:
    ///   - animation: Keyframe animation with its values set.
    ///   - duration: Full animation length in seconds.
    ///   - elapsed: Seconds already played (negative to start later).
    ///   - mediaNow: Current `CACurrentMediaTime()`.
    private static func schedule(
        _ animation: CAKeyframeAnimation, duration: TimeInterval,
        elapsed: TimeInterval, at mediaNow: CFTimeInterval
    ) {
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.beginTime = mediaNow - elapsed
        animation.fillMode = .backwards
        let fps = CarouselSlotPlan.preferredFramesPerSecond
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: 15, maximum: fps, preferred: fps
        )
    }
}

#if os(macOS)
// MARK: - Pre-dimmed artwork (macOS)

/// Covers multiplied by the backdrop's gray once, shared by every mirror.
///
/// Exactly SwiftUI's `colorMultiply(gray)` over opaque art, computed once per cover
/// (every five seconds at most) instead of per frame.
@MainActor
enum DimmedArtwork {
    private struct Entry {
        let source: CGImage
        let lightness: Double
        let dimmed: CGImage
    }

    /// Most recent results (the visible cover, the standby one and a fading one).
    private static var entries: [Entry] = []
    private static let capacity = 4

    /// The cover with every channel multiplied by `lightness`.
    ///
    /// - Parameters:
    ///   - source: Decoded, bounded cover.
    ///   - lightness: Remaining brightness in 0...1.
    /// - Returns: The dimmed copy (the source itself when nothing dims or drawing fails).
    static func image(_ source: CGImage, lightness: Double) -> CGImage {
        guard lightness < 1 else { return source }
        if let hit = entries.first(where: { $0.source === source && $0.lightness == lightness }) {
            return hit.dimmed
        }
        guard let dimmed = render(source, lightness: lightness) else { return source }
        entries.insert(Entry(source: source, lightness: lightness, dimmed: dimmed), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
        return dimmed
    }

    /// Draw the cover, then multiply it by an opaque gray.
    ///
    /// - Parameters:
    ///   - source: Cover.
    ///   - lightness: Gray level.
    /// - Returns: The multiplied bitmap, or nil when no context could be made.
    nonisolated static func render(_ source: CGImage, lightness: Double) -> CGImage? {
        let width = source.width, height = source.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(source, in: rect)
        context.setBlendMode(.multiply)
        context.setFillColor(CGColor(srgbRed: lightness, green: lightness, blue: lightness, alpha: 1))
        context.fill(rect)
        return context.makeImage()
    }
}
#endif
