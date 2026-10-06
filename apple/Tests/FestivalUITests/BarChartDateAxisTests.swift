#if os(macOS)
import AppKit
import Charts
import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign

// MARK: - Bar chart date axis (#314)

// Pixel coverage for `barChartDateAxis`: each date label is centred under its own bar,
// as the Profile/Leaderboards rank-history and Song score-history charts plot them.
// Swift Charts' default numeric-axis label sat to the trailing side of its tick, so a
// date looked like it belonged to the next bar.

/// Horizontal centres, in pixels, of the bar runs and the label runs of a rendered chart.
private struct AxisRuns {
    var bars: [Double]
    var labels: [Double]
}

/// Render `count` bars at indexes `0..<count` with the shared date axis, like the
/// history charts: index domain padded by half a slot, fixed-width bars, clipped plot.
///
/// - Parameters:
///   - count: Bars to plot.
///   - width: Chart width in points.
///   - label: Label text for every bar.
///   - typeSize: Dynamic Type size for the labels.
/// - Returns: The rendered image at 2×.
@MainActor
private func renderDateAxisChart(
    count: Int, width: CGFloat, label: String, typeSize: DynamicTypeSize = .large
) throws -> CGImage {
    let indexes = Array(0..<count)
    let barWidth = width / CGFloat(count) * 0.5
    let chart = Chart(indexes, id: \.self) { index in
        BarMark(x: .value("Date", index), y: .value("Value", 10), width: .fixed(barWidth))
            .foregroundStyle(Color(red: 0, green: 0, blue: 1))
    }
    .chartYScale(domain: 0 ... 10)
    .chartXScale(domain: -0.5 ... Double(count) - 0.5)
    .chartPlotStyle { $0.clipped() }
    .chartYAxis(.hidden)
    .barChartDateAxis(values: indexes) { _ in label }
    .frame(width: width, height: 160)
    .padding(.horizontal, 40)
    .background(Color.black)
    .environment(\.colorScheme, .dark)
    .environment(\.dynamicTypeSize, typeSize)
    let renderer = ImageRenderer(content: chart)
    renderer.scale = 2
    return try #require(renderer.cgImage)
}

/// Group the columns where `hit` is true into runs (gaps of more than `gap` pixels split
/// runs) and return each run's horizontal centre.
private func runCentres(width: Int, gap: Int = 6, _ hit: (Int) -> Bool) -> [Double] {
    var centres: [Double] = []
    var start: Int?
    var last = -gap - 1
    for x in 0..<width where hit(x) {
        if let first = start, x - last > gap {
            centres.append(Double(first + last) / 2)
            start = x
        } else if start == nil {
            start = x
        }
        last = x
    }
    if let first = start { centres.append(Double(first + last) / 2) }
    return centres
}

/// Find the blue bar runs and the bright label runs below them.
@MainActor
private func axisRuns(_ image: CGImage) throws -> AxisRuns {
    let width = image.width, height = image.height
    let space = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }
    func isBar(_ p: (Int, Int, Int)) -> Bool { p.2 > 150 && p.0 < 90 && p.1 < 90 }
    func isText(_ p: (Int, Int, Int)) -> Bool { min(p.0, p.1, p.2) > 140 }
    // The bars' bottom edge: the lowest row holding bar pixels.
    var barBottom = 0
    for y in 0..<height where (0..<width).contains(where: { isBar(rgb($0, y)) }) { barBottom = y }
    let barRow = barBottom - 4
    let bars = runCentres(width: width) { isBar(rgb($0, barRow)) }
    let labels = runCentres(width: width, gap: 12) { x in
        (barBottom + 1 ..< height).contains { isText(rgb(x, $0)) }
    }
    return AxisRuns(bars: bars, labels: labels)
}

/// One page on iPhone (2 bars in a 302 pt plot), iPad and Mac widths, plus the largest
/// text sizes on the iPhone page, where a date is nearly as wide as its slot.
@MainActor
@Test(arguments: [
    (1, CGFloat(120), DynamicTypeSize.large), (2, CGFloat(302), .large), (3, CGFloat(330), .large),
    (5, CGFloat(560), .large), (2, CGFloat(302), .xxxLarge), (2, CGFloat(302), .accessibility5),
])
func dateLabelsAreCentredUnderTheirBars(count: Int, width: CGFloat, typeSize: DynamicTypeSize) throws {
    let image = try renderDateAxisChart(count: count, width: width, label: "10/4/26", typeSize: typeSize)
    _ = try nativeHostedPNG(
        image, filename: "bar-date-axis-\(count)-\(typeSize).png", environment: "FST_CHART_RENDER_OUT"
    )
    let runs = try axisRuns(image)
    #expect(runs.bars.count == count, "Expected \(count) bars, found \(runs.bars)")
    #expect(runs.labels.count == count, "Expected one date per bar, found \(runs.labels)")
    for (bar, label) in zip(runs.bars, runs.labels) {
        // 2 pt at 2×: glyph side bearings only, not the half-label offset of #314.
        #expect(abs(bar - label) <= 4, "Date centred at \(label) px but its bar at \(bar) px")
    }
}
#endif
