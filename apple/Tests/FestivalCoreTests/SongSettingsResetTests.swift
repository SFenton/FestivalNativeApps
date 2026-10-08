import Testing
@testable import FestivalCore

// MARK: - Profile change rule

/// Web `shouldResetSongSettingsForProfileChange`: only leaving a profile resets (#359).
@Test func songSettingsResetFollowsWebProfileChangeRule() {
    #expect(!SongSettingsReset.shouldReset(from: nil, to: nil))
    #expect(!SongSettingsReset.shouldReset(from: nil, to: .player))
    #expect(!SongSettingsReset.shouldReset(from: nil, to: .band))
    #expect(SongSettingsReset.shouldReset(from: .player, to: nil))
    #expect(SongSettingsReset.shouldReset(from: .band, to: nil))
    #expect(SongSettingsReset.shouldReset(from: .player, to: .band))
    #expect(SongSettingsReset.shouldReset(from: .band, to: .player))
    #expect(!SongSettingsReset.shouldReset(from: .player, to: .player))
    #expect(!SongSettingsReset.shouldReset(from: .band, to: .band))
}

// MARK: - Reset state

/// Web `resetSongSettingsForDeselect`: filters and instrument default, a player chart
/// sort reverts to Title A–Z.
@Test func profileChangeResetClearsFiltersInstrumentAndPlayerSorts() throws {
    let general = SongGeneralFilter(excludedDecades: [1970], doubleBassSupported: false)
    let filter = SongPlayerScoreFilter(hasScores: [.lead])
    for mode in [SongSortMode.score, .percentile, .stars] {
        let saved = SongsSavedState(
            instrument: .lead, sortMode: mode, sortAscending: false,
            generalFilter: general, playerFilter: filter
        )
        #expect(saved.resetForProfileChange() == SongsSavedState())
    }
}

/// Catalogue sorts need no player, so they and their direction survive (web
/// `normalizeSongSettings` only touches instrument sorts).
@Test func profileChangeResetKeepsCatalogueSorts() {
    for mode in SongSortMode.allCases where !mode.isPlayerChartMode {
        let saved = SongsSavedState(
            instrument: .drums, sortMode: mode, sortAscending: false,
            playerFilter: SongPlayerScoreFilter(hasScores: [.drums])
        )
        #expect(saved.resetForProfileChange()
            == SongsSavedState(sortMode: mode, sortAscending: false))
    }
}
