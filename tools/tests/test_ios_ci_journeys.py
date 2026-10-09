"""``apple-ci`` simulator journeys: the CI list, fixture grouping and simulator choice in ``tools/ios_ci_journeys.py``."""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling; the fixture service check uses select() on a pipe.
    raise _unittest.SkipTest("Apple simulator tooling runs only on macOS/Linux")

import unittest
import unittest.mock
import urllib.request
from pathlib import Path

from tools import ios_ci_journeys as ci

UITESTS = Path(__file__).resolve().parents[2] / "apple" / "Apps" / "iOSUITests"


class JourneyListTests(unittest.TestCase):
    """The CI list names real journeys and keeps the #394 reading-order guard."""

    def test_every_selector_names_an_existing_test_method(self) -> None:
        for journey in ci.JOURNEYS:
            cls, _, method = journey.selector.partition("/")
            self.assertTrue(method, journey.selector)
            source = UITESTS / f"{cls}.swift"
            self.assertTrue(source.exists(), f"{cls} not in apple/Apps/iOSUITests")
            text = source.read_text(encoding="utf-8")
            self.assertIn(f"class {cls}", text)
            self.assertIn(f"func {method}()", text, journey.selector)

    def test_selectors_are_unique_and_explained(self) -> None:
        selectors = [journey.selector for journey in ci.JOURNEYS]
        self.assertEqual(len(selectors), len(set(selectors)))
        for journey in ci.JOURNEYS:
            self.assertTrue(journey.reason.strip(), journey.selector)

    def test_account_reading_order_journeys_run_in_ci(self) -> None:
        """Issue #394 review: the production-chrome Profile → bell order must be guarded in apple-ci."""
        selectors = {journey.selector for journey in ci.JOURNEYS}
        for method in (
            "testAccountButtonsReadInProductionChromeOrder",
            "testAccountButtonsReadInProductionChromeOrderOnPushedPage",
            "testChooseProfileReadsAloneInProductionChrome",
            "testAccountButtonsStaySeparateAndLabelledAtLargestTextSize",
        ):
            self.assertIn(f"NavButtonHitRegionJourneyTests/{method}", selectors)


class GroupingTests(unittest.TestCase):
    def test_groups_by_fixture_in_first_appearance_order(self) -> None:
        journeys = [
            ci.Journey("A/a", "r"), ci.Journey("B/b", "r", ("--large-catalogue",)), ci.Journey("C/c", "r"),
        ]
        self.assertEqual(
            ci.fixture_groups(journeys), [((), ["A/a", "C/c"]), (("--large-catalogue",), ["B/b"])]
        )

    def test_choose_filters_by_substring_and_rejects_unknown(self) -> None:
        journeys = [ci.Journey("A/alpha", "r"), ci.Journey("B/beta", "r")]
        self.assertEqual(ci.choose(journeys, None), journeys)
        self.assertEqual([j.selector for j in ci.choose(journeys, ["beta"])], ["B/beta"])
        with self.assertRaises(ValueError):
            ci.choose(journeys, ["gamma"])


class SimulatorChoiceTests(unittest.TestCase):
    RUNTIMES = {"runtimes": [
        {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "platform": "iOS",
         "isAvailable": True},
        {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1", "version": "27.1", "platform": "iOS",
         "isAvailable": True,
         "supportedDeviceTypes": [{"name": "iPhone 16 Pro", "identifier": "t.16pro"},
                                  {"name": "iPhone 17 Pro", "identifier": "t.17pro"}]},
        {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-28-0", "version": "28.0", "platform": "iOS",
         "isAvailable": False},
        {"identifier": "com.apple.CoreSimulator.SimRuntime.watchOS-27-0", "version": "27.0", "platform": "watchOS",
         "isAvailable": True},
    ]}

    def test_newest_available_ios_runtime(self) -> None:
        self.assertEqual(ci.pick_runtime(self.RUNTIMES), "com.apple.CoreSimulator.SimRuntime.iOS-27-1")

    def test_no_ios_runtime_is_an_error(self) -> None:
        with self.assertRaises(LookupError):
            ci.pick_runtime({"runtimes": [{"identifier": "w", "platform": "watchOS", "isAvailable": True}]})

    def test_reference_device_type_first(self) -> None:
        runtime = self.RUNTIMES["runtimes"][1]
        self.assertEqual(ci.pick_device_type(runtime, {"devicetypes": []}), "t.17pro")
        self.assertEqual(
            ci.pick_device_type(None, {"devicetypes": [{"name": "iPhone 16 Pro", "identifier": "t.16pro"}]}),
            "t.16pro",
        )
        with self.assertRaises(LookupError):
            ci.pick_device_type(None, {"devicetypes": [{"name": "iPad Pro", "identifier": "t.ipad"}]})

    def test_create_simulator_refuses_outside_github_actions(self) -> None:
        with unittest.mock.patch.dict("os.environ", {"GITHUB_ACTIONS": ""}):
            with self.assertRaises(SystemExit):
                with ci.throwaway_simulator():
                    pass


class FixtureServiceTests(unittest.TestCase):
    def test_ready_line(self) -> None:
        self.assertEqual(ci.parse_ready_port("Local test fixture service on 127.0.0.1:8765\n"), 8765)
        self.assertIsNone(ci.parse_ready_port("127.0.0.1 - - GET /api/songs 200"))

    def test_serves_loopback_fixture_until_the_block_ends(self) -> None:
        with ci.fixture_service((), port=0) as port:
            self.assertGreater(port, 0)
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/songs", timeout=10) as response:
                self.assertEqual(response.status, 200)
        with self.assertRaises(OSError):
            urllib.request.urlopen(f"http://127.0.0.1:{port}/api/songs", timeout=2)


if __name__ == "__main__":
    unittest.main()
