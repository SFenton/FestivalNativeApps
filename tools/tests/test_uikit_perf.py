"""Pure parts of ``tools/uikit_perf.py``, ``uikit_perf_report.py`` and ``perf_sampler.py``."""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise _unittest.SkipTest("Apple perf tooling runs only on macOS")

import tempfile
import unittest
from pathlib import Path

from tools import perf_sampler, uikit_perf, uikit_perf_report

SURFACES = """# comment
[surfaces]
Songs (long list)|FST_DEBUG_TAB=songs
Player Profile|FST_DEBUG_TAB=songs FST_DEBUG_PROFILE=fixture-player-1:FixturePlayer FST_DEBUG_ROUTE=player:fixture-player-1

[nav]
Push Shop|FST_DEBUG_TAB=songs FST_PERF_NAV="shop;leaderboards"
"""

SAMPLES = (
    "t\tgpu_device\tgpu_renderer\tgpu_tiler\tbackboardd_cpu_s\tapp_cpu_s\tapp_rss_mb\n"
    "100.0\t10\t8\t2\t1.00\t2.00\t50.0\n"
    "101.0\t30\t20\t4\t1.50\t2.50\t51.0\n"
    "102.0\t50\t40\t6\t2.50\t3.50\t52.0\n"
    "103.0\t-1\t-1\t-1\t\t\t\n"
)

SCROLL = ("seconds=8.00 minstr=0.00 cpu_ms=900.00 main_ms=800.00 turns=500 over4=3 over8=1 over16=0 worst_ms=9.00 "
          "p95_ms=1.50 travelled=7200 fps=59.9 hz=60 dropped=2 hitch_ms_per_s=0.40 mem_mb=40.0 peak_mb=45.0 "
          "t0=100.000 t1=102.000")


class SurfaceFileTests(unittest.TestCase):
    def test_parses_sections_names_and_quoted_values(self):
        surfaces = uikit_perf.parse_surfaces(SURFACES)
        self.assertEqual([s.name for s in surfaces], ["Songs (long list)", "Player Profile", "Push Shop"])
        self.assertEqual([s.section for s in surfaces], ["surfaces", "surfaces", "nav"])
        self.assertEqual(surfaces[1].env["FST_DEBUG_PROFILE"], "fixture-player-1:FixturePlayer")
        self.assertEqual(surfaces[2].env["FST_PERF_NAV"], "shop;leaderboards")

    def test_only_keeps_exact_names(self):
        kept = uikit_perf.parse_surfaces(SURFACES, ["Player Profile"])
        self.assertEqual([s.name for s in kept], ["Player Profile"])

    def test_rejects_bad_lines(self):
        with self.assertRaises(ValueError):
            uikit_perf.parse_surfaces("[bogus]\n")
        with self.assertRaises(ValueError):
            uikit_perf.parse_surfaces("Name|NOEQUALS\n")
        with self.assertRaises(ValueError):
            uikit_perf.parse_surfaces("|A=1\n")

    def test_shipped_surfaces_file_parses_and_names_the_requested_pages(self):
        surfaces = uikit_perf.parse_surfaces(uikit_perf.DEFAULT_SURFACES.read_text())
        names = {s.name for s in surfaces if s.section == "surfaces"}
        for wanted in ("Songs (long list)", "Song Detail", "Leaderboards", "Full Rankings", "Song Leaderboard",
                       "Player Profile", "Statistics", "Rivals", "Suggestions", "Settings", "Shop", "Global Search"):
            self.assertIn(wanted, names)
        self.assertTrue(all("FST_PERF_NAV" in s.env for s in surfaces if s.section == "nav"))


class RunPlanTests(unittest.TestCase):
    def test_app_order_alternates_each_round(self):
        apps = ["swiftui", "uikit"]
        self.assertEqual(uikit_perf.app_order(1, apps), ["swiftui", "uikit"])
        self.assertEqual(uikit_perf.app_order(2, apps), ["uikit", "swiftui"])
        self.assertEqual(uikit_perf.app_order(3, apps), ["swiftui", "uikit"])
        self.assertEqual(apps, ["swiftui", "uikit"])

    def test_run_paths_use_the_names_the_report_reads(self):
        result, samples = uikit_perf.run_paths(Path("/o"), 2, "uikit", "Songs (long list)")
        self.assertEqual(result.name, "r2-uikit-Songs--long-list-.tsv")
        self.assertEqual(samples.name, "r2-uikit-Songs--long-list-.samples.tsv")
        self.assertRegex(result.name, uikit_perf_report.FILE)

    def test_launch_env_carries_surface_perf_and_fixture_keys(self):
        surface = uikit_perf.Surface("Settings", {"FST_DEBUG_TAB": "settings"})
        env = uikit_perf.launch_env(surface, Path("/o/r.tsv"), 12, "http://127.0.0.1:9", 8, 900)
        self.assertTrue(all(k.startswith("SIMCTL_CHILD_") for k in env))
        self.assertEqual(env["SIMCTL_CHILD_FST_DEBUG_TAB"], "settings")
        self.assertEqual(env["SIMCTL_CHILD_FST_API_BASE_URL"], "http://127.0.0.1:9")
        self.assertEqual(env["SIMCTL_CHILD_FST_PERF_AUTORUN"], "12")
        self.assertEqual(env["SIMCTL_CHILD_FST_PERF_FILE"], "/o/r.tsv")
        self.assertEqual(env["SIMCTL_CHILD_FST_PERF_NAME"], "Settings")
        self.assertEqual(env["SIMCTL_CHILD_FST_PERF_SECONDS"], "8")

    def test_live_launch_sets_no_base_url_and_a_surface_can_override_defaults(self):
        surface = uikit_perf.Surface("S", {"FST_UI_TEST_CLEAR_PROFILE": "0"})
        env = uikit_perf.launch_env(surface, Path("/o/r.tsv"), 9, None)
        self.assertNotIn("SIMCTL_CHILD_FST_API_BASE_URL", env)
        self.assertEqual(env["SIMCTL_CHILD_FST_UI_TEST_CLEAR_PROFILE"], "0")

    def test_budget_grows_with_settle_and_nav_cycles(self):
        scroll = uikit_perf.Surface("S")
        nav = uikit_perf.Surface("N", section="nav")
        self.assertGreater(uikit_perf.run_budget(scroll, 12, 8), 12 + 3 * 8)
        self.assertGreater(uikit_perf.run_budget(nav, 12, 8, cycles=6), 12 + 6 * 3)

    def test_finished_needs_the_done_line(self):
        self.assertFalse(uikit_perf.finished("FSTPERF\tS\tidle\ta=1\n"))
        self.assertTrue(uikit_perf.finished("FSTPERF\tS\tidle\ta=1\nFSTPERF_DONE\n"))

    def test_build_is_release_with_debug_hooks_in_its_own_derived_data(self):
        argv = uikit_perf.build_argv(uikit_perf.APPS["uikit"])
        self.assertIn("FestivalMobileUIKit", argv)
        self.assertEqual(argv[argv.index("-configuration") + 1], "Release")
        self.assertIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG", argv)
        self.assertIn("perf-probe", argv[argv.index("-derivedDataPath") + 1])
        self.assertEqual(uikit_perf.app_bundle(uikit_perf.APPS["swiftui"]).name, "FestivalMobile.app")
        self.assertEqual(uikit_perf.APPS["uikit"].bundle_id, "com.sfenton.festivalscoretracker.native.uikit")

    def test_fixture_service_args_and_ready_line(self):
        self.assertEqual(uikit_perf.fixture_args()[:2], ["--port", "0"])
        self.assertIn("--large-catalogue", uikit_perf.fixture_args())
        self.assertEqual(uikit_perf.parse_fixture_port("Local test fixture service on 127.0.0.1:54321\n"), 54321)
        self.assertIsNone(uikit_perf.parse_fixture_port("starting"))


class SamplerTests(unittest.TestCase):
    def test_gpu_values_read_the_three_utilisations(self):
        text = '"PerformanceStatistics" = {"Device Utilization %"=37,"Renderer Utilization %"=21,"Tiler Utilization %"=9}'
        self.assertEqual(perf_sampler.gpu_values(text), [37, 21, 9])
        self.assertEqual(perf_sampler.gpu_values("nothing"), [-1, -1, -1])

    def test_find_rows_matches_this_simulators_render_server_and_app(self):
        udid = "AAAA-1111"
        rows = [
            (10, 1, "0:01.00", 1000, f"/x/{udid}/launchd_sim"),
            (11, 10, "0:02.00", 2000, "/usr/libexec/backboardd"),
            (12, 10, "0:03.00", 3000, f"/x/{udid}/FestivalMobileUIKit.app/FestivalMobileUIKit"),
            (13, 10, "0:04.00", 4000, f"/x/{udid}/FestivalMobile.app/FestivalMobile"),
            (20, 1, "0:01.00", 1000, "/other/BBBB/launchd_sim"),
            (21, 20, "0:09.00", 9000, "/usr/libexec/backboardd"),
        ]
        backboard, app = perf_sampler.find_rows(rows, udid, "FestivalMobile")
        self.assertEqual(backboard[0], 11)
        self.assertEqual(app[0], 13)  # the UIKit executable name does not match the SwiftUI app's
        _, port = perf_sampler.find_rows(rows, udid, "FestivalMobileUIKit")
        self.assertEqual(port[0], 12)
        self.assertEqual(perf_sampler.find_rows(rows, "CCCC", "FestivalMobile"), (None, None))

    def test_seconds_parses_ps_time(self):
        self.assertEqual(perf_sampler.seconds("1:02.50"), 62.5)


class ReportParsingTests(unittest.TestCase):
    def test_samples_interpolate_and_window(self):
        rows = uikit_perf_report.parse_samples(SAMPLES)
        self.assertEqual(len(rows), 4)
        self.assertIsNone(rows[3]["bb"])
        self.assertAlmostEqual(uikit_perf_report.at(rows, "bb", 100.5), 1.25)
        self.assertEqual(uikit_perf_report.at(rows, "bb", 50), 1.0)
        self.assertEqual(uikit_perf_report.at(rows, "bb", 500), 2.5)
        self.assertIsNone(uikit_perf_report.at([], "bb", 1))
        self.assertEqual(uikit_perf_report.window(rows, "gpu", 100, 102), 30)
        self.assertIsNone(uikit_perf_report.window(rows, "gpu", 200, 300))

    def test_pairs_keep_only_numbers(self):
        pairs = uikit_perf_report.parse_pairs("fps=59.9 route=shop n=5 t0=-1.5 note")
        self.assertEqual(pairs, {"fps": 59.9, "n": 5.0, "t0": -1.5})

    def test_parse_run_reads_fstperf_lines_only(self):
        text = "FSTPERF\tSongs\tidle\ta=1\nnoise\nFSTPERF\tSongs\tscroll\tb=2\nFSTPERF_DONE\n"
        self.assertEqual(uikit_perf_report.parse_run(text), [("Songs", "idle", "a=1"), ("Songs", "scroll", "b=2")])

    def test_scroll_metrics_add_host_numbers_for_the_runs_window(self):
        host = uikit_perf_report.parse_samples(SAMPLES)
        metrics = uikit_perf_report.scroll_metrics(SCROLL, host)
        self.assertAlmostEqual(metrics["render_ms"], 1500.0)  # backboardd 1.00 s -> 2.50 s
        self.assertAlmostEqual(metrics["gpu_pct"], 30.0)
        self.assertAlmostEqual(metrics["gpu_renderer_pct"], 68 / 3)
        self.assertEqual(metrics["fps"], 59.9)

    def test_scroll_line_without_a_window_is_an_error(self):
        self.assertIn("error", uikit_perf_report.scroll_metrics("no scroll view: presented=none", []))


class ReportRenderTests(unittest.TestCase):
    def write_run(self, directory: Path, round_number: int, app: str, fps: float):
        stem = f"r{round_number}-{app}-Songs--long-list-"
        scroll = SCROLL.replace("fps=59.9", f"fps={fps}")
        (directory / f"{stem}.tsv").write_text(
            "FSTPERF\tSongs (long list)\tlaunch\tlaunch=1 ready_ms=40.0 first_content_ms=900.0 cpu_ms=700 instr_m=1500 mem_mb=60.0\n"
            f"FSTPERF\tSongs (long list)\tidle\t{scroll}\n"
            f"FSTPERF\tSongs (long list)\tscroll\t{scroll}\n"
            f"FSTPERF\tSongs (long list)\tscroll\t{scroll}\n"
            "FSTPERF\tPush Shop\tpush\troute=shop n=5 cold_first_ms=90.0 first_p50_ms=40.0 first_p95_ms=60.0 settled_p50_ms=380.0 "
            "settled_p95_ms=420.0 turn_p95_ms=1.20 turn_worst_ms=14.0 over8=1 main_ms=120 cpu_ms=140\n"
            "FSTPERF\tPush Shop\tpop\tno navigation hooks registered\n"
            "FSTPERF_DONE\n")
        (directory / f"{stem}.samples.tsv").write_text(SAMPLES)

    def test_report_has_scroll_launch_and_nav_tables_with_medians(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            for round_number, (a, b) in enumerate([(50.0, 58.0), (54.0, 60.0), (52.0, 59.0)], 1):
                self.write_run(directory, round_number, "swiftui", a)
                self.write_run(directory, round_number, "uikit", b)
            text, rows = uikit_perf_report.render(uikit_perf_report.collect(directory))
        self.assertIn("### Scroll and idle", text)
        self.assertIn("### Cold launch", text)
        self.assertIn("### Navigation", text)
        self.assertIn("| Surface | Kind | App | n | fps |", text)
        swiftui = next(r for r in rows if r["table"] == "Surface" and r["app"] == "swiftui" and r["kind"] == "scroll")
        uikit = next(r for r in rows if r["table"] == "Surface" and r["app"] == "uikit" and r["kind"] == "scroll")
        self.assertEqual(swiftui["n"], 6)  # two scroll runs per round, three rounds
        self.assertEqual((swiftui["fps"], uikit["fps"]), (52.0, 59.0))
        self.assertIn("| Songs (long list) | SwiftUI | 3 | 900 |", text)
        self.assertIn("| Push Shop | push | UIKit | 3 | 90 |", text)
        self.assertIn("| Push Shop | pop | UIKit | 0 | no navigation hooks registered |", text)

    def test_empty_directory_renders_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            text, rows = uikit_perf_report.render(uikit_perf_report.collect(Path(tmp)))
        self.assertEqual((text, rows), ("", []))


if __name__ == "__main__":
    unittest.main()
