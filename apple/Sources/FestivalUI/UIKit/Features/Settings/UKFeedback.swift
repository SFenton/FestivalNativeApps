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
/// the document picker; both go through the model's own import and limits. At regular width
/// the Photos picker sits beside the form through the shared hinge-aware columns.
@MainActor
final class UKFeedbackFormViewController: UIViewController, UKModalScrollProviding, UIAdaptivePresentationControllerDelegate,
    PHPickerViewControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
    private let kind: FeedbackKind
    private let session: FestivalSession
    private let onSent: (FeedbackSentNotice) -> Void
    private let model: FeedbackFormModel
    private let scroll = UIScrollView()
    private let column = UIStackView()
    private var contentLayout: UKFormContentLayout?
    private let formHolder = UIView()
    private let formPanes = UKHingeColumnsView()
    private var library: UKFeedbackPhotoLibrary?
    private var mediaImports: [UUID: Task<Void, Never>] = [:]
    private let mediaHint = UKLabel(style: .footnote)
    private let dropHighlight = UIView()
    private lazy var mediaDrop = FeedbackMediaDropCoordinator(
        accepts: { [weak self] in self?.model.acceptsMedia == true },
        onTargetChange: { [weak self] in self?.showDropHighlight($0) },
        onDrop: { [weak self] providers in
            self?.importMedia(providers.filter { FeedbackPickedMedia.droppableType(of: $0) != nil })
        }
    )
    #if DEBUG
    private var dropMarker: UIView?
    private var dropHighlights = 0
    #endif
    private let statusView = UKCentredFillView(padding: UKEmptyStateView.fillPadding)
    private let observations = UKObservationBag()
    private let titleField = UITextField()
    private var textViews: [(UITextView, ReferenceWritableKeyPath<UKFeedbackFormViewController, String>)] = []
    private let validation = UKLabel(style: .footnote)
    private let validationSection = UKGroupSectionView(surface: .form)
    private let strip = UIStackView()
    private let stripScroll = UIScrollView()
    private let attachMenuButton = UIButton(type: .system)
    private let attachProgress = UKLoadingView(status: "Adding media…")
    private let attachMessage = UKLabel(style: .footnote, color: BrandUIColors.statusRed)
    private lazy var mediaGroup = UKGroupSectionView(
        header: header("Media", detail: mediaHint), rows: .flush(separatorInset: 0), surface: .form
    )
    private lazy var stripRow = UKGroupSectionView.formRow(stripScroll, horizontal: 0, vertical: 15)
    private lazy var progressRow = UKGroupSectionView.formRow(attachProgress)
    private lazy var messageRow = UKGroupSectionView.formRow(attachMessage, vertical: 15)
    private var visibleMediaRows: (Bool, Bool, Bool)?
    private lazy var submitItem = UIBarButtonItem(title: "Submit", primaryAction: UIAction { [weak self] _ in self?.submit() })
    private lazy var closeItem = UIBarButtonItem(title: "Cancel", primaryAction: UIAction { [weak self] _ in self?.requestClose() })
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let stopButton = UIButton(type: .system)
    private let uploadingStatus = UIStackView()
    private let filingStatus = UIStackView()
    private var sending = FeedbackSendingChoreography.Presentation.editing
    private var sendingTarget = FeedbackSendingChoreography.Target.form
    private var sendingSequence: Task<Void, Never>?
    private var sendingAnimator: UIViewPropertyAnimator?
    private var handedOver = false
    private var alertedFailure = false
    private var previewURLs: [URL] = []
    private var stripKey = ""

    var ukModalScrollView: UIScrollView? { scroll }
    var ukModalFadingView: UIView { formPanes.leadingContent }

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
        formPanes.translatesAutoresizingMaskIntoConstraints = false
        formPanes.showsTrailingContent = false
        formPanes.spacing = 0
        formPanes.layoutProvider = { [weak self] in self?.ukWindowLayout ?? .standardPhone }
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formHolder)
        view.addSubview(statusView)
        formHolder.addSubview(formPanes)
        let editor = formPanes.leadingContent
        editor.addSubview(scroll)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            formHolder.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            formHolder.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            formHolder.topAnchor.constraint(equalTo: view.topAnchor), formHolder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            formPanes.leadingAnchor.constraint(equalTo: formHolder.leadingAnchor),
            formPanes.trailingAnchor.constraint(equalTo: formHolder.trailingAnchor),
            formPanes.topAnchor.constraint(equalTo: formHolder.topAnchor),
            formPanes.bottomAnchor.constraint(equalTo: formHolder.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: editor.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
        ])
        column.axis = .vertical
        column.spacing = 28
        contentLayout = UKFormContentLayout(column, in: scroll, bottom: 40, maximumWidth: UKSettingsScrollPage.columnWidth)
        buildForm()
        buildStatus()
        installMediaDrop()
        statusView.isHidden = true
        observations.observe { [weak self] in self?.render() }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        contentLayout?.updateGutters(in: view, layout: ukWindowLayout)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if formPanes.showsTrailingContent, photoLibraryPlacement == .presented { showLibrary(false) }
        formPanes.setNeedsLayout()
        if mediaHint.text != mediaDetail { mediaHint.text = mediaDetail }
        if UKSettingsScrollPage.remeasureLabels(in: scroll) { scroll.setNeedsLayout() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed == true || isBeingDismissed { finishDismissal() }
    }

    private func finishDismissal() {
        sendingSequence?.cancel()
        cancelMediaImports()
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
            + " in total." + (platform == .ios ? "" : " You can also drag them here.")
    }

    private func header(_ title: String, detail: UILabel) -> UIView {
        let heading = UKLabel(title, style: .subheadline, weight: .semibold).asHeader()
        let stack = UIStackView(arrangedSubviews: [heading, detail])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isAccessibilityElement = false
        return stack
    }

    private func section(_ title: String, detail: String, row: UIView) -> UIView {
        section(title, hint: UKLabel(detail, style: .footnote), row: row)
    }

    private func section(_ title: String, hint: UILabel, row: UIView) -> UIView {
        let group = UKGroupSectionView(
            header: header(title, detail: hint), rows: .flush(separatorInset: 0), surface: .form
        )
        group.setRows([row])
        return group
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
        column.addArrangedSubview(section("Title", detail: titleDetail, row: UKGroupSectionView.formRow(titleField)))
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
        let media = mediaSection()
        column.addArrangedSubview(media)
        column.setCustomSpacing(UKFormViewController.sectionSpacing, after: media)
        validation.accessibilityIdentifier = "fst.settings.feedback.validation"
        validationSection.setRows([validation])
        column.addArrangedSubview(validationSection)
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
        let result = section(label, detail: detail, row: UKGroupSectionView.formRow(view, vertical: 15))
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
        stripScroll.showsHorizontalScrollIndicator = false
        stripScroll.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            strip.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            strip.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            strip.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),
            stripScroll.heightAnchor.constraint(equalToConstant: 101),
        ])
        stripScroll.accessibilityIdentifier = "fst.settings.feedback.attachments"
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Attach Media"
        configuration.image = UIImage(systemName: "paperclip")
        configuration.imagePadding = 16
        configuration.baseForegroundColor = BrandUIColors.accentBlue
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 20, bottom: 15, trailing: 20)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.font(.body)
            return attributes
        }
        attachMenuButton.configuration = configuration
        attachMenuButton.titleLabel?.adjustsFontForContentSizeCategory = true
        attachMenuButton.titleLabel?.numberOfLines = 0
        attachMenuButton.contentHorizontalAlignment = .leading
        attachMenuButton.showsMenuAsPrimaryAction = true
        updateAttachMenu()
        attachMenuButton.accessibilityIdentifier = "fst.settings.feedback.attach"
        attachMenuButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 74).isActive = true
        attachProgress.accessibilityIdentifier = "fst.settings.feedback.attach.progress"
        attachMessage.accessibilityIdentifier = "fst.settings.feedback.attachments.notice"
        mediaHint.text = mediaDetail
        updateMediaRows(hasAttachments: false, importing: false, hasMessage: false)
        return mediaGroup
    }

    /// Rebuild the group only when an optional row enters or leaves, so separators track visible rows.
    ///
    /// - Parameters:
    ///   - hasAttachments: Whether the draft has any thumbnails.
    ///   - importing: Whether at least one import is in progress.
    ///   - hasMessage: Whether the import left a notice.
    private func updateMediaRows(hasAttachments: Bool, importing: Bool, hasMessage: Bool) {
        let visible = (hasAttachments, importing, hasMessage)
        if let visibleMediaRows, visibleMediaRows == visible { return }
        visibleMediaRows = visible
        var rows = [UIView]()
        if hasAttachments { rows.append(stripRow) }
        rows.append(attachMenuButton)
        if importing { rows.append(progressRow) }
        if hasMessage { rows.append(messageRow) }
        mediaGroup.setRows(rows)
    }

    private func makeAction(_ title: String, image: String, id: String, handler: @escaping () -> Void) -> UIAction {
        let action = UIAction(title: title, image: UIImage(systemName: image)) { _ in handler() }
        action.accessibilityIdentifier = id
        return action
    }

    private func updateAttachMenu() {
        let title = formPanes.showsTrailingContent ? "Hide Photo Library" : "Photo Library"
        attachMenuButton.menu = UIMenu(children: [
            makeAction(title, image: "photo.on.rectangle", id: "fst.settings.feedback.attach.media") { [weak self] in self?.pickPhotos() },
            makeAction("Choose File…", image: "folder", id: "fst.settings.feedback.attach.files") { [weak self] in self?.pickFiles() },
        ])
    }

    // MARK: Status

    private func buildStatus() {
        statusView.backgroundColor = .clear
        statusView.hingeProvider = { [weak self] in self?.ukWindowLayout.splitHinge }
        let spinner = UKArcView(size: .large)
        spinner.exposeAsActivityIndicator(
            label: FeedbackSendingStage.busyLabel(for: kind), identifier: "fst.settings.feedback.busy"
        )
        progressBar.accessibilityLabel = "Upload progress"
        progressBar.accessibilityIdentifier = "fst.settings.feedback.progress"
        progressBar.tintColor = BrandUIColors.accentPurple
        var stop = UIButton.Configuration.plain()
        stop.title = "Stop Sending"
        stop.baseForegroundColor = UKFormViewController.destructive
        stopButton.configuration = stop
        stopButton.accessibilityIdentifier = "fst.settings.feedback.stop"
        stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stopButton.addAction(UIAction { [weak self] _ in self?.model.cancelSubmit() }, for: .touchUpInside)
        let textSlot = UIView()
        buildStage(.uploading, in: uploadingStatus, slot: textSlot)
        buildStage(.filing, in: filingStatus, slot: textSlot)
        let spinnerSlot = UIView()
        spinnerSlot.addSubview(spinner)
        let stack = UIStackView(arrangedSubviews: [spinnerSlot, textSlot])
        stack.axis = .vertical
        stack.spacing = FeedbackSendingStatusView.spinnerSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.accessibilityContainerType = .semanticGroup
        stack.accessibilityIdentifier = "fst.settings.feedback.status"
        let container = statusView.contentContainer
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor), stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor), stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spinner.topAnchor.constraint(equalTo: spinnerSlot.topAnchor), spinner.bottomAnchor.constraint(equalTo: spinnerSlot.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: spinnerSlot.centerXAnchor),
        ])
        statusView.alpha = 0
    }

    /// Lay out both stages in the same slot so the spinner keeps its frame when the text swaps.
    /// The slot fits the tallest stage without stretching the shorter stage's text.
    private func buildStage(_ stage: FeedbackSendingStage, in stack: UIStackView, slot: UIView) {
        let title = UKStateTitleLabel(stage.title(for: kind))
        title.accessibilityIdentifier = "fst.settings.feedback.status.title"
        stack.addArrangedSubview(title)
        if let subtitle = stage.subtitle(for: kind) {
            let label = UKStateSubtitleLabel(subtitle)
            label.accessibilityIdentifier = "fst.settings.feedback.status.subtitle"
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        } else {
            stack.addArrangedSubview(progressBar)
            stack.addArrangedSubview(stopButton)
            NSLayoutConstraint.activate([
                progressBar.widthAnchor.constraint(lessThanOrEqualToConstant: FeedbackSendingStatusView.barMaxWidth),
                progressBar.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
                progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor).withPriority(.defaultHigh),
                stopButton.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            ])
        }
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = UKEmptyStateView.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alpha = 0
        slot.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            stack.topAnchor.constraint(equalTo: slot.topAnchor),
            slot.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor),
            slot.bottomAnchor.constraint(equalTo: stack.bottomAnchor).withPriority(.fittingSizeLevel),
            title.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
    }

    /// Apply the same interruptible fade plan as the SwiftUI feedback form.
    private func setStatusTarget(_ target: FeedbackSendingChoreography.Target) {
        guard target != sendingTarget else { return }
        sendingTarget = target
        if case .status = target { view.endEditing(true) }
        sendingSequence?.cancel()
        settleSendingAnimator(at: .current)
        let steps = FeedbackSendingChoreography.plan(from: sending, to: target, reduceMotion: UKAccessibility.reduceMotion)
        sendingSequence = FeedbackSendingChoreography.run(steps) { [weak self] step in
            self?.applySendingStep(step)
        }
    }

    private func settleSendingAnimator(at position: UIViewAnimatingPosition) {
        if let animator = sendingAnimator, animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: position)
        }
        sendingAnimator = nil
    }

    private func applySendingStep(_ step: FeedbackSendingChoreography.Step) {
        settleSendingAnimator(at: .end)
        sending = step.presentation
        formHolder.isHidden = !sending.mountsForm
        formHolder.accessibilityElementsHidden = !sending.showsForm
        formHolder.isUserInteractionEnabled = sending.showsForm
        statusView.isHidden = sending.stage == nil
        statusView.accessibilityElementsHidden = !sending.showsStatus
        statusView.isUserInteractionEnabled = sending.showsStatus
        for (stage, stack) in [(FeedbackSendingStage.uploading, uploadingStatus), (.filing, filingStatus)] {
            stack.isHidden = sending.stage != stage
            stack.accessibilityElementsHidden = !sending.showsText || sending.stage != stage
        }
        let changes = { [self] in
            formHolder.alpha = sending.showsForm ? 1 : 0
            statusView.alpha = sending.showsStatus ? 1 : 0
            uploadingStatus.alpha = sending.showsText && sending.stage == .uploading ? 1 : 0
            filingStatus.alpha = sending.showsText && sending.stage == .filing ? 1 : 0
        }
        if let fade = step.fade {
            let ease = FeedbackSendingChoreography.ease
            let animator = UIViewPropertyAnimator(
                duration: fade, controlPoint1: CGPoint(x: ease.x1, y: ease.y1),
                controlPoint2: CGPoint(x: ease.x2, y: ease.y2)
            )
            sendingAnimator = animator
            animator.addAnimations(changes)
            animator.startAnimation()
        } else {
            UIView.performWithoutAnimation(changes)
        }
        if step.announces, let stage = sending.stage {
            UIAccessibility.post(notification: .announcement, argument: stage.title(for: kind))
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
        if busyNow { mediaDrop.ended() }
        if submitItem.isEnabled != canSubmit { submitItem.isEnabled = canSubmit }
        closeItem.title = filing ? "Close" : "Cancel"
        let modal = model.isSubmitting || (unsaved && !filing)
        if navigationController?.isModalInPresentation != modal { navigationController?.isModalInPresentation = modal }
        validation.text = (!busyNow ? issue?.message : nil)
        validationSection.isHidden = validation.text == nil
        attachMessage.text = message
        let canAttach = attachments.count < FeedbackLimits.attachments && !busyNow
        if attachMenuButton.isEnabled != canAttach { attachMenuButton.isEnabled = canAttach }
        for (box, _) in textViews where box.isEditable == busyNow { box.isEditable = !busyNow }
        if titleField.isEnabled == busyNow { titleField.isEnabled = !busyNow }
        updateStrip(attachments)
        updateMediaRows(hasAttachments: !attachments.isEmpty, importing: importing > 0, hasMessage: message != nil)
        library?.synchronizeAttachments(Set(attachments.map(\.id)))
        var fraction = 0.0
        if case let .submitting(value) = phase { fraction = value }
        progressBar.progress = Float(fraction)
        if let target = FeedbackSendingStage.target(for: phase, hasMedia: !attachments.isEmpty) {
            setStatusTarget(target)
        }
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
    }

    private func tile(_ attachment: FeedbackAttachment, position: Int) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let open = UIButton(type: .custom)
        open.translatesAutoresizingMaskIntoConstraints = false
        open.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        open.layer.cornerRadius = 12
        open.layer.cornerCurve = .continuous
        open.layer.borderWidth = 1
        open.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        open.clipsToBounds = true
        open.setImage(UIImage(systemName: attachment.isVideo ? "film" : "photo"), for: .normal)
        open.tintColor = BrandUIColors.textPrimary
        open.accessibilityLabel = attachment.accessibilityLabel(position: position)
        open.accessibilityHint = "Opens in Quick Look"
        open.accessibilityIdentifier = "fst.settings.feedback.attachment.\(position)"
        open.addAction(UIAction { [weak self] _ in self?.preview(position - 1) }, for: .touchUpInside)
        let remove = UIButton(type: .custom)
        remove.translatesAutoresizingMaskIntoConstraints = false
        let mark = UIImage.SymbolConfiguration(font: UKFont.font(.title3)).applying(
            UIImage.SymbolConfiguration(paletteColors: [.white, .black.withAlphaComponent(0.7)])
        )
        remove.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: mark), for: .normal)
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
        holder.accessibilityElements = [open, remove]
        Task { [weak open] in
            let request = QLThumbnailGenerator.Request(
                fileAt: attachment.fileURL, size: CGSize(width: 76, height: 76), scale: UIScreen.main.scale, representationTypes: .thumbnail
            )
            if let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage {
                open?.contentHorizontalAlignment = .fill
                open?.contentVerticalAlignment = .fill
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
        cancelMediaImports()
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

    private var photoLibraryPlacement: FeedbackPhotoLibraryPlacement {
        .resolve(isMac: false, windowWidthClass: ukWindowLayout.windowWidthClass)
    }

    private func showLibrary(_ show: Bool) {
        guard show != formPanes.showsTrailingContent else { return }
        if show, library == nil {
            let controller = UKFeedbackPhotoLibrary(model: model) { [weak self] in self?.showLibrary(false) }
            addChild(controller)
            let pane = formPanes.trailingContent
            let child = controller.view!
            child.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            controller.didMove(toParent: self)
            library = controller
        }
        formPanes.showsTrailingContent = show
        updateAttachMenu()
    }

    private func cancelMediaImports() {
        mediaImports.values.forEach { $0.cancel() }
        mediaImports.removeAll()
        library?.cancelImports()
    }

    private func pickPhotos() {
        if photoLibraryPlacement == .beside {
            showLibrary(!formPanes.showsTrailingContent)
            return
        }
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
        importMedia(results.map(\.itemProvider))
    }

    /// Stage the provider copies in order for each picker selection or drop.
    private func importMedia(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        let id = UUID()
        mediaImports[id] = Task { [weak self, model] in
            defer { self?.mediaImports[id] = nil }
            for provider in providers {
                guard !Task.isCancelled else { return }
                _ = await model.importPhoto(provider)
            }
        }
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

    // MARK: Media drop

    /// Accept media across the sheet, including over native text controls.
    private func installMediaDrop() {
        (navigationController?.view ?? view).addInteraction(UIDropInteraction(delegate: mediaDrop))
        titleField.textDropDelegate = mediaDrop
        textViews.forEach { $0.0.textDropDelegate = mediaDrop }
        dropHighlight.translatesAutoresizingMaskIntoConstraints = false
        dropHighlight.isHidden = true
        dropHighlight.isUserInteractionEnabled = false
        dropHighlight.accessibilityElementsHidden = true
        dropHighlight.accessibilityIdentifier = "fst.settings.feedback.drop"
        dropHighlight.backgroundColor = BrandUIColors.accentBlue.withAlphaComponent(FeedbackDropAppearance.fillOpacity)
        dropHighlight.layer.borderColor = BrandUIColors.accentBlue.cgColor
        dropHighlight.layer.borderWidth = FeedbackDropAppearance.borderWidth
        dropHighlight.layer.cornerRadius = FeedbackDropAppearance.cornerRadius
        dropHighlight.layer.cornerCurve = .continuous
        var configuration = UIButton.Configuration.filled()
        configuration.title = FeedbackDropAppearance.title
        configuration.image = UIImage(systemName: "paperclip")
        configuration.imagePadding = 6
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = BrandUIColors.accentBlue
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.font(.headline)
            return attributes
        }
        let caption = UIButton(configuration: configuration)
        caption.titleLabel?.adjustsFontForContentSizeCategory = true
        caption.titleLabel?.numberOfLines = 0
        caption.translatesAutoresizingMaskIntoConstraints = false
        dropHighlight.addSubview(caption)
        view.addSubview(dropHighlight)
        let area = view.safeAreaLayoutGuide
        let inset = FeedbackDropAppearance.inset
        NSLayoutConstraint.activate([
            dropHighlight.leadingAnchor.constraint(equalTo: area.leadingAnchor, constant: inset),
            dropHighlight.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -inset),
            dropHighlight.topAnchor.constraint(equalTo: area.topAnchor, constant: inset),
            dropHighlight.bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -inset),
            caption.centerXAnchor.constraint(equalTo: dropHighlight.centerXAnchor),
            caption.centerYAnchor.constraint(equalTo: dropHighlight.centerYAnchor),
            caption.widthAnchor.constraint(lessThanOrEqualTo: dropHighlight.widthAnchor, constant: -16),
        ])
        #if DEBUG
        if ProcessInfo.processInfo.environment["FST_UI_TEST_DROP_MARKER"] == "1" {
            let marker = UIView(frame: CGRect(x: 4, y: 4, width: 1, height: 1))
            marker.isAccessibilityElement = true
            marker.accessibilityLabel = "Drop highlights shown"
            marker.accessibilityValue = "0"
            marker.accessibilityIdentifier = "fst.settings.feedback.drop.shown"
            view.addSubview(marker)
            dropMarker = marker
        }
        #endif
    }

    private func showDropHighlight(_ targeted: Bool) {
        let show = targeted && model.acceptsMedia
        guard dropHighlight.isHidden == show else { return }
        dropHighlight.isHidden = !show
        #if DEBUG
        if show, let dropMarker {
            dropHighlights += 1
            dropMarker.accessibilityValue = String(dropHighlights)
        }
        #endif
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
