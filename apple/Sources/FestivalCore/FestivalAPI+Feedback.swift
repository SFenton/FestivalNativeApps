import Foundation

// MARK: - Multipart body

/// Writes the `multipart/form-data` body of `POST /api/feedback` to a file, streaming
/// media so large videos never sit in memory.
public enum FeedbackMultipartBody {
    /// Bytes copied per read while streaming an attachment.
    static let chunkSize = 1 << 20

    /// A random boundary that cannot appear in the text fields.
    ///
    /// - Returns: `FSTFeedback-<uuid>`.
    public static func makeBoundary() -> String {
        "FSTFeedback-\(UUID().uuidString)"
    }

    /// The request `Content-Type` for a boundary.
    ///
    /// - Parameter boundary: Value from ``makeBoundary()``.
    /// - Returns: `multipart/form-data; boundary=<boundary>`.
    public static func contentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Write one text part per form field followed by one `media` part per attachment.
    ///
    /// - Parameters:
    ///   - fields: ``FeedbackSubmission/formFields``.
    ///   - attachments: Files to append, in order.
    ///   - boundary: Part separator.
    ///   - destination: File to create or replace.
    /// - Returns: Total body length in bytes.
    /// - Throws: File creation or read errors.
    @discardableResult
    public static func write(
        fields: [FeedbackFormField], attachments: [FeedbackAttachment], boundary: String,
        to destination: URL
    ) throws -> Int64 {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var written: Int64 = 0
        func emit(_ data: Data) throws {
            try output.write(contentsOf: data)
            written += Int64(data.count)
        }
        func emit(_ text: String) throws { try emit(Data(text.utf8)) }

        for field in fields {
            try emit("--\(boundary)\r\n")
            try emit("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            try emit(field.value)
            try emit("\r\n")
        }
        for attachment in attachments {
            try emit("--\(boundary)\r\n")
            try emit(
                "Content-Disposition: form-data; name=\"media\"; filename=\"\(attachment.filename)\"\r\n"
            )
            try emit("Content-Type: \(attachment.mimeType)\r\n\r\n")
            let input = try FileHandle(forReadingFrom: attachment.fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                try emit(chunk)
            }
            try emit("\r\n")
        }
        try emit("--\(boundary)--\r\n")
        return written
    }
}

// MARK: - Upload transport

/// A transport that can stream a request body from a file and report send progress.
public protocol HTTPUploadTransport: HTTPTransport {
    /// Upload a file as the request body.
    ///
    /// - Parameters:
    ///   - request: Prepared request (method, headers).
    ///   - fileURL: Body file.
    ///   - progress: Fraction of the body sent, 0…1, on an arbitrary thread.
    /// - Returns: Status, body and headers.
    func upload(
        _ request: URLRequest, fromFile fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HTTPResult
}

extension URLSessionHTTPTransport: HTTPUploadTransport {
    /// Stream the body file with a per-task delegate that reports bytes sent.
    ///
    /// - Parameters:
    ///   - request: Prepared POST.
    ///   - fileURL: Multipart body file.
    ///   - progress: Fraction of the body sent.
    /// - Returns: HTTP status, payload and headers.
    /// - Throws: `FestivalAPIError.invalidResponse` for a non-HTTP reply, or transport errors.
    public func upload(
        _ request: URLRequest, fromFile fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HTTPResult {
        let delegate = UploadProgressDelegate(progress)
        let (data, response) = try await session.upload(
            for: request, fromFile: fileURL, delegate: delegate
        )
        guard let response = response as? HTTPURLResponse else {
            throw FestivalAPIError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else { return }
            result[key] = value
        }
        return HTTPResult(status: response.statusCode, data: data, headers: headers)
    }
}

/// Forwards `didSendBodyData` as a 0…1 fraction.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}

// MARK: - Endpoints

/// The feedback reads. Both are pure (`FSTService/Api/FeatureEndpoints.cs`,
/// `FeedbackEndpoints.cs`): `/api/features` returns configuration flags and
/// `/api/feedback/{id}` looks up an in-memory job status.
enum FeedbackServiceEndpoint: ServiceEndpoint {
    case features
    case status(String)

    /// Build the endpoint URL.
    ///
    /// - Parameter baseURL: Validated service origin.
    /// - Returns: `/api/features` or `/api/feedback/{id}`.
    /// - Throws: ``FeedbackError/forbiddenRequest`` for an ID that is not 32 lowercase hex.
    func url(relativeTo baseURL: URL) throws -> URL {
        let api = baseURL.appendingPathComponent("api")
        switch self {
        case .features:
            return api.appendingPathComponent("features")
        case let .status(id):
            guard FeedbackAcceptance.isJobID(id) else { throw FeedbackError.forbiddenRequest }
            return api.appendingPathComponent("feedback").appendingPathComponent(id)
        }
    }
}

/// `GET /api/features` flags natives read.
private struct ServiceFeaturesBody: Decodable {
    let feedback: Bool?
}

// MARK: - Submit

extension FestivalAPI {
    /// The only non-GET path the native apps may send, and only on a person's Submit.
    static let feedbackPath = "/api/feedback"

    /// Upload idle timeout for slow mobile uploads.
    static let feedbackTimeout: TimeInterval = 120

    /// Whether the service accepts in-app feedback (`GET /api/features` → `feedback`).
    ///
    /// - Returns: True only when the flag is present and true.
    /// - Throws: Transport or mapped status errors; callers hide the rows on failure.
    public func feedbackEnabled() async throws -> Bool {
        try await fetchJSON(FeedbackServiceEndpoint.features, as: ServiceFeaturesBody.self)
            .value.feedback == true
    }

    /// Read a queued report's progress (`GET /api/feedback/{id}`).
    ///
    /// - Parameter id: Job ID from ``FeedbackAcceptance``.
    /// - Returns: The job status.
    /// - Throws: ``FeedbackError/forbiddenRequest`` for a malformed ID; transport, mapped
    ///   status (404 for an unknown or expired job) or `invalidResponse` errors.
    public func feedbackStatus(id: String) async throws -> FeedbackJobStatus {
        try await fetchJSON(FeedbackServiceEndpoint.status(id), as: FeedbackJobStatus.self).value
    }

    /// Send a bug report or feature request with its media (`POST /api/feedback`).
    ///
    /// The request carries no API key and no selected-profile headers. Called only from
    /// the form's Submit button; automation submits to the loopback mock service.
    ///
    /// - Parameters:
    ///   - submission: Form contents.
    ///   - attachments: App-owned media copies.
    ///   - progress: Fraction of the upload sent.
    /// - Returns: The 202 acceptance; follow it with ``feedbackStatus(id:)``.
    /// - Throws: ``FeedbackError`` for HTTP and network failures, `CancellationError`.
    public func submitFeedback(
        _ submission: FeedbackSubmission, attachments: [FeedbackAttachment],
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> FeedbackAcceptance {
        let boundary = FeedbackMultipartBody.makeBoundary()
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fst-feedback-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        try FeedbackMultipartBody.write(
            fields: submission.formFields, attachments: attachments, boundary: boundary,
            to: bodyURL
        )
        let request = Self.makeFeedbackRequest(baseURL: baseURL, boundary: boundary)
        try Self.validateFeedbackRequest(request)
        try Task.checkCancellation()
        let response: HTTPResult
        do {
            if let uploader = transport as? any HTTPUploadTransport {
                response = try await uploader.upload(request, fromFile: bodyURL, progress: progress)
            } else {
                var buffered = request
                buffered.httpBody = try Data(contentsOf: bodyURL)
                response = try await transport.send(buffered)
                progress(1)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw FeedbackError.network
        }
        try Task.checkCancellation()
        guard (200...299).contains(response.status) else {
            throw FeedbackError.forResponse(
                status: response.status, data: response.data,
                retryAfter: response.header("Retry-After")
            )
        }
        return FeedbackAcceptance.decode(response.data)
    }

    /// Build the feedback POST.
    ///
    /// - Parameters:
    ///   - baseURL: Validated service origin.
    ///   - boundary: Multipart boundary.
    /// - Returns: A POST to `/api/feedback` with only content-type and accept headers.
    static func makeFeedbackRequest(baseURL: URL, boundary: String) -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("api").appendingPathComponent("feedback"),
            cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: feedbackTimeout
        )
        request.httpMethod = "POST"
        request.setValue(
            FeedbackMultipartBody.contentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Refuse anything but a keyless POST to exactly `/api/feedback`.
    ///
    /// - Parameter request: Request about to be sent.
    /// - Throws: ``FeedbackError/forbiddenRequest`` for another method or path, a privileged
    ///   key or a selected-profile header.
    static func validateFeedbackRequest(_ request: URLRequest) throws {
        guard request.httpMethod == "POST", request.url?.path == feedbackPath,
              request.url?.query == nil
        else { throw FeedbackError.forbiddenRequest }
        for name in (request.allHTTPHeaderFields ?? [:]).keys {
            let lowered = name.lowercased()
            if forbiddenHeaderNames.contains(lowered)
                || forbiddenHeaderPrefixes.contains(where: lowered.hasPrefix) {
                throw FeedbackError.forbiddenRequest
            }
        }
    }
}
