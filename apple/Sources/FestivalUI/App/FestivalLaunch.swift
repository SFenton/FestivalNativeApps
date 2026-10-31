import Foundation
import FestivalCore
#if os(iOS)
import UIKit
#endif

// MARK: - Launch resolution

/// What a window opens with: the process's one ``FestivalSession`` and the debug launch
/// overrides (`FST_DEBUG_*`), resolved once and shared by ``FestivalRootView`` (SwiftUI)
/// and the UIKit port's root (`UIKitPort/App/UKRootViewController`), so both apps open
/// the same section, route and sheets for the same launch environment.
@MainActor
struct FestivalLaunch {
    /// The process's session (every window of this process shares it).
    let session: FestivalSession
    /// The section to select, already resolved against the visible tabs.
    let selected: FestivalSection
    /// The initial navigation path per section.
    let paths: [FestivalSection: [AppRoute]]
    /// `FST_DEBUG_TAB=search`: start on the Search tab.
    let opensSearch: Bool
    /// `FST_DEBUG_DRAWER=1`: start with the drawer open.
    let opensDrawer: Bool
    /// `FST_DEBUG_SHEET=profile`: start with the profile sheet presented.
    let opensProfileSheet: Bool

    /// Resolves a window's launch state.
    ///
    /// - Parameter windowRoute: The content an "Open in New Window" request opened this
    ///   window with, if any.
    /// - Returns: The session and initial selection for the window.
    static func resolve(windowRoute: FestivalWindowRoute? = nil) -> FestivalLaunch {
        var initialSection = FestivalSection.songs
        var selectionStorage: UserDefaults? = .standard
        var initialRoute: AppRoute?
        var debugSelectedPlayer: SelectedPlayerIdentity?
        var debugSelectedBand: SelectedBandIdentity?
        var opensSearch = false
        var opensDrawer = false
        var opensProfileSheet = false
        #if DEBUG
        let debug = DebugLaunchRoute(environment: ProcessInfo.processInfo.environment)
        if let tab = debug.section { initialSection = tab }
        opensSearch = debug.opensSearch
        initialRoute = debug.route
        opensDrawer = debug.opensDrawer
        opensProfileSheet = debug.opensProfileSheet
        // Once per process: SwiftUI may build the root view again (a new scene or an
        // App body pass), and clearing then would erase a selection the journey made
        // since launch, so a cold relaunch came back anonymous.
        if ProcessInfo.processInfo.environment["FST_UI_TEST_CLEAR_PROFILE"] == "1",
           !debugProfileCleared {
            debugProfileCleared = true
            UserDefaults.standard.removeObject(forKey: SelectedPlayerIdentity.storageKey)
            NotificationSeenStore.reset()
        }
        // In memory only: never written to `selectionStorage`. Parallel lanes share
        // one simulator, and writing this to real `UserDefaults.standard` (the
        // previous behavior) let one lane's debug launch clobber another lane's
        // actually-persisted selection.
        debugSelectedPlayer = debug.debugSelectedPlayer()
        debugSelectedBand = debug.debugSelectedBand()
        if debug.anonymous { selectionStorage = nil }
        #endif
        let session: FestivalSession
        if let shared = processSession {
            session = shared
        } else {
            let factory: @Sendable () throws -> FestivalAPI = {
                try FestivalRootView.makeClient(environment: ProcessInfo.processInfo.environment)
            }
            session = FestivalSession(
                factory: factory, selectionStorage: selectionStorage,
                debugSelectedPlayer: debugSelectedPlayer, debugSelectedBand: debugSelectedBand,
                liveConnection: PublicationLiveConnection.isEnabled() ? PublicationLiveConnection() : nil
            )
            processSession = session
        }
        if let windowRoute { initialSection = windowRoute.section }
        // A deep link or restored tab may name a section the stored profile hides. The
        // first geometry pass has not published a layout yet; the shell re-resolves
        // once it has.
        let profile: FestivalProfileKind =
            session.selectedPlayer == nil && !keepsProfileRoutes ? .none : .player
        let visible = ShellPresentation.resolve(
            layout: .standardPhone, usesSidebarShell: supportsSidebar
        ).sections(
            profile: profile,
            hideShop: UserDefaults.standard.bool(forKey: "fst.settings.hideShop")
        )
        let resolved = FestivalTabPolicy.resolve(initialSection, in: visible)
        // A section the phone tab bar dropped for the Search tab opens as the drawer
        // would: pushed on the resolved tab (issue #92).
        if initialRoute == nil {
            initialRoute = FestivalTabPolicy.searchTabOverflowRoute(
                for: initialSection, profile: profile, visible: visible
            )
        }
        var paths: [FestivalSection: [AppRoute]] = [:]
        if let initialRoute { paths = [resolved: [initialRoute]] }
        if let route = windowRoute?.immediateRoute { paths = [resolved: [route]] }
        return FestivalLaunch(
            session: session, selected: resolved, paths: paths, opensSearch: opensSearch,
            opensDrawer: opensDrawer, opensProfileSheet: opensProfileSheet
        )
    }

    /// The one session every window of this process shares (iPad multiple windows):
    /// a second window must see the same selected profile, publication and caches.
    private static var processSession: FestivalSession?

    #if DEBUG
    /// Whether this process already applied `FST_UI_TEST_CLEAR_PROFILE`.
    private static var debugProfileCleared = false
    #endif

    /// Debug launches with `FST_DEBUG_KEEP_PROFILE_ROUTES=1` keep the profile-only tabs
    /// and routes (`ProfileRoutePolicy`) without a player, so a journey can hold
    /// Statistics' otherwise momentary no-profile state open in the real shell (issue
    /// #341). Always false in Release.
    static var keepsProfileRoutes: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["FST_DEBUG_KEEP_PROFILE_ROUTES"] == "1"
        #else
        false
        #endif
    }

    /// iPad and macOS can show the sidebar; the phone idiom never does.
    static var supportsSidebar: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }
}
