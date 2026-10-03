import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FestivalCore
import FestivalDesign
#if os(iOS)
import UIKit
#endif

// MARK: - Sheet

/// Report an Issue / Request a Feature form (issue #78, `.agents/controls/feedback-form/`).
///
/// A scoped task in a sheet with Cancel (leading) and Submit (trailing) rather than the
/// app's usual top-right Close, because closing can lose typed input.
/// HIG (Sheets): "Single-view sheets: Cancel on the top toolbar's leading edge; Done, when
/// present, trailing." HIG (Modality): "If either a dismiss gesture or button could lose
/// user-generated content, get confirmation before closing". Each box keeps a visible
/// subtitle, since HIG (Text fields) notes placeholder text "disappears on typing, so a
/// separate label can also help".
struct FeedbackFormSheet: View {
    private let kind: FeedbackKind
    private let session: FestivalSession
    @State private var model: FeedbackFormModel
    @State private var confirmingDiscard = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deviceLayout) private var layout

    /// Create an empty form.
    ///
    /// - Parameters:
    ///   - kind: Bug report or feature request.
    ///   - session: Service session used only when Submit is pressed.
    init(kind: FeedbackKind, session: FestivalSession) {
        self.kind = kind
        self.session = session
        _model = State(initialValue: FeedbackFormModel(kind: kind))
    }

    var body: some View {
        NavigationStack {
            form
                // Fade under the header like every `FestivalModal` (#94).
                .modifier(ModalTopEdgeFadeModifier())
                .navigationTitle(kind.formTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
        // Once the service has the report (filing), closing loses nothing.
        .interactiveDismissDisabled(
            model.isSubmitting || (model.hasUnsavedInput && !model.isFiling)
        )

        #if os(iOS)
        .background(SheetDismissAttemptObserver { requestClose() })
        #endif
        .photosPicker(
            isPresented: $showingPhotos, selection: $photoSelection,
            maxSelectionCount: max(1, FeedbackLimits.attachments - model.attachments.count),
            matching: .any(of: [.images, .videos]), preferredItemEncoding: .current
        )
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await model.importPhotos(items) }
        }
        .fileImporter(
            isPresented: $showingFiles, allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            Task { await model.importFiles(result) }
        }
        .alert(successTitle, isPresented: finishedBinding, presenting: outcome) { _ in
            Button("Done", role: .cancel, action: close)
                .accessibilityIdentifier("fst.settings.feedback.done")
        } message: { outcome in
            Text(successMessage(outcome))
        }
        .alert("Couldn't Send", isPresented: failedBinding) {
            Button("OK", role: .cancel) { model.acknowledgeFailure() }
        } message: {
            Text(failureMessage)
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                TextField("Title", text: $model.title)
                    .accessibilityLabel("Title")
                    .accessibilityHint(titleDetail)
                    .accessibilityIdentifier("fst.settings.feedback.field.title")
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            } header: {
                FeedbackFieldHeader("Title", detail: titleDetail)
            }
            textBox(
                "Description", detail: descriptionDetail,
                text: $model.descriptionText, identifier: "fst.settings.feedback.field.description"
            )
            if kind.includesReproduction {
                textBox(
                    "Steps to Reproduce",
                    detail: "List the steps that make it happen, one per line.",
                    text: $model.reproSteps, identifier: "fst.settings.feedback.field.repro"
                )
                textBox(
                    "Expected Behavior", detail: "What did you expect to happen instead?",
                    text: $model.expectedBehavior, identifier: "fst.settings.feedback.field.expected"
                )
            }
            mediaSection
            if model.isBusy {
                progressSection
            } else if let issue = model.draft.validationIssue {
                Section {
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(FestivalText.primary)
                        .accessibilityIdentifier("fst.settings.feedback.validation")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func textBox(
        _ label: String, detail: String, text: Binding<String>, identifier: String
    ) -> some View {
        Section {
            TextEditor(text: text)
                .frame(minHeight: 96)
                .accessibilityLabel(label)
                .accessibilityHint(detail)
                .accessibilityIdentifier(identifier)
                .disabled(model.isBusy)
        } header: {
            FeedbackFieldHeader(label, detail: detail)
        }
    }

    private var mediaSection: some View {
        Section {
            if !model.attachments.isEmpty {
                FeedbackAttachmentStrip(attachments: model.attachments) { model.remove($0) }
                    .disabled(model.isBusy)
            }
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotos = true }
                    .accessibilityIdentifier("fst.settings.feedback.attach.media")
                Button("Choose File…", systemImage: "folder") { showingFiles = true }
                    .accessibilityIdentifier("fst.settings.feedback.attach.files")
            } label: {
                // The whole row is the hit target, not only the label's glyphs.
                Label("Attach Media", systemImage: "paperclip")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(
                model.attachments.count >= FeedbackLimits.attachments || model.isBusy
            )
            .accessibilityIdentifier("fst.settings.feedback.attach")
            if model.importing > 0 {
                ProgressView("Adding media…")
                    .accessibilityIdentifier("fst.settings.feedback.attach.progress")
            }
            if let message = model.attachmentMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(FestivalSheetActionColor.destructive)
                    .accessibilityIdentifier("fst.settings.feedback.attachments.notice")
            }
        } header: {
            FeedbackFieldHeader(
                "Media",
                detail: "Optional screenshots or screen recordings: up to "
                    + "\(FeedbackLimits.attachments) photos or videos, "
                    + ByteCountFormatter.string(
                        fromByteCount: FeedbackLimits.totalAttachmentBytes, countStyle: .file
                    ) + " in total."
            )
        }
    }

    private var progressSection: some View {
        Section {
            if model.isFiling {
                // Indeterminate: the service is filing the issue and processing media.
                ProgressView {
                    Text("Filing your \(kind == .bug ? "report" : "request")…")
                }
                .accessibilityIdentifier("fst.settings.feedback.progress")
                Text("It's been received. You can close this; it will still be filed.")
                    .font(.footnote)
                    .foregroundStyle(FestivalText.primary)
            } else {
                ProgressView(value: progress) {
                    Text(model.attachments.isEmpty ? "Sending…" : "Uploading media…")
                }
                .accessibilityIdentifier("fst.settings.feedback.progress")
                Button("Stop Sending", role: .destructive) { model.cancelSubmit() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("fst.settings.feedback.stop")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(model.isFiling ? "Close" : "Cancel", action: requestClose)
                .accessibilityIdentifier("fst.settings.feedback.close")
                // Anchored to Cancel so iOS 26's popover-style dialog points at it.
                .confirmationDialog(
                    discardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible
                ) {
                    Button("Discard Changes", role: .destructive, action: close)
                        .accessibilityIdentifier("fst.settings.feedback.discard.confirm")
                    Button("Keep Editing", role: .cancel) {}
                        .accessibilityIdentifier("fst.settings.feedback.discard.cancel")
                } message: {
                    Text("Your text and attached media will be lost.")
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Submit") {
                model.submit(session: session, platform: platform)
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("fst.settings.feedback.submit")
        }
    }

    // MARK: - Actions

    /// Cancel, Escape or a swipe: confirm first when something would be lost. While the
    /// service files an accepted report nothing can be lost, so it closes at once.
    private func requestClose() {
        if model.isFiling {
            close()
        } else if model.hasUnsavedInput || model.isSubmitting {
            confirmingDiscard = true
        } else {
            close()
        }
    }

    private func close() {
        model.discardMedia()
        dismiss()
    }

    private var platform: FeedbackPlatform {
        #if os(macOS)
        FeedbackPlatform.resolve(isMac: true, isPad: false, hasHinge: false)
        #else
        FeedbackPlatform.resolve(
            isMac: false, isPad: UIDevice.current.userInterfaceIdiom == .pad,
            hasHinge: layout.pose != .standard
        )
        #endif
    }

    // MARK: - Text

    private var titleDetail: String {
        "Keep the \(kind.titlePrefix.trimmingCharacters(in: .whitespaces)) prefix and "
            + (kind == .bug ? "sum up the problem in a few words." : "name the idea in a few words.")
    }

    private var descriptionDetail: String {
        kind == .bug
            ? "What went wrong? Say which page you were on and what you saw."
            : "Describe the feature and how it would help you."
    }

    private var discardTitle: String {
        kind == .bug ? "Discard this report?" : "Discard this request?"
    }

    private var successTitle: String {
        kind == .bug ? "Report Sent" : "Request Sent"
    }

    private func successMessage(_ outcome: FeedbackFormModel.Outcome) -> String {
        switch outcome {
        case let .filed(number, skipped):
            var text = number.map { "Thank you! It was filed as issue #\($0)." }
                ?? "Thank you! It has been filed."
            if skipped > 0 {
                text += skipped == 1
                    ? " 1 attachment couldn't be included."
                    : " \(skipped) attachments couldn't be included."
            }
            return text
        case .received:
            return "Thank you! It was received and will be filed shortly."
        }
    }

    private var progress: Double {
        if case let .submitting(fraction) = model.phase { return fraction }
        return 0
    }

    private var outcome: FeedbackFormModel.Outcome? {
        if case let .finished(outcome) = model.phase { return outcome }
        return nil
    }

    private var finishedBinding: Binding<Bool> {
        Binding(get: { outcome != nil }, set: { _ in })
    }

    private var failureMessage: String {
        if case let .failed(message) = model.phase { return message }
        return ""
    }

    private var failedBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = model.phase { true } else { false } },
            set: { if !$0 { model.acknowledgeFailure() } }
        )
    }
}

// MARK: - Field header

/// A box's name with a visible line explaining what to write.
private struct FeedbackFieldHeader: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(FestivalText.primary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Swipe-to-dismiss attempt (iOS)

#if os(iOS)
/// Shows the discard confirmation when someone swipes down a sheet whose dismissal is
/// disabled because it holds unsaved input. HIG (Sheets): "If changes are unsaved when
/// swiping begins, confirm with an action sheet." SwiftUI has no public hook for the
/// attempt, so this wraps the presentation controller's delegate and forwards every other
/// call to SwiftUI's own delegate unchanged.
private struct SheetDismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(onAttempt: onAttempt)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.proxy.onAttempt = onAttempt
        controller.install()
    }

    final class Controller: UIViewController {
        let proxy: DelegateProxy

        init(onAttempt: @escaping () -> Void) {
            proxy = DelegateProxy(onAttempt: onAttempt)
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        /// Insert the proxy on the presented root's presentation controller, once.
        func install() {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil,
                  let presentation = root.presentationController,
                  presentation.delegate !== proxy
            else { return }
            proxy.original = presentation.delegate
            presentation.delegate = proxy
        }
    }

    final class DelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void
        nonisolated(unsafe) weak var original: (any UIAdaptivePresentationControllerDelegate)?

        init(onAttempt: @escaping () -> Void) {
            self.onAttempt = onAttempt
        }

        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(controller)
            onAttempt()
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
