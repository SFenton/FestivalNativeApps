"""App Navigation journeys (``journeys/navigation.py``): step syntax, state coverage and the pure tree checks.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import importlib.util
import re
import sys
import unittest
from pathlib import Path

from tools.windows import uiwin as u

_PATH = Path(__file__).resolve().parents[1] / "journeys" / "navigation.py"
_SPEC = importlib.util.spec_from_file_location("fst_navigation_journeys", _PATH)
n = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = n
_SPEC.loader.exec_module(n)

TREE = "\n".join([
    'Window "Festival Score Tracker" id= class=WinUIDesktopWin32WindowClass rect=0,0,800,600',
    '  Button "Select a player profile" id=fst.shell.profile class=Button rect=1,2,3,4 access=Alt, P [focusable] patterns=Invoke',
    '  ListItem "Songs" id=fst.nav.songs class=NavigationViewItem rect=1,2,3,4 accel=Control+1 access=Alt, S [focusable,selected] patterns=SelectionItem',
    '  ListItem "Leaderboards" id=fst.nav.leaderboards class=NavigationViewItem rect=1,2,3,4 accel=Control+2 access=Alt, L [focusable] patterns=SelectionItem',
    '  ListItem "Item Shop" id=fst.nav.shop class=NavigationViewItem rect=1,2,3,4 accel=Control+3 access=Alt, I [focusable] patterns=SelectionItem',
    '  ListItem "Settings" id=fst.nav.settings class=NavigationViewItem rect=1,2,3,4 accel=Control+Comma access=Alt, E [focusable] patterns=SelectionItem',
])


class NavigationJourneyTests(unittest.TestCase):
    """Journey definitions parse, cover every spec state and the checks report what they should."""

    def test_every_step_parses(self):
        for journey in n.JOURNEYS:
            self.assertIn(journey.preset, u.PRESETS, journey.name)
            for phase in journey.phases:
                for step in phase.steps:
                    with self.subTest(journey=journey.name, step=step):
                        u.parse_step(step)
                for pattern in [*phase.expect, *phase.forbid]:
                    re.compile(pattern)

    def test_covers_every_spec_state(self):
        names = {journey.name for journey in n.JOURNEYS}
        self.assertLessEqual({"songs", "leaderboards", "settings", "player", "band", "reselect"}, names)

    def test_selected_pattern(self):
        self.assertRegex(TREE, n.selected("fst.nav.songs"))
        self.assertNotRegex(TREE, n.selected("fst.nav.leaderboards"))
        self.assertNotRegex(TREE, n.selected("fst.nav.shop"))

    def test_present_pattern_is_exact(self):
        self.assertRegex(TREE, n.present("fst.nav.shop"))
        self.assertNotRegex(TREE, n.present("fst.nav.sho"))

    def test_check_passes(self):
        phase = n.Phase(steps=[], expect=[n.selected("fst.nav.songs"), r"accel=Control\+Comma access=Alt, E"],
                        forbid=[n.present("fst.nav.statistics")], order=n.ANONYMOUS_PANE)
        self.assertEqual([], n.check(phase, TREE))

    def test_check_reports_missing_forbidden_and_order(self):
        phase = n.Phase(steps=[], expect=[n.selected("fst.nav.leaderboards")], forbid=[n.present("fst.nav.songs")],
                        order=["fst.nav.shop", "fst.nav.songs"])
        failures = n.check(phase, TREE)
        self.assertEqual(3, len(failures))
        self.assertTrue(failures[0].startswith("expected /"))
        self.assertTrue(failures[1].startswith("did not expect /"))
        self.assertIn("'fst.nav.songs' after position", failures[2])

    def test_no_overview_pattern(self):
        # Issue #266: a Compete-style overview control fails the compete journey; other names don't.
        self.assertNotRegex(TREE, n.NO_OVERVIEW)
        self.assertRegex('  Button "Leaderboards Overview" id=fst.compete.overview class=Button', n.NO_OVERVIEW)
        self.assertRegex('  HyperlinkButton "Open leaderboard overview" id= class=HyperlinkButton', n.NO_OVERVIEW)
        self.assertNotRegex('  Text "Overview" id=fst.player.overview class=TextBlock', n.NO_OVERVIEW)
        compete = next(j for j in n.JOURNEYS if j.name == "compete")
        self.assertIn(n.NO_OVERVIEW, compete.phases[0].forbid)
        self.assertIn(n.NO_OVERVIEW, compete.phases[1].forbid)

    def test_check_reports_missing_order_item(self):
        failures = n.check(n.Phase(steps=[], order=n.PLAYER_PANE), TREE)
        self.assertEqual(1, len(failures))
        self.assertIn("fst.nav.suggestions", failures[0])


if __name__ == "__main__":
    unittest.main()
