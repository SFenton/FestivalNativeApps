"""``fade_journey.py``: scenario steps are valid ``uiwin`` steps, and a deferred scroll is awaited (issue #663).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fade_journey as j  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)


class ScenarioStepTests(unittest.TestCase):
    def test_every_step_parses(self):
        for name, scenario in j.SCENARIOS.items():
            for phase in scenario.phases:
                for step in phase.steps:
                    with self.subTest(scenario=name, step=step):
                        uiwin.parse_step(step)

    def test_profile_waits_for_the_quick_links_jump_before_the_trace_is_read(self):
        # The menu jumps only after it closes, from a Low-priority dispatch: the phase must not end on the toggle.
        steps = j.SCENARIOS["profile"].phases[0].steps
        toggle = steps.index("toggle:id=fst.quick-links.item.bands")
        self.assertEqual(j.QUICK_LINK_JUMPED, steps[toggle + 1:])
        self.assertTrue(steps[-1].startswith("assertstate:id=fst.quick-links.open|name=Quick Links, current section Bands@"))


if __name__ == "__main__":
    unittest.main()
