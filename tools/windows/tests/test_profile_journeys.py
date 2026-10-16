"""Profile journeys (``journeys/profile.py``): step syntax, and a Quick Links pick waits for its jump (issue #663).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import importlib.util
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fade_journey  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

_PATH = Path(__file__).resolve().parents[1] / "journeys" / "profile.py"
_SPEC = importlib.util.spec_from_file_location("fst_profile_journeys", _PATH)
p = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = p
_SPEC.loader.exec_module(p)

MENU_PICK = re.compile(r"^toggle:id=(fst\.quick-links\.item\.[^@|]+)$")
TIMED = re.compile(r"@\d+(\.\d+)?$")


def quick_link_pick_errors(steps: list[str]) -> list[str]:
    """Returns why each Quick Links menu pick in ``steps`` isn't awaited by state.

    The menu jumps from a Low-priority dispatch after its flyout closes (#548), so the toggle returns before anything
    scrolls. A pick must be followed by ``waitgone`` on the picked item, then a timed ``assertstate`` that the button
    reports the new current section, never by a fixed ``wait:`` (``.agents/testing/windows.md``).
    """
    errors = []
    for i, step in enumerate(steps):
        match = MENU_PICK.match(step)
        if not match:
            continue
        after = steps[i + 1:i + 3]
        gone = f"waitgone:id={match.group(1)}@"
        if len(after) < 2 or not after[0].startswith(gone) or not TIMED.search(after[0]):
            errors.append(f"{step}: next step must be a timed {gone}N, got {after[:1]}")
        elif not (after[1].startswith("assertstate:id=fst.quick-links.open|name=")
                  and "current section " in after[1] and TIMED.search(after[1])):
            errors.append(f"{step}: must then assert the button's current section with @N, got {after[1]}")
    return errors


class ProfileJourneyStepTests(unittest.TestCase):
    def test_every_step_parses(self):
        for journey in p.JOURNEYS:
            for phase in journey.steps:
                for step in phase:
                    with self.subTest(journey=journey.name, step=step):
                        uiwin.parse_step(step)

    def test_quick_links_picks_wait_for_the_jump(self):
        picks = 0
        phases = [(j.name, phase) for j in p.JOURNEYS for phase in j.steps]
        phases += [(name, phase.steps) for name, s in fade_journey.SCENARIOS.items() for phase in s.phases]
        for name, phase in phases:
            picks += sum(1 for step in phase if MENU_PICK.match(step))
            with self.subTest(journey=name):
                self.assertEqual([], quick_link_pick_errors(phase))
        self.assertGreaterEqual(picks, 2)

    def test_statistics_quick_links_asserts_the_landing_after_the_jump_without_a_fixed_wait(self):
        steps = next(j for j in p.JOURNEYS if j.name == "statistics-quick-links").steps[0]
        toggle = steps.index("toggle:id=fst.quick-links.item.bands")
        landing = steps.index("assertinset:id=fst.player.bands-section|id=fst.player.available|32")
        self.assertEqual(["waitgone:id=fst.quick-links.item.bands@10",
                          "assertstate:id=fst.quick-links.open|name=Quick Links, current section Bands@10"],
                         steps[toggle + 1:landing])

    def test_the_guard_rejects_a_fixed_settle_wait(self):
        self.assertTrue(quick_link_pick_errors(["toggle:id=fst.quick-links.item.bands", "wait:1.5",
                                                "assertinset:id=a|id=b|32"]))
        self.assertTrue(quick_link_pick_errors(["toggle:id=fst.quick-links.item.bands",
                                                "waitgone:id=fst.quick-links.item.bands@10", "wait:1"]))
        self.assertEqual([], quick_link_pick_errors(
            ["toggle:id=fst.quick-links.item.bands", *fade_journey.QUICK_LINK_JUMPED]))


if __name__ == "__main__":
    unittest.main()
