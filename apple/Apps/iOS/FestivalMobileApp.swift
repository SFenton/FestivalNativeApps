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
        FestivalLaunchResets.applyIfRequested()
        // A/B perf autorun (`tools/uikit_perf.py`); the UIKit port starts the same code in `UKApp`.
        ScrollCostAutorun.startIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            FestivalRootView()
        }
        // iPadOS menu bar and ⌘-hold overlay (adds nothing on iPhone).
        .commands { FestivalCommands() }

        // iPad "Open in New Window" (a song or player row's context menu). Every window
        // shares one session and keeps its own navigation.
        WindowGroup(for: FestivalWindowRoute.self) { $route in
            FestivalRootView(windowRoute: route)
        }
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
