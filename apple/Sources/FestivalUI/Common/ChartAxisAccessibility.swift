import SwiftUI
import Charts

// MARK: - Chart axis elements

/// What each axis of a chart reads, as plain static text over its tick labels.
///
/// Swift Charts draws tick labels without accessibility elements, so the iPad audit
/// reported one "Potentially inaccessible text" per axis (Rank History on Player and
/// Statistics, Score History on Song Detail; Lane A11Y2's open item, confirmed by the
/// count matching the axes in Lane A11Y3). Each element covers its axis's labels and
/// reads the range they show (HIG VoiceOver: "Make charts and other infographics fully
/// accessible").
struct ChartAxisLabels: Equatable {
    /// The axis left of the plot (value scale).
    var leading: String?
    /// The axis right of the plot (second scale).
    var trailing: String?
    /// The axis below the plot (categories, dates).
    var bottom: String?

    /// "first to last", or the one value when they match.
    static func span(_ first: String?, _ last: String?) -> String {
        let first = first ?? "", last = last ?? ""
        return first == last ? first : "\(first) to \(last)"
    }
}

extension View {
    /// Report the chart's plot frame for ``SwiftUI/View/chartAxisElements(_:)``. Apply to
    /// the `Chart` itself.
    ///
    /// - Returns: The chart.
    func chartPlotFrameReporter() -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.preference(key: ChartPlotFrameKey.self, value: proxy.plotFrame.map { geometry[$0] })
            }
        }
    }

    /// One static-text element over each axis's tick labels. Apply **after** the chart's
    /// own accessibility modifiers (identifier, adjustable action): inside them the axis
    /// elements took the chart's identifier and adjustable action and were audited as an
    /// 18 pt tall control.
    ///
    /// - Parameter labels: What each axis reads; a nil axis gets no element.
    /// - Returns: The chart with its axis elements.
    func chartAxisElements(_ labels: ChartAxisLabels) -> some View {
        overlayPreferenceValue(ChartPlotFrameKey.self) { plot in
            if let plot {
                GeometryReader { geometry in
                    let size = geometry.size
                    ZStack(alignment: .topLeading) {
                        if let leading = labels.leading {
                            ChartAxisElement(label: leading, frame: CGRect(
                                x: 0, y: plot.minY, width: max(1, plot.minX), height: plot.height
                            ))
                        }
                        if let trailing = labels.trailing {
                            ChartAxisElement(label: trailing, frame: CGRect(
                                x: plot.maxX, y: plot.minY, width: max(1, size.width - plot.maxX), height: plot.height
                            ))
                        }
                        if let bottom = labels.bottom {
                            ChartAxisElement(label: bottom, frame: CGRect(
                                x: plot.minX, y: plot.maxY, width: plot.width, height: max(1, size.height - plot.maxY)
                            ))
                        }
                    }
                }
            }
        }
    }
}

/// The plot area in the chart's own coordinates.
private struct ChartPlotFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

/// An invisible static-text element at `frame` (chart coordinates).
private struct ChartAxisElement: View {
    let label: String
    let frame: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isStaticText)
    }
}
