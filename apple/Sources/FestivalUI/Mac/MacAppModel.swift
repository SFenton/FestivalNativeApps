#if os(macOS)
import Foundation
import Observation
import FestivalCore

// MARK: - App model

/// Process-wide state of the macOS app: the one keyless ``FestivalSession`` and the
/// primary window's ``MacNavigationModel``, shared by the window, the Settings window
/// and the menu bar commands.
@MainActor @Observable
public final class MacAppModel {
    /// Shared session (selected player, caches, first-run coordinator).
    let session: FestivalSession
    /// Primary window navigation.
    let navigation: MacNavigationModel

    /// Create the app model from the launch environment (Debug deep links honoured).
    public convenience init() {
        var selectionStorage: UserDefaults? = .standard
        var debugPlayer: SelectedPlayerIdentity?
        var initial: MacDestination?
        var initialRoute: AppRoute?
        #if DEBUG
        let debug = DebugLaunchRoute(environment: ProcessInfo.processInfo.environment)
        initial = debug.section.flatMap(MacSidebarPolicy.destination(for:))
        if let route = debug.route {
            if let destination = MacSidebarPolicy.destination(for: route) {
                initial = destination
            } else {
                initialRoute = route
            }
        }
        debugPlayer = debug.debugSelectedPlayer()
        if debug.anonymous { selectionStorage = nil }
        #endif
        let session = FestivalSession(
            factory: { try FestivalRootView.makeClient(environment: ProcessInfo.processInfo.environment) },
            selectionStorage: selectionStorage, debugSelectedPlayer: debugPlayer
        )
        self.init(
            session: session, storage: initial == nil ? .standard : nil,
            initial: initial, initialRoute: initialRoute
        )
        #if DEBUG
        if debug.opensProfileSheet { navigation.profilePresented = true }
        #endif
    }

    /// Create the app model around an existing session (hosted tests).
    ///
    /// - Parameters:
    ///   - session: Shared session.
    ///   - storage: Where the sidebar selection persists; nil keeps it in memory.
    ///   - initial: Initial destination override.
    ///   - initialRoute: A route pushed on the initial destination.
    init(
        session: FestivalSession, storage: UserDefaults?, initial: MacDestination? = nil,
        initialRoute: AppRoute? = nil
    ) {
        self.session = session
        let hideShop = UserDefaults.standard.bool(forKey: "fst.settings.hideShop")
        let visible = MacSidebarPolicy.destinations(
            hasPlayer: session.selectedPlayer != nil, hideShop: hideShop
        )
        navigation = MacNavigationModel(storage: storage, initial: initial, visible: visible)
        if let initialRoute { navigation.push(initialRoute) }
    }
}
#endif
