"""Navigation-bar and page-tool hit-target journey (``journeys/a11y-hit-targets.json``, issues #72 and #271).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-hit-targets.json")
                    .read_text(encoding="utf-8"))
_MIN_EPX = 40.0
_TOOLS = {
    "fst.global-search.open", "fst.shell.profile", "fst.shell.notifications", "fst.songs.sort", "fst.songs.filter",
    "fst.songs.section-index-button", "fst.suggestions.filter-button", "fst.rankings.rank-by-menu",
    "fst.full-rankings.instrument-menu", "fst.band-rankings.band-type-menu", "fst.band-rankings.rank-by-menu",
    "fst.song-detail.paths", "fst.song-detail.pinned-paths", "fst.history.sort.open", "fst.shop.filter",
    "fst.quick-links.open",
}


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


def _id(step: dict) -> str:
    return step["selector"]["value"] if step["selector"]["kind"] == "id" else ""


class HitTargetsJourneyTests(unittest.TestCase):
    """Every step parses, each tool is sized and probed off-glyph, and the matrix covers each window layout."""

    def test_steps_parse(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_sizes_meet_the_fluent_minimum(self):
        for page in _PAGES:
            for raw in _steps(page):
                if raw.startswith("assertsize:"):
                    step = u.parse_step(raw)
                    with self.subTest(page=page["name"], step=raw):
                        self.assertEqual(step["height"], _MIN_EPX)
                        self.assertIn(step["width"], (0.0, _MIN_EPX))

    def test_every_sized_tool_is_probed_above_and_below(self):
        for page in _PAGES:
            parsed = [u.parse_step(s) for s in _steps(page)]
            sized = {_id(s) for s in parsed if s["verb"] == "assertsize"}
            probes = {(_id(s), s["dy"]) for s in parsed if s["verb"] == "assertat"}
            for tool in sized:
                with self.subTest(page=page["name"], tool=tool):
                    self.assertIn((tool, -18.5), probes)
                    self.assertIn((tool, 18.5), probes)

    def test_covers_every_tool_and_layout(self):
        tools = {_id(u.parse_step(s)) for p in _PAGES for s in _steps(p) if s.startswith("assertsize:")}
        self.assertLessEqual(_TOOLS, tools)
        sizes = {size for p in _PAGES for size in p.get("sizes", [])}
        self.assertLessEqual({"compact", "medium", "wide", "maximized", "snap-left", "snap-right"}, sizes)

    def test_titlebar_transitions_recheck_after_each_resize(self):
        page = next(p for p in _PAGES if p["name"] == "hit-titlebar-transitions")
        steps = _steps(page)
        resizes = [i for i, s in enumerate(steps) if s.startswith("resize:")]
        self.assertGreaterEqual(len(resizes), 3)
        for index in resizes:
            with self.subTest(step=steps[index]):
                self.assertTrue(any(s.startswith("assertat:id=fst.global-search.open") for s in steps[index + 1:]))
        notifications = steps.index("waitfor:id=fst.shell.notifications@10")
        self.assertIn("assertat:id=fst.global-search.open|0,-18.5", steps[notifications:])

    def test_live_pages_need_no_fixture(self):
        live = {p["name"] for p in m.live_pages(_PAGES) if p["name"].endswith("-live")}
        self.assertEqual({p["name"] for p in _PAGES if p["name"].endswith("-live")}, live)
        for page in _PAGES:
            if page["name"].endswith("-live"):
                self.assertTrue(page["profile"].endswith(":SFentonX"), page["name"])


if __name__ == "__main__":
    unittest.main()
