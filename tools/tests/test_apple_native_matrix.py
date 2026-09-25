"""Keep the serial Apple simulator runner safe around unrelated host devices."""

import json
import os
import signal
import subprocess
import sys
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from urllib.request import urlopen

from tools.apple_native_matrix import (
    DUO_TEST,
    FIXTURE_INPUTS,
    REQUIRED_INPUTS,
    ROOT,
    TEST_SOURCE,
    MatrixError,
    acquire_matrix_lock,
    booted_targets,
    boot_device,
    device_order,
    exit_on_signal,
    fixture_options,
    file_hashes,
    input_hashes,
    main,
    require_unchanged,
    selected_tests,
    run_device,
    start_fixture,
    stop_fixture,
    validate_product_devices,
    verify_result,
    verify_test_names,
)
from tools.mock_service import FixtureHandler, FixtureServer

IPHONE = "fixture-iphone"
IPAD = "fixture-ipad"


def inventory(*, iphone_name="FST Test iPhone", ipad_name="FST Test iPad"):
    """Return minimal typed simulator records for safe-switching assertions.

    Args:
        iphone_name: iPhone simulator display name.
        ipad_name: iPad simulator display name.

    Returns:
        Current full `simctl`-shaped device inventory.
    """
    return {"devices": {"iOS fixture runtime": [
        {
            "udid": IPHONE, "name": iphone_name, "state": "Booted",
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        },
        {
            "udid": IPAD, "name": ipad_name, "state": "Shutdown",
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch",
        },
    ]}}


class AppleNativeMatrixTests(unittest.TestCase):
    """Fail closed on skipped tests, reused one-shot state or foreign simulators."""

    def test_full_selection_excludes_only_duo_and_targeted_names_are_real(self):
        """A new UI test joins the ordinary matrix without silently skipping it."""
        source = TEST_SOURCE.read_text(encoding="utf-8")
        full = selected_tests(source, [])
        self.assertGreaterEqual(len(full), 15)
        self.assertNotIn(DUO_TEST, full)
        self.assertIn("testSongsRecoversAfterSamePublicationSettingsCheck", full)
        self.assertIn("testFailureActionRemainsReachableAtLargestTypeAndLandscape", full)
        self.assertEqual(selected_tests(source, [full[0]]), [full[0]])
        for requested in ([DUO_TEST], [full[0], full[0]], ["testTypo"]):
            with self.subTest(requested=requested), self.assertRaises(MatrixError):
                selected_tests(source, requested)
        with self.assertRaises(MatrixError):
            selected_tests("    func testSame() {}\n    func testSame() {}\n", [])

    def test_exclusive_lock_survives_until_release_across_processes(self):
        """Two matrix processes cannot concurrently own a simulator, even by mistake."""
        with TemporaryDirectory() as temporary:
            lock = Path(temporary) / "fst-matrix.lock"
            descriptor = acquire_matrix_lock(lock)
            script = (
                "import sys; from pathlib import Path; "
                "from tools.apple_native_matrix import acquire_matrix_lock; "
                "acquire_matrix_lock(Path(sys.argv[1]))"
            )
            try:
                other = subprocess.run(
                    [sys.executable, "-c", script, str(lock)], cwd=ROOT,
                    capture_output=True, text=True, check=False,
                )
                self.assertNotEqual(other.returncode, 0)
                self.assertIn("Another Apple matrix owns", other.stderr)
            finally:
                os.close(descriptor)
            next_run = subprocess.run(
                [sys.executable, "-c", script, str(lock)], cwd=ROOT,
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(next_run.returncode, 0, next_run.stderr)
            target = Path(temporary) / "target"
            target.write_text("unchanged", encoding="utf-8")
            symlink = Path(temporary) / "not-a-lock"
            symlink.symlink_to(target)
            with self.assertRaisesRegex(MatrixError, "Cannot open"):
                acquire_matrix_lock(symlink)
            self.assertEqual(target.read_text(encoding="utf-8"), "unchanged")

    def test_device_inventory_requires_two_approved_fst_families(self):
        """Even an explicitly passed UDID cannot authorize another project's device."""
        requested = {"iphone": IPHONE, "ipad": IPAD}
        validate_product_devices(inventory(), requested)
        with self.assertRaisesRegex(MatrixError, "non-FST"):
            validate_product_devices(inventory(iphone_name="Home Assistant iPhone"), requested)
        with self.assertRaisesRegex(MatrixError, "non-FST"):
            validate_product_devices(inventory(ipad_name="FST iPhone mislabeled"), requested)
        with self.assertRaisesRegex(MatrixError, "not found"):
            validate_product_devices(inventory(), dict(requested, ipad="unknown"))

    def test_booted_simulators_must_be_exactly_one_allowed_product(self):
        """Never shut down or coexist with a simulator owned by another project."""
        original = inventory()
        self.assertEqual(booted_targets(original, {IPHONE, IPAD}), {IPHONE})
        with self.assertRaisesRegex(MatrixError, "Another simulator"):
            booted_targets(original, {IPAD})
        other = inventory()
        other["devices"]["iOS fixture runtime"][1]["state"] = "Booted"
        with self.assertRaisesRegex(MatrixError, "Another simulator"):
            booted_targets(other, {IPHONE, IPAD})
        with self.assertRaisesRegex(MatrixError, "device inventory"):
            booted_targets({}, {IPHONE, IPAD})

    def test_device_switch_reuses_live_target_and_shuts_down_only_allowed_peer(self):
        """A second FST device is switched serially; an already-live target is not restarted."""
        with patch(
            "tools.apple_native_matrix.active_devices", side_effect=[{IPHONE}, {IPAD}]
        ), patch("tools.apple_native_matrix.run_checked", return_value="") as commands:
            boot_device(IPAD, {}, {IPHONE, IPAD})
            self.assertEqual(commands.call_args_list[0].args[0], [
                "xcrun", "simctl", "shutdown", IPHONE,
            ])
            self.assertEqual(commands.call_args_list[1].args[0], [
                "xcrun", "simctl", "boot", IPAD,
            ])
            self.assertEqual(commands.call_count, 3)
        with patch(
            "tools.apple_native_matrix.active_devices", return_value={IPAD}
        ), patch("tools.apple_native_matrix.run_checked") as commands, redirect_stdout(StringIO()):
            boot_device(IPAD, {}, {IPHONE, IPAD})
            commands.assert_not_called()

    def test_matrix_starts_with_the_already_booted_product_device(self):
        """A currently live tablet must not be shut down and booted again."""
        self.assertEqual(device_order("both", {IPAD}, IPHONE, IPAD), ("ipad", "iphone"))
        self.assertEqual(device_order("both", {IPHONE}, IPHONE, IPAD), ("iphone", "ipad"))
        self.assertEqual(device_order("both", set(), IPHONE, IPAD), ("iphone", "ipad"))
        self.assertEqual(device_order("ipad", {IPHONE}, IPHONE, IPAD), ("ipad",))
        with self.assertRaisesRegex(MatrixError, "unrecognized"):
            device_order("both", {"not-ours"}, IPHONE, IPAD)

    def test_result_must_contain_every_selected_case_on_right_device(self):
        """A green process exit is not a pass for zero, skipped or wrong tests."""
        summary = {
            "result": "Passed", "totalTestCount": 15, "passedTests": 15,
            "failedTests": 0, "skippedTests": 0,
            "devicesAndConfigurations": [{
                "device": {
                    "platform": "iOS Simulator", "modelName": "iPhone 17 Pro",
                    "deviceId": IPHONE,
                },
            }],
        }
        verify_result(summary, device="iphone", identifier=IPHONE, expected=15)
        with self.assertRaisesRegex(MatrixError, "expected 15"):
            verify_result(dict(summary, totalTestCount=14), device="iphone",
                          identifier=IPHONE, expected=15)
        with self.assertRaisesRegex(MatrixError, "expected 15"):
            verify_result(dict(summary, skippedTests=1), device="iphone",
                          identifier=IPHONE, expected=15)
        with self.assertRaisesRegex(MatrixError, "unexpected device"):
            verify_result(summary, device="ipad", identifier=IPAD, expected=15)

    def test_exact_executed_names_reject_an_equal_count_of_wrong_methods(self):
        """A replaced native test is not evidence even when counts still match."""
        tree = {"testNodes": [{
            "nodeType": "Test Plan", "children": [
                {"nodeType": "Test Case", "name": "testFirst()"},
                {"nodeType": "Test Case", "name": "testSecond()"},
            ],
        }]}
        verify_test_names(tree, ["testFirst", "testSecond"])
        with self.assertRaisesRegex(MatrixError, "wrong test methods"):
            verify_test_names(tree, ["testFirst", "testUnrelated"])
        tree["testNodes"][0]["children"][1]["name"] = "testFirst()"
        with self.assertRaisesRegex(MatrixError, "wrong test methods"):
            verify_test_names(tree, ["testFirst", "testSecond"])
        with self.assertRaisesRegex(MatrixError, "test-case tree"):
            verify_test_names({}, ["testFirst"])

    def test_input_snapshot_detects_changed_fixture_test_or_generated_project(self):
        """No device pair can be joined after its fixture or build inputs drift."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in REQUIRED_INPUTS:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture bytes")
            source = root / "apple/Sources/FestivalUI/Probe.swift"
            source.parent.mkdir(parents=True)
            source.write_bytes(b"// fixture")
            baseline = input_hashes(root)
            self.assertEqual(
                baseline["tools/mock_service.py"],
                file_hashes(root, FIXTURE_INPUTS)["tools/mock_service.py"],
            )
            require_unchanged(baseline, root=root)
            project = root / "apple/project.yml"
            project.write_bytes(b"changed")
            with self.assertRaisesRegex(MatrixError, "project.yml"):
                require_unchanged(baseline, root=root)
            project.write_bytes(b"fixture bytes")
            test_source = root / "apple/Apps/iOSUITests/FestivalMobileUITests.swift"
            test_source.write_bytes(b"new tests")
            with self.assertRaisesRegex(MatrixError, "FestivalMobileUITests.swift"):
                require_unchanged(baseline, root=root)

    def test_stateful_port_is_never_reused_or_terminated(self):
        """A listener owned by another task survives an unsuccessful runner start."""
        with FixtureServer(("127.0.0.1", 0), FixtureHandler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with TemporaryDirectory() as temporary:
                    with self.assertRaisesRegex(MatrixError, "in use"):
                        start_fixture(server.server_port, [], Path(temporary))
                    stale = dict(file_hashes(ROOT, FIXTURE_INPUTS))
                    stale["tools/mock_service.py"] = "0" * 64
                    with self.assertRaisesRegex(MatrixError, "stale"):
                        start_fixture(
                            server.server_port, [], Path(temporary),
                            allow_existing=True, expected_hashes=stale,
                        )
                    with redirect_stdout(StringIO()):
                        reused = start_fixture(
                            server.server_port, [], Path(temporary), allow_existing=True
                        )
                    self.assertIsNone(reused)
                    stop_fixture(reused)
                    with urlopen(
                        f"http://127.0.0.1:{server.server_port}/__fixture__/health"
                    ) as response:
                        self.assertEqual(response.status, 200)
            finally:
                server.shutdown()
                thread.join(timeout=2)

    def test_offline_mode_is_only_a_known_unpinned_one_shot_fixture(self):
        """A stopped listener cannot claim a verified or indefinitely live snapshot."""
        options = fixture_options(["--unpinned", "--stop-after-first-songs"])
        self.assertTrue(options["unpinned"])
        self.assertTrue(options["stopAfterFirstSongs"])
        with self.assertRaisesRegex(MatrixError, "Unknown"):
            fixture_options(["--stop-after-first-songs"])

    def test_runner_stops_only_its_own_fixture_child(self):
        """An ephemeral fixture is responsive, then terminates by its exact PID."""
        with FixtureServer(("127.0.0.1", 0), FixtureHandler) as probe:
            port = probe.server_port
        with TemporaryDirectory() as temporary:
            process = start_fixture(port, [], Path(temporary))
            self.assertIsNotNone(process)
            try:
                self.assertIsNone(process.poll())
                with urlopen(f"http://127.0.0.1:{port}/__fixture__/health") as response:
                    self.assertEqual(response.status, 200)
            finally:
                stop_fixture(process)
            self.assertIsNotNone(process.poll())

    def test_unhealthy_new_fixture_cleans_up_its_exact_child(self):
        """Health timeout cannot leak a managed mock process into later suites."""
        child = Mock()
        child.poll.return_value = None
        with TemporaryDirectory() as temporary, patch(
            "tools.apple_native_matrix.port_is_free", return_value=True
        ), patch(
            "tools.apple_native_matrix.subprocess.Popen", return_value=child
        ), patch(
            "tools.apple_native_matrix.fixture_json",
            side_effect=ConnectionRefusedError("not listening"),
        ), patch(
            "tools.apple_native_matrix.time.sleep"
        ), patch("tools.apple_native_matrix.stop_fixture") as stopped:
            with self.assertRaisesRegex(MatrixError, "did not become healthy"):
                start_fixture(8769, ["--fail-first-white-catalogue"], Path(temporary))
            stopped.assert_called_once_with(child)

    def test_termination_signal_exits_through_fixture_cleanup(self):
        """The process does not swallow SIGTERM and skip Python finally blocks."""
        with self.assertRaises(SystemExit) as interrupted:
            exit_on_signal(signal.SIGTERM, None)
        self.assertEqual(interrupted.exception.code, 128 + signal.SIGTERM)

    def test_full_suite_explicitly_selects_every_source_test_except_duo(self):
        """A broad Xcode skip can silently omit new cases; use exact selectors."""
        names = selected_tests(TEST_SOURCE.read_text(encoding="utf-8"), [])
        total = len(names)
        summary = {
            "result": "Passed", "totalTestCount": total, "passedTests": total,
            "failedTests": 0, "skippedTests": 0,
            "devicesAndConfigurations": [{
                "device": {
                    "platform": "iOS Simulator", "modelName": "iPhone 17 Pro",
                    "deviceId": IPHONE,
                },
            }],
        }
        cases = {"testNodes": [{
            "nodeType": "Test Plan", "children": [
                {"nodeType": "Test Case", "name": f"{name}()"} for name in names
            ],
        }]}
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch("tools.apple_native_matrix.start_fixture", side_effect=[
                Mock(), Mock(), Mock(),
            ]) as started, patch(
                "tools.apple_native_matrix.stop_fixture"
            ) as stopped, patch(
                "tools.apple_native_matrix.subprocess.run",
                return_value=Mock(returncode=0),
            ) as executed, patch(
                "tools.apple_native_matrix.xcode_json", side_effect=[summary, cases]
            ), patch(
                "tools.apple_native_matrix.require_unchanged"
            ):
                with redirect_stdout(StringIO()):
                    result = run_device(
                        "iphone", IPHONE, root, expected_tests=names,
                        baseline=file_hashes(ROOT, FIXTURE_INPUTS), env={},
                    )
                self.assertEqual(result, root / "iphone.xcresult")
                self.assertEqual(started.call_count, 3)
                self.assertEqual(stopped.call_count, 3)
                command = executed.call_args.args[0]
                selectors = {
                    argument.removeprefix(
                        "-only-testing:FestivalMobileUITests/FestivalMobileUITests/"
                    )
                    for argument in command if argument.startswith("-only-testing:")
                }
                self.assertEqual(selectors, set(names))
                self.assertNotIn(DUO_TEST, selectors)
                self.assertFalse(any(flag.startswith("-skip-testing:") for flag in command))
                self.assertIn("-enableCodeCoverage", command)

    def test_partial_green_result_still_cleans_stateful_fixtures(self):
        """Zero-test success must fail closed and terminate both owned listeners."""
        summary = {
            "result": "Passed", "totalTestCount": 0, "passedTests": 0,
            "failedTests": 0, "skippedTests": 0,
            "devicesAndConfigurations": [{
                "device": {
                    "platform": "iOS Simulator", "modelName": "iPad Pro 11-inch",
                    "deviceId": IPAD,
                },
            }],
        }
        with TemporaryDirectory() as temporary:
            with patch("tools.apple_native_matrix.start_fixture", side_effect=[
                Mock(), Mock(), Mock(),
            ]), patch(
                "tools.apple_native_matrix.stop_fixture"
            ) as stopped, patch(
                "tools.apple_native_matrix.subprocess.run",
                return_value=Mock(returncode=0),
            ), patch(
                "tools.apple_native_matrix.xcode_json", return_value=summary
            ), patch(
                "tools.apple_native_matrix.require_unchanged"
            ):
                with self.assertRaisesRegex(MatrixError, "expected 1 passing tests"):
                    run_device("ipad", IPAD, Path(temporary),
                               expected_tests=["testWhiteArtworkExposedTextAccessibility"],
                               baseline=file_hashes(ROOT, FIXTURE_INPUTS), env={})
                self.assertEqual(stopped.call_count, 3)

    def test_signal_while_xcode_runs_still_stops_both_fixtures(self):
        """SIGTERM unwinds the device suite instead of leaving fixture children alive."""
        with TemporaryDirectory() as temporary:
            with patch("tools.apple_native_matrix.start_fixture", side_effect=[
                Mock(), Mock(), Mock(),
            ]), patch(
                "tools.apple_native_matrix.stop_fixture"
            ) as stopped, patch(
                "tools.apple_native_matrix.subprocess.run",
                side_effect=SystemExit(128 + signal.SIGTERM),
            ), patch(
                "tools.apple_native_matrix.require_unchanged"
            ):
                with self.assertRaises(SystemExit):
                    run_device(
                        "iphone", IPHONE, Path(temporary),
                        expected_tests=["testWhiteArtworkExposedTextAccessibility"],
                        baseline=file_hashes(ROOT, FIXTURE_INPUTS), env={},
                    )
                self.assertEqual(stopped.call_count, 3)

    def test_full_matrix_pairs_two_results_with_the_exact_coverage_gate(self):
        """The default run cannot claim success without invoking the existing gate."""
        with TemporaryDirectory() as temporary:
            evidence = Path(temporary) / "new-results"
            with patch("tools.apple_native_matrix.run_checked", side_effect=[
                json.dumps(inventory()), "ios.ui-and-app-ux: 92.16%",
            ]) as commands, patch(
                "tools.apple_native_matrix.active_devices", return_value=set()
            ), patch(
                "tools.apple_native_matrix.start_fixture", return_value=None
            ), patch(
                "tools.apple_native_matrix.boot_device"
            ) as boot, patch(
                "tools.apple_native_matrix.run_device", side_effect=[
                    evidence / "iphone.xcresult", evidence / "ipad.xcresult",
                ]
            ) as run, patch(
                "tools.apple_native_matrix.stop_fixture"
            ), patch(
                "tools.apple_native_matrix.input_hashes",
                return_value=file_hashes(ROOT, FIXTURE_INPUTS),
            ), patch(
                "tools.apple_native_matrix.require_unchanged"
            ), patch(
                "tools.apple_native_matrix.acquire_matrix_lock",
                side_effect=lambda: os.open(os.devnull, os.O_RDONLY),
            ), patch.dict("os.environ", {}, clear=False), redirect_stdout(StringIO()):
                result = main([
                    "--iphone-udid", IPHONE, "--ipad-udid", IPAD,
                    "--evidence-dir", str(evidence),
                ])
                self.assertEqual(result, 0)
                self.assertEqual(run.call_count, 2)
                self.assertEqual(boot.call_count, 2)
                gate = commands.call_args_list[1].args[0]
                self.assertIn(str(evidence / "iphone.xcresult"), gate)
                self.assertIn(str(evidence / "ipad.xcresult"), gate)
                self.assertIn("apple_xccov_gate.py", " ".join(gate))

    def test_foreign_booted_device_blocks_all_fixture_or_simulator_mutation(self):
        """A shared Mac's unrelated simulator must remain entirely untouched."""
        foreign = inventory()
        foreign["devices"]["iOS fixture runtime"][0]["udid"] = "not-ours"
        with TemporaryDirectory() as temporary:
            evidence = Path(temporary) / "should-not-exist"
            with patch("tools.apple_native_matrix.run_checked", side_effect=[
                json.dumps(inventory()), json.dumps(foreign),
            ]), patch(
                "tools.apple_native_matrix.start_fixture"
            ) as started, patch(
                "tools.apple_native_matrix.boot_device"
            ) as boot, patch.dict(
                "os.environ", {}, clear=False
            ), patch(
                "tools.apple_native_matrix.input_hashes",
                return_value=file_hashes(ROOT, FIXTURE_INPUTS),
            ), patch(
                "tools.apple_native_matrix.acquire_matrix_lock",
                side_effect=lambda: os.open(os.devnull, os.O_RDONLY),
            ), redirect_stdout(StringIO()), redirect_stderr(StringIO()):
                result = main([
                    "--iphone-udid", IPHONE, "--ipad-udid", IPAD,
                    "--evidence-dir", str(evidence),
                ])
                self.assertEqual(result, 1)
                self.assertFalse(evidence.exists())
                started.assert_not_called()
                boot.assert_not_called()


if __name__ == "__main__":
    unittest.main()
