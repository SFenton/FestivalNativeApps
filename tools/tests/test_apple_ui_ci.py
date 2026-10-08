"""``apple-ci`` iPhone journey dispatcher (``apple_ui_ci.py``) and its workflow step (issue #441).

Run: ``python3 -m unittest discover -s tools/tests`` from the repo root.
"""

import re
import sys
import unittest
import urllib.request
from pathlib import Path

if sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise unittest.SkipTest("Apple tooling is POSIX-only")

from tools import apple_ui_ci as ci
from tools import ios_sim

ROOT = Path(__file__).resolve().parents[2]
UI_TESTS = ROOT / "apple" / "Apps" / "iOSUITests"
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"


def _runtimes(*entries):
    return {"runtimes": [
        {"identifier": f"com.apple.CoreSimulator.SimRuntime.iOS-{version.replace('.', '-')}", "platform": platform,
         "version": version, "isAvailable": available,
         "supportedDeviceTypes": [{"name": name, "identifier": f"type.{name.replace(' ', '-')}",
                                   "productFamily": "iPhone"} for name in devices]}
        for platform, version, available, devices in entries
    ]}


class RunsTests(unittest.TestCase):
    """Every registered journey exists, reads its fixture origin and is valid for ``ios_sim.py uitest``."""

    def test_runs_name_real_journeys_that_read_their_fixture(self):
        sources = {path.stem: path.read_text(encoding="utf-8") for path in UI_TESTS.glob("*.swift")}
        support = sources.get("SongsUITestSupport", "")
        names = [run.name for run in ci.RUNS]
        self.assertEqual(len(names), len(set(names)))
        for run in ci.RUNS:
            with self.subTest(run=run.name):
                self.assertTrue(run.selectors)
                self.assertLessEqual(set(run.a11y), set(ios_sim.A11Y_SETTINGS))
                for selector in run.selectors:
                    cls, _, method = selector.partition("/")
                    self.assertIn(cls, sources, f"{cls}.swift missing")
                    body = re.search(rf"func {re.escape(method)}\(\).*?\n    }}\n", sources[cls], re.S)
                    self.assertIsNotNone(body, f"{selector} not found")
                    reads = f'environment["{run.fixture_env}"]'
                    self.assertTrue(
                        reads in body.group(0) or ("SongsUITestSupport.fixtureURL" in body.group(0) and reads in support),
                        f"{selector} must read its fixture origin from {run.fixture_env}, not a fixed port",
                    )

    def test_section_title_ax5_journey_gates_pull_requests(self):
        selectors = {selector for run in ci.RUNS for selector in run.selectors}
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", selectors)

    def test_uitest_argv_runs_one_batch_per_run(self):
        run = ci.Run("demo", ("A/testOne", "B/testTwo"), a11y=("bold-text",), timeout=90)
        argv = run.uitest_argv("UDID-1")
        self.assertEqual(argv[1:6], [str(ci.IOS_SIM), "uitest", "--device", "UDID-1", "--timeout"])
        self.assertEqual(argv[argv.index("--batch-size") + 1], "2")
        self.assertEqual(argv[argv.index("--timeout") + 1], "90")
        self.assertEqual([argv[i + 1] for i, arg in enumerate(argv) if arg == "--only"], ["A/testOne", "B/testTwo"])
        self.assertEqual(argv[argv.index("--a11y") + 1], "bold-text")

    def test_select(self):
        self.assertEqual(ci.select(ci.RUNS, None), list(ci.RUNS))
        self.assertEqual([run.name for run in ci.select(ci.RUNS, "songs-section-titles-ax5")],
                         ["songs-section-titles-ax5"])
        with self.assertRaises(ValueError):
            ci.select(ci.RUNS, "nope")


class SimulatorTests(unittest.TestCase):
    """``--create-simulator`` picks the newest runtime that supports the reference iPhone."""

    def test_picks_newest_runtime_supporting_the_reference_device(self):
        runtimes = _runtimes(
            ("iOS", "26.5", True, ["iPhone 17 Pro"]),
            ("iOS", "27.1", True, ["iPhone Duo"]),
            ("iOS", "27.0", True, ["iPhone 18 Pro", "iPhone 17 Pro"]),
            ("iOS", "28.0", False, ["iPhone 17 Pro"]),
            ("watchOS", "27.0", True, ["iPhone 17 Pro"]),
        )
        self.assertEqual(ci.pick_runtime(runtimes),
                         ("com.apple.CoreSimulator.SimRuntime.iOS-27-0", "type.iPhone-17-Pro"))

    def test_numeric_versions_order_correctly(self):
        runtimes = _runtimes(("iOS", "9.3", True, ["iPhone 17 Pro"]), ("iOS", "27.10", True, ["iPhone 17 Pro"]),
                             ("iOS", "27.2", True, ["iPhone 17 Pro"]))
        self.assertEqual(ci.pick_runtime(runtimes)[0], "com.apple.CoreSimulator.SimRuntime.iOS-27-10")

    def test_no_supporting_runtime_fails_clearly(self):
        with self.assertRaises(LookupError):
            ci.pick_runtime(_runtimes(("iOS", "27.1", True, ["iPhone Duo"])))


class FixtureTests(unittest.TestCase):
    """Each run serves its own loopback fixture on a free port."""

    def test_ready_port(self):
        self.assertEqual(ci.ready_port("Local test fixture service on 127.0.0.1:51234\n"), 51234)
        self.assertIsNone(ci.ready_port("127.0.0.1 - - GET /api/songs 200"))

    def test_fixture_service_serves_loopback_then_stops(self):
        with ci.fixture_service(()) as origin:
            self.assertRegex(origin, r"^http://127\.0\.0\.1:\d+$")
            with urllib.request.urlopen(f"{origin}/api/songs", timeout=10) as response:
                self.assertEqual(response.status, 200)
        with self.assertRaises(OSError):
            urllib.request.urlopen(f"{origin}/api/songs", timeout=2)


class WorkflowTests(unittest.TestCase):
    """``apple-ci`` runs the registry on a runner-local simulator after the hosted tests."""

    def test_apple_ci_runs_the_registry(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("python3 tools/apple_ui_ci.py --create-simulator", workflow)
        self.assertLess(workflow.index("swift test --parallel"), workflow.index("run: python3 tools/apple_ui_ci.py"))


if __name__ == "__main__":
    unittest.main()
