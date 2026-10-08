import SwiftUI
import FestivalCore

// MARK: - Multi-row cards in the trailing pane (#364)

extension View {
    /// Share a song board's fitted columns with its rows and pinned footer, and, in a
    /// split's trailing pane, turn **every** row into a multi-row card when any of
    /// `names` would have to scroll in a one-line row, or any band card member in
    /// `bandRows` would have to scroll beside its instruments (owner-approved variant
    /// of leaderboard-row R3, #364; ``LeaderboardRowColumns/fittingName(availableWidth:requiredWidth:)``).
    ///
    /// Full-width and iPhone boards, and accessibility text sizes (whose rows already
    /// stack and wrap), keep `columns` unchanged. The decision re-runs when the pane
    /// width, the text size or the names change.
    ///
    /// - Parameters:
    ///   - columns: The section's fitted columns (`LeaderboardRowColumns.fit`).
    ///   - names: Every one-line row's name in the section (``SongLeaderboardRowCard``:
    ///     Solo rows and both boards' pinned footers).
    ///   - bandRows: Every band card's members in the section (``SongBandPreviewRow``:
    ///     the band board's page rows); empty on the Solo board.
    ///   - template: A row of the section, for the probe's rank, season, score, stars
    ///     and accuracy columns (their widths are shared by every row); nil while the
    ///     section has no rows.
    ///   - currentSeason: The catalogue's current season.
    ///   - starsAfterScore: The rows draw stars after the score (the band footer).
    ///   - rowInset: Horizontal space between this view's edges and its rows.
    /// - Returns: This view with the decided columns in its environment.
    func songLeaderboardSectionColumns(
        _ columns: LeaderboardRowColumns, names: [RankingRowName], bandRows: [SongBandNameRow] = [],
        template: LeaderboardEntry?, currentSeason: Int?, starsAfterScore: Bool = false, rowInset: CGFloat
    ) -> some View {
        modifier(SongLeaderboardNameFit(
            columns: columns, names: names, bandRows: bandRows, template: template,
            currentSeason: currentSeason, starsAfterScore: starsAfterScore, rowInset: rowInset
        ))
    }
}

/// Measures a song board, its widest one-line row and its widest band member line,
/// then stacks the section's rows when either would not fit
/// (``SwiftUI/View/songLeaderboardSectionColumns(_:names:bandRows:template:currentSeason:starsAfterScore:rowInset:)``).
struct SongLeaderboardNameFit: ViewModifier {
    let columns: LeaderboardRowColumns
    let names: [RankingRowName]
    var bandRows: [SongBandNameRow] = []
    let template: LeaderboardEntry?
    let currentSeason: Int?
    var starsAfterScore = false
    let rowInset: CGFloat
    @Environment(\.splitPaneSubPage) private var subPage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0
    @State private var requiredWidth: CGFloat = 0
    @State private var bandRequiredWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let fits = Self.fitsNames(subPage: subPage, size: dynamicTypeSize)
        let probesRows = template != nil && !names.isEmpty
        let probesBands = !bandRows.isEmpty
        content
            .leaderboardSectionColumns(fits ? columns.fittingName(
                availableWidth: Double(availableWidth > 0 ? availableWidth - rowInset : 0),
                requiredWidth: Double(Self.requiredWidth(
                    rows: probesRows ? requiredWidth : nil, bands: probesBands ? bandRequiredWidth : nil
                ))
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
            .background(alignment: .topLeading) {
                if fits, probesBands {
                    // The band card the longest member line needs, in the real card's
                    // columns.
                    SongBandMemberWidthProbe(rows: bandRows)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { bandRequiredWidth = $0 }
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
    }

    /// The width the section's widest card needs on one line per name.
    ///
    /// - Parameters:
    ///   - rows: The one-line row probe's width, or nil when the section has no such rows.
    ///   - bands: The band card probe's width, or nil when the section has no band cards.
    /// - Returns: The wider of the two; zero (unmeasured, keep one line) when neither
    ///   applies or neither has been measured.
    nonisolated static func requiredWidth(rows: CGFloat?, bands: CGFloat?) -> CGFloat {
        max(rows ?? 0, bands ?? 0)
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
