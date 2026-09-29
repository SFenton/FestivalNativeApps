#if DEBUG && os(iOS)
import Foundation
import QuartzCore
import SwiftUI
import FestivalCore

// MARK: - Scripted motion run (Debug only)

/// `FST_DEBUG_MOTION_SCRIPT=1`: a timed push/pop/tab-switch sequence with an
/// on-screen main-thread frame report, for frame-pacing recordings made with
/// `tools/ios_sim.py shot --record` (no XCUITest, so the animating background
/// never waits for app idle).
///
/// Each phase counts display-link callbacks whose interval exceeded 1.5× the
/// target frame duration (a dropped frame on the main thread, which stalls
/// SwiftUI's in-process animations). The report is drawn only after each phase
/// ends, so the overlay itself adds no per-frame work. Never compiled into Release.
@MainActor
enum DebugMotionScript {
    /// Whether the launch environment asked for the scripted run.
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["FST_DEBUG_MOTION_SCRIPT"] == "1"
    }

    /// Navigation hooks supplied by the root view.
    struct Hooks {
        let push: (AppRoute) -> Void
        let pop: () -> Void
        let select: (FestivalSection) -> Void
    }

    /// The running script, kept outside any view's lifetime so a shell re-render
    /// (which cancels `.task`) never stops it mid-run.
    private static var running: Task<Void, Never>?

    /// Start the scripted run once per process (no-op unless enabled).
    ///
    /// - Parameters:
    ///   - session: Session whose catalogue supplies a song with artwork.
    ///   - report: Observable report drawn by ``DebugMotionReportView``.
    ///   - hooks: Root navigation actions.
    static func start(session: FestivalSession, report: DebugMotionReport, hooks: Hooks) {
        guard enabled, running == nil else { return }
        running = Task { await run(session: session, report: report, hooks: hooks) }
    }

    /// Run the sequence twice, reporting each phase into `report`.
    ///
    /// - Parameters:
    ///   - session: Session whose catalogue supplies a song with artwork.
    ///   - report: Observable report drawn by ``DebugMotionReportView``.
    ///   - hooks: Root navigation actions.
    static func run(session: FestivalSession, report: DebugMotionReport, hooks: Hooks) async {
        guard enabled else { return }
        let monitor = FrameHitchMonitor()
        let song: Song
        do {
            try await Task.sleep(for: .seconds(6))
            let songs = try await session.catalog().catalog.songs
            let wanted = ProcessInfo.processInfo.environment["FST_DEBUG_MOTION_SONG"]
            guard let pick = songs.first(where: { $0.title == wanted && $0.albumArt != nil })
                ?? songs.filter({ $0.albumArt?.isEmpty == false })
                    .sorted(by: { $0.title < $1.title }).first else { return }
            song = pick
        } catch {
            return
        }
        let steps: [(String, () -> Void)] = [
            ("idle", {}),
            ("push detail", { hooks.push(.songDetail(song)) }),
            ("push board", { hooks.push(.songLeaderboard(song, .lead, 1)) }),
            ("pop board", { hooks.pop() }),
            ("pop detail", { hooks.pop() }),
            // Leaderboards is replaced by Compete while a profile is selected.
            ("tab boards", { hooks.select(session.selectedPlayer == nil ? .leaderboards : .compete) }),
            ("tab settings", { hooks.select(.settings) }),
            ("tab songs", { hooks.select(.songs) }),
        ]
        for round in 1...2 {
            for (name, action) in steps {
                monitor.reset()
                action()
                do {
                    try await Task.sleep(for: .seconds(2.5))
                } catch {
                    monitor.stop()
                    return
                }
                report.lines.append("\(round) \(name): \(monitor.summary)")
            }
        }
        monitor.stop()
        report.lines.append("done")
    }
}

/// Phase results shown on screen by ``DebugMotionReportView``.
@MainActor
@Observable
final class DebugMotionReport {
    var lines: [String] = []
}

/// Small monospaced report pinned to the bottom of the window.
struct DebugMotionReportView: View {
    let report: DebugMotionReport

    var body: some View {
        if !report.lines.isEmpty {
            Text(report.lines.suffix(16).joined(separator: "\n"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.yellow)
                .padding(4)
                .background(.black.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, 90)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Frame monitor

/// Counts main-thread display-link callbacks that arrive late.
@MainActor
final class FrameHitchMonitor: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var hitches = 0
    private var worst: CFTimeInterval = 0
    private var target: CFTimeInterval = 1.0 / 60

    override init() {
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Start a new phase.
    func reset() {
        last = 0
        frames = 0
        hitches = 0
        worst = 0
    }

    /// Remove the display link.
    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Frames, late frames and the worst interval of the current phase.
    var summary: String {
        String(
            format: "%d fr @%.0fHz, %d late, worst %.0f ms",
            frames, 1 / target, hitches, worst * 1000
        )
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        target = max(1.0 / 240, link.targetTimestamp - link.timestamp)
        if last > 0 {
            let interval = now - last
            frames += 1
            worst = max(worst, interval)
            if interval > target * 1.5 { hitches += 1 }
        }
        last = now
    }
}
#endif
