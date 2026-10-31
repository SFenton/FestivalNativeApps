import FestivalCore
import FestivalUI
import UIKit

/// The UIKit port's app delegate: the same launch work and orientation rules as the
/// SwiftUI app (`FestivalMobileApp`), with every window's root drawn by UIKit
/// (`FestivalUI/UIKitPort`, ``UKSceneDelegate``).
@main
final class UKAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FestivalLaunchResets.applyIfRequested()
        UKApp.didFinishLaunching()
        return true
    }

    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = UKSceneDelegate.self
        return configuration
    }

    /// iPhone stays portrait (Info.plist), iPad keeps all four, and a device with a hinge
    /// (iPhone Duo) also rotates on its outer display, as in the SwiftUI app.
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
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UKApp.makeRootViewController(
            userActivity: connectionOptions.userActivities.first ?? session.stateRestorationActivity
        )
        window.makeKeyAndVisible()
        self.window = window
    }
}
