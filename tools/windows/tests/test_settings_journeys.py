"""Settings journeys (``journeys/settings.py``): step syntax and the pure tree/saved-settings checks.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from tools.windows import uiwin as u

_PATH = Path(__file__).resolve().parents[1] / "journeys" / "settings.py"
_SPEC = importlib.util.spec_from_file_location("fst_settings_journeys", _PATH)
s = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = s
_SPEC.loader.exec_module(s)

TREE = "\n".join([
    'Window "Festival Score Tracker" id= class=WinUIDesktopWin32WindowClass rect=0,0,800,600',
    '  Button "Toggle" id=fst.settings.shop-highlights class=ToggleSwitch rect=1,2,3,4 [disabled,focusable] patterns=Toggle',
    '  Button "Leeway" id=fst.settings.leeway class=Slider rect=1,2,3,4 [focusable] patterns=RangeValue',
])


class SettingsJourneyTests(unittest.TestCase):
    """Journey definitions parse and the checks report what they should."""

    def test_every_step_parses(self):
        for journey in s.JOURNEYS:
            self.assertTrue(journey.phases, journey.name)
            if journey.relaunch is not None:
                self.assertLess(journey.relaunch, len(journey.phases) - 1, journey.name)
            for phase in journey.phases:
                for step in phase.steps:
                    u.parse_step(step)

    def test_patterns(self):
        self.assertRegex(TREE, s._disabled("fst.settings.shop-highlights"))
        self.assertNotRegex(TREE, s._disabled("fst.settings.leeway"))
        self.assertRegex(TREE, s._id("fst.settings.leeway"))
        self.assertNotRegex(TREE, s._id("fst.settings.lee"))

    def test_check_tree(self):
        ok = s.Phase([], expect=[s._id("fst.settings.leeway")], forbid=[s._disabled("fst.settings.leeway")])
        self.assertEqual(s.check_tree(TREE, ok), [])
        bad = s.Phase([], expect=[s._id("fst.settings.reset")], forbid=[s._disabled("fst.settings.shop-highlights")])
        self.assertEqual(len(s.check_tree(TREE, bad)), 2)

    def test_states_pages_parse(self):
        pages = json.loads((_PATH.parent / "settings-states.json").read_text(encoding="utf-8"))
        self.assertEqual([p["name"] for p in pages], ["settings-expanded", "settings-keyboard"])
        for page in pages:
            for step in [*page.get("ready", []), *page.get("after_ready", [])]:
                u.parse_step(step.replace("{stem}", "out"))

    def test_check_saved(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "settings.json"
            phase = s.Phase([], saved={"on": lambda v: v["hideShop"] is True, "order": lambda v: v["order"][3] == 1})
            self.assertEqual(len(s.check_saved(path, phase)), 1)  # missing file
            path.write_text(json.dumps({"hideShop": True, "order": [1]}), encoding="utf-8")
            self.assertEqual(s.check_saved(path, phase), ["saved settings: order failed"])
            self.assertEqual(s.check_saved(path, s.Phase([])), [])


if __name__ == "__main__":
    unittest.main()
