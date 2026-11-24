#if os(iOS)
import FestivalAppSupport
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Solo row

/// One Solo song-board row: hosts the shared ``UKSongLeaderboardEntryRowView`` (Common) in
/// the board's columns with separate rank, name, season, score and accuracy elements for
/// VoiceOver, 14 pt side padding and the in-card chevron. The tap is the cell's.
final class UKSongScoreRowView: UKRowHostView {
    /// What the row shows.
    struct Model {
        var entry: LeaderboardEntry
        var isPlayer = false
        var currentSeason: Int?
        var starsAfterScore = false
        var columns: LeaderboardRowColumns?
        var identifier: String
        var seasonColumn = false
        var hint: String?
    }

    private var model: Model?

    /// Fills the row.
    ///
    /// - Parameter model: The row's values.
    func apply(_ model: Model) {
        self.model = model
        var columns = model.columns
        if model.seasonColumn { columns?.showsSeason = true }
        let row = UKSongLeaderboardEntryRowView(
            entry: model.entry, isPlayer: model.isPlayer, columns: columns, currentSeason: model.currentSeason,
            chevron: true, hint: model.hint, separateParts: true, horizontalPadding: UKLeaderboardMetrics.horizontalPadding,
            starsAfterScore: model.starsAfterScore
        )
        host(row)
        row.accessibilityContainerType = .semanticGroup
        row.accessibilityIdentifier = model.identifier
        accessibilityIdentifier = nil
    }

    /// Measure the real score columns with the section's widest unwrapped name.
    static func oneLineWidth(
        columns: LeaderboardRowColumns, names: [RankingRowName], template: LeaderboardEntry,
        currentSeason: Int?, starsAfterScore: Bool
    ) -> CGFloat {
        let nameWidth = names.map { UKLeaderboardNameView.oneLineWidth($0.name, emphasized: $0.emphasized) }.max() ?? 0
        let row = UKSongLeaderboardEntryRowView(
            entry: template, isPlayer: false, columns: columns, currentSeason: currentSeason,
            chevron: true, horizontalPadding: UKLeaderboardMetrics.horizontalPadding,
            starsAfterScore: starsAfterScore, probeNameWidth: nameWidth
        )
        return row.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory, let model { apply(model) }
    }
}

// MARK: - Band card

/// One band score card (``SongBandPreviewRow``): each member's name and instruments, then
/// rank, team score, stars and accuracy, with the chevron centred on the card. One button
/// element for VoiceOver.
final class UKSongBandCardView: UIView {
    /// What the card shows.
    struct Model {
        var entry: SongBandLeaderboardEntry
        var highlighted: Bool
        var identifier: String
        var route: AppRoute
        var wrapsMembers = false
        var footerLayout: UKSongBandScoreFooterView.Layout
    }

    private static let sidePadding = UKSongBandScoreFooterView.cardInset
    private static let columnGap: CGFloat = 8
    private static let iconSide: CGFloat = 22
    private static let iconGap: CGFloat = 4

    /// Measure the widest unwrapped member line plus its instruments and card chrome.
    static func oneLineWidth(_ rows: [SongBandNameRow]) -> CGFloat? {
        let memberWidths = rows.flatMap { row in
            row.members.map { member in
                let count = CGFloat(member.chartedInstruments.count)
                let icons = count * iconSide + max(0, count - 1) * iconGap
                return UKLeaderboardNameView.oneLineWidth(member.resolvedName, emphasized: row.emphasized) + columnGap + icons
            }
        }
        let chevronWidth = ukRowChevron().intrinsicContentSize.width
        return memberWidths.max().map { $0 + sidePadding * 2 + columnGap + chevronWidth }
    }

    private let outer = UIStackView()
    private let content = UIStackView()
    private let membersStack = UIStackView()
    private var footer: UKSongBandScoreFooterView?
    private let chevron = ukRowChevron()
    private var model: Model?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        outer.axis = .horizontal
        outer.spacing = UKSongBandScoreFooterView.chevronGap
        outer.alignment = .center
        outer.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 8
        membersStack.axis = .vertical
        membersStack.spacing = 4
        content.addArrangedSubview(membersStack)
        outer.addArrangedSubview(content)
        outer.addArrangedSubview(chevron)
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.sidePadding),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.sidePadding),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 10), outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardMetrics.minHeight),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKSongBandCardView, _) in
            if let model = self.model { self.apply(model) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fills the card.
    ///
    /// - Parameter model: The card's values.
    func apply(_ model: Model) {
        self.model = model
        let entry = model.entry
        membersStack.arrangedSubviews.forEach { membersStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for member in entry.members {
            let name: UIView
            if model.wrapsMembers {
                name = UKLeaderboardNameView(name: member.resolvedName, emphasized: model.highlighted, wraps: true)
            } else {
                let label = UKMarqueeLabel(
                    member.resolvedName, font: UKLeaderboardNameView.nameFont(emphasized: model.highlighted)
                )
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                name = ukNameHolder(label)
            }
            let icons = UKInstrumentIconRow(instruments: member.chartedInstruments, side: Self.iconSide, spacing: Self.iconGap)
            icons.setContentHuggingPriority(.required, for: .horizontal)
            icons.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = UIStackView(arrangedSubviews: [name, icons])
            line.axis = .horizontal
            line.spacing = Self.columnGap
            line.alignment = .center
            membersStack.addArrangedSubview(line)
        }
        footer?.removeFromSuperview()
        let footer = UKSongBandScoreFooterView(entry: entry, highlighted: model.highlighted, layout: model.footerLayout)
        content.addArrangedSubview(footer)
        self.footer = footer
        accessibilityIdentifier = model.identifier
        accessibilityLabel = SongBandPreviewText.spokenLabel(entry, selected: model.highlighted)
        accessibilityHint = SongBandRowNavigation.hint(for: model.route)
    }
}

// MARK: - Score history row

/// One score of Score History: hosts the shared ``UKScoreHistoryRowView`` (Song Detail's,
/// its own card, the best score a purple card with border).
final class UKBoardScoreHistoryRowView: UKRowHostView {
    /// What the row shows.
    struct Model {
        var entry: ScoreHistoryEntry
        var isBest: Bool
        var seasonColumn: Bool
        var currentSeason: Int?
        var columns: LeaderboardRowColumns?
        var identifier: String
    }

    private var model: Model?

    /// Fills the row.
    ///
    /// - Parameter model: The row's values.
    func apply(_ model: Model) {
        self.model = model
        let row = UKScoreHistoryRowView(
            entry: model.entry, isBest: model.isBest, seasonColumn: model.seasonColumn, currentSeason: model.currentSeason,
            grouped: false, scoreTemplate: model.columns?.scoreLabel
        )
        row.accessibilityIdentifier = model.identifier
        host(row)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory, let model { apply(model) }
    }
}
#endif
