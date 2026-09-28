import CoreGraphics
import Foundation
import SwiftUI
import FestivalDesign

// MARK: - Song overlay model

/// One song's still album art layered above the carousel.
struct SongOverlay: Equatable, Identifiable {
    /// How the cover enters.
    enum Style: Equatable {
        /// Grows out of the song's list tile into the full background.
        case zoom
        /// Dissolves in with a slight settle and soft focus.
        case dissolve
        /// Opacity only (Reduce Motion).
        case plain
    }

    let id = UUID()
    /// Artwork path, or empty for a song without art (brand surface).
    let raw: String
    /// Decoded, bounded cover; nil shows the opaque brand surface.
    let image: CGImage?
    /// Global tile frame the art zooms out of (`.zoom` only).
    let origin: CGRect?
    /// Entrance start instant.
    let start: Date
    let style: Style

    /// Entrance length for a style.
    ///
    /// - Parameter style: Entrance style.
    /// - Returns: Seconds.
    static func duration(_ style: Style) -> TimeInterval {
        switch style {
        case .zoom: 0.55
        case .dissolve: 0.5
        case .plain: 0.3
        }
    }

    /// Eased entrance progress at a render instant.
    ///
    /// - Parameter date: Render time.
    /// - Returns: Progress in 0...1.
    func progress(at date: Date) -> Double {
        BackdropEasing.inOut(date.timeIntervalSince(start) / Self.duration(style))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// A cover dissolving away (back to the carousel, or replaced by another song).
struct ExitingOverlay: Equatable {
    let overlay: SongOverlay
    let start: Date

    /// Exit length in seconds.
    static let duration: TimeInterval = 0.45

    /// Eased exit progress at a render instant.
    ///
    /// - Parameter date: Render time.
    /// - Returns: Progress in 0...1.
    func progress(at date: Date) -> Double {
        BackdropEasing.inOut(date.timeIntervalSince(start) / Self.duration)
    }
}

// MARK: - Canvas

/// Renders a backdrop state; every copy (one per on-screen page) draws the same pixels.
///
/// Carousel slots animate with implicit animations whose start points are
/// derived from the shared timestamps (see `CarouselLayerView`), so no body is
/// re-evaluated per frame. Song-cover entrances/exits are short and drawn by a
/// `TimelineView` that exists only while one is running.
struct ArtworkBackdropCanvas: View {
    let carousel: ArtworkBackdropState
    let overlay: SongOverlay?
    let exiting: ExitingOverlay?
    /// Whether the owning page is on screen and may run animations.
    let animate: Bool
    /// Whether a cover transition is running (per-frame rendering needed).
    let ticking: Bool
    /// False for data saving or opaque accessibility presentation: brand only.
    let showsArt: Bool
    /// Black-overlay equivalent (0.7, or 0.82 with increased contrast).
    let dimming: Double

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .global)
            let size = geometry.size
            ZStack {
                BrandTokens.appBackground
                if showsArt {
                    ForEach(carousel.layers) { layer in
                        if let image = layer.image {
                            CarouselLayerView(
                                image: image, layer: layer,
                                isActive: layer.id == carousel.active,
                                size: size, lightness: 1 - dimming, animate: animate
                            )
                            .zIndex(layer.id == carousel.active ? 1 : 0)
                        }
                    }
                    if overlay != nil || exiting != nil {
                        TimelineView(.animation(minimumInterval: nil, paused: !ticking)) { context in
                            covers(
                                at: ticking ? context.date : .distantFuture,
                                size: size, bounds: bounds
                            )
                        }
                        .zIndex(2)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Song covers (exiting beneath entering) for one instant.
    ///
    /// - Parameters:
    ///   - date: Render time (`.distantFuture` when settled).
    ///   - size: Canvas size.
    ///   - bounds: Canvas frame in global coordinates (for tile origins).
    /// - Returns: The cover layers.
    private func covers(at date: Date, size: CGSize, bounds: CGRect) -> some View {
        ZStack {
            if let exiting, exiting.progress(at: date) < 1 {
                let q = exiting.progress(at: date)
                cover(exiting.overlay, size: size)
                    .modifier(SongBackdropPlacement(
                        progress: 1, opacity: 1 - q,
                        scale: exiting.overlay.style == .plain ? 1 : 1 + 0.04 * q,
                        blur: 0, origin: nil, size: size,
                        dimming: exiting.overlay.image == nil ? 0 : dimming
                    ))
                    .id(exiting.overlay.id)
            }
            if let overlay {
                cover(overlay, size: size)
                    .modifier(placement(
                        for: overlay, progress: overlay.progress(at: date),
                        size: size, bounds: bounds
                    ))
                    .id(overlay.id)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Undimmed, flexible cover or brand surface; placement frames and dims it.
    ///
    /// - Parameters:
    ///   - overlay: Song cover model.
    ///   - size: Canvas size.
    /// - Returns: Flexible cover view.
    @ViewBuilder
    private func cover(_ overlay: SongOverlay, size: CGSize) -> some View {
        if let image = overlay.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            BrandTokens.appBackground
        }
    }

    /// Placement for an entering cover.
    ///
    /// - Parameters:
    ///   - overlay: Song cover model.
    ///   - progress: Eased entrance progress.
    ///   - size: Canvas size.
    ///   - bounds: Canvas frame in global coordinates.
    /// - Returns: Frame, dimming and fade for this instant.
    private func placement(
        for overlay: SongOverlay, progress p: Double, size: CGSize, bounds: CGRect
    ) -> SongBackdropPlacement {
        let dim = overlay.image == nil ? 0 : dimming
        switch overlay.style {
        case .zoom:
            let origin = overlay.origin.flatMap {
                Self.localOrigin($0, in: bounds)
            }
            return SongBackdropPlacement(
                progress: origin == nil ? 1 : p, opacity: origin == nil ? p : 1,
                scale: 1, blur: 0, origin: origin, size: size, dimming: dim
            )
        case .dissolve:
            return SongBackdropPlacement(
                progress: 1, opacity: p, scale: 1.06 - 0.06 * p, blur: 10 * (1 - p),
                origin: nil, size: size, dimming: dim
            )
        case .plain:
            return SongBackdropPlacement(
                progress: 1, opacity: p, scale: 1, blur: 0,
                origin: nil, size: size, dimming: dim
            )
        }
    }

    /// Opaque gray used to multiply (dim) opaque artwork without a translucent layer.
    ///
    /// - Parameter lightness: Remaining brightness in 0...1.
    /// - Returns: Gray multiplier color.
    static func gray(_ lightness: Double) -> Color {
        Color(.sRGB, red: lightness, green: lightness, blue: lightness, opacity: 1)
    }

    /// Convert a global tile frame into canvas coordinates, if on screen.
    ///
    /// - Parameters:
    ///   - frame: Tile frame in global coordinates.
    ///   - bounds: Canvas frame in global coordinates.
    /// - Returns: Local frame, or nil when the tile is empty or off screen.
    static func localOrigin(_ frame: CGRect, in bounds: CGRect) -> CGRect? {
        guard frame.width > 1, frame.height > 1, bounds.intersects(frame) else {
            return nil
        }
        return frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
    }

    /// Longest decoded edge for a full-screen cover.
    ///
    /// - Parameters:
    ///   - size: Backdrop size in points.
    ///   - displayScale: Screen scale (capped at 2 to bound memory).
    /// - Returns: Pixel bound in 96...1024.
    static func maxPixels(for size: CGSize, displayScale: CGFloat) -> Int {
        min(1024, max(96, Int((max(size.width, size.height)
            * min(displayScale, 2)).rounded(.up))))
    }
}

// MARK: - Placement

/// Frame, dimming and fade for a song cover.
///
/// `progress` 0 draws the undimmed cover inside its list tile's rounded frame;
/// 1 fills the canvas with the dimmed cover.
struct SongBackdropPlacement: ViewModifier {
    let progress: Double
    let opacity: Double
    let scale: Double
    let blur: Double
    let origin: CGRect?
    let size: CGSize
    let dimming: Double

    /// Place the cover between its tile frame and the full canvas.
    ///
    /// - Parameter content: Flexible, undimmed cover.
    /// - Returns: Framed, dimmed and faded cover.
    func body(content: Content) -> some View {
        let frame = Self.frame(progress: progress, origin: origin, size: size)
        return content
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 10 * (1 - progress)))
            .colorMultiply(ArtworkBackdropCanvas.gray(1 - dimming * progress))
            .scaleEffect(scale)
            .blur(radius: blur, opaque: true)
            .opacity(opacity)
            .position(x: frame.midX, y: frame.midY)
    }

    /// Interpolate from the tile frame to the full canvas bounds.
    ///
    /// - Parameters:
    ///   - progress: 0 at the tile, 1 at full size.
    ///   - origin: Tile frame in canvas coordinates, if any.
    ///   - size: Canvas size.
    /// - Returns: Frame for this progress.
    static func frame(progress: Double, origin: CGRect?, size: CGSize) -> CGRect {
        let full = CGRect(origin: .zero, size: size)
        guard let origin else { return full }
        let t = CGFloat(min(max(progress, 0), 1))
        return CGRect(
            x: origin.minX + (full.minX - origin.minX) * t,
            y: origin.minY + (full.minY - origin.minY) * t,
            width: origin.width + (full.width - origin.width) * t,
            height: origin.height + (full.height - origin.height) * t
        )
    }
}

// MARK: - Carousel slot

/// One carousel slot, animated by the render loop from shared timestamps.
///
/// On appear and whenever the slot's timing changes, the view jumps (without
/// animation) to the value the timestamps give for "now", then animates the
/// remainder. Two mirrors therefore stay in step, a page that reappears
/// mid-motion continues seamlessly, and SwiftUI only interpolates animatable
/// data per frame instead of re-running view bodies.
struct CarouselLayerView: View {
    let image: CGImage
    let layer: ArtworkBackdropState.Layer
    let isActive: Bool
    let size: CGSize
    let lightness: Double
    let animate: Bool

    @State private var fraction: Double
    @State private var fade: Double

    /// Start at the timestamp-derived values for the current instant.
    ///
    /// - Parameters:
    ///   - image: Decoded cover.
    ///   - layer: Slot timing.
    ///   - isActive: Whether this is the top (fading-in) slot.
    ///   - size: Canvas size.
    ///   - lightness: Dimming multiplier.
    ///   - animate: Whether the owning page is on screen.
    init(
        image: CGImage, layer: ArtworkBackdropState.Layer, isActive: Bool,
        size: CGSize, lightness: Double, animate: Bool
    ) {
        self.image = image
        self.layer = layer
        self.isActive = isActive
        self.size = size
        self.lightness = lightness
        self.animate = animate
        let now = Date()
        _fraction = State(initialValue: layer.fraction(at: now))
        _fade = State(initialValue: layer.fadeOpacity(at: now))
    }

    /// Timing inputs that require re-synchronising with the shared clock.
    private struct Timing: Equatable {
        let motionStart: Date?
        let moving: Bool
        let motionFraction: Double
        let fadeStart: Date?
        let animate: Bool
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .colorMultiply(ArtworkBackdropCanvas.gray(lightness))
            .modifier(CarouselMotionEffect(fraction: fraction, motion: layer.motion))
            .opacity(isActive ? fade : 1)
            .onAppear { sync() }
            .onChange(of: Timing(
                motionStart: layer.motionStart, moving: layer.moving,
                motionFraction: layer.motionFraction, fadeStart: layer.fadeStart,
                animate: animate
            )) { _, _ in sync() }
    }

    /// Jump to the shared clock's current values, then animate the remainder.
    private func sync() {
        let now = Date()
        let currentFraction = layer.fraction(at: now)
        let currentFade = layer.fadeOpacity(at: now)
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            fraction = currentFraction
            fade = currentFade
        }
        guard animate else { return }
        let motionLeft = layer.moving ? (1 - currentFraction) * 6 : 0
        let fadeLeft = layer.fadeStart.map { max(0, 1 - now.timeIntervalSince($0)) } ?? 0
        guard motionLeft > 0 || fadeLeft > 0 else { return }
        // Start on the next turn so the jump above is committed first.
        Task { @MainActor in
            if motionLeft > 0 {
                withAnimation(.linear(duration: motionLeft)) { fraction = 1 }
            }
            if fadeLeft > 0 {
                withAnimation(.easeInOut(duration: fadeLeft)) { fade = 1 }
            }
        }
    }
}

/// Six-second zoom/pan as a pure transform (no layout per frame).
struct CarouselMotionEffect: GeometryEffect {
    var fraction: Double
    let motion: ArtworkMotionPreset

    nonisolated var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    /// Scale about the center, then translate.
    ///
    /// - Parameter size: Layer size.
    /// - Returns: Transform for the current fraction.
    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        let value = motion.value(at: fraction)
        let transform = CGAffineTransform(
            translationX: size.width / 2 + value.x, y: size.height / 2 + value.y
        )
        .scaledBy(x: value.scale, y: value.scale)
        .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}
