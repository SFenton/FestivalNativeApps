import CoreGraphics
import Foundation
import Observation
import OSLog
import SwiftUI

// MARK: - Background registrations

/// One page's declared background, tracked while that page is on screen.
struct FestivalBackgroundRegistration: Equatable {
    /// Background the page asked for.
    var mode: ArtworkBackgroundMode
    /// The page's own visibility input (false while covered in its own stack).
    var visible: Bool
    /// True between the page's `onAppear` and `onDisappear`.
    var appeared: Bool
    /// Monotonic order of the page's latest appearance or visibility gain.
    var stamp: Int
}

// MARK: - Coordinator

/// One shared backdrop per session: which page's mode wins, plus the single
/// carousel engine and song cover that every page mirrors.
///
/// Every `.festivalBackground(_:session:visible:)` call registers a token here.
/// The most recently appeared, still visible page wins, which resolves both
/// `TabView` switches and `NavigationStack` pushes/pops without the pages
/// knowing about each other: SwiftUI calls the incoming page's `onAppear`
/// before (or at the start of) the outgoing page's `onDisappear`. The shell's
/// `FestivalBackgroundHost` drives the engine and cover from `resolvedMode`.
@MainActor
@Observable
final class FestivalBackgroundCoordinator {
    /// Background of the page on top; sticky while no page is registered.
    private(set) var resolvedMode: ArtworkBackgroundMode = .carousel
    /// Token of the page whose background is shown, if any.
    private(set) var topToken: UUID?
    /// The one carousel, shared by every page for the whole process.
    let carousel: ArtworkCarouselEngine
    /// Song cover shown above the carousel, if a song page is on top.
    private(set) var overlay: SongOverlay?
    /// Cover dissolving away.
    private(set) var exiting: ExitingOverlay?
    /// False once a cover fully hides the carousel, pausing its motion and loads.
    private(set) var carouselVisible = true

    @ObservationIgnored
    private var settleTask: Task<Void, Never>?

    @ObservationIgnored
    private var registrations: [UUID: FestivalBackgroundRegistration] = [:]
    @ObservationIgnored
    private var nextStamp = 0

    /// Create the coordinator for one session.
    ///
    /// - Parameter session: Artwork cache owner for the shared carousel.
    init(session: FestivalSession) {
        carousel = ArtworkCarouselEngine(session: session)
    }

    // MARK: - Page lifecycle

    /// Record that a page became visible on screen.
    ///
    /// - Parameters:
    ///   - token: Stable identity of the page's modifier.
    ///   - mode: Background the page declares.
    ///   - visible: The page's own visibility input.
    func appear(_ token: UUID, mode: ArtworkBackgroundMode, visible: Bool) {
        nextStamp += 1
        registrations[token] = FestivalBackgroundRegistration(
            mode: mode, visible: visible, appeared: true, stamp: nextStamp
        )
        resolve()
    }

    /// Update a page's declared mode or visibility without re-ordering it,
    /// except that regaining visibility counts as a fresh appearance.
    ///
    /// - Parameters:
    ///   - token: Stable identity of the page's modifier.
    ///   - mode: Background the page declares.
    ///   - visible: The page's own visibility input.
    func update(_ token: UUID, mode: ArtworkBackgroundMode, visible: Bool) {
        guard var entry = registrations[token] else { return }
        if visible && !entry.visible {
            nextStamp += 1
            entry.stamp = nextStamp
        }
        entry.mode = mode
        entry.visible = visible
        registrations[token] = entry
        resolve()
    }

    /// Forget a page that left the screen.
    ///
    /// - Parameter token: Stable identity of the page's modifier.
    func disappear(_ token: UUID) {
        registrations[token] = nil
        resolve()
    }

    /// Whether a registered page is currently covered by a newer page.
    ///
    /// - Parameter token: Stable identity of the page's modifier.
    /// - Returns: True only when a different visible page owns the background.
    func isCovered(_ token: UUID) -> Bool {
        guard let topToken else { return false }
        return topToken != token && registrations[token] != nil
    }

    /// Pick the winning registration: newest stamp among appeared, visible pages.
    ///
    /// - Parameter registrations: Current page registrations.
    /// - Returns: Winning token, or nil when no page is on screen.
    nonisolated static func winner(
        of registrations: [UUID: FestivalBackgroundRegistration]
    ) -> UUID? {
        registrations
            .filter { $0.value.appeared && $0.value.visible }
            .max { $0.value.stamp < $1.value.stamp }?
            .key
    }

    /// Publish the winner; keep the previous mode during transient gaps.
    private func resolve() {
        let top = Self.winner(of: registrations)
        if topToken != top { topToken = top }
        if let top, let mode = registrations[top]?.mode, mode != resolvedMode {
            resolvedMode = mode
        }
    }

    // MARK: - Song cover

    /// Fade a song's cover in above the carousel (replacing any current cover,
    /// which fades out beneath it).
    ///
    /// - Parameter cover: Entering cover with its start instant.
    func showOverlay(_ cover: SongOverlay) {
        if let overlay {
            exiting = ExitingOverlay(overlay: overlay, start: cover.start)
        }
        overlay = cover
        scheduleSettle(at: cover.start.addingTimeInterval(SongOverlay.fadeDuration))
    }

    /// Fade the current cover back out to the carousel.
    ///
    /// - Parameter now: Exit start instant.
    func dismissOverlay(now: Date = .now) {
        carouselVisible = true
        guard let overlay else { return }
        exiting = ExitingOverlay(overlay: overlay, start: now)
        self.overlay = nil
        scheduleSettle(at: now.addingTimeInterval(ExitingOverlay.duration))
    }

    /// Finish transitions: drop the exited cover and pause the carousel if a
    /// cover now hides it.
    func settle() {
        exiting = nil
        carouselVisible = overlay == nil
    }

    /// Settle once the latest running transition ends.
    ///
    /// - Parameter end: When the transition just started will finish.
    private func scheduleSettle(at end: Date) {
        settleTask?.cancel()
        let delay = max(0, end.timeIntervalSinceNow) + 0.05
        settleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.settle()
        }
    }

    #if DEBUG
    /// Force a background for debug screenshots, bypassing page registrations.
    ///
    /// - Parameter mode: Background to render.
    func debugOverride(_ mode: ArtworkBackgroundMode) {
        resolvedMode = mode
    }

    #endif

    // MARK: - Mode changes

    /// Whether the shown song cover already satisfies a requested song.
    ///
    /// - Parameters:
    ///   - current: Cover on screen, if any.
    ///   - raw: Requested artwork path ("" for a song without art).
    ///   - opaque: Data saving or opaque accessibility presentation (no art is shown).
    /// - Returns: True when presenting the request would change nothing.
    nonisolated static func keepsCover(
        current: (raw: String, hasImage: Bool)?, raw: String, opaque: Bool
    ) -> Bool {
        guard let current, current.raw == raw else { return false }
        return current.hasImage || opaque || raw.isEmpty
    }

    /// Move the shared backdrop to the page-on-top's mode: dismiss the cover for
    /// the carousel, or decode and fade in a song's cover. Shared by the SwiftUI
    /// ``FestivalBackgroundHost`` and the UIKit port's host.
    ///
    /// - Parameters:
    ///   - mode: Mode of the page on top.
    ///   - session: Artwork cache owner.
    ///   - policy: Artwork policy for a single still cover.
    ///   - maxPixels: Decode bound for a full-screen cover.
    func present(
        _ mode: ArtworkBackgroundMode, session: FestivalSession,
        policy: ArtworkPlaybackPolicy, maxPixels: Int
    ) async {
        switch mode {
        case .carousel:
            dismissOverlay()
        case let .song(optionalRaw):
            let raw = optionalRaw ?? ""
            let opaque = policy.saveData || policy.reduceTransparency
            if Self.keepsCover(
                current: overlay.map { ($0.raw, $0.image != nil) }, raw: raw, opaque: opaque
            ) {
                return
            }
            var image: CGImage?
            if !raw.isEmpty && !opaque {
                // Keep the carousel until the scene and network allow a fetch.
                guard policy.mayLoad else { return }
                do {
                    image = try await session.preparedArtwork(
                        raw: raw, maxPixels: maxPixels
                    ).image
                } catch is CancellationError {
                    return
                } catch let error as URLError where error.code == .cancelled {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    Logger(
                        subsystem: "com.sfenton.festivalscoretracker", category: "artwork-background"
                    ).error("Song backdrop unavailable: \(error.localizedDescription)")
                }
            }
            guard !Task.isCancelled else { return }
            showOverlay(SongOverlay(raw: raw, image: image, start: .now))
        }
    }

    #if DEBUG
    /// `FST_DEBUG_BACKGROUND_CYCLE=<seconds>` alternates carousel and a song cover
    /// so screenshots can show transitions.
    ///
    /// - Parameter session: Source of the cover path.
    func debugCycle(session: FestivalSession) async {
        guard let raw = ProcessInfo.processInfo.environment["FST_DEBUG_BACKGROUND_CYCLE"],
              let seconds = Double(raw), seconds > 0 else { return }
        var showSong = true
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let art = session.artworkPaths.first
            else { continue }
            debugOverride(showSong ? .song(art) : .carousel)
            showSong.toggle()
        }
    }
    #endif
}
