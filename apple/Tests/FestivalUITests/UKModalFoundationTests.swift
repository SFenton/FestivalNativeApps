#if os(iOS)
    import Testing
    import UIKit
    import FestivalCore
    @testable import FestivalUI

    /// Focused UIKit modal-shell checks using a real window presentation lifecycle.
    extension UKFoundationTests {
        @MainActor
        struct UKModalFoundationTests {
            private final class Host: UIViewController {
                var appeared = false

                override func viewDidAppear(_ animated: Bool) {
                    super.viewDidAppear(animated)
                    appeared = true
                }
            }

            private final class FeaturePage: UIViewController {
                let featureAction = UIBarButtonItem(title: "Apply", style: .done, target: nil, action: nil)

                override func viewDidLoad() {
                    super.viewDidLoad()
                    view.backgroundColor = .systemBackground
                    navigationItem.rightBarButtonItem = featureAction
                }
            }

            private final class ScrollPage: UIViewController, UKModalScrollProviding {
                let scroll = UIScrollView()

                var ukModalScrollView: UIScrollView? { scroll }

                override func viewDidLoad() {
                    super.viewDidLoad()
                    view.backgroundColor = .systemBackground
                    scroll.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(scroll)
                    NSLayoutConstraint.activate([
                        scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                        scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                        scroll.topAnchor.constraint(equalTo: view.topAnchor),
                        scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    ])
                }
            }

            private final class SearchPage: UIViewController, UISearchControllerDelegate {
                let search = UISearchController(searchResultsController: nil)
                var searchPresented = false

                override func viewDidLoad() {
                    super.viewDidLoad()
                    view.backgroundColor = .systemBackground
                    definesPresentationContext = true
                    search.delegate = self
                    search.obscuresBackgroundDuringPresentation = false
                    search.hidesNavigationBarDuringPresentation = false
                    search.obscuresBackgroundDuringPresentation = false
                    search.hidesNavigationBarDuringPresentation = false
                    navigationItem.searchController = search
                    navigationItem.hidesSearchBarWhenScrolling = false
                }

                func didPresentSearchController(_ searchController: UISearchController) {
                    searchPresented = true
                }
            }

            private struct OfflineTransport: HTTPTransport {
                func send(_ request: URLRequest) async throws -> HTTPResult {
                    throw URLError(.notConnectedToInternet)
                }
            }

            private func waitUntil(
                _ condition: @escaping @MainActor () -> Bool,
                timeoutNanoseconds: UInt64 = 10_000_000_000,
                fileID: String = #fileID,
                line: Int = #line
            ) async throws {
                let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
                while !condition() {
                    if DispatchTime.now().uptimeNanoseconds >= deadline {
                        Issue.record("Timed out waiting for UIKit modal lifecycle at \(fileID):\(line)")
                        throw WindowError.lifecycleTimeout
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            }

            private func present(
                _ sheet: UKSheetNavigationController, by host: Host
            ) async throws {
                var completed = false
                host.present(sheet, animated: false) { completed = true }
                try await waitUntil { completed }
                try #require(sheet.presentingViewController === host)
                try #require(sheet.viewIfLoaded?.window != nil)
            }

            private func dismiss(_ controller: UIViewController) async {
                await withCheckedContinuation { continuation in
                    controller.dismiss(animated: true) {
                        continuation.resume()
                    }
                }
            }

            private struct WindowHarness {
                let window: UIWindow
                let previousKeyWindow: UIWindow?
            }

            private enum WindowError: Error {
                case noConnectedWindowScene
                case lifecycleTimeout
            }

            private func makeWindow(root: Host) async throws -> WindowHarness {
                try await waitUntil(
                    {
                        UIApplication.shared.connectedScenes.contains {
                            ($0 as? UIWindowScene)?.activationState == .foregroundActive
                        }
                    },
                    timeoutNanoseconds: 10_000_000_000
                )
                guard
                    let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.activationState == .foregroundActive })
                else {
                    Issue.record("UIKit modal test requires a connected UIWindowScene")
                    throw WindowError.noConnectedWindowScene
                }
                let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
                let window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                window.rootViewController = root
                window.makeKeyAndVisible()
                let harness = WindowHarness(window: window, previousKeyWindow: previousKeyWindow)
                do {
                    try await waitUntil {
                        root.appeared && root.viewIfLoaded?.window === window && window.isKeyWindow
                    }
                } catch {
                    cleanup(harness)
                    throw error
                }
                return harness
            }

            private func cleanup(_ harness: WindowHarness) {
                harness.window.rootViewController?.dismiss(animated: false)
                harness.window.isHidden = true
                harness.window.rootViewController = nil
                harness.previousKeyWindow?.makeKeyAndVisible()
            }

            @Test func presentedHeaderKeepsFeatureActionAndCloseAtTheTrailingEdge() async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                let page = FeaturePage()
                let sheet = UKSheet.make(page, title: "Sort By", closeIdentifier: "fst.modal.close")

                try await present(sheet, by: host)

                let items = sheet.viewControllers[0].navigationItem.rightBarButtonItems ?? []
                try #require(items.count == 2)
                #expect(items[0].accessibilityIdentifier == "fst.modal.close")
                #expect(items[1] === page.featureAction)
                #expect(page.navigationItem.title == "Sort By")

                sheet.dismissFromPresenter(animated: false)
                try await waitUntil { host.presentedViewController == nil }
            }

            @Test(arguments: [false, true])
            func dismissedSheetDoesNotRetainItselfThroughCallbacks(customClose: Bool) async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                var observer: UKSongsSheetDismissObserver?
                weak var sheet: UKSheetNavigationController?
                if customClose {
                    // Model legacy app-owned callbacks that close their captured sheet.
                    var capturedSheet: UKSheetNavigationController?
                    capturedSheet = UKSheet.make(
                        FeaturePage(), title: "Modal", closeIdentifier: "fst.modal.close",
                        onClose: { capturedSheet?.dismissFromPresenter(animated: true) }
                    )
                    sheet = capturedSheet
                    if let capturedSheet { host.present(capturedSheet, animated: false) }
                } else {
                    host.ukPresentSongsSheet(
                        FeaturePage(), title: "Sort By", closeIdentifier: "fst.modal.close", size: .compact
                    ) { observer = $0 }
                    sheet = host.presentedViewController as? UKSheetNavigationController
                }
                try await waitUntil {
                    sheet?.view.window != nil && sheet?.isBeingPresented == false
                        && sheet?.transitionCoordinator == nil
                }

                sheet?.ukCloseFromChrome()
                try await waitUntil { host.presentedViewController == nil }
                try await waitUntil { sheet == nil }
                #expect(customClose || observer != nil)
            }

            @Test func shellPlaceholderUsesNativeSheetChrome() throws {
                let client = try FestivalAPI(transport: OfflineTransport())
                let session = FestivalSession(factory: { client })
                let previous = UKShellSheets.notificationsFactory
                defer { UKShellSheets.notificationsFactory = previous }
                UKShellSheets.notificationsFactory = nil

                let sheet = UKShellSheets.notifications(session) { _ in }
                let page = try #require(sheet.viewControllers.first)
                page.loadViewIfNeeded()
                #expect(page.navigationItem.title == "Notifications")
                #expect(
                    page.navigationItem.rightBarButtonItems?.first?.accessibilityIdentifier == "fst.sheet.close"
                )
                #expect(sheet.modalPresentationStyle == .pageSheet)
            }

            @Test(arguments: [false, true])
            func activeSearchCloseDismissesTheOuterModal(programmatic: Bool) async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                let page = SearchPage()
                let sheet = UKSheet.make(page, title: "Search", closeIdentifier: "fst.modal.close")
                var dismissals = 0
                sheet.ukOnDismiss = {
                    #expect(host.presentedViewController == nil)
                    dismissals += 1
                }

                try await present(sheet, by: host)
                page.search.searchResultsUpdater = nil
                sheet.view.layoutIfNeeded()
                page.search.isActive = true
                try await waitUntil {
                    page.search.searchBar.searchTextField.window != nil
                        && page.search.searchBar.searchTextField.bounds.height > 0
                }
                try #require(page.search.searchBar.searchTextField.becomeFirstResponder())
                do {
                    try await waitUntil {
                        page.searchPresented
                            && page.search.isActive
                            && page.search.presentingViewController != nil
                            && page.search.viewIfLoaded?.window != nil
                    }
                } catch {
                    let diagnostic: String =
                        "Search readiness: active=\(page.search.isActive), callback=\(page.searchPresented), "
                        + "presenter=\(String(describing: page.search.presentingViewController)), "
                        + "window=\(page.search.viewIfLoaded?.window != nil), "
                        + "firstResponder=\(page.search.searchBar.searchTextField.isFirstResponder)"
                    Issue.record("\(diagnostic)")
                    throw error
                }

                #expect(
                    page.navigationItem.rightBarButtonItems?.contains(where: {
                        $0.accessibilityIdentifier == "fst.modal.close"
                    }) == true
                )
                if programmatic {
                    UKShellSheets.dismiss(page)
                } else {
                    sheet.ukCloseFromChrome()
                }
                try await waitUntil { host.presentedViewController == nil && dismissals == 1 }
                try await waitUntil { page.search.presentingViewController == nil }
                #expect(!page.search.isActive)
            }

            @Test func poppedScrollPageReleasesFadeAndController() async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                let root = ScrollPage()
                let sheet = UKSheet.make(root, title: "Modal", closeIdentifier: "fst.modal.close")
                try await present(sheet, by: host)

                var pushed: ScrollPage? = ScrollPage()
                weak var weakPushed = pushed
                sheet.pushViewController(pushed!, animated: true)
                try await waitUntil { sheet.topViewController === pushed && sheet.transitionCoordinator == nil }
                try await waitUntil { pushed?.view.layer.mask != nil }

                _ = sheet.popViewController(animated: false)
                try await waitUntil { sheet.topViewController === root && pushed?.view.layer.mask == nil }
                pushed = nil
                try await waitUntil { weakPushed == nil }

                sheet.dismissFromPresenter(animated: false)
                try await waitUntil { host.presentedViewController == nil }
            }

            @Test func repeatedAppOwnedCloseWaitsForKeepEditingThenRearms() async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                var closeCount = 0
                var sheet: UKSheetNavigationController!
                let root = FeaturePage()
                sheet = UKSheet.make(
                    root,
                    title: "Feedback",
                    closeIdentifier: "fst.modal.close",
                    onClose: {
                        closeCount += 1
                        let alert = UIAlertController(
                            title: "Discard this report?",
                            message: "Your text will be lost.",
                            preferredStyle: .alert
                        )
                        alert.addAction(
                            UIAlertAction(title: "Keep Editing", style: .cancel) { _ in
                                sheet.ukRearmClose()
                            })
                        sheet.present(alert, animated: false)
                    }
                )
                try await present(sheet, by: host)

                sheet.ukCloseFromChrome()
                try await waitUntil { sheet.presentedViewController is UIAlertController }
                sheet.ukCloseFromChrome()
                #expect(closeCount == 1)

                if let alert = sheet.presentedViewController {
                    await dismiss(alert)
                }
                try await waitUntil { sheet.presentedViewController == nil && sheet.transitionCoordinator == nil }
                sheet.ukRearmClose()
                sheet.ukCloseFromChrome()
                try await waitUntil { sheet.presentedViewController is UIAlertController }
                #expect(closeCount == 2)

                if let alert = sheet.presentedViewController {
                    await dismiss(alert)
                }
                try await waitUntil { sheet.presentedViewController == nil && sheet.transitionCoordinator == nil }
                sheet.dismissFromPresenter(animated: false)
                try await waitUntil { host.presentedViewController == nil }
            }

            @Test func realDismissalBalancesCoverage() async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                let before = FestivalSheetCoverage.shared.count
                let sheet = UKSheet.make(FeaturePage(), title: "Modal", closeIdentifier: "fst.modal.close")

                try await present(sheet, by: host)
                try await waitUntil { FestivalSheetCoverage.shared.count == before + 1 }
                sheet.dismissFromPresenter(animated: false)
                try await waitUntil {
                    host.presentedViewController == nil
                        && FestivalSheetCoverage.shared.count == before
                }
            }

            @Test func escapePopsBeforeRootCloseAndPreservesAppOwnedCallback() async throws {
                let host = Host()
                let harness = try await makeWindow(root: host)
                defer { cleanup(harness) }
                var closeCount = 0
                let root = FeaturePage()
                let sheet = UKSheet.make(
                    root,
                    title: "Modal",
                    closeIdentifier: "fst.modal.close",
                    onClose: { closeCount += 1 }
                )
                try await present(sheet, by: host)

                let pushed = FeaturePage()
                sheet.pushViewController(pushed, animated: true)
                sheet.ukCloseFromChrome()
                #expect(closeCount == 0)
                try await waitUntil { sheet.topViewController === pushed && sheet.transitionCoordinator == nil }

                #expect(sheet.accessibilityPerformEscape())
                #expect(sheet.accessibilityPerformEscape())
                try await waitUntil { sheet.topViewController === root && sheet.transitionCoordinator == nil }
                #expect(closeCount == 0)

                #expect(sheet.accessibilityPerformEscape())
                #expect(closeCount == 1)
                sheet.dismissFromPresenter(animated: false)
                try await waitUntil { host.presentedViewController == nil }
            }
        }
    }
#endif
