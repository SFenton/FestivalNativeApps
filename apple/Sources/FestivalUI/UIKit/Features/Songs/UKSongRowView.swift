#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Row inputs

/// Everything one Songs (or Item Shop) row draws from: the SwiftUI row's initializer, as a value.
struct UKSongRowInput {
    var song: Song
    var instrument: Instrument?
    var session: FestivalSession
    var highContrast = false
    var shopHighlight: ShopHighlight?
    var inShop = false
    var profileChart: Instrument?
    var catalogueObservation: Int?
    var metadata = SongMetadataVisibility()
    var fieldOrder = MetadataField.defaultSongRowOrder
    var invalidScoreLeeway: Double?
    var overThresholdCharts: Set<Instrument> = []
    var showInstrumentIcons = true
    var visibleInstruments = Set(Instrument.allCases)
    var currentSeason: Int?
    var shopOffer: SongRowShopOffer?
    var allowsProfilePanel = false
    var profilePanelFoldBand: HingeBand?
    var allowsArtwork = true
    var showsProfile = true

    /// The shared decisions for this row.
    @MainActor var presentation: SongRowPresentation {
        SongRowPresentation(
            song: song, instrument: instrument, session: session, profileChart: profileChart,
            catalogueObservation: catalogueObservation, metadata: metadata, invalidScoreLeeway: invalidScoreLeeway,
            overThresholdCharts: overThresholdCharts, showInstrumentIcons: showInstrumentIcons,
            visibleInstruments: visibleInstruments, currentSeason: currentSeason, isShopRow: shopOffer != nil,
            fieldOrder: fieldOrder, showsProfile: showsProfile
        )
    }
}

// MARK: - Title and subtitle

/// The row's title and "artist · year · duration" lines: plain labels that become a
/// marquee only when a line overflows (a marquee renders its text to an image, which a
/// scrolling list should not pay for on every row), wrapping at accessibility sizes.
final class UKSongInfoView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var titleMarquee: UKMarqueeLabel?
    private var subtitleMarquee: UKMarqueeLabel?
    private let syncGroup = UKMarqueeSyncGroup()
    private var titleWidth: CGFloat = 0
    private var subtitleWidth: CGFloat = 0
    private var wraps = false
    private var displayScale: CGFloat = 1
    private let lineSpacing: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        for label in [titleLabel, subtitleLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.textColor = BrandUIColors.textPrimary
            label.isAccessibilityElement = false
            addSubview(label)
        }
        titleLabel.font = UKFont.font(.headline)
        subtitleLabel.font = UKFont.font(.subheadline)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the lines and their sizing on the destination display.
    func configure(title: String, subtitle: String, wraps: Bool, displayScale: CGFloat) {
        self.wraps = wraps
        self.displayScale = max(1, displayScale)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        titleLabel.numberOfLines = wraps ? 0 : 1
        subtitleLabel.numberOfLines = wraps ? 0 : 1
        titleLabel.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        subtitleLabel.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        titleWidth = wraps ? 0 : ceil((title as NSString).size(withAttributes: [.font: titleLabel.font as Any]).width)
        subtitleWidth = wraps ? 0 : ceil((subtitle as NSString).size(withAttributes: [.font: subtitleLabel.font as Any]).width)
        titleMarquee?.isHidden = true
        subtitleMarquee?.isHidden = true
        titleLabel.isHidden = false
        subtitleLabel.isHidden = false
        setNeedsLayout()
    }

    /// The height at `width`.
    func height(forWidth width: CGFloat) -> CGFloat {
        lineHeight(of: titleLabel, forWidth: width) + lineSpacing + lineHeight(of: subtitleLabel, forWidth: width)
    }

    private func lineHeight(of label: UILabel, forWidth width: CGFloat) -> CGFloat {
        if wraps {
            return ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        }
        return ceil(label.font.lineHeight * displayScale) / displayScale
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let titleHeight = lineHeight(of: titleLabel, forWidth: width)
        let subtitleHeight = lineHeight(of: subtitleLabel, forWidth: width)
        let titleFrame = CGRect(x: 0, y: 0, width: width, height: titleHeight)
        let subtitleFrame = CGRect(x: 0, y: titleHeight + lineSpacing, width: width, height: subtitleHeight)
        titleLabel.frame = titleFrame
        subtitleLabel.frame = subtitleFrame
        guard !wraps, width > 0, !UKAccessibility.reduceMotion else { return }
        updateMarquee(&titleMarquee, label: titleLabel, natural: titleWidth, frame: titleFrame, width: width)
        updateMarquee(&subtitleMarquee, label: subtitleLabel, natural: subtitleWidth, frame: subtitleFrame, width: width)
    }

    private func updateMarquee(_ marquee: inout UKMarqueeLabel?, label: UILabel, natural: CGFloat, frame: CGRect, width: CGFloat) {
        guard natural > width else {
            marquee?.isHidden = true
            label.isHidden = false
            return
        }
        let view: UKMarqueeLabel
        if let existing = marquee {
            view = existing
            view.text = label.text ?? ""
            view.font = label.font
        } else {
            view = UKMarqueeLabel(label.text ?? "", font: label.font, color: BrandUIColors.textPrimary)
            view.translatesAutoresizingMaskIntoConstraints = true
            view.isAccessibilityElement = false
            view.syncGroup = syncGroup
            addSubview(view)
            marquee = view
        }
        view.frame = frame
        view.isHidden = false
        label.isHidden = true
    }
}

// MARK: - Row view

/// The Songs/Shop row's content, laid out by hand inside the card (the port's counterpart of
/// ``SongRowView``): art, title lines, profile content, Shop icons and the wide-row profile
/// panel. Measuring and placing share one plan, so a self-sizing cell costs no Auto Layout.
final class UKSongRowView: UIView {
    /// Illustrative guide content only; no selected-player state or saved visual order.
    enum GuideExample {
        case instrumentIcons([SongInstrumentBadge])
        case metadata(score: Int, fields: [SongMetadataField])
    }

    /// Horizontal padding inside the card.
    static let padH: CGFloat = 12
    /// Vertical padding inside the card.
    static let padV: CGFloat = 10
    private static let artSize: CGFloat = 44
    private static let gap: CGFloat = 12

    private let art = UKArtworkTileView(size: 44)
    private let info = UKSongInfoView()
    private let chartLabel = UILabel()
    private let statusLabel = UILabel()
    private let statusSymbol = UIImageView()
    private var dynamicViews: [UIView] = []
    private(set) var input: UKSongRowInput?
    private var plan: Plan?
    private var pieces: Pieces = Pieces()
    private var isAX = false
    /// The traits the row lays out for: the collection view's, since a cell is configured before it is attached.
    private var layoutTraits = UITraitCollection.current

    /// What the current configuration put in the row, for layout and accessibility.
    private struct Pieces {
        var kind: Kind = .plain
        var presentation: SongRowPresentation?
        var chips: UKSongStatusChipsView?
        var flow: UKSongMetadataFlowView?
        var primary: UKSongMetadataFieldView?
        var meter: UKDifficultyMeterView?
        var glyph: UIImageView?
        var bag: UIImageView?
        var badge: UIView?
        var leaving: UIImageView?
        var chevron: UIImageView?
        var marker: UIView?
        var bagSlot: UIView?
        var panel: UKSongProfilePanelView?
        var panelTiles: [SongProfilePanelTile] = []
        var invalid: InvalidScoreWarning?
        var parts: [String] = []
        var statusText: String?
        var statusIdentifier: String?
        var chartCaption: String?
        var shopOffer: SongRowShopOffer?
    }

    private enum Kind { case plain, plainAX, structured, panel, shop, shopAX }

    private struct Plan {
        var width: CGFloat
        var height: CGFloat
        var frames: [(UIView, CGRect)]
    }

    /// The warning the invalid-score glyph explains, if the row drew one.
    var invalidWarning: InvalidScoreWarning? { pieces.invalid }
    /// The glyph's frame in the row's coordinates.
    var invalidGlyphFrame: CGRect? { pieces.glyph?.frame }
    /// The profile panel's tile frames in the row's coordinates.
    var panelCards: [(id: String, label: String, frame: CGRect)] {
        guard let panel = pieces.panel else { return [] }
        return zip(pieces.panelTiles, panel.cardFrames).map { ($0.id, $0.announcement, panel.convert($1, to: self)) }
    }
    /// The Item Shop bag action's slot in the row's coordinates.
    var bagSlotFrame: CGRect? { pieces.bagSlot?.frame }
    /// The words the combined row speaks, in reading order.
    var spokenParts: [String] { pieces.parts }

    override init(frame: CGRect) {
        super.init(frame: frame)
        chartLabel.font = UKFont.font(.caption1)
        statusLabel.font = UKFont.font(.footnote)
        for label in [chartLabel, statusLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.textColor = BrandUIColors.textPrimary
            label.numberOfLines = 0
            label.isAccessibilityElement = false
        }
        statusLabel.adjustsFontForContentSizeCategory = false
        statusLabel.lineBreakMode = .byWordWrapping
        statusSymbol.contentMode = .center
        statusSymbol.isAccessibilityElement = false
        for view in [art, info, chartLabel, statusLabel, statusSymbol] { addSubview(view) }
        art.translatesAutoresizingMaskIntoConstraints = true
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Configure

    /// Fills the row.
    ///
    /// - Parameters:
    ///   - input: The row's inputs.
    ///   - width: The row card's width (decides the wide split row).
    ///   - traits: The traits the row is rendered with.
    ///   - guideExample: Sample values for an inert guide; does not read player scores.
    func configure(
        _ input: UKSongRowInput, width: CGFloat, traits: UITraitCollection? = nil, guideExample: GuideExample? = nil
    ) {
        self.input = input
        layoutTraits = traits ?? (window == nil ? layoutTraits : traitCollection)
        plan = nil
        dynamicViews.forEach { $0.removeFromSuperview() }
        dynamicViews = []
        pieces = Pieces()
        isAX = layoutTraits.preferredContentSizeCategory.isAccessibilityCategory
        let song = input.song
        art.configure(raw: input.allowsArtwork ? song.albumArt : nil, session: input.session)
        chartLabel.isHidden = true
        statusLabel.isHidden = true
        statusSymbol.isHidden = true
        statusSymbol.image = nil
        if let guideExample {
            configureGuide(guideExample, song: song)
            setNeedsLayout()
            return
        }
        let presentation = input.presentation
        pieces.presentation = presentation
        info.configure(title: song.title, subtitle: presentation.subtitle, wraps: isAX, displayScale: layoutTraits.displayScale)
        pieces.invalid = presentation.invalidScoreWarning
        var parts = [song.title, presentation.subtitle]
        let traits = layoutTraits

        if let offer = input.shopOffer {
            pieces.kind = isAX ? .shopAX : .shop
            pieces.shopOffer = offer
            buildShopOffer(offer, song: song, parts: &parts)
        } else {
            let panel = Self.profilePanel(input: input, presentation: presentation, rowWidth: width - 2 * Self.padH, isAX: isAX)
            if let panel {
                pieces.kind = .panel
                pieces.panelTiles = panel.tiles
                let view = UKSongProfilePanelView(
                    songId: song.songId, tiles: panel.tiles, arrangement: panel.arrangement,
                    keyboard: song.usesKeyboardIcon, highContrast: input.highContrast, traits: traits
                )
                pieces.panel = view
                addDynamic(view)
                if presentation.usesInstrumentChips { buildProfileContent(presentation, song: song, parts: &parts) }
                buildTrailing(input: input, presentation: presentation, song: song, parts: &parts, includeMeter: false)
            } else if let structured = presentation.structuredFields, case let .success(fields) = structured {
                pieces.kind = .structured
                if let chart = presentation.structuredScore?.chart, chart != .lead {
                    chartLabel.text = "\(chart.label) chart"
                    chartLabel.isHidden = false
                    pieces.chartCaption = "\(chart.label) chart"
                    parts.append("\(chart.label) chart")
                }
                if let primary = fields.first {
                    let view = UKSongMetadataFieldView(field: primary, traits: traits)
                    pieces.primary = view
                    addDynamic(view)
                    parts.append(primary.announcement)
                }
                if fields.count > 1 {
                    let rest = Array(fields.dropFirst())
                    let flow = UKSongMetadataFlowView(fields: rest, traits: traits, leading: false)
                    pieces.flow = flow
                    addDynamic(flow)
                    parts.append(contentsOf: rest.map(\.announcement))
                }
                buildGlyphAndShop(input: input, presentation: presentation, song: song, parts: &parts)
            } else {
                buildProfileContent(presentation, song: song, parts: &parts)
                pieces.kind = isAX && (presentation.usesInstrumentChips || !statusSymbol.isHidden) ? .plainAX : .plain
                buildTrailing(input: input, presentation: presentation, song: song, parts: &parts, includeMeter: true)
            }
        }
        pieces.parts = parts
        setNeedsLayout()
    }

    private func configureGuide(_ example: GuideExample, song: Song) {
        let subtitle = [song.artist, song.year.map(String.init), song.formattedDuration]
            .compactMap { $0 }.joined(separator: " · ")
        info.configure(title: song.title, subtitle: subtitle, wraps: isAX, displayScale: layoutTraits.displayScale)
        pieces.kind = isAX ? .plainAX : .plain
        switch example {
        case let .instrumentIcons(badges):
            let chips = UKSongStatusChipsView(badges: badges, keyboard: song.usesKeyboardIcon, traits: layoutTraits)
            pieces.chips = chips
            addDynamic(chips)
        case let .metadata(score, fields):
            let primary = UKSongMetadataFieldView(field: .score(score), traits: layoutTraits)
            let flow = UKSongMetadataFlowView(fields: fields, traits: layoutTraits, leading: false)
            pieces.primary = primary
            pieces.flow = flow
            addDynamic(primary)
            addDynamic(flow)
        }
    }

    private func addDynamic(_ view: UIView) {
        dynamicViews.append(view)
        addSubview(view)
    }

    // MARK: Pieces

    private func buildProfileContent(_ presentation: SongRowPresentation, song: Song, parts: inout [String]) {
        switch presentation.profileContent {
        case .none:
            break
        case .pausedPlayer:
            setStatus("Player scores paused until songs update", symbol: "pause.circle", gold: true, id: "fst.songs.profile-paused-row.\(song.songId)", parts: &parts)
        case let .chips(badges):
            let chips = UKSongStatusChipsView(badges: badges, keyboard: song.usesKeyboardIcon, traits: layoutTraits)
            pieces.chips = chips
            addDynamic(chips)
            parts.append(chips.announcement)
        case let .summary(player, chart, chartAvailable, score, state):
            let line = SongProfileSummaryText.line(
                player: player, chart: chart, chartAvailable: chartAvailable, score: score, state: state,
                visibility: input?.metadata ?? SongMetadataVisibility()
            )
            setStatus(line.text, symbol: line.symbol, gold: line.gold, id: "fst.songs.profile-summary.\(song.songId)", parts: &parts)
        case let .bandLoading(name):
            setStatus("Loading \(name)'s scores", symbol: "hourglass", gold: false, id: "fst.songs.band-summary.\(song.songId)", parts: &parts)
        case .bandFailed:
            setStatus("Band scores unavailable", symbol: "exclamationmark.triangle", gold: true, id: "fst.songs.band-summary.\(song.songId)", parts: &parts)
        case .bandPaused:
            setStatus("Band scores paused until songs update", symbol: "pause.circle", gold: true, id: "fst.songs.profile-paused-row.\(song.songId)", parts: &parts)
        case let .bandFields(fields):
            let flow = UKSongMetadataFlowView(fields: fields, traits: layoutTraits, leading: false)
            pieces.flow = flow
            addDynamic(flow)
            parts.append(contentsOf: fields.map(\.announcement))
        }
    }

    private func setStatus(_ text: String, symbol: String?, gold: Bool, id: String, parts: inout [String]) {
        let color = gold ? BrandUIColors.gold : BrandUIColors.textPrimary
        layoutTraits.performAsCurrent { statusLabel.font = UKFont.font(.footnote) }
        if let symbol {
            let configuration = UIImage.SymbolConfiguration(font: statusLabel.font, scale: .large)
            statusSymbol.image = UIImage(systemName: symbol, withConfiguration: configuration)
            statusSymbol.tintColor = color
            statusSymbol.isHidden = statusSymbol.image == nil
        }
        statusLabel.textColor = color
        if UKFont.isAccessibilitySize(layoutTraits) {
            statusLabel.text = text
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = UKFont.swiftUILeading(.footnote, traits: layoutTraits).lineSpacing
            paragraph.lineBreakStrategy = .pushOut
            statusLabel.attributedText = NSAttributedString(
                string: text, attributes: [.font: statusLabel.font, .foregroundColor: color, .paragraphStyle: paragraph]
            )
        }
        statusLabel.isHidden = false
        pieces.statusText = text
        pieces.statusIdentifier = id
        parts.append(text)
    }

    private func buildTrailing(
        input: UKSongRowInput, presentation: SongRowPresentation, song: Song, parts: inout [String], includeMeter: Bool
    ) {
        if includeMeter, input.metadata.intensity, presentation.selectedPlayer != nil, let instrument = input.instrument,
           presentation.structuredScore == nil, let difficulty = song.difficulty?.chartedValue(for: instrument) {
            let meter = UKDifficultyMeterView(level: difficulty, raw: true)
            meter.translatesAutoresizingMaskIntoConstraints = true
            pieces.meter = meter
            addDynamic(meter)
            parts.append(DifficultyMeter.accessibilityLabel(level: difficulty, raw: true))
        }
        buildGlyphAndShop(input: input, presentation: presentation, song: song, parts: &parts)
    }

    private func buildGlyphAndShop(input: UKSongRowInput, presentation: SongRowPresentation, song: Song, parts: inout [String]) {
        if let warning = pieces.invalid {
            let side = UKFont.scaled(28, relativeTo: .body, traits: layoutTraits)
            let image = UIImage(systemName: InvalidScoreGlyph.symbol(for: warning))
            let view = UIImageView(image: image)
            view.tintColor = warning.isOverThreshold ? BrandUIColors.gold : BrandUIColors.statusRed
            view.contentMode = .scaleAspectFit
            view.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            pieces.glyph = view
            addDynamic(view)
            if !UKAccessibility.reduceMotion, !DebugAnimationOverride.stillBackground, #available(iOS 17.0, *) {
                view.addSymbolEffect(.pulse, options: .repeating)
            }
        }
        guard input.inShop else { return }
        let bag = UIImageView(image: UIImage(
            systemName: "bag.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.font(.subheadline))
        ))
        bag.tintColor = BrandUIColors.textPrimary
        bag.contentMode = .scaleAspectFit
        pieces.bag = bag
        addDynamic(bag)
        parts.append("In the Item Shop")
        switch input.shopHighlight {
        case .new:
            let marker = UIView()
            pieces.marker = marker
            addDynamic(marker)
            parts.append("Item Shop: \(ShopHighlight.new.label)")
        case .leavingTomorrow:
            let clock = Self.leavingClock()
            pieces.leaving = clock
            addDynamic(clock)
            parts.append("Item Shop: \(ShopHighlight.leavingTomorrow.label)")
        case nil:
            break
        }
    }

    private func buildShopOffer(_ offer: SongRowShopOffer, song: Song, parts: inout [String]) {
        if offer.highlight == .leavingTomorrow {
            let clock = Self.leavingClock()
            pieces.leaving = clock
            addDynamic(clock)
            parts.append(ShopHighlight.leavingTomorrow.label)
        }
        if offer.highlight == .new {
            let marker = UIView()
            pieces.marker = marker
            addDynamic(marker)
            parts.append(ShopHighlight.new.label)
        }
        if offer.reservesBag {
            let slot = UIView()
            pieces.bagSlot = slot
            addDynamic(slot)
        }
        if offer.navigable {
            let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
            chevron.tintColor = BrandUIColors.textMuted
            chevron.contentMode = .center
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
            pieces.chevron = chevron
            addDynamic(chevron)
        }
    }

    /// The red Leaving Tomorrow clock circle.
    private static func leavingClock() -> UIImageView {
        let circle = UIImageView(image: UIImage(
            systemName: "clock", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.font(.subheadline))
        ))
        circle.tintColor = BrandUIColors.textPrimary
        circle.contentMode = .center
        circle.backgroundColor = BrandUIColors.statusRed
        circle.clipsToBounds = true
        return circle
    }

    /// The clock fills its scaled symbol's bounds, with the shared minimum at smaller sizes.
    private static func leavingSize(_ clock: UIImageView) -> CGSize {
        let symbol = clock.image?.size ?? .zero
        let side = max(ShopLeavingIndicator.minimumSide, symbol.width, symbol.height)
        return CGSize(width: side, height: side)
    }

    /// The wide split row's cards and arrangement, or nil for the plain row.
    private static func profilePanel(
        input: UKSongRowInput, presentation: SongRowPresentation, rowWidth: CGFloat, isAX: Bool
    ) -> (tiles: [SongProfilePanelTile], arrangement: SongProfilePanelPolicy.Arrangement)? {
        let session = input.session
        let band = presentation.selectedBand
        guard SongProfilePanelPolicy.allows(
            allowed: input.allowsProfilePanel, hasSelectedProfile: band != nil || presentation.selectedPlayer != nil,
            scoresCurrent: band != nil ? presentation.bandScoreDataCurrent : presentation.scoreDataCurrent,
            accessibilitySize: isAX, shopRow: input.shopOffer != nil, rowWidth: rowWidth + 24
        ) else { return nil }
        let order = presentation.fieldOrder
        let tiles: [SongProfilePanelTile]?
        if let band {
            tiles = try? SongProfilePanelPolicy.bandTiles(
                band: band, entry: session.selectedBandScores[input.song.songId],
                currentSeason: input.currentSeason, visibility: input.metadata, order: order
            )
        } else {
            tiles = try? SongProfilePanelPolicy.tiles(
                song: input.song, scores: presentation.playerScores.scores, instrumentFilter: input.instrument,
                visibleInstruments: input.visibleInstruments, currentSeason: input.currentSeason,
                visibility: input.metadata, order: order
            )
        }
        let scale = UIFontMetrics(forTextStyle: .body).scaledValue(for: 1)
        guard let tiles, !tiles.isEmpty,
              let arrangement = SongProfilePanelPolicy.arrangement(
                  width: SongProfilePanelPolicy.panelWidth(contentWidth: rowWidth, band: input.profilePanelFoldBand),
                  tiles: tiles,
                  overview: band != nil || input.instrument == nil, scale: scale
              ) else { return nil }
        return (tiles, arrangement)
    }

    // MARK: Layout

    /// The row card's height at `width`.
    func height(forWidth width: CGFloat) -> CGFloat { plan(width: width).height }

    private func plan(width: CGFloat) -> Plan {
        if let plan, plan.width == width { return plan }
        let next = computePlan(width: width)
        plan = next
        return next
    }

    private func computePlan(width: CGFloat) -> Plan {
        let content = max(0, width - 2 * Self.padH)
        var frames: [(UIView, CGRect)] = []
        let art = Self.artSize
        var contentHeight: CGFloat = art
        func hide(_ views: UIView?...) { views.compactMap { $0 }.forEach { frames.append(($0, .zero)) } }
        func size(_ view: UIView?, max width: CGFloat) -> CGSize {
            guard let view else { return .zero }
            if let flow = view as? UKSongMetadataFlowView { return CGSize(width: width, height: flow.height(forWidth: width)) }
            if let chips = view as? UKSongStatusChipsView { return CGSize(width: width, height: chips.height(forWidth: width)) }
            if let field = view as? UKSongMetadataFieldView { return field.fittedSize(maxWidth: width) }
            if view === pieces.meter { return CGSize(width: 62, height: 20) }
            if let glyph = view as? UIImageView, glyph === pieces.glyph {
                let side = glyph.bounds.width
                return CGSize(width: side, height: side)
            }
            return view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        }
        func placeStatus(x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
            let symbol = statusSymbol.image?.size ?? .zero
            // Match the compact native Label column. The AX stack uses only the symbol's width.
            let symbolWidth = symbol.width == 0 ? 0 : (isAX ? symbol.width : max(24, symbol.width))
            let indent = symbolWidth == 0 ? 0 : symbolWidth + (isAX ? 8 : 16)
            let labelWidth = max(0, width - indent)
            let fittedHeight = statusLabel.sizeThatFits(CGSize(width: labelWidth, height: .greatestFiniteMagnitude)).height
            let displayScale = max(1, layoutTraits.displayScale)
            let labelHeight = isAX ? ceil(fittedHeight) : ceil(fittedHeight * displayScale) / displayScale
            let firstLineHeight = isAX ? max(statusLabel.font.lineHeight, symbol.height) : statusLabel.font.lineHeight
            let labelTop = (firstLineHeight - statusLabel.font.lineHeight) / 2
            let height = max(firstLineHeight, labelTop + labelHeight)
            if symbolWidth > 0 {
                frames.append((statusSymbol, CGRect(x: x, y: y, width: symbolWidth, height: isAX ? firstLineHeight : height)))
            }
            frames.append((statusLabel, CGRect(x: x + indent, y: y + labelTop, width: labelWidth, height: labelHeight)))
            return height
        }
        switch pieces.kind {
        case .shop, .shopAX:
            let trailing = shopTrailing()
            let stacked = pieces.kind == .shopAX
            let infoX = stacked ? 0 : art + Self.gap
            // The compact row keeps both stack gaps around its minimum-width spacer.
            let reserve = trailing.items.isEmpty ? Self.gap + 4 : 2 * Self.gap + 4 + trailing.width
            let infoWidth = stacked ? content : max(0, content - infoX - reserve)
            let infoHeight = info.height(forWidth: infoWidth)
            let artworkLineHeight = max(art, trailing.items.map(\.1.height).max() ?? 0)
            let y = stacked ? infoHeight + Self.gap : 0
            let lineHeight = stacked ? artworkLineHeight : max(artworkLineHeight, infoHeight)
            let centerY = y + lineHeight / 2
            frames.append((self.art, CGRect(x: 0, y: centerY - art / 2, width: art, height: art)))
            frames.append((info, CGRect(
                x: infoX, y: stacked ? 0 : centerY - infoHeight / 2, width: infoWidth, height: infoHeight
            )))
            let trailingX = content - trailing.width
            var x = trailingX
            for (view, side) in trailing.items {
                frames.append((view, CGRect(x: x, y: centerY - side.height / 2, width: side.width, height: side.height)))
                x += side.width + ShopRowMetrics.spacing
            }
            if let marker = pieces.marker {
                frames.append((marker, CGRect(x: trailingX, y: centerY - 0.5, width: 1, height: 1)))
            }
            contentHeight = y + lineHeight
            hide(chartLabel, statusLabel)
        case .plainAX:
            let infoHeight = info.height(forWidth: content)
            var y = infoHeight + 12
            frames.append((info, CGRect(x: 0, y: 0, width: content, height: infoHeight)))
            frames.append((self.art, CGRect(x: 0, y: y, width: art, height: art)))
            let items = trailingItems(maxWidth: content)
            var x = content
            var rowHeight = art
            for (view, side, gap) in items.reversed() {
                x -= side.width
                frames.append((view, CGRect(x: x, y: y, width: side.width, height: side.height)))
                x -= gap
                rowHeight = max(rowHeight, side.height)
            }
            y += rowHeight
            if let chips = pieces.chips {
                y += 12
                let h = chips.height(forWidth: content)
                frames.append((chips, CGRect(x: 0, y: y, width: content, height: h)))
                y += h
            }
            if let flow = pieces.flow, pieces.chips == nil {
                y += 12
                let h = flow.height(forWidth: content)
                frames.append((flow, CGRect(x: 0, y: y, width: content, height: h)))
                y += h
            }
            if !statusLabel.isHidden {
                y += 12
                y += placeStatus(x: 0, y: y, width: content)
            }
            contentHeight = y
            hide(chartLabel)
        case .structured:
            var y: CGFloat = 0
            let infoX = art + Self.gap
            let infoWidthFull = content - infoX
            if !isAX {
                let primary = pieces.primary.map { size($0, max: infoWidthFull) } ?? .zero
                let glyph = pieces.glyph.map { size($0, max: infoWidthFull) } ?? .zero
                let reserve = (primary.width > 0 ? primary.width + 8 : 0) + (glyph.width > 0 ? glyph.width + 8 : 0)
                let infoWidth = max(0, infoWidthFull - reserve)
                let infoHeight = info.height(forWidth: infoWidth)
                let chartHeight: CGFloat = chartLabel.isHidden ? 0 : ceil(chartLabel.sizeThatFits(CGSize(width: infoWidth, height: .greatestFiniteMagnitude)).height) + 4
                frames.append((self.art, CGRect(x: 0, y: 0, width: art, height: art)))
                frames.append((info, CGRect(x: infoX, y: 0, width: infoWidth, height: infoHeight)))
                if !chartLabel.isHidden {
                    frames.append((chartLabel, CGRect(x: infoX, y: infoHeight + 4, width: infoWidth, height: chartHeight - 4)))
                }
                var x = infoX + infoWidth + 8
                if let view = pieces.primary {
                    frames.append((view, CGRect(x: x, y: 0, width: primary.width, height: primary.height)))
                    x += primary.width + 8
                }
                if let view = pieces.glyph { frames.append((view, CGRect(x: x, y: 0, width: glyph.width, height: glyph.height))) }
                y = max(art, infoHeight + chartHeight, primary.height, glyph.height)
            } else {
                let infoHeight = info.height(forWidth: infoWidthFull)
                let chartHeight: CGFloat = chartLabel.isHidden ? 0 : ceil(chartLabel.sizeThatFits(CGSize(width: infoWidthFull, height: .greatestFiniteMagnitude)).height) + 4
                frames.append((self.art, CGRect(x: 0, y: 0, width: art, height: art)))
                frames.append((info, CGRect(x: infoX, y: 0, width: infoWidthFull, height: infoHeight)))
                if !chartLabel.isHidden {
                    frames.append((chartLabel, CGRect(x: infoX, y: infoHeight + 4, width: infoWidthFull, height: chartHeight - 4)))
                }
                var blockY = infoHeight + chartHeight
                if let view = pieces.primary {
                    let s = size(view, max: infoWidthFull)
                    let g = pieces.glyph.map { size($0, max: infoWidthFull) } ?? .zero
                    blockY += 6
                    var x = content - g.width - (g.width > 0 ? 0 : 0)
                    if let glyph = pieces.glyph { frames.append((glyph, CGRect(x: x, y: blockY, width: g.width, height: g.height))) }
                    x -= s.width
                    frames.append((view, CGRect(x: x, y: blockY, width: s.width, height: s.height)))
                    blockY += max(s.height, g.height)
                }
                y = max(art, blockY)
            }
            if let flow = pieces.flow {
                y += 10
                let h = flow.height(forWidth: content)
                frames.append((flow, CGRect(x: 0, y: y, width: content, height: h)))
                y += h
            }
            if pieces.bag != nil {
                y += 10
                let items = shopIconItems()
                var x = content
                var rowHeight: CGFloat = 0
                for (view, side) in items.reversed() {
                    x -= side.width
                    frames.append((view, CGRect(x: x, y: y, width: side.width, height: side.height)))
                    x -= SongRowLayoutPolicy.shopIconGap
                    rowHeight = max(rowHeight, side.height)
                }
                y += rowHeight
            }
            contentHeight = y
            hide(statusLabel)
        case .panel:
            let (leftWidth, panelWidth) = SongProfilePanelPolicy.panelColumns(
                contentWidth: content, band: input?.profilePanelFoldBand
            )
            let panelX = content - panelWidth
            let shop = shopIconItems()
            let shopHeight = shop.map(\.1.height).max() ?? 0
            var x = leftWidth
            for (index, item) in shop.reversed().enumerated() {
                if index > 0 { x -= SongRowLayoutPolicy.shopIconGap }
                let (view, side) = item
                x -= side.width
                frames.append((view, CGRect(x: x, y: (shopHeight - side.height) / 2,
                                           width: side.width, height: side.height)))
            }
            if !shop.isEmpty { x -= Self.gap }
            if let glyph = pieces.glyph {
                let side = size(glyph, max: leftWidth)
                x -= side.width
                frames.append((glyph, CGRect(origin: CGPoint(x: x, y: 0), size: side)))
                x -= Self.gap
            }
            let infoX = art + Self.gap
            let infoWidth = max(0, x - infoX - Self.gap - SongRowLayoutPolicy.profileInfoSpacer)
            let infoHeight = info.height(forWidth: infoWidth)
            var leftHeight = infoHeight
            var chipsFrame: (UIView, CGRect)?
            if let chips = pieces.chips {
                let h = chips.height(forWidth: infoWidth)
                chipsFrame = (chips, CGRect(x: infoX, y: infoHeight + 4, width: infoWidth, height: h))
                leftHeight += 4 + h
            }
            let panelHeight = pieces.panel?.height(forWidth: panelWidth) ?? 0
            contentHeight = max(art, leftHeight, panelHeight)
            frames.append((self.art, CGRect(x: 0, y: 0, width: art, height: art)))
            frames.append((info, CGRect(x: infoX, y: 0, width: infoWidth, height: infoHeight)))
            if let chipsFrame { frames.append(chipsFrame) }
            if let panel = pieces.panel { frames.append((panel, CGRect(x: panelX, y: 0, width: panelWidth, height: panelHeight))) }
            hide(chartLabel, statusLabel)
        case .plain:
            let items = trailingItems(maxWidth: content)
            let trailWidth = items.reduce(CGFloat.zero) { $0 + $1.gap + $1.size.width }
            let infoX = art + Self.gap
            // SwiftUI keeps the spacer's stack gaps for compact chips and statuses even with no trailing icons.
            let reservesTrailingGaps = !items.isEmpty || pieces.presentation?.usesInstrumentChips == true
                || !statusLabel.isHidden
            let spacerWidth: CGFloat = reservesTrailingGaps ? 4 + 2 * Self.gap : 4
            let infoWidth = max(0, content - infoX - trailWidth - spacerWidth)
            let infoHeight = info.height(forWidth: infoWidth)
            var y = infoHeight
            frames.append((info, CGRect(x: infoX, y: 0, width: infoWidth, height: infoHeight)))
            if let chips = pieces.chips {
                y += 4
                let h = chips.height(forWidth: infoWidth)
                frames.append((chips, CGRect(x: infoX, y: y, width: infoWidth, height: h)))
                y += h
            } else if let flow = pieces.flow {
                y += 4
                let h = flow.height(forWidth: infoWidth)
                frames.append((flow, CGRect(x: infoX, y: y, width: infoWidth, height: h)))
                y += h
            } else if !statusLabel.isHidden {
                y += 4
                y += placeStatus(x: infoX, y: y, width: infoWidth)
            }
            let trailHeight = items.map(\.size.height).max() ?? 0
            contentHeight = max(art, y, trailHeight)
            let infoOffset = (contentHeight - y) / 2
            frames = frames.map { ($0.0, $0.1.offsetBy(dx: 0, dy: infoOffset)) }
            frames.append((self.art, CGRect(x: 0, y: (contentHeight - art) / 2, width: art, height: art)))
            var x = content - trailWidth
            for (view, side, gap) in items {
                x += gap
                frames.append((view, CGRect(x: x, y: (contentHeight - side.height) / 2, width: side.width, height: side.height)))
                x += side.width
            }
            hide(chartLabel)
        }
        return Plan(width: width, height: contentHeight + 2 * Self.padV, frames: frames)
    }

    /// The plain row's trailing items, with the smaller gap inside the Shop group.
    private func trailingItems(maxWidth: CGFloat) -> [(view: UIView, size: CGSize, gap: CGFloat)] {
        var items: [(UIView, CGSize)] = []
        if let primary = pieces.primary { items.append((primary, primary.fittedSize(maxWidth: maxWidth))) }
        if let meter = pieces.meter { items.append((meter, CGSize(width: 62, height: 20))) }
        if let glyph = pieces.glyph { items.append((glyph, CGSize(width: glyph.bounds.width, height: glyph.bounds.width))) }
        let shopStart = items.count
        items.append(contentsOf: shopIconItems())
        return items.enumerated().map { index, item in
            let gap = index == 0 ? 0 : (index > shopStart ? SongRowLayoutPolicy.shopIconGap : 8)
            return (view: item.0, size: item.1, gap: gap)
        }
    }

    /// The bag, then the Leaving Tomorrow clock or the New marker.
    private func shopIconItems() -> [(UIView, CGSize)] {
        var items: [(UIView, CGSize)] = []
        if let bag = pieces.bag, let size = bag.image?.size {
            items.append((bag, size))
        }
        if let clock = pieces.leaving {
            items.append((clock, Self.leavingSize(clock)))
        }
        if let marker = pieces.marker { items.append((marker, CGSize(width: 1, height: 1))) }
        return items
    }

    /// The Item Shop list row's trailing items: clock, the bag slot, chevron.
    private func shopTrailing() -> (items: [(UIView, CGSize)], width: CGFloat) {
        var items: [(UIView, CGSize)] = []
        if let clock = pieces.leaving {
            items.append((clock, Self.leavingSize(clock)))
        }
        if let slot = pieces.bagSlot {
            // The bag action overlays this slot (the Shop screen's button); nothing draws here.
            items.append((slot, CGSize(width: ShopRowMetrics.bagReserve, height: ShopRowMetrics.bagSlot)))
        }
        if let chevron = pieces.chevron { items.append((chevron, CGSize(width: ShopRowMetrics.chevronWidth, height: 20))) }
        let width = items.reduce(CGFloat.zero) { $0 + $1.1.width } + CGFloat(max(0, items.count - 1)) * ShopRowMetrics.spacing
        return (items, width)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let plan = self.plan(width: bounds.width)
        for (view, frame) in plan.frames {
            if frame == .zero, view === chartLabel || view === statusLabel { continue }
            view.frame = CGRect(x: frame.minX + Self.padH, y: frame.minY + Self.padV, width: frame.width, height: frame.height)
            if let clock = view as? UIImageView, clock === pieces.leaving { clock.layer.cornerRadius = frame.width / 2 }
        }
        if let glyph = pieces.glyph { glyph.layer.cornerRadius = 0 }
        pieces.leaving?.layer.cornerRadius = (pieces.leaving?.bounds.width ?? 0) / 2
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: height(forWidth: size.width))
    }

    // MARK: Accessibility geometry

    /// Frames of the exposed child elements in this view's coordinates, keyed by identifier.
    func childElements(songId: String) -> [(id: String, label: String, frame: CGRect, traits: UIAccessibilityTraits)] {
        var elements: [(String, String, CGRect, UIAccessibilityTraits)] = []
        func add(_ id: String, _ label: String, _ view: UIView?, _ traits: UIAccessibilityTraits = .staticText) {
            guard let view else { return }
            elements.append((id, label, view.frame, traits))
        }
        add("fst.songs.metadata.chart.\(songId)", pieces.chartCaption ?? "", pieces.chartCaption == nil ? nil : chartLabel)
        if let primary = pieces.primary { add("fst.songs.metadata.\(primary.field.id.rawValue).\(songId)", primary.field.announcement, primary) }
        if let flow = pieces.flow {
            for (field, frame) in flow.fieldFrames {
                elements.append((
                    "fst.songs.metadata.\(field.id.rawValue).\(songId)", field.announcement,
                    flow.convert(frame, to: self), .staticText
                ))
            }
        }
        if let chips = pieces.chips { add("fst.songs.instrument-status.\(songId)", chips.announcement, chips) }
        if let id = pieces.statusIdentifier, let text = pieces.statusText, !statusLabel.isHidden { add(id, text, statusLabel) }
        if let meter = pieces.meter { add("fst.songs.difficulty-meter", meter.accessibilityLabel ?? "", meter, .image) }
        if let bag = pieces.bag { add("fst.songs.shop-bag.\(songId)", "In the Item Shop", bag, .image) }
        if let input {
            if pieces.shopOffer == nil {
                if input.shopHighlight == .new { add("fst.songs.shop-badge.\(songId)", "Item Shop: \(ShopHighlight.new.label)", pieces.marker) }
                if input.shopHighlight == .leavingTomorrow { add("fst.songs.shop-badge.\(songId)", "Item Shop: \(ShopHighlight.leavingTomorrow.label)", pieces.leaving, .image) }
            } else {
                if pieces.shopOffer?.highlight == .new { add("fst.shop.badge.new.\(songId)", ShopHighlight.new.label, pieces.marker) }
                if pieces.shopOffer?.highlight == .leavingTomorrow { add("fst.shop.badge.leaving.\(songId)", ShopHighlight.leavingTomorrow.label, pieces.leaving, .image) }
            }
        }
        return elements.map { (id: $0.0, label: $0.1, frame: $0.2, traits: $0.3) }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory, let input {
            configure(input, width: bounds.width, traits: traitCollection)
        }
    }
}
#endif
