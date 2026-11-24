#if os(iOS)
import UIKit

// MARK: - UIKit chart paging

/// Draws a native plot at its current x domain. Accessibility continues to describe
/// the committed page while only the presentation domain interpolates.
class UKHistoryChartViewport: UIView {
    /// The space Swift Charts leaves between the plot and its axis labels.
    static var axisLabelGap: CGFloat { 4 }

    /// Tick text follows the current content size, including accessibility categories.
    var axisFont: UIFont { UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection) }

    private let ticker = FrameTicker()
    private(set) var windowDomain = HistoryChartWindow(0..<0)
    private var target = HistoryChartWindow(0..<0)

    /// Fits both side axes and a single line of dates inside the fixed-height chart.
    ///
    /// - Parameters:
    ///   - leadingLabelWidth: Width of the widest leading tick label.
    ///   - trailingLabelWidth: Width of the widest trailing tick label.
    /// - Returns: The plot area in the chart's bounds.
    func axisPlotFrame(leadingLabelWidth: CGFloat, trailingLabelWidth: CGFloat) -> CGRect {
        let leading = leadingLabelWidth + Self.axisLabelGap
        let trailing = trailingLabelWidth + Self.axisLabelGap
        let dateBand = ceil(axisFont.lineHeight) + Self.axisLabelGap
        return CGRect(x: leading, y: 0, width: max(0, bounds.width - leading - trailing),
                      height: max(0, bounds.height - dateBand))
    }

    /// Keeps the highest tick's text inside the chart without shifting the plot down.
    ///
    /// - Parameter tickY: Vertical position of the tick on the plot.
    /// - Returns: The top coordinate for its label.
    func axisLabelTop(at tickY: CGFloat) -> CGFloat {
        max(0, tickY - axisFont.lineHeight / 2)
    }

    /// Draws single-line dates centered on their bars, keeping the newest when space is tight.
    ///
    /// - Parameters:
    ///   - dates: The visible labels and their bar centers, oldest first.
    ///   - top: The top of the date band.
    ///   - color: Tick text color.
    ///   - gap: Minimum spacing between tick labels.
    func drawDateLabels(_ dates: [(label: String, center: CGFloat)], top: CGFloat, color: UIColor, gap: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: axisFont, .foregroundColor: color]
        let strings = dates.map { $0.label as NSString }
        let lefts = HistoryChartWindow.dateLabelLefts(
            centres: dates.map(\.center), widths: strings.map { ceil($0.size(withAttributes: attributes).width) },
            in: bounds, gap: gap
        )
        for (text, left) in zip(strings, lefts) {
            if let left { text.draw(at: CGPoint(x: left, y: top), withAttributes: attributes) }
        }
    }

    /// Moves to a new page without changing the plot or pager's frame.
    ///
    /// - Parameters:
    ///   - range: Destination page in the full series.
    ///   - animated: False for the first page, remeasurement or replacement data.
    func showWindow(_ range: Range<Int>, animated: Bool) {
        let previous = windowDomain
        target = HistoryChartWindow(range)
        ticker.stop()
        guard animated, !UKAccessibility.reduceMotion, window != nil,
              previous.lower != target.lower || previous.upper != target.upper else {
            finishSlide()
            return
        }
        let start = CACurrentMediaTime()
        ticker.start { [weak self, ticker] timestamp in
            guard let self else {
                ticker.stop()
                return
            }
            let time = (timestamp - start) / ChartMotion.duration
            if time >= 1 || UKAccessibility.reduceMotion || self.window == nil {
                self.finishSlide()
            } else {
                self.windowDomain = previous.sliding(to: self.target, time: time)
                self.setNeedsDisplay()
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finishSlide() }
    }

    private func finishSlide() {
        ticker.stop()
        windowDomain = target
        setNeedsDisplay()
    }
}
#endif
