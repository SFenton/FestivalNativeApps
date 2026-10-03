"""Pure parts of ``tools/apple_perf.py``: CPU parsing, stall windows, trace parsing."""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise _unittest.SkipTest("Apple perf tooling runs only on macOS")

import unittest

from tools.apple_perf import (
    app_bundle,
    build_argv,
    cpu_percent,
    ipad_product,
    parse_cpu_time,
    parse_launch_pid,
    parse_time_profile,
    summarize_cpu,
    summarize_stalls,
    top_symbols,
    trace_argv,
)

TRACE = """<?xml version="1.0"?>
<trace-query-result><node>
<row><thread id="1" fmt="Main Thread 0x1"/><tagged-backtrace id="2">
<frame id="3" name="leafA"><binary id="4" name="SwiftUICore"/></frame>
<frame id="5" name="SongRow.body"><binary id="6" name="FestivalDesktop.debug.dylib"/></frame>
<frame id="7" name="main"><binary ref="6"/></frame></tagged-backtrace></row>
<row><thread ref="1"/><tagged-backtrace ref="2"/></row>
<row><thread id="8" fmt="Worker"/><tagged-backtrace id="9">
<frame ref="3"/><frame id="10" name="decode"><binary ref="6"/></frame></tagged-backtrace></row>
</node></trace-query-result>"""


class CpuTests(unittest.TestCase):
    def test_parse_cpu_time_forms(self):
        self.assertEqual(parse_cpu_time("0:01.50"), 1.5)
        self.assertEqual(parse_cpu_time(" 1:02:03.00\n"), 3723.0)
        self.assertEqual(parse_cpu_time("1-00:00:01"), 86401.0)
        with self.assertRaises(ValueError):
            parse_cpu_time("1:2:3:4")

    def test_cpu_percent_and_summary(self):
        self.assertEqual(cpu_percent(1.0, 2.0), 50.0)
        self.assertEqual(cpu_percent(1.0, 0), 0.0)
        summary = summarize_cpu([10.0, 20.0, 30.0])
        self.assertEqual((summary["mean"], summary["median"], summary["min"], summary["max"]), (20.0, 20.0, 10.0, 30.0))
        self.assertEqual(summarize_cpu([])["mean"], 0.0)


class StallTests(unittest.TestCase):
    def test_only_stalls_inside_the_marked_pass_count(self):
        report = {
            "stalls": [{"at": 1.0, "ms": 400}, {"at": 5.0, "ms": 150}, {"at": 6.0, "ms": 90},
                       {"at": 20.1, "ms": 200}, {"at": 30.0, "ms": 500}],
            "marks": {"songs.stress.start": 4.0, "songs.stress.end": 20.0},
            "counters": {"songs.stress.end": 1},
        }
        summary = summarize_stalls(report)
        self.assertEqual(summary["count"], 2)
        self.assertEqual(summary["worst_ms"], 200)
        self.assertTrue(summary["completed"])

    def test_main_thread_cpu_between_marks(self):
        report = {
            "stalls": [], "marks": {"songs.stress.start": 4.0, "songs.stress.end": 20.0},
            "cpuMarks": {"songs.stress.start": 3.25, "songs.stress.end": 9.5},
            "counters": {"songs.stress.end": 1, "songs.row": 900},
        }
        summary = summarize_stalls(report)
        self.assertEqual(summary["main_cpu_s"], 6.25)
        self.assertEqual(summary["rows_built"], 900)
        self.assertIsNone(summarize_stalls({"stalls": []})["main_cpu_s"])

    def test_report_without_marks_counts_every_stall(self):
        summary = summarize_stalls({"stalls": [{"at": 1.0, "ms": 120}]})
        self.assertEqual(summary["count"], 1)
        self.assertFalse(summary["completed"])


class LaunchAndBuildTests(unittest.TestCase):
    def test_parse_launch_pid(self):
        self.assertEqual(parse_launch_pid("com.sfenton.festivalscoretracker.ipad: 4242\n"), 4242)
        self.assertIsNone(parse_launch_pid("error"))

    def test_probe_builds_use_their_own_derived_data(self):
        self.assertTrue(str(app_bundle("mac", "Release", True)).endswith("mac-probe/Build/Products/Release/FestivalDesktop.app"))
        self.assertTrue(str(app_bundle("ipad", "Debug", False)).endswith(
            f"lane/Build/Products/Debug-iphonesimulator/{ipad_product().app_name}.app"))
        self.assertIn(ipad_product().scheme, build_argv("ipad", "Debug", False))
        argv = build_argv("mac", "Release", True)
        self.assertIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG", argv)
        self.assertNotIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG", build_argv("mac", "Release", False))

    def test_trace_argv_targets_the_simulator_when_given(self):
        from pathlib import Path
        argv = trace_argv(7, "Time Profiler", 10, Path("/tmp/x.trace"), "UDID")
        self.assertEqual(argv[3:5], ["--device", "UDID"])
        self.assertIn("--attach", argv)
        self.assertEqual(trace_argv(7, "SwiftUI", 5, Path("/tmp/x.trace"), None)[3], "--template")


class TraceTests(unittest.TestCase):
    def test_back_references_resolve(self):
        samples = parse_time_profile(TRACE)
        self.assertEqual(len(samples), 3)
        self.assertEqual(samples[1][0], "Main Thread 0x1")
        self.assertEqual(samples[1][1][1], ("SongRow.body", "FestivalDesktop.debug.dylib"))
        self.assertEqual(samples[2][1][0], ("leafA", "SwiftUICore"))

    def test_top_symbols_by_leaf_app_frame_and_thread(self):
        samples = parse_time_profile(TRACE)
        self.assertEqual(top_symbols(samples), [("leafA", 3)])
        self.assertEqual(top_symbols(samples, app_only=True), [("SongRow.body", 2), ("decode", 1)])
        self.assertEqual(top_symbols(samples, app_only=True, main_only=True), [("SongRow.body", 2)])


if __name__ == "__main__":
    unittest.main()
