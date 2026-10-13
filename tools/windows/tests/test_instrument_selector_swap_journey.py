"""Instrument Selector responsive-swap tooltip pages (``journeys/a11y-instrument-selector.json``, issue #574).

Each page opens a tooltip in the row a resize hides, swaps the layout, and checks focus moved to the counterpart and no
tooltip remains before the Axe scan. Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import ui_ci
from tools.windows import uiwin as u

_FILE = "a11y-instrument-selector.json"
_PAGES = {p["name"]: p for p in json.loads((Path(__file__).resolve().parents[1] / "journeys" / _FILE)
                                           .read_text(encoding="utf-8"))}
_SWAPS = {
    # page: (size it ends at, size it opens the tooltip at, tooltip owner, focus after the swap)
    "instrument-selector-swap-narrow": ("compact", "medium", "fst.instrument-selector.auto.Solo_Bass",
                                        "fst.instrument-selector.auto.compact"),
    "instrument-selector-swap-widen": ("medium", "compact", "fst.instrument-selector.auto.next",
                                       "fst.instrument-selector.auto.Solo_Guitar"),
}


class InstrumentSelectorSwapJourneyTests(unittest.TestCase):
    def test_pages_parse(self):
        for name in _SWAPS:
            page = _PAGES[name]
            for step in (*page["setup"], *page["ready"], *page["after_ready"]):
                u.parse_step(step)

    def test_tooltip_opens_from_the_keyboard_before_the_swap(self):
        for name, (end, start, owner, _) in _SWAPS.items():
            setup = _PAGES[name]["setup"]
            self.assertEqual(setup[0], f"resize:{start}", name)
            focused = setup.index(f"assertfocus:id={owner}@3")
            # A real key, not UIA SetFocus, gives focus last: after SetFocus the programmatic hand-off still opens
            # the newcomer's tooltip (platforms/windows.md gotcha).
            self.assertTrue(setup[focused - 1].startswith("key:"), name)
            self.assertIn("&class=ToolTip@", setup[focused + 1], name)
            self.assertEqual(setup[focused + 2], f"resize:{end}", name)

    def test_swap_moves_focus_and_leaves_no_tooltip(self):
        for name, (end, _, _, target) in _SWAPS.items():
            page = _PAGES[name]
            self.assertEqual(page["sizes"], [end], name)
            self.assertEqual(page["after_ready"][0], f"assertfocus:id={target}@3", name)
            self.assertEqual(page["after_ready"][-1], "waitgone:class=ToolTip@3", name)
            steps = m.page_steps(page, end, Path("out"), "", True, 0)
            self.assertLess(steps.index("waitgone:class=ToolTip@3"), next(i for i, s in enumerate(steps)
                                                                           if s.startswith("scan:")), name)

    def test_ci_runs_them_at_normal_and_text_225(self):
        for mode in ("normal", "text-225"):
            run = next(r for r in ui_ci.RUNS if r.pages == _FILE and r.mode == mode)
            for name, (end, *_rest) in _SWAPS.items():
                self.assertIn(name, run.only.split(","), (mode, name))
                self.assertIn(end, run.sizes.split(","), (mode, name))
                self.assertTrue(run.scan, mode)


if __name__ == "__main__":
    unittest.main()
