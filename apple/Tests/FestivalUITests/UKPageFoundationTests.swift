#if os(iOS)
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
                page.clearPageState()

                #expect(scroll.superview === page.pageContainment.contentView)
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
        }
    }
#endif
