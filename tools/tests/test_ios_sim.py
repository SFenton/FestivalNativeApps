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

import contextlib
import io
import unittest
import unittest.mock
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
    should_retry_batch,
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

    def test_creates_the_ipad_beside_the_iphone(self):
        import argparse
        import contextlib
        import io
        import json
        import os
        import subprocess
        from unittest import mock

        runtimes = {"runtimes": [{"platform": "iOS", "version": "27.1", "identifier": "ios-27-1",
                                  "supportedDeviceTypes": [{"name": ios_sim.CI_IPAD_DEVICE_TYPE, "identifier": "dt.ipad"}]}]}
        devices = {"devices": {"ios-27-1": [{"name": ios_sim.CI_DEVICE_NAME, "udid": "PHONE"}]}}
        replies = [json.dumps(runtimes), json.dumps(devices), "IPAD\n"]
        calls = []

        def run(cmd, **_):
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout=replies[len(calls) - 1])

        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}), mock.patch.object(ios_sim, "_run", run), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(ios_sim.cmd_ci_device(argparse.Namespace(type=ios_sim.CI_IPAD_DEVICE_TYPE)), 0)
        self.assertEqual(out.getvalue().strip(), "IPAD")
        self.assertEqual(calls[-1][-4:], ["create", ios_sim.ci_device_name(ios_sim.CI_IPAD_DEVICE_TYPE), "dt.ipad", "ios-27-1"])

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


class UitestDiagnosticsTests(unittest.TestCase):
    """``uitest --no-test-diagnostics`` tells xcodebuild not to collect failure diagnostics."""

    def run_batch(self, **kwargs):
        with TemporaryDirectory() as tmp, \
                unittest.mock.patch.object(ios_sim, "LOCK_PATH", Path(tmp) / "sim.lock"), \
                unittest.mock.patch.object(ios_sim, "_run") as run, \
                unittest.mock.patch.object(ios_sim, "boot_exclusive"), \
                unittest.mock.patch.object(ios_sim, "run_bounded", return_value=0) as xcodebuild:
            run.return_value = ios_sim.subprocess.CompletedProcess([], 0, stdout="", stderr="")
            ios_sim._run_uitest_batch(
                udid="UDID", derived=Path(tmp), selectors=["Journey"], timeout=5, **kwargs
            )
        return xcodebuild.call_args.args[0]

    def test_collects_diagnostics_by_default(self):
        self.assertNotIn("-collect-test-diagnostics", self.run_batch())

    def test_skips_diagnostics_when_asked(self):
        cmd = self.run_batch(diagnostics=False)
        index = cmd.index("-collect-test-diagnostics")
        self.assertEqual(cmd[index + 1], "never")
        self.assertLess(index, cmd.index("test-without-building"))


class RetryBatchTests(unittest.TestCase):
    """`uitest --retries` reruns only a batch whose test failed, at most N more times."""

    def test_a_test_failure_retries_while_attempts_remain(self):
        self.assertTrue(should_retry_batch(65, 0, 1))
        self.assertFalse(should_retry_batch(65, 1, 1))

    def test_no_retries_by_default(self):
        self.assertFalse(should_retry_batch(65, 0, 0))

    def test_success_timeout_and_setup_errors_never_retry(self):
        for code in (0, 124, 70, 1, ios_sim.EXIT_POSE_MISMATCH):
            self.assertFalse(should_retry_batch(code, 0, 3), code)


class ResultSummaryReadTests(unittest.TestCase):
    """One slow or failed ``xcresulttool`` read does not fail a green batch (#620)."""

    @staticmethod
    def _completed(stdout: str):
        import subprocess

        return subprocess.CompletedProcess(args=[], returncode=0, stdout=stdout, stderr="")

    def test_a_timed_out_read_is_retried(self):
        import subprocess
        from unittest import mock

        reads = [
            subprocess.TimeoutExpired(cmd="xcresulttool", timeout=1),
            self._completed('{"passedTests": 1, "skippedTests": 0, "failedTests": 0}'),
        ]
        with mock.patch.object(ios_sim.subprocess, "run", side_effect=reads) as run, \
                mock.patch.object(ios_sim.time, "sleep"):
            summary = ios_sim._result_summary(Path("/tmp/x.xcresult"))
        self.assertEqual(run.call_count, 2)
        self.assertIsNone(skip_problem(summary))
        self.assertEqual(ios_sim._result_counts(summary), ": 1 passed, 0 skipped, 0 failed")

    def test_an_unreadable_bundle_still_fails_after_every_attempt(self):
        import subprocess
        from unittest import mock

        error = subprocess.CalledProcessError(returncode=1, cmd="xcresulttool")
        with mock.patch.object(ios_sim.subprocess, "run", side_effect=error) as run, \
                mock.patch.object(ios_sim.time, "sleep"):
            summary = ios_sim._result_summary(Path("/tmp/x.xcresult"), attempts=3)
        self.assertEqual(run.call_count, 3)
        self.assertIsNone(summary)
        self.assertEqual(skip_problem(summary), "no readable result summary")
        self.assertEqual(ios_sim._result_counts(summary), "")

    def test_a_non_object_summary_is_retried(self):
        from unittest import mock

        reads = [self._completed("[]"), self._completed('{"passedTests": 0, "skippedTests": 2}')]
        with mock.patch.object(ios_sim.subprocess, "run", side_effect=reads), \
                mock.patch.object(ios_sim.time, "sleep"):
            summary = ios_sim._result_summary(Path("/tmp/x.xcresult"))
        self.assertIn("skipped", skip_problem(summary))


class TerminateAppTests(unittest.TestCase):
    """Stopping the app after a timed-out batch never hangs the harness (#620)."""

    def test_a_hung_terminate_gives_up_after_its_timeout(self):
        from unittest import mock

        with mock.patch.object(ios_sim, "run_bounded", return_value=None) as run, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertFalse(ios_sim.terminate_app("UDID"))
        self.assertEqual(run.call_args.args[1], ios_sim.TERMINATE_TIMEOUT)
        self.assertIn("terminate", run.call_args.args[0])

    def test_a_terminate_that_returns_succeeds_whatever_its_status(self):
        from unittest import mock

        with mock.patch.object(ios_sim, "run_bounded", return_value=3):
            self.assertTrue(ios_sim.terminate_app("UDID", timeout=5))


class RunBoundedTests(unittest.TestCase):
    """`run_bounded` never waits on a child past its limit (#620: a 2400 s batch ran 78 minutes)."""

    def _run(self, script: str, timeout: float, **kwargs):
        import sys
        import time

        start = time.monotonic()
        with contextlib.redirect_stderr(io.StringIO()):
            code = ios_sim.run_bounded([sys.executable, "-c", script], timeout, poll=0.1, env=None, **kwargs)
        return code, time.monotonic() - start

    def test_a_finished_run_returns_its_status(self):
        self.assertEqual(self._run("raise SystemExit(65)", 10)[0], 65)

    def test_a_run_past_its_timeout_is_killed_with_its_children(self):
        script = "import subprocess, sys, time; subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)']); time.sleep(60)"
        code, elapsed = self._run(script, 0.5)
        self.assertIsNone(code)
        self.assertLess(elapsed, 10)

    def test_the_missing_destination_error_stops_a_hung_run(self):
        with TemporaryDirectory() as tmp:
            log = Path(tmp) / "log.txt"
            with open(log, "w") as out:
                script = f"print({ios_sim.NO_DESTINATION_SIGNATURE!r}, flush=True); import time; time.sleep(60)"
                code, elapsed = self._run(script, 30, watch=log, stop_on=ios_sim.NO_DESTINATION_SIGNATURE,
                                          stdout=out, stderr=ios_sim.subprocess.STDOUT)
        self.assertEqual(code, ios_sim.EXIT_NO_DESTINATION)
        self.assertLess(elapsed, 10)
        self.assertEqual(ios_sim.simulator_wedged(ios_sim.NO_DESTINATION_SIGNATURE), ios_sim.NO_DESTINATION_SIGNATURE)


class RebootWedgedTests(unittest.TestCase):
    """`uitest --reboot-wedged` reboots a hung simulator and reruns that batch once (#620)."""

    RUNNER = ("FestivalMobileUITests-Runner (89034) encountered an error (The test runner failed to initialize "
              "for UI testing. (Underlying Error: Timed out waiting for AX loaded notification))")

    def test_a_runner_that_failed_to_start_is_a_hang(self):
        self.assertEqual(ios_sim.simulator_wedged(f"Testing failed:\n\t{self.RUNNER}\n"),
                         "The test runner failed to initialize for UI testing")

    def test_a_test_failure_is_not_a_hang(self):
        self.assertIsNone(ios_sim.simulator_wedged("XCTAssertTrue failed - No player footer\n** TEST FAILED **"))
        self.assertIsNone(ios_sim.simulator_wedged('caught error: "Audit failed to complete in time"'))

    def test_a_batch_killed_at_its_timeout_is_a_hang(self):
        self.assertEqual(ios_sim.simulator_wedged("\n\nTIMEOUT after 2400.0s; killed.\n"), ios_sim.TIMED_OUT)
        started = ("Writing result bundle at path:\n\t/tmp/r.xcresult\n"
                   "\nTIMEOUT after 2400.0s; killed.\n")
        self.assertEqual(ios_sim.simulator_wedged(started), ios_sim.TIMED_OUT)
        self.assertIsNone(ios_sim.simulator_wedged(""))

    def test_a_second_timeout_fails_the_batch(self):
        timeout = "\nTIMEOUT after 10s; killed.\n"
        code, runs, locks = self._run([timeout, timeout], [124, 124])
        self.assertEqual((code, runs, len(locks)), (124, 2, 1))

    def test_a_timed_out_batch_reboots_the_simulator_and_reruns(self):
        code, runs, locks = self._run(["\nTIMEOUT after 10s; killed.\n", "ok"], [124, 0])
        self.assertEqual((code, runs), (0, 2))
        self.assertEqual([call.args for call in locks], [("UDID", ios_sim._shutdown_simulator)])

    def test_the_reboot_never_waits_on_a_stuck_shutdown(self):
        from unittest import mock

        with mock.patch.object(ios_sim, "run_bounded", return_value=None) as bounded, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(ios_sim._shutdown_simulator("UDID"), 0)
        self.assertEqual(bounded.call_args.args, (["xcrun", "simctl", "shutdown", "UDID"], ios_sim.SHUTDOWN_TIMEOUT))

    def _run(self, logs: list[str], codes: list[int], *, reboot: bool = True):
        """Run `cmd_uitest` over one batch whose attempts log `logs` and exit with `codes`."""
        import argparse
        from unittest import mock

        with TemporaryDirectory() as tmp:
            attempts = []
            for index, (log, code) in enumerate(zip(logs, codes)):
                path = Path(tmp) / f"log{index}.txt"
                path.write_text(log)
                attempts.append((code, 1.0, path, Path(tmp) / f"r{index}.xcresult"))
            args = argparse.Namespace(
                only=["SongsChromeJourneyTests/testA"], device="UDID", rebuild=False, batch_size=1, timeout=10,
                retries=0, reboot_wedged=reboot, fail_on_skip=False,
            )
            with mock.patch.object(ios_sim, "scripting_preflight", return_value=0), \
                    mock.patch.object(ios_sim, "resolve_device", return_value="UDID"), \
                    mock.patch.object(ios_sim, "driver_derived_data", return_value=Path(tmp)), \
                    mock.patch.object(ios_sim, "source_hash", return_value="h"), \
                    mock.patch.object(ios_sim, "driver_build_stale", return_value=False), \
                    mock.patch.object(ios_sim, "_result_summary", return_value={"passedTests": 1}), \
                    mock.patch.object(ios_sim, "_run_uitest_batch", side_effect=attempts) as batch, \
                    mock.patch.object(ios_sim, "_with_sim_lock", return_value=0) as lock, \
                    contextlib.redirect_stderr(io.StringIO()):
                code = ios_sim.cmd_uitest(args)
        return code, batch.call_count, lock.call_args_list

    def test_a_hung_runner_reboots_the_simulator_and_reruns_the_batch(self):
        code, runs, locks = self._run([self.RUNNER, "ok"], [65, 0])
        self.assertEqual((code, runs), (0, 2))
        self.assertEqual([call.args for call in locks], [("UDID", ios_sim._shutdown_simulator)])

    def test_a_second_hang_fails_the_batch(self):
        code, runs, locks = self._run([self.RUNNER, self.RUNNER], [65, 65])
        self.assertEqual((code, runs, len(locks)), (65, 2, 1))

    def test_an_ordinary_failure_is_not_rerun(self):
        code, runs, locks = self._run(["XCTAssertTrue failed"], [65])
        self.assertEqual((code, runs, locks), (65, 1, []))

    def test_the_ci_environment_turns_the_flag_on(self):
        from unittest import mock

        for value, expected in (("1", True), (None, False)):
            env = {k: v for k, v in ios_sim.os.environ.items() if k != "FST_UITEST_REBOOT_WEDGED"}
            if value:
                env["FST_UITEST_REBOOT_WEDGED"] = value
            with mock.patch.dict(ios_sim.os.environ, env, clear=True), \
                    mock.patch.object(ios_sim, "cmd_uitest", return_value=0) as run:
                ios_sim.main(["uitest", "--device", "iphone27", "--only", "A/b"])
            self.assertIs(run.call_args.args[0].reboot_wedged, expected)

    def test_without_the_flag_a_hang_fails_the_batch(self):
        code, runs, locks = self._run([self.RUNNER], [65], reboot=False)
        self.assertEqual((code, runs, locks), (65, 1, []))


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

    def test_panel_screenshot_retries_a_failed_or_stalled_attempt(self):
        """A fresh boot's first screenshot can fail or stall (apple-ci run 37913520235)."""
        import subprocess
        import tempfile
        from pathlib import Path
        from types import SimpleNamespace
        from unittest import mock

        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "outer.bmp"
            outcomes = [subprocess.TimeoutExpired("simctl", 120), SimpleNamespace(returncode=1, stderr=b"no display")]

            def fake_run(command, **_):
                if outcomes:
                    outcome = outcomes.pop(0)
                    if isinstance(outcome, Exception):
                        raise outcome
                    return outcome
                path.write_bytes(_bmp([(255, 255, 255)]))
                return SimpleNamespace(returncode=0, stderr=b"")

            with mock.patch.object(ios_sim, "_run", side_effect=fake_run) as run, \
                    mock.patch.object(ios_sim.time, "sleep") as sleep, \
                    mock.patch("sys.stderr"):
                self.assertTrue(ios_sim.screenshot_panel("UDID", "primary", path, attempts=3, timeout=120))
            self.assertEqual(run.call_count, 3)
            self.assertEqual(sleep.call_count, 2)

            outcomes[:] = [SimpleNamespace(returncode=1, stderr=b"no display")] * 3
            path.unlink()
            with mock.patch.object(ios_sim, "_run", side_effect=lambda *_, **__: outcomes.pop(0)), \
                    mock.patch.object(ios_sim.time, "sleep"), mock.patch("sys.stderr"):
                self.assertFalse(ios_sim.screenshot_panel("UDID", "primary", path, attempts=3, timeout=120))

    def test_require_pose_redetects_an_unknown_pose_after_boot(self):
        """A just-booted Duo may light neither panel yet; unknown is re-checked, a definite pose is not."""
        from unittest import mock

        with mock.patch.object(ios_sim, "detect_pose", side_effect=["unknown", "unknown", "folded"]) as detect, \
                mock.patch.object(ios_sim.time, "sleep") as sleep, mock.patch("sys.stderr"):
            self.assertIsNone(ios_sim.require_pose("UDID", "folded"))
        self.assertEqual(detect.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

        with mock.patch.object(ios_sim, "detect_pose", return_value="unfolded") as detect, \
                mock.patch.object(ios_sim.time, "sleep"), mock.patch("sys.stderr"):
            self.assertIn("not folded", ios_sim.require_pose("UDID", "folded"))
        self.assertEqual(detect.call_count, 1)

        with mock.patch.object(ios_sim, "detect_pose", return_value="unknown") as detect, \
                mock.patch.object(ios_sim.time, "sleep"), mock.patch("sys.stderr"):
            self.assertIn("unknown, not folded", ios_sim.require_pose("UDID", "folded"))
        self.assertEqual(detect.call_count, 4)

    def test_pose_screenshots_get_longer_and_retried_on_ci(self):
        import os
        from unittest import mock

        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": ""}):
            self.assertEqual(ios_sim.pose_screenshot_policy(), (120.0, 1))
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}):
            self.assertEqual(ios_sim.pose_screenshot_policy(), (180.0, 3))

    def test_detect_pose_retries_a_slow_first_screenshot(self):
        # #432: a runner's first screenshot after boot timed out, and the folded Duo read as unknown.
        import os
        import subprocess
        from unittest import mock

        calls = []

        def fake_run(argv, **kwargs):
            calls.append(argv)
            if len(calls) == 1:
                raise subprocess.TimeoutExpired(argv, kwargs["timeout"])
            lit = "--display=primary" in argv
            Path(argv[-1]).write_bytes(_bmp([(200, 200, 200)] if lit else [(0, 0, 0)]))
            return subprocess.CompletedProcess(argv, 0)

        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}), \
                mock.patch.object(ios_sim, "_run", side_effect=fake_run), \
                mock.patch.object(ios_sim.time, "sleep"), mock.patch("sys.stderr"):
            self.assertEqual(ios_sim.detect_pose("UDID"), "folded")
        self.assertEqual(len(calls), 3)
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": ""}), \
                mock.patch.object(ios_sim, "_run", side_effect=subprocess.TimeoutExpired("x", 30)), \
                mock.patch("sys.stderr"):
            self.assertEqual(ios_sim.detect_pose("UDID"), "unknown")


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

    def test_full_keyboard_access_notifies_after_enabling_and_restoring(self):
        enable, restore = a11y_commands("UDID", ["full-keyboard-access"])
        self.assertIn("FullKeyboardAccessUsesSimulatedKeyboardForAutomation", enable[0])
        self.assertIn("FullKeyboardAccessEnabled", enable[1])
        self.assertEqual(enable[2][4:], ["notifyutil", "-p", "com.apple.accessibility.fullkeyboardaccess.status"])
        self.assertEqual([cmd[4:6] for cmd in restore[:2]], [["defaults", "delete"]] * 2)
        self.assertIn("FullKeyboardAccessEnabled", restore[0])
        self.assertIn("FullKeyboardAccessUsesSimulatedKeyboardForAutomation", restore[1])
        self.assertEqual(restore[2], enable[2])

    def test_settings_restore_independently(self):
        enable, restore = a11y_commands("UDID", ["bold-text", "full-keyboard-access"])
        self.assertEqual(len(enable), 4)
        self.assertIn("notifyutil", restore[2])
        self.assertIn("EnhancedTextLegibilityEnabled", restore[3])

    def test_unknown_setting_is_rejected(self):
        with self.assertRaises(ValueError):
            a11y_commands("UDID", ["grayscale"])
