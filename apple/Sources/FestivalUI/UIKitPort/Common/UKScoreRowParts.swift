#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Accuracy badge

/// The score row's accuracy pill (the badge of ``SongLeaderboardEntryRow``): white text on
/// the graded 25 % tint, or the web's gold bold-italic text in a transparent pill with a
/// 2 pt gold outline skewed -8 degrees for a full combo. Compact sizes keep a fixed
/// column-width pill; accessibility sizes let it grow around its text. Spoken as
/// ``spoken`` (static text) with the identifier `fst.score.accuracy.<account>`.
final class UKAccuracyBadgeView: UIView {
    private let label: UKLabel
    private let outline = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let fullCombo: Bool
    private let compact: Bool
    private let skewsAlways: Bool

    /// Creates a badge.
    ///
    /// - Parameters:
    ///   - text: The visible text ("98%", or "FC" when a full combo has no accuracy).
    ///   - spoken: The VoiceOver label.
    ///   - tint: Graded fill colour (25 % opacity applied here), nil for a full combo.
    ///   - fullCombo: Draw the gold outline.
    ///   - compact: Fixed pill (standard sizes) instead of growing around the text.
    ///   - width: Compact pill width at the default size (scaled with Dynamic Type).
    ///   - fixedSize: A compact pill of exactly this unscaled size (Score History's 76 x 24).
    ///   - skewsAlways: Skew a full combo's outline even when the pill grows (Score History).
    ///   - identifier: Accessibility identifier.
    init(
        text: String, spoken: String, tint: ScoreAccuracyTint?, fullCombo: Bool, compact: Bool, width: CGFloat = 72,
        fixedSize: CGSize? = nil, skewsAlways: Bool = false, identifier: String?
    ) {
        self.fullCombo = fullCombo
        self.compact = compact
        self.skewsAlways = skewsAlways
        label = UKLabel(
            text, style: .body, color: fullCombo ? BrandUIColors.gold : BrandUIColors.textPrimary,
            lines: compact ? 1 : 0, alignment: .center
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = UKFont.font(.body, weight: fullCombo ? .bold : nil, italic: fullCombo)
        label.adjustsFontSizeToFitWidth = compact
        label.minimumScaleFactor = 0.8
        fill.fillColor = tint.map {
            UIColor(red: CGFloat($0.red) / 255, green: CGFloat($0.green) / 255, blue: CGFloat($0.blue) / 255, alpha: 0.25).cgColor
        } ?? UIColor.clear.cgColor
        outline.fillColor = nil
        outline.strokeColor = fullCombo ? BrandUIColors.gold.cgColor : nil
        outline.lineWidth = 2
        layer.addSublayer(fill)
        layer.addSublayer(outline)
        addSubview(label)
        let padding: CGFloat = compact ? 0 : 4
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
        if compact {
            let side = fixedSize?.width ?? UKFont.scaled(width - 16, relativeTo: .body) + 16
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: side),
                heightAnchor.constraint(equalToConstant: fixedSize?.height ?? UKFont.scaled(24, relativeTo: .body)),
            ])
        } else {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        isAccessibilityElement = true
        accessibilityLabel = spoken
        accessibilityTraits = .staticText
        accessibilityIdentifier = identifier
        // When a row turns the badge into a plain part of its button, XCUITest reads the text
        // child: give it the spoken name and identifier too.
        label.accessibilityLabel = spoken
        label.accessibilityIdentifier = identifier
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKAccuracyBadgeView, _) in self.setNeedsLayout() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = Self.path(in: bounds, skewed: fullCombo && (compact || skewsAlways))
        fill.path = path
        outline.path = path
        fill.frame = bounds
        outline.frame = bounds
    }

    /// The pill's outline: a rounded rectangle, sheared like the web's `GOLD_SKEW` for a
    /// compact full combo (inset horizontally first so the sheared path stays inside).
    ///
    /// - Parameters:
    ///   - rect: The badge bounds.
    ///   - skewed: Apply the -8 degree shear.
    /// - Returns: The path.
    static func path(in rect: CGRect, skewed: Bool) -> CGPath {
        guard skewed, rect.width > 0, rect.height > 0 else {
            return UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
        }
        let shift = tan(8 * CGFloat.pi / 180) * rect.height / 2
        let local = CGRect(x: shift, y: 0, width: max(0, rect.width - 2 * shift), height: rect.height)
        var transform = SongLeaderboardEntryRow.goldSkew(height: rect.height)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return UIBezierPath(roundedRect: local, cornerRadius: 8).cgPath.copy(using: &transform) ?? UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
    }

    /// The badge for a solo or history score: graded tint, gold full combo, or the
    /// full-combo-without-accuracy form.
    ///
    /// - Parameters:
    ///   - accuracy: Expanded accuracy (1,000,000 = 100 %), if the service sent one.
    ///   - fullCombo: Whether the row is a full combo.
    ///   - accessibilitySize: Accessibility text size (longer text, growing pill).
    ///   - identifier: Accessibility identifier.
    /// - Returns: The badge, or nil when there is neither accuracy nor a full combo.
    static func make(accuracy: Double?, fullCombo: Bool, accessibilitySize: Bool, identifier: String) -> UKAccuracyBadgeView? {
        if let value = accuracy {
            let percent = "\(ScoreFormatting.accuracy(value))%"
            let spoken = fullCombo ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
            guard let tint = try? ScoreFormatting.accuracyTint(value) else { return nil }
            return UKAccuracyBadgeView(
                text: accessibilitySize ? spoken : percent, spoken: spoken, tint: fullCombo ? nil : tint,
                fullCombo: fullCombo, compact: !accessibilitySize, width: 72, identifier: identifier
            )
        }
        guard fullCombo else { return nil }
        return UKAccuracyBadgeView(
            text: accessibilitySize ? "Full combo" : "FC", spoken: "Full combo; accuracy unavailable", tint: nil,
            fullCombo: true, compact: !accessibilitySize, width: 72, identifier: identifier
        )
    }
}

// MARK: - Season pill

/// The season column's pill (``ScoreSeasonPill``): "S12" (or "Season 12" at accessibility
/// sizes), inverted for the current season. A nil season is an invisible slot of the
/// pill's width so the score column lines up (none at accessibility sizes).
final class UKSeasonPillView: UIView {
    /// Creates the pill.
    ///
    /// - Parameters:
    ///   - season: The season, or nil for the empty slot.
    ///   - current: Whether it is the catalogue's current season.
    ///   - accessibilitySize: Accessibility text size.
    init(season: Int?, current: Bool, accessibilitySize: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        guard let season else {
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            if !accessibilitySize {
                NSLayoutConstraint.activate([
                    widthAnchor.constraint(equalToConstant: UKFont.scaled(44, relativeTo: .body)),
                    heightAnchor.constraint(equalToConstant: UKFont.scaled(24, relativeTo: .body)),
                ])
            } else {
                isHidden = true
            }
            return
        }
        let compact = !accessibilitySize
        let label = UKLabel(
            compact ? "S\(season)" : "Season \(season)", style: .body, weight: .semibold, monospacedDigit: true,
            color: current ? BrandUIColors.surfaceSubtle : BrandUIColors.textSecondary,
            lines: compact ? 1 : 0, alignment: .center
        )
        label.adjustsFontSizeToFitWidth = compact
        label.minimumScaleFactor = 0.8
        backgroundColor = current ? BrandUIColors.textSecondary : BrandUIColors.surfaceSubtle
        layer.cornerRadius = 6
        layer.borderWidth = 2
        layer.borderColor = (current ? BrandUIColors.surfaceSubtle : BrandUIColors.borderSubtle).cgColor
        addSubview(label)
        let padding: CGFloat = compact ? 0 : 4
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
        if compact {
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: UKFont.scaled(44, relativeTo: .body)),
                heightAnchor.constraint(equalToConstant: UKFont.scaled(24, relativeTo: .body)),
            ])
        }
        isAccessibilityElement = true
        accessibilityLabel = ScoreSeasonPill.spokenLabel(season: season, current: current)
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Purple action

/// The in-card "View Full Leaderboard" / "View All Scores" action (``PurpleActionLabel``):
/// a 12 pt-radius purple button, at least 44 pt tall, white semibold title. Inside a card
/// it is the solid purple; the spoken name adds the card after the title
/// (``PurpleActionName``).
final class UKPurpleActionButton: UIControl {
    private let titleLabel: UKLabel

    /// Called on a tap.
    var onTap: (() -> Void)?

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - title: The visible title.
    ///   - card: What the action ends, spoken after the title.
    ///   - identifier: Accessibility identifier.
    ///   - onTap: Called on a tap.
    init(title: String, card: String?, identifier: String, onTap: (() -> Void)? = nil) {
        titleLabel = UKLabel(title, style: .body, weight: .semibold, alignment: .center)
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = BrandUIColors.accentPurple
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = PurpleActionName.spoken(title, card: card)
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - Name label

/// A leaderboard row's name (``LeaderboardNameText``): one line that scrolls as a marquee
/// when it does not fit; wrapping in full at accessibility sizes or when `stacked`.
/// Bold for the selected player's row. Static text.
final class UKLeaderboardNameView: UIView {
    /// Creates the name.
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - emphasized: Bold (the selected player's own row or band).
    ///   - wraps: Wrap in full instead of scrolling.
    init(name: String, emphasized: Bool, wraps: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let font = UKFont.font(.body, weight: emphasized ? .bold : nil)
        let content: UIView
        if wraps {
            let label = UKLabel(name, style: .body, weight: emphasized ? .bold : nil)
            content = label
        } else {
            let marquee = UKMarqueeLabel(name, font: font)
            content = marquee
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        // Leading-pinned at its natural width, compressing (and scrolling) only when the
        // column is narrower: the text never drifts to the middle of a wide column.
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        isAccessibilityElement = true
        accessibilityLabel = name
        accessibilityTraits = .staticText
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Entry row

/// One solo score row as Song Detail's top-ten cards and the Solo chart draw it
/// (``SongLeaderboardEntryRow`` plus the preview row's chrome): rank, name, optional season
/// pill, score and accuracy badge in the section's shared columns, a drill-down chevron,
/// 12 pt side padding and a 48 pt minimum height. The selected player's row is the flat
/// purple band (``RankingRowSurface/playerFill``) with bold rank and name.
///
/// With a `route` the whole row is one button (rank, name, score and accuracy spoken
/// together); without one it is plain text whose parts are separate elements.
final class UKSongLeaderboardEntryRowView: UIButton {
    /// Called when a row with a route is tapped.
    var onTap: (() -> Void)?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - entry: The board row.
    ///   - isPlayer: The selected player's own row.
    ///   - columns: The section's fitted columns (rank / score templates, season).
    ///   - currentSeason: The catalogue's current season.
    ///   - chevron: nil for no chevron column; false keeps its width invisible; true draws it.
    ///   - hint: Spoken hint for a row with a route.
    ///   - separateParts: Keep rank, name, season, score and accuracy separate VoiceOver elements even with a chevron (the song boards' rows, whose tap belongs to the list cell).
    ///   - horizontalPadding: Side padding (12 in Song Detail's cards, 14 on the song boards).
    init(
        entry: LeaderboardEntry, isPlayer: Bool, columns: LeaderboardRowColumns?, currentSeason: Int?,
        chevron: Bool?, hint: String? = nil, separateParts: Bool = false, horizontalPadding: CGFloat = 12
    ) {
        isPlayerRow = isPlayer
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let accessibilitySize = UKFont.isAccessibilitySize(UITraitCollection.current)
        backgroundColor = isPlayer ? UIColor(red: 75 / 255, green: 15 / 255, blue: 99 / 255, alpha: 0.75) : .clear
        let name = SongLeaderboardEntryRow.displayName(entry)
        let rankText = SongLeaderboardEntryRow.spokenRank(entry.rank, isPlayer: isPlayer)

        let rank = UKLabel("#\(entry.rank.formatted())", style: .body, weight: isPlayer ? .bold : nil, monospacedDigit: true, lines: 1)
        rank.accessibilityLabel = rankText
        let rankSlot = UKLeaderboardColumnSlot(template: columns?.rankLabel, content: rank)
        let nameView = UKLeaderboardNameView(name: name, emphasized: isPlayer, wraps: accessibilitySize)
        rankSlot.setContentHuggingPriority(.required, for: .horizontal)
        rankSlot.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameView.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)

        var values: [UIView] = []
        var spokenParts = [rankText, name]
        let season = entry.season.flatMap { $0 > 0 ? $0 : nil }
        if columns?.showsSeason == true {
            let pill = UKSeasonPillView(season: season, current: season != nil && season == currentSeason, accessibilitySize: accessibilitySize)
            values.append(pill)
            if let season { spokenParts.append(ScoreSeasonPill.spokenLabel(season: season, current: season == currentSeason)) }
        }
        let score = UKLabel(entry.score.formatted(), style: .body, monospacedDigit: true, lines: 1, alignment: .right)
        score.setContentCompressionResistancePriority(.required, for: .horizontal)
        let scoreSlot = UKLeaderboardColumnSlot(template: columns?.scoreLabel, content: score)
        scoreSlot.setContentHuggingPriority(.required, for: .horizontal)
        values.append(scoreSlot)
        spokenParts.append(entry.score.formatted())
        if let badge = UKAccuracyBadgeView.make(
            accuracy: entry.accuracy, fullCombo: entry.isFullCombo == true, accessibilitySize: accessibilitySize,
            identifier: "fst.score.accuracy.\(entry.accountId)"
        ) {
            values.append(badge)
            spokenParts.append(badge.accessibilityLabel ?? "")
        } else if !accessibilitySize {
            let placeholder = UIView()
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            placeholder.isAccessibilityElement = false
            NSLayoutConstraint.activate([
                placeholder.widthAnchor.constraint(equalToConstant: UKFont.scaled(56, relativeTo: .body) + 16),
                placeholder.heightAnchor.constraint(equalToConstant: UKFont.scaled(24, relativeTo: .body)),
            ])
            values.append(placeholder)
        }

        let line = UIStackView()
        line.isUserInteractionEnabled = false
        line.translatesAutoresizingMaskIntoConstraints = false
        if accessibilitySize {
            line.axis = .vertical
            line.alignment = .leading
            line.spacing = 8
            let head = UIStackView(arrangedSubviews: [rankSlot, nameView])
            head.spacing = 8
            head.alignment = .firstBaseline
            let tail = UIStackView(arrangedSubviews: values)
            tail.axis = .vertical
            tail.alignment = .leading
            tail.spacing = 8
            line.addArrangedSubview(head)
            line.addArrangedSubview(tail)
        } else {
            line.axis = .horizontal
            line.alignment = .center
            line.spacing = 8
            for view in [rankSlot, nameView] + values { line.addArrangedSubview(view) }
        }

        let outer = UIStackView(arrangedSubviews: [line])
        outer.isUserInteractionEnabled = false
        outer.spacing = 8
        outer.alignment = .center
        outer.translatesAutoresizingMaskIntoConstraints = false
        if let chevron {
            let image = UIImageView(image: UIImage(systemName: "chevron.forward"))
            image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
            image.tintColor = BrandUIColors.textMuted
            image.alpha = chevron ? 1 : 0
            image.isAccessibilityElement = false
            image.setContentHuggingPriority(.required, for: .horizontal)
            image.setContentCompressionResistancePriority(.required, for: .horizontal)
            outer.addArrangedSubview(image)
        }
        addSubview(outer)
        let vertical: CGFloat = accessibilitySize ? 8 : 0
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            heightAnchor.constraint(greaterThanOrEqualToConstant: LeaderboardRowMetrics.minHeight),
        ])
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        // A row with a destination is one button; an anonymous row's parts stay separate.
        if chevron == true, !separateParts {
            // The parts are not elements of their own (VoiceOver reads the button), but XCUITest
            // lists a button's text-bearing subviews as its static-text children, as it does
            // for the SwiftUI row's `Text`s.
            for part in [rank, nameView, score] + values.compactMap({ $0 as? UKAccuracyBadgeView }) + values.compactMap({ $0 as? UKSeasonPillView }) as [UIView] {
                part.isAccessibilityElement = false
            }
            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityLabel = spokenParts.joined(separator: ", ")
            accessibilityHint = hint
        } else {
            isAccessibilityElement = false
            isUserInteractionEnabled = false
            line.isUserInteractionEnabled = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            guard !isPlayerRow else { alpha = isHighlighted ? 0.8 : 1; return }
            backgroundColor = isHighlighted ? UIColor.white.withAlphaComponent(0.1) : .clear
        }
    }

    private let isPlayerRow: Bool
}
#endif
