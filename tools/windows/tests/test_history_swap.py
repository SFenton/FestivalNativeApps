"""``journeys/history-swap.json``: the Score History instrument-switch pages (issues #61 and #261).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import uiwin  # noqa: E402  (sibling module)

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
PAGES = json.loads((JOURNEYS / "history-swap.json").read_text("utf-8"))
LIVE = json.loads((JOURNEYS / "history-swap-live.json").read_text("utf-8"))
# The card's height, from the static subtitle above the graph to the sort button below the card. The graph's own UIA
# rectangle is the union of its drawn children, so it can read 8 epx short while a redraw is being laid out.
SPAN = "id=fst.history.subtitle|id=fst.history.sort.open|card"


def steps(page: dict) -> list[str]:
    """Return every step of a page in run order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


class HistorySwapJourneyTests(unittest.TestCase):
    """Each swap state has a page, every step parses and each height check has a baseline."""

    def test_every_state_has_a_page(self):
        names = {page["name"] for page in PAGES}
        for state in ("", "-detail", "-keyboard", "-instant"):
            self.assertIn(f"history-swap{state}", names)

    def test_every_step_parses(self):
        for page in PAGES:
            for step in steps(page):
                uiwin.parse_step(step)

    def test_spans_are_marked_before_they_are_asserted(self):
        for page in PAGES + LIVE:
            seen = [step for step in steps(page) if step.startswith(("markspan:", "assertspan:"))]
            self.assertEqual(seen[0], f"markspan:{SPAN}", page["name"])
            self.assertTrue(all(step == f"assertspan:{SPAN}" for step in seen[1:]), page["name"])
            self.assertGreater(len(seen), 1, page["name"])

    def test_rapid_switching_ends_on_the_last_pick(self):
        page = next(page for page in PAGES if page["name"] == "history-swap")
        run = steps(page)
        rapid = run.index("toggle:id=fst.history.instrument.Solo_Bass", run.index("tree:{stem}-drums.txt"))
        self.assertIn("assertstate:id=fst.history.instrument.Solo_Bass|toggle=on", run[rapid:])
        self.assertTrue(any(step.startswith("assertname:id=fst.history.chart|Bass ") for step in run[rapid:]))

    def test_posted_keys_switch_within_one_fade(self):
        page = next(page for page in PAGES if page["name"] == "history-swap-keyboard")
        run = steps(page)
        burst = run.index("keys:left space left space right space")
        self.assertEqual(run[burst + 1], f"assertspan:{SPAN}")
        tail = run[burst + 1:]
        self.assertIn("assertstate:id=fst.history.instrument.Solo_Bass|toggle=on", tail)
        self.assertTrue(any(step.startswith("assertname:id=fst.history.chart|Bass ") for step in tail))

    def test_live_pages_use_a_public_player_and_parse(self):
        for page in LIVE:
            self.assertEqual(page["profile"], "195e93ef108143b2975ee46662d4d0e1:SFentonX", page["name"])
            for step in steps(page):
                uiwin.parse_step(step)
            self.assertNotIn("fixture", page["route"])

    def test_instant_page_runs_only_with_reduced_motion(self):
        page = next(page for page in PAGES if page["name"] == "history-swap-instant")
        self.assertEqual(set(page["modes"]), {"no-animations", "app-reduced"})
        self.assertNotIn("wait:", " ".join(page["after_ready"]))

    def test_pages_use_the_multi_instrument_fixture(self):
        for page in PAGES:
            self.assertEqual(page["profile"], "fixture-history-multi:History Multi", page["name"])
            self.assertTrue(page["route"].startswith("/songs/fixture-pulse/"), page["name"])


if __name__ == "__main__":
    unittest.main()
