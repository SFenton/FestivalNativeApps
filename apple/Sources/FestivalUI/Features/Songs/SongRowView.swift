import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Item Shop decoration

/// The Item Shop list's decoration of the shared Song row (web `ShopPage` renders the
/// Songs `SongRow` with `externalHref` and the red/gold `shopHighlight*` flags).
///
/// The row keeps the Songs surface, art and marquee title/artist line; Shop replaces
/// the profile/score area with its own trailing badge, bag slot and Detail chevron.
struct SongRowShopOffer: Equatable {
    /// Effective New / Leaving Tomorrow badge after Hide Shop / highlighting settings.
    let highlight: ShopHighlight?
    /// A catalogue match opens Song Detail, so the row shows a trailing chevron.
    let navigable: Bool
    /// Leave room for the official bag link the Shop overlays as a sibling action.
    let reservesBag: Bool

    /// Row border pulse: gold for New, red for Leaving Tomorrow, none for a plain
    /// offer (the web passes only the red/gold flags to Shop rows).
    var pulseTone: ShopStatusTone? {
        highlight.map(ShopStatusTone.init(highlight:))
    }
}

/// Resolves which song and decoration one Item Shop offer renders with.
enum ShopRowPolicy {
    /// One Shop list row's inputs for the shared ``SongRowView``.
    struct Row: Equatable {
        /// Catalogue song when matched, otherwise a display-only offer song.
        let song: Song
        /// Matched catalogue song for the in-app Detail link; nil means bag only.
        let detailSong: Song?
        /// Shop-only trailing content and border.
        let decoration: SongRowShopOffer
    }

    /// Pair an offer with its catalogue song and effective Shop highlight.
    ///
    /// - Parameters:
    ///   - offer: Validated public Shop offer.
    ///   - catalogue: Current catalogue songs by ID (empty when that read failed).
    ///   - hidden: The Hide Item Shop setting.
    ///   - highlightingDisabled: The disable-highlighting setting.
    ///   - reservesBag: Whether the bag overlays the row (not at accessibility sizes).
    /// - Returns: The song to draw, the optional Detail target and the decoration.
    static func row(
        for offer: ShopSong, catalogue: [String: Song],
        hidden: Bool, highlightingDisabled: Bool, reservesBag: Bool
    ) -> Row {
        let match = catalogue[offer.songId]
        return Row(
            song: match ?? Song(shopOffer: offer),
            detailSong: match,
            decoration: SongRowShopOffer(
                highlight: ShopPresentationPolicy.highlight(
                    for: offer, hidden: hidden, highlightingDisabled: highlightingDisabled
                ),
                navigable: match != nil,
                reservesBag: reservesBag
            )
        )
    }
}

// MARK: - Song row

/// The one Song row shared by Songs, the Item Shop list and first-run demos: art,
/// marquee title/artist line and the Songs glass card surface.
struct SongRowView: View {
    let song: Song
    let instrument: Instrument?
    let session: FestivalSession
    let highContrast: Bool
    let shopHighlight: ShopHighlight?
    /// In the current, publication-matched Shop with highlighting enabled (web
    /// `isShopHighlighted`): pulsing border and the bag icon.
    let inShop: Bool
    let profileChart: Instrument?
    let catalogueObservation: Int?
    let metadata: SongMetadataVisibility
    let filterInvalidScores: Bool
    let showInstrumentIcons: Bool
    let visibleInstruments: Set<Instrument>
    let currentSeason: Int?
    /// Item Shop list decoration; nil on Songs.
    let shopOffer: SongRowShopOffer?
    @AppStorage("fst.settings.songRowVisualOrder")
    private var songRowVisualOrderRaw = SettingsOrder.encode(MetadataField.allCases)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.songRowsAllowSingleLine) private var allowsSingleLine
    /// The card's width, measured only where one-line rows are allowed.
    @State private var rowWidth: CGFloat = 0

    /// Decorate one real Shop offer without turning it into a new navigation action.
    ///
    /// - Parameters:
    ///   - song: Public catalogue row.
    ///   - instrument: Optional currently selected chart.
    ///   - session: Process-scoped artwork loader.
    ///   - highContrast: Explicit content contrast override.
    ///   - shopHighlight: Validated, effectively enabled Shop badge.
    ///   - inShop: Song is in the validated Shop with highlighting enabled.
    ///   - profileChart: First visible chart or explicit Songs chart filter.
    ///   - catalogueObservation: Observed generation for this validated Songs row.
    ///   - metadata: Persisted score-field visibility switches.
    ///   - filterInvalidScores: Hide unsupported filtered-score details explicitly.
    ///   - showInstrumentIcons: Saved status-chip setting.
    ///   - visibleInstruments: Enabled charts independent of chart availability.
    ///   - currentSeason: Current catalogue season for the inverted season badge.
    ///   - shopOffer: Item Shop list decoration; replaces the profile/score area.
    init(
        song: Song, instrument: Instrument?, session: FestivalSession,
        highContrast: Bool, shopHighlight: ShopHighlight? = nil,
        inShop: Bool = false,
        profileChart: Instrument? = nil,
        catalogueObservation: Int? = nil,
        metadata: SongMetadataVisibility = SongMetadataVisibility(),
        filterInvalidScores: Bool = false,
        showInstrumentIcons: Bool = true,
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        currentSeason: Int? = nil,
        shopOffer: SongRowShopOffer? = nil
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        self.highContrast = highContrast
        self.shopHighlight = shopHighlight
        self.inShop = inShop || shopHighlight != nil
        self.profileChart = profileChart
        self.catalogueObservation = catalogueObservation
        self.metadata = metadata
        self.filterInvalidScores = filterInvalidScores
        self.showInstrumentIcons = showInstrumentIcons
        self.visibleInstruments = visibleInstruments
        self.currentSeason = currentSeason
        self.shopOffer = shopOffer
    }

    private var trailingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private var scoreDataCurrent: Bool {
        session.hasCurrentPlayerScores(forCatalogue: catalogueObservation)
    }

    private var usesInstrumentChips: Bool {
        SongInstrumentStatusPolicy.showsChips(
            hasSelectedPlayer: session.selectedPlayer != nil,
            scoresAvailable: scoreDataCurrent,
            iconsEnabled: showInstrumentIcons,
            instrumentFilter: instrument,
            filterInvalidScores: filterInvalidScores,
            visibleInstruments: visibleInstruments
        )
    }

    private var structuredScore: (chart: Instrument, score: PlayerScore)? {
        guard !usesInstrumentChips, !filterInvalidScores,
              scoreDataCurrent,
              let chart = profileChart, song.supports(chart),
              let score = session.selectedPlayerScores[song.songId]?[chart],
              score.score > 0 else {
            return nil
        }
        return (chart, score)
    }

    private var structuredFields: Result<[SongMetadataField], Error>? {
        guard let structuredScore else { return nil }
        return Result {
            let fields = try SongProfileCardPolicy.fields(
                for: structuredScore.score, chart: structuredScore.chart,
                song: song, currentSeason: currentSeason, visibility: metadata
            )
            return SongProfileCardPolicy.reordered(
                fields, by: SettingsOrder.decode(songRowVisualOrderRaw)
            )
        }
    }

    private var artworkTile: some View {
        ArtworkTile(raw: song.albumArt, session: session, size: 44)
            .id(song.albumArt)
            .accessibilityHidden(true)
    }

    private var songSubtitle: String {
        var subtitle = song.artist
        if let year = song.year, year != 0 {
            subtitle += " · \(year)"
        }
        if let duration = song.formattedDuration {
            subtitle += " · \(duration)"
        }
        return subtitle
    }

    /// Title/artist·year·duration, ported to `MarqueeText` (web `SongInfo.tsx` does
    /// the same) so a long combination auto-scrolls on one line instead of wrapping
    /// to a second line — the previous `.fixedSize(horizontal: false, vertical:
    /// true)` explicitly allowed that wrap, which is what grew rows like "6 Foot
    /// 7 Foot" tall on folded Duo's narrower card width.
    ///
    /// At accessibility text sizes both lines wrap instead (HIG Typography: "Keep
    /// text truncation to a minimum as font size increases"), as the Item Shop rows
    /// did before they reused this row (issue #18) and Android's marquee does at
    /// large text; a one-line marquee there fails the Text clipped audit.
    @ViewBuilder private var songInfo: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(songSubtitle)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FestivalText.primary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(song.title, font: .headline)
                    .foregroundStyle(FestivalText.primary)
                MarqueeText(songSubtitle, font: .subheadline)
                    .foregroundStyle(FestivalText.primary)
            }
            .marqueeSync()
        }
    }

    private var selectedChartInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            songInfo
            if let chart = structuredScore?.chart, chart != .lead {
                Text("\(chart.label) chart")
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityIdentifier("fst.songs.metadata.chart.\(song.songId)")
            }
        }
    }

    @ViewBuilder private var profileContent: some View {
        if let selected = session.selectedPlayer {
            if session.playerLoadState == .available && !scoreDataCurrent {
                Label("Player scores paused until songs update", systemImage: "pause.circle")
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.gold)
                    .accessibilityIdentifier("fst.songs.profile-paused-row.\(song.songId)")
            } else if usesInstrumentChips {
                SongInstrumentStatusChips(
                    songId: song.songId,
                    badges: SongInstrumentStatusPolicy.badges(
                        for: song, visibleInstruments: visibleInstruments,
                        scores: session.selectedPlayerScores[song.songId] ?? [:]
                    ),
                    keyboard: song.usesKeyboardIcon
                )
            } else {
                SongProfileSummary(
                    player: selected, chart: profileChart,
                    chartAvailable: profileChart.map(song.supports) ?? false,
                    score: scoreDataCurrent ? profileChart.flatMap {
                        session.selectedPlayerScores[song.songId]?[$0]
                    } : nil,
                    state: session.playerLoadState, visibility: metadata,
                    filterInvalidScores: filterInvalidScores, songId: song.songId
                )
            }
        }
    }

    /// The web row's shop bag (`IoBagHandle`) for every song in the Item Shop, before the
    /// Leaving Tomorrow clock (operator batch 7).
    @ViewBuilder private var shopIcons: some View {
        if inShop {
            HStack(spacing: 6) {
                Image(systemName: "bag.fill")
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityLabel("In the Item Shop")
                    .accessibilityIdentifier("fst.songs.shop-bag.\(song.songId)")
                shopBadge
            }
        }
    }

    @ViewBuilder private var shopBadge: some View {
        if shopHighlight == .new {
            // No visible "New" chip (operator, 2026-09-28): the row's gold outline marks
            // it. VoiceOver still hears "Item Shop: New" through the combined row.
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityLabel("Item Shop: \(ShopHighlight.new.label)")
                .accessibilityIdentifier("fst.songs.shop-badge.\(song.songId)")
        } else if let shopHighlight {
            Image(systemName: shopHighlight == .leavingTomorrow
                ? "clock" : "sparkles")
                .font(.subheadline)
                .foregroundStyle(
                    shopHighlight == .leavingTomorrow
                        ? FestivalText.primary : BrandTokens.gold
                )
                .frame(minWidth: 30, minHeight: 30)
                .background(
                    shopHighlight == .leavingTomorrow
                        ? BrandTokens.statusRed : BrandTokens.appBackground,
                    in: Circle()
                )
                .accessibilityLabel("Item Shop: \(shopHighlight.label)")
                .accessibilityIdentifier("fst.songs.shop-badge.\(song.songId)")
        }
    }

    /// Item Shop trailing content: the visible New / Leaving Tomorrow badge, the slot
    /// the Shop overlays its official bag link on, then the Detail chevron (PWA gap #17).
    ///
    /// - Parameter offer: Shop decoration for this row.
    /// - Returns: Badge, bag reserve and chevron in web order.
    private func shopOfferTrailing(_ offer: SongRowShopOffer) -> some View {
        HStack(spacing: ShopRowMetrics.spacing) {
            if let highlight = offer.highlight {
                let leaving = highlight == .leavingTomorrow
                Image(systemName: leaving ? "clock" : "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(leaving ? FestivalText.primary : BrandTokens.gold)
                    .frame(minWidth: 30, minHeight: 30)
                    .background(
                        leaving ? BrandTokens.statusRed : BrandTokens.appBackground,
                        in: Circle()
                    )
                    .accessibilityLabel(highlight.label)
                    .accessibilityIdentifier(
                        leaving
                            ? "fst.shop.badge.leaving.\(song.songId)"
                            : "fst.shop.badge.new.\(song.songId)"
                    )
            }
            if offer.reservesBag {
                Color.clear
                    .frame(width: ShopRowMetrics.bagReserve, height: ShopRowMetrics.bagSlot)
                    .accessibilityHidden(true)
            }
            if offer.navigable {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .frame(width: ShopRowMetrics.chevronWidth)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Row border: the Item Shop pulse when this row is a Shop offer or a Songs row in
    /// the Shop; nil otherwise.
    private var pulseTone: ShopStatusTone? {
        if let shopOffer { return shopOffer.pulseTone }
        return inShop ? ShopStatusTone(highlight: shopHighlight) : nil
    }

    private var trailingContent: some View {
        trailingLayout {
            // Anonymous rows are "artist · year · length" only, like the web row.
            if metadata.intensity, session.selectedPlayer != nil, let instrument,
               structuredScore == nil,
               let difficulty = song.difficulty?.chartedValue(for: instrument) {
                DifficultyMeter(level: difficulty, raw: true)
            }
            shopIcons
        }
    }

    /// Keep a right-aligned primary field and a full-width wrapped secondary row.
    ///
    /// - Parameter fields: One validated, source-ordered selected-chart projection.
    /// - Returns: One opaque, noninteractive native Song card content layout.
    private func structuredMetadataRow(_ fields: [SongMetadataField]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artworkTile
                if !dynamicTypeSize.isAccessibilitySize {
                    // The primary metric keeps its line; a long title/artist marquees
                    // instead of pushing it down (operator batch 7).
                    HStack(alignment: .top, spacing: 8) {
                        selectedChartInfo.frame(maxWidth: .infinity, alignment: .leading)
                        if let primary = fields.first {
                            SongMetadataFieldView(field: primary, songId: song.songId)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        selectedChartInfo
                        if let primary = fields.first {
                            HStack {
                                Spacer(minLength: 0)
                                SongMetadataFieldView(field: primary, songId: song.songId)
                            }
                        }
                    }
                }
            }
            if fields.count > 1 {
                SongProfileMetadataPills(
                    fields: Array(fields.dropFirst()), songId: song.songId
                )
            }
            if inShop {
                HStack {
                    Spacer(minLength: 0)
                    shopIcons
                }
            }
        }
    }

    /// Chips sit beside the title (``SongRowLayoutPolicy``) when allowed and they fit.
    private var singleLine: Bool {
        guard allowsSingleLine, usesInstrumentChips, !dynamicTypeSize.isAccessibilitySize else { return false }
        let count = visibleInstruments.count
        // `rowWidth` is measured inside the 12 pt padding; the policy counts it.
        return SongRowLayoutPolicy.fitsSingleLine(width: rowWidth + 24, chipCount: count)
    }

    var body: some View {
        Group {
            if let shopOffer {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        songInfo
                        HStack(spacing: 12) {
                            artworkTile
                            Spacer(minLength: 0)
                            shopOfferTrailing(shopOffer)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        artworkTile
                        songInfo
                        Spacer(minLength: 4)
                        shopOfferTrailing(shopOffer)
                    }
                }
            } else if let structuredFields, case let .success(fields) = structuredFields {
                structuredMetadataRow(fields)
            } else if dynamicTypeSize.isAccessibilitySize && usesInstrumentChips {
                VStack(alignment: .leading, spacing: 12) {
                    songInfo
                    HStack(alignment: .top, spacing: 12) {
                        artworkTile
                        Spacer(minLength: 0)
                        trailingContent
                    }
                    profileContent
                }
            } else if singleLine {
                // Web desktop row: chips on one line beside the title.
                HStack(spacing: 12) {
                    artworkTile
                    songInfo.frame(minWidth: SongRowLayoutPolicy.infoMinimumWidth, maxWidth: .infinity, alignment: .leading)
                    profileContent.fixedSize()
                    trailingContent
                        .frame(minWidth: SongRowLayoutPolicy.shopSlotWidth, alignment: .trailing)
                }
            } else {
                HStack(spacing: 12) {
                    artworkTile
                    VStack(alignment: .leading, spacing: 4) {
                        songInfo
                        profileContent
                    }
                    Spacer(minLength: 4)
                    trailingContent
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { allowsSingleLine ? $0.size.width : 0 } action: { rowWidth = $0 }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .festivalGlass(.card, cornerRadius: 12)
        .overlay {
            if let pulseTone {
                // Web `shopPulse`: a 2pt border fading 0 → 0.7 → 0 every 2 s, green in
                // the shop, gold when new, red when leaving tomorrow.
                ShopRowPulseBorder(tone: pulseTone, cornerRadius: 12)
            } else if highContrast {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FestivalText.primary, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
