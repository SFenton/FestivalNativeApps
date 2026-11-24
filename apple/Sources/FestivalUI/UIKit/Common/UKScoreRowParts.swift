#if os(iOS)
import FestivalAppSupport
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
    private static let bandWidth: CGFloat = 72
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
    ///   - wrapsAtAccessibilitySize: Allow a descriptive label to wrap in a growing pill.
    ///   - identifier: Accessibility identifier.
    init(
        text: String, spoken: String, tint: ScoreAccuracyTint?, fullCombo: Bool, compact: Bool, width: CGFloat = 72,
        fixedSize: CGSize? = nil, skewsAlways: Bool = false, wrapsAtAccessibilitySize: Bool = true, identifier: String?
    ) {
        self.fullCombo = fullCombo
        self.compact = compact
        self.skewsAlways = skewsAlways
        let singleLine = compact || !wrapsAtAccessibilitySize
        label = UKLabel(
            text, style: .body, color: fullCombo ? BrandUIColors.gold : BrandUIColors.textPrimary,
            lines: singleLine ? 1 : 0, alignment: singleLine ? .center : .natural,
            wrapsToLayoutWidth: !singleLine
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = UKFont.font(.body, weight: fullCombo ? .bold : nil, italic: fullCombo)
        label.adjustsFontSizeToFitWidth = singleLine
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
            let side = fixedSize?.width ?? Self.scaledWidth(width)
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
        let shape = GoldSkewBadgeShape(skewed: fullCombo && (compact || skewsAlways))
        let path = shape.path(in: bounds).cgPath
        fill.path = path
        outline.path = path
        fill.frame = bounds
        outline.frame = bounds
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

    /// Draws just the percentage on a band card; the card speaks the full score description.
    ///
    /// - Parameters:
    ///   - accuracy: Expanded accuracy (1,000,000 = 100 %).
    ///   - fullCombo: Whether the band achieved a full combo.
    ///   - accessibilitySize: Whether the badge grows around its text.
    /// - Returns: The band's one-line accuracy badge.
    static func band(accuracy: Int, fullCombo: Bool, accessibilitySize: Bool) -> UKAccuracyBadgeView? {
        let value = Double(accuracy)
        guard let tint = try? ScoreFormatting.accuracyTint(value) else { return nil }
        let percent = "\(ScoreFormatting.accuracy(value))%"
        return UKAccuracyBadgeView(
            text: percent, spoken: percent, tint: fullCombo ? nil : tint, fullCombo: fullCombo,
            compact: !accessibilitySize, width: bandWidth, wrapsAtAccessibilitySize: false, identifier: nil
        )
    }

    /// Space the compact band badge takes at the current Dynamic Type size.
    static var compactBandWidth: CGFloat { scaledWidth(bandWidth) }

    private static func scaledWidth(_ width: CGFloat) -> CGFloat {
        UKFont.scaled(width - 16, relativeTo: .body) + 16
    }
}

// MARK: - Band score footer

/// The shared footer of a song band preview and full-board row.
final class UKSongBandScoreFooterView: UIStackView {
    /// Inline when the section fits, split at standard sizes when it doesn't, and
    /// one value per line at accessibility sizes.
    enum Layout {
        case inline, badgesBelow, accessibility
    }

    static let cardInset: CGFloat = 12
    static let chevronGap: CGFloat = 8
    private static let itemSpacing: CGFloat = 8
    private let entry: SongBandLeaderboardEntry
    private let highlighted: Bool
    private var currentLayout: Layout?
    private var currentTextSize: UIContentSizeCategory?

    init(entry: SongBandLeaderboardEntry, highlighted: Bool, layout: Layout) {
        self.entry = entry
        self.highlighted = highlighted
        super.init(frame: .zero)
        apply(layout, traits: UITraitCollection.current)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fit every row to the section's narrowest card, including its chevron and insets.
    static func layout(
        for rows: [(entry: SongBandLeaderboardEntry, highlighted: Bool)], cardWidth: CGFloat, traits: UITraitCollection
    ) -> Layout {
        if UKFont.isAccessibilitySize(traits) { return .accessibility }
        guard cardWidth > 0 else { return .inline }
        var layout = Layout.inline
        traits.performAsCurrent {
            let available = cardWidth - cardInset * 2 - chevronGap - ukRowChevron().intrinsicContentSize.width
            let regular = UKFont.font(.body, monospacedDigit: true)
            let bold = UKFont.font(.body, weight: .bold, monospacedDigit: true)
            for (entry, highlighted) in rows {
                let rank = ("#\(entry.rank.formatted())" as NSString).size(withAttributes: [.font: highlighted ? bold : regular]).width
                let score = (entry.score.formatted() as NSString).size(withAttributes: [.font: regular]).width
                var needed = ceil(rank) + ceil(score) + itemSpacing * 2
                if entry.stars > 0 {
                    needed += UKStarRatingView.inlineWidth(stars: entry.stars, traits: traits) + itemSpacing
                }
                if (try? ScoreFormatting.accuracyTint(Double(entry.accuracy))) != nil {
                    needed += UKAccuracyBadgeView.compactBandWidth + itemSpacing
                }
                if needed > available {
                    layout = .badgesBelow
                    break
                }
            }
        }
        return layout
    }

    /// Update the footer in place when the preview's width or text size changes.
    func apply(_ layout: Layout, traits: UITraitCollection) {
        let textSize = traits.preferredContentSizeCategory
        guard layout != currentLayout || textSize != currentTextSize else { return }
        currentLayout = layout
        currentTextSize = textSize
        traits.performAsCurrent { rebuild(layout) }
    }

    private func rebuild(_ layout: Layout) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rank = ukRowLabel(.body, weight: highlighted ? .bold : nil, monospaced: true)
        rank.text = "#\(entry.rank.formatted())"
        let score = ukRowLabel(.body, monospaced: true)
        score.text = entry.score.formatted()
        var badges: [UIView] = []
        if entry.stars > 0 { badges.append(UKStarRatingView(stars: entry.stars)) }
        if let badge = UKAccuracyBadgeView.band(
            accuracy: entry.accuracy, fullCombo: entry.isFullCombo, accessibilitySize: layout == .accessibility
        ) {
            badge.isAccessibilityElement = false
            badges.append(badge)
        }
        axis = layout == .inline ? .horizontal : .vertical
        alignment = layout == .inline ? .center : (layout == .accessibility ? .leading : .fill)
        spacing = layout == .inline ? Self.itemSpacing : 6
        switch layout {
        case .inline:
            ([rank, UIView(), score] + badges).forEach(addArrangedSubview)
        case .badgesBelow:
            addArrangedSubview(Self.line([rank, UIView(), score]))
            if !badges.isEmpty { addArrangedSubview(Self.line([UIView()] + badges)) }
        case .accessibility:
            ([rank, score] + badges).forEach(addArrangedSubview)
        }
    }

    private static func line(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.spacing = itemSpacing
        stack.alignment = .center
        return stack
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
/// a 12 pt-radius purple button, at least 48 pt tall including padding, white semibold title. Inside a card
/// it is the solid purple; the spoken name adds the card after the title
/// (``PurpleActionName``).
final class UKPurpleActionButton: UIControl {
    private let titleLabel: UKLabel
    private var splitObservation: UKObservation?

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
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: PurpleActionMetrics.verticalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PurpleActionMetrics.verticalPadding),
            heightAnchor.constraint(greaterThanOrEqualToConstant: PurpleActionMetrics.minimumHeight),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = PurpleActionName.spoken(title, card: card)
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Creates an action that can stay selected beside its open split detail.
    ///
    /// - Parameters:
    ///   - title: The visible title.
    ///   - card: What the action ends, spoken after the title.
    ///   - identifier: Accessibility identifier.
    ///   - detail: The route to open.
    ///   - context: The navigator and observable shell for the originating page.
    convenience init(title: String, card: String?, identifier: String, detail: AppRoute, context: UKContext) {
        self.init(title: title, card: card, identifier: identifier) { [weak navigator = context.navigator] in
            navigator?.selectDetail(detail)
        }
        splitObservation = UKSplitSelection.bind(self, to: detail, in: context)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - Split selection

@MainActor
enum UKSplitSelection {
    /// Marks a control only while its exact route is open in the current section's split.
    ///
    /// - Parameters:
    ///   - control: The accessible leading-pane control.
    ///   - route: The detail it opens.
    ///   - context: The originating page and its observable shell.
    ///   - fillsRow: Whether to tint a clear row behind its content, as in `ListDetailSelectableRow`.
    /// - Returns: The binding, retained by the control.
    static func bind(
        _ control: UIControl, to route: AppRoute, in context: UKContext, fillsRow: Bool = false
    ) -> UKObservation {
        let marker = UIView()
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.backgroundColor = BrandUIColors.accentBlue
        marker.layer.cornerRadius = 1.5
        marker.isUserInteractionEnabled = false
        marker.isHidden = true
        control.addSubview(marker)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            marker.topAnchor.constraint(equalTo: control.topAnchor, constant: 8),
            marker.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -8),
            marker.widthAnchor.constraint(equalToConstant: 3),
        ])
        if fillsRow {
            control.layer.cornerRadius = 12
            control.layer.cornerCurve = .continuous
        }
        return UKObservation { [weak control, weak marker, weak shell = context.shell, section = context.section] in
            guard let control, let shell else { return }
            let selected = shell.selectedSection == section && shell.splitSelection == route
            control.isSelected = selected
            marker?.isHidden = !selected
            if selected { control.accessibilityTraits.insert(.selected) }
            else { control.accessibilityTraits.remove(.selected) }
            if fillsRow {
                control.backgroundColor = selected ? BrandUIColors.accentBlue.withAlphaComponent(0.22) : .clear
            }
        }
    }
}

// MARK: - Name label

/// A leaderboard row's name (``LeaderboardNameText``): one line that scrolls as a marquee
/// when it does not fit; wrapping in full at accessibility sizes or when `stacked`.
/// Bold for the selected player's row. Static text.
final class UKLeaderboardNameView: UIView {
    /// The preferred body font keeps the same optical spacing as SwiftUI's row names.
    /// The fit probe and both presentations use it, including for the selected name.
    ///
    /// - Parameter emphasized: Whether the name uses the bold body font.
    /// - Returns: The name's font at the current Dynamic Type size.
    static func nameFont(emphasized: Bool) -> UIFont {
        UKFont.preferredFont(.body, bold: emphasized)
    }

    /// The natural width of the name as this view draws it before scrolling or wrapping.
    static func oneLineWidth(_ name: String, emphasized: Bool) -> CGFloat {
        let font = nameFont(emphasized: emphasized)
        return ceil((name as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Creates the name.
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - emphasized: Bold (the selected player's own row or band).
    ///   - wraps: Wrap in full instead of scrolling.
    init(name: String, emphasized: Bool, wraps: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let font = Self.nameFont(emphasized: emphasized)
        let content: UIView
        if wraps {
            let label = UKLabel(name, wrapsToLayoutWidth: true)
            label.font = font
            content = label
        } else {
            let marquee = UKMarqueeLabel(name, font: font)
            content = marquee
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        // A wrapping label must measure the assigned column width, not its natural line width.
        let trailing = wraps
            ? content.trailingAnchor.constraint(equalTo: trailingAnchor)
            : content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), trailing,
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
    ///   - starsAfterScore: Draw the band footer's stars if the columns show them.
    ///   - probeNameWidth: Width of the widest unwrapped name, only for an offscreen sizing row.
    init(
        entry: LeaderboardEntry, isPlayer: Bool, columns: LeaderboardRowColumns?, currentSeason: Int?,
        chevron: Bool?, hint: String? = nil, separateParts: Bool = false, horizontalPadding: CGFloat = 12,
        starsAfterScore: Bool = false, probeNameWidth: CGFloat? = nil
    ) {
        isPlayerRow = isPlayer
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let accessibilitySize = UKFont.isAccessibilitySize(UITraitCollection.current)
        let stacksName = columns?.stacksName == true && !accessibilitySize && probeNameWidth == nil
        backgroundColor = isPlayer ? UIColor(red: 75 / 255, green: 15 / 255, blue: 99 / 255, alpha: 0.75) : .clear
        let name = SongLeaderboardEntryRow.displayName(entry)
        let rankText = SongLeaderboardEntryRow.spokenRank(entry.rank, isPlayer: isPlayer)

        let rank = UKLabel("#\(entry.rank.formatted())", style: .body, weight: isPlayer ? .bold : nil, monospacedDigit: true, lines: 1)
        rank.accessibilityLabel = rankText
        let rankSlot = UKLeaderboardColumnSlot(template: columns?.rankLabel, content: rank)
        let nameView = UKLeaderboardNameView(name: name, emphasized: isPlayer, wraps: accessibilitySize || stacksName)
        if let probeNameWidth {
            nameView.widthAnchor.constraint(equalToConstant: probeNameWidth).isActive = true
        }
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
        if starsAfterScore, columns?.showsStars == true, let stars = entry.stars, stars > 0 {
            let rating = UKStarRatingView(stars: stars)
            values.append(rating)
            if let label = rating.accessibilityLabel { spokenParts.append(label) }
        }
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
            head.alignment = .center
            let tail = UIStackView(arrangedSubviews: values)
            tail.axis = .vertical
            tail.alignment = .leading
            tail.spacing = 8
            line.addArrangedSubview(head)
            line.addArrangedSubview(tail)
        } else if stacksName {
            line.axis = .vertical
            line.spacing = SongLeaderboardEntryRow.stackedLineSpacing
            let tail = UIStackView(arrangedSubviews: [rankSlot, UIView()] + values)
            tail.alignment = .center
            tail.spacing = 8
            line.addArrangedSubview(nameView)
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
        let vertical = stacksName ? SongLeaderboardEntryRow.stackedVerticalPadding : (accessibilitySize ? 8 : 0)
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
            if stacksName { accessibilityElements = [rank, nameView] + values.map { $0 === scoreSlot ? score : $0 } }
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
