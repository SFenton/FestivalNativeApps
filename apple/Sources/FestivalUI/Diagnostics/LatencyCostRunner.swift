#if os(iOS)
import Foundation

// MARK: - No-scroll latency and memory

/// Measures a valid no-scroll surface without manufacturing a zero-sample scroll result.
@MainActor
enum LatencyCostRunner {
    /// Holds the settled page for one measured interval and records process/main CPU and memory.
    static func run(_ config: PerfConfig, output: PerfOutput) async {
        #if DEBUG
        let meter = MainThreadCostMeter()
        let pacer = FramePacer()
        let end = ContinuousClock.now + .seconds(config.seconds)
        let t0 = Date().timeIntervalSince1970
        meter.begin()
        pacer.begin()
        try? await Task.sleep(until: end, clock: .continuous)
        pacer.finish()
        let t1 = Date().timeIntervalSince1970
        var report = meter.finish()
        report.note = pacer.summary
            + " t0=\(String(format: "%.3f", t0)) t1=\(String(format: "%.3f", t1))"
        output.write(name: config.name, kind: "latency", summary: report.summary)
        #endif
    }
}
#endif
