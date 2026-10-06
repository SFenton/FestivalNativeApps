import SwiftUI
import Charts
import FestivalDesign

// MARK: - Bar chart date axis

extension View {
    /// The x axis of a history bar chart whose bars sit at integer indexes: one date
    /// label per visible bar, horizontally centred under that bar (#314).
    ///
    /// Swift Charts' default preset for a numeric axis starts the label at its tick, so
    /// a date sat right of its bar and read as belonging to the next one;
    /// `AxisValueLabel(anchor:)` alone did not move it. The `.aligned` preset centres
    /// each label on its tick, so it sits under its own bar, like the web's category ticks
    /// (`ScoreHistoryChart.tsx`, `RankHistoryChart.tsx`) and the Windows/Android slot
    /// layouts. HIG Charts: "Anchor an unassociated-looking label to its grid line with
    /// a tick." The tick labels stay out of the accessibility tree; each bar's label and
    /// ``SwiftUI/View/chartAxisElements(_:)`` carry the dates.
    ///
    /// - Parameters:
    ///   - values: Indexes of the visible bars.
    ///   - label: The date label for a bar index, or nil to leave that tick blank.
    /// - Returns: The chart with its date axis.
    func barChartDateAxis(values: [Int], label: @escaping (Int) -> String?) -> some View {
        chartXAxis {
            AxisMarks(preset: .aligned, values: values) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), let text = label(index) {
                        Text(text).foregroundStyle(FestivalText.primary)
                    }
                }
            }
        }
    }
}
