import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Shared Shop pulse clock

/// Every pulse derives its phase from wall time, so rows created at different
/// moments pulse in lockstep.
@Test func shopPulseClockPhaseIsSharedWallTime() {
    let date = Date(timeIntervalSinceReferenceDate: 1001.25)
    #expect(ShopPulseClock.elapsed(period: 2, at: date) == 1.25)
    #expect(ShopPulseClock.elapsed(period: 3, at: date) == 2.25)
    #expect(ShopPulseClock.elapsed(period: 0, at: date) == 0)
    let before = Date(timeIntervalSinceReferenceDate: -0.5)
    #expect(ShopPulseClock.elapsed(period: 2, at: before) == 1.5)
}

/// The row border keyframes reproduce the former 30 fps `TimelineView` curve.
@Test func shopPulseKeyframesSampleTheRowCurveAt30fps() {
    let frames = ShopPulseClock.keyframes(period: ShopRowPulseBorder.period) {
        ShopRowPulseBorder.opacity(at: $0, animating: true)
    }
    #expect(frames.count == 61)
    #expect(frames.first == 0)
    #expect(abs(frames[30] - ShopRowPulseBorder.peak) < 1e-9)
    #expect(abs(frames[60]) < 1e-9)
    let breathe = ShopPulseClock.keyframes(period: ShopStatusTone.period) {
        ShopStatusBreathe.intensity(at: $0, animating: true) * ShopStatusTone.peakOpacity
    }
    #expect(breathe.count == 91)
    #expect(abs(breathe[45] - ShopStatusTone.peakOpacity) < 1e-9)
}

/// A centred stroke's outer edge sits half a line outside the frame, as SwiftUI's
/// `RoundedRectangle.stroke(lineWidth:)`; a disc is the centred circle of the short side.
@Test func shopPulseShapeGeometryMatchesSwiftUIShapes() {
    let stroke = ShopPulseShape.roundedStroke(cornerRadius: 12, lineWidth: 2)
        .geometry(in: CGSize(width: 300, height: 80))
    #expect(stroke.frame == CGRect(x: -1, y: -1, width: 302, height: 82))
    #expect(stroke.cornerRadius == 13)
    #expect(stroke.borderWidth == 2)
    let disc = ShopPulseShape.disc.geometry(in: CGSize(width: 40, height: 34))
    #expect(disc.frame == CGRect(x: 3, y: 0, width: 34, height: 34))
    #expect(disc.cornerRadius == 17)
    #expect(disc.borderWidth == 0)
}

// MARK: - Marquee track

/// One cycle holds, scrolls linearly, holds, then jumps back (web `marqueeScroll`).
@Test func marqueeTrackCycleKeepsTheWebTiming() {
    #expect(MarqueeTrackLayer.keyTimes == [0, 0.05, 0.95, 1])
    #expect(MarqueeTrackLayer.offsets(distance: 120) == [0, 0, -120, -120])
}

/// The track bitmap is drawn at the display scale and sized in points.
@MainActor
@Test func marqueeTrackRendersAtDisplayScale() throws {
    var environment = EnvironmentValuesProbe.base
    environment.displayScale = 2
    let track = MarqueeTrackLayer(
        track: AnyView(Text("Long title").fixedSize()), renderKey: AnyHashable(1),
        gap: 28, cycleDuration: 8, syncGroup: nil
    )
    let rendered = try #require(track.render(in: environment))
    #expect(rendered.image.width == Int((rendered.size.width * 2).rounded()))
    #expect(rendered.size.width > 20)
    #expect(rendered.size.height > 5)
}

/// Default environment for render tests.
enum EnvironmentValuesProbe {
    static var base: EnvironmentValues { EnvironmentValues() }
}

#if os(macOS)
// MARK: - Mac pre-dimmed artwork

/// The Mac multiplies cover pixels once instead of overlaying translucent black.
@MainActor
@Test func dimmedArtworkMultipliesEveryChannel() throws {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let white = try #require(context.makeImage())
    let dimmed = DimmedArtwork.image(white, lightness: 0.3)
    #expect(dimmed !== white)
    #expect(DimmedArtwork.image(white, lightness: 0.3) === dimmed)
    #expect(DimmedArtwork.image(white, lightness: 1) === white)
    let data = try #require(dimmed.dataProvider?.data as Data?)
    // BGRA little-endian: blue channel of the first pixel ≈ 0.3 × 255.
    #expect(abs(Int(data[0]) - 77) <= 1)
}
#endif
