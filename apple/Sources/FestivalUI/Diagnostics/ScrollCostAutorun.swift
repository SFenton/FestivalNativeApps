import Foundation
#if os(iOS)
import QuartzCore
import UIKit
#endif

// MARK: - Autorun

/// The launch-time perf run (`tools/uikit_perf.py`): with `FST_PERF_AUTORUN=<settle seconds>` the process measures itself
/// and writes `FSTPERF` lines to `FST_PERF_FILE` (keys: ``PerfConfig``), then a final ``PerfLine/done``.
///
/// - Launch: when content is first on screen ``FirstContentProbe`` and the process's CPU and memory at the end of the
///   settle time.
/// - Scroll run (default): 8 s idle, then two 8 s scrolls at 900 pt/s (``ScrollCostDriver``, ``FramePacer``,
///   ``MainThreadCostMeter``).
/// - Navigation run (`FST_PERF_NAV`): push and pop of a route, `FST_PERF_NAV_CYCLES` times (``NavigationCostRunner``).
///
/// It needs no SwiftUI view and finds the page in the key window, so the same code measures the SwiftUI app
/// (`FestivalMobileApp.init`) and the UIKit port (`UKApp.didFinishLaunching`). Debug and `Release --probe` builds only
/// (the `DEBUG` condition); a true Release build ignores it.
@MainActor
public enum ScrollCostAutorun {
    /// Starts the run when the launch environment asks for it; call once, as early in launch as possible.
    public static func startIfRequested() {
        #if DEBUG && os(iOS)
        guard !started, let config = PerfConfig(environment: ProcessInfo.processInfo.environment) else { return }
        started = true
        let probe = FirstContentProbe()
        probe.start()
        Task { @MainActor in await run(config, probe: probe) }
        #endif
    }

    #if DEBUG && os(iOS)
    private static var started = false

    private static func run(_ config: PerfConfig, probe: FirstContentProbe) async {
        let output = PerfOutput(path: config.file)
        output.reset()
        try? await Task.sleep(for: .seconds(config.settle))
        probe.stop()
        output.write(name: config.name, kind: "launch", summary: launchSummary(probe))
        if config.navRoutes.isEmpty {
            let driver = ScrollCostDriver(config: config)
            for (kind, scrolling) in [("idle", false), ("scroll", true), ("scroll", true)] {
                let summary = await driver.run(scrolling: scrolling)
                output.write(name: config.name, kind: kind, summary: summary ?? "no scroll view: " + ScrollCostDriver.describeScrollViews())
            }
        } else {
            await NavigationCostRunner.run(config, output: output)
        }
        output.finish()
    }

    /// The cold launch as one line: when the process reached `startIfRequested`, when content first appeared, and what the
    /// process had cost by the end of the settle time.
    private static func launchSummary(_ probe: FirstContentProbe) -> String {
        let process = ProcessCPU.snapshot()
        let first = probe.contentMs.map { PerfFormat.oneDecimal($0) } ?? "-1"
        return "launch=1 ready_ms=\(PerfFormat.oneDecimal(probe.readyMs)) first_content_ms=\(first) "
            + "up_s=\(PerfFormat.oneDecimal(ProcessCPU.secondsSinceProcessStart())) cpu_ms=\(Int(process.cpuSeconds * 1000)) "
            + "instr_m=\(process.instructions / 1_000_000) mem_mb=\(PerfFormat.oneDecimal(FramePacer.memory().now))"
    }
    #endif
}

// MARK: - Result file

/// Appends result lines to `FST_PERF_FILE` (stderr-less: the host polls the file).
struct PerfOutput {
    let path: String?

    /// Empties the file.
    func reset() { if let path { try? Data().write(to: URL(fileURLWithPath: path)) } }

    /// Appends one data line.
    func write(name: String, kind: String, summary: String) { append(PerfLine.row(name: name, kind: kind, summary: summary)) }

    /// Appends the final line.
    func finish() { append(PerfLine.done + "\n") }

    private func append(_ text: String) {
        guard let path, let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}

#if os(iOS)
// MARK: - First content

/// Finds the moment the landing page's content is first on screen, from outside the page, so the SwiftUI app and the UIKit
/// port are timed by the same rule.
///
/// **Definition.** The first display frame, counted from the process's start (`kern.proc.pid` start time), on which the
/// key window has a vertical scroll view that covers the page and holds content: a list or collection view with at least
/// three rows on screen, any other scroll view with content taller than 300 pt. A loading spinner or placeholder does
/// not count. Page code may call ``markFirstContent()`` instead, once its real rows are on screen; the earlier of the two
/// wins.
@MainActor
final class FirstContentProbe {
    /// Milliseconds from process start to the first content frame; nil until seen.
    private(set) var contentMs: Double?
    /// Milliseconds from process start to the probe starting (pre-main, scene and root creation excluded).
    let readyMs: Double
    private let ticker = FrameTicker()
    private static var explicit: Double?

    /// Creates a probe, noting how far into the process's life it began.
    init() { readyMs = ProcessCPU.secondsSinceProcessStart() * 1000 }

    /// Starts watching frames.
    func start() {
        ticker.start { [weak self] _ in
            guard let self, self.contentMs == nil else { return }
            if let explicit = Self.explicit {
                self.contentMs = explicit
            } else if Self.hasContent() {
                self.contentMs = ProcessCPU.secondsSinceProcessStart() * 1000
            }
            if self.contentMs != nil { self.ticker.stop() }
        }
    }

    /// Stops watching.
    func stop() { ticker.stop() }

    /// Lets page code declare its first content on screen (an explicit marker for pages the heuristic cannot judge).
    static func markFirstContent() {
        if explicit == nil { explicit = ProcessCPU.secondsSinceProcessStart() * 1000 }
    }

    /// Whether the front page currently shows content (see the type's definition).
    static func hasContent() -> Bool {
        guard let scroll = ScrollCostDriver.frontScrollView() else { return false }
        if let collection = scroll as? UICollectionView { return collection.indexPathsForVisibleItems.count >= 3 }
        if let table = scroll as? UITableView { return table.indexPathsForVisibleRows.map { $0.count >= 3 } ?? false }
        return scroll.contentSize.height > 300
    }
}

// MARK: - Navigation hooks

/// How each app pushes and pops a route for ``NavigationCostRunner``; the root registers them at launch.
@MainActor
enum PerfNavigationHooks {
    /// Pushes a route on the front stack (animated).
    static var push: ((AppRoute) -> Void)?
    /// Pops the front stack's top (animated).
    static var pop: (() -> Void)?

    /// Registers the root's actions.
    ///
    /// - Parameters:
    ///   - push: Pushes a route.
    ///   - pop: Pops the top route.
    static func register(push: @escaping (AppRoute) -> Void, pop: @escaping () -> Void) {
        self.push = push
        self.pop = pop
    }
}

// MARK: - Navigation cost

/// Times a push and a pop of a route and what the main thread spent doing it, by watching the front
/// `UINavigationController` (the SwiftUI `NavigationStack` is one too), so both apps are timed by the same rule.
///
/// - **first**: ms from the push (pop) call to the first display frame on which the stack has changed and the new top
///   page's view is in the window.
/// - **settled**: ms until the stack's transition coordinator is gone (the animation finished).
/// - **turn p95 / worst**, **over8**, **main_ms**, **cpu_ms**: ``MainThreadCostMeter`` over call to settled.
///
/// The first cycle is reported apart (`cold_first_ms`); the others give the percentiles.
@MainActor
enum NavigationCostRunner {
    /// One timed push or pop.
    private struct Sample {
        var first: Double
        var settled: Double
        var report: MainThreadCostMeter.Report
    }

    /// Runs every route's cycles and writes a `push` and a `pop` line each.
    ///
    /// - Parameters:
    ///   - config: Routes and cycles.
    ///   - output: Where the lines go.
    static func run(_ config: PerfConfig, output: PerfOutput) async {
        #if DEBUG
        for token in config.navRoutes {
            guard let route = DebugLaunchRoute(environment: ["FST_DEBUG_ROUTE": token]).route else {
                output.write(name: config.name, kind: "push", summary: "unknown route \(token)")
                continue
            }
            guard let push = PerfNavigationHooks.push, let pop = PerfNavigationHooks.pop else {
                output.write(name: config.name, kind: "push", summary: "no navigation hooks registered")
                continue
            }
            var pushes: [Sample] = []
            var pops: [Sample] = []
            for _ in 0..<config.navCycles {
                guard let nav = frontNavigationController() else {
                    output.write(name: config.name, kind: "push", summary: "no navigation controller: " + describe())
                    break
                }
                let depth = nav.viewControllers.count
                guard let pushed = await measure(nav, action: { push(route) }, done: { $0.viewControllers.count > depth }) else {
                    output.write(name: config.name, kind: "push", summary: "push did not complete: depth \(depth) -> \(nav.viewControllers.count)")
                    break
                }
                pushes.append(pushed)
                try? await Task.sleep(for: .seconds(1.5))
                guard let popped = await measure(nav, action: { pop() }, done: { $0.viewControllers.count == depth }) else {
                    output.write(name: config.name, kind: "pop", summary: "pop did not complete: depth \(depth) -> \(nav.viewControllers.count)")
                    break
                }
                pops.append(popped)
                try? await Task.sleep(for: .seconds(1))
            }
            if !pushes.isEmpty { output.write(name: config.name, kind: "push", summary: "route=\(token) " + summarize(pushes)) }
            if !pops.isEmpty { output.write(name: config.name, kind: "pop", summary: "route=\(token) " + summarize(pops)) }
        }
        #endif
    }

    /// Aggregates samples: the first is `cold_*`, the rest (or all, when there is only one) give the percentiles.
    ///
    /// - Parameter samples: In run order.
    /// - Returns: `key=value` pairs.
    private static func summarize(_ samples: [Sample]) -> String {
        let warm = samples.count > 1 ? Array(samples.dropFirst()) : samples
        let first = warm.map(\.first).sorted(), settled = warm.map(\.settled).sorted()
        func ms(_ value: Double) -> String { PerfFormat.oneDecimal(value * 1000) }
        let turnP95 = PerfStats.median(warm.map(\.report.p95TurnMs))
        return [
            "n=\(warm.count)", "cold_first_ms=\(ms(samples[0].first))", "cold_settled_ms=\(ms(samples[0].settled))",
            "first_p50_ms=\(ms(PerfStats.percentile(first, 0.5)))", "first_p95_ms=\(ms(PerfStats.percentile(first, 0.95)))",
            "settled_p50_ms=\(ms(PerfStats.percentile(settled, 0.5)))", "settled_p95_ms=\(ms(PerfStats.percentile(settled, 0.95)))",
            "turn_p95_ms=\(PerfFormat.number(turnP95))", "turn_worst_ms=\(PerfFormat.number(warm.map(\.report.worstTurnMs).max() ?? 0))",
            "over8=\(Int(PerfStats.median(warm.map { Double($0.report.turnsOver8) })))",
            "main_ms=\(Int(PerfStats.median(warm.map { $0.report.mainCPUSeconds * 1000 })))",
            "cpu_ms=\(Int(PerfStats.median(warm.map { $0.report.processCPUSeconds * 1000 })))",
        ].joined(separator: " ")
    }

    private static func measure(
        _ nav: UINavigationController, action: () -> Void, done: @escaping @MainActor (UINavigationController) -> Bool
    ) async -> Sample? {
        let meter = MainThreadCostMeter()
        meter.begin()
        let t0 = CACurrentMediaTime()
        action()
        let first = await FrameTicker.wait(timeout: 5) { [weak nav] in
            guard let nav, done(nav) else { return false }
            return nav.topViewController?.viewIfLoaded?.window != nil
        }
        let settled = await FrameTicker.wait(timeout: 5) { [weak nav] in
            guard let nav else { return true }
            return done(nav) && nav.transitionCoordinator == nil
        }
        let report = meter.finish()
        guard let first, let settled else { return nil }
        return Sample(first: first - t0, settled: settled - t0, report: report)
    }

    /// The navigation controller of the page in front: of all that are on screen, the one covering the most of the window.
    static func frontNavigationController() -> UINavigationController? {
        guard let window = ScrollCostDriver.keyWindow(), let root = window.rootViewController else { return nil }
        var found: [UINavigationController] = []
        func visit(_ controller: UIViewController) {
            if let nav = controller as? UINavigationController { found.append(nav) }
            if let tabs = controller as? UITabBarController {
                if let selected = tabs.selectedViewController { visit(selected) }
            } else {
                controller.children.forEach(visit)
            }
            if let presented = controller.presentedViewController { visit(presented) }
        }
        visit(root)
        func area(_ nav: UINavigationController) -> CGFloat {
            guard nav.isViewLoaded, nav.view.window != nil, !nav.view.isHidden, nav.view.alpha > 0.01 else { return 0 }
            let visible = nav.view.convert(nav.view.bounds, to: window).intersection(window.bounds)
            return visible.width * visible.height
        }
        return found.max { area($0) < area($1) }.flatMap { area($0) > 0 ? $0 : nil }
    }

    private static func describe() -> String {
        guard let root = ScrollCostDriver.keyWindow()?.rootViewController else { return "no root" }
        var names: [String] = []
        func visit(_ controller: UIViewController, _ depth: Int) {
            guard depth < 8 else { return }
            names.append(String(repeating: ".", count: depth) + "\(type(of: controller))")
            controller.children.forEach { visit($0, depth + 1) }
        }
        visit(root, 0)
        return names.prefix(24).joined(separator: ",")
    }
}
#endif
