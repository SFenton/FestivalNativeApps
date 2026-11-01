import Foundation
import FestivalCore

// MARK: - Settings snapshot

/// The saved values that shape the Songs list (`@AppStorage` in ``SongsScreen``), read as
/// one value so the SwiftUI page and the UIKit port decide from the same inputs.
struct SongsSettings: Equatable {
    var sortMode = SongSortMode.title
    var sortAscending = true
    var generalFilterData = Data()
    var legacyFilterInShop = false
    var legacyFilterLeavingTomorrow = false
    var playerScoreFilterData = Data()
    var hideShop = false
    var disableShopHighlighting = false
    var filterInvalidScores = false
    var leeway = 1.0
    var showInstrumentIcons = true
    var metadata = SongMetadataVisibility()

    /// Reads the saved values under the keys ``SongsScreen`` declares.
    ///
    /// - Parameter defaults: The store (the app's standard defaults).
    /// - Returns: The stored values, with each default where nothing is stored.
    static func load(from defaults: UserDefaults = .standard) -> SongsSettings {
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        var settings = SongsSettings()
        settings.sortMode = (defaults.string(forKey: "fst.songs.sortMode")).flatMap(SongSortMode.init(rawValue:)) ?? .title
        settings.sortAscending = bool("fst.songs.sortAscending", true)
        settings.generalFilterData = defaults.data(forKey: SongGeneralFilter.storageKey) ?? Data()
        settings.legacyFilterInShop = bool(SongGeneralFilter.legacyInShopKey, false)
        settings.legacyFilterLeavingTomorrow = bool(SongGeneralFilter.legacyLeavingTomorrowKey, false)
        settings.playerScoreFilterData = defaults.data(forKey: SongPlayerScoreFilter.storageKey) ?? Data()
        settings.hideShop = bool("fst.settings.hideShop", false)
        settings.disableShopHighlighting = bool("fst.settings.disableShopHighlighting", false)
        settings.filterInvalidScores = bool("fst.settings.filterInvalidScores", false)
        settings.leeway = defaults.object(forKey: "fst.settings.leeway") as? Double ?? 1.0
        settings.showInstrumentIcons = bool("fst.settings.showInstrumentIcons", true)
        settings.metadata = SongMetadataVisibility(
            score: bool("fst.settings.metadataScore", true), percentage: bool("fst.settings.metadataPercentage", true),
            percentile: bool("fst.settings.metadataPercentile", true), season: bool("fst.settings.metadataSeason", true),
            intensity: bool("fst.settings.metadataIntensity", true), difficulty: bool("fst.settings.metadataDifficulty", true),
            stars: bool("fst.settings.metadataStars", true), lastPlayed: bool("fst.settings.metadataLastPlayed", true)
        )
        return settings
    }
}

// MARK: - Groups

/// One labelled run of songs: an A–Z letter, a decade, a duration or Shop bucket.
struct SongsListGroup: Identifiable {
    /// Scroll target: the scrubber's `Int` section id, or the quick-link id.
    let id: AnyHashable
    let label: String
    /// VoiceOver label when it differs from `label` ("5 stars" for "5★").
    var spokenLabel: String?
    let accessibilityID: String
    /// Quick Links entry for sorts without the scrubber (Year, Duration, Shop).
    let quickLink: QuickLinkSection?
    let songs: [Song]
}

extension SongShopSectionKind {
    /// Section title and Quick Links label.
    var label: String {
        switch self {
        case .leavingTomorrow: "Leaving Tomorrow"
        case .inShop: "In Shop"
        case .notInShop: "Not In Shop"
        }
    }
}

// MARK: - Disclosures

/// One notice above the Songs rows (``SongsPipeline/disclosures(refreshFailure:shopRefreshFailure:)``).
enum SongsDisclosure: Equatable {
    /// A last-update failure banner.
    case refreshError(String)
    /// A freshness or paused notice.
    case freshness(message: String, symbol: String, identifier: String?)
    /// "Retry Player Scores".
    case retryPlayer
    /// "Choose Profile".
    case chooseProfile
    /// "Retry Item Shop status".
    case retryShop
}

// MARK: - Pipeline

/// Everything the Songs list decides before drawing: which saved filters and sorts apply
/// or are paused, the visible rows, their groups and the notices above them.
///
/// Shared by ``SongsScreen`` and the UIKit port, so both read the same Shop-membership,
/// score-index provenance and paused-state rules (AGENTS.md invariants).
@MainActor
struct SongsPipeline {
    let session: FestivalSession
    let payload: CatalogPayload?
    let settings: SongsSettings
    let instrument: Instrument?
    let visibleInstruments: Set<Instrument>

    // MARK: Saved filters

    private var generalFilterResult: Result<SongGeneralFilter, Error> {
        Result {
            try SongGeneralFilter.decodeSaved(
                settings.generalFilterData, legacyInShop: settings.legacyFilterInShop,
                legacyLeavingTomorrow: settings.legacyFilterLeavingTomorrow
            )
        }
    }

    /// The saved General filter, nil while it is corrupt.
    var appliedGeneralFilter: SongGeneralFilter? {
        if case let .success(filter) = generalFilterResult { return filter }
        return nil
    }

    /// Whether the saved General filter fails to decode.
    var generalFilterError: Error? {
        if case let .failure(error) = generalFilterResult { return error }
        return nil
    }

    private var playerScoreFilterResult: Result<SongPlayerScoreFilter, Error> {
        Result { try SongPlayerScoreFilter.decodeSaved(settings.playerScoreFilterData) }
    }

    /// The saved player score filter, nil while it is corrupt.
    var appliedPlayerScoreFilter: SongPlayerScoreFilter? {
        if case let .success(filter) = playerScoreFilterResult { return filter }
        return nil
    }

    /// Whether the saved player score filter fails to decode.
    var playerScoreFilterError: Error? {
        if case let .failure(error) = playerScoreFilterResult { return error }
        return nil
    }

    /// The first corrupt saved filter, which blocks the list until an explicit Reset.
    var savedFilterError: Error? { generalFilterError ?? playerScoreFilterError }

    var appliedShopFilter: SongShopFilter { appliedGeneralFilter?.shop ?? SongShopFilter() }

    /// Loaded catalogue rows (the General filter's Year and Duration options).
    var catalogueSongs: [Song] { payload?.catalog.songs ?? [] }

    var currentSeason: Int? { payload?.catalog.currentSeason }

    /// Whether any saved General choice hides songs (Item Shop only while Shop is shown).
    var generalFilterActive: Bool {
        appliedGeneralFilter?.isActive(shopVisible: !settings.hideShop) == true
    }

    /// General filters need no player, so Filter is offered whenever saved filters decode.
    var canPresentFilter: Bool { savedFilterError == nil }

    // MARK: Publication provenance

    var shopPublicationMismatch: Bool {
        guard let payload, let current = session.publicationId else { return false }
        return payload.observedPublicationId != current
            || session.currentShop.map { $0.observedPublicationId != current } == true
    }

    var shopOffersForCurrentSongs: [String: ShopSong]? {
        guard !settings.hideShop, let payload,
              SongShopPublicationPolicy.matches(
                catalogue: payload.observedPublicationId,
                shop: session.currentShop?.observedPublicationId,
                current: session.publicationId
              ) else { return nil }
        return session.shopOffersById
    }

    var profilePublicationMismatch: Bool {
        guard let payload, session.selectedPlayer != nil, session.playerLoadState == .available else { return false }
        return !session.hasCurrentPlayerScores(forCatalogue: payload.observedPublicationId)
    }

    var scoreFilterAvailable: Bool {
        guard let payload else { return false }
        return session.hasCurrentPlayerScores(forCatalogue: payload.observedPublicationId)
    }

    // MARK: Filters in force

    var shopFilterPausedMessage: String? {
        guard appliedShopFilter.isActive else { return nil }
        if settings.hideShop {
            return "Item Shop filters paused while Shop is hidden. Showing all songs; "
                + "your choices are saved."
        }
        // Both categories off hides every song without classifying (web parity).
        guard appliedShopFilter.needsShopFeed else { return nil }
        if shopPublicationMismatch {
            return "Item Shop filters paused while songs and Shop publications differ. "
                + "Showing songs without Shop filters; your choices are saved."
        }
        if shopOffersForCurrentSongs == nil {
            return "Item Shop filters paused until public Shop data loads. "
                + "Showing all songs; retry Item Shop status if unavailable."
        }
        return nil
    }

    var effectiveShopFilter: SongShopFilter {
        shopFilterPausedMessage == nil ? appliedShopFilter : SongShopFilter()
    }

    /// Why saved score checks with a real cause cannot apply right now.
    var playerScoreFilterPausedMessage: String? {
        guard payload != nil, session.selectedPlayer != nil,
              let filter = appliedPlayerScoreFilter, filter.isActive else { return nil }
        if !filter.scoped(to: visibleInstruments).isActive {
            return "Player score filters paused while their charts are hidden in Settings. "
                + "Your choices are saved."
        }
        if !scoreFilterAvailable {
            return "Player score filters paused until selected scores and songs "
                + "share the current publication. Showing songs without score filters."
        }
        return nil
    }

    var effectivePlayerScoreFilter: SongPlayerScoreFilter {
        guard session.selectedPlayer != nil, playerScoreFilterPausedMessage == nil else {
            return SongPlayerScoreFilter()
        }
        let scoped = appliedPlayerScoreFilter?.scoped(to: visibleInstruments) ?? SongPlayerScoreFilter()
        // Saved Over CHOpt Threshold checks are inert while Filter Invalid Scores is off.
        return invalidScoreLeeway == nil ? scoped.clearingOverThreshold : scoped
    }

    /// Settings › Filter Invalid Scores' leeway (rounded to the slider's 0.1 steps) while
    /// it is on and a player is selected, else nil.
    var invalidScoreLeeway: Double? {
        guard settings.filterInvalidScores, session.selectedPlayer != nil, session.selectedBand == nil else { return nil }
        return (settings.leeway * 10).rounded() / 10
    }

    /// Charts whose Over CHOpt Threshold filter keeps an invalid score raw.
    var overThresholdCharts: Set<Instrument> {
        invalidScoreLeeway == nil ? [] : effectivePlayerScoreFilter.overThreshold
    }

    /// The selected player's scores as Songs shows them: raw, or each chart's effective
    /// score while Filter Invalid Scores is on.
    ///
    /// - Parameter songs: The catalogue (CHOpt maxima and population curves).
    /// - Returns: Scores by song ID and chart.
    func playerScoreIndex(songs: [Song]) -> [String: [Instrument: PlayerScore]] {
        guard let invalidScoreLeeway else { return session.selectedPlayerScores }
        let songsById = Dictionary(songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
        return InvalidScorePolicy.resolve(
            index: session.selectedPlayerScores, songsById: songsById,
            leeway: invalidScoreLeeway, overThreshold: overThresholdCharts
        )
    }

    var hiddenPlayerScoreChecks: Bool {
        guard session.selectedPlayer != nil, let filter = appliedPlayerScoreFilter else { return false }
        return filter.scoped(to: visibleInstruments) != filter
    }

    /// The Filter button's accessibility value.
    var filterAccessibilityValue: String {
        let general = appliedGeneralFilter ?? SongGeneralFilter()
        let labels = [
            general.restrictsYear ? "Year filter" : nil,
            general.restrictsDuration ? "Duration filter" : nil,
            !settings.hideShop && general.shop.isActive ? "Item Shop filter" : nil,
            general.restrictsDoubleBass ? "Double Bass filter" : nil,
        ].compactMap { $0 }
        let scoreCount = appliedPlayerScoreFilter.map { filter in
            SongScoreFilterKind.allCases.reduce(0) { count, kind in
                count + Instrument.allCases.filter { filter.contains(kind, for: $0) }.count
            }
        } ?? 0
        let scoreLabel = scoreCount > 0
            ? "\(scoreCount) player score \(scoreCount == 1 ? "check" : "checks")" : nil
        let bucketLabels = SongBucketKind.allCases.compactMap { kind in
            appliedPlayerScoreFilter?.excluded(kind).isEmpty == false ? "\(kind.rawValue.capitalized) filter" : nil
        }
        let selected = (labels + [scoreLabel].compactMap { $0 } + bucketLabels).joined(separator: ", ")
        let status = selected.isEmpty ? "No filters" : selected
        if shopFilterPausedMessage != nil {
            return status + (effectivePlayerScoreFilter.isActive || general.restrictsMetadata
                ? ", Item Shop filters paused" : ", paused; showing all songs")
        }
        return status + (playerScoreFilterPausedMessage == nil ? "" : ", player score filters paused")
    }

    // MARK: Sort

    /// Keep a saved Shop or player sort visible when its source is hidden or unavailable.
    var sortPausedMessage: String? {
        if settings.sortMode.isPlayerChartMode { return playerSortPausedMessage }
        guard settings.sortMode == .shop else { return nil }
        if settings.hideShop {
            return "Item Shop sort paused while Shop is hidden. Showing title order; "
                + "your preference is saved."
        }
        if shopPublicationMismatch {
            return "Item Shop sort paused while songs and Shop publications differ. "
                + "Showing title order; your preference is saved."
        }
        if shopOffersForCurrentSongs == nil {
            return "Item Shop sort paused until public Shop data loads. "
                + "Showing title order; retry Item Shop status if unavailable."
        }
        return nil
    }

    /// Why a saved Score/Percentile/Stars sort cannot order the rows right now.
    var playerSortPausedMessage: String? {
        let name = settings.sortMode.label
        guard instrument != nil, session.selectedPlayer != nil else { return nil }
        if !scoreFilterAvailable {
            return "\(name) sort paused until selected scores and songs share the current "
                + "publication. Showing title order; your preference is saved."
        }
        return nil
    }

    /// The sort actually applied: Title while the saved sort is paused, or while a player
    /// sort has no instrument or no player to order by.
    var effectiveSortMode: SongSortMode {
        if sortPausedMessage != nil { return .title }
        if settings.sortMode.isPlayerChartMode && (instrument == nil || session.selectedPlayer == nil) { return .title }
        return settings.sortMode
    }

    /// Selected-player sorts the Sort sheet offers.
    var playerSortModesOffered: [SongSortMode] {
        guard instrument != nil, session.selectedPlayer != nil else { return [] }
        return SongSortMode.playerChartModes.filter { mode in
            switch mode {
            case .score: settings.metadata.score
            case .percentile: settings.metadata.percentile
            case .stars: settings.metadata.stars
            default: false
            }
        }
    }

    /// The selected player's scores on the Songs instrument, only from an available score
    /// index observed with this catalogue.
    func chartScores(for payload: CatalogPayload) -> [String: PlayerScore]? {
        guard let instrument, session.hasCurrentPlayerScores(forCatalogue: payload.observedPublicationId) else { return nil }
        return playerScoreIndex(songs: payload.catalog.songs).compactMapValues { $0[instrument] }
    }

    // MARK: Rows

    /// Whether the list has any filter narrowing it (for the empty state's copy).
    func filtersApplied(general: SongGeneralFilter) -> Bool {
        instrument != nil || effectiveShopFilter.isActive || general.restrictsMetadata
            || effectivePlayerScoreFilter.isActive
    }

    /// The songs left after search, filters and sort.
    ///
    /// - Parameters:
    ///   - payload: The loaded catalogue.
    ///   - search: The settled search query.
    /// - Returns: The ordered rows, or the filter/sort failure.
    func visibleSongs(in payload: CatalogPayload, search: String) -> Result<[Song], Error> {
        let general = appliedGeneralFilter ?? SongGeneralFilter()
        let matching = payload.catalog.songs.filter { song in
            SongSearch.matches(song, query: search)
                && (instrument.map(song.supports) ?? true)
                && general.matchesMetadata(song)
        }
        let mode = effectiveSortMode
        let membership = shopOffersForCurrentSongs.map { Set($0.keys) }
        return Result {
            let publicFiltered = try effectiveShopFilter.filtered(matching, offersById: shopOffersForCurrentSongs)
            let filtered = try effectivePlayerScoreFilter.filtered(
                publicFiltered,
                scoresBySong: session.hasCurrentPlayerScores(forCatalogue: payload.observedPublicationId)
                    ? playerScoreIndex(songs: payload.catalog.songs) : nil,
                visibleInstruments: visibleInstruments, selectedInstrument: instrument,
                overThresholdLeeway: invalidScoreLeeway
            )
            MainThreadStallMonitor.count("songs.sort")
            return try SongCatalogSort.sorted(
                filtered, mode: mode, ascending: settings.sortAscending, shopSongIds: membership,
                chartScores: mode.isPlayerChartMode ? chartScores(for: payload) : nil
            )
        }
    }

    /// Group the sorted rows for the active sort (nil: an ungrouped list).
    ///
    /// Title/Artist use the A–Z scrubber; Year (decades), Duration (one-minute buckets),
    /// Item Shop and the Score/Percentile/Stars sorts use Quick Links.
    ///
    /// - Parameters:
    ///   - visible: Songs left after search and filters, in sort order.
    ///   - payload: The loaded catalogue.
    /// - Returns: The groups and whether the A–Z index shows, or nil groups for a flat list.
    func groups(visible: [Song], payload: CatalogPayload) -> (groups: [SongsListGroup]?, showsIndex: Bool) {
        let mode = effectiveSortMode
        let indexSections = SongSectionIndex.sections(visible, mode: mode)
        let showsIndex = indexSections.count > 1
        let shopSections = mode == .shop
            ? shopOffersForCurrentSongs.map { SongCatalogSort.shopSections(visible, offersById: $0) } : nil
        let durationSections = mode == .duration ? SongCatalogSort.durationSections(visible) : nil
        let yearSections = mode == .year ? SongCatalogSort.yearSections(visible) : nil
        let scoreSections = mode.isPlayerChartMode
            ? chartScores(for: payload).map { SongCatalogSort.scoreSections(visible, mode: mode, chartScores: $0) } : nil
        let groups = Self.listGroups(
            indexSections: showsIndex ? indexSections : nil, shopSections: shopSections,
            durationSections: durationSections, yearSections: yearSections, scoreSections: scoreSections
        )
        return (groups, showsIndex)
    }

    /// Group sorted rows by the active sort's sections.
    static func listGroups(
        indexSections: [SongSection]?, shopSections: [SongShopSection]?,
        durationSections: [SongDurationSection]?, yearSections: [SongYearSection]?,
        scoreSections: [SongScoreSection]? = nil
    ) -> [SongsListGroup]? {
        if let indexSections {
            return indexSections.map {
                SongsListGroup(
                    id: AnyHashable($0.id), label: $0.label,
                    accessibilityID: "fst.songs.section.\($0.id)", quickLink: nil, songs: $0.songs
                )
            }
        }
        func bucketed(_ kind: String, _ key: String, _ label: String, _ songs: [Song]) -> SongsListGroup {
            let link = QuickLinkSection(id: "\(kind):\(key)", title: label)
            return SongsListGroup(
                id: AnyHashable(link.id), label: label,
                accessibilityID: "fst.songs.\(kind)-section.\(key)", quickLink: link, songs: songs
            )
        }
        if let shopSections, shopSections.count > 1 {
            return shopSections.map { bucketed("shop", $0.kind.rawValue, $0.kind.label, $0.songs) }
        }
        if let durationSections, durationSections.count > 1 {
            return durationSections.map { bucketed("duration", $0.bucket.rawValue, $0.bucket.label, $0.songs) }
        }
        if let yearSections, yearSections.count > 1 {
            return yearSections.map { bucketed("year", $0.id, $0.label, $0.songs) }
        }
        if let scoreSections, scoreSections.count > 1 {
            return scoreSections.map { section in
                var group = bucketed("score", section.key, section.label, section.songs)
                group.spokenLabel = section.spokenLabel == section.label ? nil : section.spokenLabel
                return group
            }
        }
        return nil
    }

    // MARK: Disclosures

    /// The notices above the rows, in order.
    ///
    /// - Parameters:
    ///   - refreshFailure: The last catalogue refresh failure kept beside retained rows.
    ///   - shopRefreshFailure: The last Item Shop read failure.
    /// - Returns: Every applicable notice.
    func disclosures(refreshFailure: String?, shopRefreshFailure: String?) -> [SongsDisclosure] {
        guard let payload else { return [] }
        var items: [SongsDisclosure] = []
        if let refreshFailure { items.append(.refreshError(refreshFailure)) }
        if payload.publicationId == nil {
            items.append(.freshness(
                message: "Showing live songs without publication verification", symbol: "info.circle", identifier: nil
            ))
        }
        if let current = session.publicationId, payload.observedPublicationId != current {
            items.append(.freshness(message: "Publication changed - updating songs", symbol: "arrow.clockwise", identifier: nil))
        }
        if profilePublicationMismatch {
            items.append(.freshness(
                message: "Player scores paused until songs and player data share "
                    + "the current observed publication. Showing songs without player scores.",
                symbol: "pause.circle", identifier: "fst.songs.profile-paused"
            ))
        }
        if let message = playerScoreFilterPausedMessage {
            items.append(.freshness(message: message, symbol: "line.3.horizontal.decrease.circle", identifier: "fst.songs.score-filter-paused"))
        } else if hiddenPlayerScoreChecks {
            items.append(.freshness(
                message: "Player score checks for hidden charts are inactive. Visible chart checks still apply.",
                symbol: "eye.slash", identifier: "fst.songs.score-filter-hidden"
            ))
        }
        if let message = sortPausedMessage {
            items.append(.freshness(message: message, symbol: "arrow.up.arrow.down", identifier: "fst.songs.sort-paused"))
        }
        if let message = shopFilterPausedMessage {
            items.append(.freshness(message: message, symbol: "line.3.horizontal.decrease.circle", identifier: "fst.songs.filter-paused"))
        }
        if let selected = session.selectedPlayer {
            switch session.playerLoadState {
            case .loading:
                items.append(.freshness(
                    message: "Loading public scores for \(selected.displayName)", symbol: "hourglass",
                    identifier: "fst.songs.profile-status"
                ))
            case .syncing:
                items.append(.freshness(
                    message: "Player scores are syncing. No published score cards yet.",
                    symbol: "arrow.triangle.2.circlepath", identifier: "fst.songs.profile-status"
                ))
                items.append(.retryPlayer)
            case .failed, .none:
                items.append(.freshness(
                    message: "Player scores unavailable: \(session.playerError ?? "Not loaded")",
                    symbol: "exclamationmark.triangle", identifier: "fst.songs.profile-status"
                ))
                items.append(.retryPlayer)
            case .available:
                break
            }
        } else if let playerError = session.playerError {
            items.append(.freshness(message: playerError, symbol: "exclamationmark.triangle", identifier: "fst.songs.profile-status"))
            items.append(.chooseProfile)
        }
        if !settings.hideShop, let shopFailure = session.shopError ?? (session.currentShop == nil ? shopRefreshFailure : nil) {
            items.append(.freshness(
                message: "Item Shop status unavailable: \(shopFailure)", symbol: "exclamationmark.triangle",
                identifier: "fst.songs.shop-error"
            ))
            items.append(.retryShop)
        }
        return items
    }

    // MARK: Artwork

    /// Rows primed before the very first reveal, and how long priming may block it.
    static let artworkPrimeCount = 12
    static let artworkPrimeTimeout = Duration.milliseconds(900)

    /// Decodes the first visible rows' artwork before the very first reveal, so those rows
    /// hit the in-memory cache instantly once shown (no spinner flash). Bounded by
    /// ``artworkPrimeTimeout``.
    ///
    /// - Parameters:
    ///   - payload: Just-fetched catalogue, not yet shown.
    ///   - session: The artwork cache owner.
    ///   - instrument: The Songs instrument filter.
    ///   - settings: Saved sort.
    static func primeFirstArtwork(
        for payload: CatalogPayload, session: FestivalSession, instrument: Instrument?, settings: SongsSettings
    ) async {
        let filtered = payload.catalog.songs.filter { song in instrument.map(song.supports) ?? true }
        let sortMode = settings.sortMode
        let ordered = (try? SongCatalogSort.sorted(
            filtered, mode: sortMode == .shop || sortMode.isPlayerChartMode ? .title : sortMode,
            ascending: settings.sortAscending
        )) ?? filtered
        let artworkPaths = ordered.prefix(artworkPrimeCount)
            .compactMap { $0.albumArt?.isEmpty == false ? $0.albumArt : nil }
        guard !artworkPaths.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskGroup(of: Void.self) { downloads in
                    for raw in artworkPaths {
                        downloads.addTask {
                            _ = try? await session.preparedArtwork(raw: raw, maxPixels: 132)
                        }
                    }
                    await downloads.waitForAll()
                }
            }
            group.addTask {
                try? await Task.sleep(for: artworkPrimeTimeout)
            }
            await group.next()
            group.cancelAll()
        }
    }
}
