import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import FestivalCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Model

/// State behind a Report an Issue / Request a Feature sheet (issue #78).
///
/// Owns the draft, the app's private copies of attached media and the submit phase. Media
/// is copied into app temporary storage so the original stays untouched and Quick Look or
/// the default app can open it; ``discardMedia()`` deletes the copies.
@MainActor
@Observable
final class FeedbackFormModel {
    /// Where the submit is.
    enum Phase: Equatable {
        case editing
        /// Upload in flight; fraction of the body sent.
        case submitting(Double)
        case succeeded(FeedbackReceipt)
        case failed(String)
    }

    private(set) var draft: FeedbackDraft
    private(set) var attachments: [FeedbackAttachment] = []
    private(set) var phase: Phase = .editing
    /// Why the last picked file was refused, shown under Attach Media.
    private(set) var attachmentMessage: String?
    /// Picked items still being copied, so Submit waits for them.
    private(set) var importing = 0
    /// One key per form: a retried Submit cannot file the report twice.
    let idempotencyKey = UUID()

    @ObservationIgnored private var submitTask: Task<Void, Never>?

    /// Start an empty form.
    ///
    /// - Parameter kind: Bug report or feature request.
    init(kind: FeedbackKind) {
        draft = FeedbackDraft(kind: kind)
    }

    // MARK: - Draft

    /// Prefix-preserving title binding target.
    var title: String {
        get { draft.title }
        set { draft.setTitle(newValue) }
    }

    var descriptionText: String {
        get { draft.description }
        set { draft.description = newValue }
    }

    var reproSteps: String {
        get { draft.reproSteps }
        set { draft.reproSteps = newValue }
    }

    var expectedBehavior: String {
        get { draft.expectedBehavior }
        set { draft.expectedBehavior = newValue }
    }

    /// Whether closing would lose typed text or attached media.
    var hasUnsavedInput: Bool { draft.hasTypedInput || !attachments.isEmpty }

    var isSubmitting: Bool {
        if case .submitting = phase { return true }
        return false
    }

    /// Submit is enabled only for a valid draft with every picked item copied.
    var canSubmit: Bool { draft.validationIssue == nil && importing == 0 && !isSubmitting }

    // MARK: - Attachments

    /// Copy files chosen in the system file importer.
    ///
    /// - Parameter result: The importer's result; a failure is shown as a message.
    func importFiles(_ result: Result<[URL], any Error>) async {
        switch result {
        case let .success(urls):
            for url in urls { importFile(at: url) }
        case .failure:
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
        }
    }

    /// Copy photos and videos chosen in the system photo picker.
    ///
    /// - Parameter items: Picker selection; the picker needs no library permission.
    func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            importing += 1
            defer { importing -= 1 }
            do {
                guard let picked = try await item.loadTransferable(type: FeedbackPickedMedia.self)
                else {
                    attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
                    continue
                }
                admit(picked.url, displayName: picked.url.lastPathComponent)
            } catch {
                attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
            }
        }
    }

    /// Remove one attachment and its private copy.
    ///
    /// - Parameter attachment: Attachment to drop.
    func remove(_ attachment: FeedbackAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        Self.deleteCopy(attachment.fileURL)
        attachmentMessage = nil
    }

    /// Stop any upload and delete every private media copy (on dismiss).
    func discardMedia() {
        submitTask?.cancel()
        for attachment in attachments { Self.deleteCopy(attachment.fileURL) }
        attachments = []
    }

    private func importFile(at url: URL) {
        importing += 1
        defer { importing -= 1 }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let staged = try? FeedbackPickedMedia.stage(url) else {
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
            return
        }
        admit(staged.url, displayName: url.lastPathComponent)
    }

    /// Accept or refuse a staged copy against the type and size limits.
    private func admit(_ url: URL, displayName: String) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let media = FeedbackAttachmentPolicy.media(forFilename: url.lastPathComponent)
        let rejection: FeedbackAttachmentRejection?
        if media == nil {
            rejection = .unsupportedType(displayName)
        } else if let size {
            rejection = FeedbackAttachmentPolicy.rejection(
                byteCount: size, filename: displayName, existing: attachments
            )
        } else {
            rejection = .unreadable
        }
        guard rejection == nil, let media, let size else {
            attachmentMessage = rejection?.errorDescription
            Self.deleteCopy(url)
            return
        }
        attachmentMessage = nil
        attachments.append(FeedbackAttachment(
            fileURL: url, filename: displayName, mimeType: media.mimeType,
            byteCount: size, isVideo: media.isVideo
        ))
    }

    /// Each copy lives alone in a UUID folder; delete the folder.
    private static func deleteCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Submit

    /// Upload the report; progress, success and failure land in ``phase``.
    ///
    /// - Parameters:
    ///   - session: App service session (keyless public origin or loopback fixture).
    ///   - platform: Platform label the service applies to the issue.
    func submit(session: FestivalSession, platform: FeedbackPlatform) {
        guard canSubmit else { return }
        let submission = draft.submission(
            platform: platform,
            appVersion: AppBuildInfo.versionText(Bundle.main.infoDictionary),
            osVersion: Self.osVersion
        )
        let attachments = attachments
        let key = idempotencyKey
        phase = .submitting(0)
        let onProgress: @Sendable (Double) -> Void = { fraction in
            Task { @MainActor [weak self] in self?.reportProgress(fraction) }
        }
        submitTask = Task { [weak self] in
            let outcome: Phase
            do {
                let client = try session.client()
                let receipt = try await client.submitFeedback(
                    submission, attachments: attachments, idempotencyKey: key,
                    progress: onProgress
                )
                outcome = .succeeded(receipt)
            } catch is CancellationError {
                outcome = .editing
            } catch let error as FeedbackError {
                outcome = .failed(error.errorDescription ?? "")
            } catch {
                outcome = .failed(FeedbackError.network.errorDescription ?? "")
            }
            guard let self, self.isSubmitting else { return }
            self.phase = outcome
        }
    }

    /// Stop an upload in flight and go back to editing with everything kept.
    func cancelSubmit() {
        submitTask?.cancel()
        submitTask = nil
        phase = .editing
    }

    /// Return from an error to the editable form.
    func acknowledgeFailure() {
        if case .failed = phase { phase = .editing }
    }

    private func reportProgress(_ fraction: Double) {
        guard case let .submitting(current) = phase, fraction > current else { return }
        phase = .submitting(fraction)
    }

    /// "iOS 26.1", "iPadOS 26.1" or "macOS 26.1.0".
    static var osVersion: String {
        #if os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #endif
    }
}

// MARK: - Picker transfer

/// A photo or video copied into app temporary storage, from the system photo picker's
/// temporary file (before its import closure returns) or a file importer URL.
struct FeedbackPickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        // Movies first so a video arrives as its own file, not a still frame.
        FileRepresentation(importedContentType: .movie) { try stage($0.file) }
        FileRepresentation(importedContentType: .image) { try stage($0.file) }
    }

    /// Copy `file` into its own UUID folder, keeping a safe version of its name.
    ///
    /// - Parameter file: Readable source file.
    /// - Returns: The app-owned copy.
    /// - Throws: File system errors.
    static func stage(_ file: URL) throws -> FeedbackPickedMedia {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("fst-feedback-media", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(
            FeedbackAttachmentPolicy.sanitizedFilename(file.lastPathComponent)
        )
        try FileManager.default.copyItem(at: file, to: destination)
        return FeedbackPickedMedia(url: destination)
    }
}
