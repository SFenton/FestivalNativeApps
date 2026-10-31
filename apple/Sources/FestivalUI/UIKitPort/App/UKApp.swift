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
        #if DEBUG
        // Design lane: `FST_UIKIT_GALLERY=design` shows the design-primitive gallery.
        if let gallery = ProcessInfo.processInfo.environment["FST_UIKIT_GALLERY"], gallery.hasPrefix("design") {
            let ids = gallery.split(separator: ":", maxSplits: 1).dropFirst().first
                .map { Set($0.split(separator: ",").map(String.init)) }
            return UINavigationController(rootViewController: UKDesignGalleryViewController(only: ids))
        }
        #endif
        let root = UKRootViewController(windowRoute: UKWindows.route(from: userActivity))
        #if DEBUG
        PerfNavigationHooks.register(push: { [weak root] in root?.push($0) }, pop: { [weak root] in root?.pop() })
        // Song Detail lane: `FST_UIKIT_DEBUG_SONGDETAIL=<songId>` pushes a song's page.
        UKSongDetailDebug.openIfRequested(on: root)
        #endif
        return root
    }

    /// The iPadOS menu bar and ⌘-hold overlay, the UIKit counterpart of `FestivalCommands`
    /// (adds nothing on iPhone).
    ///
    /// - Parameter builder: The app delegate's main menu builder.
    public static func buildMenu(with builder: any UIMenuBuilder) {
        UKMenuBar.build(with: builder)
    }
}
#endif
