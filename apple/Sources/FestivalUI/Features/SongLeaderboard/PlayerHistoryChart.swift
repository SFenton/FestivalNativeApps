import SwiftUI
import Charts
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistoryChart

/// Score-over-time line chart above the history list; the web has no chart, but the
/// operator's brief calls for one when the data supports it (Swift Charts, iOS 16+).
struct PlayerHistoryChart: View {
    let entries: [ScoreHistoryEntry]
    let highScoreIndex: Int?

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let score: Int
        let isHighScore: Bool
    }

    private var points: [Point] {
        entries.enumerated().compactMap { index, entry in
            guard let date = entry.displayDate else { return nil }
            return Point(
                id: index, date: date, score: entry.newScore, isHighScore: index == highScoreIndex
            )
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        if points.count >= 2 {
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Score", point.score))
                    .foregroundStyle(BrandTokens.accentBlue)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value("Score", point.score))
                    .foregroundStyle(point.isHighScore ? BrandTokens.gold : BrandTokens.accentBlue)
                    .symbolSize(point.isHighScore ? 60 : 20)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 160)
            .padding(16)
            .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("Score history chart")
            .accessibilityValue(
                "\(points.count) tracked scores, highest \(points.map(\.score).max() ?? 0)"
            )
            .accessibilityIdentifier("fst.history.chart")
        }
    }
}
