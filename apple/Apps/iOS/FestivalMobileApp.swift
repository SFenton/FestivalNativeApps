import Foundation
import SwiftUI
import FestivalUI

/// System-owned iOS/iPadOS lifecycle and navigation chrome.
@main
struct FestivalMobileApp: App {
    /// Isolate visual fixture runs without changing production or other app settings.
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FST_UI_TEST_RESET_VISUALS"] == "1" {
            for key in [
                "fst.accessibility.reduceMotion",
                "fst.accessibility.disableAnimatedArtwork",
                "fst.accessibility.lessTransparency",
                "fst.accessibility.moreContrast",
            ] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if ProcessInfo.processInfo.environment["FST_UI_TEST_RESET_SONG_CARDS"] == "1" {
            for key in [
                "fst.settings.showInstrumentIcons",
                "fst.settings.filterInvalidScores",
                "fst.settings.leeway",
                "fst.settings.showLead",
                "fst.settings.showBass",
                "fst.settings.showDrums",
                "fst.settings.showVocals",
                "fst.settings.showProLead",
                "fst.settings.showProBass",
                "fst.settings.showKaraoke",
                "fst.settings.showProCymbals",
                "fst.settings.showProDrums",
                "fst.settings.metadataScore",
                "fst.settings.metadataPercentage",
                "fst.settings.metadataPercentile",
                "fst.settings.metadataSeason",
                "fst.settings.metadataIntensity",
                "fst.settings.metadataDifficulty",
                "fst.settings.metadataStars",
                "fst.settings.metadataLastPlayed",
                "fst.songs.filterInShop",
                "fst.songs.filterLeavingTomorrow",
            ] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if ProcessInfo.processInfo.environment["FST_UI_TEST_RESET_PATH_WARNING"] == "1" {
            UserDefaults.standard.removeObject(
                forKey: "fst.settings.pathUnavailableWarningDismissed"
            )
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            FestivalRootView()
        }
    }
}
