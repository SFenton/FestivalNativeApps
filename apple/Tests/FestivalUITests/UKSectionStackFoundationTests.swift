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
                    disappearances += 1
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

            private func makeHost() throws -> (Host, UKSectionStack, UIWindow, () -> Void) {
                let scene = try #require(
                    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                )
                let previous = scene.windows.first(where: \.isKeyWindow)
                let host = Host()
                let stack = UKSectionStack(section: .leaderboards, root: Page(), host: host)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: host.stackLayout.size)
                window.rootViewController = stack
                window.makeKeyAndVisible()
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
            func geometryChangesDoNotRemoveAnUnchangedDetail() throws {
                let (host, stack, window, restore) = try makeHost()
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
            func collapsingRestoresFeatureChromeAndKeepsTheSameController() throws {
                let (host, stack, window, restore) = try makeHost()
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
        }
    }
#endif
