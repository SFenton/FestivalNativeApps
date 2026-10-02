import SwiftUI
import FestivalCore

// MARK: - Section columns

extension EnvironmentValues {
    /// The fitted columns of the leaderboard section around a row (issue #37).
    ///
    /// Set once per section with `leaderboardSectionColumns(_:)`;
    /// `SongLeaderboardEntryRow` and `RankingRowLayout` read it to size their rank,
    /// score and rating columns to the section's widest label, so every row (pinned
    /// and spotlight rows included) lines its columns up vertically like the web's
    /// `computeRankWidth`/`scoreWidth` columns. Nil keeps each row's natural widths.
    @Entry var leaderboardRowColumns: LeaderboardRowColumns? = nil
}

extension View {
    /// Share one section's fitted columns with every leaderboard row inside it.
    ///
    /// - Parameter columns: The section's `LeaderboardRowColumns.fit(…)` result, or
    ///   nil while the section has no rows (natural widths).
    /// - Returns: This view with the columns in its environment.
    func leaderboardSectionColumns(_ columns: LeaderboardRowColumns?) -> some View {
        environment(\.leaderboardRowColumns, columns)
    }
}

// MARK: - Column slot

/// One shared row column: reserves the width `template` takes in the column's font
/// (always bold, so the selected player's bold row fits too) and draws `content`
/// inside it, aligned like the column.
///
/// The template is a hidden, accessibility-hidden `Text`, so the slot follows Dynamic
/// Type and the locale's digit grouping instead of a device-pixel heuristic. A nil or
/// empty template, or an accessibility text size (where rows stack instead of keeping
/// columns, HIG Typography: reduce text columns as size increases), draws `content`
/// at its natural width.
struct LeaderboardColumnSlot<Content: View>: View {
    /// The section's widest label for this column.
    let template: String?
    /// Leading for ranks, trailing for scores and ratings.
    var alignment: Alignment = .leading
    /// The column's font; the template always renders bold, monospaced digits.
    var font: Font = .body
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let template, !template.isEmpty, !dynamicTypeSize.isAccessibilitySize {
            ZStack(alignment: alignment) {
                Text(template)
                    .font(font)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
                content
            }
        } else {
            content
        }
    }
}
