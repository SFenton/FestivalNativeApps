"""Argument parsing and pure logic of ``tools/windows/uiwin.py``.

Covers step/selector/key parsing, presets, launch environment, perf
aggregation and task-status parsing without touching the desktop.
Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import tempfile
import unittest
from pathlib import Path

from tools.windows import uiwin as u


class SelectorAndKeyTests(unittest.TestCase):
    """UIA selectors and key combos."""

    def test_selectors(self):
        self.assertEqual(u.parse_selector("id=fst.songs.list"), {"kind": "id", "value": "fst.songs.list"})
        self.assertEqual(u.parse_selector("NAME=Refresh songs"), {"kind": "name", "value": "Refresh songs"})
        self.assertEqual(u.parse_selector(" 12, 34 "), {"kind": "xy", "x": 12, "y": 34})
        for bad in ("fst.x", "id=", "role=button"):
            with self.assertRaises(ValueError):
                u.parse_selector(bad)

    def test_keys(self):
        self.assertEqual(u.parse_keys("ctrl+shift+tab"), [0x11, 0x10, 0x09])
        self.assertEqual(u.parse_keys("alt+F4"), [0x12, 0x73])
        self.assertEqual(u.parse_keys("ctrl+l"), [0x11, ord("L")])
        with self.assertRaises(ValueError):
            u.parse_keys("ctrl+hyper")


class StepTests(unittest.TestCase):
    """Driver step expansion."""

    def test_selector_steps_with_timeout(self):
        step = u.parse_step("waitfor:id=fst.songs.list@10")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.songs.list"})
        self.assertEqual(step["timeout"], 10.0)
        self.assertNotIn("timeout", u.parse_step("invoke:id=fst.songs.refresh"))

    def test_coordinates_only_for_clicks(self):
        self.assertEqual(u.parse_step("click:5,6")["selector"]["kind"], "xy")
        self.assertEqual(u.parse_step("hover:5,6")["selector"]["kind"], "xy")
        self.assertEqual(u.parse_step("hover:id=fst.songs.list")["selector"]["kind"], "id")
        with self.assertRaises(ValueError):
            u.parse_step("invoke:5,6")

    def test_key_scroll_wait(self):
        self.assertEqual(u.parse_step("key:enter")["vk"], [0x0D])
        self.assertEqual(u.parse_step("scroll:down")["amount"], -3)
        scroll = u.parse_step("scroll:id=fst.songs.list,-7")
        self.assertEqual((scroll["amount"], scroll["selector"]["value"]), (-7, "fst.songs.list"))
        self.assertEqual(u.parse_step("wait:2")["arg"], "2.0")
        with self.assertRaises(ValueError):
            u.parse_step("scroll:sideways")
        with self.assertRaises(ValueError):
            u.parse_step("wait:soon")

    def test_scrollto_uses_the_scroll_pattern_selector(self):
        step = u.parse_step("scrollto:id=fst.player.available,62.5")
        self.assertEqual((step["selector"]["value"], step["percent"]), ("fst.player.available", 62.5))
        self.assertEqual(u.parse_step("reveal:id=fst.player.percentiles.Solo_Guitar@10")["timeout"], 10.0)
        with self.assertRaises(ValueError):
            u.parse_step("reveal:5,6")
        for bad in ("scrollto:id=x", "scrollto:id=x,101", "scrollto:id=x,down", "scrollto:5,6,10", "scrollto:,50"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_paths_resize_and_errors(self):
        shot = u.parse_step("shot:out/a.png@screen")
        self.assertEqual(shot["mode"], "screen")
        self.assertTrue(Path(shot["arg"]).is_absolute())
        self.assertTrue(shot["arg"].endswith("a.png"))
        self.assertEqual(u.parse_step("resize:compact")["op"], u.PRESETS["compact"])
        for bad in ("fly:x", "click:", "resize:huge"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_parse_steps(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "s.txt"
            script.write_text("# comment\nkey:tab\n\n")
            self.assertEqual(u.parse_steps("wait:1;", str(script)), ["key:tab", "wait:1"])
        with self.assertRaises(ValueError):
            u.parse_steps(None, None)


class PresetTests(unittest.TestCase):
    """Window presets and clamp reporting."""

    def test_required_presets(self):
        self.assertEqual(u.preset_op("compact"), {"kind": "size", "width": 500, "height": 800})
        self.assertEqual(u.preset_op("medium"), {"kind": "size", "width": 900, "height": 700})
        self.assertEqual(u.preset_op("wide"), {"kind": "size", "width": 1440, "height": 900})
        self.assertEqual(u.preset_op("portrait-tablet"),
                         {"kind": "size", "width": 800, "height": 1280})
        self.assertEqual(u.preset_op("full-screen"), {"kind": "fullscreen"})
        self.assertEqual(u.preset_op("snap-left"), {"kind": "snap-left"})
        self.assertEqual(u.preset_op("snap-right"), {"kind": "snap-right"})
        self.assertEqual(u.preset_op("1024x768"), {"kind": "size", "width": 1024, "height": 768})
        with self.assertRaises(ValueError):
            u.preset_op("gigantic")

    def test_preset_op_is_a_copy(self):
        u.preset_op("compact")["width"] = 1
        self.assertEqual(u.PRESETS["compact"]["width"], 500)

    def test_clamp_warning(self):
        op = u.preset_op("portrait-tablet")
        self.assertIsNone(u.clamp_warning(op, {"bounds_epx": [800, 1279]}))
        self.assertIn("clamped", u.clamp_warning(op, {"bounds_epx": [800, 1392]}))
        self.assertIsNone(u.clamp_warning(u.preset_op("snap-left"), {}))


class LaunchEnvTests(unittest.TestCase):
    """Debug environment mirrors the Apple/Android names."""

    def test_env(self):
        env = u.launch_env("songs", "player:1", ["FST_DEBUG_DRAWER=1"])
        self.assertEqual(env, {"FST_DEBUG_TAB": "songs", "FST_DEBUG_ROUTE": "player:1",
                               "FST_DEBUG_DRAWER": "1"})
        with self.assertRaises(ValueError):
            u.launch_env(None, None, ["broken"])

    def test_automation_marks_only_repo_publishes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            publish = root / "artifacts" / "app" / "Release-aot"
            publish.mkdir(parents=True)
            exe = publish / "FestivalScoreTracker.exe"
            original = u.ARTIFACTS_ROOT
            u.ARTIFACTS_ROOT = root / "artifacts"
            try:
                env: dict[str, str] = {}
                self.assertIsNone(u.prepare_automation(exe, env))
                self.assertEqual(env["FST_AUTOMATION"], "1")
                self.assertTrue((publish / u.AUTOMATION_MARKER).exists())
                elsewhere = root / "installed" / "FestivalScoreTracker.exe"
                self.assertIn("no fst-automation.marker", u.prepare_automation(elsewhere, {}))
                self.assertFalse((elsewhere.parent / u.AUTOMATION_MARKER).exists())
                debug = root / "bin" / "x64" / "Debug" / "FestivalScoreTracker.exe"
                self.assertIsNone(u.prepare_automation(debug, {}))
                opted_out = {"FST_AUTOMATION": "0"}
                self.assertIsNone(u.prepare_automation(elsewhere, opted_out))
                self.assertEqual(opted_out, {"FST_AUTOMATION": "0"})
            finally:
                u.ARTIFACTS_ROOT = original


class PerfTests(unittest.TestCase):
    """Counter paths, aggregation and PresentMon summaries."""

    def test_counter_paths(self):
        paths = u.counter_paths("Festival.App", 42)
        self.assertEqual(paths["cpu_percent"], r"\Process V2(Festival.App:42)\% Processor Time")
        self.assertIn("pid_42_*", paths["gpu_percent"])

    def test_summarize(self):
        self.assertEqual(u.summarize([]), {"mean": 0.0, "max": 0.0, "p95": 0.0, "samples": 0})
        summary = u.summarize([float(v) for v in range(1, 21)])
        self.assertEqual((summary["mean"], summary["max"], summary["p95"]), (10.5, 20.0, 19.0))

    def test_aggregate_counters_normalises_units(self):
        paths = u.counter_paths("app", 7)
        tick = {
            r"\process v2(app:7)\% processor time": 160.0,
            r"\process v2(app:7)\working set - private": 64 * 1024 * 1024,
            r"\gpu engine(pid_7_luid_0x1_phys_0_eng_0_engtype_3d)\utilization percentage": 30.0,
            r"\gpu engine(pid_7_luid_0x1_phys_0_eng_1_engtype_copy)\utilization percentage": 5.0,
            r"\gpu engine(pid_77_luid_0x1_phys_0_eng_0_engtype_3d)\utilization percentage": 99.0,
        }
        result = u.aggregate_counters([tick], paths, cpu_count=16)
        self.assertEqual(result["cpu_percent"]["mean"], 10.0)
        self.assertEqual(result["working_set_private_mb"]["mean"], 64.0)
        self.assertEqual(result["gpu_percent"]["mean"], 35.0)
        self.assertEqual(result["gpu_dedicated_mb"]["samples"], 0)

    def test_frame_stats(self):
        csv_v2 = "Application,FrameTime\napp,10\napp,20\napp,NA\n"
        stats = u.frame_stats(csv_v2)
        self.assertEqual(stats["frames"], 2)
        self.assertEqual(stats["fps_mean"], 66.7)
        self.assertEqual(u.frame_stats("Application,MsBetweenPresents\napp,5\n")["frames"], 1)
        self.assertEqual(u.frame_stats("Application,Other\napp,1\n"), {})
        self.assertEqual(u.frame_stats(""), {})


class TaskAndParserTests(unittest.TestCase):
    """Scheduled-task status parsing and CLI wiring."""

    def test_task_status(self):
        self.assertEqual(u.task_status('"\\FST_UiWin_x","N/A","Running"\r\n'), "Running")
        self.assertEqual(u.task_status('"\\FST_UiWin_x","9/28/2026 11:59:00 PM","Ready"'), "Ready")
        self.assertEqual(u.task_status(""), "")

    def test_parser(self):
        parser = u.build_parser()
        launch = parser.parse_args(["launch", "app.exe", "--tab", "songs", "--preset", "compact",
                                    "--extra", "K=V", "--arg=--flag"])
        self.assertEqual((launch.preset, launch.extra, launch.arg), ("compact", ["K=V"], ["--flag"]))
        self.assertIs(launch.func, u.cmd_launch)
        shot = parser.parse_args(["shot", "a.png", "--pid", "5", "--mode", "screen"])
        self.assertEqual((shot.pid, shot.mode, shot.hold), (5, "screen", 300.0))
        perf = parser.parse_args(["perf-sample", "--process", "Festival.App", "--presentmon"])
        self.assertEqual((perf.process, perf.seconds, perf.presentmon), ("Festival.App", 10, True))
        with self.assertRaises(SystemExit):
            parser.parse_args(["shot", "a.png", "--pid", "5", "--process", "x"])
        with self.assertRaises(SystemExit):
            parser.parse_args(["shot", "a.png", "--mode", "gdi"])

    def test_front_and_isolate_flags(self):
        parser = u.build_parser()
        front = parser.parse_args(["front", "--isolate"])
        self.assertIs(front.func, u.cmd_front)
        self.assertTrue(front.isolate)
        drive = parser.parse_args(["drive", "--steps", "wait:1", "--isolate", "--pid", "9"])
        self.assertEqual((drive.isolate, drive.pid), (True, 9))
        self.assertFalse(parser.parse_args(["tree"]).isolate)


class OcclusionRobustnessTests(unittest.TestCase):
    """Regression: other lanes' windows covering the target (foreground/isolate) and MSYS step paths."""

    def test_target_request(self):
        self.assertEqual(u.target_request(5, None, {"pid": 1}), {"pid": 5})
        self.assertEqual(u.target_request(None, "App", None), {"process": "App"})
        self.assertEqual(u.target_request(None, None, {"pid": 7}, isolate=True),
                         {"pid": 7, "isolate": True})
        for last in (None, {}, {"pid": 0}):
            with self.assertRaises(ValueError):
                u.target_request(None, None, last)

    def test_native_path(self):
        if u.os.name != "nt":
            self.skipTest("MSYS translation is Windows-only")
        self.assertEqual(u.native_path("/c/Users/me/a.png"), "C:/Users/me/a.png")
        self.assertEqual(u.native_path("/d"), "D:/")
        for unchanged in ("C:/x.png", "out/a.png", "/tmp2/a.png", r"C:\x\y.png"):
            self.assertEqual(u.native_path(unchanged), unchanged)
        shot = u.parse_step("shot:/c/Temp/fst/a.png")
        self.assertTrue(shot["arg"].upper().startswith("C:\\TEMP\\FST"), shot["arg"])

    def test_driver_foregrounds_before_input_steps(self):
        # The driver's contract lives in C#; guard that every real-input verb is foregrounded and that
        # isolation is restored when the request ends.
        source = (u.DRIVER_DIR / "Program.cs").read_text(encoding="utf-8")
        verbs = source.split("InputVerbs = [", 1)[1].split("]", 1)[0]
        for verb in ("click", "rightclick", "hover", "type", "key", "scroll"):
            self.assertIn(f'"{verb}"', verbs)
        self.assertIn("RestoreIsolated();", source.split("finally", 1)[1][:200])
        self.assertIn('"front" => Front(', source)


if __name__ == "__main__":
    unittest.main()
