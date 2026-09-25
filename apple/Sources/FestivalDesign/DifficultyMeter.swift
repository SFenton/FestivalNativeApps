import SwiftUI

/// The website's seven 8-by-20 parallelograms with one-point spacing.
public struct DifficultyMeter: View {
    public let level: Double
    public let raw: Bool

    /// Create a meter using either a raw (0-6) or displayed (1-7) value.
    ///
    /// - Parameters:
    ///   - level: Numeric difficulty from the song model.
    ///   - raw: Whether to add one after clamping to the source's raw scale.
    public init(level: Double, raw: Bool = false) {
        self.level = level
        self.raw = raw
    }

    // MARK: - Geometry

    /// Preserve fractional display labels while raw server values are truncated.
    ///
    /// - Parameters:
    ///   - level: Source difficulty number.
    ///   - raw: Whether the source uses the 0-6 scale.
    /// - Returns: Visible numeric level on the 1-7 scale.
    nonisolated public static func displayLevel(level: Double, raw: Bool) -> Double {
        raw
            ? min(max(level.rounded(.towardZero), 0), 6) + 1
            : min(max(level, 1), 7)
    }

    /// Convert the two difficulty scales to the count of filled bars.
    ///
    /// - Parameters:
    ///   - level: Raw or display difficulty number.
    ///   - raw: Whether the supplied level is in the 0-6 raw scale.
    /// - Returns: A clamped number of visible filled bars, from 1 through 7.
    nonisolated public static func filledBars(level: Double, raw: Bool) -> Int {
        guard level.isFinite else { return 0 }
        return Int(displayLevel(level: level, raw: raw).rounded(.down))
    }

    /// Native Canvas reproduces the original meter without raster assets.
    public var body: some View {
        Group {
            if level.isFinite {
                let displayed = Self.displayLevel(level: level, raw: raw)
                let filled = Self.filledBars(level: level, raw: raw)
                Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
                    for index in 0..<7 {
                        let x = CGFloat(index * 9)
                        var bar = Path()
                        bar.move(to: CGPoint(x: x + 2, y: 0))
                        bar.addLine(to: CGPoint(x: x + 8, y: 0))
                        bar.addLine(to: CGPoint(x: x + 6, y: 20))
                        bar.addLine(to: CGPoint(x: x, y: 20))
                        bar.closeSubpath()
                        context.fill(
                            bar,
                            with: .color(
                                index < filled
                                    ? .white
                                    : Color(.sRGB, red: 0.4, green: 0.4, blue: 0.4, opacity: 1)
                            )
                        )
                    }
                }
                .frame(width: 62, height: 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Difficulty \(displayed == Double(filled) ? String(filled) : String(displayed)) of 7"
                )
            } else {
                Text("Difficulty unavailable")
                    .accessibilityIdentifier("fst.songs.difficulty-unavailable")
            }
        }
        .accessibilityIdentifier("fst.songs.difficulty-meter")
    }
}
