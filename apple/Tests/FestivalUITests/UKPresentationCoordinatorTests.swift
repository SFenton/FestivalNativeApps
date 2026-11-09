#if os(iOS)
import FestivalCore
import Testing
import UIKit
@testable import FestivalUI

extension UKFoundationTests {
    @MainActor
    struct UKPresentationCoordinatorTests {
        private func present(
            _ controller: UIViewController, using coordinator: UKPresentationCoordinator,
            in harness: UKHostedWindow, onDismiss: (() -> Void)? = nil
        ) async throws {
            var completed = false
            #expect(coordinator.presentIndependent(
                controller, from: harness.root, animated: false, onDismiss: onDismiss,
                completion: { completed = true }
            ) == .presented)
            try await UKHostedWindow.wait { completed }
        }

        @Test
        func firstRunNativeDismissalClosesOnceAndReleasesItsPresentation() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            var closes = 0
            var presentation: UKFirstRunPresentation? = UKFirstRunPresentation(
                page: .songs, slides: FirstRunCatalog.slides(for: .songs),
                presenter: harness.root, session: session
            ) { viewed in
                closes += 1
                #expect(viewed.count == 1)
            }
            weak var released = presentation
            #expect(presentation?.admission == .presented)
            presentation = nil
            let sheet = try #require(harness.root.presentedViewController)
            var completed = false
            try await UKHostedWindow.wait {
                sheet.viewIfLoaded?.window != nil && !sheet.isBeingPresented && sheet.transitionCoordinator == nil
            }
            UKPresentationCoordinator.shared(for: harness.root).dismiss(sheet, animated: false) { completed = true }
            try await UKHostedWindow.wait { completed && closes == 1 && released == nil }
            #expect(UKPresentationCoordinator.shared(for: harness.root).canPresentIndependent(from: harness.root))
        }

        @Test
        func carouselExposesOneExplanationOnlyForItsActiveSlide() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            let slides = FirstRunCatalog.slides(for: .songs)
            let carousel = UKFirstRunCarouselViewController(
                page: .songs, slides: slides, session: session, onFinish: {}
            )
            try await harness.present(carousel)
            func descendants(_ view: UIView) -> [UIView] {
                [view] + view.subviews.flatMap(descendants)
            }
            let rendered = descendants(carousel.view).compactMap { $0 as? UKFirstRunSlideView }
            #expect(rendered.count == slides.count)
            let active = try #require(rendered.first { $0.isActiveSlide })
            #expect(active.isAccessibilityElement)
            #expect(!active.accessibilityElementsHidden)
            #expect(active.accessibilityLabel == "\(slides[0].title). \(slides[0].description)")
            let inactiveSlidesHidden = rendered.filter { !$0.isActiveSlide }.allSatisfy {
                $0.accessibilityElementsHidden
            }
            #expect(inactiveSlidesHidden)
        }

        @Test
        func everyCatalogSlideRendersItsNativeFamily() {
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            for page in FirstRunPageKey.allCases {
                for slide in FirstRunCatalog.slides(for: page) {
                    let demo = UKFirstRunNativeDemoView(slide: slide, session: session)
                    demo.frame = CGRect(x: 0, y: 0, width: 360, height: 260)
                    demo.layoutIfNeeded()
                    #expect(demo.renderedFamily != .generic, "\(page.rawValue)/\(slide.id)")
                    #expect(demo.hasRenderedContent, "\(page.rawValue)/\(slide.id) rendered no content")
                    #expect(UKFirstRunNativeDemoView.hasNativeDemo(id: slide.id))
                }
            }

        }

        @Test
        func sortAndFilterDemosAttachCanonicalChildControllersAndDetach() async throws {
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            for (id, typeName) in [
                ("songs-sort", "UKSongsSortSheetController"),
                ("songs-filter", "UKSongsFilterSheetController"),
                ("suggestions-global-filter", "UKSuggestionsFilterViewController"),
                ("playerhistory-sort", "UKPlayerHistorySortViewController"),
            ] {
                let page: FirstRunPageKey = id.hasPrefix("suggestions") ? .suggestions
                    : id.hasPrefix("playerhistory") ? .playerHistory : .songs
                let slide = try #require(FirstRunCatalog.slides(for: page).first { $0.id == id })
                let demo = UKFirstRunNativeDemoView(slide: slide, session: session)
                demo.frame = CGRect(x: 0, y: 0, width: 360, height: 300)
                harness.root.view.addSubview(demo)
                try await UKHostedWindow.wait { demo.embeddedControllerNames.contains(typeName) }
                demo.removeFromSuperview()
                try await UKHostedWindow.wait { demo.embeddedControllerNames.isEmpty }
            }
        }

        @Test
        func independentAdmissionRequiresAVisiblePresenter() {
            let presenter = UIViewController()
            let coordinator = UKPresentationCoordinator.shared(for: presenter)
            #expect(!coordinator.canPresentIndependent(from: presenter))
            #expect(
                coordinator.presentIndependent(UIViewController(), from: presenter) == .rejected
            )
        }

        @Test
        func automaticTaskWaitsForActualDismissalThenPresents() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            let first = UKSheet.make(
                UIViewController(), title: "First", closeIdentifier: "fst.test.first.close"
            )
            try await present(first, using: coordinator, in: harness)

            var built = false
            let result = coordinator.presentAutomatic(from: harness.root) {
                built = true
                return UKSheet.make(
                    UIViewController(), title: "Automatic", closeIdentifier: "fst.test.automatic.close"
                )
            }
            #expect(result == .queued)
            #expect(!built)

            first.dismiss(animated: false)
            try await UKHostedWindow.wait {
                guard let navigation = harness.root.presentedViewController as? UINavigationController else {
                    return false
                }
                return built && navigation.topViewController?.navigationItem.title == "Automatic"
            }
        }

        @Test
        func secondAutomaticRequestIsRejectedInsteadOfDroppingItsClaim() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            let first = UKSheet.make(
                UIViewController(), title: "First", closeIdentifier: "fst.test.first.close"
            )
            try await present(first, using: coordinator, in: harness)

            var firstBuilt = false
            #expect(
                coordinator.presentAutomatic(from: harness.root) {
                    firstBuilt = true
                    return UKSheet.make(
                        UIViewController(), title: "Automatic", closeIdentifier: "fst.test.automatic.close"
                    )
                } == .queued
            )
            var secondBuilt = false
            #expect(
                coordinator.presentAutomatic(from: harness.root) {
                    secondBuilt = true
                    return UIViewController()
                } == .rejected
            )
            #expect(!firstBuilt)
            #expect(!secondBuilt)
        }

        @Test
        func invisibleAutomaticRequestIsRejectedBeforeBuilding() {
            let presenter = UIViewController()
            let coordinator = UKPresentationCoordinator.shared(for: presenter)
            var built = false
            #expect(
                coordinator.presentAutomatic(from: presenter) {
                    built = true
                    return UIViewController()
                } == .rejected
            )
            #expect(!built)
        }

        @Test
        func coordinatorDismissReleasesAGenericIndependentController() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            let generic = UIViewController()
            try await present(generic, using: coordinator, in: harness)

            var built = false
            #expect(
                coordinator.presentAutomatic(from: harness.root) {
                    built = true
                    return UKSheet.make(
                        UIViewController(), title: "After Generic", closeIdentifier: "fst.test.after.close"
                    )
                } == .queued
            )
            coordinator.dismiss(generic, animated: false)
            try await UKHostedWindow.wait {
                built && harness.root.presentedViewController?.presentingViewController === harness.root
            }
        }

        @Test
        func foreignPresentationDismissalDrainsPendingAutomaticTask() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let foreign = UIViewController()
            try await harness.present(foreign)
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            var built = false
            #expect(
                coordinator.presentAutomatic(from: harness.root) {
                    built = true
                    return UKSheet.make(
                        UIViewController(), title: "After Foreign", closeIdentifier: "fst.test.after-foreign.close"
                    )
                } == .queued
            )
            foreign.dismiss(animated: false)
            try await UKHostedWindow.wait {
                built && harness.root.presentedViewController?.presentingViewController === harness.root
            }
        }

        @Test
        func relatedFullScreenControllerDoesNotFinishItsIndependentTask() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            let task = UIViewController()
            var dismissals = 0
            try await present(task, using: coordinator, in: harness) { dismissals += 1 }
            let related = UIViewController()
            related.modalPresentationStyle = .fullScreen
            var presented = false
            #expect(coordinator.presentRelated(related, from: task, animated: false) { presented = true })
            try await UKHostedWindow.wait { presented }
            #expect(dismissals == 0)

            var relatedDismissed = false
            coordinator.dismiss(related, animated: false) { relatedDismissed = true }
            try await UKHostedWindow.wait { relatedDismissed }
            #expect(dismissals == 0)

            var taskDismissed = false
            coordinator.dismiss(task, animated: false) { taskDismissed = true }
            try await UKHostedWindow.wait { taskDismissed && dismissals == 1 }
        }

        @Test
        func removingAScreenCancelsItsWindowOwnedAutomaticBuilder() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let source = UKScreenViewController()
            let navigation = UINavigationController(rootViewController: source)
            try await harness.present(navigation)
            let coordinator = UKPresentationCoordinator.shared(for: source)

            var payload: NSObject? = NSObject()
            weak var released = payload
            let result = coordinator.presentAutomatic(from: source) { [captured = payload!] in
                _ = captured
                return UIViewController()
            }
            #expect(result == .queued)
            payload = nil
            #expect(released != nil)

            var dismissed = false
            navigation.dismiss(animated: false) { dismissed = true }
            try await UKHostedWindow.wait { dismissed }
            #expect(released == nil)
        }

        @Test
        func rejectedSongsSheetDoesNotClaimItsDismissalObserver() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            let first = UKSheet.make(UIViewController(), title: "First", closeIdentifier: "fst.test.first.close")
            try await present(first, using: coordinator, in: harness)
            var claimed = false

            harness.root.ukPresentSongsSheet(
                UIViewController(), title: "Rejected", closeIdentifier: "fst.test.rejected.close",
                size: .compact, keep: { _ in claimed = true }
            )

            #expect(!claimed)
            #expect(harness.root.presentedViewController === first)
        }

        @Test
        func feedbackNotifiesItsHostOnlyAfterTheNativeSheetHasGone() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            var callbacks = 0
            var wasDismissed = false
            UKFeedbackFormViewController.present(
                kind: .bug, session: session, from: harness.root, onSent: { _ in }
            ) {
                callbacks += 1
                wasDismissed = harness.root.presentedViewController == nil
            }
            let sheet = try #require(harness.root.presentedViewController)
            try await UKHostedWindow.wait {
                sheet.viewIfLoaded?.window != nil && !sheet.isBeingPresented && sheet.transitionCoordinator == nil
            }
            #expect(callbacks == 0)

            UKPresentationCoordinator.shared(for: harness.root).dismiss(sheet, animated: false)
            try await UKHostedWindow.wait { callbacks == 1 }
            #expect(wasDismissed)
            #expect(UKPresentationCoordinator.shared(for: harness.root).canPresentIndependent(from: harness.root))
        }

        @Test
        func feedbackFormHasARealNativeViewportBeforeOpeningItsLibrary() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
            let form = UKFeedbackFormViewController(kind: .bug, session: session, onSent: { _ in })
            let sheet = UKSheet.make(form, title: "Report an Issue", closeIdentifier: "fst.test.feedback.close")
            try await present(sheet, using: .shared(for: harness.root), in: harness)
            form.view.layoutIfNeeded()
            let scroll = try #require(form.ukModalScrollView)

            #expect(scroll.window === harness.window)
            #expect(scroll.bounds.width > 0)
            #expect(scroll.bounds.height > 0)
            #expect(scroll.contentSize.height > 0)
        }

        @Test
        func nativeAlertKeepsItsSystemPresentationDelegate() async throws {
            let harness = try await UKHostedWindow.make()
            defer { harness.close() }
            let coordinator = UKPresentationCoordinator.shared(for: harness.root)
            let alert = UIAlertController(title: "Notice", message: "Fixture", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            var presented = false

            #expect(coordinator.presentRelated(alert, from: harness.root, animated: false) { presented = true })
            try await UKHostedWindow.wait { presented }
            #expect(harness.root.presentedViewController === alert)
            var dismissed = false
            coordinator.dismiss(alert, animated: false) { dismissed = true }
            try await UKHostedWindow.wait { dismissed }
        }
    }
}
#endif
