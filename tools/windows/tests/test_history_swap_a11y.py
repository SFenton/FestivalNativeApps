"""``journeys/a11y-history-swap.json``: accessibility pages for Score History's instrument switch (issues #61, #423).

Issue #61 made the Score History graph fade out and back in on an instrument switch, keep the card's size, and switch
instantly with reduced motion. These checks keep the a11y_matrix pages honest: Axe scans, Narrator phrases and toggle
state, reading order through the swap, 40x40 targets, keyboard picks and Tab order, the instant swap, the page held
still across a swap (#423's scroll-anchoring fix), and the ``windows-ui`` runs (generated normal and text 225%; explicit
in-app Reduce Motion and Animation effects off).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import ui_ci
from tools.windows import uiwin as u

_FILE = "a11y-history-swap.json"
_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / _FILE).read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_SPAN = "id=fst.history.subtitle|raw=fst.history.rows|card"
_PAGE = "id=fst.song-detail|id=fst.history|page"
_INSTRUMENT = "id=fst.history.instrument."


def _steps(page: dict) -> list[str]:
    """A page's setup, ready and after-ready steps, in run order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", [])]


class HistorySwapA11yJourneyTests(unittest.TestCase):
    """The journey parses, covers what #61 changed and runs in ``windows-ui``."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_pages_are_fixture_scans_with_only_the_popup_allowed(self):
        self.assertEqual(set(_BY_NAME), {"history-swap-access", "history-swap-keyboard-access",
                                         "history-swap-reduced-access"})
        for page in _PAGES:
            self.assertTrue(page["scan"], page["name"])
            # Only WinUI's tooltip PopupHost (windows-accessibility open issue 8) may be dropped from the Axe results.
            self.assertEqual(page["axe_allow"], ["framework-popup"], page["name"])
            self.assertTrue(page["profile"].startswith("fixture-history-multi:"), page["name"])
            self.assertFalse(page.get("live_only"), page["name"])

    def test_access_page_reads_state_order_and_targets_across_the_swap(self):
        steps = _steps(_BY_NAME["history-swap-access"])
        pick = steps.index(f"toggle:{_INSTRUMENT}Solo_Bass")
        self.assertIn(f"assertread:{_INSTRUMENT}Solo_Bass|Bass, button, off", steps[:pick])
        self.assertIn(f"assertread:{_INSTRUMENT}Solo_Bass|Bass, button, on", steps[pick:])
        self.assertIn(f"assertsize:{_INSTRUMENT}Solo_Bass|40x40", steps)
        self.assertIn("assertstate:id=fst.history|heading=2", steps)
        orders = [s for s in steps if s.startswith("assertorder:")]
        self.assertTrue(any(s.endswith("|id=fst.history") and "Solo_Drums" in s for s in orders))
        # Page jumps hide when a page holds one bar (compact, 225% text), so the order ends on the entry pager.
        self.assertTrue(any(s.endswith("id=fst.history.chart|id=fst.history.bar.7|id=fst.history.entry-back")
                            for s in orders))
        self.assertNotIn("page-back", " ".join(steps))
        self.assertIn(f"markspan:{_SPAN}", steps)
        fading = steps.index(f"assertspan:{_SPAN}~12")
        self.assertIn(f"assertspan:{_SPAN}", steps[fading + 1:], "the span must settle back to 1 epx after the fade")

    def test_keyboard_page_picks_by_keys_and_keeps_focus(self):
        page = _BY_NAME["history-swap-keyboard-access"]
        steps = _steps(page)
        for key in ("key:right", "key:space", "key:left", "key:enter", "key:tab", "key:shift+tab"):
            self.assertIn(key, steps)
        space = steps.index("key:space")
        self.assertIn(f"assertfocus:{_INSTRUMENT}Solo_Bass@3", steps[space + 1:space + 4])
        # At 225% text the pinned header covers a selector 72 epx below the scroller's top.
        self.assertTrue(page["ready"][-1].endswith("|160"))

    def test_reduced_page_is_instant(self):
        page = _BY_NAME["history-swap-reduced-access"]
        self.assertEqual(page["modes"], ["app-reduced", "no-animations"])
        steps = _steps(page)
        self.assertTrue(any(s.startswith("assertname:id=fst.history.chart@0.1|") for s in steps))
        self.assertNotIn(f"assertspan:{_SPAN}~12", steps)
        self.assertNotIn("wait:0.8", steps)
        self.assertIn(f"assertspan:{_PAGE}", steps)

    def test_swaps_do_not_scroll_the_page(self):
        # #423: on a window tall enough to show a Leaderboards card, WinUI's scroll anchoring scrolled the page by the
        # top-five rows' height change (Bass 2 rows, Lead 5), pushing Score History off the top.
        for name in ("history-swap-access", "history-swap-reduced-access"):
            steps = _steps(_BY_NAME[name])
            with self.subTest(page=name):
                marks = [i for i, s in enumerate(steps) if s == f"markspan:{_PAGE}"]
                self.assertTrue(marks)
                for mark in marks:
                    pick = next(i for i in range(mark, len(steps)) if steps[i].startswith(f"toggle:{_INSTRUMENT}"))
                    self.assertIn(f"assertspan:{_PAGE}", steps[pick:], "every marked swap checks the page held")
        access = _steps(_BY_NAME["history-swap-access"])
        self.assertEqual(access.count(f"markspan:{_PAGE}"), 2, "Lead -> Bass and Bass -> Lead")

    def test_windows_ui_runs_every_page(self):
        runs = {run.name: run for run in ui_ci.RUNS if run.pages == _FILE}
        self.assertEqual(set(runs), {"a11y-history-swap-normal", "a11y-history-swap-text-225",
                                     "a11y-history-swap-app-reduced", "a11y-history-swap-no-animations"})
        ran = set()
        for run in runs.values():
            for page in ui_ci.run_pages(run):
                if m.page_sizes(page, run.sizes.split(","), run.mode):
                    ran.add(page["name"])
        self.assertEqual(ran, set(_BY_NAME))
        self.assertTrue(ui_ci.tier_runs([runs["a11y-history-swap-normal"]], "pr"))

    def test_reduced_page_runs_in_every_motion_off_mode(self):
        # The review of #585: the generated runs schedule only a page's first mode, so Windows' Animation effects off
        # (the other path that makes the swap instant) needs its own run.
        page = _BY_NAME["history-swap-reduced-access"]
        for mode in page["modes"]:
            runs = [run for run in ui_ci.RUNS if run.pages == _FILE and run.mode == mode]
            with self.subTest(mode=mode):
                self.assertEqual(len(runs), 1)
                self.assertEqual([p["name"] for p in ui_ci.run_pages(runs[0])], [page["name"]])
                self.assertTrue(m.page_sizes(page, runs[0].sizes.split(","), mode))


if __name__ == "__main__":
    unittest.main()
