"""Argument parsing and pure device logic of ``tools/android/device.py``.

These cover everything ``device.py`` decides before it touches adb or the
emulator, so lanes can trust its parsing without a running device.
Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import argparse
import tempfile
import unittest
from pathlib import Path

from tools.android import device as d

UI_XML = """<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node text="" resource-id="" content-desc="" bounds="[0,0][1080,2424]">
    <node text="Songs" resource-id="fst.nav.songs" content-desc="" bounds="[0,2200][360,2424]" />
    <node text="Settings" resource-id="com.x:id/settings" content-desc="Open settings"
          bounds="[360,2200][720,2424]" />
    <node text="Hidden" resource-id="fst.hidden" content-desc="" bounds="[0,0][0,0]" />
  </node>
</hierarchy>"""


class LaunchTests(unittest.TestCase):
    """Debug extras and the ``am start`` line."""

    def test_parse_extras(self):
        self.assertEqual(d.parse_extras(["FST_DEBUG_DRAWER=1", "A=b=c"]),
                         [("FST_DEBUG_DRAWER", "1"), ("A", "b=c")])
        self.assertEqual(d.parse_extras(None), [])
        for bad in ("novalue", "=x"):
            with self.assertRaises(ValueError):
                d.parse_extras([bad])

    def test_launch_extras_order(self):
        extras = d.launch_extras("songs", "player:1", [("K", "v")])
        self.assertEqual(extras, [("FST_DEBUG_TAB", "songs"), ("FST_DEBUG_ROUTE", "player:1"),
                                  ("K", "v")])
        self.assertEqual(d.launch_extras(None, None, []), [])

    def test_am_start_quotes_and_targets_display_zero(self):
        line = d.am_start_command("pkg/.Main", [("FST_DEBUG_ROUTE", "it's a route")])
        self.assertTrue(line.startswith(
            "am start -W -S --activity-clear-task --display 0 -n 'pkg/.Main'"))
        self.assertIn("--es 'FST_DEBUG_ROUTE' 'it'\\''s a route'", line)

    def test_reused_instance(self):
        self.assertTrue(d.reused_instance(
            "Warning: Activity not started, intent has been delivered to currently "
            "running top-most instance.\nLaunchState: UNKNOWN (0)"))
        self.assertFalse(d.reused_instance("Status: ok\nLaunchState: COLD\nComplete"))

    def test_launch_retries_after_reused_instance(self):
        class FakeDevice:
            def __init__(self, outputs):
                self.outputs, self.commands = list(outputs), []

            def shell(self, command, cap=60.0, check=True):
                self.commands.append(command)
                return self.outputs.pop(0) if command.startswith("am start") else ""

        args = argparse.Namespace(activity="pkg/.Main", package="pkg", tab="settings",
                                  route=None, extra=None)
        stale = "Warning: Activity not started, intent has been delivered"
        device = FakeDevice([stale, "LaunchState: COLD"])
        d._launch(device, args)
        self.assertEqual(device.commands[1], "am force-stop 'pkg'")
        self.assertEqual(sum(c.startswith("am start") for c in device.commands), 2)
        self.assertIn("--es 'FST_DEBUG_TAB' 'settings'", device.commands[-1])
        with self.assertRaises(d.DeviceError):
            d._launch(FakeDevice([stale, stale]), args)

    def test_remote_quote(self):
        self.assertEqual(d.remote_quote("a b"), "'a b'")
        self.assertEqual(d.remote_quote("x'y"), "'x'\\''y'")


class EmulatorArgsTests(unittest.TestCase):
    """Deterministic, headless-by-default emulator launches on the FST port."""

    def test_headless_defaults(self):
        args = d.emulator_args("FST_Phone", gpu="swiftshader_indirect")
        self.assertEqual(args[:4], ["-avd", "FST_Phone", "-port", str(d.FST_PORT)])
        for flag in ("-no-snapshot", "-no-boot-anim", "-no-audio", "-no-window"):
            self.assertIn(flag, args)

    def test_window_flag(self):
        self.assertNotIn("-no-window", d.emulator_args("FST_Phone", window=True))


class MatrixTests(unittest.TestCase):
    """The AVD matrix is internally consistent."""

    def test_names_and_forms(self):
        self.assertEqual(set(d.AVDS), {"FST_Phone", "FST_Book_Fold", "FST_Passport_Fold",
                                       "FST_TriFold", "FST_Tablet", "FST_Resizable"})
        for name, spec in d.AVDS.items():
            self.assertTrue(name.startswith(d.FST_PREFIX))
            if spec.form in ("book", "passport", "trifold"):
                self.assertIn(spec.form, d.POSTURES)

    def test_trifold_has_two_hinges_and_no_half_open(self):
        config = d.AVDS["FST_TriFold"].config
        self.assertEqual(config["hw.sensor.hinge.count"], "2")
        self.assertNotIn("half", d.POSTURES["trifold"])

    def test_config_lines_replace_in_place_and_append_sorted(self):
        text = d.config_lines("a=1\nb=2\n\n", {"b": "9", "d": "4", "c": "3"})
        self.assertEqual(text, "a=1\nb=9\nc=3\nd=4\n")


class PostureTests(unittest.TestCase):
    """Posture names, explicit angles and validation."""

    def test_named_postures(self):
        self.assertEqual(d.posture_angles("book", "half"), (90,))
        self.assertEqual(d.posture_angles("trifold", "partial"), (180, 0))

    def test_explicit_angles(self):
        self.assertEqual(d.posture_angles("trifold", "180, 45"), (180, 45))

    def test_errors(self):
        with self.assertRaises(ValueError):
            d.posture_angles("phone", "folded")
        with self.assertRaises(ValueError):
            d.posture_angles("book", "tent")
        with self.assertRaises(ValueError):
            d.posture_angles("trifold", "180")
        with self.assertRaises(ValueError):
            d.posture_angles("book", "200")

    def test_trifold_layout(self):
        self.assertEqual(d.trifold_layout((0, 0)), ("720x1584", ""))
        self.assertEqual(d.trifold_layout((0, 180)), ("720x1584", ""))
        size, features = d.trifold_layout((180, 0))
        self.assertEqual(size, "1440x1584")
        self.assertEqual(features.count("fold-"), 1)
        size, features = d.trifold_layout((180, 180))
        self.assertIsNone(size)
        self.assertEqual(features.count("fold-"), 2)

    def test_resize_presets(self):
        self.assertEqual(d.RESIZE_PRESETS["phone"], (None, None, ""))
        self.assertIn("fold-", d.RESIZE_PRESETS["foldable"][2])


class StepTests(unittest.TestCase):
    """Driver step scripts."""

    def test_parse_steps_file_then_inline(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "s.txt"
            script.write_text("# c\nwait:1\n\nback\n")
            self.assertEqual(d.parse_steps("shot:a.png ; ", str(script)),
                             ["wait:1", "back", "shot:a.png"])
        with self.assertRaises(ValueError):
            d.parse_steps(" ; # x", None)

    def test_parse_step(self):
        self.assertEqual(d.parse_step("TAP: text=Songs"), ("tap", "text=Songs"))
        self.assertEqual(d.parse_step("back"), ("back", ""))
        for bad in ("fly:x", "tap:", "shot"):
            with self.assertRaises(ValueError):
                d.parse_step(bad)

    def test_record_step(self):
        self.assertEqual(d.parse_step("record:out/a.mp4"), ("record", "out/a.mp4"))
        self.assertEqual(d.parse_step("record:stop"), ("record", "stop"))
        with self.assertRaises(ValueError):
            d.parse_step("record")
        self.assertEqual(d.record_command(), "screenrecord --time-limit 180 '/sdcard/fst-record.mp4'")
        self.assertIn("--time-limit 180 ", d.record_command(limit=900))
        self.assertIsNone(d.Device(None).stop_recording())

    def test_parse_selector(self):
        self.assertEqual(d.parse_selector("id=fst.nav.songs"), ("id", "fst.nav.songs"))
        self.assertEqual(d.parse_selector(" 10 , 20 "), ("xy", "10,20"))
        with self.assertRaises(ValueError):
            d.parse_selector("bogus")

    def test_toggle_arg(self):
        self.assertTrue(d.toggle_arg("ON"))
        self.assertFalse(d.toggle_arg("0"))
        with self.assertRaises(ValueError):
            d.toggle_arg("maybe")


class UiTreeTests(unittest.TestCase):
    """UIAutomator dump parsing."""

    def test_parse_bounds(self):
        self.assertEqual(d.parse_bounds("[0,63][1080,210]"), (0, 63, 1080, 210))
        with self.assertRaises(ValueError):
            d.parse_bounds("0,0,1,1")

    def test_find_center_by_kind(self):
        self.assertEqual(d.find_center(UI_XML, "id", "fst.nav.songs"), (180, 2312))
        self.assertEqual(d.find_center(UI_XML, "id", "settings"), (540, 2312))
        self.assertEqual(d.find_center(UI_XML, "text", "Settings"), (540, 2312))
        self.assertEqual(d.find_center(UI_XML, "desc", "Open settings"), (540, 2312))
        self.assertEqual(d.find_center(UI_XML, "contains", "Song"), (180, 2312))

    def test_zero_size_and_missing_nodes(self):
        self.assertIsNone(d.find_center(UI_XML, "id", "fst.hidden"))
        self.assertIsNone(d.find_center(UI_XML, "text", "Nope"))

    def test_swipe_vector(self):
        self.assertEqual(d.swipe_vector("up", 1000, 2000), (500, 1500, 500, 500, 300))
        self.assertEqual(d.swipe_vector("right", 1000, 2000), (200, 1000, 800, 1000, 300))
        self.assertEqual(d.swipe_vector("1,2,3,4", 9, 9), (1, 2, 3, 4, 300))
        self.assertEqual(d.swipe_vector("1,2,3,4,50", 9, 9), (1, 2, 3, 4, 50))
        with self.assertRaises(ValueError):
            d.swipe_vector("diagonal", 9, 9)

    def test_input_text_arg(self):
        self.assertEqual(d.input_text_arg("a b%"), "'a%sb\\%'")

    def test_parse_wm_size(self):
        self.assertEqual(d.parse_wm_size("Physical size: 1080x2424"), (1080, 2424))
        self.assertEqual(d.parse_wm_size("Physical size: 2160x1584\nOverride size: 720x1584"),
                         (720, 1584))
        with self.assertRaises(ValueError):
            d.parse_wm_size("nothing")


class ProbeAndProcessTests(unittest.TestCase):
    """Probe log lines, display ids and FST process matching."""

    def test_parse_probe_line(self):
        line = ("09-28 I FST_PROBE: window=2160x1584 features=[fold state=flat "
                "bounds=720,0,720,1584; fold state=half bounds=1440,0,1440,1584]")
        report = d.parse_probe_line(line)
        self.assertEqual(report["window"], "2160x1584")
        self.assertEqual([f["state"] for f in report["features"]], ["flat", "half"])
        self.assertEqual(report["features"][0]["bounds"], [720, 0, 720, 1584])
        self.assertEqual(d.parse_probe_line("FST_PROBE: window=1x2 features=[]")["features"], [])
        self.assertEqual(d.parse_probe_line("FST_PROBE: error=boom")["error"], "boom")
        self.assertIsNone(d.parse_probe_line("FST_PROBE: registered vendorApiLevel=10"))
        self.assertIsNone(d.parse_probe_line("unrelated"))

    def test_default_physical_display(self):
        out = ('Displays:\nDisplay id 2: DisplayInfo{uniqueId "local:222"}\n'
               'Display id 0: DisplayInfo{"Built-in", uniqueId "local:4619827259835644672"}\n')
        self.assertEqual(d.default_physical_display(out), "4619827259835644672")
        self.assertIsNone(d.default_physical_display("Displays:\n"))

    def test_fst_process_ids_only_match_fst_avds_on_fst_port(self):
        listing = ("1\tqemu -avd FST_TriFold -port 5580 -no-window\n"
                   "2\temulator.exe -avd Pixel_5_API_36 -port 5560\n"
                   "3\tqemu -avd FST_Phone -port 55801\n"
                   "4\temulator.exe -avd FST_Phone -port 5560\n"
                   "junk line\n")
        self.assertEqual(d.fst_process_ids(listing), [1])


class GradleAndParserTests(unittest.TestCase):
    """Connected-test filters and CLI wiring."""

    def test_gradle_test_args(self):
        task = ":app:connectedDebugAndroidTest"
        self.assertEqual(d.gradle_test_args(None, task), [task, "--console=plain"])
        self.assertIn("-Pandroid.testInstrumentationRunnerArguments.class=a.B#c",
                      d.gradle_test_args("a.B#c", task))
        self.assertIn("-Pandroid.testInstrumentationRunnerArguments.package=a.b",
                      d.gradle_test_args("package:a.b", task))

    def test_parser_defaults_and_choices(self):
        parser = d.build_parser()
        shot = parser.parse_args(["shot", "a.png", "b.png", "--tab", "songs", "--extra", "K=V"])
        self.assertEqual(shot.avd, d.DEFAULT_AVD)
        self.assertEqual(shot.out, ["a.png", "b.png"])
        self.assertEqual(shot.hold, 300.0)
        self.assertEqual(shot.extra, ["K=V"])
        self.assertIs(shot.func, d.cmd_shot)
        boot = parser.parse_args(["boot", "FST_TriFold", "--window"])
        self.assertEqual((boot.name, boot.window), ("FST_TriFold", True))
        features = parser.parse_args(["features", "--avd", "FST_Book_Fold", "folded", "half"])
        self.assertEqual(features.postures, ["folded", "half"])
        test = parser.parse_args(["test", "a.B"])
        self.assertEqual(test.task, ":app:connectedDebugAndroidTest")
        with self.assertRaises(SystemExit):
            parser.parse_args(["boot", "Pixel_5_API_36"])
        with self.assertRaises(SystemExit):
            parser.parse_args(["shot", "a.png", "--avd", "Other"])

    def test_main_reports_value_errors_as_exit_3(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = str(Path(tmp) / "none.apk")
            self.assertEqual(d.main(["install", missing]), 3)


if __name__ == "__main__":
    unittest.main()
