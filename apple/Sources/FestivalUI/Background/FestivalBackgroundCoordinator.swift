import CoreGraphics
import Foundation
import Observation
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
    /// True while a cover enters or exits, so mirrors render every frame.
    private(set) var overlayAnimating = false
    /// False once a cover fully hides the carousel, pausing its motion and loads.
    private(set) var carouselVisible = true

    @ObservationIgnored
    private var settleTask: Task<Void, Never>?

    @ObservationIgnored
    private var registrations: [UUID: FestivalBackgroundRegistration] = [:]
    @ObservationIgnored
    private var nextStamp = 0
    @ObservationIgnored
    private var tileFrames: [String: TileFrame] = [:]

    /// Create the coordinator for one session.
    ///
    /// - Parameter session: Artwork cache owner for the shared carousel.
    init(session: FestivalSession) {
        carousel = ArtworkCarouselEngine(session: session)
    }

    /// Last known on-screen frame of a carousel page's album tile.
    struct TileFrame: Equatable {
        let frame: CGRect
        let owner: UUID
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
        tileFrames = tileFrames.filter { $0.value.owner != token }
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

    /// Show a song's cover above the carousel (replacing any current cover).
    ///
    /// - Parameter cover: Entering cover with its start instant and style.
    func showOverlay(_ cover: SongOverlay) {
        if let overlay {
            exiting = ExitingOverlay(overlay: overlay, start: cover.start)
        }
        overlay = cover
        overlayAnimating = true
        scheduleSettle(
            at: cover.start.addingTimeInterval(SongOverlay.duration(cover.style))
        )
    }

    /// Dissolve the current cover back to the carousel.
    ///
    /// - Parameter now: Exit start instant.
    func dismissOverlay(now: Date = .now) {
        carouselVisible = true
        guard let overlay else { return }
        exiting = ExitingOverlay(overlay: overlay, start: now)
        self.overlay = nil
        overlayAnimating = true
        scheduleSettle(at: now.addingTimeInterval(ExitingOverlay.duration))
    }

    /// Finish transitions: drop the exited cover, stop per-frame rendering and
    /// pause the carousel if a cover now hides it.
    func settle() {
        exiting = nil
        overlayAnimating = false
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

    // MARK: - Album tile geometry

    /// Remember where an album tile is drawn on a carousel page.
    ///
    /// Stored without observation so scrolling never re-renders the host.
    ///
    /// - Parameters:
    ///   - raw: Artwork path the tile displays.
    ///   - frame: Tile frame in global (window) coordinates.
    ///   - owner: Token of the page drawing the tile.
    func noteTile(_ raw: String, frame: CGRect, owner: UUID) {
        tileFrames[raw] = TileFrame(frame: frame, owner: owner)
    }

    /// Forget a tile that scrolled away or was removed.
    ///
    /// - Parameters:
    ///   - raw: Artwork path the tile displays.
    ///   - owner: Token of the page drawing the tile.
    func forgetTile(_ raw: String, owner: UUID) {
        if tileFrames[raw]?.owner == owner { tileFrames[raw] = nil }
    }

    /// Frame to zoom a song's album art from, if a carousel page shows its tile.
    ///
    /// - Parameter raw: Artwork path of the song being opened.
    /// - Returns: Global tile frame, or nil when no matching tile is on screen.
    func sourceFrame(for raw: String) -> CGRect? {
        guard let tile = tileFrames[raw], registrations[tile.owner] != nil else {
            return nil
        }
        return tile.frame
    }

    #if DEBUG
    /// Force a background for debug screenshots, bypassing page registrations.
    ///
    /// - Parameter mode: Background to render.
    func debugOverride(_ mode: ArtworkBackgroundMode) {
        resolvedMode = mode
    }

    /// An album tile currently on screen on a registered carousel page.
    ///
    /// - Returns: Artwork path of the top-most such tile, if any.
    func debugVisibleTileRaw() -> String? {
        tileFrames
            .filter { registrations[$0.value.owner] != nil && $0.value.frame.minY > 150 }
            .min { $0.value.frame.minY < $1.value.frame.minY }?
            .key
    }
    #endif
}

// MARK: - Environment

extension EnvironmentValues {
    /// Registration token and mode of the page a view is drawn on.
    ///
    /// Album tiles use it to report their frame only from carousel pages.
    @Entry var festivalBackgroundPage: FestivalBackgroundPage?
}

/// The enclosing page's background registration, visible to descendants.
struct FestivalBackgroundPage: Equatable {
    let token: UUID
    let mode: ArtworkBackgroundMode
}
