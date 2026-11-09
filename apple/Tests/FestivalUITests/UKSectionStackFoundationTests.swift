#if os(iOS)
    import FestivalCore
    import Testing
    import UIKit
    @testable import FestivalUI

    extension UKFoundationTests {
        @MainActor
        struct UKSectionStackFoundationTests {
            private final class Page: UIViewController {
                let originalAction = UIBarButtonItem(title: "Original", style: .plain, target: nil, action: nil)
                let scroll = UIScrollView()
                var disappearances = 0
                var appeared = false

                override func viewDidLoad() {
                    super.viewDidLoad()
                    navigationItem.leftBarButtonItem = originalAction
                    view.addSubview(scroll)
                    scroll.frame = view.bounds
                    scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    scroll.contentSize = CGSize(width: 200, height: 3000)
                }

                override func viewDidDisappear(_ animated: Bool) {
                    super.viewDidDisappear(animated)
                    appeared = false
                    disappearances += 1
                }

                override func viewDidAppear(_ animated: Bool) {
                    super.viewDidAppear(animated)
                    appeared = true
                }
            }

            private final class Host: UKSectionStackHost {
                var stackLayout = DeviceLayout.resolve(
                    LayoutSignals(
                        size: CGSize(width: 1210, height: 834), widthClass: .regular, usesSidebarShell: true
                    ))
                var pages: [AppRoute: Page] = [:]

                func stackMakeScreen(_ route: AppRoute, section: FestivalSection) -> UIViewController {
                    let page = Page()
                    page.ukRoute = route
                    pages[route] = page
                    return page
                }

                func stackWillShow(
                    _ controller: UIViewController, in stack: UKSectionStack, navigation: UINavigationController
                ) {}
                func stackDidChangePath(_ stack: UKSectionStack) {}
            }

            private func makeHost() async throws -> (Host, UKSectionStack, UIWindow, () -> Void) {
                let scene = try #require(
                    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                )
                let previous = scene.windows.first(where: \.isKeyWindow)
                let host = Host()
                let root = Page()
                let stack = UKSectionStack(section: .leaderboards, root: root, host: host)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: host.stackLayout.size)
                window.rootViewController = stack
                window.makeKeyAndVisible()
                do {
                    try await UKHostedWindow.wait { root.appeared }
                } catch {
                    window.isHidden = true
                    window.rootViewController = nil
                    previous?.makeKeyAndVisible()
                    throw error
                }
                stack.view.frame = window.bounds
                stack.view.layoutIfNeeded()
                return (
                    host, stack, window,
                    {
                        window.isHidden = true
                        window.rootViewController = nil
                        previous?.makeKeyAndVisible()
                    }
                )
            }

            @Test
            func dividerExistsOnlyWhileADetailIsOpen() async throws {
                let (host, stack, _, restore) = try await makeHost()
                defer { withExtendedLifetime(host) { restore() } }
                let divider = try #require(stack.view.subviews.first {
                    $0.accessibilityIdentifier == "fst.split.divider"
                })
                stack.setPath([.fullRankings(instrument: .lead, rankBy: "adjusted")], animated: false)
                #expect(stack.isDetailOpen)
                #expect(!divider.isHidden)
                #expect(stack.trailing?.view.accessibilityIdentifier == "fst.split.trailing")

                stack.popToRoot(animated: false)
                #expect(!stack.isDetailOpen)
                #expect(divider.isHidden)
                #expect(stack.trailing?.view.accessibilityIdentifier == nil)
            }

            @Test
            func geometryChangesDoNotRemoveAnUnchangedDetail() async throws {
                let (host, stack, window, restore) = try await makeHost()
                defer { restore() }
                let route = AppRoute.fullRankings(instrument: .lead, rankBy: "adjusted")
                stack.setPath([route], animated: false)
                let page = try #require(host.pages[route])
                let pane = try #require(stack.trailing)
                page.loadViewIfNeeded()
                page.scroll.contentOffset.y = 180
                let before = page.disappearances

                stack.reshape(animated: false)
                window.frame.size.width = 1240
                stack.view.frame = window.bounds
                stack.layoutDidChange()

                #expect(stack.trailing === pane)
                #expect(pane.viewControllers.first === page)
                #expect(page.disappearances == before)
                #expect(page.scroll.contentOffset.y == 180)
                #expect(stack.path == [route])
            }

            @Test
            func collapsingRestoresFeatureChromeAndKeepsTheSameController() async throws {
                let (host, stack, window, restore) = try await makeHost()
                defer { restore() }
                let route = AppRoute.fullRankings(instrument: .lead, rankBy: "adjusted")
                stack.setPath([route], animated: false)
                let page = try #require(host.pages[route])
                #expect(page.navigationItem.leftBarButtonItem?.accessibilityIdentifier == "fst.split.close")

                host.stackLayout = .standardPhone
                window.frame.size = CGSize(width: 402, height: 874)
                stack.view.frame = window.bounds
                stack.reshape(animated: false)

                #expect(stack.trailing == nil)
                #expect(stack.leading.topViewController === page)
                #expect(page.navigationItem.leftBarButtonItem === page.originalAction)
                #expect(!page.navigationItem.hidesBackButton)
                #expect(stack.path == [route])
            }

            @Test
            func hingeDividerExposesTheFoldBandAndKeepsContrastLineCentered() async throws {
                let (host, stack, window, restore) = try await makeHost()
                defer { restore() }
                host.stackLayout = DeviceLayout.resolve(LayoutSignals(
                    size: CGSize(width: 1210, height: 834), widthClass: .regular,
                    hinge: .partiallyOpen,
                    divisions: [CGRect(x: 593, y: 0, width: 24, height: 834)],
                    usesSidebarShell: true
                ))
                window.frame = CGRect(origin: .zero, size: host.stackLayout.size)
                stack.view.frame = window.bounds
                stack.setPath([.fullRankings(instrument: .lead, rankBy: "adjusted")], animated: false)
                stack.view.layoutIfNeeded()

                let band = try #require(stack.view.subviews.first {
                    $0.accessibilityIdentifier == "fst.split.divider"
                })
                let line = try #require(band.subviews.first)
                #expect(abs(band.frame.width - 24) < 0.5)
                #expect(abs(line.frame.width - 1) < 0.5)
                #expect(abs(line.frame.midX - band.bounds.midX) < 0.5)
                #expect(line.isHidden)
                #expect(!band.isAccessibilityElement)
                #expect(!line.isAccessibilityElement)
            }
        }
    }
#endif
