"""Physical probe safety, wire-key fidelity, context gates and report separation."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import subprocess

if sys.platform == "win32":
    raise unittest.SkipTest("Apple capacity tooling requires POSIX")

from tools import uikit_perf, uikit_perf_device, uikit_perf_report


class PhysicalPerfTests(unittest.TestCase):
    def test_device_options_precede_launch_bundle_argument(self):
        """devicectl treats everything after the launch bundle as app arguments."""
        with patch.object(uikit_perf_device.subprocess, "run",
                          return_value=subprocess.CompletedProcess([], 0, "", "")) as command:
            uikit_perf_device.device_command("owned-device", "process", "launch", "--terminate-existing", "probe.bundle")
        argv = command.call_args.args[0]
        self.assertLess(argv.index("--device"), argv.index("probe.bundle"))
        self.assertLess(argv.index("--timeout"), argv.index("probe.bundle"))

    def test_wire_key_preserves_duplicates_blanks_and_encoded_values(self):
        """Query order is irrelevant, but repeated keys remain distinct."""
        self.assertEqual(
            uikit_perf_device.request_key("/api/rankings?combo=Lead%2BBass&q=&q=a+b"),
            uikit_perf_device.request_key("/api/rankings?q=a%20b&q=&combo=Lead%2BBass"),
        )
        self.assertNotEqual(uikit_perf_device.request_key("/api/songs?q="),
                            uikit_perf_device.request_key("/api/songs"))
        self.assertNotEqual(uikit_perf_device.request_key("/api/songs?q=a&q=a"),
                            uikit_perf_device.request_key("/api/songs?q=a"))

    def test_export_refuses_external_origins_and_stateful_controls(self):
        """A request file cannot redirect export to production or advance a fixture."""
        for target in ("https://festivalscoretracker.com/api/songs", "//example.test/api/songs",
                       "/__fixture__/advance-publication", "/api/songs?q=%0Aextra"):
            with self.subTest(target=target), self.assertRaises(ValueError):
                uikit_perf_device.request_key(target)

    def test_normal_installed_app_identities_are_rejected_before_access(self):
        """The fresh-install path cannot erase either normal app's data."""
        for label, identifier in (("swiftui", "com.sfenton.festivalscoretracker.native"),
                                  ("uikit", "com.sfenton.festivalscoretracker.native.uikit")):
            with self.subTest(label=label), self.assertRaises(ValueError):
                uikit_perf_device.validate_app(f"{label}|/absent/FST.app|{identifier}|FST")

    def test_physical_launch_uses_actual_sandbox_and_no_simulator_prefix(self):
        """The iPhone never receives a host result path or a live-service default."""
        surface = uikit_perf.Surface("Songs", {"FST_DEBUG_TAB": "songs"})
        env = uikit_perf_device.physical_env(
            surface, "/private/var/mobile/Containers/Data/Application/fixture-container",
            Path("/host/run.tsv"), 12, 8,
        )
        self.assertEqual(env["FST_API_BASE_URL"], uikit_perf_device.ORIGIN)
        self.assertEqual(env["FST_PERF_FILE"],
                         "/private/var/mobile/Containers/Data/Application/fixture-container/Documents/run.tsv")
        self.assertFalse(any(key.startswith("SIMCTL_CHILD_") for key in env))
        with self.assertRaises(ValueError):
            uikit_perf_device.physical_env(surface, "/host/container", Path("/host/run.tsv"), 12, 8)

    def test_missing_context_warm_phone_and_unknown_reads_fail_closed(self):
        """Only complete nominal-power, zero-miss physical runs may qualify."""
        valid = "\n".join([
            "FSTPERF\tSongs\tcontext\tphase=start thermal=0 low_power=0 maximum_hz=120 fixture_active=1 fixture_misses=0",
            "FSTPERF\tSongs\tcontext\tphase=end thermal=0 low_power=0 maximum_hz=120 fixture_active=1 fixture_misses=0",
        ])
        self.assertEqual(uikit_perf_device.context_failures(valid), [])
        before_scene = valid.replace("phase=start thermal=0 low_power=0 maximum_hz=120",
                                     "phase=start thermal=0 low_power=0 maximum_hz=0")
        self.assertEqual(uikit_perf_device.context_failures(before_scene), [])
        for changed in ("thermal=1", "low_power=1", "fixture_misses=1", "maximum_hz=0"):
            key = changed.split("=")[0]
            original = "maximum_hz=120" if key == "maximum_hz" else f"{key}=0"
            with self.subTest(changed=changed):
                self.assertTrue(uikit_perf_device.context_failures(valid.replace(original, changed)))
        self.assertTrue(uikit_perf_device.context_failures(valid.splitlines()[0]))
        self.assertTrue(uikit_perf_device.context_failures(""))
        self.assertIn("physical failure", uikit_perf_report.qualify(
            {"runs": {}, "files": {}},
            {"platform": "physical-ios", "rounds": 3, "surfaces": [], "physical_failures": ["physical failure"]},
        ))

    def test_physical_report_never_labels_host_gpu_as_device_gpu(self):
        """Reuse report math, not simulator-only columns."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "r1-uikit-Songs.tsv").write_text(
                "FSTPERF\tSongs\tidle\tseconds=8 cpu_ms=9 main_ms=8 fps=119 hz=120 "
                "mem_mb=40 peak_mb=45 t0=100 t1=108\nFSTPERF_DONE\n"
            )
            collected = uikit_perf_report.collect(root)
            text, rows = uikit_perf_report.render(collected, physical=True)
            self.assertNotIn("Mac GPU", text)
            self.assertNotIn("render server CPU", text)
            self.assertNotIn("gpu_pct", rows[0])
            self.assertNotIn("render_ms", rows[0])
            qualification = uikit_perf_report.qualification_markdown(
                collected, {"platform": "physical-ios", "rounds": 3, "surfaces": [], "apps": []}
            )
            self.assertIn("Physical iOS device:", qualification)
            self.assertNotIn("Simulator:", qualification)
            self.assertNotIn("Mac GPU utilisation", qualification)

    def test_rerender_rechecks_raw_context_even_without_runner_failures(self):
        """Editing the manifest summary cannot turn a warm phone's raw evidence green."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "manifest.json").write_text(
                '{"platform":"physical-ios","rounds":3,"surfaces":[],"physical_failures":[]}'
            )
            (root / "r1-uikit-Songs.tsv").write_text(
                "FSTPERF\tSongs\tcontext\tphase=start thermal=1 low_power=0 maximum_hz=120 "
                "fixture_active=1 fixture_misses=0\nFSTPERF_DONE\n"
            )
            collected = uikit_perf_report.collect(root)
            failures = uikit_perf_report.qualify(collected, uikit_perf_report.load_manifest(root))
            self.assertTrue(any("thermal" in failure for failure in failures))
