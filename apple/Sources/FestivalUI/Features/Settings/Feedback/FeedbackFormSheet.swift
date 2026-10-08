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
///
/// Photos, videos and image or movie files dropped anywhere on the form attach to it, and
/// at regular width on iPad and the iPhone Duo inner display Photo Library opens in a pane
/// beside the form rather than over it (issue #373, ``FeedbackPhotoLibraryPlacement``).
/// HIG (Entering data): "As much as possible, support drag and drop and paste."
struct FeedbackFormSheet: View {
    private let kind: FeedbackKind
    private let session: FestivalSession
    @State private var model: FeedbackFormModel
    @State private var confirmingDiscard = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var photoSelection: [PhotosPickerItem] = []
    /// The beside-the-form library is open (regular-width iPad and Duo only).
    @State private var showingLibraryPane = false
    /// Items ticked in the beside-the-form library, mirrored into ``model``'s attachments.
    @State private var librarySelection: [PhotosPickerItem] = []
    @State private var libraryLinks = FeedbackPickerLinks<PhotosPickerItem>()
    /// How many drop targets (the sheet, each form row and header) the drag is over.
    @State private var dropTargets = 0
    /// How many times the drop highlight has appeared (Debug UI-test marker only).
    @State private var dropHighlights = 0
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
            panes
                .overlay {
                    if dropTargets > 0 && model.acceptsMedia {
                        FeedbackDropHighlight()
                            .onAppear { dropHighlights += 1 }
                    }
                }
                .overlay(alignment: .topLeading) { dropMarker }
                .modifier(dropTarget)
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
        .background(
            FeedbackSheetDropInteraction(accepts: model.acceptsMedia) { over in
                dropTargets = over ? 1 : 0
            } onDrop: { providers in
                importDropped(providers)
            }
        )
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
        .onChange(of: librarySelection) { old, new in syncLibrarySelection(from: old, to: new) }
        .onChange(of: model.attachments.map(\.id)) { _, ids in
            // Attachments discarded or removed elsewhere untick their library items.
            let stale = libraryLinks.prune(keeping: Set(ids))
            if !stale.isEmpty { librarySelection.removeAll { stale.contains($0) } }
        }
        .onChange(of: photoLibraryPlacement) { _, placement in
            if placement == .presented { showingLibraryPane = false }
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
        // Page-sized at regular width on iPad and Duo so the library fits beside the form.
        .festivalSheet(.large, sizing: .regularPage)
    }

    // MARK: - Panes

    /// The form alone, or the form and the photo library side by side (issue #373), through
    /// the canonical hinge-aware row: they meet at a partially folded Duo's fold and divide
    /// the sheet at its midpoint otherwise (pattern `hinge-columns` R1, R7).
    private var panes: some View {
        FeedbackFormPanes(showsLibrary: libraryPaneVisible) {
            form
                // Fade under the header like every `FestivalModal` (#94).
                .modifier(ModalTopEdgeFadeModifier())
        } library: {
            libraryPane
        }
    }

    /// The system photo picker shown inline beside the form. Ticking a photo attaches it,
    /// unticking removes it; it runs out of process, so no library permission is needed.
    /// `photoLibrary: .shared()` only gives the picked items identifiers, so the form can
    /// untick a photo whose attachment was removed.
    private var libraryPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Photo Library")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button("Hide") { showingLibraryPane = false }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Hide Photo Library")
                    .accessibilityIdentifier("fst.settings.feedback.library.hide")
            }
            .padding(.horizontal, 16)
            PhotosPicker(
                selection: $librarySelection, maxSelectionCount: FeedbackLimits.attachments,
                selectionBehavior: .continuousAndOrdered, matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current, photoLibrary: .shared()
            ) {
                Text("Photo Library")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .disabled(!model.acceptsMedia)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.settings.feedback.library")
    }

    /// Debug UI-test marker (`FST_UI_TEST_DROP_MARKER=1` only): a drop journey's long
    /// press blocks XCUITest until the drop, so it cannot see the highlight while it shows.
    /// The count of highlights shown persists instead, like `fst.publication.announced`.
    @ViewBuilder
    private var dropMarker: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FST_UI_TEST_DROP_MARKER"] == "1" {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("Drop highlights shown")
                .accessibilityValue(String(dropHighlights))
                .accessibilityIdentifier("fst.settings.feedback.drop.shown")
        }
        #endif
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
                    .modifier(dropTarget)
            } header: {
                FeedbackFieldHeader("Title", detail: titleDetail)
                    .modifier(dropTarget)
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
                        .modifier(dropTarget)
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
                .modifier(dropTarget)
        } header: {
            FeedbackFieldHeader(label, detail: detail)
                .modifier(dropTarget)
        }
    }

    private var mediaSection: some View {
        Section {
            Group { mediaRows }
                .modifier(dropTarget)
        } header: {
            FeedbackFieldHeader("Media", detail: mediaDetail)
                .modifier(dropTarget)
        }
    }

    @ViewBuilder
    private var mediaRows: some View {
        if !model.attachments.isEmpty {
            FeedbackAttachmentStrip(attachments: model.attachments) { removeAttachment($0) }
                .disabled(model.isBusy)
        }
        Menu {
            Button(
                libraryMenuTitle, systemImage: "photo.on.rectangle", action: openPhotoLibrary
            )
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
    }

    /// Accepts dropped media on the view it modifies. The sheet has one, but `Form` is a
    /// collection view whose own drop handling claims drags over its rows and headers, so
    /// each of those carries one too (found in an iPad drive, #373).
    private var dropTarget: FeedbackDropTarget {
        FeedbackDropTarget(accepts: model.acceptsMedia, targets: $dropTargets) { providers in
            importDropped(providers)
        }
    }

    /// Copy dropped item providers' media and attach it.
    ///
    /// - Parameter providers: The dropped items.
    private func importDropped(_ providers: [NSItemProvider]) {
        Task { await model.importDropped(await FeedbackPickedMedia.load(from: providers)) }
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

    /// Photo Library from Attach Media: the pane beside the form where there is room,
    /// otherwise the system picker over it.
    private func openPhotoLibrary() {
        switch photoLibraryPlacement {
        case .beside: showingLibraryPane.toggle()
        case .presented: showingPhotos = true
        }
    }

    /// Remove an attachment from the form, unticking it in the library pane.
    private func removeAttachment(_ attachment: FeedbackAttachment) {
        if let item = libraryLinks.unlink(attachmentID: attachment.id) {
            librarySelection.removeAll { $0 == item }
        }
        model.remove(attachment)
    }

    /// Mirror the library pane's ticks into attachments: newly ticked items are copied
    /// (a refused one is unticked again), unticked ones are removed.
    private func syncLibrarySelection(from old: [PhotosPickerItem], to new: [PhotosPickerItem]) {
        let changes = FeedbackPickerLinks<PhotosPickerItem>.changes(from: old, to: new)
        for item in changes.removed {
            if let id = libraryLinks.unlink(item) { model.remove(id: id) }
        }
        for item in changes.added {
            Task {
                guard let id = await model.importPhoto(item) else {
                    librarySelection.removeAll { $0 == item }
                    return
                }
                if librarySelection.contains(item) {
                    libraryLinks.link(item, to: id)
                } else {
                    // Unticked while it was still being copied.
                    model.remove(id: id)
                }
            }
        }
    }

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

    private var libraryPaneVisible: Bool {
        showingLibraryPane && photoLibraryPlacement == .beside
    }

    private var photoLibraryPlacement: FeedbackPhotoLibraryPlacement {
        #if os(macOS)
        FeedbackPhotoLibraryPlacement.resolve(isMac: true, windowWidthClass: layout.windowWidthClass)
        #else
        FeedbackPhotoLibraryPlacement.resolve(isMac: false, windowWidthClass: layout.windowWidthClass)
        #endif
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

    private var libraryMenuTitle: String {
        photoLibraryPlacement == .beside && showingLibraryPane
            ? "Hide Photo Library" : "Photo Library"
    }

    private var mediaDetail: String {
        "Optional screenshots or screen recordings: up to "
            + "\(FeedbackLimits.attachments) photos or videos, "
            + ByteCountFormatter.string(
                fromByteCount: FeedbackLimits.totalAttachmentBytes, countStyle: .file
            ) + " in total." + (platform == .ios ? "" : " You can also drag them here.")
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

// MARK: - Drop target

/// One place on the Mac feedback form that accepts dropped photos, videos and image or
/// movie files: the form and each row and header, so a text box's own drop handling
/// doesn't take a file dropped on it. Every target shares one counter, so moving between
/// rows keeps the highlight on whichever order the enter and exit callbacks arrive in.
/// On iOS it does nothing: ``FeedbackSheetDropInteraction`` covers the whole sheet.
private struct FeedbackDropTarget: ViewModifier {
    /// False while sending: the drop is refused.
    let accepts: Bool
    /// Targets the drag is over, shared by the whole form.
    @Binding var targets: Int
    /// Takes the dropped item providers.
    let onDrop: ([NSItemProvider]) -> Void
    @State private var isOver = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onDrop(of: FeedbackPickedMedia.droppableTypes, isTargeted: $isOver) { providers in
                guard accepts, !providers.isEmpty else { return false }
                onDrop(providers)
                return true
            }
            .onChange(of: isOver) { _, over in
                targets = max(0, targets + (over ? 1 : -1))
            }
        #else
        content
        #endif
    }
}

// MARK: - Drop highlight

/// Shows the form accepts what is being dragged over it. HIG (Drag and drop): "Show
/// whether a destination accepts the content, like an insertion point or highlight if it
/// can"; nothing is shown for content it can't take.
private struct FeedbackDropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(BrandTokens.accentBlue, lineWidth: 3)
            .background(
                BrandTokens.accentBlue.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .padding(6)
            .overlay {
                Label("Drop to Attach", systemImage: "paperclip")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BrandTokens.accentBlue, in: Capsule())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("fst.settings.feedback.drop")
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
