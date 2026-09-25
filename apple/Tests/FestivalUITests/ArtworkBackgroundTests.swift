import AppKit
import ImageIO
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// Decode the original fixture asset without contacting an artwork CDN.
///
/// - Returns: Immutable, synthetic artwork pixels.
/// - Throws: Missing or invalid fixture image.
private func fixtureCover() throws -> CGImage {
    let url = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

/// Return original PNG bytes or deliberate HTTP failures for named covers.
private actor ArtworkResponseTransport: HTTPTransport {
    let data: Data
    let failures: Set<String>
    let failFirstRequests: Int
    private var paths: [String] = []
    private var times: [ContinuousClock.Instant] = []

    /// Supply fully synthetic outcomes without any remote image requests.
    ///
    /// - Parameters:
    ///   - data: Original fixture PNG bytes.
    ///   - failures: Fixture route paths that respond with HTTP 404.
    ///   - failFirstRequests: Fail this many distinct requests regardless of shuffle order.
    init(data: Data, failures: Set<String>, failFirstRequests: Int = 0) {
        self.data = data
        self.failures = failures
        self.failFirstRequests = failFirstRequests
    }

    /// Record a bounded artwork request and reply with valid bytes or 404.
    ///
    /// - Parameter request: Loopback or synthetic CDN-shaped fixture art URL.
    /// - Returns: Image response or deliberate missing-cover error.
    /// - Throws: Unexpected artwork paths outside the two fixture namespaces.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let path = request.url?.path,
              (path.hasPrefix("/__fixture__/art/")
               && request.url?.host == "127.0.0.1")
                || (path.hasPrefix("/covers/cover-")
                    && request.url?.host == "cdn2.unrealengine.com") else {
            throw FestivalAPIError.invalidResource
        }
        paths.append(path)
        times.append(ContinuousClock().now)
        if failures.contains(path) || paths.count <= failFirstRequests {
            return HTTPResult(status: 404, data: Data())
        }
        return HTTPResult(
            status: 200, data: data, headers: ["Content-Type": "image/png"]
        )
    }

    /// Return request order for the failed-B-to-valid-C assertion.
    ///
    /// - Returns: Original synthetic artwork paths requested.
    func requestedPaths() -> [String] { paths }

    /// Return monotonic request instants for the paced retry assertions.
    ///
    /// - Returns: One timestamp for every synthetic artwork request.
    func requestTimes() -> [ContinuousClock.Instant] { times }
}

/// Readable five-second instants must not grow to six after the fade finishes.
@Test func artworkDeadlinesIncludeFadeWithoutAddingItToTheDwell() {
    let clock = ContinuousClock()
    let start = clock.now
    let first = ArtworkTransitionSchedule.deadline(
        after: start, ready: start.advanced(by: .seconds(1))
    )
    let second = ArtworkTransitionSchedule.deadline(
        after: first, ready: first.advanced(by: .seconds(1))
    )
    let third = ArtworkTransitionSchedule.deadline(
        after: second, ready: second.advanced(by: .seconds(1))
    )
    #expect(first == start.advanced(by: .seconds(5)))
    #expect(second == start.advanced(by: .seconds(10)))
    #expect(third == start.advanced(by: .seconds(15)))
    let late = ArtworkTransitionSchedule.deadline(
        after: first, ready: first.advanced(by: .seconds(7))
    )
    #expect(late == first.advanced(by: .seconds(7)))
    #expect(ArtworkTransitionSchedule.fade == .seconds(1))
    #expect(ArtworkTransitionSchedule.motion == .seconds(6))
}

/// The second cover's 404 must not prevent a valid third cover from staging.
@MainActor
@Test func badStandbyIsSkippedForValidFollowingArtwork() async throws {
    let url = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let paths = [
        "/__fixture__/art/a.png",
        "/__fixture__/art/b.png",
        "/__fixture__/art/c.png",
    ]
    let transport = ArtworkResponseTransport(
        data: try Data(contentsOf: url), failures: [paths[1]]
    )
    let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:8765")!)
    let session = FestivalSession(
        factory: { client }, artwork: ArtworkCache(transport: transport)
    )
    let background = ArtworkBackground(
        mode: .carousel, session: session, saveDataOverride: false
    )
    let prepared = try await background.preloadNext(
        after: 0, paths: paths, maxPixels: 64, excluding: []
    )
    #expect(prepared.next?.index == 2)
    #expect(prepared.rejected == [paths[1]])
    #expect(await transport.requestedPaths() == [
        paths[1], paths[2],
    ])
}

/// A broken CDN receives at most five attempts per publication pool.
@MainActor
@Test func allBadStandbysStopAfterBoundedAttempts() async throws {
    let url = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let paths = (0..<7).map { "/__fixture__/art/\($0).png" }
    let transport = ArtworkResponseTransport(
        data: try Data(contentsOf: url), failures: Set(paths[1...5])
    )
    let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:8765")!)
    let session = FestivalSession(
        factory: { client }, artwork: ArtworkCache(transport: transport)
    )
    let background = ArtworkBackground(
        mode: .carousel, session: session, saveDataOverride: false
    )
    let first = try await background.preloadNext(
        after: 0, paths: paths, maxPixels: 64, excluding: []
    )
    #expect(first.next == nil && first.rejected.count == 3)
    let second = try await background.preloadNext(
        after: 0, paths: paths, maxPixels: 64, excluding: first.rejected
    )
    #expect(second.next == nil && second.rejected.count == 2)
    let rejected = first.rejected.union(second.rejected)
    let third = try await background.preloadNext(
        after: 0, paths: paths, maxPixels: 64, excluding: rejected
    )
    #expect(third.next == nil && third.rejected.isEmpty)
    #expect((await transport.requestedPaths()).count == 5)
}

/// A 100-cover offline failure must not spray 100 sequential CDN requests.
@MainActor
@Test func firstArtworkFailureCapsRequestsBeforeShowingBrandSurface() async throws {
    let url = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let failures = Set((0..<105).map { "/covers/cover-\($0).png" })
    let transport = ArtworkResponseTransport(
        data: try Data(contentsOf: url), failures: failures
    )
    let client = try FestivalAPI(transport: ArtworkPoolTransport())
    let session = FestivalSession(
        factory: { client }, artwork: ArtworkCache(transport: transport)
    )
    _ = try await session.catalog()
    #expect(session.artworkPaths.count == 100)
    let renderer = ImageRenderer(content: ArtworkBackground(
        mode: .carousel, session: session, saveDataOverride: false
    ).environment(\.scenePhase, .active).frame(width: 320, height: 568))
    renderer.scale = 1
    _ = try #require(renderer.cgImage)
    for _ in 0..<20 {
        if (await transport.requestedPaths()).count == 3 { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect((await transport.requestedPaths()).count == 3)
    try await Task.sleep(for: .milliseconds(100))
    #expect((await transport.requestedPaths()).count == 3)
}

/// Three failed covers cannot hide a valid fourth; five failed covers exhaust the pool.
@MainActor
@Test(arguments: [3, 5])
func initialArtworkFailuresRetryAfterDwellAndStopAtPoolLimit(
    failedRequests: Int
) async throws {
    let url = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let transport = ArtworkResponseTransport(
        data: try Data(contentsOf: url), failures: [],
        failFirstRequests: failedRequests
    )
    let client = try FestivalAPI(transport: ArtworkPoolTransport())
    let session = FestivalSession(
        factory: { client }, artwork: ArtworkCache(transport: transport)
    )
    _ = try await session.catalog()
    let renderer = ImageRenderer(content: ArtworkBackground(
        mode: .carousel, session: session, saveDataOverride: false
    ).environment(\.scenePhase, .active).frame(width: 320, height: 568))
    renderer.scale = 1
    func snapshot() throws -> Data {
        let image = try #require(renderer.cgImage)
        return try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
    }
    let blank = try snapshot()
    for _ in 0..<40 where (await transport.requestedPaths()).count < 3 {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect((await transport.requestedPaths()).count == 3)
    #expect(try snapshot() == blank)
    try await Task.sleep(for: .milliseconds(150))
    #expect((await transport.requestedPaths()).count == 3)

    var visible = blank
    for _ in 0..<160 {
        visible = try snapshot()
        let count = (await transport.requestedPaths()).count
        if count >= (failedRequests == 3 ? 4 : 5)
            && (failedRequests == 5 || visible != blank) {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    let paths = await transport.requestedPaths()
    let times = await transport.requestTimes()
    if failedRequests == 3 {
        #expect((4...5).contains(paths.count))
    } else {
        #expect(paths.count == 5)
    }
    #expect(Set(paths).count == paths.count)
    #expect(times.count == paths.count)
    if times.count > 3 {
        let delay = times[0].duration(to: times[3])
        #expect(delay >= .seconds(4.7))
        #expect(delay < .seconds(8))
    }
    if failedRequests == 3 {
        #expect(visible != blank)
    } else {
        #expect(visible == blank)
        try await Task.sleep(for: .milliseconds(5_500))
        #expect((await transport.requestedPaths()).count == 5)
    }
}

/// The original PWA uses ten bounded six-second zoom/pan presets.
@Test func artworkMotionPresetsStayWithinSourceGeometry() {
    #expect(ArtworkMotionPreset.all.count == 10)
    for preset in ArtworkMotionPreset.all {
        #expect((1...1.18).contains(preset.startScale))
        #expect((1...1.18).contains(preset.endScale))
        for offset in [
            preset.startX, preset.endX, preset.startY, preset.endY,
        ] {
            #expect((-18...18).contains(offset))
        }
    }
}

/// Crossfading never needs more than two decoded images or replaces an active slot.
@Test func backdropKeepsStableLayersAndReleasesHiddenArtwork() throws {
    let image = try fixtureCover()
    var state = ArtworkBackdropState()
    #expect(!state.hasImage)
    state.crossfade()
    #expect(state.active == 0 && !state.hasImage)
    state.show(image, raw: "first")
    #expect(state.currentRaw == "first")
    #expect(state.layers[0].visible)
    state.startMotion(ArtworkMotionPreset.all[0])
    #expect(state.layers[0].moving)
    state.startMotion(ArtworkMotionPreset.all[2])
    #expect(state.layers[0].motion == ArtworkMotionPreset.all[0])
    state.stage(image, raw: "second", motion: ArtworkMotionPreset.all[2])
    #expect(state.layers.filter { $0.image != nil }.count == 2)
    #expect(!state.layers[1].visible)
    state.crossfade()
    #expect(state.active == 1 && state.currentRaw == "second")
    #expect(!state.layers[0].visible && state.layers[1].moving)
    state.releaseHidden()
    #expect(state.layers[0].image == nil)
    #expect(state.layers[1].image != nil)
    state.pauseMotion()
    #expect(!state.layers[1].moving)
    state.clear()
    #expect(!state.hasImage && state.layers.allSatisfy { $0.image == nil })
}

/// Data Saver must remove both the cover and dim layer rather than downloading.
@MainActor
@Test func artworkBackdropDimsRealPixelsButDataSavingUsesTheBaseSurface() throws {
    let image = try fixtureCover()
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    func snapshot(preview: CGImage?, constrained: Bool) throws -> Data {
        let renderer = ImageRenderer(content: ArtworkBackground(
            mode: .song("/__fixture__/art/pulse.png"), session: session,
            previewImage: preview, saveDataOverride: constrained
        ).frame(width: 320, height: 568))
        renderer.scale = 1
        let rendered = try #require(renderer.cgImage)
        return try #require(
            NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
        )
    }
    let shown = try snapshot(preview: image, constrained: false)
    let saved = try snapshot(preview: image, constrained: true)
    let noArt = try snapshot(preview: nil, constrained: true)
    #expect(shown != saved)
    #expect(saved == noArt)

    let blankRenderer = ImageRenderer(content: ArtworkBackground(
        mode: .song(nil), session: session, saveDataOverride: false
    ).frame(width: 320, height: 568))
    blankRenderer.scale = 1
    let blankImage = try #require(blankRenderer.cgImage)
    let blank = try #require(
        NSBitmapImageRep(cgImage: blankImage).representation(using: .png, properties: [:])
    )
    #expect(blank == saved)
}

/// In-app contrast and transparency toggles must alter composited artwork.
@MainActor
@Test func artworkOverridesAlterHostedPagePixels() throws {
    let suiteName = "fst.artwork-visual.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    defer { preferences.removePersistentDomain(forName: suiteName) }
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let image = try fixtureCover()
    func snapshot(preview: CGImage?) throws -> Data {
        let content = ArtworkBackground(
            mode: .song("/__fixture__/art/pulse.png"), session: session,
            previewImage: preview, saveDataOverride: false
        )
        let renderer = ImageRenderer(content: content.defaultAppStorage(preferences)
            .frame(width: 320, height: 568))
        renderer.scale = 1
        let rendered = try #require(renderer.cgImage)
        return try #require(
            NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
        )
    }
    let normal = try snapshot(preview: image)
    preferences.set(true, forKey: "fst.accessibility.moreContrast")
    let contrasted = try snapshot(preview: image)
    #expect(normal != contrasted)

    preferences.set(true, forKey: "fst.accessibility.lessTransparency")
    let opaque = try snapshot(preview: image)
    let blank = try snapshot(preview: nil)
    #expect(contrasted != opaque)
    #expect(opaque == blank)
}

/// The 100-cover catalogue feeds the same original art compositor as Detail.
@MainActor
@Test func carouselBackdropRendersCatalogArtWithoutPrefetchingOtherCovers() async throws {
    let client = try FestivalAPI(transport: ArtworkPoolTransport())
    let session = FestivalSession(factory: { client })
    _ = try await session.catalog()
    let image = try fixtureCover()
    func snapshot(constrained: Bool) throws -> Data {
        let renderer = ImageRenderer(content: ArtworkBackground(
            mode: .carousel, session: session, previewImage: image,
            saveDataOverride: constrained
        ).frame(width: 320, height: 568))
        renderer.scale = 1
        let rendered = try #require(renderer.cgImage)
        return try #require(
            NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
        )
    }
    let art = try snapshot(constrained: false)
    let saved = try snapshot(constrained: true)
    #expect(art != saved)
    #expect(session.artworkPaths.count == 100)
}

/// A hosted macOS static backdrop should load, decode and visibly dim fixture art.
@MainActor
@Test func liveStaticBackdropChangesRealRenderedPixels() async throws {
    let url = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let transport = ArtworkFixtureTransport(data: try Data(contentsOf: url))
    let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:8765")!)
    let session = FestivalSession(
        factory: { client }, artwork: ArtworkCache(transport: transport)
    )
    let renderer = ImageRenderer(content: ArtworkBackground(
        mode: .song("/__fixture__/art/pulse.png"), session: session,
        saveDataOverride: false
    ).environment(\.scenePhase, .active).frame(width: 320, height: 568))
    renderer.scale = 1
    func snapshot() throws -> Data {
        let image = try #require(renderer.cgImage)
        return try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
    }
    let initial = try snapshot()
    var updated = initial
    for _ in 0..<20 where updated == initial {
        try await Task.sleep(for: .milliseconds(50))
        updated = try snapshot()
    }
    #expect(updated != initial)
    #expect(await transport.requestCount() == 1)
}

/// Global-queue Low Power notifications must not break the live hosted view.
@MainActor
@Test func backdropReceivesBackgroundPowerNotificationOnTheMainQueue() async throws {
    let image = try fixtureCover()
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let renderer = ImageRenderer(content: ArtworkBackground(
        mode: .song("/__fixture__/art/pulse.png"), session: session,
        previewImage: image, saveDataOverride: false
    ).environment(\.scenePhase, .active).frame(width: 320, height: 568))
    renderer.scale = 1
    _ = try #require(renderer.cgImage)
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            NotificationCenter.default.post(
                name: .NSProcessInfoPowerStateDidChange, object: nil
            )
            continuation.resume()
        }
    }
    try await Task.sleep(for: .milliseconds(50))
    let after = try #require(renderer.cgImage)
    #expect(after.width == 320 && after.height == 568)
}
