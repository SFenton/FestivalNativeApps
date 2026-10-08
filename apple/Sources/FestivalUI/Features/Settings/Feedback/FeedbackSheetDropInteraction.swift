#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Sheet drop interaction (iOS)

/// Lets photos, videos and image or movie files dragged from another app drop anywhere on
/// the feedback sheet (issue #373).
///
/// SwiftUI's `onDrop` and `dropDestination` on `Form` rows never see a drop on iOS 18 and
/// later: the drop controller of the `Form`'s own collection view is the closest drop
/// interaction to every row, claims the session and then cancels it (Apple Developer
/// Forums 758015; confirmed on the iPadOS 26 simulator with a drag from Photos in Split
/// View). So this, in the way ``SheetDismissAttemptObserver`` wraps the presentation
/// delegate:
/// - wraps each of the sheet's collection views' `dropDelegate` in a proxy that takes
///   media drops and forwards every other call to SwiftUI's own delegate, and
/// - adds one `UIDropInteraction` to the presented sheet's root view for the parts outside
///   the form (the navigation bar and the library pane's margins).
struct FeedbackSheetDropInteraction: UIViewControllerRepresentable {
    /// False while sending: the drop is shown as forbidden.
    let accepts: Bool
    /// Called with true when an acceptable drag enters the sheet and false when it leaves,
    /// drops or ends.
    let onTargetChange: (Bool) -> Void
    /// Takes the dropped item providers.
    let onDrop: ([NSItemProvider]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.parent = self
        controller.install()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Coordinator) {
        controller.uninstall()
    }

    // MARK: - Controller

    /// Invisible child controller that attaches the drop handling to the presented root.
    final class Controller: UIViewController {
        private let coordinator: Coordinator
        private let interaction: UIDropInteraction
        private weak var host: UIView?
        private var collections: [CollectionDropProxy] = []

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            interaction = UIDropInteraction(delegate: coordinator)
            super.init(nibName: nil, bundle: nil)
            coordinator.controller = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }

        /// Add the interaction to the presented root's view once, and wrap the drop
        /// delegate of any of its collection views not wrapped yet.
        func install() {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil, let view = root.view else { return }
            if host !== view {
                host?.removeInteraction(interaction)
                view.addInteraction(interaction)
                host = view
            }
            collections.removeAll { $0.collectionView == nil }
            for collectionView in Self.collectionViews(in: view) {
                if let proxy = collections.first(where: { $0.collectionView === collectionView }) {
                    proxy.attach()
                } else {
                    let proxy = CollectionDropProxy(collectionView, coordinator: coordinator)
                    proxy.attach()
                    collections.append(proxy)
                }
            }
        }

        /// Remove the interaction and give each collection view back its own delegate.
        func uninstall() {
            host?.removeInteraction(interaction)
            host = nil
            collections.forEach { $0.detach() }
            collections.removeAll()
        }

        private static func collectionViews(in view: UIView) -> [UICollectionView] {
            var found: [UICollectionView] = []
            var pending = [view]
            while let next = pending.popLast() {
                if let collectionView = next as? UICollectionView { found.append(collectionView) }
                pending.append(contentsOf: next.subviews)
            }
            return found
        }
    }

    // MARK: - Coordinator

    /// Shared drop handling for the sheet's interaction and its collection views.
    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var parent: FeedbackSheetDropInteraction
        weak var controller: Controller?
        /// Drop targets the drag is over; the sheet's and a collection view's overlap.
        private var targets = 0

        init(_ parent: FeedbackSheetDropInteraction) {
            self.parent = parent
        }

        /// Whether a session holds a movie or an image the form can take.
        ///
        /// - Parameter session: The drop session.
        /// - Returns: True when any item conforms to a droppable type.
        static func holdsMedia(_ session: any UIDropSession) -> Bool {
            session.hasItemsConforming(
                toTypeIdentifiers: FeedbackPickedMedia.droppableTypes.map(\.identifier)
            )
        }

        /// The operation to propose for a media session.
        var operation: UIDropOperation { parent.accepts ? .copy : .forbidden }

        /// A media drag entered one target.
        func entered() {
            targets += 1
            if targets == 1 { parent.onTargetChange(true) }
        }

        /// A media drag left one target.
        func exited() {
            guard targets > 0 else { return }
            targets -= 1
            if targets == 0 { parent.onTargetChange(false) }
        }

        /// The drag ended, dropped or not.
        func ended() {
            guard targets > 0 else { return }
            targets = 0
            parent.onTargetChange(false)
        }

        /// Attach the media in a dropped session.
        ///
        /// - Parameter session: The session being dropped.
        func perform(_ session: any UIDropSession) {
            ended()
            guard parent.accepts else { return }
            parent.onDrop(session.items.map(\.itemProvider))
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            // A collection view created since the last pass is wrapped before it is asked.
            controller?.install()
            return Self.holdsMedia(session)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {
            entered()
        }

        func dropInteraction(
            _ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession
        ) -> UIDropProposal {
            UIDropProposal(operation: operation)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) {
            exited()
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) {
            ended()
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
            perform(session)
        }
    }

    // MARK: - Collection view proxy

    /// Stands in for a collection view's drop delegate: media sessions go to the
    /// ``Coordinator``; every other session and call goes to SwiftUI's own delegate.
    final class CollectionDropProxy: NSObject, UICollectionViewDropDelegate {
        weak var collectionView: UICollectionView?
        private let coordinator: Coordinator
        nonisolated(unsafe) weak var original: (any UICollectionViewDropDelegate)?

        init(_ collectionView: UICollectionView, coordinator: Coordinator) {
            self.collectionView = collectionView
            self.coordinator = coordinator
        }

        /// Become the collection view's drop delegate, keeping whichever delegate it had.
        func attach() {
            guard let collectionView, collectionView.dropDelegate !== self else { return }
            original = collectionView.dropDelegate
            collectionView.dropDelegate = self
        }

        /// Give the collection view back its own delegate.
        func detach() {
            guard let collectionView, collectionView.dropDelegate === self else { return }
            collectionView.dropDelegate = original
        }

        func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
            Coordinator.holdsMedia(session)
                || (original?.collectionView?(collectionView, canHandle: session) ?? false)
        }

        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidEnter session: any UIDropSession
        ) {
            if Coordinator.holdsMedia(session) {
                coordinator.entered()
            } else {
                original?.collectionView?(collectionView, dropSessionDidEnter: session)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            dropSessionDidUpdate session: any UIDropSession,
            withDestinationIndexPath destinationIndexPath: IndexPath?
        ) -> UICollectionViewDropProposal {
            if Coordinator.holdsMedia(session) {
                return UICollectionViewDropProposal(operation: coordinator.operation)
            }
            return original?.collectionView?(
                collectionView, dropSessionDidUpdate: session,
                withDestinationIndexPath: destinationIndexPath
            ) ?? UICollectionViewDropProposal(operation: .cancel)
        }

        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidExit session: any UIDropSession
        ) {
            if Coordinator.holdsMedia(session) {
                coordinator.exited()
            } else {
                original?.collectionView?(collectionView, dropSessionDidExit: session)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidEnd session: any UIDropSession
        ) {
            if Coordinator.holdsMedia(session) {
                coordinator.ended()
            } else {
                original?.collectionView?(collectionView, dropSessionDidEnd: session)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            performDropWith dropCoordinator: any UICollectionViewDropCoordinator
        ) {
            if Coordinator.holdsMedia(dropCoordinator.session) {
                coordinator.perform(dropCoordinator.session)
            } else {
                original?.collectionView(collectionView, performDropWith: dropCoordinator)
            }
        }

        override nonisolated func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            if let original, original.responds(to: selector) { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
#endif
