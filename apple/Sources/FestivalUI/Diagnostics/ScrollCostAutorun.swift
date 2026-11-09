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
        do {
            try PhysicalPerfFixture.startIfRequested(environment: ProcessInfo.processInfo.environment)
        } catch {
            let output = PerfOutput(path: config.file)
            output.reset()
            output.write(name: config.name, kind: "context", summary: "fixture_start_failed=1")
            output.finish()
            return
        }
        FirstContentProbe.reset()
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
        let physical = ProcessInfo.processInfo.environment["FST_PERF_FIXTURE_ARCHIVE"] != nil
        if physical {
            output.write(name: config.name, kind: "context", summary: physicalContext(phase: "start"))
            guard ProcessInfo.processInfo.thermalState == .nominal,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled else {
                output.finish()
                return
            }
        }
        let priorIdleTimerPolicy = UIApplication.shared.isIdleTimerDisabled
        if physical { UIApplication.shared.isIdleTimerDisabled = true }
        defer { if physical { UIApplication.shared.isIdleTimerDisabled = priorIdleTimerPolicy } }
        try? await Task.sleep(for: .seconds(config.settle))
        probe.stop()
        output.write(name: config.name, kind: "launch", summary: launchSummary(probe))
        if config.mode == "modal" || !config.modalRoutes.isEmpty {
            await ModalCostRunner.run(config, output: output)
        } else if config.mode == "component" || !config.componentRoutes.isEmpty {
            await ComponentCostRunner.run(config, output: output)
        } else if config.mode == "nav" || !config.navRoutes.isEmpty {
            await NavigationCostRunner.run(config, output: output)
        } else if config.mode == "latency" {
            await LatencyCostRunner.run(config, output: output)
        } else {
            let driver = ScrollCostDriver(config: config)
            for (kind, scrolling) in [("idle", false), ("scroll", true), ("scroll", true)] {
                let summary = await driver.run(scrolling: scrolling)
                output.write(name: config.name, kind: kind, summary: summary ?? "no scroll view: " + ScrollCostDriver.describeScrollViews())
            }
        }
        if physical { output.write(name: config.name, kind: "context", summary: physicalContext(phase: "end")) }
        output.finish()
    }

    private static func physicalContext(phase: String) -> String {
        let process = ProcessInfo.processInfo
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
        return "phase=\(phase) thermal=\(process.thermalState.rawValue) low_power=\(process.isLowPowerModeEnabled ? 1 : 0) "
            + "maximum_hz=\(screen?.maximumFramesPerSecond ?? 0) " + PhysicalPerfFixture.summary
    }

    /// The cold launch as one line: when the process reached `startIfRequested`, when content first appeared, and what the
    /// process had cost by the end of the settle time.
    private static func launchSummary(_ probe: FirstContentProbe) -> String {
        let process = ProcessCPU.snapshot()
        let first = probe.contentMs.map { PerfFormat.oneDecimal($0) } ?? "-1"
        return "launch=1 ready_ms=\(PerfFormat.oneDecimal(probe.readyMs)) first_content_ms=\(first) "
            + "content_real=\(probe.contentMs == nil ? 0 : 1) content_rows=\(probe.visibleRows) "
            + "content_height=\(PerfFormat.oneDecimal(probe.contentHeight)) content_source=\(probe.contentSource) "
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
    /// Number of visible rows observed by the shared heuristic, when a list exposes them.
    private(set) var visibleRows = 0
    /// Height of the observed content in points.
    private(set) var contentHeight: Double = 0
    /// `explicit`, `collection`, `table`, `scroll` or `none`.
    private(set) var contentSource = "none"
    private let ticker = FrameTicker()
    private static var explicit: (time: Double, rows: Int)?

    /// Creates a probe, noting how far into the process's life it began.
    init() { readyMs = ProcessCPU.secondsSinceProcessStart() * 1000 }

    /// Starts watching frames.
    func start() {
        ticker.start { [weak self] _ in
            guard let self, self.contentMs == nil else { return }
            if let explicit = Self.explicit {
                self.contentMs = explicit.time
                self.contentSource = "explicit"
                self.visibleRows = explicit.rows
                self.contentHeight = Self.frontScrollContentHeight()
            } else if let observation = Self.contentObservation() {
                self.contentMs = ProcessCPU.secondsSinceProcessStart() * 1000
                self.contentSource = observation.source
                self.visibleRows = observation.rows
                self.contentHeight = observation.height
            }
            if self.contentMs != nil { self.ticker.stop() }
        }
    }

    /// Stops watching.
    func stop() { ticker.stop() }

    /// Lets page code declare its first content on screen (an explicit marker for pages the heuristic cannot judge).
    static func markFirstContent() {
        markFirstContent(rows: 3)
    }

    /// Marks a real loaded body with its actual rendered-item count.
    ///
    /// The count is diagnostic evidence, not a qualification override: failed,
    /// loading and empty states must not call this method.
    static func markFirstContent(rows: Int) {
        guard rows > 0, explicit == nil else { return }
        explicit = (ProcessCPU.secondsSinceProcessStart() * 1000, rows)
    }

    /// Clears a previous process-local marker before a new autorun.
    static func reset() {
        explicit = nil
    }

    private struct Observation {
        let source: String
        let rows: Int
        let height: Double
    }

    /// Whether the front page currently shows real content (see the type's definition).
    private static func contentObservation() -> Observation? {
        guard let scroll = ScrollCostDriver.frontScrollView() else { return nil }
        let height = max(Double(scroll.contentSize.height), Double(scroll.bounds.height))
        if let collection = scroll as? UICollectionView {
            let rows = collection.indexPathsForVisibleItems.count
            return rows >= 3 ? Observation(source: "collection", rows: rows, height: height) : nil
        }
        if let table = scroll as? UITableView {
            let rows = table.indexPathsForVisibleRows?.count ?? 0
            return rows >= 3 ? Observation(source: "table", rows: rows, height: height) : nil
        }
        // A generic SwiftUI scroll view has no portable row API. Require a non-empty
        // rendered subtree as well as a substantial content height so a blank shell or
        // spinner-sized placeholder cannot qualify.
        let rendered = scroll.subviews.contains { !$0.isHidden && $0.alpha > 0.01 && !$0.frame.isEmpty }
        return height > 300 && rendered ? Observation(source: "scroll", rows: 0, height: height) : nil
    }

    private static func frontScrollContentHeight() -> Double {
        guard let scroll = ScrollCostDriver.frontScrollView() else { return 0 }
        return max(Double(scroll.contentSize.height), Double(scroll.bounds.height))
    }
}

// MARK: - Navigation hooks

/// How each app pushes and pops a route for ``NavigationCostRunner``; the root registers them at launch.
@MainActor
enum PerfNavigationHooks {
    /// One real product modal/task action registered by the owning screen.
    struct ModalAction {
        let present: @MainActor () -> Void
        let dismiss: @MainActor () -> Void
        let isPresented: @MainActor () -> Bool
    }

    /// One real product component/animation action registered by the owning screen.
    struct ComponentAction {
        let start: @MainActor () -> Void
        let stop: @MainActor () -> Void
        let isReady: @MainActor () -> Bool
        let isRestored: (@MainActor () -> Bool)?
    }

    /// Pushes a route on the front stack (animated).
    static var push: ((AppRoute) -> Void)?
    /// Pops the front stack's top (animated).
    static var pop: (() -> Void)?
    /// Presents a modal/task token (animated).
    static var presentModal: ((String) -> Void)?
    /// Dismisses the measured modal/task.
    static var dismissModal: (() -> Void)?
    /// Starts a component/animation token (animated).
    static var startComponent: ((String) -> Void)?
    /// Ends the measured component/animation.
    static var stopComponent: (() -> Void)?
    /// Whether a component/animation token has reached its visible settled state.
    static var componentIsReady: (() -> Bool)?
    private(set) static var modalActions: [String: ModalAction] = [:]
    private(set) static var componentActions: [String: ComponentAction] = [:]

    /// Registers the root's actions.
    ///
    /// - Parameters:
    ///   - push: Pushes a route.
    ///   - pop: Pops the top route.
    static func register(push: @escaping (AppRoute) -> Void, pop: @escaping () -> Void) {
        self.push = push
        self.pop = pop
        presentModal = nil
        dismissModal = nil
        startComponent = nil
        stopComponent = nil
        componentIsReady = nil
        modalActions.removeAll()
        componentActions.removeAll()
    }

    /// Adds optional modal and component timing seams without changing existing route hooks.
    ///
    /// - Parameters:
    ///   - presentModal: Opens a modal/task token.
    ///   - dismissModal: Closes the currently measured modal/task.
    ///   - startComponent: Starts a component or animation token.
    ///   - stopComponent: Ends the currently measured component or animation.
    ///   - componentIsReady: Returns true once the component is visible and settled.
    static func register(
        presentModal: ((String) -> Void)? = nil,
        dismissModal: (() -> Void)? = nil,
        startComponent: ((String) -> Void)? = nil,
        stopComponent: (() -> Void)? = nil,
        componentIsReady: (() -> Bool)? = nil
    ) {
        self.presentModal = presentModal
        self.dismissModal = dismissModal
        self.startComponent = startComponent
        self.stopComponent = stopComponent
        self.componentIsReady = componentIsReady
    }

    /// Registers a real product-owned modal or task action under a manifest token.
    static func registerModal(
        _ token: String, present: @escaping @MainActor () -> Void,
        dismiss: @escaping @MainActor () -> Void,
        isPresented: @escaping @MainActor () -> Bool
    ) {
        modalActions[token] = ModalAction(present: present, dismiss: dismiss, isPresented: isPresented)
    }

    /// Registers a real product-owned animation/component action under a manifest token.
    static func registerComponent(
        _ token: String, start: @escaping @MainActor () -> Void,
        stop: @escaping @MainActor () -> Void,
        isReady: @escaping @MainActor () -> Bool,
        isRestored: (@MainActor () -> Bool)? = nil
    ) {
        componentActions[token] = ComponentAction(
            start: start, stop: stop, isReady: isReady, isRestored: isRestored
        )
    }

    /// Removes a screen-owned action when its screen leaves the active tree.
    static func unregisterModal(_ token: String) { modalActions.removeValue(forKey: token) }
    /// Removes a component-owned action when its screen leaves the active tree.
    static func unregisterComponent(_ token: String) { componentActions.removeValue(forKey: token) }
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

// MARK: - Modal/task cost

/// Measures modal and task presentation using the same first-frame and settled definitions as navigation.
@MainActor
enum ModalCostRunner {
    private struct Sample {
        var first: Double
        var settled: Double
        var report: MainThreadCostMeter.Report
    }

    /// Runs every modal token's present/dismiss cycles.
    static func run(_ config: PerfConfig, output: PerfOutput) async {
        #if DEBUG
        for token in config.modalRoutes {
            guard let action = PerfNavigationHooks.modalActions[token] else {
                output.write(name: config.name, kind: "present", summary: "no modal hook registered for \(token)")
                continue
            }
            var presents: [Sample] = []
            var dismisses: [Sample] = []
            for _ in 0..<config.navCycles {
                guard let shown = await measure(
                    action: action.present,
                    done: { PerfNavigationHooks.modalActions[token]?.isPresented() ?? false }
                ) else {
                    output.write(name: config.name, kind: "present", summary: "modal did not present: \(token)")
                    break
                }
                presents.append(shown)
                try? await Task.sleep(for: .seconds(1))
                guard let hidden = await measure(
                    action: action.dismiss,
                    done: { !(PerfNavigationHooks.modalActions[token]?.isPresented() ?? true) }
                ) else {
                    output.write(name: config.name, kind: "dismiss", summary: "modal did not dismiss: \(token)")
                    break
                }
                dismisses.append(hidden)
                try? await Task.sleep(for: .seconds(0.5))
            }
            if !presents.isEmpty {
                output.write(name: config.name, kind: "present", summary: "route=\(token) " + summarize(presents))
            }
            if !dismisses.isEmpty {
                output.write(name: config.name, kind: "dismiss", summary: "route=\(token) " + summarize(dismisses))
            }
        }
        #endif
    }

    private static func measure(action: () -> Void, done: @escaping @MainActor () -> Bool) async -> Sample? {
        let meter = MainThreadCostMeter()
        meter.begin()
        let start = CACurrentMediaTime()
        action()
        let first = await FrameTicker.wait(timeout: 5, until: done)
        let settled = await FrameTicker.wait(timeout: 5) {
            guard done() else { return false }
            return frontPresentedController()?.transitionCoordinator == nil
        }
        let report = meter.finish()
        guard let first, let settled else { return nil }
        return Sample(first: first - start, settled: settled - start, report: report)
    }

    private static func summarize(_ samples: [Sample]) -> String {
        let warm = samples.count > 1 ? Array(samples.dropFirst()) : samples
        let first = warm.map(\.first).sorted()
        let settled = warm.map(\.settled).sorted()
        func ms(_ value: Double) -> String { PerfFormat.oneDecimal(value * 1000) }
        return [
            "n=\(warm.count)", "cold_first_ms=\(ms(samples[0].first))", "cold_settled_ms=\(ms(samples[0].settled))",
            "first_p50_ms=\(ms(PerfStats.percentile(first, 0.5)))", "first_p95_ms=\(ms(PerfStats.percentile(first, 0.95)))",
            "settled_p50_ms=\(ms(PerfStats.percentile(settled, 0.5)))", "settled_p95_ms=\(ms(PerfStats.percentile(settled, 0.95)))",
            "turn_p95_ms=\(PerfFormat.number(PerfStats.median(warm.map { $0.report.p95TurnMs })))",
            "turn_worst_ms=\(PerfFormat.number(warm.map { $0.report.worstTurnMs }.max() ?? 0))",
            "over8=\(Int(PerfStats.median(warm.map { Double($0.report.turnsOver8) })))",
            "main_ms=\(Int(PerfStats.median(warm.map { $0.report.mainCPUSeconds * 1000 })))",
            "cpu_ms=\(Int(PerfStats.median(warm.map { $0.report.processCPUSeconds * 1000 })))",
        ].joined(separator: " ")
    }

    private static func frontPresentedController() -> UIViewController? {
        guard let window = ScrollCostDriver.keyWindow() else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let controller, controller !== window.rootViewController else { return nil }
        return controller.viewIfLoaded?.window == nil ? nil : controller
    }
}

// MARK: - Component/animation cost

/// Measures a component class through the narrow app-registered seam. This keeps animation timing out of page code and
/// lets the manifest inventory fades, rows, sheets and other shared classes without inventing a demo frontend.
@MainActor
enum ComponentCostRunner {
    private struct Sample {
        let activation: Double
        let activeSeconds: Double
        let report: MainThreadCostMeter.Report
        let frame: FramePacer.Report
        let restored: Bool
    }

    static func run(_ config: PerfConfig, output: PerfOutput) async {
        #if DEBUG
        for token in config.componentRoutes {
            guard let action = PerfNavigationHooks.componentActions[token] else {
                output.write(name: config.name, kind: "component", summary: "no component hook registered for \(token)")
                continue
            }
            var samples: [Sample] = []
            for _ in 0..<config.navCycles {
                let meter = MainThreadCostMeter()
                let pacer = FramePacer()
                meter.begin()
                pacer.begin()
                let t0 = CACurrentMediaTime()
                action.start()
                guard let first = await FrameTicker.wait(timeout: 5, until: {
                    PerfNavigationHooks.componentActions[token]?.isReady() ?? false
                }) else {
                    pacer.finish()
                    _ = meter.finish()
                    let diagnostic = token == "marquee"
                        ? " " + PerfComponentDebugState.shared.marqueeDiagnosticSummary : ""
                    action.stop()
                    output.write(
                        name: config.name, kind: "component",
                        summary: "component did not settle: \(token)" + diagnostic
                    )
                    break
                }
                let activeStart = CACurrentMediaTime()
                try? await Task.sleep(for: .seconds(config.seconds))
                let activeEnd = CACurrentMediaTime()
                pacer.finish()
                let report = meter.finish()
                action.stop()
                let restored = await FrameTicker.wait(timeout: 5) {
                    if let isRestored = PerfNavigationHooks.componentActions[token]?.isRestored {
                        return isRestored()
                    }
                    return !(PerfNavigationHooks.componentActions[token]?.isReady() ?? true)
                } != nil
                samples.append(
                    Sample(
                        activation: first - t0, activeSeconds: activeEnd - activeStart,
                        report: report, frame: pacer.report, restored: restored
                    )
                )
                if !restored {
                    output.write(name: config.name, kind: "component", summary: "component did not restore: \(token)")
                    break
                }
            }
            if !samples.isEmpty {
                let warm = samples.count > 1 ? Array(samples.dropFirst()) : samples
                let active = PerfStats.median(warm.map(\.activeSeconds))
                let cpu = PerfStats.median(warm.map { $0.report.processCPUSeconds * 1000 })
                let main = PerfStats.median(warm.map { $0.report.mainCPUSeconds * 1000 })
                let p95 = PerfStats.median(warm.map(\.report.p95TurnMs))
                let worst = warm.map(\.report.worstTurnMs).max() ?? 0
                let over8 = PerfStats.median(warm.map { Double($0.report.turnsOver8) })
                let fps = PerfStats.median(warm.map(\.frame.fps))
                let dropped = PerfStats.median(warm.map { Double($0.frame.dropped) })
                let hitch = PerfStats.median(warm.map(\.frame.hitchMillisecondsPerSecond))
                let memory = PerfStats.median(warm.map(\.frame.memoryMB))
                let peak = PerfStats.median(warm.map(\.frame.peakMB))
                output.write(
                    name: config.name, kind: "component",
                    summary: "route=\(token) n=\(warm.count) restored=\(warm.allSatisfy(\.restored) ? 1 : 0) "
                        + "cold_first_ms=\(PerfFormat.oneDecimal(samples[0].activation * 1000)) "
                        + "first_p50_ms=\(PerfFormat.oneDecimal(PerfStats.percentile(warm.map(\.activation).sorted(), 0.5) * 1000)) "
                        + "first_p95_ms=\(PerfFormat.oneDecimal(PerfStats.percentile(warm.map(\.activation).sorted(), 0.95) * 1000)) "
                        + "active_s=\(PerfFormat.number(active)) cpu_ms=\(PerfFormat.number(cpu)) "
                        + "main_ms=\(PerfFormat.number(main)) p95_ms=\(PerfFormat.number(p95)) "
                        + "worst_ms=\(PerfFormat.number(worst)) over8=\(PerfFormat.number(over8)) "
                        + "fps=\(PerfFormat.oneDecimal(fps)) dropped=\(PerfFormat.number(dropped)) "
                        + "hitch_ms_per_s=\(PerfFormat.number(hitch)) mem_mb=\(PerfFormat.oneDecimal(memory)) "
                        + "peak_mb=\(PerfFormat.oneDecimal(peak))"
                )
            }
        }
        #endif
    }
}

#endif
