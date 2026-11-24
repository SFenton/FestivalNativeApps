import Foundation

// MARK: - History value axes

/// Rounded linear ticks for the custom history plots.
enum HistoryAxisTicks {
    /// Picks a round step at least as large as the requested interval.
    ///
    /// - Parameters:
    ///   - top: The axis maximum.
    ///   - intervals: Target number of gaps across the domain.
    /// - Returns: Ascending tick values from zero through the last tick in the domain.
    static func linear(top: Double, intervals: Int) -> [Double] {
        guard top.isFinite, top > 0 else { return [0] }
        let raw = top / Double(max(1, intervals))
        let magnitude = pow(10, floor(log10(raw)))
        guard magnitude > 0 else { return [0] }
        let step = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * magnitude }.first { $0 >= raw } ?? 10 * magnitude
        guard step.isFinite else { return [0] }
        return Array(stride(from: 0, through: top, by: step))
    }
}
