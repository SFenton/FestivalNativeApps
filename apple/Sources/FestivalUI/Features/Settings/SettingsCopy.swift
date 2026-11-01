import Foundation
import FestivalCore

// MARK: - Settings copy

/// Strings and small state mappings the Settings page computes inline, shared by the
/// SwiftUI ``SettingsScreen`` and the UIKit port so both read and say the same thing.
enum SettingsCopy {
    /// The Accessibility card's description.
    ///
    /// - Parameter systemSettingsName: Where system accessibility options live ("device Settings").
    /// - Returns: The sentence-case description.
    static func accessibilitySubtitle(systemSettingsName: String) -> String {
        "Off follows your device; On adds an app override. "
            + "VoiceOver and text size are managed in \(systemSettingsName)."
    }

    /// Where system accessibility options live on iPhone and iPad.
    static let deviceSettingsName = "device Settings"

    /// The Show Instrument Metadata card's description.
    ///
    /// - Parameters:
    ///   - hasPlayer: Whether a player is selected.
    ///   - showInstrumentIcons: `fst.settings.showInstrumentIcons`.
    /// - Returns: The sentence-case description.
    static func metadataSubtitle(hasPlayer: Bool, showInstrumentIcons: Bool) -> String {
        hasPlayer == false
            ? "Select a player to customize score metadata."
            : showInstrumentIcons
                ? "With icons and All instruments, status chips replace score "
                    + "metadata. Turn icons off or filter one chart to show these fields."
                : "Visible score fields update Songs cards. Enable Independent Song Row "
                    + "Visual Order above to choose which field leads; Last Played sort is "
                    + "still being ported."
    }

    /// A metadata switch's accessibility hint.
    ///
    /// - Parameters:
    ///   - field: Metadata setting that supplies a Song-row label or meter.
    ///   - hasPlayer: Whether a player is selected.
    /// - Returns: Explanation of the actual currently supported row effect.
    static func metadataHint(for field: MetadataField, hasPlayer: Bool) -> String {
        if field == .intensity {
            return "Controls song Intensity on selected score cards or filtered anonymous rows"
        }
        if field == .lastPlayed {
            return hasPlayer == false
                ? "Select a player to show the saved date"
                : "Shows the saved date on native Songs cards; Last Played sort is not yet available"
        }
        return hasPlayer == false
            ? "Select a player to use score metadata"
            : "Updates Songs score fields when icons are off or one chart is filtered"
    }

    /// Debug vs Release, useful context when a user reports a bug.
    static var buildConfigurationText: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    /// The live service build text, "Loading" until it answers.
    ///
    /// - Parameters:
    ///   - version: The version read from `GET /api/version`, if any.
    ///   - failed: Whether the read failed.
    /// - Returns: The row's value.
    static func serviceVersionText(version: String?, failed: Bool) -> String {
        version ?? (failed ? "Unavailable" : "Loading")
    }

    /// Whether an instrument switch is disabled: the last visible chart stays on.
    ///
    /// - Parameters:
    ///   - isShown: Whether this instrument is currently shown.
    ///   - visibleCount: How many instruments are shown.
    /// - Returns: True when the switch must be disabled.
    static func instrumentSwitchDisabled(isShown: Bool, visibleCount: Int) -> Bool {
        isShown && visibleCount <= 1
    }

    /// Whether a metadata switch is disabled: score fields need a selected player.
    ///
    /// - Parameters:
    ///   - field: The metadata field.
    ///   - hasPlayer: Whether a player is selected.
    /// - Returns: True when the switch must be disabled.
    static func metadataSwitchDisabled(_ field: MetadataField, hasPlayer: Bool) -> Bool {
        hasPlayer == false && field != .intensity
    }
}
