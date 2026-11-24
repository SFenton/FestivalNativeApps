#if os(iOS)
import UIKit

// MARK: - Entry point

/// The UIKit app's entry point: the `FestivalMobile` target's scene delegate asks
/// for each window's root here.
@MainActor
public enum UKApp {
    /// Process-wide setup for feature registration and launch diagnostics.
    public static func didFinishLaunching() {
        NavigationTitleStyle.apply()
        // Settings lane: the Notifications and What's New sheets, first-run carousels, launch What's New.
        UKSettingsRegistration.install()
        #if DEBUG
        MainThreadStallMonitor.startIfRequested()
        ScrollFlingStressRunner.startIfRequested()
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

    /// The iPadOS menu bar and ⌘-hold overlay (adds nothing on iPhone).
    ///
    /// - Parameter builder: The app delegate's main menu builder.
    public static func buildMenu(with builder: any UIMenuBuilder) {
        UKMenuBar.build(with: builder)
    }
}
#endif
