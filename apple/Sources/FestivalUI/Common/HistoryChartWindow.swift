import CoreGraphics

// MARK: - History chart projection

/// A fractional x domain keeps the same bars and line moving between integer pages.
struct HistoryChartWindow {
    let lower: Double
    let upper: Double

    /// - Parameter range: The indexes on a settled page, one slot per bar.
    init(_ range: Range<Int>) {
        lower = Double(range.lowerBound) - 0.5
        upper = Double(max(range.lowerBound + 1, range.upperBound)) - 0.5
    }

    private init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    /// Projects a bar's index to its horizontal centre.
    ///
    /// - Parameters:
    ///   - index: Index in the full series.
    ///   - plot: Plot area, excluding axis gutters.
    /// - Returns: The x position, possibly outside the plot during a page change.
    func x(_ index: Int, in plot: CGRect) -> CGFloat {
        plot.minX + CGFloat((Double(index) - lower) / (upper - lower)) * plot.width
    }

    /// Finds the bars centred inside the current domain, optionally keeping neighbours
    /// so the clipped curve and partial bars stay connected at the edges.
    ///
    /// - Parameters:
    ///   - series: Valid indexes.
    ///   - padding: Extra samples on each side.
    /// - Returns: The indexes to project.
    func indexes(in series: Range<Int>, padding: Int = 0) -> Range<Int> {
        let first = min(series.upperBound, max(series.lowerBound, Int(ceil(lower)) - padding))
        let end = min(series.upperBound, max(first, Int(floor(upper)) + 1 + padding))
        return first..<end
    }

    /// Samples the Apple `.easeOut` curve from the current domain, not the last target.
    ///
    /// - Parameters:
    ///   - target: Destination domain.
    ///   - time: Fraction of the animation elapsed.
    /// - Returns: The interpolated domain.
    func sliding(to target: Self, time: Double) -> Self {
        if time <= 0 { return self }
        if time >= 1 { return target }
        // Solve x(t) for the ease-out control points (0, 0), (0.58, 1).
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<16 {
            let t = (lo + hi) / 2
            let x = 3 * (1 - t) * t * t * 0.58 + t * t * t
            if x < time { lo = t } else { hi = t }
        }
        let t = (lo + hi) / 2
        let progress = t * t * (3 - 2 * t)
        return Self(lower: lower + (target.lower - lower) * progress,
                    upper: upper + (target.upper - upper) * progress)
    }

    /// Centres each date under its bar, pinning edges and reserving room for the newest date.
    ///
    /// - Parameters:
    ///   - centres: Bar centres in chronological order.
    ///   - widths: Measured label widths, in the same order.
    ///   - bounds: Horizontal extent including the axis gutters.
    ///   - gap: Minimum space between labels.
    /// - Returns: A leading position per label; nil means the label does not fit.
    static func dateLabelLefts(centres: [CGFloat], widths: [CGFloat], in bounds: CGRect, gap: CGFloat) -> [CGFloat?] {
        let frames: [CGRect?] = zip(centres, widths).map { centre, width in
            guard width <= bounds.width else { return nil }
            let left = min(max(bounds.minX, centre - width / 2), bounds.maxX - width)
            return CGRect(x: left, y: 0, width: width, height: 1)
        }
        guard let last = frames.lastIndex(where: { $0 != nil }), let newest = frames[last] else {
            return frames.map { _ in nil }
        }
        var nextLeft = bounds.minX
        return frames.enumerated().map { index, frame -> CGFloat? in
            guard let frame else { return nil }
            if index != last {
                guard frame.minX >= nextLeft, frame.maxX + gap <= newest.minX else { return nil }
                nextLeft = frame.maxX + gap
            }
            return frame.minX
        }
    }
}
