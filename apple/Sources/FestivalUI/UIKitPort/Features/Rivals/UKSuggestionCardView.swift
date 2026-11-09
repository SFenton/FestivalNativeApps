#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song row

/// One flat row inside a category's material card (``SuggestionSongRowView``): album art,
/// title and "artist · year", then the category's metadata. On a compact width the metadata
/// wraps to a right-aligned second line (web `twoRow`). One button element opening the song.
final class UKSuggestionSongRowView: UIControl {
    private let item: SuggestionSongItem
    private let session: FestivalSession
    private let categoryKey: String
    private let categoryInstrument: Instrument?
    private let currentSeason: Int?
    private let visibleInstruments: Set<Instrument>
    private var content: UIView?
    /// Called when pressed.
    var onSelect: (() -> Void)?

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - item: The suggestion.
    ///   - session: The session (artwork caches, the player's scores).
    ///   - categoryKey: The category's key, choosing the metadata layout.
    ///   - categoryInstrument: The category's own instrument.
    ///   - currentSeason: Effective current season, highlighted on season pills.
    ///   - visibleInstruments: Settings-visible charts for the status chips.
    init(
        item: SuggestionSongItem, session: FestivalSession, categoryKey: String, categoryInstrument: Instrument?,
        currentSeason: Int?, visibleInstruments: Set<Instrument>
    ) {
        self.item = item
        self.session = session
        self.categoryKey = categoryKey
        self.categoryInstrument = categoryInstrument
        self.currentSeason = currentSeason
        self.visibleInstruments = visibleInstruments
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "fst.suggestions.row.\(item.id)"
        accessibilityTraits = .button
        isAccessibilityElement = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .touchUpInside)
        rebuild()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitHorizontalSizeClass.self]) { (self: UKSuggestionSongRowView, _) in
            self.rebuild()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    private var layout: SuggestionRowLayout { SuggestionRowLayout.forCategory(categoryKey) }
    private var rowInstrument: Instrument? { item.instrument ?? categoryInstrument }
    private var showsStars: Bool { SuggestionRowLayout.showsStars(categoryKey: categoryKey) && (item.stars ?? 0) > 0 }

    private var subtitle: String {
        [item.song.artist, item.song.year.map(String.init)].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func rebuild() {
        content?.removeFromSuperview()
        let accessibilitySize = UKFont.isAccessibilitySize(traitCollection)
        let (metadata, spoken) = makeMetadata()
        let info = songInfo()
        let stacked = layout.stacksMetadata(
            regularWidth: traitCollection.horizontalSizeClass == .regular, accessibilitySize: accessibilitySize, showsStars: showsStars
        )
        let root: UIStackView
        if stacked, let metadata {
            root = UIStackView(arrangedSubviews: [info, metadata])
            root.axis = .vertical
            root.spacing = 6
            root.alignment = .trailing
            info.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        } else {
            root = UIStackView(arrangedSubviews: [info] + (metadata.map { [$0] } ?? []))
            root.axis = .horizontal
            root.spacing = 12
            root.alignment = .center
        }
        root.isUserInteractionEnabled = false
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        root.ukPin(to: self)
        content = root
        ukFlattenAccessibility()
        accessibilityLabel = ([item.song.title, subtitle] + spoken).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func songInfo() -> UIView {
        let art = UKArtworkTileView(size: 44)
        art.configure(raw: item.song.albumArt, session: session)
        let group = UKMarqueeSyncGroup()
        let title = UKMarqueeLabel(item.song.title, font: UKFont.font(.subheadline, weight: .semibold))
        let artist = UKMarqueeLabel(subtitle, font: UKFont.font(.caption1))
        title.syncGroup = group
        artist.syncGroup = group
        let column = UIStackView(arrangedSubviews: [title, artist])
        column.axis = .vertical
        column.spacing = 2
        let row = UIStackView(arrangedSubviews: [art, column])
        row.spacing = 12
        row.alignment = .center
        return row
    }

    /// The category's metadata view and the words it adds to the row's spoken label.
    private func makeMetadata() -> (UIView?, [String]) {
        let songId = item.song.songId
        switch layout {
        case .hidden:
            return (nil, [])
        case .rival:
            var views: [UIView] = []
            var spoken: [String] = []
            let showsRivalName = SuggestionRowLayout.showsRivalName(categoryKey: categoryKey)
            if showsRivalName, let rivalName = item.rivalName {
                views.append(rivalBadge(rivalName))
                spoken.append(rivalName)
            }
            if let delta = item.rivalRankDelta, delta != 0 {
                let label = UKLabel(delta > 0 ? "+\(delta)" : "\(delta)", style: .footnote, weight: .bold, monospacedDigit: true, color: UKRivalStatusPill.readable(delta > 0 ? BrandUIColors.statusGreen : BrandUIColors.statusRed), lines: 1)
                label.setContentHuggingPriority(.required, for: .horizontal)
                views.append(label)
                spoken.append(SuggestionRowLayout.rivalDeltaAccessibilityLabel(delta: delta, rivalName: showsRivalName ? nil : item.rivalName))
            }
            if let icon = instrumentIcon() { views.append(icon); spoken.append(rowInstrument?.label ?? "") }
            return (row(views), spoken)
        case .unfcAccuracy:
            guard let accuracy = SuggestionRowLayout.unfcAccuracy(percent: item.percent) else { return (nil, []) }
            let field = SongMetadataField.accuracy(accuracy, fullCombo: false, percentageVisible: true, tint: try? ScoreFormatting.accuracyTint(accuracy))
            return (
                UKSongMetadataFieldView(
                    field: field, traits: traitCollection,
                    accessibilityIdentifier: "fst.songs.metadata.\(field.id.rawValue).\(songId)"
                ),
                [field.announcement]
            )
        case .season:
            guard let season = seasonAchieved, season > 0 else { return (nil, []) }
            let field = SongMetadataField.season(season, current: season == currentSeason)
            return (
                UKSongMetadataFieldView(
                    field: field, traits: traitCollection,
                    accessibilityIdentifier: "fst.songs.metadata.\(field.id.rawValue).\(songId)"
                ),
                [field.announcement]
            )
        case .percentile:
            var views: [UIView] = []
            var spoken: [String] = []
            if let display = item.percentileDisplay {
                let field = SongMetadataField.percentile(display, tier: Self.tier(display))
                views.append(
                    UKSongMetadataFieldView(
                        field: field, traits: traitCollection,
                        accessibilityIdentifier: "fst.songs.metadata.\(field.id.rawValue).\(songId)"
                    )
                )
                spoken.append(field.announcement)
            }
            if let icon = instrumentIcon() { views.append(icon); spoken.append(rowInstrument?.label ?? "") }
            return (row(views), spoken)
        case .singleInstrument:
            var views: [UIView] = []
            var spoken: [String] = []
            if showsStars, let stars = item.stars {
                let rating = UKStarRatingView(stars: stars, size: 18)
                rating.accessibilityLabel = stars >= 6 ? "5 gold stars" : "\(stars) stars"
                views.append(rating)
                spoken.append(rating.accessibilityLabel ?? "")
            }
            if let icon = instrumentIcon() { views.append(icon); spoken.append(rowInstrument?.label ?? "") }
            return (row(views), spoken)
        case .instrumentChips:
            let badges = SongInstrumentStatusPolicy.badges(
                for: item.song, visibleInstruments: visibleInstruments, scores: session.selectedPlayerScores[songId] ?? [:]
            )
            let chips = UKSongStatusChipsView(
                badges: badges, keyboard: item.song.usesKeyboardIcon, traits: traitCollection,
                accessibilityIdentifier: "fst.songs.instrument-status.\(songId)"
            )
            return (chips, [badges.map(\.announcement).joined(separator: "; ")])
        }
    }

    private func row(_ views: [UIView]) -> UIView? {
        guard !views.isEmpty else { return nil }
        let stack = UIStackView(arrangedSubviews: views)
        stack.spacing = 8
        stack.alignment = .center
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private func instrumentIcon() -> UIView? {
        guard let rowInstrument else { return nil }
        return UKInstrumentIconView(rowInstrument, size: 28)
    }

    private var seasonAchieved: Int? {
        let scores = session.selectedPlayerScores[item.song.songId] ?? [:]
        if let rowInstrument { return scores[rowInstrument]?.season }
        return scores.values.compactMap(\.season).max()
    }

    /// Web `PercentilePill` auto tier: gold italic for Top 1%, gold for Top 5%.
    static func tier(_ display: String) -> SongPercentileTier {
        SuggestionSongRowView.tier(display)
    }

    /// A rival category's badge: the name (truncated past 12 characters) in a blue capsule.
    private func rivalBadge(_ name: String) -> UIView {
        let blue = UIColor(red: 66 / 255, green: 133 / 255, blue: 244 / 255, alpha: 1)
        let label = UKLabel(name.count > 12 ? "\(name.prefix(11))\u{2026}" : name, style: .caption2, weight: .semibold, color: blue, lines: 1)
        label.accessibilityLabel = name
        let holder = UIView()
        holder.backgroundColor = blue.withAlphaComponent(0.2)
        holder.layer.cornerRadius = 8
        holder.layer.cornerCurve = .continuous
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: holder.topAnchor, constant: 4), label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -4),
        ])
        holder.setContentHuggingPriority(.required, for: .horizontal)
        return holder
    }
}

// MARK: - Category card

/// One ``SuggestionCategory`` as a titled material card (``SuggestionCategoryCardView``):
/// the title, description and (for a single-instrument category) its instrument icon above
/// the card, the song rows flat inside it.
final class UKSuggestionCardView: UIView {
    /// Creates the card.
    ///
    /// - Parameters:
    ///   - category: The category.
    ///   - context: The page's context (session, navigation).
    ///   - currentSeason: Effective current season.
    ///   - visibleInstruments: Settings-visible charts.
    init(category: SuggestionCategory, context: UKContext, currentSeason: Int?, visibleInstruments: Set<Instrument>) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let categoryInstrument = SuggestionRowLayout.categoryInstrument(category.key)
        let header = UKSectionHeaderView(category.title, subtitle: category.description)
        let top = UIStackView(arrangedSubviews: [header])
        top.spacing = 12
        top.alignment = .top
        if let categoryInstrument {
            top.addArrangedSubview(UKInstrumentIconView(categoryInstrument, size: 36, hidesFromAccessibility: true))
        }
        let topHolder = UIView()
        top.translatesAutoresizingMaskIntoConstraints = false
        topHolder.addSubview(top)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: topHolder.leadingAnchor, constant: 4), top.trailingAnchor.constraint(equalTo: topHolder.trailingAnchor, constant: -4),
            top.topAnchor.constraint(equalTo: topHolder.topAnchor), top.bottomAnchor.constraint(equalTo: topHolder.bottomAnchor),
        ])
        let group = UKGroupSectionView()
        group.setRows(category.songs.map { item in
            let row = UKSuggestionSongRowView(
                item: item, session: context.session, categoryKey: category.key, categoryInstrument: categoryInstrument,
                currentSeason: currentSeason, visibleInstruments: visibleInstruments
            )
            row.onSelect = { [weak navigator = context.navigator] in navigator?.push(.songDetail(item.song)) }
            return row
        })
        let stack = UIStackView(arrangedSubviews: [topHolder, group])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.ukPin(to: self)
        accessibilityIdentifier = "fst.suggestions.category.\(category.key)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
