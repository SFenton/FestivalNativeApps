"""Compete per-card loading accessibility pages (``journeys/a11y-compete-loading.json``, issue #427).

Issue #65 (PR #59) gave every Rivals hub card on ``/compete`` a centred ProgressRing named "Loading <Title>" until its
rows, empty removal or inline error replace it. These pages pin what that exposes to Narrator in the ``windows-ui`` job:
each ring's phrase and role (WinUI prefixes "Busy" to an active ring), that it is not a Tab stop, reading order title →
tabs → card header → its ring, the ring below its header and clear of it at 225% text, an Axe scan mid-load, the ring
giving way to rows card by card on both tabs, and the same ring with Reduce Motion or system animations off.
Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import ui_ci as ci
from tools.windows import uiwin as u

_FILE = "a11y-compete-loading.json"
_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / _FILE).read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_LEAD_RING = "id=fst.rivals.section.Solo_Guitar.loading"


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


class CompeteLoadingJourneyTests(unittest.TestCase):
    """The pages parse, use the slow fixture account and cover what #65 changed."""

    def test_every_step_parses_and_names_are_unique(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_pages_hold_the_rivals_reads_on_compete(self):
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                self.assertEqual(page["route"], "/compete")
                # rivals_fixture.py holds every rivals list read for accounts containing "-slow".
                self.assertIn("-slow", page["profile"].split(":")[0])
        self.assertEqual(m.live_pages(_PAGES), [])

    def test_rings_are_named_progress_indicators_outside_the_tab_order(self):
        steps = _steps(_BY_NAME["compete-loading"])
        self.assertIn(f"assertread:{_LEAD_RING}|Busy Loading Lead Rivals, ProgressRing", steps)
        self.assertIn("assertread:id=fst.rivals.section.common.loading|Busy Loading Common Rivals, ProgressRing", steps)
        self.assertIn(f"assertstate:{_LEAD_RING}|type=progressbar", steps)
        self.assertIn(f"assertstate:{_LEAD_RING}|focusable=false", steps)
        self.assertTrue(_BY_NAME["compete-loading"]["scan"])
        scan = steps.index("scan:{stem}-loading")
        self.assertEqual(steps[scan - 1], "wait:1")  # ProgressRing start-up transient (open issue 10)
        self.assertLess(scan, steps.index(f"waitgone:{_LEAD_RING}@30"))

    def test_reading_order_puts_each_header_before_its_ring(self):
        steps = _steps(_BY_NAME["compete-loading"])
        order = next(st for st in steps if st.startswith("assertorder:id=fst.rivals.title|"))
        self.assertIn("|id=fst.rivals.section.common|id=fst.rivals.section.common.loading|", order)
        self.assertTrue(order.endswith(f"|id=fst.rivals.section.Solo_Guitar|{_LEAD_RING}"))
        self.assertIn("assertbelow:id=fst.rivals.section.common.loading|id=fst.rivals.section.common", steps)
        self.assertIn("assertapart:id=fst.rivals.section.common|id=fst.rivals.section.common.loading", steps)

    def test_rings_give_way_to_rows_card_by_card_on_both_tabs(self):
        steps = _steps(_BY_NAME["compete-loading"])
        lead_gone = steps.index(f"waitgone:{_LEAD_RING}@30")
        common_still = steps.index("waitfor:id=fst.rivals.section.common.loading@2")
        self.assertLess(lead_gone, common_still)
        self.assertLess(common_still, steps.index("waitgone:id=fst.rivals.section.common.loading@45"))
        tab = steps.index("select:id=fst.rivals.tab.leaderboard")
        self.assertLess(tab, steps.index(
            "assertread:id=fst.rivals.section.leaderboard.Solo_Guitar.loading|Busy Loading Lead Rivals, ProgressRing"))
        self.assertLess(tab, steps.index("waitgone:id=fst.rivals.section.leaderboard.Solo_Guitar.loading@30"))

    def test_motion_pages_keep_the_named_ring(self):
        reduced = _BY_NAME["compete-loading-motion-reduced"]
        self.assertTrue(reduced["settings"]["reduceMotion"])
        self.assertEqual(m.mode_pages([reduced], "normal"), [reduced])
        system = _BY_NAME["compete-loading-motion-system"]
        self.assertEqual(m.mode_pages([system], "normal"), [])
        self.assertEqual(m.mode_pages([system], "no-animations"), [system])
        for page in (reduced, system):
            with self.subTest(page=page["name"]):
                self.assertIn(f"assertread:{_LEAD_RING}|Busy Loading Lead Rivals, ProgressRing", page["ready"])
                self.assertIn(f"waitgone:{_LEAD_RING}@30", page["ready"])

    def test_windows_ui_runs_default_largest_text_and_motion_off(self):
        runs = {run.mode: run for run in ci.RUNS if run.pages == _FILE}
        self.assertEqual(set(runs), {"normal", "text-225", "no-animations"})
        self.assertIn("compete-loading", runs["normal"].only.split(","))
        self.assertIn("compete-loading", runs["text-225"].only.split(","))
        self.assertTrue(all(run.scan for run in runs.values()))


if __name__ == "__main__":
    unittest.main()
