import FestivalCore
import FestivalUI
import OSLog
import UIKit

/// The universal iOS app's UIKit entry point.
@main
final class FestivalMobileAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FestivalLaunchResets.applyIfRequested()
        UKApp.didFinishLaunching()
        NotificationCenter.default.addObserver(
            self, selector: #selector(recoverLegacyWindow(_:)),
            name: UIScene.willEnterForegroundNotification, object: nil
        )
        return true
    }

    /// Reconnects a SwiftUI-era session that UIKit foregrounds without an app window.
    ///
    /// - Parameter notification: The system's scene foreground event.
    @objc private func recoverLegacyWindow(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene,
              scene.session.role == .windowApplication,
              !(scene.delegate is UKSceneDelegate),
              !scene.windows.contains(where: { $0.windowLevel == .normal && $0.rootViewController != nil })
        else { return }
        Logger(subsystem: "com.sfenton.festivalscoretracker.native", category: "Scene")
            .notice("Reconnecting a restored application scene without the UIKit scene delegate")
        let delegate = UKSceneDelegate()
        scene.delegate = delegate
        delegate.connect(scene, userActivity: scene.session.stateRestorationActivity)
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        UKApp.buildMenu(with: builder)
    }

    /// iPhone stays portrait (Info.plist), iPad keeps all four, and a device with a hinge
    /// (iPhone Duo) also rotates on its outer display.
    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        FestivalOrientationSupport.mask(for: window)
    }
}

/// One window: its root comes from ``UKApp``.
final class UKSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        connect(scene, userActivity: connectionOptions.userActivities.first ?? session.stateRestorationActivity)
    }

    /// Attaches the shared UIKit root to a new or reconnected application window.
    ///
    /// - Parameters:
    ///   - scene: The application's scene.
    ///   - userActivity: A requested or restored window route, if any.
    func connect(_ scene: UIWindowScene, userActivity: NSUserActivity?) {
        guard window == nil else { return }
        let window = UIWindow(windowScene: scene)
        // The app is dark everywhere (SwiftUI's `preferredColorScheme(.dark)` darkens the
        // window): system glass, sheets and bars take their style from the window.
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UKApp.makeRootViewController(userActivity: userActivity)
        self.window = window
        window.makeKeyAndVisible()
    }
}
