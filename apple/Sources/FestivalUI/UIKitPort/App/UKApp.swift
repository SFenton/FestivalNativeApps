#if os(iOS)
import UIKit

private final class UKWeakRootBox {
    weak var value: UKRootViewController?
    init(_ value: UKRootViewController) { self.value = value }
}

// MARK: - Entry point

/// The UIKit app's entry point: the `FestivalMobileUIKit` target's scene delegate asks
/// for each window's root here (`apple/Apps/iOSUIKit`).
@MainActor
public enum UKApp {
    /// Process-wide launch work shared with the SwiftUI app (debug monitors and probes).
    public static func didFinishLaunching() {
        // Settings lane: the Notifications and What's New sheets, first-run carousels, launch What's New.
        UKSettingsRegistration.install()
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
        let rootBox = UKWeakRootBox(root)
        PerfNavigationHooks.register(push: { rootBox.value?.push($0) }, pop: { rootBox.value?.pop() })
        PerfNavigationHooks.registerModal(
            "profile",
            present: { rootBox.value?.presentProfile() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "global-search",
            present: { rootBox.value?.openSearch() },
            dismiss: { rootBox.value?.perform(.closeSearch) },
            isPresented: { rootBox.value?.searchActive == true }
        )
        PerfNavigationHooks.registerModal(
            "notifications",
            present: { rootBox.value?.presentNotifications() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "whats-new",
            present: { rootBox.value?.ukWhatsNew() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "songs-filter",
            present: { rootBox.value?.perfPresentSongsFilter() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "song-paths",
            present: { rootBox.value?.perfPresentSongPaths() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "suggestions-filter",
            present: { rootBox.value?.perfPresentSuggestionsFilter() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "feedback",
            present: { rootBox.value?.perfPresentFeedback() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerModal(
            "privacy-policy",
            present: { rootBox.value?.perfPresentPrivacyPolicy() },
            dismiss: { rootBox.value?.dismiss(animated: true) },
            isPresented: { rootBox.value?.presentedViewController != nil }
        )
        PerfNavigationHooks.registerComponent(
            "drawer",
            start: { rootBox.value?.openDrawer() },
            stop: { rootBox.value?.dismissDrawer() },
            isReady: { rootBox.value?.drawer != nil }
        )
        PerfNavigationHooks.registerComponent(
            "sheet",
            start: { rootBox.value?.presentProfile() },
            stop: { rootBox.value?.dismiss(animated: true) },
            isReady: { rootBox.value?.presentedViewController != nil }
        )
        let priorSection = root.selected
        PerfNavigationHooks.registerComponent(
            "section-stack",
            start: { rootBox.value?.select(.settings) },
            stop: { rootBox.value?.select(priorSection) },
            isReady: { rootBox.value?.selected == .settings }
        )
        let perfDebug = PerfComponentDebugState.shared
        PerfNavigationHooks.registerComponent(
            "row-press",
            start: { rootBox.value?.openDrawer(); PerfComponentDebugState.shared.rowPressed = true; UKDrawerRow.setDebugPressed(true) },
            stop: { PerfComponentDebugState.shared.rowPressed = false; UKDrawerRow.setDebugPressed(false); rootBox.value?.dismissDrawer() },
            isReady: { rootBox.value?.drawer != nil && UKDrawerRow.debugIsPressed }
        )
        PerfNavigationHooks.registerComponent(
            "edge-fade",
            start: { PerfComponentBuiltins.startEdgeFade() },
            stop: { PerfComponentBuiltins.stopEdgeFade() },
            isReady: { PerfComponentBuiltins.edgeFadeReady },
            isRestored: { PerfComponentBuiltins.edgeFadeRestored }
        )
        PerfNavigationHooks.registerComponent(
            "marquee",
            start: {
                perfDebug.beginMarqueeComponent()
                if rootBox.value?.selected != .songs { rootBox.value?.select(.songs) }
                perfDebug.marqueeRequested = true
            },
            stop: { perfDebug.marqueeRequested = false },
            isReady: { perfDebug.marqueeComponentReady },
            isRestored: { perfDebug.marqueeComponentRestored }
        )
        PerfNavigationHooks.registerComponent(
            "accordion",
            start: { rootBox.value?.perfToggleAccordion() },
            stop: { rootBox.value?.perfRestoreAccordion() },
            isReady: { rootBox.value?.perfAccordionIsOpen == true },
            isRestored: { rootBox.value?.perfAccordionIsOpen == false }
        )
        PerfNavigationHooks.registerComponent(
            "carousel",
            start: { rootBox.value?.perfPresentFirstRunCarousel() },
            stop: { rootBox.value?.perfStopFirstRunCarousel() },
            isReady: { rootBox.value?.perfFirstRunCarouselReady == true },
            isRestored: { rootBox.value?.perfFirstRunCarouselRestored == true }
        )
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
