#if os(macOS)
import AppKit
import FestivalCore
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Harnesses

/// Solid white rows with no gaps, so the mask's alpha is the pixel brightness over black.
private struct WhiteRows: View {
    var count = 60

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                Color.white.frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            }
        }
    }
}

/// Sheet content under the canonical sheet-header fade, on one scroll path.
private struct ModalFadeHarness: View {
    let legacy: Bool

    var body: some View {
        ScrollView { WhiteRows() }
            .modifier(ModalTopEdgeFadeModifier(legacyScrollTracking: legacy))
            .background(Color.black)
            // Hosts such as GitHub's macOS runner report Reduce Transparency on (issue
            // #122), which correctly makes the ramp a hard edge; pin it off.
            .environment(\._accessibilityReduceTransparency, false)
            .environment(\._colorSchemeContrast, .standard)
    }
}

/// Where a bottom-chrome harness reports its fade height.
@MainActor
private final class FadeDistanceBox {
    var distance: Double?
}

/// A paginated board's shape: rows above pinned bottom chrome under the canonical
/// bottom-chrome fade, as a `ScrollView` (Full Rankings) or a `List` (Song Leaderboard).
private struct BottomChromeHarness: View {
    static let space = "fst.tests.bottomChromeLegacy"
    static let chromeHeight: CGFloat = 60
    let list: Bool
    let legacy: Bool
    let box: FadeDistanceBox
    @State private var chromeTop: CGFloat?
    @State private var distance = ScrollEdgeFade.distance

    var body: some View {
        Group {
            if list {
                List {
                    ForEach(0..<60, id: \.self) { _ in
                        Color.white.frame(height: 44)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.white)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView { WhiteRows() }
            }
        }
        .bottomChromeFade(chromeTop: chromeTop, distance: $distance, in: Self.space, legacyScrollTracking: legacy)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.black.frame(height: Self.chromeHeight)
                .reportsBottomChromeTop(in: Self.space) { chromeTop = $0 }
        }
        .coordinateSpace(.named(Self.space))
        .background(Color.black)
        .onChange(of: distance, initial: true) { _, value in box.distance = value }
        .environment(\._accessibilityReduceTransparency, false)
        .environment(\._colorSchemeContrast, .standard)
    }
}

/// Records every reading of the shared scroll reader.
@MainActor
private final class ReadingBox {
    var reading: PlatformScrollObserver.Reading?
}

/// A `List` or `ScrollView` read by ``SwiftUI/View/onScrollEdgeReading(legacy:_:action:)``.
private struct ReaderHarness: View {
    let list: Bool
    let legacy: Bool
    let box: ReadingBox

    var body: some View {
        Group {
            if list {
                List(0..<60, id: \.self) { index in
                    Text("Row \(index)").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .listStyle(.plain)
            } else {
                ScrollView { WhiteRows() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.black.frame(height: 50) }
        .onScrollEdgeReading(legacy: legacy, { $0 }) { box.reading = $0 }
    }
}

// MARK: - Helpers

/// The harness's main scroll view: the largest one whose document runs past its height.
@MainActor
private func mainScrollView(in view: NSView) -> NSScrollView? {
    var best: NSScrollView?
    func walk(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           document.frame.height > scroll.contentView.bounds.height + 100,
           scroll.frame.height > (best?.frame.height ?? 0) {
            best = scroll
        }
        view.subviews.forEach(walk)
    }
    walk(view)
    return best
}

/// Scroll so `offset` points of content sit above the resting top (any document
/// orientation), and let the readings and masks settle.
@MainActor
@discardableResult
private func scroll(
    _ scrollView: NSScrollView, to offset: CGFloat, host: NSHostingView<some View>
) async throws -> CGImage {
    let clip = scrollView.contentView
    let documentHeight = scrollView.documentView?.frame.height ?? 0
    let top = offset - scrollView.contentInsets.top
    let y = clip.isFlipped ? top : documentHeight - top - clip.bounds.height
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
    return try await nativeHostedSettle(host)
}

/// The scroll offset at the end of the content, where its bottom meets the bottom inset.
@MainActor
private func endOffset(_ scrollView: NSScrollView) -> CGFloat {
    let documentHeight = scrollView.documentView?.frame.height ?? 0
    return documentHeight + scrollView.contentInsets.bottom - scrollView.contentView.bounds.height
        + scrollView.contentInsets.top
}

/// Scroll to the end of the content. A `List`'s table grows as it realizes rows near the
/// end, so scroll again until the end stops moving.
@MainActor
@discardableResult
private func scrollToEnd(
    _ scrollView: NSScrollView, host: NSHostingView<some View>
) async throws -> CGImage {
    var image = try await scroll(scrollView, to: endOffset(scrollView), host: host)
    for _ in 0..<6 {
        let end = endOffset(scrollView)
        let offset = PlatformScrollObserver.reading(
            visible: scrollView.contentView.bounds, documentHeight: scrollView.documentView?.frame.height ?? 0,
            topInset: scrollView.contentInsets.top, flipped: scrollView.contentView.isFlipped
        ).offset
        if abs(end - offset) <= 0.5 { break }
        image = try await scroll(scrollView, to: end, host: host)
    }
    return image
}

/// Mean brightness (0–255) of a horizontal strip of the capture, in host points.
private func brightness(fromY minY: CGFloat, toY maxY: CGFloat, of image: CGImage, hostSize: CGSize) -> Double {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return 0 }
    let scale = CGFloat(width) / hostSize.width
    let rows = max(0, Int(minY * scale))..<min(height, Int(maxY * scale))
    let columns = Int(hostSize.width * scale * 0.25)..<Int(hostSize.width * scale * 0.75)
    var total = 0.0, count = 0.0
    for y in rows {
        for x in columns {
            let pixel = (y * width + x) * 4
            total += Double(Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2])) / 3
            count += 1
        }
    }
    return count > 0 ? total / count : 0
}

// MARK: - Sheet header (issue #308 review)

/// Design review of #308: before iOS 18 / macOS 15 the sheet-header fade read no scroll
/// offset, so scrolled sheet content was cut off hard under the header instead of fading
/// in over 40 pt. On both scroll paths the content right under the header is fully drawn
/// at rest (R4), partly faded after 15 pt of scrolling, and once scrolled past the ramp is
/// clear at the header edge, half drawn 20 pt below it and opaque past 40 pt (R2, R3).
@MainActor
@Test(arguments: [true, false])
func modalTopFadeGrowsTheSharedRampOnEveryScrollPath(legacy: Bool) async throws {
    let size = CGSize(width: 420, height: 640)
    let host = nativeHostedView(
        ModalFadeHarness(legacy: legacy).frame(width: size.width, height: size.height),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host)
    let scrollView = try #require(mainScrollView(in: host))
    #expect(host.isFlipped)

    let rest = try await scroll(scrollView, to: 0, host: host)
    #expect(brightness(fromY: 1, toY: 5, of: rest, hostSize: size) > 240, "nothing is dimmed at rest")

    let early = try await scroll(scrollView, to: 15, host: host)
    let earlyEdge = brightness(fromY: 1, toY: 5, of: early, hostSize: size)
    #expect(earlyEdge > 120 && earlyEdge < 210, "the ramp grows with the first 40 pt of scrolling")

    let scrolled = try await scroll(scrollView, to: 400, host: host)
    #expect(brightness(fromY: 0, toY: 3, of: scrolled, hostSize: size) < 30, "clear at the header edge")
    let middle = brightness(fromY: 18, toY: 22, of: scrolled, hostSize: size)
    #expect(middle > 90 && middle < 165, "half drawn halfway down the 40 pt ramp")
    #expect(brightness(fromY: 44, toY: 60, of: scrolled, hostSize: size) > 240, "opaque past the ramp")
}

// MARK: - Bottom chrome (issue #308 review)

/// Design review of #308: before iOS 18 / macOS 15 the bottom-chrome fade read no
/// remaining scroll, so Full Rankings (a `ScrollView`) and Song Leaderboard (a `List`)
/// kept the full 36 pt fade at the end of the list. On both scroll paths and both scroll
/// kinds the fade is 36 pt mid-list, with row content dim just above the chrome, and 0 at
/// the end, where the last row is drawn fully up to the chrome (R4).
@MainActor
@Test(arguments: [true, false], [false, true])
func bottomChromeFadeIsZeroAtTheEndOnEveryScrollPath(legacy: Bool, list: Bool) async throws {
    let size = CGSize(width: 420, height: 640)
    let box = FadeDistanceBox()
    let host = nativeHostedView(
        BottomChromeHarness(list: list, legacy: legacy, box: box).frame(width: size.width, height: size.height),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host)
    let scrollView = try #require(mainScrollView(in: host))
    let chromeTop = size.height - BottomChromeHarness.chromeHeight

    let middle = try await scroll(scrollView, to: 600, host: host)
    #expect(box.distance == ScrollEdgeFade.distance)
    #expect(brightness(fromY: chromeTop - 6, toY: chromeTop - 1, of: middle, hostSize: size) < 60,
            "rows fade out above the chrome mid-list")
    #expect(brightness(fromY: chromeTop - 120, toY: chromeTop - 60, of: middle, hostSize: size) > 240)

    let end = try await scrollToEnd(scrollView, host: host)
    #expect(box.distance == 0, "no bottom ramp at the end of the list")
    #expect(brightness(fromY: chromeTop - 6, toY: chromeTop - 1, of: end, hostSize: size) > 240,
            "the last row is drawn fully up to the chrome")
}

// MARK: - Shared reader

/// The platform scroll view path reports what `onScrollGeometryChange` does, for a `List`
/// and a `ScrollView` read from outside: the distance scrolled, and the content left below
/// the bottom inset (0 at the end).
@MainActor
@Test(arguments: [false, true])
func scrollEdgeReadingMatchesScrollGeometryFromOutside(list: Bool) async throws {
    let size = CGSize(width: 420, height: 640)
    var readings: [[PlatformScrollObserver.Reading]] = []
    for legacy in [false, true] {
        let box = ReadingBox()
        let host = nativeHostedView(
            ReaderHarness(list: list, legacy: legacy, box: box).frame(width: size.width, height: size.height),
            size: size, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host) { box.reading != nil }
        let scrollView = try #require(mainScrollView(in: host))
        var path: [PlatformScrollObserver.Reading] = []
        for offset: CGFloat in [0, 15, 400] {
            try await scroll(scrollView, to: offset, host: host)
            path.append(try #require(box.reading))
        }
        try await scrollToEnd(scrollView, host: host)
        path.append(try #require(box.reading))
        window.orderOut(nil)
        #expect(abs(path[0].offset) <= 0.5)
        #expect(abs(path[1].offset - 15) <= 0.5)
        #expect(abs(path[2].offset - 400) <= 0.5)
        #expect(abs(try #require(path[3].overflow)) <= 0.5, "the end reads no overflow")
        #expect(try #require(path[2].overflow) > 100)
        readings.append(path)
    }
    for (modern, legacy) in zip(readings[0], readings[1]) {
        #expect(abs(modern.inset - legacy.inset) <= 0.5)
        #expect(abs(modern.offset - legacy.offset) <= 0.5)
        #expect(abs((modern.overflow ?? .nan) - (legacy.overflow ?? .nan)) <= 0.5)
    }
}
#endif
