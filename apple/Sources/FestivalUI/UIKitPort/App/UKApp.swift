#if os(iOS)
import UIKit

// MARK: - Entry point

/// The UIKit app's entry point: the `FestivalMobileUIKit` target's scene delegate asks
/// for each window's root here (`apple/Apps/iOSUIKit`).
@MainActor
public enum UKApp {
    /// Process-wide launch work shared with the SwiftUI app (debug monitors and probes).
    public static func didFinishLaunching() {
        #if DEBUG
        MainThreadStallMonitor.startIfRequested()
        #endif
    }

    /// The root controller for a new window.
    ///
    /// - Parameter userActivity: The activity an "Open in New Window" request carried,
    ///   if any.
    /// - Returns: The window's root.
    public static func makeRootViewController(userActivity: NSUserActivity? = nil) -> UIViewController {
        #if DEBUG
        // Design lane: `FST_UIKIT_GALLERY=design` shows the design-primitive gallery.
        if ProcessInfo.processInfo.environment["FST_UIKIT_GALLERY"] == "design" {
            return UINavigationController(rootViewController: UKDesignGalleryViewController())
        }
        #endif
        return UKRootViewController(windowRoute: nil)
    }
}
#endif
