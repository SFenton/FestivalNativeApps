#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

private actor HostedPathTransport: HTTPTransport {
    let text: Data
    let image: Data
    private var paths: [String] = []

    /// Serve only synthetic, publication-bound CHOpt artifact reads.
    ///
    /// - Parameters:
    ///   - text: Original local schema-2 fixture, never a downloaded path.
    ///   - image: Generated one-color PNG, not game artwork.
    init(text: Data, image: Data) {
        self.text = text
        self.image = image
    }

    /// Reject privileged or cross-chart requests instead of returning plausible data.
    ///
    /// - Parameter request: Public native GET to the isolated fake transport.
    /// - Returns: Fixture publication, typed text or an original generated image.
    /// - Throws: Invalid method, headers, generation, route or chart.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        guard url.query == "generationId=fixture-generation",
              request.value(forHTTPHeaderField: "X-FST-Publication-Id") == "7" else {
            throw FestivalAPIError.invalidPublication
        }
        let bytes: Data
        switch url.path {
        case "/api/paths/fixture-pulse/Solo_Guitar/expert/data":
            bytes = text
        case "/api/paths/fixture-pulse/Solo_Guitar/expert":
            bytes = image
        default:
            throw FestivalAPIError.invalidResource
        }
        paths.append(url.path)
        return HTTPResult(
            status: 200, data: bytes,
            headers: ["X-FST-Publication-Id": "7"]
        )
    }

    /// Confirm that the visible view actually requested its matching fixture artifact.
    ///
    /// - Returns: Ordered synthetic path URL paths, excluding publication reads.
    func recordedPaths() -> [String] { paths }
}

/// Decode the same original catalogue identity used by the device path fixture.
///
/// - Returns: A charted, revision-scoped synthetic Song.
/// - Throws: Incorrect local test schema.
private func hostedPathSong() throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse",
     "artist":"Synthetic Quartet","pathArtifactGenerationId":"fixture-generation"}
    """.utf8))
}

/// Generate an original solid-orange PNG to distinguish loaded art from picker blue.
///
/// - Returns: Valid bounded 240x180 image bytes generated wholly inside the test.
/// - Throws: Missing local graphics context, image or PNG destination.
private func hostedPathPNG() throws -> Data {
    guard let context = CGContext(
        data: nil, width: 240, height: 180, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw FestivalAPIError.invalidPathImage }
    context.setFillColor(CGColor(red: 0.95, green: 0.42, blue: 0.05, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
    guard let image = context.makeImage() else {
        throw FestivalAPIError.invalidPathImage
    }
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        bytes, "public.png" as CFString, 1, nil
    ) else { throw FestivalAPIError.invalidPathImage }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw FestivalAPIError.invalidPathImage
    }
    return bytes as Data
}

/// Distinguish real chart-note frets or generated art from selector-blue controls.
///
/// - Parameter image: Fully rendered AppKit Paths sheet after a bounded local read.
/// - Returns: Sampled green/red note marks and orange image pixels.
@MainActor
private func pathContentPixels(_ image: CGImage) -> (
    green: Int, red: Int, orange: Int
) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    var green = 0
    var red = 0
    var orange = 0
    for y in stride(from: 0, to: image.height, by: 4) {
        for x in stride(from: 0, to: image.width, by: 4) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let r = color.redComponent
            let g = color.greenComponent
            let b = color.blueComponent
            if g > 0.55 && g > r * 1.4 && g > b * 1.2 { green += 1 }
            if r > 0.55 && r > g * 1.5 && r > b * 1.4 { red += 1 }
            if r > 0.7 && g > 0.25 && g < 0.6 && b < 0.25 { orange += 1 }
        }
    }
    return (green, red, orange)
}

/// Horizontal extent of the generated orange path image in a rendered sheet.
///
/// - Parameter image: Fully rendered AppKit Paths sheet after a bounded local read.
/// - Returns: Leftmost and rightmost orange pixel columns, or nil when none painted.
@MainActor
private func orangeColumns(_ image: CGImage) -> (min: Int, max: Int)? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    var bounds: (min: Int, max: Int)?
    for y in stride(from: 0, to: image.height, by: 8) {
        var row: (min: Int, max: Int, count: Int)?
        for x in 0..<image.width {
            guard let color = bitmap.colorAt(x: x, y: y),
                  color.redComponent > 0.7, color.greenComponent > 0.25,
                  color.greenComponent < 0.6, color.blueComponent < 0.25 else { continue }
            row = (row?.min ?? x, x, (row?.count ?? 0) + 1)
        }
        // Only rows crossing the image itself, not small orange glyphs elsewhere.
        guard let row, row.count > 100 else { continue }
        bounds = (Swift.min(bounds?.min ?? row.min, row.min), Swift.max(bounds?.max ?? row.max, row.max))
    }
    return bounds
}

/// Native CHOpt selectors must paint real AppKit controls, not snapshot placeholders.
@MainActor
@Test func pathSheetPaintsNativeSelectorsAcrossWidthsAndTextSizes() throws {
    let song = try hostedPathSong()
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let cases: [(CGSize, PathDisplayMode, DynamicTypeSize, String)] = [
        (CGSize(width: 390, height: 844), .image, .large, "phone-image"),
        (CGSize(width: 820, height: 1180), .text, .large, "wide-text"),
        (CGSize(width: 390, height: 844), .text, .accessibility5, "phone-ax5-text"),
    ]
    var snapshots: [Data] = []
    for (size, display, typeSize, name) in cases {
        let host = nativeHostedView(
            SongPathsSheet(
                song: song, session: session, instruments: [.lead, .drums],
                firstInstrument: .lead, defaultDisplay: display,
                warnAboutKaraoke: false
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .environment(\.dynamicTypeSize, typeSize),
            size: size
        )
        let image = try nativeHostedImage(host)
        let scale = CGFloat(image.width) / size.width
        #expect((1...3).contains(scale))
        #expect(abs(CGFloat(image.height) / size.height - scale) < 0.02)
        let pixels = nativeHostedControlPixels(image)
        // Selectors are menu pickers in a bottom row now (no blue selected segment);
        // require painted white labels and no placeholder surface.
        #expect(pixels.bright > 20)
        #expect(pixels.placeholder == 0)
        snapshots.append(try nativeHostedPNG(
            image, filename: "paths-\(name).png",
            environment: "FST_PATH_RENDER_OUT"
        ))
    }
    #expect(snapshots[0] != snapshots[1])
    #expect(snapshots[0] != snapshots[2])
}

/// A real local text/image GET must paint activation marks or generated pixels.
///
/// Runs without animation: a windowless host never ticks SwiftUI animations, so the
/// switch fades (issue #70) would leave the path at its starting opacity. The fade
/// sequence itself is covered by `PathSwitchTransitionTests`.
@MainActor
@Test func pathSheetPaintsValidatedTextAndImageArtifacts() async throws {
    let song = try hostedPathSong()
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/path-demo.json")
    let transport = HostedPathTransport(
        text: try Data(contentsOf: fixture), image: try hostedPathPNG()
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })

    func loaded(_ display: PathDisplayMode, size: CGSize) async throws -> CGImage {
        let host = nativeHostedView(
            SongPathsSheet(
                song: song, session: session, instruments: [.lead, .drums],
                firstInstrument: .lead, defaultDisplay: display,
                warnAboutKaraoke: false
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .transaction { $0.animation = nil },
            size: size
        )
        var painted: CGImage?
        // The spinner stays up at least 400–500 ms before the path appears (issue #70).
        for _ in 0..<60 {
            let image = try nativeHostedImage(host)
            let pixels = pathContentPixels(image)
            if (display == .text && pixels.green > 10 && pixels.red > 10)
                || (display == .image && pixels.orange > 100) {
                painted = image
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try #require(painted, "Validated \(display.label) path never painted")
    }

    let textImage = try await loaded(.text, size: CGSize(width: 820, height: 1180))
    let textPixels = nativeHostedControlPixels(textImage)
    #expect(textPixels.bright > 20)
    #expect(await transport.recordedPaths()
        .contains("/api/paths/fixture-pulse/Solo_Guitar/expert/data"))
    _ = try nativeHostedPNG(
        textImage, filename: "paths-loaded-text.png",
        environment: "FST_PATH_RENDER_OUT"
    )

    let image = try await loaded(.image, size: CGSize(width: 390, height: 844))
    let imagePixels = nativeHostedControlPixels(image)
    #expect(imagePixels.bright > 20)
    #expect(await transport.recordedPaths()
        .contains("/api/paths/fixture-pulse/Solo_Guitar/expert"))
    // A path narrower than the sheet sits centred, with equal side margins (issue #87).
    let columns = try #require(orangeColumns(image))
    let scale = CGFloat(image.width) / 390
    let leftMargin = CGFloat(columns.min)
    let rightMargin = CGFloat(image.width - 1 - columns.max)
    #expect(abs(leftMargin - rightMargin) <= 2 * scale, "Margins \(leftMargin) vs \(rightMargin)")
    _ = try nativeHostedPNG(
        image, filename: "paths-loaded-image.png",
        environment: "FST_PATH_RENDER_OUT"
    )
}
#endif
