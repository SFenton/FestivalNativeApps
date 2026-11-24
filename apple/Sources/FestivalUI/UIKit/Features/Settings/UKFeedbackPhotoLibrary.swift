#if os(iOS)
import FestivalCore
import FestivalDesign
import PhotosUI
import UIKit

/// The regular-width Feedback pane containing the out-of-process system Photos picker.
/// The form keeps it mounted while hidden so a refold does not lose the library selection.
@MainActor
final class UKFeedbackPhotoLibrary: UIViewController, PHPickerViewControllerDelegate {
    private let model: FeedbackFormModel
    private let onHide: () -> Void
    private var selection: [String] = []
    private var links = FeedbackPickerLinks<String>()
    private var imports: [String: Task<Void, Never>] = [:]
    private var lastImport: Task<Void, Never>?

    private lazy var picker: PHPickerViewController = {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        configuration.selectionLimit = FeedbackLimits.attachments
        configuration.selection = .continuousAndOrdered
        configuration.disabledCapabilities = .selectionActions
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = self
        return controller
    }()

    /// Creates the picker pane.
    ///
    /// - Parameters:
    ///   - model: The owning feedback draft.
    ///   - onHide: Restores the full-width form without discarding attached media.
    init(model: FeedbackFormModel, onHide: @escaping () -> Void) {
        self.model = model
        self.onHide = onHide
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "fst.settings.feedback.library"
        view.accessibilityContainerType = .semanticGroup
        let title = UKLabel("Photo Library", style: .headline).asHeader()
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Hide"
        configuration.baseForegroundColor = BrandUIColors.accentBlue
        configuration.contentInsets = .zero
        let hide = UIButton(configuration: configuration)
        hide.contentHorizontalAlignment = .trailing
        hide.accessibilityLabel = "Hide Photo Library"
        hide.accessibilityIdentifier = "fst.settings.feedback.library.hide"
        hide.setContentHuggingPriority(.required, for: .horizontal)
        hide.setContentCompressionResistancePriority(.required, for: .horizontal)
        hide.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        hide.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        hide.addAction(UIAction { [weak self] _ in self?.onHide() }, for: .primaryActionTriggered)
        let header = UIStackView(arrangedSubviews: [title, hide])
        header.alignment = .center
        header.spacing = 12
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        addChild(picker)
        let content = UIStackView(arrangedSubviews: [header, picker.view])
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        separator.isUserInteractionEnabled = false
        view.addSubview(separator)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
        ])
        picker.didMove(toParent: self)
    }

    /// Reflect removal from the attachment strip back into the picker.
    ///
    /// - Parameter attachmentIDs: IDs still present on the form.
    func synchronizeAttachments(_ attachmentIDs: Set<UUID>) {
        let stale = links.prune(keeping: attachmentIDs)
        guard !stale.isEmpty else { return }
        selection.removeAll { stale.contains($0) }
        picker.deselectAssets(withIdentifiers: stale)
    }

    /// Cancel any outstanding imports when the form is dismissed or discarded.
    func cancelImports() {
        imports.values.forEach { $0.cancel() }
        imports.removeAll()
        lastImport = nil
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard model.acceptsMedia else { return }
        let next = results.compactMap(\.assetIdentifier)
        let changes = FeedbackPickerLinks<String>.changes(from: selection, to: next)
        selection = next
        for key in changes.removed {
            imports.removeValue(forKey: key)?.cancel()
            if let id = links.unlink(key) { model.remove(id: id) }
        }
        for key in changes.added {
            guard let result = results.first(where: { $0.assetIdentifier == key }) else { continue }
            let previous = lastImport
            let task = Task { [weak self, model] in
                await previous?.value
                guard !Task.isCancelled else { return }
                let id = await model.importPhoto(result.itemProvider)
                guard !Task.isCancelled, let self else {
                    if let id { model.remove(id: id) }
                    return
                }
                imports[key] = nil
                if let id {
                    links.link(key, to: id)
                } else {
                    selection.removeAll { $0 == key }
                    picker.deselectAssets(withIdentifiers: [key])
                }
            }
            imports[key] = task
            lastImport = task
        }
    }
}
#endif
