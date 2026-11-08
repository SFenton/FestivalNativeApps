#if os(iOS)
import Testing
import UIKit
@testable import FestivalUI

extension UKFoundationTests {
    @MainActor
    struct UKMotionFoundationTests {
        @Test
        func reducedMotionAccordionSettlesWithoutDelayedFade() {
            let key = "fst.accessibility.reduceMotion"
            let previous = UserDefaults.standard.object(forKey: key)
            defer {
                if let previous { UserDefaults.standard.set(previous, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            UserDefaults.standard.set(true, forKey: key)
            let accordion = UKAccordionView<Int> { _ in UILabel() }

            accordion.follow(1)
            #expect(accordion.state.phase.isOpen)
            #expect(accordion.state.phase.showsContent)
            accordion.follow(nil)
            #expect(!accordion.state.phase.isOpen)
            #expect(!accordion.state.phase.showsContent)
        }

        @Test
        func finishingPageEntrancesRestoresContentAndReleasesPendingView() async throws {
            let before = UKFadeIn.isEnabled
            UKFadeIn.isEnabled = true
            defer { UKFadeIn.isEnabled = before }
            let root = UIView()
            var content: UIView? = UIView()
            weak var released = content
            root.addSubview(content!)
            UKFadeIn.fadeIn(content!, staggerIndex: 5)

            UKFadeIn.finishAnimations(in: root)
            #expect(content?.alpha == 1)
            #expect(content?.transform == .identity)
            content?.removeFromSuperview()
            content = nil
            await Task.yield()
            #expect(released == nil)
        }

        @Test
        func offsetLoadingRegionUsesItsOwnCoordinateSpaceAndNativeIndicator() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let slot = UIView(frame: CGRect(x: 35, y: 100, width: 220, height: 300))
            harness.root.view.addSubview(slot)
            let loading = UKLoadingView(accessibilityLabel: "Loading fixture", placement: .fill)
            loading.translatesAutoresizingMaskIntoConstraints = true
            loading.frame = slot.bounds
            slot.addSubview(loading)
            loading.layoutIfNeeded()

            let arc = try #require(loading.subviews.first)
            #expect(abs(arc.center.x - loading.bounds.midX) < 0.5)
            #expect(abs(arc.center.y - loading.bounds.midY) < 0.5)
            let indicators = arc.subviews.compactMap { $0 as? UIActivityIndicatorView }
            #expect(indicators.count == 1)
            #expect(indicators.first?.accessibilityLabel == "Loading fixture")
            #expect(indicators.first?.color != .clear)
        }

        @Test
        func scrollingOverflowFillDoesNotMoveItsContentOrigin() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let fill = UKCentredFillView(padding: 24)
            fill.translatesAutoresizingMaskIntoConstraints = true
            fill.frame = CGRect(x: 30, y: 90, width: 220, height: 200)
            harness.root.view.addSubview(fill)
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            fill.contentContainer.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: fill.contentContainer.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: fill.contentContainer.trailingAnchor),
                label.topAnchor.constraint(equalTo: fill.contentContainer.topAnchor),
                label.bottomAnchor.constraint(equalTo: fill.contentContainer.bottomAnchor),
                label.heightAnchor.constraint(equalToConstant: 600),
            ])
            fill.layoutIfNeeded()
            let origin = fill.contentContainer.frame.origin
            let contentSize = fill.contentSize
            #expect(abs(origin.x - 24) < 0.5)
            #expect(abs(origin.y - 24) < 0.5)

            fill.contentOffset.y = 70
            fill.setNeedsLayout()
            fill.layoutIfNeeded()

            #expect(fill.contentContainer.frame.origin == origin)
            #expect(fill.contentSize == contentSize)
        }

        @Test
        func paneFocusUsesRealViewGeometryForANativeHeading() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let pane = UIView(frame: CGRect(x: 140, y: 90, width: 240, height: 500))
            harness.root.view.addSubview(pane)
            let heading = UIView(frame: CGRect(x: 20, y: 120, width: 200, height: 44))
            heading.isAccessibilityElement = true
            heading.accessibilityTraits = .header
            heading.accessibilityLabel = "Fixture pane heading"
            pane.addSubview(heading)
            let anchor = AccessibilityFocusAnchor.AnchorView(frame: pane.bounds)
            anchor.isUserInteractionEnabled = false
            pane.addSubview(anchor)
            let frame = AccessibilityFocusAnchor.AnchorView.frame(of: heading)
            let expected = heading.convert(heading.bounds, to: harness.window.screen.coordinateSpace)

            #expect(frame == expected)
            #expect(frame.minX >= 160)
            #expect(frame.minY >= 210)
            #expect(anchor.move(AccessibilityFocusRequest(target: .topHeading, token: 1)))
        }

        #if DEBUG
        @Test
        func edgeProbeRestoresItsOffsetBeforeReportingClosed() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let scroll = UIScrollView(frame: harness.root.view.bounds)
            scroll.contentSize = CGSize(width: scroll.bounds.width, height: 3000)
            harness.root.view.addSubview(scroll)
            let original = scroll.contentOffset
            defer { PerfComponentBuiltins.stopEdgeFade() }

            PerfComponentBuiltins.startEdgeFade()
            try await UKHostedWindow.wait { PerfComponentBuiltins.edgeFadeReady }
            #expect(abs(scroll.contentOffset.y - original.y) > 1)
            PerfComponentBuiltins.stopEdgeFade()
            #expect(PerfComponentBuiltins.edgeFadeReady || abs(scroll.contentOffset.y - original.y) < 0.5)
            try await UKHostedWindow.wait { !PerfComponentBuiltins.edgeFadeReady }

            #expect(abs(scroll.contentOffset.y - original.y) < 0.5)
        }
        #endif
    }
}
#endif
