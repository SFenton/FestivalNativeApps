import CoreGraphics
import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Page resolution

/// The newest appeared, visible page wins; hidden or disappeared pages never do.
@Test func backgroundWinnerIsNewestVisibleAppearedPage() {
    let a = UUID(), b = UUID(), c = UUID()
    let entries: [UUID: FestivalBackgroundRegistration] = [
        a: .init(mode: .carousel, visible: true, appeared: true, stamp: 1),
        b: .init(mode: .song("x"), visible: false, appeared: true, stamp: 3),
        c: .init(mode: .song("y"), visible: true, appeared: false, stamp: 4),
    ]
    #expect(FestivalBackgroundCoordinator.winner(of: entries) == a)
    #expect(FestivalBackgroundCoordinator.winner(of: [:]) == nil)
}

/// Push (detail appears before the list disappears) and pop resolve correctly.
@MainActor
@Test func pushAndPopResolveToTheTopPage() {
    let coordinator = FestivalBackgroundCoordinator(session: FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }
    ))
    let songs = UUID(), detail = UUID()
    coordinator.appear(songs, mode: .carousel, visible: true)
    #expect(coordinator.resolvedMode == .carousel)
    // Push: Songs' own visibility drops first, then Detail appears.
    coordinator.update(songs, mode: .carousel, visible: false)
    #expect(coordinator.resolvedMode == .carousel)  // sticky during the gap
    coordinator.appear(detail, mode: .song("art.png"), visible: true)
    #expect(coordinator.resolvedMode == .song("art.png"))
    #expect(coordinator.topToken == detail)
    #expect(coordinator.isCovered(songs))
    #expect(!coordinator.isCovered(detail))
    // Pop: Songs becomes visible again (fresh stamp) before Detail disappears.
    coordinator.update(songs, mode: .carousel, visible: true)
    #expect(coordinator.resolvedMode == .carousel)
    coordinator.disappear(detail)
    #expect(coordinator.resolvedMode == .carousel)
    #expect(coordinator.topToken == songs)
}

/// Tab switches: the newly shown tab wins even if the old one disappears later.
@MainActor
@Test func tabSwitchResolvesToTheNewTabAndStaysStickyWhenEmpty() {
    let coordinator = FestivalBackgroundCoordinator(session: FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }
    ))
    let detail = UUID(), leaderboards = UUID()
    coordinator.appear(detail, mode: .song("a.png"), visible: true)
    coordinator.appear(leaderboards, mode: .carousel, visible: true)
    #expect(coordinator.resolvedMode == .carousel)
    coordinator.disappear(detail)
    coordinator.disappear(leaderboards)
    #expect(coordinator.resolvedMode == .carousel)
    #expect(coordinator.topToken == nil)
    // Returning to the Songs tab re-appears Detail.
    coordinator.appear(detail, mode: .song("a.png"), visible: true)
    #expect(coordinator.resolvedMode == .song("a.png"))
    // A page changing its declared art updates the shared mode.
    coordinator.update(detail, mode: .song("b.png"), visible: true)
    #expect(coordinator.resolvedMode == .song("b.png"))
}

// MARK: - Tile origins

/// Tile frames are only offered while their carousel page is registered.
@MainActor
@Test func tileOriginsRequireALivePage() {
    let coordinator = FestivalBackgroundCoordinator(session: FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }
    ))
    let songs = UUID()
    let frame = CGRect(x: 16, y: 300, width: 44, height: 44)
    coordinator.noteTile("a.png", frame: frame, owner: songs)
    #expect(coordinator.sourceFrame(for: "a.png") == nil)
    coordinator.appear(songs, mode: .carousel, visible: true)
    #expect(coordinator.sourceFrame(for: "a.png") == frame)
    coordinator.forgetTile("a.png", owner: UUID())
    #expect(coordinator.sourceFrame(for: "a.png") == frame)
    coordinator.disappear(songs)
    #expect(coordinator.sourceFrame(for: "a.png") == nil)
}

// MARK: - Cover transitions

/// Showing a cover keeps the carousel running until settled; dismissing resumes it.
@MainActor
@Test func overlayLifecyclePausesAndResumesTheCarousel() {
    let coordinator = FestivalBackgroundCoordinator(session: FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }
    ))
    let first = SongOverlay(raw: "a", image: nil, origin: nil, start: .now, style: .dissolve)
    coordinator.showOverlay(first)
    #expect(coordinator.overlay == first && coordinator.overlayAnimating)
    #expect(coordinator.carouselVisible)
    coordinator.settle()
    #expect(!coordinator.carouselVisible && !coordinator.overlayAnimating)
    let second = SongOverlay(raw: "b", image: nil, origin: nil, start: .now, style: .plain)
    coordinator.showOverlay(second)
    #expect(coordinator.exiting?.overlay == first && coordinator.overlay == second)
    #expect(!coordinator.carouselVisible)
    coordinator.dismissOverlay()
    #expect(coordinator.overlay == nil && coordinator.exiting?.overlay == second)
    #expect(coordinator.carouselVisible && coordinator.overlayAnimating)
    coordinator.settle()
    #expect(coordinator.exiting == nil && coordinator.carouselVisible)
}

/// Entrance and exit progress are eased, clamped functions of time.
@Test func overlayProgressIsClampedAndEased() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let cover = SongOverlay(raw: "a", image: nil, origin: nil, start: start, style: .zoom)
    #expect(cover.progress(at: start.addingTimeInterval(-1)) == 0)
    #expect(abs(cover.progress(at: start.addingTimeInterval(0.275)) - 0.5) < 1e-9)
    #expect(cover.progress(at: start.addingTimeInterval(5)) == 1)
    #expect(cover.progress(at: .distantFuture) == 1)
    let exit = ExitingOverlay(overlay: cover, start: start)
    #expect(exit.progress(at: start.addingTimeInterval(ExitingOverlay.duration)) == 1)
    #expect(BackdropEasing.inOut(0.25) < 0.25 && BackdropEasing.inOut(0.75) > 0.75)
}

/// The cover interpolates from its tile frame to the full canvas.
@Test func placementInterpolatesFromTileToFullScreen() {
    let size = CGSize(width: 400, height: 800)
    let tile = CGRect(x: 20, y: 100, width: 40, height: 40)
    #expect(SongBackdropPlacement.frame(progress: 0, origin: tile, size: size) == tile)
    #expect(SongBackdropPlacement.frame(progress: 1, origin: tile, size: size)
        == CGRect(origin: .zero, size: size))
    #expect(SongBackdropPlacement.frame(progress: 0.5, origin: tile, size: size)
        == CGRect(x: 10, y: 50, width: 220, height: 420))
    #expect(SongBackdropPlacement.frame(progress: 0.3, origin: nil, size: size)
        == CGRect(origin: .zero, size: size))
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
    #expect(ArtworkBackdropCanvas.localOrigin(tile, in: bounds) == tile)
    #expect(ArtworkBackdropCanvas.localOrigin(
        CGRect(x: 500, y: 0, width: 40, height: 40), in: bounds
    ) == nil)
    #expect(ArtworkBackdropCanvas.maxPixels(
        for: CGSize(width: 402, height: 874), displayScale: 3
    ) == 1024)
}

// MARK: - Timestamped carousel state

/// Pausing keeps the zoom/pan fraction and resuming continues from it.
@Test func carouselMotionPausesAndResumesWithoutJumping() throws {
    let image = try #require(CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )?.makeImage())
    let start = Date(timeIntervalSinceReferenceDate: 5_000)
    var state = ArtworkBackdropState()
    state.show(image, raw: "a", now: start)
    #expect(state.layers[0].fadeOpacity(at: start) == 0)
    #expect(state.layers[0].fadeOpacity(at: start.addingTimeInterval(1)) == 1)
    state.startMotion(ArtworkMotionPreset.all[0], now: start)
    #expect(state.animating)
    #expect(abs(state.layers[0].fraction(at: start.addingTimeInterval(3)) - 0.5) < 1e-9)
    state.pauseMotion(now: start.addingTimeInterval(3))
    #expect(!state.animating)
    #expect(state.layers[0].fraction(at: start.addingTimeInterval(60)) == 0.5)
    let later = start.addingTimeInterval(100)
    state.resumeMotion(or: ArtworkMotionPreset.all[3], now: later)
    #expect(state.layers[0].motion == ArtworkMotionPreset.all[0])
    #expect(state.layers[0].fraction(at: later) == 0.5)
    #expect(state.layers[0].fraction(at: later.addingTimeInterval(3)) == 1)
    let value = ArtworkMotionPreset.all[0].value(at: 0.5)
    #expect(abs(value.scale - 1.06) < 0.0001)
}

// MARK: - Session wiring

/// One coordinator per live session, and the carousel loads without Songs.
@MainActor
@Test func sessionOwnsOneCoordinatorAndLoadsCarouselIndependently() async throws {
    let client = try FestivalAPI(transport: ArtworkPoolTransport())
    let session = FestivalSession(factory: { client })
    let other = FestivalSession(factory: { client })
    #expect(session.backgroundCoordinator === session.backgroundCoordinator)
    #expect(session.backgroundCoordinator !== other.backgroundCoordinator)
    #expect(session.artworkPaths.isEmpty)
    await session.loadArtworkCatalogIfNeeded(grace: .zero)
    #expect(session.artworkPaths.count == 100)
}
