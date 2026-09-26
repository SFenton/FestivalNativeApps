import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FestivalCore

private let pathPublication = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

private let unpinnedPathPublication = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
""".utf8)

private let pathJSON = Data("""
{"schemaVersion":2,"songName":"Fixture Pulse","artist":"Synthetic Quartet",
"charter":"Fixture","difficulty":"expert","totalScore":9000,
"pathSummary":"Two synthetic activations","activations":[
  {"startBeat":5,"endBeat":7,"activationBeat":5.5,"activationSeconds":2.75,
   "anchorBeat":5,"odAtActivation":0.75,"scoreBeforeActivation":123,
   "instruction":"Begin at the synthetic chord"},
  {"startBeat":11.5,"endBeat":15,"startNotes":[
    {"beat":11,"seconds":6,"cumulativeScore":700,"noteValue":10,
     "odPercent":0.3,"isSpGranting":false}
  ]}
],"notes":[
  {"beat":5,"seconds":2.5,"isSpNote":true,"frets":{"green":0.1,"red":0.2}},
  {"beat":11,"seconds":6,"isSpNote":false,"frets":{"open":0.5}}
]}
""".utf8)

/// Encode an original one-color image without bundling a song chart.
///
/// - Returns: Valid in-memory 8x8 PNG fixture.
/// - Throws: A fixture-generation failure rather than an empty image.
private func pathTestPNG() throws -> Data {
    guard let context = CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw FestivalAPIError.invalidPathImage }
    context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    guard let image = context.makeImage() else { throw FestivalAPIError.invalidPathImage }
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

@Test func songPathURLsKeepGenerationAndRejectUnsupportedCharts() throws {
    let origin = URL(string: "https://festivalscoretracker.com")!
    let text = try PublicEndpoint.path(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert,
        display: .text, generationId: "revision + 1"
    ).url(relativeTo: origin)
    let image = try PublicEndpoint.path(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert,
        display: .image
    ).url(relativeTo: origin)
    #expect(text.path == "/api/paths/fixture-pulse/Solo_Guitar/expert/data")
    #expect(URLComponents(url: text, resolvingAgainstBaseURL: false)?
        .queryItems?.first?.value == "revision + 1")
    #expect(image.path == "/api/paths/fixture-pulse/Solo_Guitar/expert")
    #expect(image.query == nil)
    for invalid in ["", "../outside", "inside/path"] {
        #expect(throws: FestivalAPIError.invalidResource) {
            try PublicEndpoint.path(
                songId: invalid, instrument: .lead, difficulty: .expert,
                display: .text
            ).url(relativeTo: origin)
        }
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.path(
            songId: "fixture-pulse", instrument: .karaoke,
            difficulty: .expert, display: .image
        ).url(relativeTo: origin)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.path(
            songId: "fixture-pulse", instrument: .lead, difficulty: .hard,
            display: .text, generationId: ""
        ).url(relativeTo: origin)
    }
    let song = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Pulse","artist":"Fixture",
     "pathArtifactGenerationId":"revision + 1"}
    """.utf8))
    #expect(song.pathArtifactGenerationId == "revision + 1")
    #expect(PathDifficulty.allCases.map(\.label) == ["Easy", "Medium", "Hard", "Expert"])
    #expect(PathDisplayMode.allCases.map(\.label) == ["Image", "Text"])
}

@Test func songPathRowsMatchAnchorsAndValidateNumericData() throws {
    let data = try JSONDecoder().decode(SongPathData.self, from: pathJSON)
    try data.validate(for: .expert)
    let rows = data.activationRows()
    #expect(rows.count == 2)
    #expect(rows[0].number == 1)
    #expect(rows[0].frets == ["green", "red"])
    #expect(rows[0].beat == 5.5)
    #expect(rows[0].seconds == 2.75)
    #expect(rows[0].odPercent == 75)
    #expect(rows[0].scoreBeforeActivation == 123)
    #expect(rows[1].number == 2)
    #expect(rows[1].frets == ["open"])
    #expect(rows[1].odPercent == 30)
    #expect(rows[1].scoreBeforeActivation == 700)
    #expect(throws: FestivalAPIError.invalidPathData) {
        try data.validate(for: .hard)
    }
    for (old, replacement) in [
        ("\"totalScore\":9000", "\"totalScore\":0"),
        ("\"schemaVersion\":2", "\"schemaVersion\":3"),
        ("\"odAtActivation\":0.75", "\"odAtActivation\":1.5"),
        ("\"green\":0.1", "\"unknown\":0.1"),
        ("\"activationSeconds\":2.75", "\"activationSeconds\":1e100"),
        ("\"anchorBeat\":5", "\"anchorBeat\":1e100"),
    ] {
        let changed = Data(
            String(decoding: pathJSON, as: UTF8.self)
                .replacingOccurrences(of: old, with: replacement).utf8
        )
        let invalid = try JSONDecoder().decode(SongPathData.self, from: changed)
        #expect(throws: FestivalAPIError.invalidPathData) {
            try invalid.validate(for: .expert)
        }
    }
    #expect(FestivalAPIError.invalidPathData.errorDescription?.contains("path data") == true)
    #expect(FestivalAPIError.invalidPathImage.errorDescription?.contains("path image") == true)
}

@Test func songPathTextPinsPublicationAndReusesSafeETag() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: pathPublication),
        HTTPResult(status: 200, data: pathJSON, headers: [
            "X-FST-Publication-Id": "7", "ETag": "\"path-revision\"",
        ]),
        HTTPResult(status: 304, data: Data(), headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await client.pathData(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert,
        generationId: "fixture-generation"
    )
    let second = try await client.pathData(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert,
        generationId: "fixture-generation"
    )
    #expect(first.path.activations.count == 2)
    #expect(first.rows.map(\.frets) == [["green", "red"], ["open"]])
    #expect(first.publicationId == 7)
    #expect(!second.isStale)
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[1].url?.path == "/api/paths/fixture-pulse/Solo_Guitar/expert/data")
    #expect(requests[1].url?.query == "generationId=fixture-generation")
    #expect(requests[1].value(forHTTPHeaderField: "X-FST-Publication-Id") == "7")
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == "\"path-revision\"")
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-API-Key") == nil })
}

@Test func songPathTextRejectsInvalidBytesBeforeWarmOffline() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPathPublication)),
        .success(HTTPResult(status: 200, data: Data("{\"invalid\":true}".utf8))),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidPathData) {
        try await client.pathData(
            songId: "fixture-pulse", instrument: .lead, difficulty: .expert
        )
    }
    await #expect(throws: URLError.self) {
        try await client.pathData(
            songId: "fixture-pulse", instrument: .lead, difficulty: .expert
        )
    }
}

@Test func songPathImageDecodesAndStaysProcessOnlyOnWarmLoss() async throws {
    let png = try pathTestPNG()
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPathPublication)),
        .success(HTTPResult(status: 200, data: png)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    let image = try await client.pathImage(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert
    )
    #expect(image.image.width == 8 && image.image.height == 8)
    #expect(image.publicationId == nil)
    let offline = try await client.pathImage(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert
    )
    #expect(offline.isStale && offline.observedPublicationId == 7)
    #expect(offline.publicationId == nil)
    await #expect(throws: FestivalAPIError.invalidPathImage) {
        try await SongPathImageDecoding.prepare(Data("not a PNG".utf8))
    }
    await #expect(throws: FestivalAPIError.invalidPathImage) {
        try await SongPathImageDecoding.prepare(Data(repeating: 0, count: 8_000_001))
    }
}

@Test func songPathImageRejectsInvalidBytesBeforeWarmOffline() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPathPublication)),
        .success(HTTPResult(status: 200, data: Data("not a PNG".utf8))),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidPathImage) {
        try await client.pathImage(
            songId: "fixture-pulse", instrument: .lead, difficulty: .expert
        )
    }
    await #expect(throws: URLError.self) {
        try await client.pathImage(
            songId: "fixture-pulse", instrument: .lead, difficulty: .expert
        )
    }
}

@Test func songPathImagePinsAndSafelyRevalidatesVerifiedBytes() async throws {
    let png = try pathTestPNG()
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: pathPublication),
        HTTPResult(status: 200, data: png, headers: [
            "X-FST-Publication-Id": "7", "ETag": "\"image-revision\"",
        ]),
        HTTPResult(status: 304, data: Data(), headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await client.pathImage(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert
    )
    let second = try await client.pathImage(
        songId: "fixture-pulse", instrument: .lead, difficulty: .expert
    )
    #expect(first.publicationId == 7 && second.publicationId == 7)
    #expect(second.image.width == 8 && !second.isStale)
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[1].url?.path == "/api/paths/fixture-pulse/Solo_Guitar/expert")
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == "\"image-revision\"")
}

@Test func songPathImageOversizeCannotEnterPinnedCache() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: pathPublication)),
        .success(HTTPResult(
            status: 200, data: Data(repeating: 0, count: 8_000_001),
            headers: ["X-FST-Publication-Id": "7", "ETag": "\"oversized\""]
        )),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidPathImage) {
        try await client.pathImage(
            songId: "fixture-pulse", instrument: .lead, difficulty: .expert
        )
    }
    await #expect(throws: URLError.self) {
        try await client.pathImage(
            songId: "fixture-pulse", instrument: .lead, difficulty: .expert
        )
    }
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
}
