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
        #endif
    }

    var body: some Scene {
        WindowGroup {
            FestivalRootView()
        }
    }
}
