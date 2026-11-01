#if os(iOS)
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
            chevron: true, hint: model.hint, separateParts: true, horizontalPadding: UKLeaderboardMetrics.horizontalPadding
        )
        host(row)
        row.accessibilityContainerType = .semanticGroup
        row.accessibilityIdentifier = model.identifier
        accessibilityIdentifier = nil
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
    }

    private let outer = UIStackView()
    private let content = UIStackView()
    private let membersStack = UIStackView()
    private let footer = UIStackView()
    private let rankLabel = ukRowLabel(.body, monospaced: true)
    private let scoreLabel = ukRowLabel(.body, monospaced: true)
    private let chevron = ukRowChevron()
    private var model: Model?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        outer.axis = .horizontal
        outer.spacing = 8
        outer.alignment = .center
        outer.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 8
        membersStack.axis = .vertical
        membersStack.spacing = 4
        footer.axis = .horizontal
        footer.spacing = 8
        footer.alignment = .center
        content.addArrangedSubview(membersStack)
        content.addArrangedSubview(footer)
        outer.addArrangedSubview(content)
        outer.addArrangedSubview(chevron)
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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
        let stacked = UKFont.isAccessibilitySize(traitCollection)
        membersStack.arrangedSubviews.forEach { membersStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for member in entry.members {
            let name = UKMarqueeLabel(member.resolvedName, font: UKFont.font(.body, weight: model.highlighted ? .bold : nil))
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let icons = UKInstrumentIconRow(instruments: member.chartedInstruments, side: 22, spacing: 4)
            icons.setContentHuggingPriority(.required, for: .horizontal)
            icons.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = UIStackView(arrangedSubviews: [ukNameHolder(name), icons])
            line.axis = .horizontal
            line.spacing = 8
            line.alignment = .center
            membersStack.addArrangedSubview(line)
        }
        rankLabel.text = "#\(entry.rank.formatted())"
        rankLabel.font = UKFont.font(.body, weight: model.highlighted ? .bold : nil, monospacedDigit: true)
        scoreLabel.text = entry.score.formatted()
        footer.arrangedSubviews.forEach { footer.removeArrangedSubview($0); $0.removeFromSuperview() }
        footer.axis = stacked ? .vertical : .horizontal
        footer.alignment = stacked ? .leading : .center
        footer.spacing = stacked ? 6 : 8
        footer.addArrangedSubview(rankLabel)
        if !stacked { footer.addArrangedSubview(UIView()) }
        footer.addArrangedSubview(scoreLabel)
        if entry.stars > 0 { footer.addArrangedSubview(UKStarRatingView(stars: entry.stars)) }
        if let badge = UKAccuracyBadgeView.make(
            accuracy: Double(entry.accuracy), fullCombo: entry.isFullCombo, accessibilitySize: stacked, identifier: ""
        ) {
            badge.isAccessibilityElement = false
            badge.accessibilityIdentifier = nil
            footer.addArrangedSubview(badge)
        }
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
