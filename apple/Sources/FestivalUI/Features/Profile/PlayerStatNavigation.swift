import SwiftUI
import FestivalCore

// MARK: - Navigator environment

/// Root-owned navigation a player-page stat tile needs: push a route on the current
/// tab, or show the Songs tab with a filter preset (web `navigate('/songs')` after
/// `saveSongSettings`).
///
/// `FestivalRootView` installs it; without it (hosted previews and tests) stat tiles
/// that need it render as plain, non-interactive tiles rather than dead buttons.
///
/// Always equal, like `OpenProfileAction`: the root re-creates the closures on every
/// body pass, and the handlers only mutate root-owned state.
struct PlayerStatNavigator: Equatable {
    let push: @MainActor (AppRoute) -> Void
    let showSongs: @MainActor (SongsFilterPreset) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Stat-tile navigation installed by the root shell; nil outside it.
    @Entry var playerStatNavigator: PlayerStatNavigator?
}

// MARK: - Songs preset store

/// Reads and writes the Songs tab's saved state (its `@AppStorage` keys) so a preset
/// shows up as that tab's normal saved filters. The instrument filter is root `@State`,
/// so the root applies ``SongsSavedState/instrument`` itself.
enum SongsPresetStore {
    static let sortModeKey = "fst.songs.sortMode"
    static let sortAscendingKey = "fst.songs.sortAscending"

    /// Read the saved Songs state; a corrupt saved player or General filter reads as empty.
    ///
    /// - Parameters:
    ///   - defaults: Store the Songs tab's `@AppStorage` uses.
    ///   - instrument: Current root instrument filter.
    /// - Returns: The saved state.
    static func load(from defaults: UserDefaults, instrument: Instrument?) -> SongsSavedState {
        let filterData = defaults.data(forKey: SongPlayerScoreFilter.storageKey) ?? Data()
        return SongsSavedState(
            instrument: instrument,
            sortMode: defaults.string(forKey: sortModeKey).flatMap(SongSortMode.init(rawValue:)) ?? .title,
            sortAscending: defaults.object(forKey: sortAscendingKey) as? Bool ?? true,
            generalFilter: (try? SongGeneralFilter.decodeSaved(
                defaults.data(forKey: SongGeneralFilter.storageKey) ?? Data(),
                legacyInShop: defaults.bool(forKey: SongGeneralFilter.legacyInShopKey),
                legacyLeavingTomorrow: defaults.bool(forKey: SongGeneralFilter.legacyLeavingTomorrowKey)
            )) ?? SongGeneralFilter(),
            playerFilter: (try? SongPlayerScoreFilter.decodeSaved(filterData)) ?? SongPlayerScoreFilter()
        )
    }

    /// Write a saved Songs state.
    ///
    /// - Parameters:
    ///   - state: State to save.
    ///   - defaults: Store the Songs tab's `@AppStorage` uses.
    static func save(_ state: SongsSavedState, to defaults: UserDefaults) {
        defaults.set(state.sortMode.rawValue, forKey: sortModeKey)
        defaults.set(state.sortAscending, forKey: sortAscendingKey)
        defaults.set((try? state.generalFilter.encoded()) ?? Data(), forKey: SongGeneralFilter.storageKey)
        defaults.removeObject(forKey: SongGeneralFilter.legacyInShopKey)
        defaults.removeObject(forKey: SongGeneralFilter.legacyLeavingTomorrowKey)
        defaults.set((try? state.playerFilter.encoded()) ?? Data(), forKey: SongPlayerScoreFilter.storageKey)
    }

    /// Reset the saved Songs state after a deselect or a player/band switch (web
    /// `resetSongSettingsForDeselect`, ``SongsSavedState/resetForProfileChange()``).
    /// The instrument filter is root `@State`: roots clear it on
    /// `FestivalSession.songSettingsResetRevision`.
    ///
    /// - Parameter defaults: Store the Songs tab's `@AppStorage` uses.
    static func resetForProfileChange(in defaults: UserDefaults) {
        save(load(from: defaults, instrument: nil).resetForProfileChange(), to: defaults)
    }

    /// Apply a preset to the saved Songs state.
    ///
    /// - Parameters:
    ///   - preset: The tile's preset.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - instrument: Current root instrument filter.
    ///   - defaults: Store the Songs tab's `@AppStorage` uses.
    /// - Returns: The saved state, whose `instrument` the root applies.
    @discardableResult
    static func apply(
        _ preset: SongsFilterPreset, visibleInstruments: Set<Instrument>,
        instrument: Instrument?, defaults: UserDefaults = .standard
    ) -> SongsSavedState {
        let next = preset.applied(
            to: load(from: defaults, instrument: instrument), visibleInstruments: visibleInstruments
        )
        save(next, to: defaults)
        return next
    }
}
