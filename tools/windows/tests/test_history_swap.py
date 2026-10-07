"""``journeys/history-swap.json``: Song Detail's Score History instrument-switch pages (issues #61, #261 and #324).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import a11y_matrix  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
PAGES = json.loads((JOURNEYS / "history-swap.json").read_text("utf-8"))
LIVE = json.loads((JOURNEYS / "history-swap-live.json").read_text("utf-8"))
# The card's height, from the static subtitle above the graph to the top-five rows below the card (the card has no sort
# button since issue #324). The graph's own UIA rectangle is the union of its drawn children, so it can read 8 epx short
# while a redraw is being laid out.
SPAN = "id=fst.history.subtitle|raw=fst.history.rows|card"
# The rows rise FadeInTiming.OffsetY (12 epx) while they fade in, so a check inside the fade allows that much; every
# check after the fade (and every check with motion off) holds the card within 1 epx.
FADING = f"{SPAN}~12"


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
            if page["name"] == "history-swap-keyboard":
                self.assertEqual(seen, [], "keyboard focus checks must run where the card is taller than the window")
                continue
            self.assertEqual(seen[0], f"markspan:{SPAN}", page["name"])
            self.assertTrue(all(step in (f"assertspan:{SPAN}", f"assertspan:{FADING}") for step in seen[1:]), page["name"])
            self.assertGreater(len(seen), 1, page["name"])

    def test_settled_checks_stay_strict(self):
        # Only a check inside the fade may allow the rows' rise; after a wait (or with motion off) it is 1 epx.
        for page in PAGES + LIVE:
            run = steps(page)
            for index, step in enumerate(run):
                if step == f"assertspan:{FADING}":
                    self.assertFalse(run[index - 1].startswith("wait:"), page["name"])
                    self.assertNotEqual(page["name"], "history-swap-instant")
            self.assertTrue(any(step == f"assertspan:{SPAN}" for step in run) or page["name"] == "history-swap-keyboard",
                            page["name"])

    def test_span_tolerance_parses_only_on_assertspan(self):
        self.assertEqual(uiwin.parse_step(f"assertspan:{FADING}")["tolerance"], 12.0)
        self.assertNotIn("tolerance", uiwin.parse_step(f"assertspan:{SPAN}"))
        for bad in (f"markspan:{FADING}", f"assertspan:{SPAN}~0.5", f"assertspan:{SPAN}~x"):
            with self.assertRaises(ValueError):
                uiwin.parse_step(bad)

    def test_detail_page_skips_compact_large_text(self):
        # With a bar's detail row at compact and large text, the subtitle and the rows below the card never share the screen.
        detail = next(p for p in PAGES if p["name"] == "history-swap-detail")
        self.assertEqual(a11y_matrix.page_sizes(detail, ["compact", "medium", "wide"], "text-200"), ["medium", "wide"])
        self.assertEqual(a11y_matrix.page_sizes(detail, ["compact", "medium", "wide"], "hc-desert"),
                         ["compact", "medium", "wide"])

    def test_detail_page_keeps_the_span_after_the_row_closes(self):
        # Issue #261 review: a switch closes the selected bar's row but its slot keeps the card's height, after the fade,
        # after rapid switching and with motion off (no skip_modes), and a new pick fills the slot without a jump.
        detail = next(p for p in PAGES if p["name"] == "history-swap-detail")
        self.assertNotIn("skip_modes", detail)
        run = steps(detail)
        gone = run.index("waitgone:id=fst.history.detail@3")
        self.assertEqual(run[gone + 1], f"assertspan:{SPAN}")
        rapid = run.index("toggle:id=fst.history.instrument.Solo_Drums")
        self.assertEqual(run[rapid + 1:rapid + 4], ["toggle:id=fst.history.instrument.Solo_Guitar",
                                                    "toggle:id=fst.history.instrument.Solo_Bass", f"assertspan:{FADING}"])
        self.assertIn(f"assertspan:{SPAN}", run[run.index("wait:0.8", rapid):])
        self.assertEqual(run[-1], f"assertspan:{SPAN}")
        self.assertEqual(run[-2], "waitfor:id=fst.history.detail@5")

    def test_chart_names_ignore_the_visible_page(self):
        # Large text pages the chart to fewer bars, so the name's "N of 2 scores from …" range varies by size.
        for page in PAGES:
            for step in steps(page):
                if step.startswith("assertname:id=fst.history.chart"):
                    self.assertTrue(step.endswith("|Bass score history, * of 2 scores *"), step)

    def test_keyboard_span_page_skips_modes_where_the_card_overflows(self):
        # Focusing the selector scrolls it into view; when the card is taller than the window the rows (the span's
        # bottom anchor) then leave the screen, and UIA reports an off-screen rectangle as empty.
        plain, spanned = (next(p for p in PAGES if p["name"] == name)
                          for name in ("history-swap-keyboard", "history-swap-keyboard-span"))
        self.assertIn("text-200", spanned["skip_modes"])
        self.assertIn("hc-desert", spanned["skip_modes"])
        self.assertNotIn("skip_modes", plain)
        self.assertEqual([s for s in steps(spanned) if "span:" not in s and "fst.history.rows" not in s],
                         [s for s in steps(plain) if "fst.history.rows" not in s])

    def test_rapid_switching_ends_on_the_last_pick(self):
        page = next(page for page in PAGES if page["name"] == "history-swap")
        run = steps(page)
        rapid = run.index("toggle:id=fst.history.instrument.Solo_Bass", run.index("tree:{stem}-drums.txt"))
        self.assertIn("assertstate:id=fst.history.instrument.Solo_Bass|toggle=on", run[rapid:])
        self.assertTrue(any(step.startswith("assertname:id=fst.history.chart|Bass ") for step in run[rapid:]))

    def test_posted_keys_switch_within_one_fade(self):
        page = next(page for page in PAGES if page["name"] == "history-swap-keyboard-span")
        run = steps(page)
        burst = run.index("keys:left space left space right space")
        self.assertEqual(run[burst + 1], f"assertspan:{FADING}")
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
            self.assertEqual(page["route"], "/songs/fixture-pulse", page["name"])

    def test_pages_open_song_detail_not_the_history_page(self):
        # Issue #324: /songs/:id/:instrument/history opens the separate Player History page, which has no chart or
        # instrument selector; the swap pages drive Song Detail's card, which has no sort button.
        for page in PAGES + LIVE:
            self.assertFalse(page["route"].endswith("/history"), page["name"])
            self.assertNotIn("sort.open", " ".join(steps(page)), page["name"])


if __name__ == "__main__":
    unittest.main()
