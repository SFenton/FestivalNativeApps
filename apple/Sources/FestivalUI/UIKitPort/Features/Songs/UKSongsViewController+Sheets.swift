#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Sort and Filter sheets

extension UKSongsViewController {
    /// Opens the Sort sheet (compact: medium and large detents with a grabber).
    func presentSort() {
        let pipeline = makePipeline()
        let sheet = UKSongsSortSheetController(
            mode: settings.sortMode, ascending: settings.sortAscending, showShop: !settings.hideShop,
            shopAvailable: pipeline.shopOffersForCurrentSongs != nil, playerModes: pipeline.playerSortModesOffered
        ) { mode, ascending in
            let defaults = UserDefaults.standard
            defaults.set(mode.rawValue, forKey: "fst.songs.sortMode")
            defaults.set(ascending, forKey: "fst.songs.sortAscending")
        }
        ukPresentSongsSheet(sheet, title: "Sort By", closeIdentifier: "fst.songs.sort.done", size: .compact) { sheetObserver = $0 }
    }

    /// Opens the Filter sheet (large detent).
    func presentFilter() {
        let pipeline = makePipeline()
        guard let general = pipeline.appliedGeneralFilter, let player = pipeline.appliedPlayerScoreFilter else { return }
        let inputs = UKSongsFilterSheetController.Inputs(
            appliedGeneral: general, showShop: !settings.hideShop, shopAvailable: pipeline.shopOffersForCurrentSongs != nil,
            availableDecades: SongGeneralFilter.decades(in: pipeline.catalogueSongs),
            availableDurations: SongGeneralFilter.durationBuckets(in: pipeline.catalogueSongs),
            appliedPlayerFilter: player, appliedInstrument: instrument, visibleInstruments: visibleInstruments,
            selectedPlayer: session.selectedPlayer != nil, scoreAvailable: pipeline.scoreFilterAvailable,
            invalidScoreFilteringEnabled: pipeline.invalidScoreLeeway != nil,
            availableSeasons: SongSeasonBucket.keys(in: pipeline.playerScoreIndex(songs: pipeline.catalogueSongs))
        )
        let sheet = UKSongsFilterSheetController(inputs) { [weak self] general, player, instrument in
            let playerData = try player.encoded()
            let generalData = try general.encoded()
            let defaults = UserDefaults.standard
            defaults.set(generalData, forKey: SongGeneralFilter.storageKey)
            defaults.set(false, forKey: SongGeneralFilter.legacyInShopKey)
            defaults.set(false, forKey: SongGeneralFilter.legacyLeavingTomorrowKey)
            defaults.set(playerData, forKey: SongPlayerScoreFilter.storageKey)
            self?.instrument = instrument
            self?.settings = SongsSettings.load()
            self?.normalizePlayerSort()
            self?.recompute()
        }
        ukPresentSongsSheet(sheet, title: "Filter Songs", closeIdentifier: "fst.songs.filter.done", size: .large) { sheetObserver = $0 }
    }

    /// Player sorts need one instrument: without one the web resets to Title A–Z.
    func normalizePlayerSort() {
        guard instrument == nil, settings.sortMode.isPlayerChartMode else { return }
        let defaults = UserDefaults.standard
        defaults.set(SongSortMode.title.rawValue, forKey: "fst.songs.sortMode")
        defaults.set(true, forKey: "fst.songs.sortAscending")
        settings = SongsSettings.load()
    }
}
#endif
