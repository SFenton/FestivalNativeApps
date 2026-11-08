#if os(iOS)
import UIKit

/// Shared native chart interpolation used by rank and score history plots.
enum UKChartMath {
    /// Builds a monotone cubic path through ordered points.
    ///
    /// - Parameter points: Left-to-right plot points.
    /// - Returns: The curve, or nil for no points.
    static func monotonePath(_ points: [CGPoint]) -> CGPath? {
        guard let first = points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: first)
        guard points.count > 1 else { return path }

        let count = points.count
        var slopes = [CGFloat](repeating: 0, count: count - 1)
        for index in 0..<(count - 1) {
            let dx = points[index + 1].x - points[index].x
            slopes[index] = dx == 0 ? 0 : (points[index + 1].y - points[index].y) / dx
        }
        var tangents = [CGFloat](repeating: 0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]
        for index in 1..<(count - 1) {
            tangents[index] = slopes[index - 1] * slopes[index] <= 0
                ? 0 : (slopes[index - 1] + slopes[index]) / 2
        }
        for index in 0..<(count - 1) {
            if slopes[index] == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let a = tangents[index] / slopes[index]
            let b = tangents[index + 1] / slopes[index]
            let magnitude = (a * a + b * b).squareRoot()
            if magnitude > 3 {
                tangents[index] = 3 * a / magnitude * slopes[index]
                tangents[index + 1] = 3 * b / magnitude * slopes[index]
            }
        }
        for index in 0..<(count - 1) {
            let third = (points[index + 1].x - points[index].x) / 3
            path.addCurve(
                to: points[index + 1],
                control1: CGPoint(
                    x: points[index].x + third, y: points[index].y + tangents[index] * third
                ),
                control2: CGPoint(
                    x: points[index + 1].x - third,
                    y: points[index + 1].y - tangents[index + 1] * third
                )
            )
        }
        return path
    }
}
#endif
