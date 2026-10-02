import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fakes

/// Answers every request with one canned result.
private struct CannedTransport: HTTPTransport {
    let result: Result<HTTPResult, URLError>

    func send(_ request: URLRequest) async throws -> HTTPResult {
        try result.get()
    }
}

/// Answers the POST with `submit`, then each status GET with the next scripted reply
/// (repeating the last one).
private actor ScriptedTransport: HTTPTransport {
    private let submit: HTTPResult
    private var statuses: [Result<HTTPResult, URLError>]
    private(set) var statusReads = 0

    init(submit: HTTPResult, statuses: [Result<HTTPResult, URLError>]) {
        self.submit = submit
        self.statuses = statuses
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        if request.httpMethod == "POST" { return submit }
        statusReads += 1
        let next = statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        return try next.get()
    }
}

private let jobID = "0123456789abcdef0123456789abcdef"

private func accepted(_ id: String = jobID) -> HTTPResult {
    HTTPResult(status: 202, data: Data(#"{"id":"\#(id)","status":"queued"}"#.utf8))
}

private func job(_ status: String, issue: Int? = nil, skipped: Int = 0) -> Result<HTTPResult, URLError> {
    let number = issue.map { #","issueNumber":\#($0)"# } ?? ""
    let media = Array(repeating: #"{"name":"a","kind":"image","outcome":"skipped"}"#, count: skipped)
        .joined(separator: ",")
    return .success(HTTPResult(
        status: 200,
        data: Data(#"{"id":"\#(jobID)","status":"\#(status)"\#(number),"attachments":[\#(media)]}"#.utf8)
    ))
}

/// Never answers until cancelled, so the submitting phase can be observed.
private struct HangingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

@MainActor
private func session(_ transport: any HTTPTransport) -> FestivalSession {
    FestivalSession(factory: {
        try FestivalAPI(baseURL: URL(string: "https://festivalscoretracker.com")!, transport: transport)
    })
}

private func sourceFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("fst-feedback-model-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Raw bytes under `name` (not a readable image or movie).
private func sourceFile(_ name: String, bytes: Int = 16) throws -> URL {
    let url = try sourceFolder().appendingPathComponent(name)
    try Data(repeating: 7, count: bytes).write(to: url)
    return url
}

/// A real 4×4 image, optionally GPS-tagged.
private func sourceImage(_ name: String, type: UTType = .png, gps: Bool = false) throws -> URL {
    let url = try sourceFolder().appendingPathComponent(name)
    let context = try #require(CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let image = try #require(context.makeImage())
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
    )
    let properties: [CFString: Any] = gps
        ? [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W",
        ]]
        : [:]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

private func hasGPS(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return false }
    return properties[kCGImagePropertyGPSDictionary] != nil
}

@MainActor
/// Generous default wait: `swift test --parallel` can starve the main actor for seconds.
private func validBug(timeout: Duration = .seconds(60)) -> FeedbackFormModel {
    let model = FeedbackFormModel(kind: .bug, pollInterval: .milliseconds(5), pollTimeout: timeout)
    model.title = "[Bug] Crash"
    model.descriptionText = "Boom"
    return model
}

@MainActor
/// Polls `condition` every 10 ms until it holds or 60 s pass (a deadline, not an iteration
/// count, so a busy parallel run cannot end the wait early).
private func waitUntil(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(60))
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Tests

@Suite("Feedback form model", .serialized)
@MainActor
struct FeedbackFormModelTests {
    @Test("Typing keeps the prefix and marks the form unsaved")
    func draft() {
        let model = FeedbackFormModel(kind: .feature)
        #expect(model.title == "[Feature] ")
        #expect(!model.hasUnsavedInput)
        #expect(!model.canSubmit)
        model.title = "Dark mode"
        #expect(model.title == "[Feature] Dark mode")
        #expect(model.hasUnsavedInput)
        model.descriptionText = "Please"
        model.reproSteps = "ignored"
        model.expectedBehavior = "ignored"
        #expect(model.reproSteps == "ignored")
        #expect(model.expectedBehavior == "ignored")
        #expect(model.canSubmit)
    }

    @Test("A picked file is copied, typed and removable; the original is untouched")
    func importAndRemove() async throws {
        let source = try sourceImage("shot.png")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let model = FeedbackFormModel(kind: .bug)
        await model.importFiles(.success([source]))
        let attachment = try #require(model.attachments.first)
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.byteCount == Int64(try Data(contentsOf: source).count))
        #expect(attachment.fileURL != source)
        #expect(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        #expect(model.hasUnsavedInput)
        #expect(model.importing == 0)

        model.remove(attachment)
        #expect(model.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: attachment.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Documents, a fifth file and importer failures are refused with a reason")
    func refusals() async throws {
        let model = FeedbackFormModel(kind: .bug)
        let text = try sourceFile("notes.txt")
        await model.importFiles(.success([text]))
        #expect(model.attachments.isEmpty)
        #expect(model.attachmentMessage?.contains("notes.txt") == true)

        let broken = try sourceFile("broken.mov")
        await model.importFiles(.success([broken]))
        #expect(model.attachments.isEmpty)
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)

        let clips = try (1...(FeedbackLimits.attachments + 1)).map { try sourceImage("shot\($0).png") }
        await model.importFiles(.success(clips))
        #expect(model.attachments.count == FeedbackLimits.attachments)
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.tooMany.errorDescription)

        await model.importFiles(.failure(URLError(.cancelled)))
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)

        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID()).png")
        await model.importFiles(.success([missing]))
        #expect(model.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)

        let copies = model.attachments.map(\.fileURL)
        model.discardMedia()
        #expect(model.attachments.isEmpty)
        #expect(copies.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        for url in [text, broken] + clips {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    @Test("An attached photo loses its location; the original keeps it")
    func locationRemoved() async throws {
        let source = try sourceImage("trip.jpg", type: .jpeg, gps: true)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let model = FeedbackFormModel(kind: .bug)
        await model.importFiles(.success([source]))
        let attachment = try #require(model.attachments.first)
        #expect(!hasGPS(attachment.fileURL))
        #expect(hasGPS(source))
        #expect(attachment.byteCount == Int64(try Data(contentsOf: attachment.fileURL).count))
        model.discardMedia()
    }

    @Test("A submit is followed until the issue is filed")
    func submitFiled() async {
        let model = validBug()
        let transport = ScriptedTransport(
            submit: accepted(),
            statuses: [job("queued"), job("processing"), job("submitted", issue: 3, skipped: 1)]
        )
        model.submit(session: session(transport), platform: .ios)
        #expect(model.isSubmitting)
        #expect(model.isBusy)
        #expect(!model.canSubmit)
        await waitUntil { if case .finished = model.phase { true } else { false } }
        #expect(model.phase == .finished(.filed(issueNumber: 3, skipped: 1)))
        #expect(await transport.statusReads == 3)
    }

    @Test("An accepted report shows the filing phase, which closes without losing anything")
    func filingPhase() async {
        let model = validBug()
        model.submit(
            session: session(ScriptedTransport(submit: accepted(), statuses: [job("queued")])),
            platform: .ios
        )
        await waitUntil { model.isFiling }
        #expect(model.isFiling)
        #expect(model.isBusy)
        #expect(!model.isSubmitting)
        #expect(!model.canSubmit)
        model.cancelSubmit()
        #expect(model.isFiling)
        model.discardMedia()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.isFiling)
    }

    @Test("A failed job returns to the form with a message")
    func jobFailed() async {
        let model = validBug()
        model.submit(
            session: session(ScriptedTransport(submit: accepted(), statuses: [job("failed")])),
            platform: .ios
        )
        await waitUntil { if case .failed = model.phase { true } else { false } }
        #expect(model.phase == .failed(FeedbackError.filingFailed.errorDescription ?? ""))
        model.acknowledgeFailure()
        #expect(model.canSubmit)
        #expect(model.title == "[Bug] Crash")
    }

    @Test(
        "An outcome the app can't follow reads as received",
        arguments: [
            "no ID", "unknown job", "status reads keep failing", "wait ran out",
        ]
    )
    func received(scenario: String) async {
        let model = validBug(timeout: scenario == "wait ran out" ? .milliseconds(30) : .seconds(60))
        let transport: ScriptedTransport
        switch scenario {
        case "no ID":
            transport = ScriptedTransport(
                submit: HTTPResult(status: 202, data: Data("{}".utf8)), statuses: [job("queued")]
            )
        case "unknown job":
            transport = ScriptedTransport(
                submit: accepted(),
                statuses: [.success(HTTPResult(status: 404, data: Data(#"{"code":"not_found"}"#.utf8)))]
            )
        case "status reads keep failing":
            transport = ScriptedTransport(
                submit: accepted(), statuses: [.failure(URLError(.notConnectedToInternet))]
            )
        default:
            transport = ScriptedTransport(submit: accepted(), statuses: [job("processing")])
        }
        model.submit(session: session(transport), platform: .ios)
        await waitUntil { if case .finished = model.phase { true } else { false } }
        #expect(model.phase == .finished(.received))
        if scenario == "status reads keep failing" {
            #expect(await transport.statusReads == FeedbackFormModel.pollFailureAllowance)
        }
    }

    @Test("One lost status read does not end the wait")
    func transientStatusFailure() async {
        let model = validBug()
        let transport = ScriptedTransport(
            submit: accepted(),
            statuses: [.failure(URLError(.timedOut)), job("submitted", issue: 8)]
        )
        model.submit(session: session(transport), platform: .ios)
        await waitUntil { if case .finished = model.phase { true } else { false } }
        #expect(model.phase == .finished(.filed(issueNumber: 8, skipped: 0)))
    }

    @Test("A refused submit keeps the input and can be acknowledged")
    func submitFails() async {
        let model = validBug()
        let busy = HTTPResult(
            status: 503, data: Data(#"{"error":"x","code":"feedback_busy"}"#.utf8),
            headers: ["Retry-After": "60"]
        )
        model.submit(session: session(CannedTransport(result: .success(busy))), platform: .macos)
        await waitUntil { !model.isSubmitting }
        #expect(model.phase == .failed(FeedbackError.busy.errorDescription ?? ""))
        #expect(model.title == "[Bug] Crash")
        model.acknowledgeFailure()
        #expect(model.phase == .editing)
        #expect(model.canSubmit)
    }

    @Test("Network failures and a broken client read as connection errors")
    func submitNetwork() async {
        let offline = validBug()
        offline.submit(
            session: session(CannedTransport(result: .failure(URLError(.notConnectedToInternet)))),
            platform: .ipados
        )
        await waitUntil { !offline.isSubmitting }
        #expect(offline.phase == .failed(FeedbackError.network.errorDescription ?? ""))

        let broken = validBug()
        broken.submit(
            session: FestivalSession(factory: { throw FestivalAPIError.insecureBaseURL }),
            platform: .ios
        )
        await waitUntil { !broken.isSubmitting }
        #expect(broken.phase == .failed(FeedbackError.network.errorDescription ?? ""))
    }

    @Test("Stop Sending returns to editing and a late reply is ignored")
    func cancelSubmit() async {
        let model = validBug()
        model.submit(session: session(HangingTransport()), platform: .iphoneDuo)
        #expect(model.isSubmitting)
        model.cancelSubmit()
        #expect(model.phase == .editing)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .editing)
        #expect(model.hasUnsavedInput)
    }

    @Test("An invalid draft does not submit")
    func invalidDoesNotSubmit() {
        let model = FeedbackFormModel(kind: .bug)
        model.submit(session: session(HangingTransport()), platform: .ios)
        #expect(model.phase == .editing)
    }

    @Test("Client info names the OS version and device")
    func clientInfo() {
        #expect(FeedbackFormModel.osVersion.hasPrefix("macOS ") || FeedbackFormModel.osVersion.contains("OS "))
        #expect(FeedbackFormModel.clientInfo.hasPrefix(FeedbackFormModel.osVersion + "; "))
    }

    @Test("Closing the sheet purges every staged copy")
    func purge() async throws {
        let source = try sourceImage("shot.png")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let model = FeedbackFormModel(kind: .bug)
        await model.importFiles(.success([source]))
        let copy = try #require(model.attachments.first?.fileURL)
        FeedbackFormModel.purgeStagedMedia()
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: FeedbackPickedMedia.stagingFolder.path))
    }
}
