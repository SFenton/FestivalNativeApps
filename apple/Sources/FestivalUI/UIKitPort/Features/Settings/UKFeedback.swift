#if os(iOS)
import FestivalCore
import FestivalDesign
import PhotosUI
import QuickLook
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

// MARK: - Form sheet

/// The Report an Issue / Request a Feature form (``FeedbackFormSheet``, issue #78): Title,
/// Description (and Steps to Reproduce and Expected Behavior for a bug), Media, a Cancel
/// (leading) and Submit (trailing) bar, the sending status that replaces the form on Submit, a
/// "Couldn't Send" alert that keeps the input, and the discard confirmation. It drives the
/// shared ``FeedbackFormModel``; a filed form closes itself and hands its notice to the
/// presenter, which shows "Report Sent" once the sheet has gone (issue #565).
///
/// Photos come from the system picker (`PHPickerViewController`, out of process) and files from
/// the document picker; both go through the model's own import and limits. Regular-width iPad
/// and Duo windows can host the photo picker beside the form, and media drops are accepted on
/// the form through native UIKit drop interactions.
@MainActor
final class UKFeedbackFormViewController: UKScreenViewController, UKModalScrollProviding, UIAdaptivePresentationControllerDelegate,
    PHPickerViewControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate,
    UIDropInteractionDelegate {
    private let kind: FeedbackKind
    private let session: FestivalSession
    private let onSent: (FeedbackSentNotice) -> Void
    private let model: FeedbackFormModel
    private let scroll = UIScrollView()
    private let column = UIStackView()
    private let formHolder = UIView()
    private let formPane = UIView()
    private let libraryPane = UIView()
    private var paneHost: UKHingeColumnsView?
    private var formHolderConstraints: [NSLayoutConstraint] = []
    private var formPaneConstraints: [NSLayoutConstraint] = []
    private var paneHostConstraints: [NSLayoutConstraint] = []
    private var libraryPicker: PHPickerViewController?
    private var libraryVisible = false
    private var libraryHideButton: UIButton?
    private lazy var librarySelection = UKFeedbackPhotoSelection(
        importItem: { [model] provider in
            let items = await FeedbackPickedMedia.load(from: [provider])
            guard let item = items.first else { return nil }
            return await model.importPickedMedia(item)
        },
        remove: { [model] in model.remove(id: $0) }
    )
    private let statusView = UIView()
    private let observations = UKObservationBag()
    private let titleField = UITextField()
    private var textViews: [(UITextView, ReferenceWritableKeyPath<UKFeedbackFormViewController, String>)] = []
    private let validation = UKLabel(style: .footnote)
    private let strip = UIStackView()
    private let attachMenuButton = UIButton(type: .system)
    private let attachProgress = UKLoadingView(status: "Adding media…")
    private let attachMessage = UKLabel(style: .footnote, color: BrandUIColors.statusRed)
    private let dropNotice = UKLabel("Drop to Attach", style: .footnote, color: BrandUIColors.accentBlue)
    private var dropTargets = 0
    private lazy var submitItem = UIBarButtonItem(title: "Submit", primaryAction: UIAction { [weak self] _ in self?.submit() })
    private lazy var closeItem = UIBarButtonItem(title: "Cancel", primaryAction: UIAction { [weak self] _ in self?.requestClose() })
    private var statusTitle = UKStateTitleLabel("")
    private var statusSubtitle = UKStateSubtitleLabel("")
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let stopButton = UIButton(type: .system)
    private let busy: UIActivityIndicatorView
    private var showsStatus = false
    private var shownStage: FeedbackSendingStage?
    private var handedOver = false
    private var alertedFailure = false
    private var previewURLs: [URL] = []
    private var stripKey = ""
    private var mediaImports: [UUID: Task<Void, Never>] = [:]
    private var didFinishDismissal = false

    var ukModalScrollView: UIScrollView? { scroll }

    /// Creates the form.
    ///
    /// - Parameters:
    ///   - kind: Bug report or feature request.
    ///   - session: Service session used only when Submit is pressed.
    ///   - onSent: Called with the success notice just before the form closes itself.
    init(kind: FeedbackKind, session: FestivalSession, onSent: @escaping (FeedbackSentNotice) -> Void) {
        self.kind = kind
        self.session = session
        self.onSent = onSent
        model = FeedbackFormModel(kind: kind)
        busy = UIActivityIndicatorView(style: .large)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { mediaImports.values.forEach { $0.cancel() } }

    /// Presents the form over `presenter`.
    ///
    /// - Parameters:
    ///   - kind: Bug report or feature request.
    ///   - session: The shared session.
    ///   - presenter: The controller to present from.
    ///   - onSent: Receives the sent notice when a form files.
    ///   - onDismiss: Runs after the sheet has gone, however it closed.
    static func present(
        kind: FeedbackKind, session: FestivalSession, from presenter: UIViewController,
        onSent: @escaping (FeedbackSentNotice) -> Void, onDismiss: @escaping () -> Void
    ) {
        let form = UKFeedbackFormViewController(kind: kind, session: session, onSent: onSent)
        let sheet = UKSheet.make(
            form, title: kind.formTitle, closeIdentifier: "fst.settings.feedback.close", size: .large, sizing: .regularPage,
            regularWidth: presenter.traitCollection.horizontalSizeClass == .regular, onClose: { form.requestClose() }
        )
        form.rearmClose = { [weak sheet] in sheet?.ukRearmClose() }
        sheet.presentationController?.delegate = form
        form.onDismiss = onDismiss
        _ = UKPresentationCoordinator.shared(for: presenter).presentIndependent(
            sheet, from: presenter, onDismiss: { [weak form] in form?.finishDismissal() }
        )
    }

    private var onDismiss: (() -> Void)?
    private var rearmClose: (() -> Void)?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        navigationItem.leftBarButtonItem = closeItem
        navigationItem.rightBarButtonItem = submitItem
        closeItem.accessibilityIdentifier = "fst.settings.feedback.close"
        submitItem.accessibilityIdentifier = "fst.settings.feedback.submit"
        submitItem.style = .done
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        formHolder.translatesAutoresizingMaskIntoConstraints = false
        formPane.translatesAutoresizingMaskIntoConstraints = false
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formHolder)
        view.addSubview(statusView)
        formPane.addSubview(scroll)
        formHolder.addSubview(formPane)
        formHolderConstraints = [
            formHolder.leadingAnchor.constraint(equalTo: view.leadingAnchor), formHolder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formHolder.topAnchor.constraint(equalTo: view.topAnchor), formHolder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(formHolderConstraints)
        NSLayoutConstraint.activate([
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor), statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: view.topAnchor), statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        formPaneConstraints += [
            formPane.leadingAnchor.constraint(equalTo: formHolder.leadingAnchor), formPane.trailingAnchor.constraint(equalTo: formHolder.trailingAnchor),
            formPane.topAnchor.constraint(equalTo: formHolder.topAnchor), formPane.bottomAnchor.constraint(equalTo: formHolder.bottomAnchor),
        ]
        NSLayoutConstraint.activate(formPaneConstraints)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: formPane.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: formPane.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: formPane.topAnchor), scroll.bottomAnchor.constraint(equalTo: formPane.bottomAnchor),
        ])
        column.axis = .vertical
        column.spacing = 20
        UKSettingsScrollPage.install(column, in: scroll, side: 16, top: 8, bottom: 32)
        buildForm()
        buildStatus()
        statusView.isHidden = true
        installDropInteractions()
        librarySelection.onDeselect = { [weak self] identifiers in
            self?.libraryPicker?.deselectAssets(withIdentifiers: identifiers)
        }
        observations.observe { [weak self] in self?.render() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if libraryVisible && !canInlinePhotoLibrary { hideInlinePhotoLibrary() }
        if UKSettingsScrollPage.remeasureLabels(in: scroll) { scroll.setNeedsLayout() }
    }

    private func finishDismissal() {
        guard !didFinishDismissal else { return }
        didFinishDismissal = true
        stopMediaImports()
        librarySelection.close()
        model.discardMedia()
        let done = onDismiss
        onDismiss = nil
        done?()
    }

    // MARK: Form

    private var platform: FeedbackPlatform {
        FeedbackPlatform.resolve(isMac: false, isPad: UIDevice.current.userInterfaceIdiom == .pad, hasHinge: ukWindowLayout.pose != .standard)
    }

    private var titleDetail: String {
        "Keep the \(kind.titlePrefix.trimmingCharacters(in: .whitespaces)) prefix and "
            + (kind == .bug ? "sum up the problem in a few words." : "name the idea in a few words.")
    }

    private var descriptionDetail: String {
        kind == .bug
            ? "What went wrong? Say which page you were on and what you saw."
            : "Describe the feature and how it would help you."
    }

    private var mediaDetail: String {
        "Optional screenshots or screen recordings: up to \(FeedbackLimits.attachments) photos or videos, "
            + ByteCountFormatter.string(fromByteCount: FeedbackLimits.totalAttachmentBytes, countStyle: .file)
            + " in total."
    }

    private func header(_ title: String, detail: String) -> UIView {
        let heading = UKLabel(title, style: .subheadline, weight: .semibold).asHeader()
        let text = UKLabel(detail, style: .footnote)
        let stack = UIStackView(arrangedSubviews: [heading, text])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isAccessibilityElement = false
        return stack
    }

    private func section(_ title: String, detail: String, content: UIView) -> UIView {
        let card = UKCardView(cornerRadius: 12)
        card.embed(content, insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        let stack = UIStackView(arrangedSubviews: [header(title, detail: detail), card])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func buildForm() {
        titleField.font = UKFont.font(.body)
        titleField.adjustsFontForContentSizeCategory = true
        titleField.textColor = BrandUIColors.textPrimary
        titleField.attributedPlaceholder = NSAttributedString(string: "Title", attributes: [.foregroundColor: BrandUIColors.textMuted])
        titleField.autocapitalizationType = .sentences
        titleField.clearButtonMode = .never
        titleField.text = model.title
        titleField.accessibilityLabel = "Title"
        titleField.accessibilityHint = titleDetail
        titleField.accessibilityIdentifier = "fst.settings.feedback.field.title"
        titleField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        titleField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            model.title = titleField.text ?? ""
            let normalized = model.title
            if normalized != titleField.text { titleField.text = normalized }
        }, for: .editingChanged)
        column.addArrangedSubview(section("Title", detail: titleDetail, content: titleField))
        column.addArrangedSubview(textBox("Description", detail: descriptionDetail, identifier: "fst.settings.feedback.field.description", keyPath: \.descriptionValue))
        if kind.includesReproduction {
            column.addArrangedSubview(textBox(
                "Steps to Reproduce", detail: "List the steps that make it happen, one per line.",
                identifier: "fst.settings.feedback.field.repro", keyPath: \.reproValue
            ))
            column.addArrangedSubview(textBox(
                "Expected Behavior", detail: "What did you expect to happen instead?",
                identifier: "fst.settings.feedback.field.expected", keyPath: \.expectedValue
            ))
        }
        column.addArrangedSubview(mediaSection())
        validation.accessibilityIdentifier = "fst.settings.feedback.validation"
        column.addArrangedSubview(validation)
    }

    fileprivate var descriptionValue: String {
        get { model.descriptionText }
        set { model.descriptionText = newValue }
    }

    fileprivate var reproValue: String {
        get { model.reproSteps }
        set { model.reproSteps = newValue }
    }

    fileprivate var expectedValue: String {
        get { model.expectedBehavior }
        set { model.expectedBehavior = newValue }
    }

    private func textBox(_ label: String, detail: String, identifier: String, keyPath: ReferenceWritableKeyPath<UKFeedbackFormViewController, String>) -> UIView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = UKFont.font(.body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = BrandUIColors.textPrimary
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.text = self[keyPath: keyPath]
        view.accessibilityLabel = label
        view.accessibilityHint = detail
        view.accessibilityIdentifier = identifier
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        view.isEditable = true
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        textViews.append((view, keyPath))
        view.delegate = self
        let result = section(label, detail: detail, content: view)
        // A tap anywhere in the box's card focuses it, as a SwiftUI `TextEditor` row does.
        let focus = UITapGestureRecognizer(target: view, action: #selector(UIResponder.becomeFirstResponder))
        focus.cancelsTouchesInView = false
        result.addGestureRecognizer(focus)
        return result
    }

    private func mediaSection() -> UIView {
        strip.axis = .horizontal
        strip.spacing = 12
        strip.isLayoutMarginsRelativeArrangement = true
        let stripScroll = UIScrollView()
        stripScroll.showsHorizontalScrollIndicator = false
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            strip.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            strip.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            strip.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),
            stripScroll.heightAnchor.constraint(equalToConstant: 100),
        ])
        stripScroll.accessibilityIdentifier = "fst.settings.feedback.attachments"
        stripScroll.isHidden = true
        stripScroll.tag = 77
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Attach Media"
        configuration.image = UIImage(systemName: "paperclip")
        configuration.imagePadding = 8
        configuration.baseForegroundColor = BrandUIColors.accentBlue
        configuration.contentInsets = .zero
        attachMenuButton.configuration = configuration
        attachMenuButton.contentHorizontalAlignment = .leading
        attachMenuButton.showsMenuAsPrimaryAction = true
        attachMenuButton.menu = UIMenu(children: [
            makeAction("Photo Library", image: "photo.on.rectangle", id: "fst.settings.feedback.attach.media") { [weak self] in self?.pickPhotos() },
            makeAction("Choose File…", image: "folder", id: "fst.settings.feedback.attach.files") { [weak self] in self?.pickFiles() },
        ])
        attachMenuButton.accessibilityIdentifier = "fst.settings.feedback.attach"
        attachMenuButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        attachProgress.accessibilityIdentifier = "fst.settings.feedback.attach.progress"
        attachMessage.accessibilityIdentifier = "fst.settings.feedback.attachments.notice"
        dropNotice.accessibilityIdentifier = "fst.settings.feedback.drop.shown"
        dropNotice.isHidden = true
        let content = UIStackView(arrangedSubviews: [
            stripScroll, attachMenuButton, attachProgress, attachMessage, dropNotice,
        ])
        content.axis = .vertical
        content.spacing = 8
        return section("Media", detail: mediaDetail, content: content)
    }

    private func makeAction(_ title: String, image: String, id: String, handler: @escaping () -> Void) -> UIAction {
        let action = UIAction(title: title, image: UIImage(systemName: image)) { _ in handler() }
        action.accessibilityIdentifier = id
        return action
    }

    // MARK: Inline photo library and drops

    private var canInlinePhotoLibrary: Bool {
        let widthClass: WidthClass = traitCollection.horizontalSizeClass == .regular ? .regular : .compact
        let isPadOrDuo = UIDevice.current.userInterfaceIdiom == .pad || ukWindowLayout.pose != .standard
        return isPadOrDuo && FeedbackPhotoLibraryPlacement.resolve(
            isMac: false, windowWidthClass: widthClass
        ) == .beside
    }

    private func makePhotoPicker(inline: Bool = false) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = inline
            ? FeedbackLimits.attachments : max(1, FeedbackLimits.attachments - model.attachments.count)
        if inline {
            configuration.selection = .continuousAndOrdered
            configuration.preselectedAssetIdentifiers = librarySelection.selected
        }
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        return picker
    }

    private func showInlinePhotoLibrary() {
        guard canInlinePhotoLibrary, !libraryVisible else { return }
        libraryVisible = true
        libraryPane.translatesAutoresizingMaskIntoConstraints = false
        libraryPane.accessibilityIdentifier = "fst.settings.feedback.library"
        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.addArrangedSubview(UKLabel("Photo Library", style: .headline, weight: .semibold))
        header.addArrangedSubview(UIView())
        let hide = UIButton(type: .system)
        hide.setTitle("Hide", for: .normal)
        hide.accessibilityIdentifier = "fst.settings.feedback.library.hide"
        NSLayoutConstraint.activate([
            hide.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            hide.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        hide.addAction(UIAction { [weak self] _ in self?.hideInlinePhotoLibrary() }, for: .touchUpInside)
        header.addArrangedSubview(hide)
        libraryHideButton = hide
        let picker = makePhotoPicker(inline: true)
        libraryPicker = picker
        addChild(picker)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        libraryPane.addSubview(header)
        libraryPane.addSubview(picker.view)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: libraryPane.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: libraryPane.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: libraryPane.topAnchor, constant: 8),
            picker.view.leadingAnchor.constraint(equalTo: libraryPane.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: libraryPane.trailingAnchor),
            picker.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            picker.view.bottomAnchor.constraint(equalTo: libraryPane.bottomAnchor),
        ])
        picker.didMove(toParent: self)

        NSLayoutConstraint.deactivate(formPaneConstraints)
        formPane.removeFromSuperview()
        let host = UKHingeColumnsView()
        host.layoutProvider = { [weak self] in self?.ukWindowLayout ?? .standardPhone }
        host.translatesAutoresizingMaskIntoConstraints = false
        host.leadingContent.addSubview(formPane)
        host.trailingContent.addSubview(libraryPane)
        formPane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            formPane.leadingAnchor.constraint(equalTo: host.leadingContent.leadingAnchor),
            formPane.trailingAnchor.constraint(equalTo: host.leadingContent.trailingAnchor),
            formPane.topAnchor.constraint(equalTo: host.leadingContent.topAnchor),
            formPane.bottomAnchor.constraint(equalTo: host.leadingContent.bottomAnchor),
            libraryPane.leadingAnchor.constraint(equalTo: host.trailingContent.leadingAnchor),
            libraryPane.trailingAnchor.constraint(equalTo: host.trailingContent.trailingAnchor),
            libraryPane.topAnchor.constraint(equalTo: host.trailingContent.topAnchor),
            libraryPane.bottomAnchor.constraint(equalTo: host.trailingContent.bottomAnchor),
        ])
        formHolder.addSubview(host)
        paneHostConstraints = [
            host.leadingAnchor.constraint(equalTo: formHolder.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: formHolder.trailingAnchor),
            host.topAnchor.constraint(equalTo: formHolder.topAnchor),
            host.bottomAnchor.constraint(equalTo: formHolder.bottomAnchor),
        ]
        NSLayoutConstraint.activate(paneHostConstraints)
        paneHost = host
    }

    private func hideInlinePhotoLibrary() {
        guard libraryVisible else { return }
        libraryVisible = false
        if let picker = libraryPicker {
            picker.willMove(toParent: nil)
            picker.view.removeFromSuperview()
            picker.removeFromParent()
        }
        libraryPicker = nil
        libraryHideButton = nil
        libraryPane.subviews.forEach { $0.removeFromSuperview() }
        if let host = paneHost {
            NSLayoutConstraint.deactivate(paneHostConstraints)
            host.removeFromSuperview()
            paneHost = nil
        }
        formPane.removeFromSuperview()
        formHolder.addSubview(formPane)
        NSLayoutConstraint.activate(formPaneConstraints)
    }

    private func installDropInteractions() {
        let interaction = UIDropInteraction(delegate: self)
        formHolder.addInteraction(interaction)
        scroll.addInteraction(UIDropInteraction(delegate: self))
        for textView in textViews {
            textView.0.addInteraction(UIDropInteraction(delegate: self))
        }
    }

    private func setDropTarget(_ active: Bool) {
        dropTargets = max(0, dropTargets + (active ? 1 : -1))
        let visible = dropTargets > 0 && model.acceptsMedia
        dropNotice.isHidden = !visible
        formHolder.layer.borderWidth = visible ? 2 : 0
        formHolder.layer.borderColor = visible ? BrandUIColors.accentBlue.cgColor : nil
        formHolder.layer.cornerRadius = visible ? 12 : 0
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: FeedbackPickedMedia.droppableTypes.map(\.identifier))
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {
        setDropTarget(true)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) {
        setDropTarget(false)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: model.acceptsMedia ? .copy : .forbidden)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        setDropTarget(false)
        guard model.acceptsMedia else { return }
        let providers = session.items.map(\.itemProvider)
        importMedia { [model] in await model.importDropped(await FeedbackPickedMedia.load(from: providers)) }
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) {
        setDropTarget(false)
    }

    // MARK: Status

    private func buildStatus() {
        statusView.backgroundColor = .clear
        busy.translatesAutoresizingMaskIntoConstraints = false
        busy.hidesWhenStopped = false
        busy.startAnimating()
        busy.isAccessibilityElement = true
        busy.accessibilityLabel = FeedbackSendingStage.busyLabel(for: kind)
        busy.accessibilityIdentifier = "fst.settings.feedback.busy"
        statusTitle.accessibilityIdentifier = "fst.settings.feedback.status.title"
        statusSubtitle.accessibilityIdentifier = "fst.settings.feedback.status.subtitle"
        progressBar.accessibilityLabel = "Upload progress"
        progressBar.accessibilityIdentifier = "fst.settings.feedback.progress"
        progressBar.tintColor = BrandUIColors.accentPurple
        var stop = UIButton.Configuration.plain()
        stop.title = "Stop Sending"
        stop.baseForegroundColor = BrandUIColors.statusRed
        stopButton.configuration = stop
        stopButton.accessibilityIdentifier = "fst.settings.feedback.stop"
        stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stopButton.addAction(UIAction { [weak self] _ in self?.model.cancelSubmit() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [busy, statusTitle, statusSubtitle, progressBar, stopButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.setCustomSpacing(20, after: busy)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.accessibilityContainerType = .semanticGroup
        stack.accessibilityIdentifier = "fst.settings.feedback.status"
        statusView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -24),
            progressBar.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor).withPriority(.defaultHigh),
            busy.widthAnchor.constraint(greaterThanOrEqualToConstant: 44), busy.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func setStatus(_ stage: FeedbackSendingStage?) {
        let show = stage != nil
        if let stage {
            statusTitle.text = stage.title(for: kind)
            let subtitle = stage.subtitle(for: kind)
            statusSubtitle.text = subtitle
            statusSubtitle.isHidden = subtitle == nil
            progressBar.isHidden = subtitle != nil
            stopButton.isHidden = subtitle != nil
            if shownStage != stage, shownStage != nil { UIAccessibility.post(notification: .announcement, argument: stage.title(for: kind)) }
        }
        shownStage = stage
        guard show != showsStatus else { return }
        showsStatus = show
        view.endEditing(true)
        let duration: TimeInterval = UKAccessibility.reduceMotion ? 0 : 0.3
        if show {
            statusView.isHidden = false
            statusView.alpha = 0
            UIView.animate(withDuration: duration) {
                self.formHolder.alpha = 0
                self.statusView.alpha = 1
            } completion: { _ in self.formHolder.isHidden = self.showsStatus }
            if duration == 0 { formHolder.isHidden = true }
        } else {
            formHolder.isHidden = false
            UIView.animate(withDuration: duration) {
                self.formHolder.alpha = 1
                self.statusView.alpha = 0
            } completion: { _ in self.statusView.isHidden = !self.showsStatus }
            if duration == 0 { statusView.isHidden = true }
        }
    }

    // MARK: Rendering

    private func render() {
        let phase = model.phase
        let canSubmit = model.canSubmit
        let issue = model.draft.validationIssue
        let busyNow = model.isBusy
        let attachments = model.attachments
        let importing = model.importing
        let message = model.attachmentMessage
        let unsaved = model.hasUnsavedInput
        let filing = model.isFiling
        librarySelection.prune(keeping: Set(attachments.map(\.id)))
        libraryPicker?.view.isUserInteractionEnabled = !busyNow
        if busyNow {
            dropTargets = 0
            dropNotice.isHidden = true
            formHolder.layer.borderWidth = 0
        }
        if submitItem.isEnabled != canSubmit { submitItem.isEnabled = canSubmit }
        closeItem.title = filing ? "Close" : "Cancel"
        let modal = model.isSubmitting || (unsaved && !filing)
        if navigationController?.isModalInPresentation != modal { navigationController?.isModalInPresentation = modal }
        validation.text = (!busyNow ? issue?.message : nil)
        validation.isHidden = validation.text == nil
        attachProgress.isHidden = importing == 0
        attachMessage.text = message
        attachMessage.isHidden = message == nil
        let canAttach = attachments.count < FeedbackLimits.attachments && !busyNow
        if attachMenuButton.isEnabled != canAttach { attachMenuButton.isEnabled = canAttach }
        for (box, _) in textViews where box.isEditable == busyNow { box.isEditable = !busyNow }
        if titleField.isEnabled == busyNow { titleField.isEnabled = !busyNow }
        updateStrip(attachments)
        var fraction = 0.0
        if case let .submitting(value) = phase { fraction = value }
        progressBar.progress = Float(fraction)
        setStatus(FeedbackSendingStage.target(for: phase, hasMedia: !attachments.isEmpty).flatMap {
            if case let .status(stage) = $0 { stage } else { nil }
        })
        switch phase {
        case let .failed(text) where !alertedFailure:
            alertedFailure = true
            let alert = UIAlertController(title: "Couldn't Send", message: text, preferredStyle: .alert)
            alert.addAction(alert.ukAction(title: "OK", style: .cancel) { [weak self] in
                self?.alertedFailure = false
                self?.model.acknowledgeFailure()
            })
            _ = UKPresentationCoordinator.shared(for: self).presentRelated(alert, from: self)
        case let .finished(outcome) where !handedOver:
            handedOver = true
            onSent(FeedbackSentNotice(kind: kind, outcome: outcome))
            closeNow()
        default: break
        }
    }

    private func updateStrip(_ attachments: [FeedbackAttachment]) {
        let key = attachments.map(\.id.uuidString).joined(separator: ",")
        guard key != stripKey else { return }
        stripKey = key
        previewURLs = attachments.map(\.fileURL)
        strip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, attachment) in attachments.enumerated() {
            strip.addArrangedSubview(tile(attachment, position: index + 1))
        }
        strip.superview?.isHidden = attachments.isEmpty
        UIView.performWithoutAnimation { column.layoutIfNeeded() }
    }

    private func tile(_ attachment: FeedbackAttachment, position: Int) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let open = UIButton(type: .custom)
        open.translatesAutoresizingMaskIntoConstraints = false
        open.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        open.layer.cornerRadius = 12
        open.layer.cornerCurve = .continuous
        open.clipsToBounds = true
        open.setImage(UIImage(systemName: attachment.isVideo ? "film" : "photo"), for: .normal)
        open.tintColor = BrandUIColors.textPrimary
        open.accessibilityLabel = attachment.accessibilityLabel(position: position)
        open.accessibilityHint = "Opens in Quick Look"
        open.accessibilityIdentifier = "fst.settings.feedback.attachment.\(position)"
        open.addAction(UIAction { [weak self] _ in self?.preview(position - 1) }, for: .touchUpInside)
        let remove = UIButton(type: .custom)
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.font(.title3))), for: .normal)
        remove.tintColor = BrandUIColors.textPrimary
        remove.accessibilityLabel = "Remove \(attachment.filename)"
        remove.accessibilityIdentifier = "fst.settings.feedback.attachment.\(position).remove"
        remove.addAction(UIAction { [weak self] _ in
            self?.librarySelection.removeAttachment(id: attachment.id)
        }, for: .touchUpInside)
        holder.addSubview(open)
        holder.addSubview(remove)
        NSLayoutConstraint.activate([
            open.leadingAnchor.constraint(equalTo: holder.leadingAnchor), open.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            open.widthAnchor.constraint(equalToConstant: 76), open.heightAnchor.constraint(equalToConstant: 76),
            open.topAnchor.constraint(equalTo: holder.topAnchor, constant: 22),
            remove.widthAnchor.constraint(equalToConstant: 44), remove.heightAnchor.constraint(equalToConstant: 44),
            remove.centerXAnchor.constraint(equalTo: open.trailingAnchor), remove.centerYAnchor.constraint(equalTo: open.topAnchor),
            holder.trailingAnchor.constraint(equalTo: remove.trailingAnchor),
        ])
        holder.accessibilityContainerType = .semanticGroup
        Task { [weak open] in
            let request = QLThumbnailGenerator.Request(
                fileAt: attachment.fileURL, size: CGSize(width: 76, height: 76), scale: UIScreen.main.scale, representationTypes: .thumbnail
            )
            if let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage {
                open?.setImage(image, for: .normal)
                open?.imageView?.contentMode = .scaleAspectFill
            }
        }
        return holder
    }

    // MARK: Actions

    private func submit() {
        view.endEditing(true)
        model.submit(session: session, platform: platform)
    }

    /// Cancel, Escape or a swipe: confirm first when something would be lost. While the service
    /// files an accepted report nothing can be lost, so it closes at once.
    func requestClose() {
        if model.isFiling {
            closeNow()
        } else if model.hasUnsavedInput || model.isSubmitting {
            confirmDiscard()
        } else {
            closeNow()
        }
    }

    private func closeNow() {
        stopMediaImports()
        librarySelection.close()
        model.discardMedia()
        let controller = navigationController ?? self
        UKPresentationCoordinator.shared(for: self).dismiss(controller)
    }

    private func confirmDiscard() {
        let alert = UIAlertController(
            title: kind == .bug ? "Discard this report?" : "Discard this request?",
            message: "Your text and attached media will be lost.", preferredStyle: .actionSheet
        )
        let discard = alert.ukAction(title: "Discard Changes", style: .destructive) { [weak self] in self?.closeNow() }
        let keep = alert.ukAction(title: "Keep Editing", style: .cancel) { [weak self] in
            self?.rearmClose?()
        }
        alert.addAction(discard)
        alert.addAction(keep)
        alert.popoverPresentationController?.barButtonItem = closeItem
        _ = UKPresentationCoordinator.shared(for: self).presentRelated(alert, from: self) {
            UKAlertIdentifiers.apply(["Discard Changes": "fst.settings.feedback.discard.confirm", "Keep Editing": "fst.settings.feedback.discard.cancel"], in: alert.view)
        }
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { requestClose() }

    // MARK: Pickers

    private func pickPhotos() {
        guard model.attachments.count < FeedbackLimits.attachments else { return }
        if canInlinePhotoLibrary {
            showInlinePhotoLibrary()
        } else {
            let picker = makePhotoPicker()
            _ = UKPresentationCoordinator.shared(for: self).presentRelated(picker, from: self)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let isInline = picker === libraryPicker
        if isInline {
            librarySelection.apply(results.compactMap { result in
                result.assetIdentifier.map {
                    UKFeedbackPhotoSelection.Item(identifier: $0, provider: result.itemProvider)
                }
            })
            return
        } else {
            UKPresentationCoordinator.shared(for: self).dismiss(picker)
        }
        let providers = results.map(\.itemProvider)
        guard !providers.isEmpty else { return }
        importMedia { [model] in await model.importDropped(await FeedbackPickedMedia.load(from: providers)) }
    }

    private func pickFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        _ = UKPresentationCoordinator.shared(for: self).presentRelated(picker, from: self)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        UKPresentationCoordinator.shared(for: self).dismiss(controller) { [weak self] in
            guard let self else { return }
            importMedia { [model] in await model.importFiles(.success(urls)) }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        UKPresentationCoordinator.shared(for: self).dismiss(controller)
    }

    private func importMedia(_ operation: @escaping @MainActor () async -> Void) {
        guard !didFinishDismissal, model.acceptsMedia else { return }
        let token = UUID()
        mediaImports[token] = Task { @MainActor [weak self] in
            await operation()
            self?.mediaImports[token] = nil
        }
    }

    private func stopMediaImports() {
        mediaImports.values.forEach { $0.cancel() }
        mediaImports.removeAll()
    }

    // MARK: Quick Look

    private func preview(_ index: Int) {
        let controller = QLPreviewController()
        controller.dataSource = self
        controller.delegate = self
        controller.currentPreviewItemIndex = index
        _ = UKPresentationCoordinator.shared(for: self).presentRelated(controller, from: self)
    }

    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        MainActor.assumeIsolated { previewURLs[index] as NSURL }
    }

    nonisolated func previewControllerDidDismiss(_ controller: QLPreviewController) {
        MainActor.assumeIsolated { UKMotionVisibility.changed() }
    }
}

extension UKFeedbackFormViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let entry = textViews.first(where: { $0.0 === textView }) else { return }
        self[keyPath: entry.1] = textView.text
    }
}

// MARK: - Alert identifiers

/// Accessibility identifiers for the buttons of a system alert or action sheet, which
/// `UIAlertAction` cannot carry: found by their title in the presented alert's views.
@MainActor
enum UKAlertIdentifiers {
    /// Sets identifiers on the alert's button views.
    ///
    /// - Parameters:
    ///   - identifiers: Button title to identifier.
    ///   - root: The alert controller's view.
    static func apply(_ identifiers: [String: String], in root: UIView) {
        func walk(_ view: UIView) {
            if let label = view.accessibilityLabel, let id = identifiers[label], view.accessibilityIdentifier == nil || view.accessibilityIdentifier == "" {
                view.accessibilityIdentifier = id
            }
            if let label = (view as? UILabel)?.text, let id = identifiers[label] {
                view.accessibilityIdentifier = id
                var parent = view.superview
                while let current = parent, current !== root {
                    if current.isAccessibilityElement, current.accessibilityIdentifier == nil { current.accessibilityIdentifier = id }
                    parent = current.superview
                }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
    }
}

// MARK: - Debug focus trace

/// The Debug focus-trace element (`fst.nav.a11y-focus`, `FST_DEBUG_A11Y_FOCUS_TRACE=1`): 1 pt and
/// nearly clear, labelled with ``AccessibilityFocusTrace``'s last move, so a journey can read where
/// VoiceOver focus was sent.
@MainActor
final class UKFocusTraceView: UIView {
    private let observations = UKObservationBag()

    /// Creates the trace element when tracing is on, else nil.
    static func makeIfEnabled() -> UKFocusTraceView? {
        AccessibilityFocusTrace.isEnabled ? UKFocusTraceView() : nil
    }

    private init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        alpha = 0.02
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "fst.nav.a11y-focus"
        observations.observe { [weak self] in
            let last = AccessibilityFocusTrace.shared.last
            self?.accessibilityLabel = last.isEmpty ? "none" : last
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
