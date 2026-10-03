import Foundation
import SwiftUI
import UIKit
import FestivalCore
import FestivalUI

/// System-owned iOS/iPadOS lifecycle and navigation chrome.
@main
struct FestivalMobileApp: App {
    @UIApplicationDelegateAdaptor(FestivalMobileAppDelegate.self) private var appDelegate

    /// Isolate visual fixture runs without changing production or other app settings.
    init() {
        #if DEBUG
        MainThreadStallMonitor.startIfRequested()
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
                SongGeneralFilter.legacyInShopKey,
                SongGeneralFilter.legacyLeavingTomorrowKey,
                SongGeneralFilter.storageKey,
                SongPlayerScoreFilter.storageKey,
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
        // iPadOS menu bar and ⌘-hold overlay (adds nothing on iPhone).
        .commands { FestivalCommands() }
    }
}

/// Supplies supported orientations only: iPhone stays portrait (Info.plist), iPad keeps
/// all four, and a device with a hinge (iPhone Duo) also rotates on its outer display
/// (operator decision O1 (b), 2026-10-02; `duo-notes.md`).
final class FestivalMobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        FestivalOrientationSupport.mask(for: window)
    }
}
