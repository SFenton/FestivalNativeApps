import CoreGraphics
import Foundation
import SwiftUI
import FestivalDesign

// MARK: - Song cover model

/// One song's still album art layered above the carousel.
///
/// Mirrors the web's `BackgroundImage` (`FortniteFestivalWeb/src/components/page/BackgroundImage.tsx`):
/// the song cover fades in over the shared animated background with
/// `opacity 300ms ease` once its image is ready, and fades back out when a
/// carousel page returns. It never grows out of the tapped list tile.
struct SongOverlay: Equatable, Identifiable {
    let id = UUID()
    /// Artwork path, or empty for a song without art (brand surface).
    let raw: String
    /// Decoded, bounded cover; nil shows the opaque brand surface.
    let image: CGImage?
    /// Fade-in start instant.
    let start: Date

    /// Web `TRANSITION_MS` (300 ms) for the background image opacity.
    static let fadeDuration: TimeInterval = 0.3

    /// Fade-in opacity at a render instant.
    ///
    /// - Parameter date: Render time.
    /// - Returns: Opacity in 0...1 on the CSS `ease` curve.
    func opacity(at date: Date) -> Double {
        BackdropEasing.cssEase(date.timeIntervalSince(start) / Self.fadeDuration)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// A cover fading away (back to the carousel, or replaced by another song).
struct ExitingOverlay: Equatable {
    let overlay: SongOverlay
    let start: Date
    /// Opacity the cover had when its exit began (an interrupted fade-in exits from there).
    let from: Double

    /// Exit length in seconds (same 300 ms `ease` as the entrance).
    static let duration: TimeInterval = SongOverlay.fadeDuration

    /// Begin fading a cover out from wherever its entrance had reached.
    ///
    /// - Parameters:
    ///   - overlay: Cover leaving the screen.
    ///   - start: Exit start instant.
    init(overlay: SongOverlay, start: Date) {
        self.overlay = overlay
        self.start = start
        from = overlay.opacity(at: start)
    }

    /// Fade-out opacity at a render instant.
    ///
    /// - Parameter date: Render time.
    /// - Returns: Opacity in 0...`from`.
    func opacity(at date: Date) -> Double {
        from * (1 - BackdropEasing.cssEase(date.timeIntervalSince(start) / Self.duration))
    }
}

/// One cover layer as drawn: entering/held, or exiting.
///
/// Keyed by the cover's id, so a cover that starts exiting keeps its view
/// identity and animates on from its current opacity instead of restarting.
struct CoverLayer: Identifiable, Equatable {
    let overlay: SongOverlay
    let exit: ExitingOverlay?

    var id: UUID { overlay.id }

    /// Opacity at a render instant.
    ///
    /// - Parameter date: Render time.
    /// - Returns: Opacity in 0...1.
    func opacity(at date: Date) -> Double {
        exit?.opacity(at: date) ?? overlay.opacity(at: date)
    }

    /// Opacity this layer settles at.
    var target: Double { exit == nil ? 1 : 0 }

    /// Seconds of the running fade left at an instant (0 when settled).
    ///
    /// - Parameter date: Render time.
    /// - Returns: Remaining seconds.
    func remaining(at date: Date) -> TimeInterval {
        let start = exit?.start ?? overlay.start
        return max(0, SongOverlay.fadeDuration - date.timeIntervalSince(start))
    }

    /// Layers to draw, exiting beneath entering.
    ///
    /// - Parameters:
    ///   - overlay: Entering or held cover.
    ///   - exiting: Cover fading away.
    /// - Returns: Bottom-to-top layers.
    static func layers(overlay: SongOverlay?, exiting: ExitingOverlay?) -> [CoverLayer] {
        var result: [CoverLayer] = []
        if let exiting, exiting.overlay.id != overlay?.id {
            result.append(CoverLayer(overlay: exiting.overlay, exit: exiting))
        }
        if let overlay { result.append(CoverLayer(overlay: overlay, exit: nil)) }
        return result
    }
}

// MARK: - Canvas

/// Renders a backdrop state; every copy (one per on-screen page) draws the same pixels.
///
/// Carousel slots and song covers animate from start points derived from the
/// shared timestamps (see `CarouselSlotLayer` and `CoverLayerView`), so no body is re-evaluated per frame and a
/// page that appears mid-transition joins it in step.
struct ArtworkBackdropCanvas: View {
    let carousel: ArtworkBackdropState
    let overlay: SongOverlay?
    let exiting: ExitingOverlay?
    /// Whether the owning page is on screen and may run animations.
    let animate: Bool
    /// False for data saving or opaque accessibility presentation: brand only.
    let showsArt: Bool
    /// Black-overlay equivalent (0.7, or 0.82 with increased contrast).
    let dimming: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                BrandTokens.appBackground
                if showsArt {
                    ForEach(carousel.layers) { layer in
                        if let image = layer.image {
                            slot(image: image, layer: layer, size: size)
                                .zIndex(layer.id == carousel.active ? 1 : 0)
                        }
                    }
                    ForEach(CoverLayer.layers(overlay: overlay, exiting: exiting)) { layer in
                        CoverLayerView(
                            layer: layer, size: size, lightness: 1 - dimming, animate: animate
                        )
                    }
                    .zIndex(2)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One carousel slot. A running zoom/pan or fade plays on Core Animation (no
    /// per-frame app work, 30 fps cap). On the Mac a still slot (paused, finished or
    /// Reduce Motion) is drawn by SwiftUI instead, so `ImageRenderer` captures and
    /// hosted tests see its pixels (platform views do not render there); iOS keeps
    /// one Core Animation view throughout.
    ///
    /// - Parameters:
    ///   - image: Decoded cover.
    ///   - layer: Slot timing.
    ///   - size: Canvas size.
    /// - Returns: The slot view.
    @ViewBuilder
    private func slot(
        image: CGImage, layer: ArtworkBackdropState.Layer, size: CGSize
    ) -> some View {
        let isActive = layer.id == carousel.active
        #if os(macOS)
        let now = Date()
        if CarouselSlotPlan(layer: layer, isActive: isActive, animate: animate, now: now).isAnimating {
            animatedSlot(image: image, layer: layer, isActive: isActive, size: size)
        } else {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .colorMultiply(Self.gray(1 - dimming))
                .modifier(CarouselMotionEffect(fraction: layer.fraction(at: now), motion: layer.motion))
                .opacity(isActive ? layer.fadeOpacity(at: now) : 1)
        }
        #else
        animatedSlot(image: image, layer: layer, isActive: isActive, size: size)
        #endif
    }

    /// The Core Animation slot.
    private func animatedSlot(
        image: CGImage, layer: ArtworkBackdropState.Layer, isActive: Bool, size: CGSize
    ) -> some View {
        CarouselSlotLayer(
            image: image, layer: layer, isActive: isActive,
            lightness: 1 - dimming, animate: animate
        )
        .frame(width: size.width, height: size.height)
    }

    /// Opaque gray used to multiply (dim) opaque artwork without a translucent layer.
    ///
    /// - Parameter lightness: Remaining brightness in 0...1.
    /// - Returns: Gray multiplier color.
    static func gray(_ lightness: Double) -> Color {
        Color(.sRGB, red: lightness, green: lightness, blue: lightness, opacity: 1)
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

// MARK: - Cover layer

/// One song cover, faded by the render loop from shared timestamps.
///
/// Like `CarouselSlotLayer`: on appear and whenever the fade changes direction
/// it jumps (without animation) to the timestamp value for "now", then animates
/// the remainder on the web's `ease` curve. Only opacity animates, so a fade is
/// composited without re-running bodies, layout or a blur per frame.
struct CoverLayerView: View {
    let layer: CoverLayer
    let size: CGSize
    let lightness: Double
    let animate: Bool

    @State private var opacity: Double

    /// Start at the timestamp-derived opacity for the current instant.
    ///
    /// - Parameters:
    ///   - layer: Cover and fade timing.
    ///   - size: Canvas size.
    ///   - lightness: Dimming multiplier for art (brand surface is never dimmed).
    ///   - animate: Whether the owning page is on screen.
    init(layer: CoverLayer, size: CGSize, lightness: Double, animate: Bool) {
        self.layer = layer
        self.size = size
        self.lightness = lightness
        self.animate = animate
        _opacity = State(initialValue: layer.opacity(at: Date()))
    }

    /// Inputs that require re-synchronising with the shared clock.
    private struct Timing: Equatable {
        let exitStart: Date?
        let animate: Bool
    }

    var body: some View {
        Group {
            if let image = layer.overlay.image {
                // Drawn in a Canvas, not as an `Image` view: the hidden full-screen
                // `Image` stayed in the iPadOS accessibility tree as an unlabelled node
                // the size of the cover behind Song Detail (Increase Contrast audit,
                // "Element has no description"; Lane A11Y3/A11Y4). A Canvas exposes no
                // element for what it draws.
                Canvas { context, canvasSize in
                    context.draw(
                        Image(decorative: image, scale: 1),
                        in: Self.aspectFill(
                            CGSize(width: image.width, height: image.height), in: canvasSize
                        )
                    )
                }
                .frame(width: size.width, height: size.height)
                .colorMultiply(ArtworkBackdropCanvas.gray(lightness))
                .accessibilityHidden(true)
            } else {
                BrandTokens.appBackground
                    .frame(width: size.width, height: size.height)
            }
        }
        .opacity(opacity)
        .onAppear { sync() }
        .onChange(of: Timing(exitStart: layer.exit?.start, animate: animate)) { _, _ in sync() }
    }

    /// The rect that scales `image` to cover `bounds`, centred (`scaledToFill`).
    ///
    /// - Parameters:
    ///   - image: Image size (any unit; only the aspect ratio matters).
    ///   - bounds: Size to cover.
    /// - Returns: The image's drawing rect in `bounds` coordinates (may overhang).
    static func aspectFill(_ image: CGSize, in bounds: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: bounds) }
        let scale = max(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    /// Jump to the shared clock's current opacity, then animate the remainder.
    private func sync() {
        let now = Date()
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) { opacity = layer.opacity(at: now) }
        let left = layer.remaining(at: now)
        guard animate, left > 0 else { return }
        let target = layer.target
        // Start on the next turn so the jump above is committed first.
        Task { @MainActor in
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: left)) {
                opacity = target
            }
        }
    }
}

// MARK: - Motion reference

/// Six-second zoom/pan as a pure SwiftUI transform: draws a still Mac slot and is
/// the reference that `CarouselSlotPose.transform` (the Core Animation slot) matches.
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
