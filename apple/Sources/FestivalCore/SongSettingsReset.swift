import Foundation

// MARK: - Profile change reset

/// Which kind of profile scopes the Songs settings (web `SelectedProfile.type`).
public enum SongsProfileScope: Sendable, Equatable {
    /// A selected player.
    case player
    /// A selected band.
    case band
}

/// When a profile change resets the saved Songs settings, ported from the web's
/// `shouldResetSongSettingsForProfileChange` (`state/selectedProfile.ts`).
public enum SongSettingsReset {
    /// Whether moving between two profiles resets Songs (issue #359).
    ///
    /// Deselecting any profile, or switching between a player and a band, resets;
    /// choosing a first profile or switching player to player (or band to band) keeps
    /// the saved filters and sort.
    ///
    /// - Parameters:
    ///   - previous: The profile scope before the change, or nil when none was selected.
    ///   - next: The profile scope after the change, or nil after a deselect.
    /// - Returns: True when Songs must return to its default filters and instrument.
    public static func shouldReset(from previous: SongsProfileScope?, to next: SongsProfileScope?) -> Bool {
        guard let previous else { return false }
        guard let next else { return true }
        return previous != next
    }
}

extension SongsSavedState {
    /// The web's `resetSongSettingsForDeselect` (`utils/songSettings.ts`): every filter
    /// (General and player score checks) and the instrument return to their defaults,
    /// and a selected-player chart sort, which needs an instrument, reverts to Title A–Z
    /// (`normalizeSongSettings`). Other sorts and their direction are kept.
    ///
    /// - Returns: The saved state after a deselect or a player/band switch.
    public func resetForProfileChange() -> SongsSavedState {
        let keepsSort = !sortMode.isPlayerChartMode
        return SongsSavedState(
            instrument: nil,
            sortMode: keepsSort ? sortMode : .title,
            sortAscending: keepsSort ? sortAscending : true
        )
    }
}
