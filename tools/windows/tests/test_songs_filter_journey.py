"""``songs_filter_fixture.py`` / ``songs_filter_journey.py``: Shop-feed pinning and journey step compilation.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import songs_filter_fixture as fixture  # noqa: E402  (sibling module)
import songs_filter_journey as journey  # noqa: E402  (sibling module)

FILTER_LINE = ('Button "Filter Songs" id=fst.songs.filter class=Microsoft.UI.Xaml.Controls.DropDownButton '
               'rect=1,2,3,4{status} [focusable] patterns=Invoke,ExpandCollapse')
SWITCH_LINE = ('Button "Missing Pro Lead Scores" id=fst.songs.filter.score.chart.prolead.missing-scores '
               'class=ToggleSwitch rect=1,2,3,4 toggle={state} [focusable] patterns=Toggle')


class FixtureTests(unittest.TestCase):
    """Shop read rewriting and the ``--shop`` option."""

    def test_rewrite_pins_shop_reads_only(self):
        self.assertEqual(fixture.rewrite("/api/shop", "empty"), "/api/shop?scenario=empty")
        self.assertEqual(fixture.rewrite("/api/shop?x=1", "error"), "/api/shop?x=1&scenario=error")
        self.assertEqual(fixture.rewrite("/api/shop?scenario=demo", "error"), "/api/shop?scenario=demo")
        self.assertEqual(fixture.rewrite("/api/songs", "empty"), "/api/songs")
        self.assertEqual(fixture.rewrite("/api/shop", "demo"), "/api/shop")

    def test_split_args_takes_shop_option(self):
        self.assertEqual(fixture.split_args(["--shop", "empty", "--port", "1"]), ("empty", ["--port", "1"]))
        self.assertEqual(fixture.split_args(["--shop=error"]), ("error", []))
        self.assertEqual(fixture.split_args(["--port", "2"]), ("demo", ["--port", "2"]))
        with self.assertRaises(SystemExit):
            fixture.split_args(["--shop", "broken"])
        with self.assertRaises(SystemExit):
            fixture.split_args(["--shop"])

    def test_mark_double_bass_sets_listed_songs_only(self):
        catalogue = {"songs": [{"songId": "fixture-pulse"}, {"songId": "fixture-orbit"}, {"songId": "other"}]}
        fixture.mark_double_bass(catalogue)
        self.assertEqual([song.get("doubleBassSupported") for song in catalogue["songs"]], [True, False, None])
        self.assertNotIn("doubleBassSupported", catalogue["songs"][2])


class JourneyTests(unittest.TestCase):
    """Tree checks, placeholder compilation and Axe parsing."""

    def test_status_reads_item_status(self):
        self.assertEqual(journey.status_of(FILTER_LINE.format(status=' status="Filters applied"')), "Filters applied")
        self.assertEqual(journey.status_of(FILTER_LINE.format(status="")), "")
        self.assertIsNone(journey.status_of("Text \"Songs\" id=fst.songs.title class=TextBlock"))

    def test_toggle_reads_state(self):
        tree = SWITCH_LINE.format(state="On")
        automation_id = "fst.songs.filter.score.chart.prolead.missing-scores"
        self.assertEqual(journey.toggle_of(tree, automation_id), "On")
        self.assertIsNone(journey.toggle_of(tree, "fst.songs.filter.score.chart.prolead"))
        self.assertIsNone(journey.toggle_of(FILTER_LINE.format(status=""), "fst.songs.filter"))

    def test_check_tree(self):
        applied = FILTER_LINE.format(status=' status="Filters applied"') + "\n" + SWITCH_LINE.format(state="Off")
        self.assertIsNone(journey.check_tree(applied, "status", "Filters applied"))
        self.assertIn("expected ''", journey.check_tree(applied, "status", ""))
        self.assertIsNone(journey.check_tree(applied, "toggle", "fst.songs.filter.score.chart.prolead.missing-scores=Off"))
        self.assertIn("expected 'On'",
                      journey.check_tree(applied, "toggle", "fst.songs.filter.score.chart.prolead.missing-scores=On"))

    def test_compile_steps_expands_placeholders(self):
        work, shots = Path(tempfile.gettempdir()) / "w", Path(tempfile.gettempdir()) / "s"
        steps, checks = journey.compile_steps(
            ["expand:id=fst.songs.filter", "{shot:open}", "{scan:open}", "{status:}", "{toggle:a.b=On}"],
            work, shots, "compact", 1)
        self.assertEqual(steps[0], "expand:id=fst.songs.filter")
        self.assertEqual(steps[1], f"shot:{shots / 'open-compact.png'}")
        self.assertEqual(steps[2], f"scan:{work / 'open-compact'}")
        self.assertEqual(steps[3:], [f"tree:{work / 'tree-1-0.txt'}", f"tree:{work / 'tree-1-1.txt'}"])
        self.assertEqual(checks, [(work / "tree-1-0.txt", "status", ""), (work / "tree-1-1.txt", "toggle", "a.b=On")])
        no_shots, _ = journey.compile_steps(["{shot:open}"], work, None, "wide")
        self.assertEqual(no_shots, [])

    def test_scan_errors(self):
        response = {"scans": [{"scan_id": "a", "errors": 0}, {"scan_id": "b", "errors": 2, "findings": [{"rule": "NameNotNull"}]}]}
        errors = journey.scan_errors("log line\n" + json.dumps(response))
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("b: 1 Axe error(s)"))
        popup = {"rule": "BoundingRectangleCompletelyObscuresContainer", "element": {"ClassName": "InputSiteWindowClass"},
                 "parents": ['Pane(50033) "PopupHost" id= class=Microsoft.UI.Content.PopupWindowSiteBridge', "Window"]}
        app = {"rule": "NameNotNull", "element": {"ClassName": "Button"}, "parents": ["Window"]}
        self.assertEqual(journey.scan_errors(json.dumps({"scans": [{"scan_id": "c", "errors": 2,
                                                                    "findings": [popup, popup]}]})), [])
        mixed = journey.scan_errors(json.dumps({"scans": [{"scan_id": "d", "errors": 2, "findings": [popup, app]}]}))
        self.assertEqual(len(mixed), 1)
        self.assertIn("NameNotNull", mixed[0])
        self.assertNotIn("PopupWindowSiteBridge", mixed[0])
        self.assertEqual(journey.scan_errors("no json"), [])
        self.assertEqual(journey.scan_errors("{broken"), [])

    def test_every_scenario_names_spec_states_and_compiles(self):
        for name, scenario in journey.SCENARIOS.items():
            self.assertTrue(scenario.states, name)
            self.assertIn(scenario.shop, fixture.SHOP_SCENARIOS, name)
            for step in scenario.steps:
                if step == journey.RELAUNCH or step.startswith("{"):
                    continue
                self.assertIn(step.split(":", 1)[0], ("waitfor", "waitgone", "expand", "collapse", "invoke", "toggle",
                                                      "scrollinto", "setvalue", "key", "wait"), f"{name}: {step}")


if __name__ == "__main__":
    unittest.main()
