import Testing
@testable import FestivalUI

/// The pure parts of the A/B perf probes (`Diagnostics/`): report math, statistics, configuration and result lines.
@MainActor
struct PerfProbeTests {
    @Test func reportCountsTurnsOverEachBudgetAndFindsThePercentiles() {
        let turns = (1...100).map { MainThreadCostMeter.Turn(cpuMs: Double($0)) }
        let report = MainThreadCostMeter.report(
            seconds: 8, process: .init(instructions: 5_000_000, cpuSeconds: 1.5), mainSeconds: 1.25, turns: turns
        )
        #expect(report.turns == 100)
        #expect(report.turnsOver4 == 96)
        #expect(report.turnsOver8 == 92)
        #expect(report.turnsOver16 == 84)
        #expect(report.worstTurnMs == 100)
        #expect(report.p95TurnMs == 96)
        #expect(report.megaInstructions == 5)
        #expect(report.processCPUSeconds == 1.5)
    }

    @Test func emptyRunReportsZeros() {
        let report = MainThreadCostMeter.report(seconds: 1, process: .zero, mainSeconds: 0, turns: [])
        #expect(report.turns == 0 && report.worstTurnMs == 0 && report.p95TurnMs == 0)
    }

    @Test func summaryIsKeyValueAndAppendsTheNote() {
        var report = MainThreadCostMeter.report(
            seconds: 2, process: .init(instructions: 0, cpuSeconds: 0.5), mainSeconds: 0.25,
            turns: [.init(cpuMs: 3), .init(cpuMs: 9)]
        )
        report.travelledPoints = 1800.7
        report.note = "fps=60.0"
        #expect(report.summary == "seconds=2.00 minstr=0.00 cpu_ms=500.00 main_ms=250.00 turns=2 over4=1 over8=1 over16=0 "
            + "worst_ms=9.00 p95_ms=9.00 travelled=1800 fps=60.0")
    }

    @Test func processCountersDifferenceWrapsInstructions() {
        let delta = ProcessCPU.Snapshot(instructions: 10, cpuSeconds: 3) - ProcessCPU.Snapshot(instructions: 4, cpuSeconds: 1)
        #expect(delta.instructions == 6 && delta.cpuSeconds == 2)
    }

    @Test func medianAndPercentile() {
        #expect(PerfStats.median([3, 1, 2]) == 2)
        #expect(PerfStats.median([4, 1, 2, 3]) == 2.5)
        #expect(PerfStats.median([]) == 0)
        #expect(PerfStats.percentile([1, 2, 3, 4], 0.5) == 3)
        #expect(PerfStats.percentile([1, 2, 3, 4], 1) == 4)
        #expect(PerfStats.percentile([], 0.9) == 0)
    }

    @Test func hitchTallyCountsMissedRefreshesAndLateTime() {
        var tally = HitchTally()
        let frame = 1.0 / 60
        tally.record(timestamp: 0, expected: frame)
        tally.record(timestamp: frame, expected: frame)
        tally.record(timestamp: frame * 4, expected: frame)  // two refreshes missed
        tally.record(timestamp: frame * 5, expected: frame)
        #expect(tally.frames == 4)
        #expect(tally.dropped == 2)
        #expect(abs(tally.hitchSeconds - 2 * frame) < 1e-9)
    }

    @Test func hitchTallyIgnoresUnknownRefreshInterval() {
        var tally = HitchTally()
        tally.record(timestamp: 0, expected: 0)
        tally.record(timestamp: 1, expected: 0)
        #expect(tally.frames == 2 && tally.dropped == 0)
    }

    @Test func configRequiresTheAutorunKeyAndDefaults() {
        #expect(PerfConfig(environment: [:]) == nil)
        #expect(PerfConfig(environment: ["FST_PERF_AUTORUN": "soon"]) == nil)
        let config = PerfConfig(environment: ["FST_PERF_AUTORUN": "9"])
        #expect(config?.settle == 9)
        #expect(config?.seconds == 8 && config?.speed == 900 && config?.horizontal == false)
        #expect(config?.navRoutes == [] && config?.navCycles == 6)
        #expect(config?.file == nil && config?.name == "surface")
    }

    @Test func configReadsEveryKey() {
        let config = PerfConfig(environment: [
            "FST_PERF_AUTORUN": "12", "FST_PERF_FILE": "/tmp/x.tsv", "FST_PERF_NAME": "Songs", "FST_PERF_SECONDS": "0.1",
            "FST_PERF_SPEED": "450", "FST_PERF_AXIS": "horizontal", "FST_PERF_NAV": "leaderboards;rivals",
            "FST_PERF_NAV_CYCLES": "0",
        ])
        #expect(config?.file == "/tmp/x.tsv" && config?.name == "Songs")
        #expect(config?.seconds == 0.5)  // clamped
        #expect(config?.speed == 450 && config?.horizontal == true)
        #expect(config?.navRoutes == ["leaderboards", "rivals"])
        #expect(config?.navCycles == 1)  // clamped
    }

    @Test func resultRowsAreOneTabSeparatedLine() {
        #expect(PerfLine.row(name: "Songs", kind: "idle", summary: "a=1 b=2") == "FSTPERF\tSongs\tidle\ta=1 b=2\n")
        #expect(PerfLine.row(name: "S", kind: "scroll", summary: "bad\tline\nbreak") == "FSTPERF\tS\tscroll\tbad line break\n")
        #expect(PerfLine.done == "FSTPERF_DONE")
    }
}
