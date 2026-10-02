import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fakes

/// Records feedback requests and answers with a canned result.
private actor RecordingTransport: HTTPTransport {
    private let reply: Result<HTTPResult, URLError>
    private(set) var requests: [URLRequest] = []

    init(_ reply: Result<HTTPResult, URLError>) {
        self.reply = reply
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        return try reply.get()
    }
}

/// Upload-capable fake that reads the streamed body file and reports progress.
private actor RecordingUploadTransport: HTTPUploadTransport {
    private let reply: HTTPResult
    private(set) var body = Data()
    private(set) var request: URLRequest?

    init(_ reply: HTTPResult) {
        self.reply = reply
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        Issue.record("upload transports must not buffer the feedback body")
        return reply
    }

    func upload(
        _ request: URLRequest, fromFile fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HTTPResult {
        self.request = request
        body = try Data(contentsOf: fileURL)
        progress(0.5)
        progress(1)
        return reply
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var all: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private func makeAPI(_ transport: any HTTPTransport) throws -> FestivalAPI {
    try FestivalAPI(baseURL: URL(string: "https://festivalscoretracker.com")!, transport: transport)
}

private func bugSubmission() -> FeedbackSubmission {
    var draft = FeedbackDraft(kind: .bug)
    draft.setTitle("[Bug] Songs list jumps")
    draft.description = "It jumps."
    draft.reproSteps = "Scroll."
    return draft.submission(platform: .ios, appVersion: "1.0 (1)", clientInfo: "iOS 26.5; iPhone")
}

private func temporaryFile(_ name: String, bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("fst-feedback-test-\(UUID().uuidString)-\(name)")
    try bytes.write(to: url)
    return url
}

// MARK: - Draft

@Suite("Feedback draft")
struct FeedbackDraftTests {
    @Test("Each form pre-fills its prefix and only the bug form asks for reproduction")
    func prefixes() {
        #expect(FeedbackDraft(kind: .bug).title == "[Bug] ")
        #expect(FeedbackDraft(kind: .feature).title == "[Feature] ")
        #expect(FeedbackKind.bug.includesReproduction)
        #expect(!FeedbackKind.feature.includesReproduction)
        #expect(FeedbackKind.bug.formTitle == "Report an Issue")
        #expect(FeedbackKind.feature.formTitle == "Request a Feature")
    }

    @Test(
        "The title always keeps its prefix",
        arguments: [
            ("[Bug] Crash", "[Bug] Crash"),
            ("[Bug]", "[Bug] "),
            ("[Bu", "[Bug] "),
            ("", "[Bug] "),
            ("Crash on launch", "[Bug] Crash on launch"),
            ("[Bug]Crash", "[Bug] Crash"),
            ("  Crash", "[Bug] Crash"),
        ]
    )
    func prefixKept(raw: String, expected: String) {
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle(raw)
        #expect(draft.title == expected)
    }

    @Test("Unsaved input ignores the bare prefix and whitespace")
    func unsavedInput() {
        var draft = FeedbackDraft(kind: .feature)
        #expect(!draft.hasTypedInput)
        draft.setTitle("[Feature]    ")
        draft.description = "  \n"
        #expect(!draft.hasTypedInput)
        draft.expectedBehavior = "x"
        #expect(draft.hasTypedInput)
        var titled = FeedbackDraft(kind: .bug)
        titled.setTitle("[Bug] a")
        #expect(titled.hasTypedInput)
    }

    @Test("Submit needs a title body and description within the limits")
    func validation() {
        var draft = FeedbackDraft(kind: .bug)
        #expect(draft.validationIssue == .missingTitle)
        draft.setTitle("[Bug] Crash")
        #expect(draft.validationIssue == .missingDescription)
        draft.description = "Details"
        #expect(draft.validationIssue == nil)
        draft.reproSteps = String(repeating: "a", count: FeedbackLimits.bodyCharacters + 1)
        #expect(draft.validationIssue == .textTooLong)
        draft.reproSteps = ""
        draft.setTitle("[Bug] " + String(repeating: "t", count: FeedbackLimits.titleCharacters))
        #expect(draft.validationIssue == .titleTooLong)
        // The service counts UTF-16 units: 194 + "[Bug] " fits, one emoji more does not.
        draft.setTitle("[Bug] " + String(repeating: "t", count: FeedbackLimits.titleCharacters - 7))
        #expect(draft.validationIssue == nil)
        draft.setTitle(draft.title + "🎸")
        #expect(draft.validationIssue == .titleTooLong)
        #expect(FeedbackValidationIssue.missingTitle.message.contains("title"))
        #expect(!FeedbackValidationIssue.titleTooLong.message.isEmpty)
        #expect(!FeedbackValidationIssue.missingDescription.message.isEmpty)
        #expect(!FeedbackValidationIssue.textTooLong.message.isEmpty)
    }

    @Test("Feature requests ignore hidden bug boxes")
    func featureIgnoresBugBoxes() {
        var draft = FeedbackDraft(kind: .feature)
        draft.setTitle("[Feature] Dark mode")
        draft.description = "Please"
        draft.reproSteps = String(repeating: "a", count: FeedbackLimits.bodyCharacters + 1)
        #expect(draft.validationIssue == nil)
        let submission = draft.submission(platform: .macos, appVersion: "v", clientInfo: "o")
        #expect(submission.repro == nil)
        #expect(submission.expected == nil)
        #expect(!submission.formFields.contains { $0.name == "repro" || $0.name == "expected" })
    }

    @Test("The submission trims text and omits empty bug boxes")
    func submissionShape() throws {
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle("[Bug]   Crash  ")
        draft.description = "  Boom \n"
        draft.reproSteps = "1. Open"
        let submission = draft.submission(
            platform: .iphoneDuo, appVersion: "1.0 (2)", clientInfo: "iOS 27.1;\n iPhone"
        )
        #expect(submission.title == "[Bug] Crash")
        #expect(submission.description == "Boom")
        #expect(submission.repro == "1. Open")
        #expect(submission.expected == nil)
        #expect(submission.formFields.map { "\($0.name)=\($0.value)" } == [
            "kind=bug", "platform=iphone-duo", "title=[Bug] Crash", "description=Boom",
            "repro=1. Open", "appVersion=1.0 (2)", "clientInfo=iOS 27.1; iPhone",
        ])
    }

    @Test("Metadata is one line within the service's field limits")
    func metadataLimits() {
        let draft = FeedbackDraft(kind: .feature)
        let long = draft.submission(
            platform: .ios, appVersion: String(repeating: "9", count: 100),
            clientInfo: String(repeating: "é", count: 300)
        )
        #expect(long.appVersion?.utf16.count == FeedbackLimits.appVersionCharacters)
        #expect(long.clientInfo?.utf16.count == FeedbackLimits.clientInfoCharacters)
        let blank = draft.submission(platform: .ios, appVersion: " \n ", clientInfo: "")
        #expect(blank.appVersion == nil)
        #expect(blank.clientInfo == nil)
        #expect(blank.formFields.map(\.name) == ["kind", "platform", "title", "description"])
    }

    @Test(
        "Platform resolution prefers Mac, then hinge, then iPad",
        arguments: [
            (true, true, true, FeedbackPlatform.macos),
            (false, true, true, .iphoneDuo),
            (false, true, false, .ipados),
            (false, false, false, .ios),
        ]
    )
    func platform(isMac: Bool, isPad: Bool, hasHinge: Bool, expected: FeedbackPlatform) {
        #expect(FeedbackPlatform.resolve(isMac: isMac, isPad: isPad, hasHinge: hasHinge) == expected)
    }
}

// MARK: - Attachments

@Suite("Feedback attachments")
struct FeedbackAttachmentTests {
    private func attachment(_ bytes: Int64, video: Bool = false) -> FeedbackAttachment {
        FeedbackAttachment(
            fileURL: URL(fileURLWithPath: "/tmp/x"), filename: "x.png",
            mimeType: "image/png", byteCount: bytes, isVideo: video
        )
    }

    @Test("Count, per-file and total limits reject in that order")
    func limits() {
        let mb: Int64 = 1_000_000
        #expect(FeedbackLimits.attachments == 4)
        #expect(FeedbackLimits.totalAttachmentBytes < 94_371_840)
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: mb, filename: "a", existing: []) == nil)
        let full = Array(repeating: attachment(mb), count: FeedbackLimits.attachments)
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: 1, filename: "a", existing: full) == .tooMany)
        #expect(
            FeedbackAttachmentPolicy.rejection(
                byteCount: FeedbackLimits.attachmentBytes + 1, filename: "big.mov", existing: []
            ) == .fileTooLarge("big.mov")
        )
        let two = [attachment(40 * mb), attachment(40 * mb)]
        #expect(
            FeedbackAttachmentPolicy.rejection(byteCount: 11 * mb, filename: "c", existing: two)
                == .totalTooLarge
        )
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: 10 * mb, filename: "c", existing: two) == nil)
        #expect(FeedbackAttachmentRejection.totalTooLarge.errorDescription?.contains("90 MB") == true)
    }

    @Test("Rejections explain themselves")
    func rejectionMessages() {
        let all: [FeedbackAttachmentRejection] = [
            .tooMany, .fileTooLarge("a.mov"), .totalTooLarge, .unsupportedType("a.pdf"), .unreadable,
        ]
        for rejection in all {
            #expect(!(rejection.errorDescription ?? "").isEmpty)
        }
        #expect(FeedbackAttachmentRejection.unsupportedType("a.pdf").errorDescription?.contains("a.pdf") == true)
    }

    @Test(
        "Only photos and videos are accepted",
        arguments: [
            ("shot.png", "image/png", false),
            ("photo.HEIC", "image/heic", false),
            ("clip.mov", "video/quicktime", true),
            ("clip.mp4", "video/mp4", true),
        ]
    )
    func mediaTypes(name: String, mime: String, video: Bool) throws {
        let media = try #require(FeedbackAttachmentPolicy.media(forFilename: name))
        #expect(media.mimeType == mime)
        #expect(media.isVideo == video)
    }

    @Test("Documents and unknown types are refused")
    func refusedTypes() {
        #expect(FeedbackAttachmentPolicy.media(forFilename: "notes.pdf") == nil)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "readme.txt") == nil)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "noext") == nil)
    }

    @Test("File names are made safe for the multipart header")
    func sanitizing() {
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("a/b/IMG_1.png") == "IMG_1.png")
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("ev\"il\r\n.png") == "evil.png")
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("  ") == "attachment")
        let long = String(repeating: "n", count: 300) + ".mov"
        let trimmed = FeedbackAttachmentPolicy.sanitizedFilename(long)
        #expect(trimmed.count == 120)
        #expect(trimmed.hasSuffix(".mov"))
        #expect(FeedbackAttachmentPolicy.sanitizedFilename(String(repeating: "z", count: 200)).count == 120)
    }

    @Test("Thumbnails have a spoken kind, position, name and size")
    func accessibilityLabel() {
        let label = attachment(2_048, video: true).accessibilityLabel(position: 2)
        #expect(label.hasPrefix("Video 2, x.png, "))
        #expect(attachment(1).accessibilityLabel(position: 1).hasPrefix("Photo 1"))
    }
}

// MARK: - Wire

@Suite("Feedback wire")
struct FeedbackWireTests {
    @Test("Multipart body carries each text field then each file")
    func multipart() throws {
        let file = try temporaryFile("a.png", bytes: Data([0, 1, 2, 3]))
        defer { try? FileManager.default.removeItem(at: file) }
        let attachment = FeedbackAttachment(
            fileURL: file, filename: "a.png", mimeType: "image/png", byteCount: 4, isVideo: false
        )
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("fst-feedback-test-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: out) }
        let length = try FeedbackMultipartBody.write(
            fields: [
                FeedbackFormField(name: "kind", value: "bug"),
                FeedbackFormField(name: "title", value: "[Bug] Ünïcode"),
            ],
            attachments: [attachment], boundary: "B", to: out
        )
        let body = try Data(contentsOf: out)
        #expect(Int64(body.count) == length)
        let expected = Data(
            ("--B\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nbug\r\n"
                + "--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n[Bug] Ünïcode\r\n"
                + "--B\r\nContent-Disposition: form-data; name=\"media\"; filename=\"a.png\"\r\n"
                + "Content-Type: image/png\r\n\r\n").utf8
        ) + Data([0, 1, 2, 3]) + Data("\r\n--B--\r\n".utf8)
        #expect(body == expected)
        #expect(FeedbackMultipartBody.contentType(boundary: "B") == "multipart/form-data; boundary=B")
        #expect(FeedbackMultipartBody.makeBoundary().hasPrefix("FSTFeedback-"))
    }

    @Test("A 202 keeps only a well-formed job ID")
    func acceptance() {
        let id = "0123456789abcdef0123456789abcdef"
        #expect(FeedbackAcceptance.decode(Data(#"{"id":"\#(id)","status":"queued"}"#.utf8)).id == id)
        #expect(FeedbackAcceptance.decode(Data(#"{"id":"0123456789ABCDEF0123456789ABCDEF"}"#.utf8)).id == nil)
        #expect(FeedbackAcceptance.decode(Data(#"{"id":"../x"}"#.utf8)).id == nil)
        #expect(FeedbackAcceptance.decode(Data()).id == nil)
        #expect(!FeedbackAcceptance.isJobID(id + "0"))
    }

    @Test("Job status decodes the state, issue number and skipped media")
    func jobStatus() throws {
        let body = #"{"id":"x","status":"submitted","issueNumber":42,"attachments":[{"name":"a.png","kind":"image","outcome":"attached"},{"name":"b.mov","kind":"video","outcome":"skipped","note":"too big"}]}"#
        let status = try JSONDecoder().decode(FeedbackJobStatus.self, from: Data(body.utf8))
        #expect(status.status == .submitted)
        #expect(status.issueNumber == 42)
        #expect(status.skippedAttachments == 1)
        #expect(status.isFinished)
        let queued = try JSONDecoder().decode(
            FeedbackJobStatus.self, from: Data(#"{"status":"processing","issueNumber":0}"#.utf8)
        )
        #expect(!queued.isFinished)
        #expect(queued.issueNumber == nil)
        #expect(queued.attachments.isEmpty)
        #expect(FeedbackJobStatus(status: .failed, issueNumber: nil).isFinished)
    }

    @Test(
        "Error codes map to fixed copy before statuses",
        arguments: [
            ("title_required", 400, FeedbackError.titleRequired),
            ("description_required", 400, .descriptionRequired),
            ("field_too_long", 400, .fieldTooLong),
            ("too_many_attachments", 400, .tooManyAttachments),
            ("unsupported_media", 400, .unsupportedMedia),
            ("invalid_kind", 400, .invalidForm),
            ("invalid_platform", 400, .invalidForm),
            ("invalid_form", 400, .invalidForm),
            ("payload_too_large", 413, .tooLarge),
            ("feedback_disabled", 404, .notAvailable),
            ("feedback_busy", 503, .busy),
        ]
    )
    func codes(code: String, status: Int, expected: FeedbackError) {
        let body = Data(#"{"error":"server text","code":"\#(code)"}"#.utf8)
        let error = FeedbackError.forResponse(status: status, data: body, retryAfter: nil)
        #expect(error == expected)
        #expect(!(error.errorDescription ?? "").isEmpty)
        #expect(error.errorDescription?.contains("server text") == false)
    }

    @Test(
        "Statuses without a known code map to readable errors",
        arguments: [
            (400, FeedbackError.invalidForm), (422, .invalidForm), (413, .tooLarge),
            (415, .unsupportedMedia), (429, .rateLimited(retryAfter: nil)), (404, .notAvailable),
            (405, .notAvailable), (501, .notAvailable), (503, .busy), (502, .unavailable),
            (504, .unavailable), (500, .httpStatus(500)),
        ]
    )
    func statuses(code: Int, expected: FeedbackError) {
        #expect(FeedbackError.forResponse(status: code, data: Data("<html>".utf8), retryAfter: nil) == expected)
        #expect(!(expected.errorDescription ?? "").isEmpty)
    }

    @Test("Rate limits say how long to wait when the service does")
    func rateLimitWait() {
        let error = FeedbackError.forResponse(status: 429, data: Data(), retryAfter: " 90 ")
        #expect(error == .rateLimited(retryAfter: 90))
        #expect(error.errorDescription?.contains("2 minutes") == true)
        #expect(FeedbackError.rateLimited(retryAfter: 45).errorDescription?.contains("45 seconds") == true)
        #expect(FeedbackError.rateLimited(retryAfter: 1).errorDescription?.contains("1 second") == true)
        #expect(FeedbackError.rateLimited(retryAfter: 60).errorDescription?.contains("1 minute") == true)
        #expect(FeedbackError.rateLimited(retryAfter: 0).errorDescription?.contains("few minutes") == true)
        #expect(FeedbackError.forResponse(status: 429, data: Data(), retryAfter: "soon") == .rateLimited(retryAfter: nil))
    }

    @Test("Other errors have readable text")
    func otherErrors() {
        #expect(FeedbackError.network.errorDescription?.contains("connection") == true)
        #expect(!(FeedbackError.forbiddenRequest.errorDescription ?? "").isEmpty)
        #expect(!(FeedbackError.filingFailed.errorDescription ?? "").isEmpty)
        #expect(!(FeedbackError.httpStatus(500).errorDescription ?? "").isEmpty)
    }

    @Test("Only a keyless POST to /api/feedback passes the gate")
    func gate() throws {
        let base = URL(string: "https://festivalscoretracker.com")!
        let request = FestivalAPI.makeFeedbackRequest(baseURL: base, boundary: "B")
        try FestivalAPI.validateFeedbackRequest(request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://festivalscoretracker.com/api/feedback")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")

        var keyed = request
        keyed.setValue("secret", forHTTPHeaderField: "X-API-Key")
        #expect(throws: FeedbackError.forbiddenRequest) { try FestivalAPI.validateFeedbackRequest(keyed) }
        var profiled = request
        profiled.setValue("a", forHTTPHeaderField: "X-FST-Selected-Account-Id")
        #expect(throws: FeedbackError.forbiddenRequest) { try FestivalAPI.validateFeedbackRequest(profiled) }
        var get = request
        get.httpMethod = "GET"
        #expect(throws: FeedbackError.forbiddenRequest) { try FestivalAPI.validateFeedbackRequest(get) }
        var other = request
        other.url = URL(string: "https://festivalscoretracker.com/api/player/x/track")
        #expect(throws: FeedbackError.forbiddenRequest) { try FestivalAPI.validateFeedbackRequest(other) }
    }

    @Test("Submit streams through an upload transport and returns the job ID")
    func submitUpload() async throws {
        let id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let transport = RecordingUploadTransport(HTTPResult(
            status: 202, data: Data(#"{"id":"\#(id)","status":"queued"}"#.utf8)
        ))
        let file = try temporaryFile("clip.mov", bytes: Data("video".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let attachment = FeedbackAttachment(
            fileURL: file, filename: "clip.mov", mimeType: "video/quicktime", byteCount: 5, isVideo: true
        )
        let log = ProgressLog()
        let acceptance = try await makeAPI(transport).submitFeedback(
            bugSubmission(), attachments: [attachment], progress: { log.append($0) }
        )
        #expect(acceptance.id == id)
        #expect(log.all == [0.5, 1])
        let body = String(decoding: await transport.body, as: UTF8.self)
        #expect(body.contains("name=\"title\"\r\n\r\n[Bug] Songs list jumps\r\n"))
        #expect(body.contains("name=\"platform\"\r\n\r\nios\r\n"))
        #expect(body.contains("name=\"clientInfo\"\r\n\r\niOS 26.5; iPhone\r\n"))
        #expect(body.contains(#"filename="clip.mov""#))
        #expect(body.contains("video"))
        let request = try #require(await transport.request)
        #expect(request.url?.path == "/api/feedback")
    }

    @Test("A plain transport receives the buffered body; a 202 without an ID is still accepted")
    func submitBuffered() async throws {
        let transport = RecordingTransport(.success(HTTPResult(
            status: 202, data: Data(#"{"submissionId":"abc"}"#.utf8)
        )))
        let log = ProgressLog()
        let acceptance = try await makeAPI(transport).submitFeedback(
            bugSubmission(), attachments: [], progress: { log.append($0) }
        )
        #expect(acceptance == FeedbackAcceptance(id: nil))
        #expect(log.all == [1])
        let sent = try #require(await transport.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(String(decoding: sent.httpBody ?? Data(), as: UTF8.self).contains("name=\"kind\"\r\n\r\nbug"))
    }

    @Test("HTTP and network failures become feedback errors")
    func submitFailures() async throws {
        let rejected = RecordingTransport(.success(HTTPResult(
            status: 429, data: Data(), headers: ["Retry-After": "30"]
        )))
        await #expect(throws: FeedbackError.rateLimited(retryAfter: 30)) {
            _ = try await makeAPI(rejected).submitFeedback(bugSubmission(), attachments: [])
        }
        let busy = RecordingTransport(.success(HTTPResult(
            status: 503, data: Data(#"{"error":"x","code":"feedback_busy"}"#.utf8)
        )))
        await #expect(throws: FeedbackError.busy) {
            _ = try await makeAPI(busy).submitFeedback(bugSubmission(), attachments: [])
        }
        let offline = RecordingTransport(.failure(URLError(.notConnectedToInternet)))
        await #expect(throws: FeedbackError.network) {
            _ = try await makeAPI(offline).submitFeedback(bugSubmission(), attachments: [])
        }
        let cancelled = RecordingTransport(.failure(URLError(.cancelled)))
        await #expect(throws: CancellationError.self) {
            _ = try await makeAPI(cancelled).submitFeedback(bugSubmission(), attachments: [])
        }
    }

    @Test("Status reads are keyless GETs to a validated job path")
    func statusRead() async throws {
        let id = "0123456789abcdef0123456789abcdef"
        let transport = RecordingTransport(.success(HTTPResult(
            status: 200, data: Data(#"{"id":"\#(id)","status":"submitted","issueNumber":9,"attachments":[]}"#.utf8)
        )))
        let status = try await makeAPI(transport).feedbackStatus(id: id)
        #expect(status.issueNumber == 9)
        let sent = try #require(await transport.requests.first)
        #expect(sent.httpMethod == "GET")
        #expect(sent.url?.path == "/api/feedback/\(id)")
        #expect(sent.allHTTPHeaderFields?.keys.contains { $0.lowercased().hasPrefix("x-") } == false)
        await #expect(throws: FeedbackError.forbiddenRequest) {
            _ = try await makeAPI(transport).feedbackStatus(id: "../../api/player/x")
        }
        #expect(await transport.requests.count == 1)
        let missing = RecordingTransport(.success(HTTPResult(status: 404, data: Data())))
        await #expect(throws: FestivalAPIError.httpStatus(404)) {
            _ = try await makeAPI(missing).feedbackStatus(id: id)
        }
    }

    @Test(
        "The features flag enables feedback only when it is true",
        arguments: [
            (#"{"appManual":false,"feedback":true}"#, true),
            (#"{"appManual":false,"feedback":false}"#, false),
            (#"{"appManual":false}"#, false),
        ]
    )
    func features(body: String, expected: Bool) async throws {
        let transport = RecordingTransport(.success(HTTPResult(status: 200, data: Data(body.utf8))))
        #expect(try await makeAPI(transport).feedbackEnabled() == expected)
        let sent = try #require(await transport.requests.first)
        #expect(sent.url?.path == "/api/features")
        #expect(sent.httpMethod == "GET")
    }

    @Test("The URLSession transport uploads a file and reports progress")
    func urlSessionUpload() async throws {
        let transport = URLSessionHTTPTransport(protocolClasses: [FeedbackEchoProtocol.self])
        let file = try temporaryFile("body", bytes: Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        var request = URLRequest(url: URL(string: "https://festivalscoretracker.com/api/feedback")!)
        request.httpMethod = "POST"
        let result = try await transport.upload(request, fromFile: file, progress: { _ in })
        #expect(result.status == 201)
        #expect(result.header("x-echo") == "ok")
    }
}

/// Answers any request with 201 so the real URLSession upload path can run offline.
private final class FeedbackEchoProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1",
            headerFields: ["X-Echo": "ok"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
