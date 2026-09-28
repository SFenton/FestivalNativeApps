import Foundation

// MARK: - RankHistoryChartScale

/// Maps the web's two-axis Rank History chart onto one plotted y scale.
///
/// The web (`pages/leaderboards/components/RankHistoryChart.tsx`) draws a Recharts
/// `ComposedChart`: Total Score bars on a leading value axis and the global rank as a
/// line on a trailing, reversed rank axis (rank 1 at the top). Swift Charts has a single
/// y scale, so ranks are projected into the value range: the best rank of the padded
/// rank domain sits at the value axis top and the worst at zero. Trailing axis marks use
/// ``y(forRank:)`` positions labelled with the rank they represent.
public struct RankHistoryChartScale: Equatable, Sendable {
    /// Top of the value axis (bars and projected line share `0...valueTop`).
    public let valueTop: Double
    /// Best (smallest) rank at the top of the rank axis.
    public let bestRank: Int
    /// Worst (largest) rank at the bottom of the rank axis.
    public let worstRank: Int

    /// Build the shared scale for a series.
    ///
    /// - Parameters:
    ///   - values: Charted Total Score values (missing values count as 0, like the web).
    ///   - ranks: Charted Total Score ranks.
    public init(values: [Double], ranks: [Int]) {
        let maxValue = values.max() ?? 0
        valueTop = maxValue > 0 ? maxValue * 1.1 : 1
        let domain = Self.rankDomain(ranks)
        bestRank = domain.best
        worstRank = domain.worst
    }

    /// The web's `getRankHistoryDomain`: pad by 10% of the spread (rounded up), never
    /// above #1, `[1, 100]` when nothing is ranked. A flat series is widened by one place
    /// each side so the line has a non-empty domain.
    ///
    /// - Parameter ranks: Charted ranks; non-positive values are ignored.
    /// - Returns: Best and worst ranks of the axis.
    public static func rankDomain(_ ranks: [Int]) -> (best: Int, worst: Int) {
        let ranked = ranks.filter { $0 > 0 }
        guard let low = ranked.min(), let high = ranked.max() else { return (1, 100) }
        let padding = Int((Double(high - low) * 0.1).rounded(.up))
        var best = max(1, low - padding)
        var worst = high + padding
        if worst <= best {
            best = max(1, best - 1)
            worst = best + 2
        }
        return (best, worst)
    }

    /// Plot position for a rank: `valueTop` for ``bestRank``, 0 for ``worstRank``.
    ///
    /// - Parameter rank: Global rank to project.
    /// - Returns: The y value in the shared value scale.
    public func y(forRank rank: Int) -> Double {
        let span = Double(worstRank - bestRank)
        let clamped = Double(min(max(rank, bestRank), worstRank))
        return valueTop * (Double(worstRank) - clamped) / span
    }

    /// Up to four whole-number rank ticks from best to worst, evenly spaced.
    public var rankTicks: [Int] {
        let span = worstRank - bestRank
        let step = max(1, Int((Double(span) / 3).rounded(.up)))
        var ticks = Array(stride(from: bestRank, through: worstRank, by: step))
        if ticks.last != worstRank, ticks.count < 4 { ticks.append(worstRank) }
        return ticks
    }
}

// MARK: - Formatting

/// Text and colour rules shared with the web's rank-history chart model.
public enum RankHistoryChartFormat {
    /// The web's `formatValueTick` for `totalscore`: `1.2K`, `3M`, `1.5B`.
    ///
    /// - Parameter value: Axis value.
    /// - Returns: Compact label with at most one decimal.
    public static func compactScore(_ value: Double) -> String {
        let absolute = abs(value)
        let sign = value < 0 ? "-" : ""
        for (threshold, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")]
        where absolute >= threshold {
            let scaled = absolute / threshold
            // JS `toFixed(1)` rounds half away from zero (1.25 → "1.3"), unlike printf.
            let tenths = (scaled * 10).rounded()
            let text = scaled.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(scaled)) : String(format: "%.1f", tenths / 10)
            return sign + text + suffix
        }
        return String(Int(value.rounded()))
    }

    /// The web's `formatRankHistoryAxisDate`: `M/D/YY` from a `yyyy-MM-dd` snapshot day.
    ///
    /// - Parameter snapshotDate: Wire calendar day.
    /// - Returns: Short axis label, or the input when malformed.
    public static func axisDate(_ snapshotDate: String) -> String {
        let parts = snapshotDate.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return snapshotDate
        }
        return "\(month)/\(day)/\(parts[0].suffix(2))"
    }

    /// The web's `rankColor(rank, total)` → `accuracyColor`: red (220,40,40) for the
    /// bottom of the field to green (46,204,113) for the top; grey (127,140,141) when the
    /// field size is unknown.
    ///
    /// - Parameters:
    ///   - rank: Global rank.
    ///   - totalAccounts: Ranked accounts on the board.
    /// - Returns: 0–255 RGB components.
    public static func rankColor(rank: Int, totalAccounts: Int?) -> (red: Int, green: Int, blue: Int) {
        guard let totalAccounts, totalAccounts > 0, rank > 0 else { return (127, 140, 141) }
        let t = min(max(1 - Double(rank) / Double(totalAccounts), 0), 1)
        func mix(_ low: Double, _ high: Double) -> Int { Int((low * (1 - t) + high * t).rounded()) }
        return (mix(220, 46), mix(40, 204), mix(40, 113))
    }
}

// MARK: - RankHistoryPaging

/// Window over a chronological series for the swipeable, paginated chart, mirroring the
/// web's `useChartDimensions`/`useChartPagination` (`MIN_BAR_WIDTH` 96, `BAR_GAP` 8).
///
/// `start` is the index of the oldest visible point; the chart opens on the newest page.
public struct RankHistoryPaging: Equatable, Sendable {
    /// Web `MIN_BAR_WIDTH`.
    public static let minBarWidth: Double = 96
    /// Web `BAR_GAP`.
    public static let barGap: Double = 8

    /// Points in the series.
    public let count: Int
    /// Points visible at once.
    public let pageSize: Int

    /// Create a window.
    ///
    /// - Parameters:
    ///   - count: Points in the series.
    ///   - pageSize: Visible points; clamped to at least 1.
    public init(count: Int, pageSize: Int) {
        self.count = max(0, count)
        self.pageSize = max(1, pageSize)
    }

    /// How many bars fit a plot width at the web's minimum bar width and gap.
    ///
    /// - Parameter plotWidth: Width available to the bars, in points.
    /// - Returns: At least one bar.
    public static func pageSize(forPlotWidth plotWidth: Double) -> Int {
        max(1, Int(((max(0, plotWidth) + barGap) / (minBarWidth + barGap)).rounded(.down)))
    }

    /// Whether the series is wider than one page (web `needsPagination`).
    public var needsPagination: Bool { count > pageSize }
    /// Largest valid `start`: the newest page.
    public var latestStart: Int { max(0, count - pageSize) }

    /// Keep `start` inside the series.
    ///
    /// - Parameter start: Proposed oldest visible index.
    /// - Returns: `start` clamped to `0...latestStart`.
    public func clamp(_ start: Int) -> Int { min(max(start, 0), latestStart) }

    /// Web "Back one page": one page older.
    public func backPage(from start: Int) -> Int { clamp(start - pageSize) }
    /// Web "Back one entry": one snapshot older.
    public func backEntry(from start: Int) -> Int { clamp(start - 1) }
    /// Web "Forward one entry": one snapshot newer.
    public func forwardEntry(from start: Int) -> Int { clamp(start + 1) }
    /// Web "Forward one page": one page newer.
    public func forwardPage(from start: Int) -> Int { clamp(start + pageSize) }

    /// Whether older points exist before `start`.
    public func canGoBack(from start: Int) -> Bool { clamp(start) > 0 }
    /// Whether newer points exist after the window at `start`.
    public func canGoForward(from start: Int) -> Bool { clamp(start) < latestStart }

    /// Indices visible at `start`.
    ///
    /// - Parameter start: Oldest visible index.
    /// - Returns: The visible index range (empty for an empty series).
    public func visibleRange(from start: Int) -> Range<Int> {
        let first = clamp(start)
        return first..<min(count, first + pageSize)
    }
}
