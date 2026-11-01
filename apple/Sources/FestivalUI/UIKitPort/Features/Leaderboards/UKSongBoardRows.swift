#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Accuracy

/// How a score's accuracy pill reads, shared by the Solo row, the band card and the
/// footer (the SwiftUI rows compute this inline).
enum UKAccuracyPill {
    /// What to draw.
    struct Content {
        var text: String
        var spoken: String
        var tint: UIColor?
        var fullCombo: Bool
    }

    /// The pill for an optional accuracy and full-combo flag.
    ///
    /// - Parameters:
    ///   - accuracy: Expanded accuracy (ten-thousandths of a percent), or nil.
    ///   - fullCombo: The score is a full combo.
    ///   - accessibilitySize: Accessibility text size (the pill spells its state out).
    /// - Returns: The content, or nil when there is neither accuracy nor a full combo.
    static func content(accuracy: Double?, fullCombo: Bool, accessibilitySize: Bool) -> Content? {
        if let accuracy {
            let tint = try? ScoreFormatting.accuracyTint(accuracy)
            let percent = "\(ScoreFormatting.accuracy(accuracy))%"
            let spoken = fullCombo ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
            return Content(
                text: accessibilitySize ? spoken : percent, spoken: spoken,
                tint: tint.map { UIColor(red: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 1) },
                fullCombo: fullCombo
            )
        }
        if fullCombo {
            return Content(
                text: accessibilitySize ? "Full combo" : "FC", spoken: "Full combo; accuracy unavailable",
                tint: nil, fullCombo: true
            )
        }
        return nil
    }
}

// MARK: - Solo row

/// One Solo song-board row (``SongLeaderboardEntryRow`` inside ``SongLeaderboardRowCard``):
/// rank, name, then season, score, stars and accuracy in the section's columns, and the
/// in-card chevron. A container for VoiceOver whose children are the rank, name, season,
/// score and accuracy elements, read in that order.
final class UKSongScoreRowView: UIView {
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

    private let rankLabel = ukRowLabel(.body, monospaced: true)
    private lazy var rankSlot = UKColumnSlot(content: rankLabel, minimumWidth: 0)
    private let nameMarquee = UKMarqueeLabel("")
    private lazy var nameHolder = ukNameHolder(nameMarquee)
    private let seasonPill = UKBoardSeasonPillView()
    private let scoreLabel = ukRowLabel(.body, monospaced: true, alignment: .right)
    private lazy var scoreSlot = UKColumnSlot(content: scoreLabel, bold: false)
    private var starsView: UKStarRatingView?
    private let badge = UKBoardAccuracyBadgeView()
    private let placeholder = UIView()
    private let chevron = ukRowChevron()
    private let outer = UIStackView()
    private let head = UIStackView()
    private let values = UIStackView()
    private var model: Model?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        head.axis = .horizontal
        head.spacing = 8
        head.alignment = .center
        values.axis = .horizontal
        values.spacing = 8
        values.alignment = .center
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isUserInteractionEnabled = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UKLeaderboardMetrics.horizontalPadding),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UKLeaderboardMetrics.horizontalPadding),
            outer.topAnchor.constraint(equalTo: topAnchor), outer.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardMetrics.minHeight),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKSongScoreRowView, _) in
            if let model = self.model { self.apply(model) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The spoken rank: "Your rank, 3rd" on the player's own row, else "#3".
    ///
    /// - Parameters:
    ///   - rank: The row's 1-based rank.
    ///   - isPlayer: The selected player's own row.
    static func spokenRank(_ rank: Int, isPlayer: Bool) -> String {
        isPlayer ? "Your rank, \(RankingFormatting.ordinal(rank))" : "#\(rank.formatted())"
    }

    /// The name a row shows: the display name, or "Unknown User" without one.
    ///
    /// - Parameter entry: A board row.
    static func displayName(_ entry: LeaderboardEntry) -> String {
        entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
    }

    /// Fills the row.
    ///
    /// - Parameter model: The row's values.
    func apply(_ model: Model) {
        self.model = model
        let entry = model.entry
        let stacked = UKFont.isAccessibilitySize(traitCollection)
        rankLabel.text = "#\(entry.rank.formatted())"
        rankLabel.font = UKFont.font(.body, weight: model.isPlayer ? .bold : nil, monospacedDigit: true)
        rankLabel.isAccessibilityElement = true
        rankLabel.accessibilityLabel = Self.spokenRank(entry.rank, isPlayer: model.isPlayer)
        nameMarquee.text = Self.displayName(entry)
        nameMarquee.font = UKFont.font(.body, weight: model.isPlayer ? .bold : nil)
        scoreLabel.text = entry.score.formatted()
        scoreLabel.isAccessibilityElement = true
        rankSlot.template = model.columns?.rankLabel
        scoreSlot.template = model.columns?.scoreLabel
        let season = entry.season.flatMap { $0 > 0 ? $0 : nil }
        let showsSeason = model.seasonColumn || model.columns?.showsSeason == true
        seasonPill.show(season: showsSeason ? season : nil, current: season != nil && season == model.currentSeason)

        starsView?.removeFromSuperview()
        starsView = nil
        if model.starsAfterScore, model.columns?.showsStars == true, let stars = entry.stars, stars > 0 {
            starsView = UKStarRatingView(stars: stars)
        }
        let pill = UKAccuracyPill.content(accuracy: entry.accuracy, fullCombo: entry.isFullCombo == true, accessibilitySize: stacked)
        if let pill {
            badge.show(
                text: pill.text, spoken: pill.spoken, identifier: "fst.score.accuracy.\(entry.accountId)",
                tint: pill.tint, fullCombo: pill.fullCombo
            )
        }

        // Arrangement.
        outer.arrangedSubviews.forEach { outer.removeArrangedSubview($0); $0.removeFromSuperview() }
        head.arrangedSubviews.forEach { head.removeArrangedSubview($0); $0.removeFromSuperview() }
        values.arrangedSubviews.forEach { values.removeArrangedSubview($0); $0.removeFromSuperview() }
        head.addArrangedSubview(rankSlot)
        head.addArrangedSubview(nameHolder)
        if showsSeason, season != nil || !stacked { values.addArrangedSubview(seasonPill) }
        values.addArrangedSubview(scoreSlot)
        if let starsView { values.addArrangedSubview(starsView) }
        if pill != nil {
            values.addArrangedSubview(badge)
        } else if !stacked {
            NSLayoutConstraint.deactivate(placeholder.constraints)
            placeholder.widthAnchor.constraint(equalToConstant: UKFont.scaled(56, relativeTo: .body, traits: traitCollection) + 16).isActive = true
            placeholder.heightAnchor.constraint(equalToConstant: UKFont.scaled(24, relativeTo: .body, traits: traitCollection)).isActive = true
            values.addArrangedSubview(placeholder)
        }
        badge.isHidden = pill == nil
        if stacked {
            outer.axis = .vertical
            outer.alignment = .fill
            values.axis = .vertical
            values.alignment = .leading
            outer.addArrangedSubview(head)
            outer.addArrangedSubview(values)
            // Chevron trails the stacked content.
            head.addArrangedSubview(chevron)
            chevron.isHidden = false
        } else {
            outer.axis = .horizontal
            outer.alignment = .center
            values.axis = .horizontal
            values.alignment = .center
            outer.addArrangedSubview(head)
            outer.addArrangedSubview(values)
            outer.addArrangedSubview(chevron)
            chevron.isHidden = false
        }
        outer.layoutMargins = .zero
        rankSlot.applyTemplate()
        scoreSlot.applyTemplate()

        accessibilityIdentifier = model.identifier
        accessibilityHint = model.hint
        var order: [Any] = [rankLabel, nameMarquee]
        if showsSeason, season != nil { order.append(seasonPill) }
        order.append(scoreLabel)
        if let starsView { order.append(starsView) }
        if pill != nil { order.append(badge) }
        accessibilityElements = order
        // Vertical padding at AX sizes (`.padding(.vertical, 8)`).
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: stacked ? 8 : 0, leading: 0, bottom: stacked ? 8 : 0, trailing: 0)
        outer.isLayoutMarginsRelativeArrangement = true
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
    private let badge = UKBoardAccuracyBadgeView(textWidth: 56, height: 24)
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
        let accuracy = Double(entry.accuracy)
        let tint = try? ScoreFormatting.accuracyTint(accuracy)
        let uiTint = tint.map { UIColor(red: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 1) }
        badge.show(
            text: "\(ScoreFormatting.accuracy(accuracy))%", spoken: "", identifier: nil, tint: uiTint, fullCombo: entry.isFullCombo
        )
        badge.isAccessibilityElement = false
        footer.addArrangedSubview(badge)
        accessibilityIdentifier = model.identifier
        accessibilityLabel = SongBandPreviewText.spokenLabel(entry, selected: model.highlighted)
        accessibilityHint = SongBandRowNavigation.hint(for: model.route)
    }
}

// MARK: - Score history row

/// One score of Score History (``ScoreHistoryListRow``): date, optional season pill,
/// score and accuracy; the best score purple and bold. Read-only static text.
final class UKBoardScoreHistoryRowView: UIView {
    /// What the row shows.
    struct Model {
        var entry: ScoreHistoryEntry
        var isBest: Bool
        var seasonColumn: Bool
        var currentSeason: Int?
        var columns: LeaderboardRowColumns?
        var identifier: String
    }

    private let dateLabel = ukRowLabel(.body)
    private let seasonPill = UKBoardSeasonPillView()
    private let scoreLabel = ukRowLabel(.body, weight: .semibold, monospaced: true, alignment: .right)
    private lazy var scoreSlot = UKColumnSlot(content: scoreLabel, bold: false)
    private let badge = UKHistoryAccuracyBadge()
    private let line = UIStackView()
    private var model: Model?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UKLeaderboardMetrics.horizontalPadding),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UKLeaderboardMetrics.horizontalPadding),
            line.topAnchor.constraint(equalTo: topAnchor), line.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKBoardScoreHistoryRowView, _) in
            if let model = self.model { self.apply(model) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The score's date as the row draws it.
    ///
    /// - Parameter entry: A history entry.
    static func dateText(_ entry: ScoreHistoryEntry) -> String {
        guard let date = entry.displayDate else { return "\u{2014}" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Fills the row.
    ///
    /// - Parameter model: The row's values.
    func apply(_ model: Model) {
        self.model = model
        let entry = model.entry
        let stacked = UKFont.isAccessibilitySize(traitCollection)
        let season = model.seasonColumn ? entry.season.flatMap { $0 > 0 ? $0 : nil } : nil
        let dateText = Self.dateText(entry)
        dateLabel.text = dateText
        dateLabel.font = UKFont.font(.body, weight: model.isBest ? .bold : nil)
        dateLabel.numberOfLines = stacked ? 0 : 1
        dateLabel.adjustsFontSizeToFitWidth = !stacked
        dateLabel.minimumScaleFactor = 0.75
        dateLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scoreLabel.text = entry.newScore.formatted()
        scoreLabel.adjustsFontSizeToFitWidth = true
        scoreLabel.minimumScaleFactor = stacked ? 0.5 : 1
        scoreSlot.template = stacked ? nil : model.columns?.scoreLabel
        seasonPill.show(season: season, current: season != nil && season == model.currentSeason)
        badge.show(entry: entry, stacked: stacked)

        line.arrangedSubviews.forEach { line.removeArrangedSubview($0); $0.removeFromSuperview() }
        if stacked {
            line.axis = .vertical
            line.alignment = .leading
            line.spacing = 6
            line.addArrangedSubview(dateLabel)
            if season != nil { line.addArrangedSubview(seasonPill) }
            line.addArrangedSubview(scoreSlot)
            if entry.accuracy != nil { line.addArrangedSubview(badge) }
            line.isLayoutMarginsRelativeArrangement = true
            line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        } else {
            line.axis = .horizontal
            line.alignment = .center
            line.spacing = 10
            line.isLayoutMarginsRelativeArrangement = false
            line.addArrangedSubview(dateLabel)
            if model.seasonColumn { line.addArrangedSubview(seasonPill) }
            line.addArrangedSubview(scoreSlot)
            line.addArrangedSubview(badge)
        }
        scoreSlot.applyTemplate()
        accessibilityIdentifier = model.identifier
        accessibilityLabel = dateText
            + (season.map { ", " + ScoreSeasonPill.spokenLabel(season: $0, current: $0 == model.currentSeason).lowercased() } ?? "")
            + ", score \(entry.newScore.formatted())"
            + (entry.accuracy.map { ", accuracy \(ScoreFormatting.accuracy($0)) percent" } ?? "")
            + (entry.isFullCombo == true ? ", full combo" : "")
            + (model.isBest ? ", best score" : "")
    }
}

/// The history row's fixed 76 x 24 accuracy pill (a pill that grows around its text at
/// accessibility sizes), tinted along the web's red-to-green `accuracyColor`.
final class UKHistoryAccuracyBadge: UIView {
    private let label = UKLabel(nil, style: .body, lines: 1, alignment: .center)
    private let shape = CAShapeLayer()
    private var skewed = false
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.addSublayer(shape)
        addSubview(label)
        widthConstraint = widthAnchor.constraint(equalToConstant: 76)
        heightConstraint = heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint, heightConstraint,
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows an entry's accuracy; hidden-but-reserved without one on a single line.
    ///
    /// - Parameters:
    ///   - entry: The history entry.
    ///   - stacked: Accessibility-size layout.
    func show(entry: ScoreHistoryEntry, stacked: Bool) {
        isAccessibilityElement = false
        widthConstraint.constant = 76
        heightConstraint.constant = 24
        // Stacked: the pill grows around its text, at least 76 x 24.
        widthConstraint.isActive = !stacked
        heightConstraint.isActive = !stacked
        label.numberOfLines = stacked ? 0 : 1
        guard let accuracy = entry.accuracy else {
            label.text = nil
            shape.fillColor = nil
            shape.strokeColor = nil
            isHidden = stacked
            return
        }
        isHidden = false
        let fullCombo = entry.isFullCombo == true
        label.text = "\(ScoreFormatting.accuracy(accuracy))%"
        label.font = UKFont.font(.body, weight: fullCombo ? .bold : nil, italic: fullCombo)
        label.textColor = fullCombo ? BrandUIColors.gold : BrandUIColors.textPrimary
        let t = min(max(accuracy / 10_000 / 100, 0), 1)
        let tint = UIColor(
            red: (220 * (1 - t) + 46 * t) / 255, green: (40 * (1 - t) + 204 * t) / 255, blue: (40 * (1 - t) + 113 * t) / 255, alpha: 1
        )
        shape.fillColor = fullCombo ? nil : tint.withAlphaComponent(0.25).cgColor
        shape.strokeColor = fullCombo ? BrandUIColors.gold.cgColor : nil
        shape.lineWidth = fullCombo ? 2 : 0
        skewed = fullCombo
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        guard bounds.width > 0 else { return }
        if skewed {
            let shift = tan(8 * CGFloat.pi / 180) * bounds.height / 2
            let local = CGRect(x: shift, y: 0, width: max(0, bounds.width - 2 * shift), height: bounds.height)
            var transform = CGAffineTransform(a: 1, b: 0, c: -tan(8 * CGFloat.pi / 180), d: 1, tx: shift, ty: 0)
            shape.path = UIBezierPath(roundedRect: local, cornerRadius: 8).cgPath.copy(using: &transform)
        } else {
            shape.path = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
        }
    }
}
#endif
