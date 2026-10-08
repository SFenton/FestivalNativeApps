import SwiftUI
import FestivalCore

// MARK: - Multi-row cards in the trailing pane (#364)

extension View {
    /// Share a song board's fitted columns with its rows and pinned footer, and, in a
    /// split's trailing pane, turn **every** row into a multi-row card when any of
    /// `names` would have to scroll in a one-line row (owner-approved variant of
    /// leaderboard-row R3, #364; ``LeaderboardRowColumns/fittingName(availableWidth:requiredWidth:)``).
    ///
    /// Full-width and iPhone boards, and accessibility text sizes (whose rows already
    /// stack and wrap), keep `columns` unchanged. The decision re-runs when the pane
    /// width, the text size or the names change.
    ///
    /// - Parameters:
    ///   - columns: The section's fitted columns (`LeaderboardRowColumns.fit`).
    ///   - names: Every row's name in the section, the pinned footer's included.
    ///   - template: A row of the section, for the probe's rank, season, score, stars
    ///     and accuracy columns (their widths are shared by every row); nil while the
    ///     section has no rows.
    ///   - currentSeason: The catalogue's current season.
    ///   - starsAfterScore: The rows draw stars after the score (the band footer).
    ///   - rowInset: Horizontal space between this view's edges and its rows.
    /// - Returns: This view with the decided columns in its environment.
    func songLeaderboardSectionColumns(
        _ columns: LeaderboardRowColumns, names: [RankingRowName], template: LeaderboardEntry?,
        currentSeason: Int?, starsAfterScore: Bool = false, rowInset: CGFloat
    ) -> some View {
        modifier(SongLeaderboardNameFit(
            columns: columns, names: names, template: template, currentSeason: currentSeason,
            starsAfterScore: starsAfterScore, rowInset: rowInset
        ))
    }
}

/// Measures a song board and its widest one-line row, then stacks the section's rows
/// when that row would not fit (``SwiftUI/View/songLeaderboardSectionColumns(_:names:template:currentSeason:starsAfterScore:rowInset:)``).
struct SongLeaderboardNameFit: ViewModifier {
    let columns: LeaderboardRowColumns
    let names: [RankingRowName]
    let template: LeaderboardEntry?
    let currentSeason: Int?
    var starsAfterScore = false
    let rowInset: CGFloat
    @Environment(\.splitPaneSubPage) private var subPage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0
    @State private var requiredWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let fits = Self.fitsNames(subPage: subPage, size: dynamicTypeSize)
        content
            .leaderboardSectionColumns(fits ? columns.fittingName(
                availableWidth: Double(availableWidth > 0 ? availableWidth - rowInset : 0),
                requiredWidth: Double(requiredWidth)
            ) : columns)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .background(alignment: .topLeading) {
                if fits, let template, !names.isEmpty {
                    // The one-line row the longest name needs, drawn by the real card
                    // in the section's one-line columns.
                    SongLeaderboardRowCard(
                        entry: template, currentSeason: currentSeason,
                        starsAfterScore: starsAfterScore, probeNames: names
                    )
                    .leaderboardSectionColumns(columns)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { requiredWidth = $0 }
                    .hidden()
                    .accessibilityHidden(true)
                }
            }
    }

    /// Whether a board decides between one-line rows and multi-row cards.
    ///
    /// - Parameters:
    ///   - subPage: The board is in a split's trailing pane beside its list page
    ///     (``SwiftUI/EnvironmentValues/splitPaneSubPage``).
    ///   - size: The current Dynamic Type size.
    /// - Returns: True only in the trailing pane at non-accessibility sizes; elsewhere
    ///   long names keep marqueeing (leaderboard-row R3), and accessibility sizes
    ///   already stack and wrap every row.
    nonisolated static func fitsNames(subPage: Bool, size: DynamicTypeSize) -> Bool {
        subPage && !size.isAccessibilitySize
    }
}
