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
            for index, args in journey.relaunch_to.items():
                self.assertLess(index, len(journey.phases) - 1, journey.name)
                self.assertNotEqual(index, journey.relaunch, journey.name)
                self.assertIn(args[0], ("--route", "--tab"), journey.name)
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

    def test_version_pages_parse(self):
        pages = json.loads((_PATH.parent / "a11y-settings-version.json").read_text(encoding="utf-8"))
        self.assertEqual([p["name"] for p in pages], ["settings-version", "kb-settings-version"])
        for page in pages:
            self.assertNotIn("fixture", page)  # live-safe: anonymous public reads only
            for step in [*page.get("ready", []), *page.get("after_ready", [])]:
                u.parse_step(step.replace("{stem}", "out"))

    def test_path_view_pages_parse(self):
        pages = json.loads((_PATH.parent / "a11y-settings-path-view.json").read_text(encoding="utf-8"))
        self.assertEqual([p["name"] for p in pages], ["settings-path-view-image", "settings-path-view-text", "kb-settings-path-view"])
        for page in pages:
            self.assertNotIn("fixture", page)  # live-safe: anonymous public reads only
            self.assertNotIn("profile", page)
            for step in [*page.get("ready", []), *page.get("after_ready", [])]:
                u.parse_step(step.replace("{stem}", "out"))

    def test_path_default_view_journey_checks_inline_radio_group(self):
        journey = next(j for j in s.JOURNEYS if j.name == "path-default-view")
        first = journey.phases[0]
        tree = "\n".join([
            '    Text "CHOpt Path Default View" id= class=TextBlock rect=1,2,3,4 heading=3',
            '    Text "Choose whether CHOpt paths open as an image or text table by default." id= class=TextBlock rect=1,2,3,4',
            '    Group "CHOpt Path Default View" id=fst.settings.path-default-view class=Microsoft.UI.Xaml.Controls.RadioButtons rect=1,2,3,4',
            '      RadioButton "Image" id=fst.settings.path-default-view.image class=RadioButton rect=1,2,3,4 [focusable,selected] patterns=SelectionItem',
            '      RadioButton "Text" id=fst.settings.path-default-view.text class=RadioButton rect=1,2,3,4 [focusable] patterns=SelectionItem',
            '    Text "CHOpt Text Path Column Order" id= class=TextBlock rect=1,2,3,4 heading=3',
        ])
        self.assertEqual(s.check_tree(tree, first), [])
        disclosure = tree.replace("class=Microsoft.UI.Xaml.Controls.RadioButtons rect=1,2,3,4",
                                  "class=Expander rect=1,2,3,4 patterns=ExpandCollapse")
        self.assertEqual(len(s.check_tree(disclosure, first)), 1)  # a collapsible disclosure is not the inline picker
        self.assertEqual(len(s.check_tree(tree.replace('"Text" id=', '"Text view" id='), first)), 1)
        self.assertEqual(s._path_view_selected("text"), ["assertstate:id=fst.settings.path-default-view.text|selected=true@5",
                                                         "assertstate:id=fst.settings.path-default-view.image|selected=false"])
        self.assertEqual(journey.relaunch_to, {2: ["--route", s.PATHS_SONG]})
        saved = {name for phase in journey.phases for name in phase.saved}
        self.assertEqual(saved, {"pathDefaultView Text", "pathDefaultView Image"})

    def test_version_journey_checks_text_and_order(self):
        phase = next(j for j in s.JOURNEYS if j.name == "version").phases[0]

        def tree(app_version: str, swap: bool = False) -> str:
            rows = ['    Text "App Version" id= class=TextBlock rect=1,2,3,4',
                    f'    Text "{app_version}" id=fst.settings.app-version class=TextBlock rect=1,2,3,4',
                    '    Text "Build Configuration" id= class=TextBlock rect=1,2,3,4',
                    '    Text "Debug" id= class=TextBlock rect=1,2,3,4',
                    '    Text "Service Version" id= class=TextBlock rect=1,2,3,4',
                    '    Text "1.0.202" id=fst.settings.service-version class=TextBlock rect=1,2,3,4']
            if swap:
                rows[0], rows[1] = rows[1], rows[0]
            return "\n".join(rows)

        self.assertEqual(s.check_tree(tree("0.1.0 · ab87472"), phase), [])
        self.assertEqual(s.check_tree(tree("2610.04.01 · 0123abc"), phase), [])
        self.assertEqual(len(s.check_tree(tree("0.1.0"), phase)), 1)  # unstamped local build
        self.assertEqual(len(s.check_tree(tree("0.1.0 · AB87472"), phase)), 1)  # not normalised
        self.assertEqual(len(s.check_tree(tree("0.1.0 · ab87472", swap=True), phase)), 1)  # value read before label

    def test_order_requires_every_pattern(self):
        phase = s.Phase([], order=[s._id("fst.settings.leeway"), s._id("fst.settings.reset")])
        self.assertEqual(len(s.check_tree(TREE, phase)), 1)
        self.assertEqual(s.check_tree(TREE, s.Phase([], order=[s._id("fst.settings.shop-highlights"), s._id("fst.settings.leeway")])), [])

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
