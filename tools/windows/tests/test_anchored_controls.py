"""Anchored page controls journey (``journeys/anchored-controls.json``, issues #52 and #252).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "anchored-controls.json")
                    .read_text(encoding="utf-8"))
_SONGS = {"id=fst.songs.search", "id=fst.songs.sort", "id=fst.songs.filter", "id=fst.songs.section-index-button"}
_SUGGESTIONS = {"id=fst.suggestions.filter-button"}
_GLOBAL = "id=fst.global-search.open"


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


class AnchoredControlsJourneyTests(unittest.TestCase):
    """Every step parses, each page pins what it asserts, and live pages need no fixture."""

    def test_steps_parse(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_assertpinned_follows_pin(self):
        for page in _PAGES:
            pinned: set[str] = set()
            asserted = 0
            for step in _steps(page):
                verb, _, arg = step.partition(":")
                if verb == "pin":
                    pinned.add(arg)
                elif verb == "assertpinned":
                    self.assertIn(arg, pinned, f"{page['name']}: {step} before its pin")
                    asserted += 1
            with self.subTest(page=page["name"]):
                self.assertGreater(asserted, 0)

    def test_pages_cover_every_anchored_control_after_scrolling(self):
        for page in _PAGES:
            steps = _steps(page)
            pins = {s.partition(":")[2] for s in steps if s.startswith("pin:")}
            expected = _SUGGESTIONS if page.get("route") == "/suggestions" else _SONGS
            with self.subTest(page=page["name"]):
                self.assertIn(_GLOBAL, pins)
                if not page["name"].endswith("global-search"):
                    self.assertLessEqual(expected, pins)
                if "args" not in page:
                    self.assertTrue(any(s.startswith("scrollto:") for s in steps))

    def test_live_pages_need_no_fixture(self):
        live = {p["name"] for p in m.live_pages(_PAGES)}
        self.assertEqual({p["name"] for p in _PAGES if p["name"].endswith("-live")}, live)
        for page in _PAGES:
            if page["name"].endswith("-live"):
                self.assertTrue(page["profile"].endswith(":SFentonX"), page["name"])


if __name__ == "__main__":
    unittest.main()
