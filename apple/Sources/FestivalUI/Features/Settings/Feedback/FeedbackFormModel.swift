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
        /// The service accepted the report and is filing it; the app follows the job.
        case filing
        case finished(Outcome)
        case failed(String)
    }

    /// How a delivered report ended.
    enum Outcome: Equatable {
        /// Filed on GitHub; `skipped` attachments could not be fitted into the issue.
        case filed(issueNumber: Int?, skipped: Int)
        /// Accepted, but the app could not follow it to the end (no ID, a lost status
        /// read or the wait ran out). The service still files it.
        case received
    }

    private(set) var draft: FeedbackDraft
    private(set) var attachments: [FeedbackAttachment] = []
    private(set) var phase: Phase = .editing
    /// Why the last picked file was refused, shown under Attach Media.
    private(set) var attachmentMessage: String?
    /// Picked items still being copied, so Submit waits for them.
    private(set) var importing = 0
    @ObservationIgnored private var submitTask: Task<Void, Never>?
    /// Time between status reads while filing.
    @ObservationIgnored let pollInterval: Duration
    /// How long to follow a job before reporting it as received.
    @ObservationIgnored let pollTimeout: Duration

    /// Status reads that may fail in a row before the job is reported as received.
    static let pollFailureAllowance = 3

    /// Start an empty form.
    ///
    /// - Parameters:
    ///   - kind: Bug report or feature request.
    ///   - pollInterval: Time between status reads (2 s, as the other native apps).
    ///   - pollTimeout: Longest wait for the issue number (5 minutes).
    init(
        kind: FeedbackKind, pollInterval: Duration = .seconds(2),
        pollTimeout: Duration = .seconds(300)
    ) {
        draft = FeedbackDraft(kind: kind)
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
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

    /// The upload is in flight; stopping it keeps the form.
    var isSubmitting: Bool {
        if case .submitting = phase { return true }
        return false
    }

    /// The service has the report; closing now loses nothing.
    var isFiling: Bool { phase == .filing }

    /// Uploading or filing: the form is read-only.
    var isBusy: Bool { isSubmitting || isFiling }

    /// Submit is enabled only for a valid draft with every picked item copied.
    var canSubmit: Bool { draft.validationIssue == nil && importing == 0 && phase == .editing }

    // MARK: - Attachments

    /// Copy files chosen in the system file importer.
    ///
    /// - Parameter result: The importer's result; a failure is shown as a message.
    func importFiles(_ result: Result<[URL], any Error>) async {
        switch result {
        case let .success(urls):
            for url in urls { await importFile(at: url) }
        case .failure:
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
        }
    }

    /// Copy photos and videos chosen in the system photo picker.
    ///
    /// - Parameter items: Picker selection; the picker needs no library permission.
    func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items { await importPhoto(item) }
    }

    /// Copy one photo or video chosen in the system photo picker (presented or inline).
    ///
    /// - Parameter item: Picker item; the picker needs no library permission.
    /// - Returns: The new attachment's ID, or nil when it was refused (the reason is in
    ///   ``attachmentMessage``).
    @discardableResult
    func importPhoto(_ item: PhotosPickerItem) async -> UUID? {
        importing += 1
        defer { importing -= 1 }
        do {
            guard let picked = try await item.loadTransferable(type: FeedbackPickedMedia.self)
            else {
                attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
                return nil
            }
            return await admit(picked.url, displayName: picked.url.lastPathComponent)
        } catch {
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
            return nil
        }
    }

    /// Admit photos, videos or image/movie files dropped onto the form (issue #373).
    ///
    /// The drop has already copied each item into its own staging folder
    /// (``FeedbackPickedMedia/transferRepresentation``); every copy goes through the same
    /// location removal and limits as a picked file, so a drop past the limits shows the
    /// same notice.
    ///
    /// - Parameter items: Staged copies, in drop order.
    func importDropped(_ items: [FeedbackPickedMedia]) async {
        for item in items {
            importing += 1
            defer { importing -= 1 }
            await admit(item.url, displayName: item.url.lastPathComponent)
        }
    }

    /// Whether the form takes new media now (drops and the inline library): not while
    /// uploading or filing.
    var acceptsMedia: Bool { !isBusy }

    /// Remove one attachment and its private copy.
    ///
    /// - Parameter attachment: Attachment to drop.
    func remove(_ attachment: FeedbackAttachment) {
        remove(id: attachment.id)
    }

    /// Remove one attachment by ID and delete its private copy; unknown IDs are ignored.
    ///
    /// - Parameter id: Attachment to drop.
    func remove(id: UUID) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = attachments.remove(at: index)
        Self.deleteCopy(attachment.fileURL)
        attachmentMessage = nil
    }

    /// Stop any upload and delete every private media copy (on dismiss).
    func discardMedia() {
        submitTask?.cancel()
        for attachment in attachments { Self.deleteCopy(attachment.fileURL) }
        attachments = []
    }

    private func importFile(at url: URL) async {
        importing += 1
        defer { importing -= 1 }
        let staged: FeedbackPickedMedia
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            staged = try FeedbackPickedMedia.stage(url)
        } catch {
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
            return
        }
        await admit(staged.url, displayName: url.lastPathComponent)
    }

    /// Accept or refuse a staged copy against the type and size limits, after
    /// removing location metadata (the issue is public).
    @discardableResult
    private func admit(_ url: URL, displayName: String) async -> UUID? {
        let media = FeedbackAttachmentPolicy.media(forFilename: url.lastPathComponent)
        if let media {
            do {
                try await FeedbackLocationScrubber.scrub(url, isVideo: media.isVideo)
            } catch {
                let rejection: FeedbackAttachmentRejection =
                    error as? FeedbackLocationScrubber.Failure == .unreadable
                        ? .unreadable : .locationNotRemoved(displayName)
                attachmentMessage = rejection.errorDescription
                Self.deleteCopy(url)
                return nil
            }
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
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
            return nil
        }
        attachmentMessage = nil
        let attachment = FeedbackAttachment(
            fileURL: url, filename: displayName, mimeType: media.mimeType,
            byteCount: size, isVideo: media.isVideo
        )
        attachments.append(attachment)
        return attachment.id
    }

    /// Delete every staged media copy. Called when a feedback sheet goes away by any
    /// route, including a swipe while the service is filing (one form is open at a time).
    static func purgeStagedMedia() {
        try? FileManager.default.removeItem(at: FeedbackPickedMedia.stagingFolder)
    }

    /// Each copy lives alone in a UUID folder; delete the folder.
    private static func deleteCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Submit

    /// Upload the report, then follow the service's job until it is filed; progress,
    /// success and failure land in ``phase``.
    ///
    /// - Parameters:
    ///   - session: App service session (keyless public origin or loopback fixture).
    ///   - platform: Platform label the service applies to the issue.
    func submit(session: FestivalSession, platform: FeedbackPlatform) {
        guard canSubmit else { return }
        let submission = draft.submission(
            platform: platform,
            appVersion: AppBuildInfo.versionText(Bundle.main.infoDictionary),
            clientInfo: Self.clientInfo
        )
        let attachments = attachments
        phase = .submitting(0)
        let onProgress: @Sendable (Double) -> Void = { fraction in
            Task { @MainActor [weak self] in self?.reportProgress(fraction) }
        }
        let interval = pollInterval
        let timeout = pollTimeout
        submitTask = Task { [weak self] in
            let client: FestivalAPI
            let acceptance: FeedbackAcceptance
            do {
                client = try session.client()
                acceptance = try await client.submitFeedback(
                    submission, attachments: attachments, progress: onProgress
                )
            } catch is CancellationError {
                self?.finishUpload(.editing)
                return
            } catch let error as FeedbackError {
                self?.finishUpload(.failed(error.errorDescription ?? ""))
                return
            } catch {
                self?.finishUpload(.failed(FeedbackError.network.errorDescription ?? ""))
                return
            }
            guard let self, self.isSubmitting else { return }
            guard let id = acceptance.id else {
                self.phase = .finished(.received)
                return
            }
            self.phase = .filing
            let outcome = await Self.follow(
                id: id, client: client, interval: interval, timeout: timeout
            )
            guard !Task.isCancelled, self.isFiling else { return }
            self.phase = outcome
        }
    }

    /// Poll a queued job until it is submitted or failed, the reads keep failing or the
    /// wait runs out.
    ///
    /// - Parameters:
    ///   - id: Job ID.
    ///   - client: Service client.
    ///   - interval: Time between reads.
    ///   - timeout: Longest wait.
    /// - Returns: `.finished(.filed)`, `.failed` for a failed job, else `.finished(.received)`.
    static func follow(
        id: String, client: FestivalAPI, interval: Duration, timeout: Duration
    ) async -> Phase {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var failures = 0
        while !Task.isCancelled {
            do {
                let status = try await client.feedbackStatus(id: id)
                failures = 0
                switch status.status {
                case .submitted:
                    return .finished(.filed(
                        issueNumber: status.issueNumber, skipped: status.skippedAttachments
                    ))
                case .failed:
                    return .failed(FeedbackError.filingFailed.errorDescription ?? "")
                case .queued, .processing:
                    break
                }
            } catch FestivalAPIError.httpStatus(404) {
                return .finished(.received)
            } catch {
                failures += 1
                if failures >= pollFailureAllowance { return .finished(.received) }
            }
            guard clock.now.advanced(by: interval) < deadline else { break }
            do { try await Task.sleep(for: interval) } catch { break }
        }
        return .finished(.received)
    }

    private func finishUpload(_ outcome: Phase) {
        guard isSubmitting else { return }
        phase = outcome
    }

    /// Stop an upload in flight and go back to editing with everything kept.
    func cancelSubmit() {
        guard isSubmitting else { return }
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

    /// Operating system and device for the issue, for example "iOS 26.1; iPhone".
    static var clientInfo: String {
        #if os(macOS)
        return "\(osVersion); Mac"
        #else
        return "\(osVersion); \(UIDevice.current.model)"
        #endif
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

    /// Parent of every staged copy, inside the app's temporary directory.
    static let stagingFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("fst-feedback-media", isDirectory: true)

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
        let folder = stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(
            FeedbackAttachmentPolicy.sanitizedFilename(file.lastPathComponent)
        )
        try FileManager.default.copyItem(at: file, to: destination)
        return FeedbackPickedMedia(url: destination)
    }
}
