"""Pure parts of ``tools/mac_app.py``: sizes, profiles, launch environment, window choice.

Nothing here builds, launches or captures; the subprocess wrappers are exercised by
running the tool itself on the Mac.
"""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise _unittest.SkipTest("Apple Mac app tooling runs only on macOS")

import os
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.mac_app import (
    PROFILES,
    helper_stale,
    launch_argv,
    launch_environment,
    parse_size,
    parse_window_lines,
    pick_main_window,
    resolve_profile,
    screencapture_argv,
    validate_command,
)


class ParseSizeTests(unittest.TestCase):
    """``--size`` accepts WIDTHxHEIGHT within sane window bounds."""

    def test_parses_width_and_height(self):
        self.assertEqual(parse_size("1280x800"), (1280, 800))
        self.assertEqual(parse_size(" 760 X 600 "), (760, 600))
        self.assertEqual(parse_size("900×700"), (900, 700))

    def test_rejects_malformed_or_out_of_range(self):
        for raw in ("1280", "1280x", "axb", "100x800", "1280x9000", "1x2x3"):
            with self.assertRaises(ValueError, msg=raw):
                parse_size(raw)


class ProfileTests(unittest.TestCase):
    """``--profile`` maps the SFentonX alias or takes ``id:name``."""

    def test_alias_is_case_insensitive(self):
        self.assertEqual(resolve_profile("SFentonX"), PROFILES["sfentonx"])
        self.assertTrue(PROFILES["sfentonx"].endswith(":SFentonX"))

    def test_explicit_identity_and_none(self):
        self.assertEqual(resolve_profile("abc123:Some Name"), "abc123:Some Name")
        self.assertIsNone(resolve_profile(None))

    def test_rejects_bad_identity(self):
        for raw in ("nobody", ":Name", "abc:"):
            with self.assertRaises(ValueError, msg=raw):
                resolve_profile(raw)


class LaunchEnvironmentTests(unittest.TestCase):
    """The launch environment carries only this launch's deep link."""

    def test_sets_requested_keys(self):
        env = launch_environment(
            {"PATH": "/bin"}, tab="songs", route="shop", profile="a:B", anonymous=True,
            size=(1280, 800), extra=["FST_DEBUG_KEEP_FADES=1"],
        )
        self.assertEqual(env["FST_DEBUG_TAB"], "songs")
        self.assertEqual(env["FST_DEBUG_ROUTE"], "shop")
        self.assertEqual(env["FST_DEBUG_PROFILE"], "a:B")
        self.assertEqual(env["FST_DEBUG_ANONYMOUS"], "1")
        self.assertEqual(env["FST_DEBUG_WINDOW_SIZE"], "1280x800")
        self.assertEqual(env["FST_DEBUG_KEEP_FADES"], "1")
        self.assertEqual(env["PATH"], "/bin")

    def test_drops_inherited_deep_links_and_keeps_base(self):
        base = {"FST_DEBUG_ROUTE": "player:x", "FST_DEBUG_PROFILE": "a:b", "HOME": "/h"}
        env = launch_environment(base)
        self.assertNotIn("FST_DEBUG_ROUTE", env)
        self.assertNotIn("FST_DEBUG_PROFILE", env)
        self.assertEqual(base["FST_DEBUG_ROUTE"], "player:x")

    def test_rejects_extra_without_equals(self):
        with self.assertRaises(ValueError):
            launch_environment({}, extra=["NOPE"])


class LaunchArgvTests(unittest.TestCase):
    """The app starts without window restoration."""

    def test_ignores_persistent_state(self):
        argv = launch_argv(Path("/x/FestivalDesktop.app"))
        self.assertEqual(argv[0], "/x/FestivalDesktop.app/Contents/MacOS/FestivalDesktop")
        self.assertEqual(argv[1:], ["-ApplePersistenceIgnoreState", "YES"])


class WindowChoiceTests(unittest.TestCase):
    """Only the app's own main window is ever captured."""

    def test_parses_json_lines_and_skips_junk(self):
        text = 'warning\n{"id": 5, "layer": 0, "w": 800, "h": 600}\n{broken\n'
        self.assertEqual(parse_window_lines(text), [{"id": 5, "layer": 0, "w": 800, "h": 600}])

    def test_picks_largest_normal_layer_window(self):
        windows = [
            {"id": 1, "layer": 0, "w": 1280, "h": 820},
            {"id": 2, "layer": 0, "w": 1400, "h": 900},
            {"id": 3, "layer": 101, "w": 3000, "h": 2000},  # menu/overlay layer
            {"id": 4, "layer": 0, "w": 150, "h": 40},  # tooltip-sized
        ]
        self.assertEqual(pick_main_window(windows)["id"], 2)

    def test_name_filter_picks_titled_window(self):
        windows = [
            {"id": 1, "layer": 0, "w": 1280, "h": 820, "name": "Songs"},
            {"id": 2, "layer": 0, "w": 640, "h": 760, "name": "Festival Score Tracker Settings"},
        ]
        self.assertEqual(pick_main_window(windows, "settings")["id"], 2)
        self.assertIsNone(pick_main_window(windows, "Nope"))

    def test_no_candidate_means_no_capture(self):
        self.assertIsNone(pick_main_window([]))
        self.assertIsNone(pick_main_window([{"id": 3, "layer": 25, "w": 900, "h": 900}]))

    def test_screencapture_is_window_only(self):
        argv = screencapture_argv(42, Path("/tmp/out.png"))
        self.assertEqual(argv, ["screencapture", "-x", "-o", "-l", "42", "/tmp/out.png"])
        for bad in (0, -1, None, "42"):
            with self.assertRaises(ValueError, msg=repr(bad)):
                screencapture_argv(bad, Path("/tmp/out.png"))


class CommandTests(unittest.TestCase):
    """Debug shell commands are checked before they reach the app."""

    def test_accepts_known_commands(self):
        for raw in ("back", " sort ", "select:2", "select:leaderboards", "route:player:abc", "settings", "settings:paths", "menus"):
            self.assertEqual(validate_command(raw), raw.strip())

    def test_rejects_unknown_or_malformed(self):
        for raw in ("explode", "select", "select:", "back:1", "route:", "settings:"):
            with self.assertRaises(ValueError, msg=raw):
                validate_command(raw)


class HelperStalenessTests(unittest.TestCase):
    """The Swift window helper recompiles only when its source is newer."""

    def test_missing_or_older_binary_is_stale(self):
        with TemporaryDirectory() as tmp:
            source = Path(tmp) / "mac_window.swift"
            binary = Path(tmp) / "mac_window"
            source.write_text("// helper")
            self.assertTrue(helper_stale(source, binary))
            binary.write_text("bin")
            now = time.time()
            os.utime(source, (now - 10, now - 10))
            os.utime(binary, (now, now))
            self.assertFalse(helper_stale(source, binary))
            os.utime(source, (now + 10, now + 10))
            self.assertTrue(helper_stale(source, binary))


if __name__ == "__main__":
    unittest.main()
