#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

/// One score beneath the Score History chart (``ScoreHistoryListRow``): date, optional
/// season pill, score and the accuracy badge, the best score purple and bold. A flat entry
/// inside the song page's group card (the best one a purple band), or its own card for the
/// tapped bar's detail row. Read-only text: one static-text element.
///
/// At accessibility sizes the date, season, score and accuracy stack.
final class UKScoreHistoryRowView: UIView {
    /// Creates a row.
    ///
    /// - Parameters:
    ///   - entry: The history row.
    ///   - isBest: The list's best score.
    ///   - seasonColumn: Show the season pill before the score.
    ///   - currentSeason: The catalogue's current season, whose pill is inverted.
    ///   - grouped: Inside the Score History group card (no card of its own).
    ///   - scoreTemplate: The list's widest score, so scores line up (``LeaderboardRowColumns/scoreLabel``).
    init(entry: ScoreHistoryEntry, isBest: Bool, seasonColumn: Bool, currentSeason: Int?, grouped: Bool, scoreTemplate: String?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let accessibilitySize = UKFont.isAccessibilitySize(UITraitCollection.current)
        let season = seasonColumn ? entry.season.flatMap { $0 > 0 ? $0 : nil } : nil
        let dateText = entry.displayDate.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "\u{2014}"

        // Surface
        let purple = UIColor(red: 75 / 255, green: 15 / 255, blue: 99 / 255, alpha: 0.75)
        if grouped {
            if isBest { backgroundColor = purple }
        } else if isBest {
            backgroundColor = purple
            layer.cornerRadius = 12
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            layer.borderColor = BrandUIColors.accentPurple.withAlphaComponent(0.5).cgColor
        } else {
            let card = UKCardView(cornerRadius: 12)
            card.isUserInteractionEnabled = false
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
                card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        // Content
        let date = UKLabel(dateText, style: .body, weight: isBest ? .bold : nil, lines: accessibilitySize ? 0 : 1)
        date.adjustsFontSizeToFitWidth = !accessibilitySize
        date.minimumScaleFactor = accessibilitySize ? 1 : 0.75
        let score = UKLabel(entry.newScore.formatted(), style: .body, weight: .semibold, monospacedDigit: true, lines: 1, alignment: .right)
        score.adjustsFontSizeToFitWidth = accessibilitySize
        score.minimumScaleFactor = accessibilitySize ? 0.5 : 1
        score.setContentCompressionResistancePriority(.required, for: .horizontal)
        let scoreView: UIView = accessibilitySize ? score : UKLeaderboardColumnSlot(template: scoreTemplate, content: score)
        var badge: UIView?
        if let accuracy = entry.accuracy {
            let fullCombo = entry.isFullCombo == true
            let tint = try? ScoreFormatting.accuracyTint(accuracy)
            badge = UKAccuracyBadgeView(
                text: "\(ScoreFormatting.accuracy(accuracy))%", spoken: "", tint: fullCombo ? nil : tint, fullCombo: fullCombo,
                compact: !accessibilitySize, fixedSize: CGSize(width: 76, height: 24), skewsAlways: true, identifier: nil
            )
        } else if !accessibilitySize {
            let gap = UIView()
            gap.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([gap.widthAnchor.constraint(equalToConstant: 76), gap.heightAnchor.constraint(equalToConstant: 24)])
            badge = gap
        }
        let content = UIStackView()
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        if accessibilitySize {
            content.axis = .vertical
            content.alignment = .leading
            content.spacing = 6
            content.addArrangedSubview(date)
            if let season { content.addArrangedSubview(UKSeasonPillView(season: season, current: season == currentSeason, accessibilitySize: true)) }
            content.addArrangedSubview(scoreView)
            if let badge { content.addArrangedSubview(badge) }
        } else {
            content.axis = .horizontal
            content.alignment = .center
            content.spacing = 10
            content.addArrangedSubview(date)
            content.addArrangedSubview(UIView())
            if seasonColumn {
                content.addArrangedSubview(UKSeasonPillView(season: season, current: season != nil && season == currentSeason, accessibilitySize: false))
            }
            content.addArrangedSubview(scoreView)
            if let badge { content.addArrangedSubview(badge) }
        }
        addSubview(content)
        let vertical: CGFloat = accessibilitySize ? 10 : 0
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: vertical), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = SongScoreHistoryChartMath.spokenRow(
            dateText: dateText, season: season, currentSeason: currentSeason, entry: entry, isBest: isBest
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
