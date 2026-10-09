"""Back keeps place journeys (``journeys/back-keeps-place.json``, issue #276; its accessibility pages
``journeys/a11y-back-keeps-place.json``, issues #82/#435; pattern ``back-keeps-place`` R5).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import re
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
_FIXTURE = json.loads((_JOURNEYS / "back-keeps-place.json").read_text(encoding="utf-8"))
_A11Y = json.loads((_JOURNEYS / "a11y-back-keeps-place.json").read_text(encoding="utf-8"))
_PAGES = [*_FIXTURE, *_A11Y]
_BACK = ("key:alt+left", "invoke:id=PART_BackButton")


def _rounds(page: dict) -> list[list[str]]:
    """Splits a page's after-ready steps into one list per Back round (each ends at its first ``assertfocus`` after the
    Back step; later keyboard checks such as Tab and Shift+Tab are not rounds)."""
    rounds, current = [], []
    for step in page["after_ready"]:
        current.append(step)
        if step.startswith("assertfocus:") and any(s in _BACK for s in current):
            rounds.append(current)
            current = []
    return rounds


class BackKeepsPlaceJourneyTests(unittest.TestCase):
    """R5: each Back round pins the opener and its container and asserts both, immediately and after 1.5 s."""

    def test_steps_parse(self):
        for page in _PAGES:
            for step in [*page.get("ready", []), *page["after_ready"]]:
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_every_round_pins_opener_and_container_and_asserts_both_twice(self):
        for page in _PAGES:
            rounds = _rounds(page)
            self.assertTrue(rounds, page["name"])
            for index, steps in enumerate(rounds):
                with self.subTest(page=page["name"], round=index):
                    pins = [s.partition(":")[2] for s in steps if s.startswith("pin:")]
                    self.assertGreaterEqual(len(set(pins)), 2, "pin the opener and its card, section or container")
                    opener = steps[-1].partition(":")[2].rpartition("@")[0]
                    self.assertIn(opener, pins, "the focused opener is pinned")
                    back = next(i for i, s in enumerate(steps) if s in _BACK)
                    wait = steps.index("wait:1.5", back)
                    for pin in pins:
                        before = [s for s in steps[back:wait] if s == f"assertpinned:{pin}"]
                        after = [s for s in steps[wait:] if s == f"assertpinned:{pin}"]
                        self.assertEqual((len(before), len(after)), (1, 1), pin)

    def test_accessibility_pages_check_the_opener_before_and_after_back(self):
        """#435: the opener's Narrator phrase, button role, 40 epx height and reading order after its card are asserted
        before it is activated and again once Back has returned focus to it."""
        self.assertFalse([p for p in _A11Y if not p.get("profile", "fixture-").startswith("fixture-")], "fixtures only")
        verbs = ("assertread", "assertstate", "assertsize", "assertorder")
        backs = set()
        for page in _A11Y:
            with self.subTest(page=page["name"]):
                steps = page["after_ready"]
                (steps_round,) = _rounds(page)
                opener = steps_round[-1].partition(":")[2].rpartition("@")[0]
                back = next(i for i, s in enumerate(steps) if s in _BACK)
                backs.add(steps[back])
                focus = steps.index(steps_round[-1])
                for verb in verbs:
                    mine = [i for i, s in enumerate(steps) if s.startswith(f"{verb}:") and opener in s]
                    self.assertTrue(any(i < back for i in mine), f"{verb} before Back")
                    self.assertTrue(any(i > focus for i in mine), f"{verb} after focus returns")
                self.assertIn(f"assertsize:{opener}|0x40", steps)
                self.assertIn(f"assertstate:{opener}|type=button", steps)
                self.assertTrue(re.search(r", button$", next(s for s in steps if s.startswith(f"assertread:{opener}|"))))
        self.assertEqual(set(_BACK), backs, "cover keyboard (Alt+Left) and pointer (title-bar Back) returns")

    def test_live_pages_use_the_public_profile(self):
        live = {p["name"] for p in m.live_pages(_PAGES)}
        self.assertLessEqual({p["name"] for p in _PAGES if p["name"].endswith("-live")}, live)
        for page in _PAGES:
            if page["name"].endswith("-live"):
                self.assertTrue(page["profile"].endswith(":SFentonX"), page["name"])


if __name__ == "__main__":
    unittest.main()
