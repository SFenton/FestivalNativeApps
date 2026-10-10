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

from tools import ios_sim
from tools.ios_sim import (
    a11y_commands,
    accessibility_instructions,
    app_bundle_for,
    bmp_is_dark,
    classify_pose,
    match_pose_control,
    choose_hub_process,
    find_hub_control,
    has_pose_controls,
    hub_helper_stale,
    hub_window_shows,
    output_paths as _output_paths,
    parse_host_command,
    pose_presses,
    rank_device_windows,
    driver_build_stale,
    existing_ci_device,
    output_paths,
    pick_ci_runtime,
    skip_problem,
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
        self.assertEqual(output_paths(["wait:1", "back", "tap:x", "fill", "resize:0.5"]), [])

    def test_collects_system_tree_paths(self):
        self.assertEqual(output_paths(["systemTree:/tmp/sb.txt", "systemTap:window-controls"]), ["/tmp/sb.txt"])

    def test_collects_audit_paths(self):
        self.assertEqual(output_paths(["audit:/tmp/a.txt", "tap:x"]), ["/tmp/a.txt"])


class SelectProductTests(unittest.TestCase):
    """The iPad alias runs the iPad journeys; everything else the iPhone journeys. Both
    install the same universal app."""

    def tearDown(self):
        ios_sim.select_product(None, None)

    def test_ipad_alias_selects_ipad_journeys_on_the_universal_app(self):
        product = ios_sim.select_product(None, "ipad")
        self.assertEqual(product.scheme, "FestivalMobileIPad")
        self.assertEqual(product.uitest_target, "FestivalMobileIPadUITests")
        self.assertEqual(product.app_name, "FestivalMobile")
        self.assertEqual(ios_sim.product().bundle_id, ios_sim.BUNDLE_ID)
        self.assertTrue(str(ios_sim.driver_derived_data()).endswith("lane-driver-ipad"))

    def test_default_and_other_devices_select_phone_app(self):
        for device in (None, "iphone", "duo", "4E9F2A49-127D-40BC-A909-08AF3D4BE6A5"):
            self.assertEqual(ios_sim.select_product(None, device).scheme, "FestivalMobile")
        self.assertEqual(ios_sim.product().bundle_id, ios_sim.BUNDLE_ID)

    def test_explicit_app_overrides_device(self):
        self.assertEqual(ios_sim.select_product("phone", "ipad").scheme, "FestivalMobile")
        self.assertEqual(ios_sim.select_product("ipad", "iphone").scheme, "FestivalMobileIPad")


class ResolveDeviceTests(unittest.TestCase):
    """Aliases map to UDIDs; anything else (a raw UDID) passes through."""

    def test_known_alias(self):
        self.assertEqual(
            resolve_device("iphone"), "4E9F2A49-127D-40BC-A909-08AF3D4BE6A5"
        )

    def test_unknown_alias_passes_through_as_udid(self):
        self.assertEqual(resolve_device("SOME-OTHER-UDID"), "SOME-OTHER-UDID")


class DiagnosticsArgsTests(unittest.TestCase):
    """``FST_UITEST_NO_DIAGNOSTICS=1`` skips xcodebuild's slow failure diagnostics (#391)."""

    def test_default_keeps_diagnostics(self) -> None:
        self.assertEqual(ios_sim.uitest_diagnostics_args({}), [])
        self.assertEqual(ios_sim.uitest_diagnostics_args({"FST_UITEST_NO_DIAGNOSTICS": "0"}), [])

    def test_opt_out_skips_them(self) -> None:
        self.assertEqual(
            ios_sim.uitest_diagnostics_args({"FST_UITEST_NO_DIAGNOSTICS": "1"}),
            ["-collect-test-diagnostics", "never"],
        )


class CiDeviceTests(unittest.TestCase):
    """`ci-device` picks the newest iOS runtime for the iPhone and only runs in CI."""

    RUNTIMES = [
        {"platform": "iOS", "version": "26.5", "identifier": "ios-26-5", "isAvailable": True,
         "supportedDeviceTypes": [{"name": "iPhone 17 Pro", "identifier": "dt.iphone-17-pro"}]},
        {"platform": "iOS", "version": "27.1", "identifier": "ios-27-1", "isAvailable": True,
         "supportedDeviceTypes": [{"name": "iPhone 17 Pro", "identifier": "dt.iphone-17-pro"},
                                  {"name": "iPhone Duo", "identifier": "dt.duo"}]},
        {"platform": "iOS", "version": "28.0", "identifier": "ios-28-0", "isAvailable": False,
         "supportedDeviceTypes": [{"name": "iPhone 17 Pro", "identifier": "dt.iphone-17-pro"}]},
        {"platform": "watchOS", "version": "30.0", "identifier": "watch-30", "isAvailable": True,
         "supportedDeviceTypes": [{"name": "iPhone 17 Pro", "identifier": "dt.iphone-17-pro"}]},
    ]

    def test_newest_available_ios_runtime_wins(self):
        self.assertEqual(pick_ci_runtime(self.RUNTIMES), ("ios-27-1", "dt.iphone-17-pro"))

    def test_runtime_must_support_the_device_type(self):
        self.assertEqual(pick_ci_runtime(self.RUNTIMES, "iPhone Duo"), ("ios-27-1", "dt.duo"))
        with self.assertRaises(LookupError):
            pick_ci_runtime(self.RUNTIMES, "iPad Pro")

    def test_older_listing_without_platform_key_uses_the_name(self):
        runtimes = [{"name": "iOS 26.5", "version": "26.5", "identifier": "ios-26-5",
                     "supportedDeviceTypes": [{"name": "iPhone 17 Pro", "identifier": "dt"}]}]
        self.assertEqual(pick_ci_runtime(runtimes), ("ios-26-5", "dt"))

    def test_reuses_the_device_it_created(self):
        devices = {"ios-27-1": [{"name": "Other", "udid": "A"}, {"name": ios_sim.CI_DEVICE_NAME, "udid": "B"}]}
        self.assertEqual(existing_ci_device(devices, "ios-27-1"), "B")
        self.assertIsNone(existing_ci_device(devices, "ios-26-5"))

    def test_each_device_type_has_its_own_name(self):
        self.assertEqual(ios_sim.ci_device_name(), ios_sim.CI_DEVICE_NAME)
        ipad = ios_sim.ci_device_name(ios_sim.CI_IPAD_DEVICE_TYPE)
        self.assertNotEqual(ipad, ios_sim.CI_DEVICE_NAME)
        devices = {"ios-27-1": [{"name": ios_sim.CI_DEVICE_NAME, "udid": "PHONE"}]}
        self.assertIsNone(existing_ci_device(devices, "ios-27-1", ipad))
        devices["ios-27-1"].append({"name": ipad, "udid": "PAD"})
        self.assertEqual(existing_ci_device(devices, "ios-27-1", ipad), "PAD")

    def test_refuses_outside_ci(self):
        import argparse
        import os
        from unittest import mock

        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": ""}), mock.patch.object(ios_sim, "_run") as run:
            self.assertEqual(ios_sim.cmd_ci_device(argparse.Namespace(type=ios_sim.CI_DEVICE_TYPE)), 2)
        run.assert_not_called()


class FailOnSkipTests(unittest.TestCase):
    """`uitest --fail-on-skip` fails a green batch that skipped or ran nothing."""

    def test_all_passed_is_fine(self):
        self.assertIsNone(skip_problem({"passedTests": 1, "skippedTests": 0, "failedTests": 0}))

    def test_a_skip_fails(self):
        self.assertIn("skipped", skip_problem({"passedTests": 2, "skippedTests": 1}))

    def test_nothing_ran_fails(self):
        self.assertEqual(skip_problem({"passedTests": 0, "skippedTests": 0}), "no test ran")

    def test_unreadable_summary_fails(self):
        self.assertIsNotNone(skip_problem(None))


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


class DeviceHubWindowTests(unittest.TestCase):
    """Finding Device Hub's window for our Duo without touching other projects' windows."""

    def test_title_match_is_exact_name_plus_separator(self):
        self.assertTrue(hub_window_shows("iPhone Duo (FST) – iOS 27.1", "iPhone Duo (FST)"))
        self.assertTrue(hub_window_shows("iPhone Duo (FST)", "iPhone Duo (FST)"))
        self.assertFalse(hub_window_shows("iPhone Duo (HASS) – iOS 27.1", "iPhone Duo (FST)"))
        self.assertFalse(hub_window_shows("iPhone Duo (FST) 2 – iOS 27.1", "iPhone Duo (FST)"))
        self.assertFalse(hub_window_shows("HA Resume Probe iPhone 17 Pro – iOS 27.0", "iPhone Duo (FST)"))

    def test_visible_standard_main_windows_rank_first(self):
        windows = [
            {"pid": 10, "window": 2, "title": "iPhone Duo (FST) – iOS 27.1", "subrole": "AXDialog",
             "minimized": True, "main": False},
            {"pid": 10, "window": 1, "title": "iPhone Duo (HASS) – iOS 27.1", "subrole": "AXStandardWindow",
             "minimized": False, "main": True},
            {"pid": 20, "window": 0, "title": "iPhone Duo (FST) – iOS 27.1", "subrole": "AXStandardWindow",
             "minimized": False, "main": False},
            {"pid": 30, "window": 0, "title": "iPhone Duo (FST) – iOS 27.1", "subrole": "AXStandardWindow",
             "minimized": False, "main": True},
        ]
        ranked = rank_device_windows(windows, "iPhone Duo (FST)")
        self.assertEqual([(entry["pid"], entry["window"]) for entry in ranked], [(30, 0), (20, 0), (10, 2)])

    def test_new_window_goes_to_the_frontmost_hub_process(self):
        self.assertEqual(choose_hub_process([10, 20, 30], 20), 20)
        self.assertEqual(choose_hub_process([10, 20, 30], 999), 30)
        self.assertEqual(choose_hub_process([10, 20, 30], None), 30)

    def test_helper_recompiles_when_missing_or_older(self):
        with TemporaryDirectory() as folder:
            source, binary = Path(folder) / "a.swift", Path(folder) / "a"
            source.write_text("//")
            self.assertTrue(hub_helper_stale(source, binary))
            binary.write_text("bin")
            import os
            os.utime(source, (1, 1))
            self.assertFalse(hub_helper_stale(source, binary))
            os.utime(binary, (0, 0))
            self.assertTrue(hub_helper_stale(source, binary))


class DeviceHubControlsTests(unittest.TestCase):
    """The calibrated Device Hub 27.1 device window: Rotate Right, Closed, Book, Open."""

    def setUp(self):
        self.controls = [
            _control(description="Home", identifier="app.grid.3x3"),
            _control(description="Screenshot", identifier="camera.viewfinder"),
            _control(description="Rotate Right"),
            _control(description="Closed"),
            _control(description="Book"),
            _control(description="Open"),
            _control(description="Hide Sidebar"),
            _control(subrole="AXCloseButton"),
        ]

    def test_each_pose_presses_its_button(self):
        self.assertEqual(pose_presses("folded", self.controls), [self.controls[3]])
        self.assertEqual(pose_presses("half", self.controls), [self.controls[4]])
        self.assertEqual(pose_presses("unfolded", self.controls), [self.controls[5]])
        self.assertEqual(pose_presses("rotate-right", self.controls), [self.controls[2]])

    def test_simulated_app_elements_never_match(self):
        content = [_control(role="AXGroup", subrole="iOSContentGroup", path=[0, 3, 0]),
                   _control(description="#1, player, Full combo, Open in new window", path=[0, 3, 0, 31]),
                   _control(description="Closed door", path=[0, 3, 0, 32])]
        self.assertEqual(pose_presses("unfolded", content + self.controls), [self.controls[5]])
        self.assertEqual(pose_presses("folded", content + self.controls), [self.controls[3]])
        self.assertEqual(pose_presses("folded", content), [])

    def test_toolbar_toggle_found_by_exact_label(self):
        toggle = _control(role="AXCheckBox", description="Capture Keyboard", help="Capture Keyboard")
        group = _control(role="AXGroup", help="Capture Keyboard")
        self.assertIs(find_hub_control([group, toggle] + self.controls, "Capture Keyboard"), toggle)
        self.assertIsNone(find_hub_control(self.controls, "Capture"))

    def test_rotate_left_is_three_right_rotations(self):
        self.assertEqual(pose_presses("rotate-left", self.controls), [self.controls[2]] * 3)

    def test_pose_controls_present_only_when_booted(self):
        self.assertTrue(has_pose_controls(self.controls))
        booted_off = [_control(description="Start"), _control(description="Hide Sidebar")]
        self.assertFalse(has_pose_controls(booted_off))
        self.assertEqual(pose_presses("half", booted_off), [])


class HostCommandTests(unittest.TestCase):
    """``host:`` driver steps the host runs mid-drive (Duo poses, panel captures, menus)."""

    def test_valid_commands(self):
        self.assertEqual(parse_host_command("pose half"), ("pose", ["half"]))
        self.assertEqual(parse_host_command(" capture inner /tmp/a b.png "), ("capture", ["inner", "/tmp/a b.png"]))
        self.assertEqual(parse_host_command("menu Device/Keyboard/Toggle Software Keyboard"),
                         ("menu", ["Device/Keyboard/Toggle Software Keyboard"]))
        self.assertEqual(parse_host_command("control Capture Keyboard"), ("control", ["Capture Keyboard"]))

    def test_invalid_commands(self):
        for text in ("pose sideways", "pose", "capture middle /tmp/a.png", "capture inner relative.png",
                     "reboot now", "", "menu"):
            with self.assertRaises(ValueError, msg=text):
                parse_host_command(text)

    def test_capture_paths_are_outputs(self):
        steps = ["host:pose unfolded", "host:capture inner /tmp/x/inner.png", "shot:/tmp/x/a.png",
                 "host:capture nowhere /tmp/bad.png"]
        self.assertEqual(_output_paths(steps), ["/tmp/x/inner.png", "/tmp/x/a.png"])


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


class A11yCommandsTests(unittest.TestCase):
    """`shot --a11y` switches simulator settings on, then restores them in reverse."""

    def test_settings_enable_in_order_and_restore_in_reverse(self):
        enable, restore = a11y_commands("UDID", ["increase-contrast", "reduce-transparency"])
        self.assertEqual(enable[0], ["xcrun", "simctl", "ui", "UDID", "increase_contrast", "enabled"])
        self.assertEqual(enable[1][:6], ["xcrun", "simctl", "spawn", "UDID", "defaults", "write"])
        self.assertIn("EnhancedBackgroundContrastEnabled", enable[1])
        self.assertEqual(restore[0][4:6], ["defaults", "delete"])
        self.assertEqual(restore[1], ["xcrun", "simctl", "ui", "UDID", "increase_contrast", "disabled"])

    def test_no_settings_runs_nothing(self):
        self.assertEqual(a11y_commands("UDID", None), ([], []))

    def test_bold_text_writes_the_legibility_preference(self):
        enable, restore = a11y_commands("UDID", ["bold-text"])
        self.assertEqual(enable[0][4:6], ["defaults", "write"])
        self.assertIn("EnhancedTextLegibilityEnabled", enable[0])
        self.assertEqual(restore[0][4:7], ["defaults", "delete", "com.apple.Accessibility"])

    def test_unknown_setting_is_rejected(self):
        with self.assertRaises(ValueError):
            a11y_commands("UDID", ["grayscale"])
