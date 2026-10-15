"""Songs toolbar journey (``journeys/a11y-songs-toolbar.json``, issue #646).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import ui_ci as ci
from tools.windows import uiwin as u

_PAGES = {page["name"]: page for page in json.loads(
    (Path(__file__).resolve().parents[1] / "journeys" / "a11y-songs-toolbar.json").read_text(encoding="utf-8"))}
_SEARCH, _SORT, _FILTER, _JUMP = (f"id=fst.songs.{tool}" for tool in ("search", "sort", "filter", "section-index-button"))
_ROW = "id=fst.songs.row.fixture-pulse"


def _steps(page: dict) -> list[str]:
    return [*page.get("ready", []), *page.get("after_ready", [])]


class SongsToolbarJourneyTests(unittest.TestCase):
    """Both layouts check one height, 40 epx targets, a full-width row and reading order."""

    def test_steps_parse(self):
        for page in _PAGES.values():
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_every_tool_is_at_least_40_epx_and_buttons_40x40(self):
        for page in _PAGES.values():
            steps = _steps(page)
            with self.subTest(page=page["name"]):
                self.assertIn(f"assertsize:{_SEARCH}|0x40", steps)
                for button in (_SORT, _FILTER, _JUMP):
                    self.assertIn(f"assertsize:{button}|40x40", steps)

    def test_search_and_buttons_share_one_height(self):
        for page in _PAGES.values():
            steps = _steps(page)
            for a, b in ((_SEARCH, _SORT), (_SORT, _FILTER), (_FILTER, _JUMP)):
                with self.subTest(page=page["name"], pair=(a, b)):
                    self.assertIn(f"assertheight:{a}|{b}", steps)

    def test_row_fills_the_content_width_in_each_layout(self):
        row, stacked = _PAGES["songs-toolbar-row"], _PAGES["songs-toolbar-stacked"]
        self.assertIn(f"assertright:{_JUMP}|{_ROW}", _steps(row))
        self.assertIn(f"assertlevel:{_SEARCH}|{_JUMP}", _steps(row))
        self.assertIn(f"assertright:{_SEARCH}|{_ROW}", _steps(stacked))
        self.assertIn(f"assertbelow:{_SORT}|{_SEARCH}", _steps(stacked))
        self.assertEqual({"medium", "wide"}, set(row["sizes"]))
        self.assertEqual(["compact"], stacked["sizes"])

    def test_reading_order_is_search_then_tools_then_rows(self):
        for page in _PAGES.values():
            with self.subTest(page=page["name"]):
                self.assertIn(f"assertorder:{_SEARCH}|{_SORT}|{_FILTER}|{_JUMP}|{_ROW}", _steps(page))

    def test_ci_runs_both_layouts_at_default_and_large_text(self):
        runs = [run for run in ci.RUNS if run.pages == "a11y-songs-toolbar.json"]
        self.assertEqual({"normal", "text-225"}, {run.mode for run in runs})
        for run in runs:
            with self.subTest(run=run.name):
                self.assertIn("compact", run.sizes.split(","))
                self.assertIn("medium", run.sizes.split(","))


if __name__ == "__main__":
    unittest.main()
