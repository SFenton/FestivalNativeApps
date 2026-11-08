#if os(iOS)
import UIKit

/// Shared geometry for native chart date labels.
///
/// Labels stay centred on their bars, are pinned inside the plot bounds, and use the
/// same collision policy for Profile rank history and Song Detail score history.
enum UKChartDateAxis {
    /// Returns the indices whose labels can be shown without overlap.
    ///
    /// The newest label is always retained. Earlier labels are selected in source order
    /// when they fit beside the newest label and the labels already selected.
    ///
    /// - Parameters:
    ///   - centres: Bar centres in the plot's coordinate space.
    ///   - widths: Measured label widths in the same coordinate space.
    ///   - bounds: The horizontal plot bounds.
    ///   - minimumGap: The minimum gap between labels.
    /// - Returns: Source indices for the visible labels.
    static func visibleIndices(
        centres: [CGFloat], widths: [CGFloat], bounds: CGRect, minimumGap: CGFloat
    ) -> [Int] {
        guard !centres.isEmpty, centres.count == widths.count else { return [] }
        let frames = labelFrames(centres: centres, widths: widths, bounds: bounds)
        guard frames.count > 1 else { return [0] }

        let newest = frames.count - 1
        let newestFrame = frames[newest]
        var result: [Int] = []
        var lastMax = bounds.minX - minimumGap
        for index in 0..<newest {
            let frame = frames[index]
            guard frame.maxX + minimumGap <= newestFrame.minX else { continue }
            guard frame.minX >= lastMax + minimumGap else { continue }
            result.append(index)
            lastMax = frame.maxX
        }
        result.append(newest)
        return result
    }

    /// Returns centred, edge-pinned frames for labels.
    ///
    /// - Parameters:
    ///   - centres: Bar centres in the plot's coordinate space.
    ///   - widths: Measured label widths in the same coordinate space.
    ///   - bounds: The horizontal plot bounds.
    ///   - height: Label height.
    /// - Returns: One frame per input label.
    static func labelFrames(
        centres: [CGFloat], widths: [CGFloat], bounds: CGRect, height: CGFloat = 0
    ) -> [CGRect] {
        guard centres.count == widths.count else { return [] }
        return zip(centres, widths).map { centre, width in
            let constrainedWidth = min(max(0, width), max(0, bounds.width))
            let left = min(
                max(bounds.minX, centre - constrainedWidth / 2),
                max(bounds.minX, bounds.maxX - constrainedWidth)
            )
            return CGRect(x: left, y: bounds.minY, width: constrainedWidth, height: height)
        }
    }
}
#endif
