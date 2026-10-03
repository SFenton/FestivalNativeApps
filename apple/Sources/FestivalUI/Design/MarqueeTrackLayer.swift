import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Core Animation marquee track

/// The scrolling two-copy track of an overflowing ``MarqueeText``, measured and
/// played by Core Animation.
///
/// The text is rendered once into a bitmap (`ImageRenderer`, at the display scale,
/// with the marquee's own environment so font and colour match). The platform view
/// shows two copies `distance` apart and scrolls them with a repeating keyframe
/// animation on the render server, so no SwiftUI update runs per frame or per
/// measurement. It knows both widths itself (its bounds and the bitmap), so the
/// overflow check, the distance and the sync group need no SwiftUI state. One cycle
/// keeps the web's timing: hold ``MarqueeTiming/dwellFraction``, scroll linearly by
/// `distance`, hold, jump back.
struct MarqueeTrackLayer {
    /// One copy of the text (`fixedSize`), drawn into the bitmap.
    let track: AnyView
    /// Re-render identity (text, font, scale, …).
    let renderKey: AnyHashable
    /// Minimum space between copies.
    let gap: CGFloat
    /// Seconds per cycle.
    let cycleDuration: Double
    /// Shared distance group, if inside ``SwiftUI/View/marqueeSync(gap:)``.
    let syncGroup: MarqueeSyncGroup?

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

    /// Draw the text at the environment's display scale.
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

    /// Exactly the size ``MarqueeFitLayout`` proposes (zero while the text fits).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarqueeTrackView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}
#elseif os(macOS)
extension MarqueeTrackLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> MarqueeTrackView { MarqueeTrackView() }

    func updateNSView(_ view: MarqueeTrackView, context: Context) {
        view.apply(self, environment: context.environment)
    }

    /// Exactly the size ``MarqueeFitLayout`` proposes (zero while the text fits).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeTrackView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}
#endif

// MARK: - Sync group

/// Overflowing marquees of one ``SwiftUI/View/marqueeSync(gap:)`` container.
///
/// Members register their natural text width while in a window; with two or more,
/// every member scrolls ``MarqueeTiming/syncDistance(widths:gap:)`` so they move in
/// lockstep (web `useMarqueeSync`). Plain object state: changes never invalidate a
/// SwiftUI view.
@MainActor
final class MarqueeSyncGroup {
    private struct Member {
        weak var view: MarqueeTrackView?
        var width: CGFloat
    }

    private var members: [ObjectIdentifier: Member] = [:]
    private(set) var gap: CGFloat = 28

    /// Set the container's gap.
    ///
    /// - Parameter gap: Space between copies.
    /// - Returns: This group.
    func withGap(_ gap: CGFloat) -> MarqueeSyncGroup {
        self.gap = gap
        return self
    }

    /// Shared distance, or nil while fewer than two members overflow.
    var syncDistance: CGFloat? {
        MarqueeTiming.syncDistance(widths: members.values.map(\.width), gap: gap)
    }

    /// Add or update a member, telling the others when the shared distance changes.
    ///
    /// - Parameters:
    ///   - view: The member's track view.
    ///   - width: Its natural text width.
    func register(_ view: MarqueeTrackView, width: CGFloat) {
        let before = syncDistance
        members[ObjectIdentifier(view)] = Member(view: view, width: width)
        prune()
        notifyIfChanged(from: before, except: view)
    }

    /// Remove a member (it left its window).
    ///
    /// - Parameter view: The member's track view.
    func unregister(_ view: MarqueeTrackView) {
        let before = syncDistance
        members[ObjectIdentifier(view)] = nil
        prune()
        notifyIfChanged(from: before, except: view)
    }

    private func prune() {
        members = members.filter { $0.value.view != nil }
    }

    private func notifyIfChanged(from before: CGFloat?, except sender: MarqueeTrackView) {
        guard syncDistance != before else { return }
        for member in members.values where member.view !== sender {
            member.view?.syncDistanceChanged()
        }
    }
}

// MARK: - Track view

/// Clipping host with two copies of the text bitmap on a scrolling track layer.
final class MarqueeTrackView: PlatformLayerHostView {
    private let trackLayer = CALayer()
    private let firstCopy = CALayer()
    private let secondCopy = CALayer()
    private var renderKey: AnyHashable?
    /// Inputs of the bitmap still to draw (drawn only once the track gets a size).
    private var pending: (track: MarqueeTrackLayer, environment: EnvironmentValues)?
    private var registered = false
    private var textSize: CGSize = .zero
    private var gap: CGFloat = 28
    private var cycleDuration: Double = 0
    private weak var group: MarqueeSyncGroup?
    /// What the running animation was planned for, so layout passes leave it alone.
    private var plan: Plan?

    private struct Plan: Equatable {
        let distance: CGFloat
        let cycleDuration: Double
        let renderKey: AnyHashable
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for copy in [firstCopy, secondCopy] {
            copy.contentsGravity = .resize
            trackLayer.addSublayer(copy)
        }
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
        refresh()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowChanged()
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Apply inputs; re-renders only when the text or its style changed.
    ///
    /// - Parameters:
    ///   - track: Representable inputs.
    ///   - environment: The marquee's environment.
    func apply(_ track: MarqueeTrackLayer, environment: EnvironmentValues) {
        gap = track.gap
        cycleDuration = track.cycleDuration
        if group !== track.syncGroup {
            leaveGroup()
            group = track.syncGroup
        }
        if track.renderKey != renderKey {
            renderKey = track.renderKey
            pending = (track, environment)
            plan = nil
        }
        refresh()
    }

    /// Draw the pending bitmap now that the text overflows a real width.
    private func renderIfNeeded() {
        guard let pending else { return }
        self.pending = nil
        let rendered = pending.track.render(in: pending.environment)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        firstCopy.contents = rendered?.image
        secondCopy.contents = rendered?.image
        textSize = rendered?.size ?? .zero
        CATransaction.commit()
    }

    private func joinGroup() {
        guard let group else { return }
        registered = true
        group.register(self, width: textSize.width)
    }

    private func leaveGroup() {
        guard registered else { return }
        registered = false
        group?.unregister(self)
    }

    /// The sync group's shared distance changed.
    func syncDistanceChanged() {
        refresh()
    }

    private func windowChanged() {
        plan = nil
        if window == nil {
            leaveGroup()
            trackLayer.removeAnimation(forKey: "marquee")
        } else {
            refresh()
        }
    }

    /// Lay out both copies and (re)start the loop when its plan changed.
    private func refresh() {
        // The layout gives the track a size only while the text overflows.
        let active = window != nil && bounds.width > 0
        if active { renderIfNeeded() }
        let overflowing = active
            && MarqueeTiming.overflows(textWidth: textSize.width, available: bounds.width)
        if overflowing {
            joinGroup()
        } else {
            leaveGroup()
        }
        let distance = MarqueeTiming.distance(
            textWidth: textSize.width, gap: gap, syncDistance: group?.syncDistance
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        let y = (bounds.height - textSize.height) / 2
        firstCopy.frame = CGRect(x: 0, y: y, width: textSize.width, height: textSize.height)
        secondCopy.frame = CGRect(x: distance, y: y, width: textSize.width, height: textSize.height)
        secondCopy.isHidden = !overflowing
        CATransaction.commit()
        let next = overflowing && cycleDuration > 0 && renderKey != nil
            ? Plan(distance: distance, cycleDuration: cycleDuration, renderKey: renderKey!) : nil
        guard next != plan else { return }
        plan = next
        trackLayer.removeAnimation(forKey: "marquee")
        guard let next else { return }
        // Start one loop from rest now (the web restarts its CSS animation on mount).
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = MarqueeTrackLayer.offsets(distance: next.distance).map { NSNumber(value: $0) }
        animation.keyTimes = MarqueeTrackLayer.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = next.cycleDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = CACurrentMediaTime()
        trackLayer.add(animation, forKey: "marquee")
    }
}
