import Foundation
import UniformTypeIdentifiers

// MARK: - Kind and platform

/// Which in-app feedback form is open (Settings → App Settings, issue #78).
public enum FeedbackKind: String, Sendable, Codable, CaseIterable, Identifiable {
    /// "Report an Issue": title, description, repro steps and expected behavior.
    case bug
    /// "Request a Feature": title and description.
    case feature

    public var id: String { rawValue }

    /// Title prefix the form pre-fills and keeps, including its trailing space.
    public var titlePrefix: String {
        switch self {
        case .bug: "[Bug] "
        case .feature: "[Feature] "
        }
    }

    /// The Settings row and sheet title.
    public var formTitle: String {
        switch self {
        case .bug: "Report an Issue"
        case .feature: "Request a Feature"
        }
    }

    /// Whether the form shows the Steps to Reproduce and Expected Behavior boxes.
    public var includesReproduction: Bool { self == .bug }
}

/// The platform label the service applies to the created GitHub issue.
public enum FeedbackPlatform: String, Sendable, Codable, CaseIterable {
    case ios
    case ipados
    case iphoneDuo = "iphone-duo"
    case macos

    /// Resolve the submitting surface.
    ///
    /// - Parameters:
    ///   - isMac: True in the native macOS app.
    ///   - isPad: True when the iOS app runs with the iPad idiom.
    ///   - hasHinge: True when the device reports a hinge (iPhone Duo).
    /// - Returns: `macos`, `iphone-duo`, `ipados` or `ios`, in that precedence.
    public static func resolve(isMac: Bool, isPad: Bool, hasHinge: Bool) -> FeedbackPlatform {
        if isMac { return .macos }
        if hasHinge { return .iphoneDuo }
        if isPad { return .ipados }
        return .ios
    }
}

// MARK: - Limits

/// Client-side bounds matching the service's `POST /api/feedback` validation
/// (`FeedbackSubmissionValidator`, `FeedbackOptions`). Text lengths are counted in UTF-16
/// code units, as the service's .NET `string.Length` does.
public enum FeedbackLimits {
    /// Title, prefix included.
    public static let titleCharacters = 200
    /// Per text box (Description, Steps to Reproduce, Expected Behavior).
    public static let bodyCharacters = 10_000
    /// `appVersion` form field.
    public static let appVersionCharacters = 64
    /// `clientInfo` form field.
    public static let clientInfoCharacters = 256
    /// Attachments per submission.
    public static let attachments = 4
    /// Bytes across all attached files (90 MB, decimal as the system formats file sizes).
    /// The service refuses a whole request over 90 MiB (94,371,840 bytes); this leaves room
    /// for the text fields and multipart framing.
    public static let totalAttachmentBytes: Int64 = 90_000_000
    /// Bytes per attached file: one file may use the whole allowance.
    public static let attachmentBytes: Int64 = totalAttachmentBytes
}

// MARK: - Draft

/// The editable form state, with the title prefix rule and submit validation.
public struct FeedbackDraft: Sendable, Equatable {
    public let kind: FeedbackKind
    /// Always starts with ``FeedbackKind/titlePrefix``; set through ``setTitle(_:)``.
    public private(set) var title: String
    public var description: String = ""
    public var reproSteps: String = ""
    public var expectedBehavior: String = ""

    /// A blank form with the prefix pre-filled.
    ///
    /// - Parameter kind: Bug report or feature request.
    public init(kind: FeedbackKind) {
        self.kind = kind
        title = kind.titlePrefix
    }

    /// Store an edited title, keeping the prefix the person cannot remove.
    ///
    /// - Parameter raw: The text field's new value.
    public mutating func setTitle(_ raw: String) {
        title = Self.prefixedTitle(raw, kind: kind)
    }

    /// Re-apply the prefix to an edited title.
    ///
    /// Deleting into the prefix restores it; text typed over a selected prefix is kept
    /// after it; a prefix typed without its space gains one.
    ///
    /// - Parameters:
    ///   - raw: Edited title text.
    ///   - kind: Form whose prefix applies.
    /// - Returns: `prefix + remainder`, the remainder with leading whitespace trimmed.
    public static func prefixedTitle(_ raw: String, kind: FeedbackKind) -> String {
        let prefix = kind.titlePrefix
        if raw.hasPrefix(prefix) { return raw }
        let bare = prefix.trimmingCharacters(in: .whitespaces)
        let remainder: Substring
        if raw.hasPrefix(bare) {
            remainder = raw.dropFirst(bare.count)
        } else if prefix.hasPrefix(raw) {
            remainder = ""
        } else {
            remainder = Substring(raw)
        }
        return prefix + remainder.drop(while: \.isWhitespace)
    }

    /// The title without its prefix, trimmed.
    public var titleBody: String {
        String(title.dropFirst(kind.titlePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether dismissing would lose anything the person entered (title beyond the prefix
    /// or any box), so the form must confirm first. Attachments are checked by the caller.
    public var hasTypedInput: Bool {
        !titleBody.isEmpty || [description, reproSteps, expectedBehavior].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The first problem that blocks Submit, or nil when the draft can be sent.
    public var validationIssue: FeedbackValidationIssue? {
        if titleBody.isEmpty { return .missingTitle }
        if title.utf16.count > FeedbackLimits.titleCharacters { return .titleTooLong }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingDescription
        }
        let boxes = kind.includesReproduction
            ? [description, reproSteps, expectedBehavior] : [description]
        if boxes.contains(where: { $0.utf16.count > FeedbackLimits.bodyCharacters }) {
            return .textTooLong
        }
        return nil
    }

    /// The text fields of the upload, with whitespace trimmed and the bug-only boxes
    /// omitted for feature requests and when empty.
    ///
    /// - Parameters:
    ///   - platform: Label for the created issue.
    ///   - appVersion: App version/build text (``AppBuildInfo/versionText(_:)``).
    ///   - clientInfo: Operating system and device, for example `iOS 26.0; iPhone`.
    /// - Returns: The submission's form fields.
    public func submission(
        platform: FeedbackPlatform, appVersion: String, clientInfo: String
    ) -> FeedbackSubmission {
        func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func optional(_ text: String) -> String? {
            guard kind.includesReproduction else { return nil }
            let value = trimmed(text)
            return value.isEmpty ? nil : value
        }
        return FeedbackSubmission(
            kind: kind, platform: platform,
            title: kind.titlePrefix + titleBody,
            description: trimmed(description),
            repro: optional(reproSteps),
            expected: optional(expectedBehavior),
            appVersion: FeedbackSubmission.singleLine(appVersion, limit: FeedbackLimits.appVersionCharacters),
            clientInfo: FeedbackSubmission.singleLine(clientInfo, limit: FeedbackLimits.clientInfoCharacters)
        )
    }
}

/// Why Submit is unavailable.
public enum FeedbackValidationIssue: Sendable, Equatable {
    case missingTitle
    case titleTooLong
    case missingDescription
    case textTooLong

    /// Short guidance shown under the form while Submit is disabled.
    public var message: String {
        switch self {
        case .missingTitle: "Add a title after the prefix."
        case .titleTooLong: "Shorten the title to \(FeedbackLimits.titleCharacters) characters."
        case .missingDescription: "Add a description."
        case .textTooLong: "Shorten each box to \(FeedbackLimits.bodyCharacters.formatted()) characters."
        }
    }
}

// MARK: - Wire models

/// One text part of the `multipart/form-data` upload.
public struct FeedbackFormField: Sendable, Equatable {
    public let name: String
    public let value: String
}

/// The text fields of `POST /api/feedback` (`docs/components/in-app-feedback.md` in the
/// service repository): flat form fields, no JSON part.
public struct FeedbackSubmission: Sendable, Equatable {
    public let kind: FeedbackKind
    public let platform: FeedbackPlatform
    public let title: String
    public let description: String
    /// Bug reports only.
    public let repro: String?
    /// Bug reports only.
    public let expected: String?
    public let appVersion: String?
    public let clientInfo: String?

    /// Fields in upload order; absent optional values are not sent.
    public var formFields: [FeedbackFormField] {
        var fields = [
            FeedbackFormField(name: "kind", value: kind.rawValue),
            FeedbackFormField(name: "platform", value: platform.rawValue),
            FeedbackFormField(name: "title", value: title),
            FeedbackFormField(name: "description", value: description),
        ]
        let optional: [(String, String?)] = [
            ("repro", repro), ("expected", expected),
            ("appVersion", appVersion), ("clientInfo", clientInfo),
        ]
        for case let (name, value?) in optional {
            fields.append(FeedbackFormField(name: name, value: value))
        }
        return fields
    }

    /// Collapse whitespace to single spaces and cut to the service's field limit.
    ///
    /// - Parameters:
    ///   - text: Raw metadata.
    ///   - limit: Maximum UTF-16 length.
    /// - Returns: The single-line value, or nil when nothing remains.
    static func singleLine(_ text: String, limit: Int) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var value = words.joined(separator: " ")
        while value.utf16.count > limit { value.removeLast() }
        return value.isEmpty ? nil : value
    }
}

/// The service's 202 answer: the report is queued and will be filed in the background.
public struct FeedbackAcceptance: Sendable, Equatable {
    /// Job ID for `GET /api/feedback/{id}`; nil when the body had no valid ID, so the
    /// outcome can't be followed (the report was still received).
    public let id: String?

    /// Decode a 202 body, keeping the ID only when it is 32 lowercase hex characters.
    ///
    /// - Parameter data: Response body.
    /// - Returns: The acceptance, with or without a followable ID.
    public static func decode(_ data: Data) -> FeedbackAcceptance {
        struct Wire: Decodable { let id: String? }
        let id = (try? JSONDecoder().decode(Wire.self, from: data))?.id
        return FeedbackAcceptance(id: id.flatMap { isJobID($0) ? $0 : nil })
    }

    /// Whether a string is a service job ID (32 lowercase hex characters).
    ///
    /// - Parameter value: Candidate ID.
    /// - Returns: True for a well-formed ID.
    public static func isJobID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
        }
    }
}

/// `GET /api/feedback/{id}`: where a queued report is.
public struct FeedbackJobStatus: Sendable, Equatable, Decodable {
    /// Job state.
    public enum State: String, Sendable, Decodable {
        case queued
        case processing
        case submitted
        case failed
    }

    /// One attachment's processing result.
    public struct Attachment: Sendable, Equatable, Decodable {
        /// `attached`, `transcoded` or `skipped` (others are treated as attached).
        public let outcome: String
    }

    public let status: State
    /// The GitHub issue number once `submitted`. No URL is returned: the tracker may be
    /// private, so the app shows only the number.
    public let issueNumber: Int?
    public let attachments: [Attachment]

    /// Whether polling can stop.
    public var isFinished: Bool { status == .submitted || status == .failed }

    /// Attachments the service could not fit into the issue.
    public var skippedAttachments: Int { attachments.filter { $0.outcome == "skipped" }.count }

    public init(status: State, issueNumber: Int?, attachments: [Attachment] = []) {
        self.status = status
        self.issueNumber = issueNumber
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey { case status, issueNumber, attachments }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(State.self, forKey: .status)
        let number = try container.decodeIfPresent(Int.self, forKey: .issueNumber)
        issueNumber = number.flatMap { $0 > 0 ? $0 : nil }
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
}

/// A failed submission, phrased for the person (never the server's own text).
public enum FeedbackError: LocalizedError, Equatable, Sendable {
    case invalidForm
    case titleRequired
    case descriptionRequired
    case fieldTooLong
    case tooManyAttachments
    case tooLarge
    case unsupportedMedia
    /// 429; seconds from `Retry-After` when the service sent it.
    case rateLimited(retryAfter: Int?)
    /// 404 `feedback_disabled`.
    case notAvailable
    /// 503 `feedback_busy`.
    case busy
    case unavailable
    case httpStatus(Int)
    case network
    case forbiddenRequest
    /// The background job reported `failed`; the form stays open to try again.
    case filingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidForm:
            "The service couldn't accept this report. Check the fields and try again."
        case .titleRequired:
            "Add a title after the prefix, then try again."
        case .descriptionRequired:
            "Add a description, then try again."
        case .fieldTooLong:
            "One of the boxes is too long. Shorten it and try again."
        case .tooManyAttachments:
            "You can attach up to \(FeedbackLimits.attachments) photos or videos. Remove one and try again."
        case .tooLarge:
            "The attachments are too large to send. Remove one and try again."
        case .unsupportedMedia:
            "One of the attachments isn't a supported photo or video. Remove it and try again."
        case let .rateLimited(seconds?) where seconds > 0:
            "Too many reports were sent from this network. Try again in \(Self.waitText(seconds))."
        case .rateLimited:
            "Too many reports were sent from this network. Wait a few minutes and try again."
        case .notAvailable:
            "Sending reports from the app isn't available right now."
        case .busy:
            "The service is busy with other reports. Try again in a minute."
        case .unavailable:
            "The service is unavailable right now. Try again in a few minutes."
        case let .httpStatus(code):
            "The report couldn't be sent (error \(code)). Try again."
        case .network:
            "The report couldn't be sent. Check your connection and try again."
        case .forbiddenRequest:
            "The report couldn't be sent. Try again."
        case .filingFailed:
            "The service couldn't file this report. Try again."
        }
    }

    /// Map a non-202 answer using the body's `code`, then the status.
    ///
    /// - Parameters:
    ///   - status: HTTP status.
    ///   - data: Body, `{"error", "code"}` when the service produced it.
    ///   - retryAfter: `Retry-After` header value.
    /// - Returns: The matching error.
    public static func forResponse(status: Int, data: Data, retryAfter: String?) -> FeedbackError {
        struct Wire: Decodable { let code: String? }
        let code = (try? JSONDecoder().decode(Wire.self, from: data))?.code
        switch code {
        case "title_required": return .titleRequired
        case "description_required": return .descriptionRequired
        case "field_too_long": return .fieldTooLong
        case "too_many_attachments": return .tooManyAttachments
        case "unsupported_media": return .unsupportedMedia
        case "payload_too_large": return .tooLarge
        case "feedback_disabled": return .notAvailable
        case "feedback_busy": return .busy
        case "invalid_form", "invalid_kind", "invalid_platform": return .invalidForm
        default: break
        }
        switch status {
        case 400, 422: return .invalidForm
        case 413: return .tooLarge
        case 415: return .unsupportedMedia
        case 429:
            let seconds = retryAfter.flatMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            return .rateLimited(retryAfter: seconds)
        case 404, 405, 501: return .notAvailable
        case 503: return .busy
        case 502, 504: return .unavailable
        default: return .httpStatus(status)
        }
    }

    /// "45 seconds" or "3 minutes" (rounded up).
    static func waitText(_ seconds: Int) -> String {
        if seconds < 60 { return seconds == 1 ? "1 second" : "\(seconds) seconds" }
        let minutes = (seconds + 59) / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

// MARK: - Attachments

/// One media file the form will upload: a private app copy, never the original.
public struct FeedbackAttachment: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Local copy inside the app's temporary directory.
    public let fileURL: URL
    /// Sanitized display and upload name.
    public let filename: String
    /// MIME type sent with the file part.
    public let mimeType: String
    public let byteCount: Int64
    public let isVideo: Bool

    /// Create an attachment record.
    ///
    /// - Parameters:
    ///   - id: Stable identity for lists.
    ///   - fileURL: App-owned copy of the media.
    ///   - filename: Name to show and upload (sanitized here).
    ///   - mimeType: `image/*` or `video/*` type.
    ///   - byteCount: File size in bytes.
    ///   - isVideo: Whether the media is a movie.
    public init(
        id: UUID = UUID(), fileURL: URL, filename: String, mimeType: String,
        byteCount: Int64, isVideo: Bool
    ) {
        self.id = id
        self.fileURL = fileURL
        self.filename = FeedbackAttachmentPolicy.sanitizedFilename(filename)
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.isVideo = isVideo
    }

    /// VoiceOver label for the thumbnail button.
    ///
    /// - Parameter position: 1-based position in the list.
    /// - Returns: For example "Video 2, clip.mov, 4.2 MB".
    public func accessibilityLabel(position: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        return "\(isVideo ? "Video" : "Photo") \(position), \(filename), \(size)"
    }
}

/// Why a picked file was not attached.
public enum FeedbackAttachmentRejection: LocalizedError, Equatable, Sendable {
    case tooMany
    case fileTooLarge(String)
    case totalTooLarge
    case unsupportedType(String)
    case unreadable
    /// Location metadata could not be removed, so the file stays private.
    case locationNotRemoved(String)

    public var errorDescription: String? {
        let total = ByteCountFormatter.string(
            fromByteCount: FeedbackLimits.totalAttachmentBytes, countStyle: .file
        )
        switch self {
        case .tooMany:
            return "You can attach up to \(FeedbackLimits.attachments) photos or videos."
        case let .fileTooLarge(name):
            return "\(name) is larger than \(total)."
        case .totalTooLarge:
            return "Attachments can total up to \(total). Remove one to add another."
        case let .unsupportedType(name):
            return "\(name) isn't a photo or video."
        case .unreadable:
            return "That file couldn't be attached. Try another."
        case let .locationNotRemoved(name):
            return "\(name) wasn't attached because its location couldn't be removed."
        }
    }
}

/// Admission rules and naming for attachments.
public enum FeedbackAttachmentPolicy {
    /// Check a candidate against the per-file, total and count limits.
    ///
    /// - Parameters:
    ///   - byteCount: Candidate size.
    ///   - filename: Candidate name, for messages.
    ///   - existing: Already attached files.
    /// - Returns: nil when it fits, otherwise the reason it does not.
    public static func rejection(
        byteCount: Int64, filename: String, existing: [FeedbackAttachment]
    ) -> FeedbackAttachmentRejection? {
        if existing.count >= FeedbackLimits.attachments { return .tooMany }
        if byteCount > FeedbackLimits.attachmentBytes { return .fileTooLarge(filename) }
        let total = existing.reduce(Int64(0)) { $0 + $1.byteCount } + byteCount
        if total > FeedbackLimits.totalAttachmentBytes { return .totalTooLarge }
        return nil
    }

    /// Classify a file as an uploadable photo or video.
    ///
    /// - Parameter filename: Name with extension.
    /// - Returns: MIME type and video flag, or nil when it is neither an image nor a movie.
    public static func media(forFilename filename: String) -> (mimeType: String, isVideo: Bool)? {
        let ext = (filename as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return nil }
        let isVideo = type.conforms(to: .movie) || type.conforms(to: .video)
        guard isVideo || type.conforms(to: .image) else { return nil }
        let mime = type.preferredMIMEType ?? (isVideo ? "video/quicktime" : "image/jpeg")
        return (mime, isVideo)
    }

    /// A safe single-line name for display and the multipart header.
    ///
    /// - Parameter raw: Picked file name.
    /// - Returns: The last path component without quotes, control characters or
    ///   separators, at most 120 characters; `attachment` when nothing remains.
    public static func sanitizedFilename(_ raw: String) -> String {
        let last = raw.split(separator: "/").last.map(String.init) ?? raw
        let cleaned = last.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !"\"\\/:".unicodeScalars.contains($0)
        }
        let name = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "attachment" }
        guard name.count > 120 else { return name }
        let ext = (name as NSString).pathExtension
        let keep = 120 - (ext.isEmpty ? 0 : ext.count + 1)
        return String(name.prefix(keep)) + (ext.isEmpty ? "" : ".\(ext)")
    }
}
