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
/// the document picker; both go through the model's own import and limits. Dragging media onto
/// the form and the beside-the-form photo pane are not ported.
@MainActor
final class UKFeedbackFormViewController: UIViewController, UKModalScrollProviding, UIAdaptivePresentationControllerDelegate,
    PHPickerViewControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
    private let kind: FeedbackKind
    private let session: FestivalSession
    private let onSent: (FeedbackSentNotice) -> Void
    private let model: FeedbackFormModel
    private let scroll = UIScrollView()
    private let column = UIStackView()
    private let formHolder = UIView()
    private let statusView = UIView()
    private let observations = UKObservationBag()
    private let titleField = UITextField()
    private var textViews: [(UITextView, ReferenceWritableKeyPath<UKFeedbackFormViewController, String>)] = []
    private let validation = UKLabel(style: .footnote)
    private let strip = UIStackView()
    private let attachMenuButton = UIButton(type: .system)
    private let attachProgress = UKLoadingView(status: "Adding media…")
    private let attachMessage = UKLabel(style: .footnote, color: BrandUIColors.statusRed)
    private lazy var submitItem = UIBarButtonItem(title: "Submit", primaryAction: UIAction { [weak self] _ in self?.submit() })
    private lazy var closeItem = UIBarButtonItem(title: "Cancel", primaryAction: UIAction { [weak self] _ in self?.requestClose() })
    private var statusTitle = UKStateTitleLabel("")
    private var statusSubtitle = UKStateSubtitleLabel("")
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let stopButton = UIButton(type: .system)
    private let busy: UKLoadingView
    private var showsStatus = false
    private var shownStage: FeedbackSendingStage?
    private var handedOver = false
    private var alertedFailure = false
    private var previewURLs: [URL] = []
    private var stripKey = ""

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
        busy = UKLoadingView(accessibilityLabel: FeedbackSendingStage.busyLabel(for: kind), placement: .inline)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        sheet.presentationController?.delegate = form
        form.onDismiss = onDismiss
        presenter.present(sheet, animated: true)
    }

    private var onDismiss: (() -> Void)?

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
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formHolder)
        view.addSubview(statusView)
        formHolder.addSubview(scroll)
        NSLayoutConstraint.activate([
            formHolder.leadingAnchor.constraint(equalTo: view.leadingAnchor), formHolder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            formHolder.topAnchor.constraint(equalTo: view.topAnchor), formHolder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor), statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: view.topAnchor), statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: formHolder.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: formHolder.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: formHolder.topAnchor), scroll.bottomAnchor.constraint(equalTo: formHolder.bottomAnchor),
        ])
        column.axis = .vertical
        column.spacing = 20
        UKSettingsScrollPage.install(column, in: scroll, side: 16, top: 8, bottom: 32)
        buildForm()
        buildStatus()
        statusView.isHidden = true
        observations.observe { [weak self] in self?.render() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if UKSettingsScrollPage.remeasureLabels(in: scroll) { scroll.setNeedsLayout() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed == true || isBeingDismissed { finishDismissal() }
    }

    private func finishDismissal() {
        FeedbackFormModel.purgeStagedMedia()
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
        let content = UIStackView(arrangedSubviews: [stripScroll, attachMenuButton, attachProgress, attachMessage])
        content.axis = .vertical
        content.spacing = 8
        return section("Media", detail: mediaDetail, content: content)
    }

    private func makeAction(_ title: String, image: String, id: String, handler: @escaping () -> Void) -> UIAction {
        let action = UIAction(title: title, image: UIImage(systemName: image)) { _ in handler() }
        action.accessibilityIdentifier = id
        return action
    }

    // MARK: Status

    private func buildStatus() {
        statusView.backgroundColor = .clear
        busy.accessibilityIdentifier = "fst.settings.feedback.busy"
        busy.translatesAutoresizingMaskIntoConstraints = false
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
            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.alertedFailure = false
                self?.model.acknowledgeFailure()
            })
            present(alert, animated: true)
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
        remove.addAction(UIAction { [weak self] _ in self?.model.remove(attachment) }, for: .touchUpInside)
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
        model.discardMedia()
        (navigationController ?? self).dismiss(animated: true) { [weak self] in self?.finishDismissal() }
    }

    private func confirmDiscard() {
        let alert = UIAlertController(
            title: kind == .bug ? "Discard this report?" : "Discard this request?",
            message: "Your text and attached media will be lost.", preferredStyle: .actionSheet
        )
        let discard = UIAlertAction(title: "Discard Changes", style: .destructive) { [weak self] _ in self?.closeNow() }
        let keep = UIAlertAction(title: "Keep Editing", style: .cancel)
        alert.addAction(discard)
        alert.addAction(keep)
        alert.popoverPresentationController?.barButtonItem = closeItem
        present(alert, animated: true) {
            UKAlertIdentifiers.apply(["Discard Changes": "fst.settings.feedback.discard.confirm", "Keep Editing": "fst.settings.feedback.discard.cancel"], in: alert.view)
        }
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { requestClose() }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finishDismissal() }

    // MARK: Pickers

    private func pickPhotos() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = max(1, FeedbackLimits.attachments - model.attachments.count)
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let providers = results.map(\.itemProvider)
        guard !providers.isEmpty else { return }
        Task { await model.importDropped(await FeedbackPickedMedia.load(from: providers)) }
    }

    private func pickFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { await model.importFiles(.success(urls)) }
    }

    // MARK: Quick Look

    private func preview(_ index: Int) {
        let controller = QLPreviewController()
        controller.dataSource = self
        controller.currentPreviewItemIndex = index
        present(controller, animated: true)
    }

    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        MainActor.assumeIsolated { previewURLs[index] as NSURL }
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
