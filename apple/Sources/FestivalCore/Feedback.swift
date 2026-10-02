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

/// Client-side bounds for one submission. The service enforces its own and transcodes
/// oversized media to fit GitHub; these keep uploads from mobile networks reasonable.
public enum FeedbackLimits {
    /// GitHub's issue-title limit, prefix included.
    public static let titleCharacters = 256
    /// Per text box (Description, Steps to Reproduce, Expected Behavior).
    public static let bodyCharacters = 8_000
    /// Attachments per submission.
    public static let attachments = 5
    /// Bytes per attached file (100 MB).
    public static let attachmentBytes: Int64 = 100 * 1_024 * 1_024
    /// Bytes across all attached files (250 MB).
    public static let totalAttachmentBytes: Int64 = 250 * 1_024 * 1_024
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
        if title.count > FeedbackLimits.titleCharacters { return .titleTooLong }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingDescription
        }
        let boxes = kind.includesReproduction
            ? [description, reproSteps, expectedBehavior] : [description]
        if boxes.contains(where: { $0.count > FeedbackLimits.bodyCharacters }) {
            return .textTooLong
        }
        return nil
    }

    /// The JSON part of the upload, with whitespace trimmed and bug-only boxes omitted for
    /// feature requests and when empty.
    ///
    /// - Parameters:
    ///   - platform: Label for the created issue.
    ///   - appVersion: App version/build text (``AppBuildInfo/versionText(_:)``).
    ///   - osVersion: Operating system name and version.
    /// - Returns: The wire `submission` value.
    public func submission(
        platform: FeedbackPlatform, appVersion: String, osVersion: String
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
            reproSteps: optional(reproSteps),
            expectedBehavior: optional(expectedBehavior),
            appVersion: appVersion, osVersion: osVersion
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
        case .textTooLong: "Shorten each box to \(FeedbackLimits.bodyCharacters) characters."
        }
    }
}

// MARK: - Wire models

/// The `submission` JSON part of `POST /api/feedback`.
public struct FeedbackSubmission: Codable, Sendable, Equatable {
    public let kind: FeedbackKind
    public let platform: FeedbackPlatform
    public let title: String
    public let description: String
    public let reproSteps: String?
    public let expectedBehavior: String?
    public let appVersion: String
    public let osVersion: String
}

/// What the service returned for an accepted submission.
public struct FeedbackReceipt: Sendable, Equatable {
    /// Created issue number (201), when known.
    public let issueNumber: Int?
    /// Created issue page, only when it is an `https://github.com/…` URL.
    public let issueURL: URL?

    /// Decode a 201/202 body; an empty or unreadable body is still an accepted receipt.
    ///
    /// - Parameter data: Response body.
    /// - Returns: Receipt with any trustworthy issue number and link.
    public static func decode(_ data: Data) -> FeedbackReceipt {
        struct Wire: Decodable {
            let issueNumber: Int?
            let issueUrl: String?
        }
        let wire = try? JSONDecoder().decode(Wire.self, from: data)
        let url = wire?.issueUrl.flatMap(URL.init(string:)).flatMap { url -> URL? in
            guard url.scheme == "https", url.host?.lowercased() == "github.com" else { return nil }
            return url
        }
        return FeedbackReceipt(issueNumber: wire?.issueNumber.flatMap { $0 > 0 ? $0 : nil }, issueURL: url)
    }
}

/// A failed submission, phrased for the person (never the server's own text).
public enum FeedbackError: LocalizedError, Equatable, Sendable {
    case invalidSubmission
    case tooLarge
    case unsupportedMedia
    case rateLimited
    case notAvailable
    case unavailable
    case httpStatus(Int)
    case network
    case forbiddenRequest

    public var errorDescription: String? {
        switch self {
        case .invalidSubmission:
            "The service couldn't accept this report. Check the fields and try again."
        case .tooLarge:
            "The attachments are too large to send. Remove one and try again."
        case .unsupportedMedia:
            "One of the attachments isn't a supported photo or video. Remove it and try again."
        case .rateLimited:
            "Too many reports were sent recently. Wait a few minutes and try again."
        case .notAvailable:
            "Sending reports from the app isn't available yet. Try again after the next update."
        case .unavailable:
            "The service is unavailable right now. Try again in a few minutes."
        case let .httpStatus(code):
            "The report couldn't be sent (error \(code)). Try again."
        case .network:
            "The report couldn't be sent. Check your connection and try again."
        case .forbiddenRequest:
            "The report couldn't be sent. Try again."
        }
    }

    /// Map a non-success HTTP status.
    ///
    /// - Parameter status: Response status outside 200…202.
    /// - Returns: The matching error.
    public static func forStatus(_ status: Int) -> FeedbackError {
        switch status {
        case 400, 422: .invalidSubmission
        case 413: .tooLarge
        case 415: .unsupportedMedia
        case 429: .rateLimited
        case 404, 405, 501: .notAvailable
        case 502, 503, 504: .unavailable
        default: .httpStatus(status)
        }
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

    public var errorDescription: String? {
        let perFile = ByteCountFormatter.string(
            fromByteCount: FeedbackLimits.attachmentBytes, countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: FeedbackLimits.totalAttachmentBytes, countStyle: .file
        )
        switch self {
        case .tooMany:
            return "You can attach up to \(FeedbackLimits.attachments) photos or videos."
        case let .fileTooLarge(name):
            return "\(name) is larger than \(perFile)."
        case .totalTooLarge:
            return "Attachments can total up to \(total)."
        case let .unsupportedType(name):
            return "\(name) isn't a photo or video."
        case .unreadable:
            return "That file couldn't be attached. Try another."
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
