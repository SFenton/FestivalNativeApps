"""Item Shop Filters flyout accessibility pages (``journeys/a11y-shop-filter.json``, issue #428).

Tracker #19 (PR #80) added the Shop Filters flyout: a level-2 "Filter Item Shop" heading, New / Available / Leaving
Tomorrow toggle switches with a description each, a red Reset, the "Filters applied" button status, the "N of M songs"
count and the empty state. These pages pin their Narrator phrases, roles and state, the flyout's reading order (the
flyout lives in a popup host Narrator still walks), 40 epx targets (Reset was 32 epx before #428) and text scaling.
The default mock fixture has one New (``fixture-pulse``) and one Leaving Tomorrow (``fixture-orbit``) song. Run:
``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-shop-filter.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_SWITCHES = {
    "new": "New, toggle switch, {}, Songs that are new in the Item Shop today.",
    "available": "Available, toggle switch, {}, Songs in the Item Shop today that aren't new or leaving tomorrow.",
    "leaving": "Leaving Tomorrow, toggle switch, {}, Songs that are leaving the Item Shop tomorrow.",
}
_RESET = "assertread:id=fst.shop.filter.reset|Reset Item Shop Filters, button"


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


class ShopFilterJourneyTests(unittest.TestCase):
    """The pages parse, run on the Shop and cover every flyout requirement #428 asks for."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in [*_steps(page), *page.get("teardown", [])]:
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_names_are_unique_and_pages_are_live_safe(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                self.assertEqual(page["route"], "/shop")
                self.assertNotIn("fixture", page)
        # Every page uses only public reads, but the counts and empty state assume the default mock fixture.
        self.assertEqual(len(m.live_pages(_PAGES)), len(_PAGES))

    def test_read_page_covers_labels_roles_order_and_targets(self):
        page = _BY_NAME["shop-filter-read"]
        steps = _steps(page)
        self.assertTrue(page["scan"])
        self.assertEqual(set(page["sizes"]), {"compact", "medium", "wide"})
        self.assertIn("assertread:id=fst.shop.filter|Filter Item Shop, button, collapsed", steps)
        self.assertIn("assertread:id=fst.shop.filter.title|Filter Item Shop, text", steps)
        self.assertIn("assertstate:id=fst.shop.filter.title|heading=2", steps)
        for key, phrase in _SWITCHES.items():
            self.assertIn(f"assertread:id=fst.shop.filter.{key}|{phrase.format('on')}", steps)
            self.assertIn(f"assertsize:id=fst.shop.filter.{key}|40x40", steps)
        self.assertIn(_RESET, steps)
        self.assertIn("assertorder:id=fst.shop.filter.title|id=fst.shop.filter.new|id=fst.shop.filter.available"
                      "|id=fst.shop.filter.leaving|id=fst.shop.filter.reset", steps)
        self.assertIn("narrate:id=FilterFlyout", steps)
        # Issue #428: Reset is a 40 epx target, checked by size and by hit tests 18.5 epx above and below its centre.
        self.assertIn("assertsize:id=fst.shop.filter.reset|0x40", steps)
        self.assertEqual(sum(st.startswith("assertat:id=fst.shop.filter.reset|") for st in steps), 2)
        self.assertEqual(sum(st.startswith("assertat:id=fst.shop.filter.new|") for st in steps), 4)
        self.assertEqual(sum(st.startswith("assertapart:") for st in steps), 3)
        self.assertIn("collapse:id=fst.shop.filter", page["teardown"])

    def test_state_page_reads_toggle_count_status_and_reset(self):
        steps = _steps(_BY_NAME["shop-filter-state"])
        off = steps.index(f"assertread:id=fst.shop.filter.new|{_SWITCHES['new'].format('off')}")
        self.assertGreater(off, steps.index("toggle:id=fst.shop.filter.new"))
        self.assertIn("assertname:id=fst.shop.count|1 of 2 songs", steps)
        self.assertIn("assertstatus:id=fst.shop.filter|Filters applied@5", steps)
        reset = steps.index("invoke:id=fst.shop.filter.reset")
        self.assertIn(f"assertread:id=fst.shop.filter.new|{_SWITCHES['new'].format('on')}", steps[reset:])
        self.assertIn("assertname:id=fst.shop.count|2 songs", steps[reset:])
        self.assertIn("assertread:id=fst.shop.filter|Filter Item Shop, button, collapsed, Filters applied", steps)

    def test_empty_page_reads_the_empty_state_in_order(self):
        page = _BY_NAME["shop-filter-empty-read"]
        steps = _steps(page)
        self.assertTrue(page["scan"])
        self.assertIn("assertread:id=fst.shop.filter.empty|No Item Shop songs match your filters, text", steps)
        self.assertIn("assertread:id=fst.shop.filter.empty-message|Try changing your filters to see more songs., text",
                      steps)
        self.assertIn("assertorder:id=fst.shop.filter|id=fst.shop.filter.empty|id=fst.shop.filter.empty-message", steps)

    def test_text_page_runs_only_at_large_text(self):
        page = _BY_NAME["shop-filter-text"]
        self.assertEqual(m.mode_pages([page], "normal"), [])
        for mode in ("text-150", "text-200", "text-225", "hc-desert+text-225"):
            self.assertEqual(m.mode_pages([page], mode), [page], mode)
        steps = _steps(page)
        self.assertIn(_RESET, steps)
        self.assertIn("assertsize:id=fst.shop.filter.reset|0x40", steps)
        for key in _SWITCHES:
            self.assertIn(f"assertsize:id=fst.shop.filter.{key}|40x40", steps)
        # The wrapped descriptions never overlap their switch at large text, and Leaving Tomorrow clears the pinned Reset.
        self.assertGreaterEqual(sum(st.startswith("assertapart:") for st in steps), 4)
        # The rows scroll inside the flyout at 200%+ text while Reset stays pinned below them.
        self.assertIn("scrollto:id=fst.shop.filter.scroll,100", steps)
        self.assertIn("assertapart:id=fst.shop.filter.leaving|id=fst.shop.filter.reset", steps)

    def test_one_viewport_pages_scroll_or_skip_at_large_text(self):
        read = _BY_NAME["shop-filter-read"]
        self.assertEqual(m.mode_pages([read], "text-150"), [read])
        for mode in ("text-200", "text-225"):
            self.assertEqual(m.mode_pages([read], mode), [], mode)
        for name in ("shop-filter-state", "shop-filter-empty-read"):
            steps = _steps(_BY_NAME[name])
            toggle = steps.index("toggle:id=fst.shop.filter.leaving")
            self.assertEqual(steps[toggle - 2], "scrollto:id=fst.shop.filter.scroll,100", name)


if __name__ == "__main__":
    unittest.main()
