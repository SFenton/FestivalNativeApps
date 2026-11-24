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

    func makeCoordinator() -> FeedbackMediaDropCoordinator {
        FeedbackMediaDropCoordinator(accepts: { accepts }, onTargetChange: onTargetChange, onDrop: onDrop)
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.accepts = { accepts }
        context.coordinator.onTargetChange = onTargetChange
        context.coordinator.onDrop = onDrop
        controller.install()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: FeedbackMediaDropCoordinator) {
        controller.uninstall()
    }

    // MARK: - Controller

    /// Invisible child controller that attaches the drop handling to the presented root.
    final class Controller: UIViewController {
        private let coordinator: FeedbackMediaDropCoordinator
        private let interaction: UIDropInteraction
        private weak var host: UIView?
        private var collections: [CollectionDropProxy] = []

        init(coordinator: FeedbackMediaDropCoordinator) {
            self.coordinator = coordinator
            interaction = UIDropInteraction(delegate: coordinator)
            super.init(nibName: nil, bundle: nil)
            // A collection view created since the last pass must be wrapped before it is asked.
            coordinator.prepareSession = { [weak self] in self?.install() }
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

    // MARK: - Collection view proxy

    /// Stands in for a collection view's drop delegate: media sessions go to the
    /// ``FeedbackMediaDropCoordinator``; every other session and call goes to SwiftUI's own delegate.
    final class CollectionDropProxy: NSObject, UICollectionViewDropDelegate {
        weak var collectionView: UICollectionView?
        private let coordinator: FeedbackMediaDropCoordinator
        nonisolated(unsafe) weak var original: (any UICollectionViewDropDelegate)?

        init(_ collectionView: UICollectionView, coordinator: FeedbackMediaDropCoordinator) {
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
            FeedbackMediaDropCoordinator.holdsMedia(session)
                || (original?.collectionView?(collectionView, canHandle: session) ?? false)
        }

        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidEnter session: any UIDropSession
        ) {
            if FeedbackMediaDropCoordinator.holdsMedia(session) {
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
            if FeedbackMediaDropCoordinator.holdsMedia(session) {
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
            if FeedbackMediaDropCoordinator.holdsMedia(session) {
                coordinator.exited()
            } else {
                original?.collectionView?(collectionView, dropSessionDidExit: session)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidEnd session: any UIDropSession
        ) {
            if FeedbackMediaDropCoordinator.holdsMedia(session) {
                coordinator.ended()
            } else {
                original?.collectionView?(collectionView, dropSessionDidEnd: session)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            performDropWith dropCoordinator: any UICollectionViewDropCoordinator
        ) {
            if FeedbackMediaDropCoordinator.holdsMedia(dropCoordinator.session) {
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

// MARK: - Shared native drop coordinator

/// Routes media drops from a sheet and its child controls without changing ordinary text drops.
@MainActor
final class FeedbackMediaDropCoordinator: NSObject, UIDropInteractionDelegate, UITextDropDelegate {
    var accepts: () -> Bool
    var onTargetChange: (Bool) -> Void
    var onDrop: ([NSItemProvider]) -> Void
    var prepareSession: (() -> Void)?
    private var targets = 0

    init(accepts: @escaping () -> Bool, onTargetChange: @escaping (Bool) -> Void, onDrop: @escaping ([NSItemProvider]) -> Void) {
        self.accepts = accepts
        self.onTargetChange = onTargetChange
        self.onDrop = onDrop
    }

    /// Whether a drop contains an image or movie the form recognizes.
    static func holdsMedia(_ session: any UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: FeedbackPickedMedia.droppableTypes.map(\.identifier))
    }

    /// A drop copies media to the form and is forbidden while the form sends.
    var operation: UIDropOperation { accepts() ? .copy : .forbidden }

    /// Keep the highlight while any of the overlapping targets contains the drag.
    func entered() {
        targets += 1
        if targets == 1 { onTargetChange(true) }
    }

    /// Clear the highlight after leaving the last target.
    func exited() {
        guard targets > 0 else { return }
        targets -= 1
        if targets == 0 { onTargetChange(false) }
    }

    /// Clear the highlight whether or not a drag was dropped.
    func ended() {
        guard targets > 0 else { return }
        targets = 0
        onTargetChange(false)
    }

    /// Attach recognized items from the session.
    func perform(_ session: any UIDropSession) {
        ended()
        guard accepts() else { return }
        onDrop(session.items.map(\.itemProvider))
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        prepareSession?()
        return Self.holdsMedia(session)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) { entered() }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: operation)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) { exited() }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) { ended() }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) { perform(session) }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: any UITextDropRequest) -> UITextDropProposal {
        guard Self.holdsMedia(drop.dropSession) else { return drop.suggestedProposal }
        let proposal = UITextDropProposal(operation: operation)
        proposal.dropPerformer = .delegate
        proposal.dropProgressMode = .custom
        return proposal
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, willPerformDrop drop: any UITextDropRequest) {
        if Self.holdsMedia(drop.dropSession) { perform(drop.dropSession) }
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, dropSessionDidEnter session: any UIDropSession) {
        if Self.holdsMedia(session) { entered() }
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, dropSessionDidExit session: any UIDropSession) {
        if Self.holdsMedia(session) { exited() }
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, dropSessionDidEnd session: any UIDropSession) {
        if Self.holdsMedia(session) { ended() }
    }
}
#endif
