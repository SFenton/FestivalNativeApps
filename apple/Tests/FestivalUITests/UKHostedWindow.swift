#if os(iOS)
import Testing
import UIKit

/// A real scene-backed window shared by UIKit architecture tests.
@MainActor
final class UKHostedWindow {
    private final class Host: UIViewController {
        var appeared = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appeared = true
        }
    }

    let window: UIWindow
    let root: UIViewController
    private let previous: UIWindow?

    private init(window: UIWindow, root: UIViewController, previous: UIWindow?) {
        self.window = window
        self.root = root
        self.previous = previous
    }

    /// Admits a foreground scene and waits for the host's actual appearance.
    static func make() async throws -> UKHostedWindow {
        try await wait {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let root = Host()
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = root
        window.makeKeyAndVisible()
        let harness = UKHostedWindow(window: window, root: root, previous: previous)
        do {
            try await wait { root.appeared && window.isKeyWindow }
        } catch {
            harness.close()
            throw error
        }
        return harness
    }

    /// Presents through UIKit, using its completion rather than guessed timing.
    func present(_ controller: UIViewController) async throws {
        var completed = false
        root.present(controller, animated: false) { completed = true }
        try await Self.wait { completed }
        try #require(root.presentedViewController === controller)
    }

    /// Restores the previous host after explicitly completed presentation checks.
    func close() {
        root.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
    }

    /// Waits boundedly for an observable native event.
    static func wait(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while !condition() {
            try #require(clock.now < deadline, "Native UIKit event did not complete")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
#endif
