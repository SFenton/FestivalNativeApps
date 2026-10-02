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
private func validBug() -> FeedbackFormModel {
    let model = FeedbackFormModel(kind: .bug)
    model.title = "[Bug] Crash"
    model.descriptionText = "Boom"
    return model
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Tests

@Suite("Feedback form model")
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

    @Test("Documents, a sixth file and importer failures are refused with a reason")
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

        let clips = try (1...6).map { try sourceImage("shot\($0).png") }
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

    @Test("A successful submit ends with the receipt")
    func submitSucceeds() async {
        let model = validBug()
        let body = Data(#"{"issueNumber":3,"issueUrl":"https://github.com/o/r/issues/3"}"#.utf8)
        model.submit(
            session: session(CannedTransport(result: .success(HTTPResult(status: 201, data: body)))),
            platform: .ios
        )
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        await waitUntil { !model.isSubmitting }
        guard case let .succeeded(receipt) = model.phase else {
            Issue.record("expected success, got \(model.phase)")
            return
        }
        #expect(receipt.issueNumber == 3)
    }

    @Test("A failed submit keeps the input and can be acknowledged")
    func submitFails() async {
        let model = validBug()
        model.submit(
            session: session(CannedTransport(result: .success(HTTPResult(status: 503, data: Data())))),
            platform: .macos
        )
        await waitUntil { !model.isSubmitting }
        #expect(model.phase == .failed(FeedbackError.unavailable.errorDescription ?? ""))
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

    @Test("The OS version names the platform")
    func osVersion() {
        #expect(FeedbackFormModel.osVersion.hasPrefix("macOS ") || FeedbackFormModel.osVersion.contains("OS "))
    }
}
