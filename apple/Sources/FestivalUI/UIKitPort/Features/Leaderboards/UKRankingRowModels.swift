#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Ranking row models

/// Builds the values of an account or band rankings row from a rankings entry: the same
/// strings and spoken labels the SwiftUI ``AccountRankingRow`` and ``BandRankingRow`` draw.
@MainActor
enum UKRankingRowModels {
    /// An account row.
    ///
    /// - Parameters:
    ///   - entry: The rankings row.
    ///   - metric: The board's metric.
    ///   - isSelected: The selected player's own row (bold, "Your rank …" spoken).
    ///   - columns: The section's fitted columns.
    ///   - opensProfile: The row is its own link (false for the pinned footer, whose button is the action).
    /// - Returns: The row's model.
    static func account(
        entry: AccountRankingEntry, metric: RankingMetric, isSelected: Bool, columns: LeaderboardRowColumns?,
        opensProfile: Bool = true
    ) -> UKRankingRowView.Model {
        let songs = entry.songsLabel(for: metric)
        let name = AccountRankingRow.displayName(entry)
        let rank = entry.rank(for: metric)
        return UKRankingRowView.Model(
            rank: rank, name: name, songs: songs,
            spokenSongs: RankingsCountText.spokenSongs(songs, fullCombos: metric == .fcrate),
            rating: RankingFormatting.rating(entry.ratingValue(for: metric), metric: metric),
            bayesian: entry.bayesianValue(for: metric).map(RankingFormatting.bayesian),
            emphasized: isSelected, showsChevron: entry.hasAccount, columns: columns,
            identifier: opensProfile ? "fst.rankings.row.\(entry.id)" : "fst.rankings.footer-row.\(entry.id)",
            opensSomething: opensProfile && entry.hasAccount,
            hint: opensProfile && !entry.hasAccount ? "Profile unavailable" : nil,
            spokenOverride: isSelected ? "Your rank, \(RankingFormatting.ordinal(rank)). \(name)." : nil
        )
    }

    /// A band row.
    ///
    /// - Parameters:
    ///   - entry: The band rankings row.
    ///   - metric: The board's band metric.
    ///   - columns: The section's fitted columns.
    /// - Returns: The row's model.
    static func band(entry: BandRankingEntry, metric: BandRankingMetric, columns: LeaderboardRowColumns?) -> UKRankingRowView.Model {
        let songs = entry.songsLabel(for: metric)
        return UKRankingRowView.Model(
            rank: entry.rank(for: metric), name: entry.membersLabel, songs: songs,
            spokenSongs: RankingsCountText.spokenSongs(songs, fullCombos: metric == .fcrate),
            rating: RankingFormatting.rating(entry.ratingValue(for: metric), metric: metric.asRankingMetric),
            bayesian: entry.bayesianValue(for: metric).map(RankingFormatting.bayesian),
            emphasized: false, showsChevron: true, columns: columns,
            identifier: "fst.band-rankings.row.\(entry.teamKey)"
        )
    }

    /// The row wrapper for an account entry.
    ///
    /// - Parameters:
    ///   - model: The row's values.
    ///   - selectedBand: Draw the purple band.
    ///   - onTap: Opens the profile, or nil.
    static func row(_ model: UKRankingRowView.Model, selectedBand: Bool, onTap: (() -> Void)?) -> UKLeaderboardRow {
        UKLeaderboardRow(
            kind: .ranking, make: { UKRankingRowView() },
            apply: { ($0 as? UKRankingRowView)?.apply(model) },
            isSelectedBand: selectedBand, onTap: onTap
        )
    }

    // MARK: Songs column fit (#38)

    /// The width a section's widest rankings row needs with its songs column shown: the
    /// same columns, fonts, spacing and padding as ``UKRankingRowView`` with every name on
    /// one line (the SwiftUI `RankingRowWidthProbe`).
    ///
    /// - Parameters:
    ///   - columns: The section's fitted columns.
    ///   - names: Every row's name, bold for the selected player's.
    ///   - traits: The board's trait collection (text size).
    /// - Returns: The required width in points.
    static func requiredRowWidth(columns: LeaderboardRowColumns, names: [RankingRowName], traits: UITraitCollection) -> CGFloat {
        func width(_ text: String?, _ style: UIFont.TextStyle, bold: Bool, monospaced: Bool) -> CGFloat {
            guard let text else { return 0 }
            let font = UKFont.font(style, weight: bold ? .bold : nil, monospacedDigit: monospaced)
            return ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let nameWidth = names.map { width($0.name, .body, bold: $0.emphasized, monospaced: false) }.max() ?? 0
        let columnsWidth = width(columns.rankLabel, .body, bold: true, monospaced: true)
            + width(columns.songsLabel, .subheadline, bold: false, monospaced: true)
            + width(columns.ratingLabel, .body, bold: true, monospaced: true)
        let chevron: CGFloat = 13
        return UKLeaderboardMetrics.horizontalPadding * 2 + columnsWidth + nameWidth + chevron + UKLeaderboardMetrics.columnSpacing * 4
    }

    /// The columns with the songs column hidden when showing it would truncate a name.
    ///
    /// - Parameters:
    ///   - base: The section's fitted columns, nil while it has no rows.
    ///   - names: Every row's name.
    ///   - sectionWidth: The section's measured width.
    ///   - rowInset: Horizontal padding around each row.
    ///   - pageColumns: Columns of rows across the section.
    ///   - traits: The board's trait collection.
    static func fittingSongs(
        _ base: LeaderboardRowColumns?, names: [RankingRowName], sectionWidth: CGFloat, rowInset: CGFloat,
        pageColumns: Int, traits: UITraitCollection
    ) -> LeaderboardRowColumns? {
        guard let base else { return nil }
        let available = RankingSongsFit.rowWidth(section: sectionWidth, rowInset: rowInset, columns: pageColumns)
        let required = requiredRowWidth(columns: base, names: names, traits: traits)
        return base.fittingSongs(availableWidth: Double(available), requiredWidth: Double(required))
    }
}
#endif
