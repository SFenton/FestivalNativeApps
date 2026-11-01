#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Band section

/// One band size's leaderboard preview on Song Detail (``SongBandPreviewSection``): a title
/// with the ranked-band total, then up to ten band cards in one group card (the selected
/// player's band highlighted, or appended when outside the top ten), ending with "View Full
/// Leaderboard". All three sections share the page's one band read.
final class UKSongBandPreviewView: UIView {
    private let song: Song
    private let bandType: BandType
    private let context: UKContext
    private let onRetry: () -> Void
    private let titleLabel: UKLabel
    private let subtitleLabel = UKLabel(style: .subheadline)
    private let header = UIView()
    private let body = UIView()
    private var currentBody: UIView?

    /// The shared band read's state; setting it redraws the section.
    var state: SongBandPreviewState {
        didSet { render() }
    }

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - song: The song.
    ///   - bandType: The band size.
    ///   - state: The shared read's state.
    ///   - context: The page's context.
    ///   - onRetry: Re-reads the band previews after a failure.
    init(song: Song, bandType: BandType, state: SongBandPreviewState, context: UKContext, onRetry: @escaping () -> Void) {
        self.song = song
        self.bandType = bandType
        self.state = state
        self.context = context
        self.onRetry = onRetry
        titleLabel = UKLabel(bandType.label, style: .title3, weight: .bold)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        texts.axis = .vertical
        texts.spacing = 2
        texts.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(texts)
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: header.leadingAnchor), texts.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            texts.topAnchor.constraint(equalTo: header.topAnchor), texts.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        header.isAccessibilityElement = true
        header.accessibilityTraits = .header
        header.accessibilityIdentifier = "fst.song-detail.band-header.\(bandType.rawValue)"
        let stack = UIStackView(arrangedSubviews: [header, body])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "fst.song-detail.band.\(bandType.rawValue)"
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The header, for Quick Links' rotor.
    var headerElement: UIView { header }

    private func render() {
        var subtitle: String?
        if case let .loaded(response) = state { subtitle = SongDetailPlan.bandSubtitle(response, bandType: bandType) }
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        header.accessibilityLabel = [bandType.label, subtitle].compactMap { $0 }.joined(separator: ", ")
        let next: UIView
        switch state {
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Loading \(bandType.label) scores")
            loading.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            let holder = UIView()
            loading.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(loading)
            NSLayoutConstraint.activate([
                loading.leadingAnchor.constraint(equalTo: holder.leadingAnchor), loading.topAnchor.constraint(equalTo: holder.topAnchor),
                loading.bottomAnchor.constraint(equalTo: holder.bottomAnchor), loading.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
            ])
            next = holder
        case let .failed(message):
            let card = UKCardView(cornerRadius: 12)
            var configuration = UIButton.Configuration.plain()
            configuration.title = "Retry \(bandType.label) scores"
            configuration.baseForegroundColor = UKAccentText.blue
            configuration.contentInsets = .zero
            let retry = UIButton(configuration: configuration)
            retry.contentHorizontalAlignment = .leading
            retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            retry.accessibilityIdentifier = "fst.song-detail.band-retry.\(bandType.rawValue)"
            retry.addAction(UIAction { [weak self] _ in self?.onRetry() }, for: .primaryActionTriggered)
            let column = UIStackView(arrangedSubviews: [UKLabel("Band scores unavailable: \(message)"), retry])
            column.axis = .vertical
            column.spacing = 8
            card.embed(column, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
            next = card
        case let .loaded(response):
            next = rows(response.preview(for: bandType))
        }
        currentBody?.removeFromSuperview()
        next.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(next)
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: body.leadingAnchor), next.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            next.topAnchor.constraint(equalTo: body.topAnchor), next.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        currentBody = next
    }

    private func rows(_ preview: SongBandLeaderboardPreview) -> UIView {
        let displayed = Array(preview.entries.prefix(10))
        let footer = preview.footerEntry
        if displayed.isEmpty && footer == nil {
            let card = UKCardView(cornerRadius: 12)
            let text = UKLabel("When \(bandType.label) scores are submitted for this song, they will show up here on the next leaderboard update.")
            text.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            card.embed(text, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
            card.accessibilityIdentifier = "fst.song-detail.band-empty.\(bandType.rawValue)"
            return card
        }
        let section = UKGroupSectionView(rows: .flush(separatorInset: 12))
        var views: [UIView] = displayed.enumerated().map { index, entry in
            makeRow(entry, highlighted: preview.isSelected(entry), route: nil)
                .identified("fst.song-detail.band-row.\(bandType.rawValue).\(index)")
        }
        if let footer {
            views.append(makeRow(
                footer, highlighted: true,
                route: SongBandRowNavigation.previewRoute(for: footer, song: song, bandType: bandType, isAppended: true)
            ).identified("fst.song-detail.band-selected.\(bandType.rawValue)"))
        }
        section.setRows(views)
        section.setAction(UKPurpleActionButton(
            title: "View Full Leaderboard", card: bandType.label, identifier: "fst.song-detail.band-leaderboard.\(bandType.rawValue)"
        ) { [weak self] in
            guard let self else { return }
            self.context.navigator?.selectDetail(.songBandLeaderboard(self.song, bandType: self.bandType.rawValue))
        })
        return section
    }

    private func makeRow(_ entry: SongBandLeaderboardEntry, highlighted: Bool, route: AppRoute?) -> UKSongBandRowView {
        let row = UKSongBandRowView(entry: entry, highlighted: highlighted, route: route)
        row.onTap = { [weak self, route = row.route] in
            guard let navigator = self?.context.navigator else { return }
            if case .songBandLeaderboard = route { navigator.selectDetail(route) } else { navigator.push(route) }
        }
        return row
    }
}

// MARK: - Band row

/// One band score card (``SongBandPreviewRow``): each member's name and instruments, then
/// rank, team score, stars and accuracy, with a disclosure chevron centred on the card. The
/// whole card is one button (to Band Detail, or for the selected band's appended row, to its
/// place in the full board).
final class UKSongBandRowView: UIControl {
    /// Where a tap goes.
    let route: AppRoute
    /// Called on a tap.
    var onTap: (() -> Void)?
    private let isHighlightedBand: Bool

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - entry: The band score row.
    ///   - highlighted: The selected player's band.
    ///   - route: Tap destination; nil opens the band's page.
    init(entry: SongBandLeaderboardEntry, highlighted: Bool, route: AppRoute? = nil) {
        self.route = route ?? SongBandRowNavigation.bandRoute(entry)
        isHighlightedBand = highlighted
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = highlighted ? UIColor(red: 75 / 255, green: 15 / 255, blue: 99 / 255, alpha: 0.75) : .clear
        let accessibilitySize = UKFont.isAccessibilitySize(UITraitCollection.current)

        let members = UIStackView()
        members.axis = .vertical
        members.spacing = 4
        for member in entry.members {
            let name = UKLeaderboardNameView(name: member.resolvedName, emphasized: highlighted, wraps: accessibilitySize)
            name.isAccessibilityElement = false
            let icons = UIStackView(arrangedSubviews: member.chartedInstruments.map { UKInstrumentIconView($0, size: 22, hidesFromAccessibility: true) })
            icons.spacing = 4
            icons.setContentHuggingPriority(.required, for: .horizontal)
            icons.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = UIStackView(arrangedSubviews: [name, icons])
            line.spacing = 8
            line.alignment = .center
            members.addArrangedSubview(line)
        }

        let rank = UKLabel("#\(entry.rank.formatted())", style: .body, weight: highlighted ? .bold : nil, monospacedDigit: true)
        let score = UKLabel(entry.score.formatted(), style: .body, monospacedDigit: true, lines: 1)
        score.setContentCompressionResistancePriority(.required, for: .horizontal)
        var footerViews: [UIView] = [rank]
        if !accessibilitySize { footerViews.append(UIView()) }
        footerViews.append(score)
        if entry.stars > 0 { footerViews.append(UKStarRatingView(stars: entry.stars)) }
        let value = Double(entry.accuracy)
        let percent = "\(ScoreFormatting.accuracy(value))%"
        if let tint = try? ScoreFormatting.accuracyTint(value) {
            footerViews.append(UKAccuracyBadgeView(
                text: percent, spoken: percent, tint: entry.isFullCombo ? nil : tint, fullCombo: entry.isFullCombo,
                compact: !accessibilitySize, width: 72, identifier: nil
            ))
        }
        let footer = UIStackView(arrangedSubviews: footerViews)
        footer.axis = accessibilitySize ? .vertical : .horizontal
        footer.spacing = accessibilitySize ? 6 : 8
        footer.alignment = accessibilitySize ? .leading : .center

        let column = UIStackView(arrangedSubviews: [members, footer])
        column.axis = .vertical
        column.spacing = 8
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.tintColor = BrandUIColors.textMuted
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        let outer = UIStackView(arrangedSubviews: [column, chevron])
        outer.spacing = 8
        outer.alignment = .center
        outer.isUserInteractionEnabled = false
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 10), outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: LeaderboardRowMetrics.minHeight),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = SongBandPreviewText.spokenLabel(entry, selected: highlighted)
        accessibilityHint = SongBandRowNavigation.hint(for: self.route)
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            if isHighlightedBand { alpha = isHighlighted ? 0.8 : 1 } else {
                backgroundColor = isHighlighted ? UIColor.white.withAlphaComponent(0.1) : .clear
            }
        }
    }
}
#endif
