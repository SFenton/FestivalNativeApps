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
        // A/B perf autorun (`tools/uikit_perf.py`): the same code the SwiftUI app starts in `FestivalMobileApp`.
        ScrollCostAutorun.startIfRequested()
        #endif
    }

    /// The root controller for a new window.
    ///
    /// - Parameter userActivity: The activity an "Open in New Window" request carried,
    ///   if any.
    /// - Returns: The window's root.
    public static func makeRootViewController(userActivity: NSUserActivity? = nil) -> UIViewController {
        let root = UKRootViewController(windowRoute: nil)
        #if DEBUG
        PerfNavigationHooks.register(push: { [weak root] in root?.push($0) }, pop: { [weak root] in root?.pop() })
        #endif
        return root
    }
}
#endif
