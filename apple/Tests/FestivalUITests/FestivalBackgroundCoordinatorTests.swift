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

// MARK: - Cover transitions

/// Showing a cover keeps the carousel running until settled; dismissing resumes it.
@MainActor
@Test func overlayLifecyclePausesAndResumesTheCarousel() {
    let coordinator = FestivalBackgroundCoordinator(session: FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }
    ))
    let first = SongOverlay(raw: "a", image: nil, start: .now)
    coordinator.showOverlay(first)
    #expect(coordinator.overlay == first && coordinator.carouselVisible)
    coordinator.settle()
    #expect(!coordinator.carouselVisible)
    let second = SongOverlay(raw: "b", image: nil, start: .now)
    coordinator.showOverlay(second)
    #expect(coordinator.exiting?.overlay == first && coordinator.overlay == second)
    #expect(!coordinator.carouselVisible)
    coordinator.dismissOverlay()
    #expect(coordinator.overlay == nil && coordinator.exiting?.overlay == second)
    #expect(coordinator.carouselVisible)
    coordinator.settle()
    #expect(coordinator.exiting == nil && coordinator.carouselVisible)
}

/// The cover fades like the web's `BackgroundImage`: opacity over 300 ms on CSS `ease`.
@Test func coverFadeMatchesWebTiming() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let cover = SongOverlay(raw: "a", image: nil, start: start)
    #expect(SongOverlay.fadeDuration == 0.3)
    #expect(cover.opacity(at: start.addingTimeInterval(-1)) == 0)
    #expect(cover.opacity(at: start.addingTimeInterval(0.3)) == 1)
    #expect(cover.opacity(at: .distantFuture) == 1)
    // CSS `ease` at half time is ~0.8024 (front-loaded, unlike ease-in-out).
    #expect(abs(cover.opacity(at: start.addingTimeInterval(0.15)) - 0.8024) < 0.001)
    let exit = ExitingOverlay(overlay: cover, start: start.addingTimeInterval(1))
    #expect(exit.from == 1)
    #expect(exit.opacity(at: start.addingTimeInterval(1)) == 1)
    #expect(exit.opacity(at: start.addingTimeInterval(1.3)) == 0)
    #expect(BackdropEasing.inOut(0.25) < 0.25 && BackdropEasing.inOut(0.75) > 0.75)
}

/// An exit that interrupts an entrance fades out from the entrance's opacity, and
/// the leaving cover keeps its layer identity (no restart, no jump).
@Test func interruptedFadeExitsFromCurrentOpacity() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let cover = SongOverlay(raw: "a", image: nil, start: start)
    let exitAt = start.addingTimeInterval(0.1)
    let exit = ExitingOverlay(overlay: cover, start: exitAt)
    #expect(exit.from > 0 && exit.from < 1)
    #expect(abs(exit.opacity(at: exitAt) - cover.opacity(at: exitAt)) < 1e-12)
    let entering = CoverLayer.layers(overlay: cover, exiting: nil)
    let leaving = CoverLayer.layers(overlay: nil, exiting: exit)
    #expect(entering.map(\.id) == leaving.map(\.id))
    #expect(entering.first?.target == 1 && leaving.first?.target == 0)
    #expect(abs((leaving.first?.remaining(at: exitAt) ?? 0) - 0.3) < 1e-9)
    #expect(leaving.first?.remaining(at: exitAt.addingTimeInterval(1)) == 0)
    // Replacing one song with another stacks the leaving cover beneath.
    let next = SongOverlay(raw: "b", image: nil, start: exitAt)
    #expect(CoverLayer.layers(overlay: next, exiting: exit).map(\.id) == [cover.id, next.id])
}

/// CSS `cubic-bezier` evaluation is clamped, monotonic and hits its endpoints.
@Test func cubicBezierIsClampedAndMonotonic() {
    #expect(BackdropEasing.cssEase(-1) == 0 && BackdropEasing.cssEase(2) == 1)
    var previous = 0.0
    for step in 1...20 {
        let value = BackdropEasing.cssEase(Double(step) / 20)
        #expect(value >= previous)
        previous = value
    }
    #expect(abs(BackdropEasing.cubicBezier(0.5, x1: 0, y1: 0, x2: 1, y2: 1) - 0.5) < 1e-6)
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
