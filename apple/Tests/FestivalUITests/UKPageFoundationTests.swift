#if os(iOS)
    import FestivalCore
    import UIKit
    import Testing
    @testable import FestivalUI

    @MainActor
    @Suite(.serialized)
    struct UKFoundationTests {}

    @MainActor
    private final class UKPageFoundationRivalsProbe: UKRivalsPageViewController {
        override func build() {}
    }

    @MainActor
    private final class UKPageFoundationRivalsMenuProbe: UKRivalsPageViewController {
        override func build() {}
        override var pageMenuCommands: [UKPageMenuCommand] {
            [UKPageMenuCommand(identifier: "rivals-probe", title: "Rivals Probe")]
        }
    }

    @MainActor
    private final class UKPageFoundationProfileMenuProbe: UKProfileScrollViewController {
        override var pageMenuCommands: [UKPageMenuCommand] {
            [UKPageMenuCommand(identifier: "profile-probe", title: "Profile Probe")]
        }
    }

    @MainActor
    private final class UKPageMenuProbe: UIViewController, UKPageToolsProviding {
        var ukPageTools: [UKPageTool] { [] }
        var didPerform = false
        var ukPageMenuCommands: [UKPageMenuCommand] {
            [UKPageMenuCommand(identifier: "probe", title: "Probe", perform: { [weak self] in self?.didPerform = true })]
        }
    }

    extension UKFoundationTests {
        @MainActor
        struct UKPageFoundationTests {
            @Test
            func registrationTakesExplicitInsetOwnershipAndRestoresBaseline() {
                let page = UKPageViewController()
                page.loadViewIfNeeded()
                let scroll = UIScrollView()
                scroll.contentInsetAdjustmentBehavior = .automatic
                scroll.contentInset = UIEdgeInsets(top: 3, left: 4, bottom: 5, right: 6)
                scroll.scrollIndicatorInsets = UIEdgeInsets(top: 7, left: 8, bottom: 9, right: 10)

                page.installPageContent(scroll, scrollView: scroll, viewport: .contained)

                #expect(page.registeredPageScrollView === scroll)
                #expect(scroll.contentInsetAdjustmentBehavior == .never)
                page.unregisterPageScrollView()
                #expect(scroll.contentInsetAdjustmentBehavior == .automatic)
                #expect(scroll.contentInset == UIEdgeInsets(top: 3, left: 4, bottom: 5, right: 6))
                #expect(scroll.scrollIndicatorInsets == UIEdgeInsets(top: 7, left: 8, bottom: 9, right: 10))
            }

            @Test
            func replacingContentRestoresPreviousScrollWithoutReparentingIt() {
                let page = UKPageViewController()
                page.loadViewIfNeeded()
                let first = UIScrollView()
                first.contentInsetAdjustmentBehavior = .scrollableAxes
                page.installPageContent(first, scrollView: first, viewport: .contained)

                let second = UIScrollView()
                page.installPageContent(second, scrollView: second)

                #expect(first.superview == nil)
                #expect(first.contentInsetAdjustmentBehavior == .scrollableAxes)
                #expect(second.contentInsetAdjustmentBehavior == .automatic)
            }

            @Test
            func nativeViewportKeepsAutomaticInsetsAndFullContentFrame() {
                let page = UKPageViewController()
                page.loadViewIfNeeded()
                page.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
                page.additionalSafeAreaInsets = UIEdgeInsets(top: 10, left: 21, bottom: 32, right: 43)
                let scroll = UIScrollView()

                page.installPageContent(scroll, scrollView: scroll)
                page.view.layoutIfNeeded()

                #expect(page.pageViewportPolicy == .native)
                #expect(page.registeredPageScrollView == nil)
                #expect(scroll.contentInsetAdjustmentBehavior == .automatic)
                #expect(page.pageContainment.contentView.frame == page.pageContainment.bounds)
                #expect(scroll.superview === page.pageContainment.contentView)
            }

            @Test
            func nativeViewportPreservesScrollOffsetAcrossStateVisibilityChanges() {
                let page = UKPageViewController()
                page.loadViewIfNeeded()
                let scroll = UIScrollView()
                page.installPageContent(scroll, scrollView: scroll)
                scroll.contentOffset = CGPoint(x: 0, y: 173)
                let state = UIView()
                page.showPageState(state)
                #expect(page.pageContainment.isHidden)
                page.clearPageState()

                #expect(scroll.superview === page.pageContainment.contentView)
                #expect(!page.pageContainment.isHidden)
                #expect(scroll.contentOffset.y == 173)
                #expect(scroll.contentInsetAdjustmentBehavior == .automatic)
            }

            @Test(arguments: [247, 413])
            func reloadGateHandoffReclaimsPrimaryContentAndPreservesNativeScrollState(gateOffset: Int) {
                let page = UKPageViewController()
                page.loadViewIfNeeded()
                page.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
                let scroll = UIScrollView()
                page.installPageContent(scroll, scrollView: scroll)
                let featureColumn = UIView()
                featureColumn.translatesAutoresizingMaskIntoConstraints = false
                scroll.addSubview(featureColumn)
                let featureWidth = featureColumn.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
                let featureHeight = featureColumn.heightAnchor.constraint(greaterThanOrEqualToConstant: 1_400)
                NSLayoutConstraint.activate([
                    featureWidth,
                    featureHeight,
                    featureColumn.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                    featureColumn.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                    featureColumn.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                    featureColumn.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                ])
                page.view.layoutIfNeeded()
                scroll.contentSize = CGSize(width: scroll.bounds.width, height: 1_400)
                scroll.contentOffset = CGPoint(x: 0, y: 247)
                #expect(scroll.bounds.height > 0)
                #expect(scroll.contentSize.height > scroll.bounds.height)
                #expect(scroll.contentOffset.y == 247)
                let gate = UIView()
                let gateContent = UIView()
                gateContent.translatesAutoresizingMaskIntoConstraints = false
                gate.addSubview(gateContent)
                NSLayoutConstraint.activate([
                    gateContent.leadingAnchor.constraint(equalTo: gate.leadingAnchor),
                    gateContent.trailingAnchor.constraint(equalTo: gate.trailingAnchor),
                    gateContent.topAnchor.constraint(equalTo: gate.topAnchor),
                    gateContent.bottomAnchor.constraint(equalTo: gate.bottomAnchor),
                ])

                page.showPageState(gate, edgeToEdge: true)
                page.view.layoutIfNeeded()
                scroll.removeFromSuperview()
                gateContent.addSubview(scroll)
                NSLayoutConstraint.activate([
                    scroll.leadingAnchor.constraint(equalTo: gateContent.leadingAnchor),
                    scroll.trailingAnchor.constraint(equalTo: gateContent.trailingAnchor),
                    scroll.topAnchor.constraint(equalTo: gateContent.topAnchor),
                    scroll.bottomAnchor.constraint(equalTo: gateContent.bottomAnchor),
                ])
                gate.layoutIfNeeded()
                scroll.contentOffset.y = CGFloat(gateOffset)
                page.clearPageState()

                #expect(scroll.superview === page.pageContainment.contentView)
                #expect(scroll.contentOffset.y == CGFloat(gateOffset))
                #expect(scroll.contentInsetAdjustmentBehavior == .automatic)
                #expect(featureColumn.superview === scroll)
                #expect(featureWidth.isActive)
                #expect(featureHeight.isActive)
            }

            @Test
            func rivalsStateTransitionsKeepNativeScrollerRegisteredInHost() {
                let session = FestivalSession(factory: { fatalError("network is not used") })
                let page = UKPageFoundationRivalsProbe(context: UKContext(session: session))
                page.loadViewIfNeeded()
                page.scrollView.contentOffset = CGPoint(x: 0, y: 211)

                page.showLoading("Loading rivals")
                #expect(page.scrollView.superview === page.pageContainment.contentView)
                #expect(page.scrollView.isHidden)
                #expect(page.scrollView.contentOffset.y == 211)
                #expect(page.scrollView.contentInsetAdjustmentBehavior == .automatic)

                page.showScroll()
                page.showLoading("Loading rivals")
                page.showScroll()
                #expect(page.scrollView.superview === page.pageContainment.contentView)
                #expect(!page.scrollView.isHidden)
                #expect(page.scrollView.contentOffset.y == 211)
            }

            @Test
            func pageMenuCommandsPreserveNativeStateAndActionOwnership() {
                let page = UKPageMenuProbe()
                let checked = UKPageMenuCommand(
                    identifier: "checked", title: "Checked", state: .on,
                    children: [UKPageMenuCommand(identifier: "probe", title: "Probe", perform: { page.didPerform = true })]
                )

                #expect(checked.isSubmenu)
                #expect(checked.state == .on)
                checked.children[0].perform?()
                #expect(page.didPerform)
                #expect(page.ukPageMenuCommands.first?.isEnabled == true)
            }

            @Test
            func inheritedPageToolWitnessForwardsConcreteRivalsAndProfileCommands() {
                let session = FestivalSession(factory: { fatalError("network is not used") })
                let rivals: UKPageToolsProviding = UKPageFoundationRivalsMenuProbe(context: UKContext(session: session))
                let profile: UKPageToolsProviding = UKPageFoundationProfileMenuProbe(context: UKContext(session: session))

                #expect(rivals.ukPageMenuCommands.map(\.identifier) == ["rivals-probe"])
                #expect(profile.ukPageMenuCommands.map(\.identifier) == ["profile-probe"])
            }

            @Test
            func UIKitRankByCommandsHonorExperimentalRanksFlag() {
                let key = ExperimentalRanks.storageKey
                let previous = UserDefaults.standard.object(forKey: key)
                defer {
                    if let previous {
                        UserDefaults.standard.set(previous, forKey: key)
                    } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }

                let session = FestivalSession(factory: { fatalError("network is not used") })
                let context = UKContext(session: session)
                let full = UKFullRankingsViewController(
                    context: context, instrument: .lead, rankBy: "adjusted", page: 1, focusSelected: false
                )
                let band = UKBandRankingsViewController(
                    context: context, bandType: BandType.duets.rawValue, rankBy: "adjusted", page: 1
                )

                UserDefaults.standard.set(false, forKey: key)
                #expect(rankByChildren(of: full).map(\.identifier) == ["rank.totalscore"])
                #expect(rankByChildren(of: band).map(\.identifier) == ["rank.totalscore"])

                UserDefaults.standard.set(true, forKey: key)
                #expect(rankByChildren(of: full).map(\.identifier) == [
                    "rank.totalscore", "rank.adjusted", "rank.weighted", "rank.fcrate", "rank.maxscore",
                ])
                #expect(rankByChildren(of: band).map(\.identifier) == [
                    "rank.totalscore", "rank.adjusted", "rank.weighted", "rank.fcrate",
                ])
            }

            private func rankByChildren(of page: UKPageToolsProviding) -> [UKPageMenuCommand] {
                page.ukPageMenuCommands.first { $0.identifier == "rankBy" }?.children ?? []
            }
        }
    }
#endif
