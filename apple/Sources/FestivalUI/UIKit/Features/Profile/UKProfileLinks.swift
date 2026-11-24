#if os(iOS)
import FestivalCore
import Foundation

// MARK: - Stat tile links

/// Where a tapped stat tile goes in the UIKit shell: the UIKit counterpart of the SwiftUI
/// root's ``PlayerStatNavigator`` installation. Routes push on the current section's stack;
/// Song Detail resolves the song from the cached catalogue first; a Songs filter preset is
/// saved and the Songs section is shown (web `navigateToSongs`).
@MainActor
enum UKProfileLinks {
    /// Posted (on the main queue) after a preset was saved to the Songs state, with the
    /// instrument filter the Songs root must apply in `userInfo["instrument"]` (an
    /// ``Instrument`` raw value, absent for none). The Songs lane's root observes it to set
    /// its own instrument filter and clear its search, as the SwiftUI root's `showSongs` does.
    static let songsPresetApplied = Notification.Name("fst.uikit.songs.preset-applied")

    /// Replaces the default Songs preset hand-off (the Songs lane may own the whole
    /// sequence). Receives the preset and the tapping screen's context.
    static var showSongsHandler: ((SongsFilterPreset, UKContext) -> Void)?

    /// Follows a tapped tile's link.
    ///
    /// - Parameters:
    ///   - link: The tile's link.
    ///   - context: The tapping screen's context.
    static func follow(_ link: PlayerStatLink, context: UKContext) {
        guard let navigator = context.navigator else { return }
        let stat = PlayerStatNavigator(
            push: { navigator.push($0) },
            showSongs: { preset in showSongs(preset, context: context) }
        )
        stat.follow(link, session: context.session)
    }

    /// Save a player-page tile's Songs filter, then show the Songs section at its root (web
    /// `navigateToSongs`: `saveSongSettings`, `setQuery('')`, `navigate('/songs')`).
    ///
    /// - Parameters:
    ///   - preset: The tapped tile's preset.
    ///   - context: The tapping screen's context.
    static func showSongs(_ preset: SongsFilterPreset, context: UKContext) {
        if let showSongsHandler {
            showSongsHandler(preset, context)
            return
        }
        let saved = SongsPresetStore.apply(preset, visibleInstruments: UKSettings.visibleInstruments(), instrument: nil)
        var info: [AnyHashable: Any] = [:]
        if let instrument = saved.instrument { info["instrument"] = instrument.rawValue }
        NotificationCenter.default.post(name: songsPresetApplied, object: nil, userInfo: info)
        context.navigator?.select(.songs)
    }
}
#endif
