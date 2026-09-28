"""Step-script parsing and build-cache decisions for the simulator driver.

These exercise the pure, subprocess-free pieces of ``tools/ios_sim.py`` — the
functions ``drive`` composes before it ever touches ``xcodebuild`` or
``simctl`` — so lanes can trust the driver's argument handling without a
real simulator.
"""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise _unittest.SkipTest("Apple simulator tooling runs only on macOS")

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.ios_sim import (
    accessibility_instructions,
    app_bundle_for,
    bmp_is_dark,
    classify_pose,
    match_pose_control,
    driver_build_stale,
    output_paths,
    parse_steps,
    resolve_device,
    source_hash,
    write_driver_hash,
)


class ParseStepsTests(unittest.TestCase):
    """`--steps` and `--steps-file` combine into one ordered, cleaned list."""

    def test_inline_steps_split_on_semicolon_and_trim(self):
        steps = parse_steps("tap:fst.nav.settings ; shot:/tmp/a.png", None)
        self.assertEqual(steps, ["tap:fst.nav.settings", "shot:/tmp/a.png"])

    def test_steps_file_splits_on_newline_and_skips_blank_and_comments(self):
        with TemporaryDirectory() as tmp:
            script = Path(tmp) / "steps.txt"
            script.write_text(
                "# open settings\n"
                "tap:fst.nav.settings\n"
                "\n"
                "   \n"
                "swipe:up\n"
            )
            steps = parse_steps(None, str(script))
        self.assertEqual(steps, ["tap:fst.nav.settings", "swipe:up"])

    def test_file_steps_precede_inline_steps(self):
        with TemporaryDirectory() as tmp:
            script = Path(tmp) / "steps.txt"
            script.write_text("wait:1\n")
            steps = parse_steps("shot:/tmp/a.png", str(script))
        self.assertEqual(steps, ["wait:1", "shot:/tmp/a.png"])

    def test_neither_source_raises(self):
        with self.assertRaises(ValueError):
            parse_steps(None, None)

    def test_only_comments_and_blanks_raises(self):
        with self.assertRaises(ValueError):
            parse_steps("  ; # nope ; \n", None)


class OutputPathsTests(unittest.TestCase):
    """`shot:`/`tree:` steps name host paths the caller should verify."""

    def test_collects_shot_and_tree_paths_in_order(self):
        steps = [
            "tap:fst.nav.settings",
            "shot:/tmp/one.png",
            "swipe:up",
            "tree:/tmp/one.tree.txt",
            "shot:/tmp/two.png",
        ]
        self.assertEqual(
            output_paths(steps), ["/tmp/one.png", "/tmp/one.tree.txt", "/tmp/two.png"]
        )

    def test_ignores_other_verbs_and_missing_arguments(self):
        self.assertEqual(output_paths(["wait:1", "back", "tap:x"]), [])


class ResolveDeviceTests(unittest.TestCase):
    """Aliases map to UDIDs; anything else (a raw UDID) passes through."""

    def test_known_alias(self):
        self.assertEqual(
            resolve_device("iphone"), "4E9F2A49-127D-40BC-A909-08AF3D4BE6A5"
        )

    def test_unknown_alias_passes_through_as_udid(self):
        self.assertEqual(resolve_device("SOME-OTHER-UDID"), "SOME-OTHER-UDID")


class SourceHashTests(unittest.TestCase):
    """The driver rebuild cache must react to real edits and nothing else."""

    def test_hash_is_stable_for_unchanged_files(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.swift").write_text("struct A {}")
            first = source_hash([root])
            second = source_hash([root])
        self.assertEqual(first, second)

    def test_hash_changes_when_a_file_is_edited(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "a.swift"
            target.write_text("struct A {}")
            before = source_hash([root])
            target.write_text("struct A { let x = 1 }")
            after = source_hash([root])
        self.assertNotEqual(before, after)

    def test_hash_changes_when_a_file_is_added(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.swift").write_text("struct A {}")
            before = source_hash([root])
            (root / "b.swift").write_text("struct B {}")
            after = source_hash([root])
        self.assertNotEqual(before, after)


class DriverBuildStaleTests(unittest.TestCase):
    """Rebuild only when the test-runner product or the hash marker is missing/stale."""

    def _runner_app(self, derived: Path) -> Path:
        return (
            derived / "Build/Products/Debug-iphonesimulator"
            / "FestivalMobileUITests-Runner.app"
        )

    def test_stale_when_runner_app_missing(self):
        with TemporaryDirectory() as tmp:
            derived = Path(tmp)
            self.assertTrue(driver_build_stale(derived, "deadbeef"))

    def test_stale_when_marker_missing(self):
        with TemporaryDirectory() as tmp:
            derived = Path(tmp)
            self._runner_app(derived).mkdir(parents=True)
            self.assertTrue(driver_build_stale(derived, "deadbeef"))

    def test_stale_when_hash_differs(self):
        with TemporaryDirectory() as tmp:
            derived = Path(tmp)
            self._runner_app(derived).mkdir(parents=True)
            write_driver_hash(derived, "old-hash")
            self.assertTrue(driver_build_stale(derived, "new-hash"))

    def test_not_stale_when_hash_matches_and_product_exists(self):
        with TemporaryDirectory() as tmp:
            derived = Path(tmp)
            self._runner_app(derived).mkdir(parents=True)
            write_driver_hash(derived, "same-hash")
            self.assertFalse(driver_build_stale(derived, "same-hash"))


def _bmp(pixels: list[tuple[int, int, int]], bits: int = 32) -> bytes:
    """Build a one-row uncompressed BMP (BGR[A]) for the dark-panel check."""
    step = bits // 8
    row = b"".join(bytes((b, g, r) + ((255,) if step == 4 else ())) for r, g, b in pixels)
    row += b"\0" * ((-len(row)) % 4)
    header = bytearray(54)
    header[0:2] = b"BM"
    header[10:14] = (54).to_bytes(4, "little")
    header[28:30] = bits.to_bytes(2, "little")
    return bytes(header) + row


class DuoPoseTests(unittest.TestCase):
    """Panel darkness and pose classification behind ``--pose``/``--display auto``."""

    def test_black_32_bit_panel_is_dark_despite_opaque_alpha(self):
        self.assertTrue(bmp_is_dark(_bmp([(0, 0, 0)] * 5)))

    def test_any_lit_pixel_is_not_dark(self):
        self.assertFalse(bmp_is_dark(_bmp([(0, 0, 0), (0, 40, 0)])))

    def test_24_bit_rows_with_padding(self):
        self.assertTrue(bmp_is_dark(_bmp([(0, 0, 0)] * 3, bits=24)))
        self.assertFalse(bmp_is_dark(_bmp([(0, 0, 0), (200, 0, 0), (0, 0, 0)], bits=24)))

    def test_near_black_within_threshold(self):
        self.assertTrue(bmp_is_dark(_bmp([(8, 8, 8)])))

    def test_rejects_non_bmp(self):
        with self.assertRaises(ValueError):
            bmp_is_dark(b"\x89PNG" + bytes(60))

    def test_classify_pose(self):
        self.assertEqual(classify_pose(outer_dark=False, inner_dark=True), "folded")
        self.assertEqual(classify_pose(outer_dark=True, inner_dark=False), "unfolded")
        self.assertEqual(classify_pose(outer_dark=True, inner_dark=True), "unknown")
        self.assertEqual(classify_pose(outer_dark=False, inner_dark=False), "unknown")


def _control(title=None, role="AXButton", kind="control", **extra):
    """Build one Device Hub ``dump`` entry."""
    entry = {"kind": kind, "path": ["w", 0, len(title or "")], "role": role, "subrole": None,
             "title": title, "description": None, "help": None, "identifier": None,
             "enabled": True}
    entry.update(extra)
    return entry


class PoseControlMatchTests(unittest.TestCase):
    """Keyword matching behind ``pose --set`` (Device Hub UI scripting)."""

    def setUp(self):
        self.controls = [
            _control(subrole="AXCloseButton", description="close button"),
            _control("Open in New Window", role="AXMenuItem", kind="menu"),
            _control(description="Close", identifier="pose.closed"),
            _control(description="Partially Open"),
            _control(description="Open", help="Unfold the device"),
            _control("Rotate Left", role="AXMenuItem", kind="menu"),
            _control(identifier="rotate.device.left"),
            _control(identifier="rotate.device.right"),
        ]

    def test_each_action_finds_its_control(self):
        found = {action: match_pose_control(action, self.controls)
                 for action in ("folded", "unfolded", "half", "rotate-left", "rotate-right")}
        self.assertEqual(found["folded"]["identifier"], "pose.closed")
        self.assertEqual(found["unfolded"]["help"], "Unfold the device")
        self.assertEqual(found["half"]["description"], "Partially Open")
        self.assertEqual(found["rotate-right"]["identifier"], "rotate.device.right")

    def test_window_buttons_beat_menu_items(self):
        self.assertEqual(match_pose_control("rotate-left", self.controls)["identifier"],
                         "rotate.device.left")

    def test_window_chrome_and_unrelated_items_never_match(self):
        chrome = [self.controls[0], self.controls[1]]
        for action in ("folded", "unfolded"):
            self.assertIsNone(match_pose_control(action, chrome))

    def test_bare_open_close_buttons_match_only_in_the_device_window(self):
        controls = [_control(description="Close"), _control(description="Open"),
                    _control("Close", role="AXMenuItem", kind="menu"),
                    _control(description="Close Navigation")]
        self.assertEqual(match_pose_control("folded", controls), controls[0])
        self.assertEqual(match_pose_control("unfolded", controls), controls[1])
        self.assertIsNone(match_pose_control("folded", controls[2:]))

    def test_disabled_and_static_text_ignored(self):
        controls = [_control(description="Partially Open", enabled=False),
                    _control(description="Partially Open", role="AXStaticText")]
        self.assertIsNone(match_pose_control("half", controls))


class AccessibilityInstructionTests(unittest.TestCase):
    """The operator is told exactly which app to allow; nothing is changed for them."""

    def test_bundle_is_outermost_app(self):
        path = "/Applications/Claude.app/Contents/Helpers/x.app/Contents/MacOS/x"
        self.assertEqual(app_bundle_for(path), "/Applications/Claude.app")
        self.assertEqual(app_bundle_for("/usr/bin/python3"), "/usr/bin/python3")

    def test_names_the_responsible_app_and_settings_path(self):
        text = accessibility_instructions((42, "/Apps/Agent.app/Contents/MacOS/agent"))
        self.assertIn("/Apps/Agent.app", text)
        self.assertIn("Privacy & Security > Accessibility", text)
        self.assertIn("never changes privacy settings", text)

    def test_automation_variant(self):
        text = accessibility_instructions((42, "/Apps/Agent.app/Contents/MacOS/agent"), automation=True)
        self.assertIn("Automation", text)
        self.assertIn("System Events", text)


if __name__ == "__main__":
    unittest.main()
